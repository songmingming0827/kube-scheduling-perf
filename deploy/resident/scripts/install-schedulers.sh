#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"
DOWNLOAD_DIR="${DEPLOY_DIR}/downloads"
SCHEDULER_PLUGINS_DIR="${DOWNLOAD_DIR}/scheduler-plugins-${SCHEDULER_PLUGINS_VERSION#v}"

patch_cpu_baseline() {
  local namespace="$1"
  local deployment="$2"
  local container="$3"
  local container_index
  local patch

  container_index="$("${KUBECTL}" get deployment "${deployment}" --namespace "${namespace}" -o json | \
    jq --arg container "${container}" -r '.spec.template.spec.containers | map(.name) | index($container)')"
  if [[ "${container_index}" == "null" ]]; then
    echo "Container ${namespace}/${deployment}:${container} not found" >&2
    return 1
  fi
  patch="$(jq -cn \
    --arg path "/spec/template/spec/containers/${container_index}/resources" \
    '[{"op":"add","path":$path,"value":{"requests":{"cpu":"500m"},"limits":{"cpu":"8"}}}]')"
  "${KUBECTL}" patch deployment "${deployment}" --namespace "${namespace}" \
    --type json --patch "${patch}"
}

replace_container_args() {
  local namespace="$1"
  local deployment="$2"
  local container="$3"
  local args_json="$4"
  local container_index
  local patch

  container_index="$("${KUBECTL}" get deployment "${deployment}" --namespace "${namespace}" -o json | \
    jq --arg container "${container}" -r '.spec.template.spec.containers | map(.name) | index($container)')"
  if [[ "${container_index}" == "null" ]]; then
    echo "Container ${namespace}/${deployment}:${container} not found" >&2
    return 1
  fi
  patch="$(jq -cn \
    --arg path "/spec/template/spec/containers/${container_index}/args" \
    --argjson value "${args_json}" \
    '[{"op":"add","path":$path,"value":$value}]')"
  "${KUBECTL}" patch deployment "${deployment}" --namespace "${namespace}" \
    --type json --patch "${patch}"
}

patch_volcano_admission_args() {
  local args_json

  args_json="$("${KUBECTL}" get deployment volcano-admission --namespace volcano-system -o json | \
    jq -c '.spec.template.spec.containers[] | select(.name == "admission") | (.args // []) |
      map(select((startswith("--kube-api-qps=") or startswith("--kube-api-burst=")) | not)) +
      ["--kube-api-qps=1000", "--kube-api-burst=1000"]')"
  replace_container_args volcano-system volcano-admission admission "${args_json}"
}

patch_yunikorn_baseline() {
  local deployment="$1"
  local container="$2"
  local container_index
  local patch

  container_index="$("${KUBECTL}" get deployment "${deployment}" --namespace yunikorn -o json | \
    jq --arg container "${container}" -r '.spec.template.spec.containers | map(.name) | index($container)')"
  if [[ "${container_index}" == "null" ]]; then
    echo "Container yunikorn/${deployment}:${container} not found" >&2
    return 1
  fi
  patch="$(jq -cn \
    --arg resource_path "/spec/template/spec/containers/${container_index}/resources" \
    --arg env_path "/spec/template/spec/containers/${container_index}/env" \
    '[
      {"op":"add","path":$resource_path,"value":{"requests":{"cpu":"500m"},"limits":{"cpu":"8"}}},
      {"op":"add","path":$env_path,"value":[{"name":"NAMESPACE","valueFrom":{"fieldRef":{"fieldPath":"metadata.namespace"}}}]}
    ]')"
  "${KUBECTL}" patch deployment "${deployment}" --namespace yunikorn \
    --type json --patch "${patch}"
}

"${DEPLOY_DIR}/scripts/prepare-scheduler-artifacts.sh"

export KUBECONFIG="${KUBECONFIG_PATH}"
"${KUBECTL}" apply -f "${DEPLOY_DIR}/manifests/benchmark-namespaces.yaml"

helm upgrade --install volcano "${DOWNLOAD_DIR}/volcano-${VOLCANO_VERSION#v}.tgz" \
  --kubeconfig "${KUBECONFIG_PATH}" \
  --namespace volcano-system \
  --create-namespace \
  --values "${DEPLOY_DIR}/values/volcano.yaml" \
  --wait --timeout 10m
patch_cpu_baseline volcano-system volcano-scheduler volcano-scheduler
patch_cpu_baseline volcano-system volcano-agent-scheduler volcano-agent-scheduler
patch_cpu_baseline volcano-system volcano-controllers volcano-controllers
patch_cpu_baseline volcano-system volcano-admission admission
patch_volcano_admission_args
"${KUBECTL}" rollout status deployment/volcano-scheduler --namespace volcano-system --timeout=10m
"${KUBECTL}" rollout status deployment/volcano-agent-scheduler --namespace volcano-system --timeout=10m
"${KUBECTL}" rollout status deployment/volcano-controllers --namespace volcano-system --timeout=10m
"${KUBECTL}" rollout status deployment/volcano-admission --namespace volcano-system --timeout=10m

"${KUBECTL}" apply --server-side --force-conflicts \
  -f "${DOWNLOAD_DIR}/kueue-${KUEUE_VERSION}.yaml"
"${KUBECTL}" apply -f "${DEPLOY_DIR}/manifests/kueue-manager-config.yaml"
patch_cpu_baseline kueue-system kueue-controller-manager manager
"${KUBECTL}" rollout restart deployment/kueue-controller-manager --namespace kueue-system
"${KUBECTL}" rollout status deployment/kueue-controller-manager \
  --namespace kueue-system --timeout=10m
"${DEPLOY_DIR}/scripts/scope-kueue-webhooks.sh"

"${KUBECTL}" apply --server-side \
  -f "${SCHEDULER_PLUGINS_DIR}/manifests/coscheduling/crd.yaml"
"${KUBECTL}" apply --server-side \
  -f "${SCHEDULER_PLUGINS_DIR}/config/crd/bases/scheduling.x-k8s.io_elasticquotas.yaml"
helm upgrade --install coscheduling \
  "${SCHEDULER_PLUGINS_DIR}/manifests/install/charts/as-a-second-scheduler" \
  --kubeconfig "${KUBECONFIG_PATH}" \
  --namespace coscheduling \
  --create-namespace \
  --skip-crds \
  --values "${DEPLOY_DIR}/values/coscheduling.yaml" \
  --wait --timeout 10m
"${KUBECTL}" apply -f "${DEPLOY_DIR}/manifests/coscheduling-configmap.yaml"
replace_container_args coscheduling scheduler-plugins-controller scheduler-plugins-controller \
  '["--qps=1000","--burst=1000","--workers=100"]'
"${KUBECTL}" rollout restart deployment/coscheduling --namespace coscheduling
"${KUBECTL}" rollout status deployment/coscheduling --namespace coscheduling --timeout=10m
"${KUBECTL}" rollout status deployment/scheduler-plugins-controller \
  --namespace coscheduling --timeout=10m

helm upgrade --install yunikorn "${DOWNLOAD_DIR}/yunikorn-${YUNIKORN_VERSION#v}.tgz" \
  --kubeconfig "${KUBECONFIG_PATH}" \
  --namespace yunikorn \
  --create-namespace \
  --values "${DEPLOY_DIR}/values/yunikorn.yaml" \
  --wait --timeout 10m
patch_yunikorn_baseline yunikorn-scheduler yunikorn-scheduler-k8s
patch_yunikorn_baseline yunikorn-admission-controller yunikorn-admission-controller
"${DEPLOY_DIR}/scripts/scope-yunikorn-webhooks.sh"
"${KUBECTL}" rollout status deployment/yunikorn-scheduler --namespace yunikorn --timeout=10m
"${KUBECTL}" rollout status deployment/yunikorn-admission-controller \
  --namespace yunikorn --timeout=10m
