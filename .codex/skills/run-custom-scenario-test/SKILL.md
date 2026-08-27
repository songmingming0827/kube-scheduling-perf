---
name: run-custom-scenario-test
description: Run one small-scale kube-scheduling-perf scenario-custom performance test with exactly one scheduler on the resident benchmark server, accept optional workload parameters, restore the idle baseline, validate the generated metrics, and publish results. Use for custom single-scheduler performance or smoke-scale benchmark requests, not fixed scenario-1 through scenario-8 tests.
---

# Run Custom Scenario Test

## Inputs

Use these defaults for every omitted input; do not ask the user to repeat them:

| Input | Default | Accepted values |
|---|---:|---|
| `SCHEDULERS` | `volcano` | Exactly one of `kueue`, `volcano`, `yunikorn` |
| `VOLCANO_MODE` | `batch` | `auto`, `agent`, `batch`; relevant only to Volcano |
| `QUEUES_SIZE` | `1` | Positive integer |
| `JOBS_SIZE_PER_QUEUE` | `50` | Positive integer |
| `PODS_SIZE_PER_JOB` | `16` | Positive integer |
| `GANG` | `false` | `true` or `false` |
| `TEST_TIMEOUT_SECONDS` | `300` | Positive integer |

Accept partial overrides and preserve every omitted applicable default. When the selected scheduler is not Volcano, use `VOLCANO_MODE=auto` internally if the user omitted it and reject an explicitly supplied Volcano mode. Reject multiple schedulers and `VOLCANO_MODE=agent` with `GANG=true`. Do not impose an invented workload-size cap; report the requested total Pod count before execution when the user overrides the small default shape.

## Environment

- Local repository: `/Users/csmvic/Downloads/volcano-versions/kube-scheduling-perf`
- Server repository: `/root/github/kube-scheduling-perf`
- Read `RESIDENT_CLUSTER_PLAN_DETAIL.md` section `2.4 单场景、单调度器运行用于性能测试` and `CLUSTER_DEPLOYMENT_RECORD.md` before operating the cluster.
- Connect with `$volcano-benchmark-server`; never expose credentials, kubeconfig contents, Secrets, or tokens.

## Prepare

1. Require local `master` to be clean and fully pushed to `origin/master` so the server receives the current `scenario-custom` target. The Skill wrapper itself is copied separately in step 4.
2. Require the server repository to be on `master` with no tracked changes, then fast-forward it to `origin/master`.
3. Create a unique `/tmp` workspace and detached `tmux` session using the full CST timestamp.
4. Copy `scripts/run-custom-test.sh` from this Skill into the temporary workspace and make that copy executable.

## Run

Launch the copied wrapper in the detached server session:

```bash
bash run-custom-test.sh REPOSITORY RUN_WORKSPACE SCHEDULER VOLCANO_MODE QUEUES JOBS PODS_PER_JOB GANG TIMEOUT_SECONDS
```

The wrapper runs exactly one command shaped as follows, with resolved input values:

```bash
make scenario-custom \
  SCHEDULERS=<scheduler> \
  VOLCANO_MODE=<mode> \
  QUEUES_SIZE=<queues> \
  JOBS_SIZE_PER_QUEUE=<jobs> \
  PODS_SIZE_PER_JOB=<pods> \
  GANG=<gang> \
  TEST_TIMEOUT_SECONDS=<timeout>
```

It always runs `make down` afterward. Monitor the workspace completion marker rather than the SSH connection. If the session disappears without the marker and no benchmark process remains, run one manual `make down`; do not retry the performance test automatically.

Do not generate or expect a relative Dashboard. Do not modify `results/scenario-1` through `results/scenario-8`.

## Validate and publish

A run passes only when:

- `make scenario-custom` and the following `make down` both exit `0`.
- `results/scenario-custom/envs.txt`, `result-window.txt`, and `<scheduler>/{window.txt,report.txt}` exist and are non-empty.
- `envs.txt` records the requested scheduler, queue count, Job count, replicas, Gang setting, and effective Volcano mode.
- `report.txt` contains P50, P90, P99, throughput, and a scheduled Pod count equal to `QUEUES_SIZE × JOBS_SIZE_PER_QUEUE × PODS_SIZE_PER_JOB`.
- The resident verification scripts confirm the fixed idle baseline after cleanup.

When validation succeeds, stage only `results/scenario-custom`, commit as a timestamped custom performance result including scheduler, effective mode when Volcano is selected, and workload shape, then push `master`. Fast-forward the local repository afterward. Do not publish a failed run or stage source changes.

Return the resolved parameters, expected and observed Pod counts, P50/P90/P99, throughput, test and cleanup statuses, result directory, and publication commit. Remove the temporary workspace only after its evidence has been recorded.
