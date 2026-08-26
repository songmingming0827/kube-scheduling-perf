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

client_version="$("${KUBECTL}" version --client -o json | jq -r '.clientVersion.gitVersion')"
server_version="$("${KUBECTL}" version -o json | jq -r '.serverVersion.gitVersion')"
total_nodes="$("${KUBECTL}" get nodes --no-headers | wc -l | tr -d ' ')"
ready_nodes="$("${KUBECTL}" get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"
kwok_image="$("${KUBECTL}" -n kube-system get deployment kwok-controller -o jsonpath='{.spec.template.spec.containers[0].image}')"
audit_log="${BUNDLE_DIR}/logs/kube-apiserver-audit.log"
expected_kwok_nodes="${1:-${CANARY_KWOK_NODES}}"
controller_manager_json="$("${KUBECTL}" -n kube-system get pod -l component=kube-controller-manager -o json)"
scheduler_json="$("${KUBECTL}" -n kube-system get pod -l component=kube-scheduler -o json)"

[[ "${server_version}" == "${KUBERNETES_VERSION}" ]]
[[ "${client_version}" == "${KUBECTL_VERSION}" ]]
[[ "${total_nodes}" -eq $((expected_kwok_nodes + 1)) ]]
[[ "${ready_nodes}" -eq "${total_nodes}" ]]
[[ "${kwok_image}" == "registry.k8s.io/kwok/kwok:${KWOK_VERSION}" ]]
[[ -s "${audit_log}" ]]
jq -e '
  .items | length == 1 and
  .[0].status.phase == "Running" and
  (.[0].spec.containers[0].command | index("--concurrent-job-syncs=100")) != null and
  (.[0].spec.containers[0].command | index("--kube-api-qps=1000")) != null and
  (.[0].spec.containers[0].command | index("--kube-api-burst=1000")) != null and
  .[0].spec.containers[0].resources.requests.cpu == "500m" and
  .[0].spec.containers[0].resources.limits.cpu == "8"
' <<<"${controller_manager_json}" >/dev/null
jq -e '
  .items | length == 1 and
  .[0].status.phase == "Running" and
  (.[0].spec.containers[0].command | index("--kube-api-qps=1000")) != null and
  (.[0].spec.containers[0].command | index("--kube-api-burst=1000")) != null and
  .[0].spec.containers[0].resources.requests.cpu == "500m" and
  .[0].spec.containers[0].resources.limits.cpu == "8"
' <<<"${scheduler_json}" >/dev/null

echo "cluster=${CLUSTER_NAME}"
echo "client_version=${client_version}"
echo "server_version=${server_version}"
echo "nodes=${ready_nodes}/${total_nodes}_Ready"
echo "kwok_image=${kwok_image}"
echo "audit_log=writing"
echo "controller_manager_client=1000/1000 job_syncs=100 cpu=500m/8"
echo "default_scheduler_client=1000/1000 cpu=500m/8"
