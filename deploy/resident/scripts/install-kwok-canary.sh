#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "${SCRIPT_DIR}")"

# shellcheck source=/dev/null
source "${BUNDLE_DIR}/versions.env"

export KUBECONFIG="${BUNDLE_DIR}/kubeconfig"
KUBECTL="${BUNDLE_DIR}/bin/kubectl"

if [[ ! -x "${KUBECTL}" ]]; then
  echo "Run scripts/install-tooling.sh first" >&2
  exit 1
fi

"${KUBECTL}" apply -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/kwok.yaml"
"${KUBECTL}" apply -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/stage-fast.yaml"
"${KUBECTL}" apply -f "${BUNDLE_DIR}/manifests/kwok-configuration.yaml"
"${KUBECTL}" rollout restart -n kube-system deployment/kwok-controller
"${KUBECTL}" wait -n kube-system deployment/kwok-controller \
  --for=condition=Available --timeout=180s

# Kind's network DaemonSets tolerate every taint. Exclude virtual nodes so a
# 1000-node baseline does not create 10000 unrelated system Pods.
for daemonset in kindnet kube-proxy; do
  "${KUBECTL}" patch daemonset "${daemonset}" -n kube-system --type=merge -p '
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: type
                operator: NotIn
                values:
                - kwok
' >/dev/null
done

for ((i = 0; i < CANARY_KWOK_NODES; i++)); do
  "${KUBECTL}" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Node
metadata:
  name: kwok-node-${i}
  annotations:
    kwok.x-k8s.io/node: fake
    node.alpha.kubernetes.io/ttl: "0"
  labels:
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: kwok-node-${i}
    kubernetes.io/os: linux
    node-role.kubernetes.io/agent: ""
    type: kwok
spec:
  taints:
  - effect: NoSchedule
    key: kwok.x-k8s.io/node
    value: fake
status:
  allocatable:
    cpu: "16"
    memory: 64Gi
    pods: "110"
  capacity:
    cpu: "16"
    memory: 64Gi
    pods: "110"
  conditions:
  - lastHeartbeatTime: "2026-01-01T00:00:00Z"
    lastTransitionTime: "2026-01-01T00:00:00Z"
    message: kubelet is posting ready status
    reason: KubeletReady
    status: "True"
    type: Ready
  phase: Running
EOF
done

expected_nodes=$((CANARY_KWOK_NODES + 1))
for _ in $(seq 1 60); do
  ready_nodes="$("${KUBECTL}" get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"
  if [[ "${ready_nodes}" -eq "${expected_nodes}" ]]; then
    break
  fi
  sleep 2
done

ready_nodes="$("${KUBECTL}" get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"
if [[ "${ready_nodes}" -ne "${expected_nodes}" ]]; then
  echo "Expected ${expected_nodes} Ready nodes, found ${ready_nodes}" >&2
  exit 1
fi

echo "kwok_version=${KWOK_VERSION}"
echo "ready_nodes=${ready_nodes}/${expected_nodes}"
