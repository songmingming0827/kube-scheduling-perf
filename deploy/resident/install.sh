#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_SOURCE_DIR="$(dirname "${SOURCE_DIR}")/grafana-ingress"
TARGET_DIR="/root/benchmark-1348-deploy"
MODE="setup"

usage() {
  cat <<'EOF'
Usage: install.sh [--stage-only]

Stages the versioned resident deployment bundle at
/root/benchmark-1348-deploy. By default it then installs and verifies a fresh
resident benchmark cluster. --stage-only stops after copying the bundle.
EOF
}

case "${1:-}" in
  "") ;;
  --stage-only) MODE="stage-only" ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ "${EUID}" -ne 0 ]]; then
  echo "Resident cluster installation must run as root" >&2
  exit 1
fi

for command in install tar; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command}" >&2
    exit 1
  fi
done

# shellcheck source=versions.env
source "${SOURCE_DIR}/versions.env"

if [[ ! -d "${INGRESS_SOURCE_DIR}" ]]; then
  echo "Missing Grafana Ingress bundle: ${INGRESS_SOURCE_DIR}" >&2
  exit 1
fi

if [[ "${SOURCE_DIR}" == "${TARGET_DIR}" ]]; then
  echo "Run setup.sh from the staged deployment bundle" >&2
  exit 1
fi

if [[ "${MODE}" == "setup" ]]; then
  for command in docker kind; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      echo "Required command is unavailable: ${command}" >&2
      exit 1
    fi
  done

  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is unavailable" >&2
    exit 1
  fi

  if kind get clusters | grep -Fxq -- "${CLUSTER_NAME}"; then
    echo "Refusing to overwrite existing Kind cluster: ${CLUSTER_NAME}" >&2
    exit 1
  fi
fi

install -d -m 0755 "${TARGET_DIR}" "${TARGET_DIR}/grafana-ingress"

tar -C "${SOURCE_DIR}" \
  --exclude='./bin' \
  --exclude='./downloads' \
  --exclude='./logs' \
  --exclude='./kubeconfig' \
  -cf - . | tar -C "${TARGET_DIR}" -xf -

tar -C "${INGRESS_SOURCE_DIR}" -cf - . | \
  tar -C "${TARGET_DIR}/grafana-ingress" -xf -

printf 'resident_bundle=%s\n' "${TARGET_DIR}"

if [[ "${MODE}" == "stage-only" ]]; then
  printf 'next=bash %s/setup.sh\n' "${TARGET_DIR}"
  exit 0
fi

bash "${TARGET_DIR}/setup.sh"
