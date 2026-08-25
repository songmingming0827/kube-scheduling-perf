#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
  get mutatingwebhookconfiguration yunikorn-admission-controller-mutations -o json |
  jq '
    .webhooks |= map(
      .namespaceSelector.matchExpressions =
        ((.namespaceSelector.matchExpressions // []) |
         map(select(.key != "benchmark.scheduling/base")) +
         [{"key":"benchmark.scheduling/base","operator":"In","values":["yunikorn"]}])
    )
  ' |
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" apply -f - >/dev/null

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" \
  get validatingwebhookconfiguration yunikorn-admission-controller-validations -o json |
  jq '
    .webhooks |= map(
      .namespaceSelector.matchExpressions =
        ((.namespaceSelector.matchExpressions // []) |
         map(select(.key != "kubernetes.io/metadata.name")) +
         [{"key":"kubernetes.io/metadata.name","operator":"In","values":["yunikorn"]}])
    )
  ' |
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" apply -f - >/dev/null

printf 'yunikorn_webhooks_scoped=true\n'
