#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"
CONTROLLER_MANAGER_MANIFEST="/etc/kubernetes/manifests/kube-controller-manager.yaml"
SCHEDULER_MANIFEST="/etc/kubernetes/manifests/kube-scheduler.yaml"

docker inspect "${CONTROL_PLANE}" >/dev/null

ensure_arg() {
  local manifest="$1"
  local command="$2"
  local prefix="$3"
  local desired="$4"
  local current

  current="$(docker exec "${CONTROL_PLANE}" grep -E -- "^    - ${prefix}" "${manifest}" || true)"
  if [[ "${current}" == "    - ${desired}" ]]; then
    return
  fi
  if [[ -n "${current}" ]]; then
    docker exec "${CONTROL_PLANE}" sed -i \
      "s|^    - ${prefix}.*$|    - ${desired}|" "${manifest}"
  else
    docker exec "${CONTROL_PLANE}" sed -i \
      "/^    - ${command}$/a\\    - ${desired}" "${manifest}"
  fi
}

ensure_cpu_baseline() {
  local manifest="$1"
  local original_request="$2"

  if docker exec "${CONTROL_PLANE}" grep -q '^        cpu: 500m$' "${manifest}" &&
     docker exec "${CONTROL_PLANE}" grep -q '^      limits:$' "${manifest}" &&
     docker exec "${CONTROL_PLANE}" grep -q '^        cpu: 8$' "${manifest}"; then
    return
  fi
  if docker exec "${CONTROL_PLANE}" grep -q '^        cpu: 1$' "${manifest}" &&
     docker exec "${CONTROL_PLANE}" grep -q '^      limits:$' "${manifest}" &&
     docker exec "${CONTROL_PLANE}" grep -q '^        cpu: 8$' "${manifest}"; then
    docker exec "${CONTROL_PLANE}" sed -i \
      's/^        cpu: 1$/        cpu: 500m/' "${manifest}"
    return
  fi
  if ! docker exec "${CONTROL_PLANE}" grep -q "^        cpu: ${original_request}$" "${manifest}"; then
    echo "Unexpected CPU resources in ${manifest}" >&2
    return 1
  fi
  docker exec "${CONTROL_PLANE}" sed -i \
    "s/^        cpu: ${original_request}$/        cpu: 500m\\n      limits:\\n        cpu: 8/" \
    "${manifest}"
}

controller_manager_uid="$("${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
  get pod -n kube-system -l component=kube-controller-manager \
  -o jsonpath='{.items[0].metadata.uid}')"
scheduler_uid="$("${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
  get pod -n kube-system -l component=kube-scheduler \
  -o jsonpath='{.items[0].metadata.uid}')"
controller_manager_sha="$(docker exec "${CONTROL_PLANE}" sha256sum \
  "${CONTROLLER_MANAGER_MANIFEST}" | awk '{print $1}')"
scheduler_sha="$(docker exec "${CONTROL_PLANE}" sha256sum \
  "${SCHEDULER_MANIFEST}" | awk '{print $1}')"

ensure_arg "${CONTROLLER_MANAGER_MANIFEST}" kube-controller-manager \
  '--concurrent-job-syncs=' '--concurrent-job-syncs=100'
ensure_arg "${CONTROLLER_MANAGER_MANIFEST}" kube-controller-manager \
  '--kube-api-qps=' '--kube-api-qps=1000'
ensure_arg "${CONTROLLER_MANAGER_MANIFEST}" kube-controller-manager \
  '--kube-api-burst=' '--kube-api-burst=1000'
ensure_arg "${SCHEDULER_MANIFEST}" kube-scheduler \
  '--kube-api-qps=' '--kube-api-qps=1000'
ensure_arg "${SCHEDULER_MANIFEST}" kube-scheduler \
  '--kube-api-burst=' '--kube-api-burst=1000'
ensure_cpu_baseline "${CONTROLLER_MANAGER_MANIFEST}" 200m
ensure_cpu_baseline "${SCHEDULER_MANIFEST}" 100m

new_controller_manager_sha="$(docker exec "${CONTROL_PLANE}" sha256sum \
  "${CONTROLLER_MANAGER_MANIFEST}" | awk '{print $1}')"
new_scheduler_sha="$(docker exec "${CONTROL_PLANE}" sha256sum \
  "${SCHEDULER_MANIFEST}" | awk '{print $1}')"

wait_for_static_pod() {
  local component="$1"
  local old_uid="$2"
  local current_uid
  local ready

  for _ in $(seq 1 180); do
    current_uid="$("${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
      get pod -n kube-system -l component="${component}" \
      -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null || true)"
    ready="$("${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
      get pod -n kube-system -l component="${component}" \
      -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)"
    if [[ -n "${current_uid}" && "${current_uid}" != "${old_uid}" && "${ready}" == "true" ]]; then
      return
    fi
    sleep 1
  done
  echo "Timed out waiting for ${component} static Pod replacement" >&2
  return 1
}

if [[ "${new_controller_manager_sha}" != "${controller_manager_sha}" ]]; then
  wait_for_static_pod kube-controller-manager "${controller_manager_uid}"
fi
if [[ "${new_scheduler_sha}" != "${scheduler_sha}" ]]; then
  wait_for_static_pod kube-scheduler "${scheduler_uid}"
fi

printf 'controller_manager_client=1000/1000 job_syncs=100 cpu=500m/8\n'
printf 'default_scheduler_client=1000/1000 cpu=500m/8\n'
