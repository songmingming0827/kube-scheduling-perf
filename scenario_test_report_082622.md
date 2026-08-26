# 场景测试报告（失败）

## 1. 执行概要

- 测试 Commit：`6694a19a237fe2c15cd612e158cb8dfdf2eb3006`
- 请求顺序：场景 1、2、3、4
- 执行命令：依次执行 `make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`；每个命令完成后执行 `make down`
- tmux 会话：`scenario-test-20260826221041`
- CST 总时间：`2026-08-26 22:10:51` 至 `2026-08-26 22:44:16`
- 总耗时：`33m24.723s`
- 场景退出码：1（make 0，down 0）；2（make 0，down 0）；3（make 0，down 0）；4（make 0，down 0）
- TestBatchJob：`12/12` Case 通过
- 更新结果：场景 1 结果不完整，场景 2–4 结果完整
- 总体状态：失败

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 1 | agent；队列 1；每队列 Job 10000；每 Job Pod 1 | 2026-08-26 22:10:51–22:21:09 | 10m18.284s | 1787753451633–1787753981498 | `results/scenario-1` | 失败（缺少 kueue） |
| 2 | agent；队列 1；每队列 Job 500；每 Job Pod 20 | 2026-08-26 22:21:09–22:28:46 | 7m36.430s | 1787754069936–1787754464060 | `results/scenario-2` | 通过 |
| 3 | agent；队列 1；每队列 Job 20；每 Job Pod 500 | 2026-08-26 22:28:46–22:36:24 | 7m38.351s | 1787754526382–1787754921612 | `results/scenario-3` | 通过 |
| 4 | agent；队列 1；每队列 Job 1；每 Job Pod 10000 | 2026-08-26 22:36:24–22:44:16 | 7m51.559s | 1787754984751–1787755391735 | `results/scenario-4` | 通过 |

## 3. 问题说明

场景 1 的三个 `TestBatchJob` Case 均通过，且 `make down` 成功；但结果保存阶段 Kueue 指标校验失败：`pod create/binding event count mismatch: bindings=10000, paired=9998`，导致 `results/scenario-1/kueue` 目录未生成。该结果缺失使场景 1 不满足完整结果目录验收标准，整体结论为失败。证据位于 `/tmp/scenario-test-20260826221041-run/01-scenario-1.log`，约第 30548 行。未进行源代码修复或自动重跑。该问题不是图片异常。

## 4. 最终结论

失败。场景 1–4 均执行，12/12 个 TestBatchJob Case 通过，场景 2–4 结果完整；场景 1 因 Kueue 结果保存校验失败而缺少结果目录。每次 `make down` 均成功，最终 `verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 均通过，调度器组件与 Audit Exporter 已恢复到一副本空闲基线。
