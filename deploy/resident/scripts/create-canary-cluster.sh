#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "${SCRIPT_DIR}")"

# shellcheck source=/dev/null
source "${BUNDLE_DIR}/versions.env"

KUBECONFIG_PATH="${BUNDLE_DIR}/kubeconfig"
AUDIT_POLICY="${BUNDLE_DIR}/manifests/audit-policy.yaml"
KUBECTL="${BUNDLE_DIR}/bin/kubectl"

if [[ ! -x "${KUBECTL}" ]]; then
  echo "Run scripts/install-tooling.sh first" >&2
  exit 1
fi

if kind get clusters | grep -Fxq -- "${CLUSTER_NAME}"; then
  echo "Refusing to overwrite existing Kind cluster: ${CLUSTER_NAME}" >&2
  exit 1
fi

if [[ ! -f "${AUDIT_POLICY}" ]]; then
  echo "Missing audit policy: ${AUDIT_POLICY}" >&2
  exit 1
fi

mkdir -p "${BUNDLE_DIR}/logs"

(
  cd "${BUNDLE_DIR}"
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --image "${KIND_NODE_IMAGE}" \
    --config kind-config.yaml \
    --kubeconfig "${KUBECONFIG_PATH}"
)

"${BUNDLE_DIR}/scripts/configure-control-plane-baseline.sh"

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
  taint node "${CLUSTER_NAME}-control-plane" \
  node-role.kubernetes.io/control-plane:NoSchedule- >/dev/null 2>&1 || true

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" wait \
  --for=condition=Ready "node/${CLUSTER_NAME}-control-plane" \
  --timeout=180s

server_version="$("${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" version -o json | jq -r '.serverVersion.gitVersion')"
if [[ "${server_version}" != "${KUBERNETES_VERSION}" ]]; then
  echo "Unexpected Kubernetes server version: ${server_version}" >&2
  exit 1
fi

echo "cluster=${CLUSTER_NAME}"
echo "server_version=${server_version}"
echo "kubeconfig=${KUBECONFIG_PATH}"
