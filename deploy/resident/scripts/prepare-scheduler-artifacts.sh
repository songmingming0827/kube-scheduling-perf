#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

DOWNLOAD_DIR="${DEPLOY_DIR}/downloads"
KUEUE_MANIFEST="${DOWNLOAD_DIR}/kueue-${KUEUE_VERSION}.yaml"
SCHEDULER_PLUGINS_ARCHIVE="${DOWNLOAD_DIR}/scheduler-plugins-${SCHEDULER_PLUGINS_VERSION}.tar.gz"
SCHEDULER_PLUGINS_DIR="${DOWNLOAD_DIR}/scheduler-plugins-${SCHEDULER_PLUGINS_VERSION#v}"

mkdir -p "${DOWNLOAD_DIR}"

if [[ ! -f "${KUEUE_MANIFEST}" ]]; then
  curl -fL --retry 3 \
    "https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml" \
    -o "${KUEUE_MANIFEST}"
fi
echo "${KUEUE_MANIFEST_SHA256}  ${KUEUE_MANIFEST}" | sha256sum --check --status

if [[ ! -f "${SCHEDULER_PLUGINS_ARCHIVE}" ]]; then
  curl -fL --retry 3 \
    "https://github.com/kubernetes-sigs/scheduler-plugins/archive/refs/tags/${SCHEDULER_PLUGINS_VERSION}.tar.gz" \
    -o "${SCHEDULER_PLUGINS_ARCHIVE}"
fi
echo "${SCHEDULER_PLUGINS_SOURCE_SHA256}  ${SCHEDULER_PLUGINS_ARCHIVE}" | sha256sum --check --status

if [[ ! -d "${SCHEDULER_PLUGINS_DIR}" ]]; then
  tar -xzf "${SCHEDULER_PLUGINS_ARCHIVE}" -C "${DOWNLOAD_DIR}"
fi

helm repo add volcano-sh https://volcano-sh.github.io/helm-charts --force-update >/dev/null
helm repo add yunikorn https://apache.github.io/yunikorn-release --force-update >/dev/null
helm repo update >/dev/null

if [[ ! -f "${DOWNLOAD_DIR}/volcano-${VOLCANO_VERSION#v}.tgz" ]]; then
  helm pull volcano-sh/volcano --version "${VOLCANO_VERSION#v}" --destination "${DOWNLOAD_DIR}"
fi
if [[ ! -f "${DOWNLOAD_DIR}/yunikorn-${YUNIKORN_VERSION#v}.tgz" ]]; then
  helm pull yunikorn/yunikorn --version "${YUNIKORN_VERSION#v}" --destination "${DOWNLOAD_DIR}"
fi

sha256sum \
  "${KUEUE_MANIFEST}" \
  "${SCHEDULER_PLUGINS_ARCHIVE}" \
  "${DOWNLOAD_DIR}/volcano-${VOLCANO_VERSION#v}.tgz" \
  "${DOWNLOAD_DIR}/yunikorn-${YUNIKORN_VERSION#v}.tgz"
