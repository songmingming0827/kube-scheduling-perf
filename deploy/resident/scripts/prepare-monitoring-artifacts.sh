#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

DOWNLOAD_DIR="${DEPLOY_DIR}/downloads"
CHART="${DOWNLOAD_DIR}/kube-prometheus-stack-${KUBE_PROMETHEUS_STACK_VERSION}.tgz"
mkdir -p "${DOWNLOAD_DIR}"

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null

if [[ ! -f "${CHART}" ]]; then
  helm pull prometheus-community/kube-prometheus-stack \
    --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
    --destination "${DOWNLOAD_DIR}"
fi

echo "${KUBE_PROMETHEUS_STACK_SHA256}  ${CHART}" | sha256sum --check --status
sha256sum "${CHART}"
