#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "$#" -lt 3 ]]; then
  printf 'usage: %s REPOSITORY RUN_WORKSPACE SCENARIO [SCENARIO ...]\n' "$0" >&2
  exit 2
fi

repository="$1"
run_workspace="$2"
shift 2
scenarios=("$@")

for scenario in "${scenarios[@]}"; do
  case "${scenario}" in
    1|2|3|4|5|6|7|8) ;;
    *)
      printf 'scenario must be an integer from 1 to 8: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "${repository}/.git" ]]; then
  printf 'repository is not a Git checkout: %s\n' "${repository}" >&2
  exit 2
fi

mkdir -p "${run_workspace}"
if [[ -e "${run_workspace}/started-cst.txt" ]]; then
  printf 'run workspace already initialized: %s\n' "${run_workspace}" >&2
  exit 2
fi

cd "${repository}"

for command in awk date git make python3 sha256sum tee; do
  command -v "${command}" >/dev/null || {
    printf 'required command is unavailable: %s\n' "${command}" >&2
    exit 2
  }
done

timestamp_stream() {
  TZ=Asia/Shanghai python3 -u -c 'import sys, time
for line in sys.stdin:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] {line}", end="", flush=True)'
}

epoch_millis() {
  python3 -c 'import time; print(time.time_ns() // 1_000_000)'
}

write_result_manifest() {
  local destination="$1"
  local scenario directory file digest

  : >"${destination}"
  for scenario in "${scenarios[@]}"; do
    directory="results/scenario-${scenario}"
    file="${directory}/result-window.txt"
    if [[ -f "${file}" ]]; then
      digest="$(sha256sum "${file}" | awk '{print $1}')"
      printf '%s\t%s\t%s\n' "${scenario}" "${digest}" "${file}" >>"${destination}"
    else
      printf '%s\tMISSING\t%s\n' "${scenario}" "${file}" >>"${destination}"
    fi
  done
}

started_epoch_millis="$(epoch_millis)"
TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S' >"${run_workspace}/started-cst.txt"
printf '%s\n' "${started_epoch_millis}" >"${run_workspace}/started-epoch-millis.txt"
printf '%s\n' "${scenarios[*]}" >"${run_workspace}/requested-scenarios.txt"
git rev-parse HEAD >"${run_workspace}/tested-commit.txt"
write_result_manifest "${run_workspace}/results-before.tsv"
printf 'sequence\tscenario\tmake_exit\tmake_down_exit\tstarted_cst\tended_cst\tduration_millis\n' >"${run_workspace}/scenario-status.tsv"

overall_status=0
sequence=0

for scenario in "${scenarios[@]}"; do
  sequence=$((sequence + 1))
  run_id="$(printf '%02d-scenario-%s' "${sequence}" "${scenario}")"
  scenario_started_epoch_millis="$(epoch_millis)"
  scenario_started_cst="$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')"

  set +o errexit
  make "scenario-${scenario}" 2>&1 | timestamp_stream | tee "${run_workspace}/${run_id}.log"
  make_status="${PIPESTATUS[0]}"
  printf '%s\n' "${make_status}" >"${run_workspace}/${run_id}-make-exit-code.txt"

  make down 2>&1 | timestamp_stream | tee "${run_workspace}/${run_id}-make-down.log"
  down_status="${PIPESTATUS[0]}"
  printf '%s\n' "${down_status}" >"${run_workspace}/${run_id}-make-down-exit-code.txt"
  set -o errexit

  scenario_ended_epoch_millis="$(epoch_millis)"
  scenario_ended_cst="$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')"
  scenario_duration_millis=$((scenario_ended_epoch_millis - scenario_started_epoch_millis))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${sequence}" "${scenario}" "${make_status}" "${down_status}" \
    "${scenario_started_cst}" "${scenario_ended_cst}" "${scenario_duration_millis}" \
    >>"${run_workspace}/scenario-status.tsv"

  if [[ "${make_status}" -ne 0 ]]; then
    overall_status=1
  fi
  if [[ "${down_status}" -ne 0 ]]; then
    overall_status=1
    break
  fi
done

write_result_manifest "${run_workspace}/results-after.tsv"
ended_epoch_millis="$(epoch_millis)"
TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S' >"${run_workspace}/ended-cst.txt"
printf '%s\n' "${ended_epoch_millis}" >"${run_workspace}/ended-epoch-millis.txt"
printf '%s\n' "$((ended_epoch_millis - started_epoch_millis))" >"${run_workspace}/duration-millis.txt"
printf '%s\n' "${overall_status}" >"${run_workspace}/overall-exit-code.txt"
touch "${run_workspace}/complete"

exit "${overall_status}"
