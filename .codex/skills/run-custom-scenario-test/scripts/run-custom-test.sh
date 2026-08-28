#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "$#" -ne 9 ]]; then
  printf 'usage: %s REPOSITORY RUN_WORKSPACE SCHEDULER VOLCANO_MODE QUEUES JOBS PODS_PER_JOB GANG TIMEOUT_SECONDS\n' "$0" >&2
  exit 2
fi

repository="$1"
run_workspace="$2"
scheduler="$3"
volcano_mode="$4"
queues="$5"
jobs="$6"
pods_per_job="$7"
gang="$8"
timeout_seconds="$9"

case "${scheduler}" in
  kueue|volcano|yunikorn) ;;
  *) printf 'scheduler must be kueue, volcano, or yunikorn\n' >&2; exit 2 ;;
esac

case "${volcano_mode}" in
  auto|agent|batch) ;;
  *) printf 'VOLCANO_MODE must be auto, agent, or batch\n' >&2; exit 2 ;;
esac

if [[ "${scheduler}" != "volcano" && "${volcano_mode}" != "auto" ]]; then
  printf 'VOLCANO_MODE may only be selected when scheduler is volcano\n' >&2
  exit 2
fi

case "${gang}" in
  true|false) ;;
  *) printf 'GANG must be true or false\n' >&2; exit 2 ;;
esac

if [[ "${scheduler}" == "volcano" && "${volcano_mode}" == "agent" && "${gang}" == "true" ]]; then
  printf 'VOLCANO_MODE=agent does not support GANG=true\n' >&2
  exit 2
fi

for value_name in queues jobs pods_per_job timeout_seconds; do
  value="${!value_name}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer\n' "${value_name}" >&2
    exit 2
  fi
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

for command in awk date git grep make python3 sed tail tee; do
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

cleanup_result_staging() {
  local path
  for path in ./tmp/result-staging ./tmp/result-kueue-staging ./tmp/result-volcano-staging ./tmp/result-yunikorn-staging; do
    if [[ -e "${path}" ]]; then
      rm -rf -- "${path}"
    fi
  done
}

effective_volcano_mode="${volcano_mode}"
if [[ "${volcano_mode}" == "auto" ]]; then
  effective_volcano_mode="batch"
fi
result_scheduler="${scheduler}"
if [[ "${scheduler}" == "volcano" && "${effective_volcano_mode}" == "agent" ]]; then
  result_scheduler="volcano-agent"
fi
expected_pods=$((queues * jobs * pods_per_job))

cd "${repository}"

if [[ "$(git branch --show-current)" != "master" ]]; then
  printf 'server repository must be on master\n' >&2
  exit 2
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  printf 'server repository has tracked changes\n' >&2
  exit 2
fi

git pull --ff-only origin master
cleanup_result_staging

TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S' >"${run_workspace}/started-cst.txt"
git rev-parse HEAD >"${run_workspace}/tested-commit.txt"
printf 'scheduler=%s\nvolcano_mode=%s\neffective_volcano_mode=%s\nresult_scheduler=%s\nqueues=%s\njobs=%s\npods_per_job=%s\ngang=%s\ntimeout_seconds=%s\nexpected_pods=%s\n' \
  "${scheduler}" "${volcano_mode}" "${effective_volcano_mode}" "${result_scheduler}" "${queues}" "${jobs}" \
  "${pods_per_job}" "${gang}" "${timeout_seconds}" "${expected_pods}" \
  >"${run_workspace}/parameters.txt"

set +o errexit
make scenario-custom \
  SCHEDULERS="${scheduler}" \
  VOLCANO_MODE="${volcano_mode}" \
  QUEUES_SIZE="${queues}" \
  JOBS_SIZE_PER_QUEUE="${jobs}" \
  PODS_SIZE_PER_JOB="${pods_per_job}" \
  GANG="${gang}" \
  TEST_TIMEOUT_SECONDS="${timeout_seconds}" \
  2>&1 | timestamp_stream | tee "${run_workspace}/make.log"
make_status="${PIPESTATUS[0]}"
printf '%s\n' "${make_status}" >"${run_workspace}/make-exit-code.txt"

make down 2>&1 | timestamp_stream | tee "${run_workspace}/make-down.log"
down_status="${PIPESTATUS[0]}"
printf '%s\n' "${down_status}" >"${run_workspace}/make-down-exit-code.txt"
set -o errexit

validation_status=1
publish_status=1
observed_pods=""
result_root="results/scenario-custom"
result_path="${result_root}/${result_scheduler}"

if [[ "${make_status}" -eq 0 && "${down_status}" -eq 0 ]]; then
  validation_status=0
  for file in \
    "${result_root}/envs.txt" \
    "${result_root}/result-window.txt" \
    "${result_path}/window.txt" \
    "${result_path}/report.txt"; do
    if [[ ! -s "${file}" ]]; then
      printf 'missing or empty result file: %s\n' "${file}" >&2
      validation_status=1
    fi
  done

  if [[ "${validation_status}" -eq 0 ]]; then
    envs_file="${result_root}/envs.txt"
    for expected in \
      "SCHEDULERS=${scheduler}" \
      "QUEUES_SIZE=${queues}" \
      "JOBS_SIZE_PER_QUEUE=${jobs}" \
      "PODS_SIZE_PER_JOB=${pods_per_job}" \
      "GANG=${gang}" \
      "VOLCANO_MODE=${effective_volcano_mode}"; do
      if ! grep -Eq "(^| )${expected}( |$)" "${envs_file}"; then
        printf 'result parameters do not contain: %s\n' "${expected}" >&2
        validation_status=1
      fi
    done

    report_file="${result_path}/report.txt"
    for metric in P50 P90 P99 'Pod scheduling throughput'; do
      if ! grep -Fq "${metric}" "${report_file}"; then
        printf 'result report does not contain metric: %s\n' "${metric}" >&2
        validation_status=1
      fi
    done

    observed_pods="$(sed -n 's/.*Total scheduled: \([0-9][0-9]*\) pods.*/\1/p' "${report_file}" | tail -n 1)"
    if [[ "${observed_pods}" != "${expected_pods}" ]]; then
      printf 'scheduled Pod count mismatch: expected=%s observed=%s\n' "${expected_pods}" "${observed_pods:-missing}" >&2
      validation_status=1
    fi
  fi
fi

printf '%s\n' "${observed_pods:-missing}" >"${run_workspace}/observed-pods.txt"
printf '%s\n' "${validation_status}" >"${run_workspace}/validation-exit-code.txt"

if [[ "${validation_status}" -eq 0 ]]; then
  set +o errexit
  git add -- "${result_root}"
  publish_status="$?"
  if [[ "${publish_status}" -eq 0 ]]; then
    run_stamp="$(TZ=Asia/Shanghai date '+%m%d%H%M%S')"
    if [[ "${scheduler}" == "volcano" ]]; then
      commit_subject="results: custom ${scheduler} ${effective_volcano_mode} ${queues}x${jobs}x${pods_per_job} test ${run_stamp}"
    else
      commit_subject="results: custom ${scheduler} ${queues}x${jobs}x${pods_per_job} test ${run_stamp}"
    fi
    git commit -m "${commit_subject}"
    publish_status="$?"
  fi
  if [[ "${publish_status}" -eq 0 ]]; then
    git push origin master
    publish_status="$?"
  fi
  if [[ "${publish_status}" -eq 0 ]]; then
    git rev-parse HEAD >"${run_workspace}/published-commit.txt"
  fi
  set -o errexit
fi

cleanup_result_staging
TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S' >"${run_workspace}/ended-cst.txt"
printf 'make=%s\nmake_down=%s\nvalidation=%s\npublish=%s\n' \
  "${make_status}" "${down_status}" "${validation_status}" "${publish_status}" \
  >"${run_workspace}/status.txt"
touch "${run_workspace}/complete"

if [[ "${make_status}" -ne 0 ]]; then
  exit "${make_status}"
fi
if [[ "${down_status}" -ne 0 ]]; then
  exit "${down_status}"
fi
if [[ "${validation_status}" -ne 0 ]]; then
  exit "${validation_status}"
fi
exit "${publish_status}"
