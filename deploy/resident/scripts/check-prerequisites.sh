#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "${SCRIPT_DIR}")"
EXPECTED_BUNDLE_DIR="/root/benchmark-1348-deploy"

# shellcheck source=/dev/null
source "${BUNDLE_DIR}/versions.env"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Resident cluster installation must run as root" >&2
  exit 1
fi

if [[ "${BUNDLE_DIR}" != "${EXPECTED_BUNDLE_DIR}" ]]; then
  echo "Resident deployment bundle must be staged at ${EXPECTED_BUNDLE_DIR}" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "Resident deployment currently supports Linux x86_64 only" >&2
  exit 1
fi

for command in curl docker helm install jq kind make sha256sum ss systemctl tar; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command}" >&2
    exit 1
  fi
done

if [[ ! -d /run/systemd/system ]]; then
  echo "A running systemd instance is required" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is unavailable" >&2
  exit 1
fi

kind_version="$(kind version | awk 'NR == 1 {print $2}')"
if [[ "${kind_version}" != "${KIND_VERSION}" ]]; then
  echo "Expected Kind ${KIND_VERSION}, found ${kind_version:-unknown}" >&2
  exit 1
fi

helm_version="$(helm version --short)"
if [[ ! "${helm_version}" =~ ^v3\. ]]; then
  echo "Expected Helm v3, found ${helm_version:-unknown}" >&2
  exit 1
fi

for port in 31003 31004 31005 8080; do
  if ss -H -ltn | awk -v suffix=":${port}" '$4 ~ suffix "$" { found = 1 } END { exit !found }'; then
    echo "Required host port is already in use: ${port}" >&2
    exit 1
  fi
done

printf 'platform=linux/amd64\n'
printf 'kind_version=%s\n' "${kind_version}"
printf 'docker=ready\n'
printf 'helm=%s\n' "${helm_version}"
printf 'ports=31003,31004,31005,8080_available\n'
printf 'systemd=ready\n'
