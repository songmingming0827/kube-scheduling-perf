#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"
TARGET_NODES="${1:-${FORMAL_KWOK_NODES}}"

kc() {
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
}

if ! [[ "${TARGET_NODES}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Target node count must be a positive integer\n' >&2
  exit 1
fi

declare -A existing_nodes=()
while IFS= read -r node_name; do
  existing_nodes["${node_name}"]=1
done < <(kc get nodes -l type=kwok -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

generate_missing_nodes() {
  local i
  for ((i = 0; i < TARGET_NODES; i++)); do
    if [[ -n "${existing_nodes[kwok-node-${i}]:-}" ]]; then
      continue
    fi
    printf '%s\n' "---"
    printf '%s\n' \
      "apiVersion: v1" \
      "kind: Node" \
      "metadata:" \
      "  name: kwok-node-${i}" \
      "  annotations:" \
      "    kwok.x-k8s.io/node: fake" \
      "    node.alpha.kubernetes.io/ttl: \"0\"" \
      "  labels:" \
      "    kubernetes.io/arch: amd64" \
      "    kubernetes.io/hostname: kwok-node-${i}" \
      "    kubernetes.io/os: linux" \
      "    node-role.kubernetes.io/agent: \"\"" \
      "    type: kwok" \
      "spec:" \
      "  taints:" \
      "  - effect: NoSchedule" \
      "    key: kwok.x-k8s.io/node" \
      "    value: fake" \
      "status:" \
      "  allocatable:" \
      "    cpu: \"16\"" \
      "    memory: 64Gi" \
      "    pods: \"110\"" \
      "  capacity:" \
      "    cpu: \"16\"" \
      "    memory: 64Gi" \
      "    pods: \"110\"" \
      "  conditions:" \
      "  - lastHeartbeatTime: \"2026-01-01T00:00:00Z\"" \
      "    lastTransitionTime: \"2026-01-01T00:00:00Z\"" \
      "    message: kubelet is posting ready status" \
      "    reason: KubeletReady" \
      "    status: \"True\"" \
      "    type: Ready" \
      "  phase: Running"
  done
}

missing_count=$((TARGET_NODES - ${#existing_nodes[@]}))
if ((missing_count > 0)); then
  printf 'creating_kwok_nodes=%s\n' "${missing_count}"
  generate_missing_nodes | kc create -f - >/dev/null
fi

expected_nodes=$((TARGET_NODES + 1))
for _ in $(seq 1 180); do
  ready_nodes="$(kc get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"
  if [[ "${ready_nodes}" -eq "${expected_nodes}" ]]; then
    break
  fi
  sleep 2
done

ready_nodes="$(kc get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"
if [[ "${ready_nodes}" -ne "${expected_nodes}" ]]; then
  printf 'Expected %s Ready nodes, found %s\n' "${expected_nodes}" "${ready_nodes}" >&2
  exit 1
fi

system_pods_on_kwok="$(kc get pods -n kube-system -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | awk '$0 ~ /^kwok-node-/ {count++} END {print count+0}')"
if [[ "${system_pods_on_kwok}" -ne 0 ]]; then
  printf 'Unexpected kube-system Pods on KWOK nodes: %s\n' "${system_pods_on_kwok}" >&2
  exit 1
fi

printf 'ready_nodes=%s/%s\n' "${ready_nodes}" "${expected_nodes}"
printf 'system_pods_on_kwok_nodes=0\n'
