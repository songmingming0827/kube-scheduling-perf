# 场景测试报告（通过）

## 1. 执行概要

- 测试 Commit：`c581048d338f6ff1da999115d7b4a59de78e16ee`
- 请求顺序：场景 1、2、3、4
- 执行命令：依次执行 `make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`；每个命令完成后执行 `make down`
- tmux 会话：`cst-scenario-20260827_095830`
- CST 总时间：`2026-08-27 09:58:30` 至 `2026-08-27 10:31:49`
- 总耗时：`33m19.598s`
- 场景退出码：1（make 0，down 0）；2（make 0，down 0）；3（make 0，down 0）；4（make 0，down 0）
- TestBatchJob：`12/12` Case 通过
- 更新结果：场景 1–4 均更新且目录完整
- 总体状态：通过

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 1 | agent；队列 1；每队列 Job 10000；每 Job Pod 1 | 2026-08-27 09:58:30–10:08:48 | 10m18.016s | 1787795910715–1787796441064 | `results/scenario-1` | 通过 |
| 2 | agent；队列 1；每队列 Job 500；每 Job Pod 20 | 2026-08-27 10:08:48–10:16:22 | 7m33.836s | 1787796528747–1787796920266 | `results/scenario-2` | 通过 |
| 3 | agent；队列 1；每队列 Job 20；每 Job Pod 500 | 2026-08-27 10:16:22–10:24:04 | 7m41.828s | 1787796982591–1787797381567 | `results/scenario-3` | 通过 |
| 4 | agent；队列 1；每队列 Job 1；每 Job Pod 10000 | 2026-08-27 10:24:04–10:31:49 | 7m45.331s | 1787797444440–1787797845959 | `results/scenario-4` | 通过 |

## 3. 问题说明

未发现影响结论的问题。四场 `make scenario-N` 与后续 `make down` 均成功，结果目录与指标窗口完整；最终 `verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 均通过。未进行源代码修复或自动重跑。

## 4. 最终结论

通过。场景 1–4 均执行成功，12/12 个 TestBatchJob Case 通过，4 个场景结果均更新；每次 `make down` 均成功，调度器组件与 Audit Exporter 已恢复到固定一副本空闲基线。

