#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"

for configuration in \
  mutatingwebhookconfiguration/kueue-mutating-webhook-configuration \
  validatingwebhookconfiguration/kueue-validating-webhook-configuration; do
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" get "${configuration}" -o json |
    jq '
      .webhooks |= map(
        .namespaceSelector.matchExpressions =
          ((.namespaceSelector.matchExpressions // []) |
           map(select(.key != "benchmark.scheduling/base")) +
           [{"key":"benchmark.scheduling/base","operator":"In","values":["kueue"]}])
      )
    ' |
    "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" apply -f - >/dev/null
done

printf 'kueue_webhooks_scoped=true\n'
