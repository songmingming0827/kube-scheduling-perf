---
name: run-scenario-test
description: Run one or more explicitly selected kube-scheduling-perf scenario-N benchmarks in the user's requested order on the resident server cluster, restore the idle baseline after each scenario, and publish the generated results with a timestamped scenario_test_report_MMDDHH.md in one commit. Use for selected scenario tests, not a complete eight-scenario integrity run.
---

# Run Scenario Test

## Required input

- Require the user to explicitly identify at least one scenario from `1` through `8`.
- If no scenario is stated, ask which scenario or scenarios to run and do not access or modify the server yet.
- Accept individual numbers or an unambiguous range, expand ranges, and preserve the user's requested order. Do not silently sort the scenarios.
- Reject values outside `1` through `8`. Do not infer a scenario from prior test results or stale conversation context.
- Each requested scenario is one complete single-scenario run using exactly `make scenario-N`. A request for the complete eight-scenario integrity test belongs to `$run-full-integrity-test` instead.

## Environment

- Local repository: `/Users/csmvic/Downloads/volcano-versions/kube-scheduling-perf`
- Server repository: `/root/github/kube-scheduling-perf`
- Read `CLUSTER_DEPLOYMENT_RECORD.md` before operating the cluster.
- Use `$volcano-benchmark-server` from `.codex/skills/volcano-benchmark-server/` to connect, and do not expose credentials, kubeconfig contents, Secrets, or tokens.

## 1. Prepare

1. Require the local repository to be on `master`, clean, and fully pushed to `origin/master`.
2. Require the server repository to have no tracked changes, then fast-forward it to `origin/master`.
3. Record the CST start time immediately before creating the server session.
4. Name the report `scenario_test_report_MMDDHH.md` using the start month, day, and hour. Example: `2026-08-12 09:23:10` becomes `scenario_test_report_081209.md`.
5. If that report name already exists, append the first available numeric suffix: `_2`, `_3`, and so on. Never overwrite an existing report.
6. Create a unique temporary working directory under `/tmp/` and a unique `tmux` session name using the full start timestamp.

## 2. Execute

Copy this Skill's `scripts/run-scenario-test.sh` into the temporary working directory, mark it executable, and launch that copy in a detached `tmux` session. Pass the server repository, temporary working directory, and the ordered scenario numbers as arguments.

The wrapper performs the following work for every requested scenario, in order:

- Removes only the repository result staging paths `tmp/result-staging`, `tmp/result-kueue-staging`, `tmp/result-volcano-staging`, and `tmp/result-yunikorn-staging` before the first scenario and after every scenario, including failed scenarios. Do not remove other repository `tmp/` content.
- Runs exactly `make scenario-N` and saves a CST-timestamped console log and exit code.
- Runs `make down` after that command finishes, including when the scenario fails, and saves its exit code.
- Continues to the next requested scenario when the scenario command fails but `make down` succeeds.
- Stops without running later scenarios when `make down` fails, because the idle baseline is no longer established.
- Records per-scenario start/end times and result manifests, then writes a completion marker.

Monitor the completion marker so an SSH or network interruption does not interrupt or restart the test. If the wrapper terminates without a completion marker and no test process remains, run one manual `make down`, record the recovery, and end the run without rerunning any scenario.

Do not repair source, alter scenario parameters, or automatically retry a failed scenario during this workflow.

## 3. Evaluate

A requested scenario passes only when:

- Its `make scenario-N` command exits `0`.
- Its three `TestBatchJob` cases pass with no failures or timeouts.
- `results/scenario-N` is updated and contains `envs.txt`, `result-window.txt`, and the `kueue`, `volcano`, and `yunikorn` result directories.
- The `make down` following that scenario exits `0` and removes all experiment resources.

The overall run passes only when every requested scenario passes and the final scheduler components and Audit Exporter are at the fixed one-replica idle baseline. Run the repository's resident verification scripts to confirm the final baseline.

A missing or failed `job-submission.png` is recorded but does not fail an otherwise successful scenario. A scenario not reached because baseline restoration failed is `未执行`, not a test failure for that scenario; the overall run still fails because restoration failed.

Read each scenario's exact metric window from `results/scenario-N/result-window.txt`. Use the wrapper's per-scenario CST timestamps for its command boundary and duration.

## 4. Create the report

Create the report in the server repository root with exactly these sections:

```markdown
# 场景测试报告（通过或失败）

## 1. 执行概要

## 2. 场景时间边界与结果目录

## 3. 问题说明

## 4. 最终结论
```

### 执行概要

Record the tested Commit, requested scenario order, exact commands, `tmux` session, overall CST start/end in `YYYY-MM-DD HH:mm:ss`, precise duration, each scenario and cleanup exit code, passed Case count, updated scenario count, and overall status.

### 场景时间边界与结果目录

Use this table in the requested order:

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|

Mark a requested scenario that was not reached as `未执行`. Do not include unrequested scenarios in the table.

### 问题说明

If no issue occurred, state that no problem affecting the conclusion was found. Otherwise record the symptom, supported direct cause, impact, and evidence location. Distinguish non-blocking image failures from scenario or baseline-restoration failures. Leave source repair and reruns for a separate user request.

### 最终结论

State `通过` or `失败` and summarize the requested scenarios, passed Cases, updated results, and idle-baseline restoration.

## 5. Publish and clean up

After creating the report:

1. Stage only the requested `results/scenario-N` directories that changed and the current report.
2. Confirm every staged path is one of those requested result directories or the current report. Do not stage source changes or results from unrequested scenarios.
3. Commit them together as `results: scenario test <scenario-list> MMDDHH` and push `master`.
4. Fast-forward the local repository.
5. Confirm the repository result staging paths named above are absent, then delete the server temporary working directory after its evidence has been incorporated into the report.

If the run produced no result changes, publish the report alone. A failed run is still reported and published; do not conceal it by omitting the report.

## 6. Return

Return the overall result, scenarios actually executed, scenarios not executed, report path, publication commit, and any non-blocking anomaly.
