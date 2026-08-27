---
name: run-single-scheduler-scenario-test
description: Run one kube-scheduling-perf scenario with exactly one scheduler on the resident benchmark server, optionally select the Volcano scheduler mode, restore the cluster with make down, and automatically commit and push that scheduler's generated results. Use when the user asks to test, rerun, or publish a single scenario and single scheduler combination.
---

# Run Single Scheduler Scenario Test

## Inputs

Require:

- Scenario: integer `1` through `8`.
- Scheduler: `kueue`, `volcano`, or `yunikorn`.
- Volcano mode: optional `auto`, `agent`, or `batch` when Scheduler is `volcano`; default to `auto`. Do not request it for other schedulers.

`auto` resolves scenarios `1` through `4` to `agent` and scenarios `5` through `8` to `batch`. Reject `agent` for scenarios `5` through `8` because those fixed scenarios use `GANG=true`, which Agent mode does not support.

Use `/root/github/kube-scheduling-perf` as the server repository. Read `CLUSTER_DEPLOYMENT_RECORD.md` before operating the cluster and connect with `$volcano-benchmark-server`.

## Prepare

1. Require local `master` changes for this workflow to be committed and pushed.
2. Require the server repository to have no tracked changes.
3. Fast-forward the server repository to `origin/master`.
4. Create a unique directory under `/tmp` and a unique `tmux` session name.

## Run

Launch `scripts/run-single-test.sh` in the detached server `tmux` session:

```bash
bash scripts/run-single-test.sh REPOSITORY SCENARIO SCHEDULER RUN_WORKSPACE [VOLCANO_MODE]
```

The script:

- Runs `make scenario-N SCHEDULERS=<scheduler> VOLCANO_MODE=<mode>`. The optional mode defaults to `auto`.
- Always runs `make down` afterward.
- Does not inspect or validate `window.txt` or `report.txt`.
- When both Make commands succeed, stages only `results/scenario-N/<scheduler>`, commits it as a timestamped single-scheduler test result, includes the effective `agent` or `batch` mode in a Volcano result commit, and pushes `master`.
- Does not publish results when either Make command fails.
- Writes logs, statuses, the requested and effective Volcano modes, the publication commit, and a completion marker into the temporary workspace.

Monitor the completion marker rather than the SSH connection. If the session disappears without the marker and no benchmark process remains, run one manual `make down`; do not restart the test automatically.

## Finish

Fast-forward the local repository after the server push. Return the scheduler, requested and effective Volcano modes when applicable, Make statuses, and publication commit. Remove the temporary workspace after the outcome is recorded.
