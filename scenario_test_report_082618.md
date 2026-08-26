# 场景测试报告（失败）

## 1. 执行概要

- 测试提交：`c54fe80`
- 请求顺序：场景 1、2、3、4
- 执行命令：`make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`；每个场景后执行 `make down`
- tmux 会话：`scenario-test-20260826185316-3595777`
- CST 起止：2026-08-26 18:53:16 — 2026-08-26 19:26:05
- 总耗时：32 分 48.845 秒（1,968,845 毫秒）
- 场景退出码：场景 1（make 0 / down 0）、场景 2（0 / 0）、场景 3（0 / 0）、场景 4（0 / 0）
- TestBatchJob：12/12 Case 通过（每场景 Kueue、Volcano、YuniKorn 各 1）
- 更新结果场景：4 个（但每个均缺少 Kueue 结果目录）
- 最终状态：失败

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | agent；queues=1，jobs/queue=10000，pods/job=1 | 2026-08-26 18:53:16 — 19:03:15 | 599.083 秒 | 1787741596600 — 1787742119084 | `results/scenario-1` | 失败（缺少 kueue） |
| 2 | agent；queues=1，jobs/queue=500，pods/job=20 | 2026-08-26 19:03:15 — 19:10:52 | 457.033 秒 | 1787742195699 — 1787742595249 | `results/scenario-2` | 失败（缺少 kueue） |
| 3 | agent；queues=1，jobs/queue=20，pods/job=500 | 2026-08-26 19:10:52 — 19:18:21 | 448.727 秒 | 1787742652749 — 1787743044154 | `results/scenario-3` | 失败（缺少 kueue） |
| 4 | agent；queues=1，jobs/queue=1，pods/job=10000 | 2026-08-26 19:18:21 — 19:26:05 | 463.906 秒 | 1787743101489 — 1787743505287 | `results/scenario-4` | 失败（缺少 kueue） |

## 3. 问题说明

四个场景的三组 `TestBatchJob` 均通过，且每次 `make down` 均成功。结果保存阶段均因残留的 `./tmp/result-kueue-staging` 已存在而报错（`Scheduler result staging already exists`），导致 Kueue 结果目录未生成；Volcano 与 YuniKorn 结果目录已更新。该问题使四个场景均不满足完整结果目录验收标准，整体结论为失败。证据位于 tmux 工作目录 `/tmp/scenario-test-20260826185316-3595777/0[1-4]-scenario-*-make*.log`。未执行源代码修复或自动重跑。最终空闲基线已通过 `/root/benchmark-1348-deploy/scripts/verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 校验。

## 4. 最终结论

失败。场景 1–4 均实际执行，12/12 TestBatchJob Case 通过，四次清理和最终一副本空闲基线恢复均成功；但四个场景均缺少必需的 Kueue 结果目录，因此结果完整性验收未通过。
