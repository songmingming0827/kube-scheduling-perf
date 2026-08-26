#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"
MANIFEST="${DEPLOY_DIR}/manifests/scheduler-smoke-tests.yaml"

kc() {
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
}

cleanup() {
  kc delete -f "${MANIFEST}" --ignore-not-found --timeout=2m >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_pod_scheduled() {
  local namespace="$1"
  local target="$2"
  local pod_name=""

  for _ in $(seq 1 60); do
    pod_name="$(kc get pod -n "${namespace}" \
      --selector="benchmark.scheduling/smoke=${target}" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "${pod_name}" ]]; then
      kc wait pod -n "${namespace}" "${pod_name}" \
        --for=condition=PodScheduled --timeout=3m
      return
    fi
    sleep 1
  done

  printf 'No smoke-test Pod appeared for %s\n' "${target}" >&2
  return 1
}

cleanup
kc apply -f "${MANIFEST}"

for target in volcano agent kueue yunikorn; do
  namespace="bench-${target}"
  if [[ "${target}" == agent ]]; then
    namespace="bench-volcano"
  fi
  wait_for_pod_scheduled "${namespace}" "${target}"
  printf '%s_scheduled=true\n' "${target}"
done

kc wait workload -n bench-kueue --all --for=condition=Admitted --timeout=2m
printf 'kueue_admitted=true\n'
