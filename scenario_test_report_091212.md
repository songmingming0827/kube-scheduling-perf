# 场景测试报告（通过）

## 1. 执行概要

- 测试 Commit：`c407fdb3e6df802fa03c3c8acd0fffd7fca934e7`
- 请求场景顺序：场景 5
- 执行命令：`make scenario-5`；清理命令：`make down`
- tmux 会话：`cst-scenario-20260912121814`
- 整体 CST 时间：2026-09-12 12:18:50 至 2026-09-12 12:33:18
- 精确耗时：868739 毫秒（14 分 28.739 秒）
- 场景 5：`make scenario-5` 退出码 0；`make down` 退出码 0
- 通过 Case：3/3（Kueue、Volcano、YuniKorn 各 1 个 `TestBatchJob`）
- 更新结果场景数：1
- 整体状态：通过

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---:|---|---|
| 场景 5 | Batch；GANG=true；QUEUES_SIZE=1；JOBS_SIZE_PER_QUEUE=10000；PODS_SIZE_PER_JOB=1；PREEMPTION=false | 2026-09-12 12:18:50 至 2026-09-12 12:33:18 | 868701 毫秒 | from=1789186730600；to=1789187503769 | `results/scenario-5` | 通过 |

结果目录包含 `envs.txt`、`result-window.txt`、`kueue`、`volcano`、`yunikorn` 和 Batch Dashboard 图片。

## 3. 问题说明

未发现影响结论的问题。场景命令、三项 `TestBatchJob`、清理命令均成功；结果暂存路径已清理。最终 `verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 均通过，Audit Exporter 保持 1 副本运行。

## 4. 最终结论

通过。场景 5 已完成，3/3 Case 通过，`results/scenario-5` 已更新，场景结束后的空闲基线已恢复并验证通过。
