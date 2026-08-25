#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "${SCRIPT_DIR}")"

# shellcheck source=/dev/null
source "${BUNDLE_DIR}/versions.env"

BIN_DIR="${BUNDLE_DIR}/bin"
KUBECTL="${BIN_DIR}/kubectl"

mkdir -p "${BIN_DIR}"

if [[ ! -x "${KUBECTL}" ]] || [[ "$("${KUBECTL}" version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion')" != "${KUBECTL_VERSION}" ]]; then
  curl --fail --location --silent --show-error \
    --output "${KUBECTL}" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  curl --fail --location --silent --show-error \
    --output "${KUBECTL}.sha256" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
  printf '%s  %s\n' "$(<"${KUBECTL}.sha256")" "${KUBECTL}" | sha256sum --check --status
  chmod 0755 "${KUBECTL}"
fi

client_version="$("${KUBECTL}" version --client -o json | jq -r '.clientVersion.gitVersion')"
[[ "${client_version}" == "${KUBECTL_VERSION}" ]]
echo "kubectl_version=${client_version}"

