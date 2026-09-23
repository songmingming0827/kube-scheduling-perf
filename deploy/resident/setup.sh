#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_DIR="${BUNDLE_DIR}/grafana-ingress"

# shellcheck source=versions.env
source "${BUNDLE_DIR}/versions.env"

run_step() {
  local label="$1"
  shift
  printf '\n==> %s\n' "${label}"
  "$@"
}

if ! command -v kind >/dev/null 2>&1; then
  echo "Required command is unavailable: kind" >&2
  exit 1
fi

if kind get clusters | grep -Fxq -- "${CLUSTER_NAME}"; then
  echo "Refusing to overwrite existing Kind cluster: ${CLUSTER_NAME}" >&2
  exit 1
fi

run_step "Check host prerequisites" \
  bash "${BUNDLE_DIR}/scripts/check-prerequisites.sh"

if [[ ! -x "${INGRESS_DIR}/install.sh" ]]; then
  echo "Missing staged Grafana Ingress installer: ${INGRESS_DIR}/install.sh" >&2
  exit 1
fi

run_step "Install the pinned kubectl" \
  "${BUNDLE_DIR}/scripts/install-tooling.sh"
run_step "Download and verify scheduler artifacts" \
  "${BUNDLE_DIR}/scripts/prepare-scheduler-artifacts.sh"
run_step "Download and verify monitoring artifacts" \
  "${BUNDLE_DIR}/scripts/prepare-monitoring-artifacts.sh"
run_step "Create the resident Kind control plane" \
  "${BUNDLE_DIR}/scripts/create-canary-cluster.sh"
run_step "Install KWOK and create canary nodes" \
  "${BUNDLE_DIR}/scripts/install-kwok-canary.sh"
run_step "Verify the 100-node canary baseline" \
  "${BUNDLE_DIR}/scripts/verify-base.sh" "${CANARY_KWOK_NODES}"
run_step "Install the scheduler stacks" \
  "${BUNDLE_DIR}/scripts/install-schedulers.sh"
run_step "Verify the scheduler stacks" \
  "${BUNDLE_DIR}/scripts/verify-schedulers.sh"
run_step "Run scheduler smoke tests" \
  "${BUNDLE_DIR}/scripts/run-scheduler-smoke-tests.sh"
run_step "Install monitoring and Audit Exporter" \
  "${BUNDLE_DIR}/scripts/install-monitoring.sh"
run_step "Verify monitoring" \
  "${BUNDLE_DIR}/scripts/verify-monitoring.sh"
run_step "Install the persistent Grafana Ingress" \
  "${INGRESS_DIR}/install.sh"
run_step "Scale KWOK to the formal node baseline" \
  "${BUNDLE_DIR}/scripts/scale-kwok-nodes.sh" "${FORMAL_KWOK_NODES}"
run_step "Verify the formal cluster baseline" \
  "${BUNDLE_DIR}/scripts/verify-base.sh" "${FORMAL_KWOK_NODES}"
run_step "Verify schedulers after node scale-up" \
  "${BUNDLE_DIR}/scripts/verify-schedulers.sh"
run_step "Verify monitoring after node scale-up" \
  "${BUNDLE_DIR}/scripts/verify-monitoring.sh"
run_step "Verify the persistent Grafana Ingress" \
  "${INGRESS_DIR}/verify.sh"

printf '\nresident_cluster=%s\n' "${CLUSTER_NAME}"
printf 'ready_nodes=%s/%s\n' "$((FORMAL_KWOK_NODES + 1))" "$((FORMAL_KWOK_NODES + 1))"
printf 'kubeconfig=%s/kubeconfig\n' "${BUNDLE_DIR}"
printf 'status=ready\n'
