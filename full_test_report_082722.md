# 完整性测试报告（通过）

## 1. 执行概要

- 测试 Commit：`1e71515a44565064d923f0833fdc8d37c62693d6`
- 命令：`make`，结束后自动执行 `make down`
- tmux 会话：`full-integrity-r1-20260827T222805`
- CST 开始：`2026-08-27 22:28:05`
- CST 结束：`2026-08-27 23:51:36`
- 精确耗时：`1h23m30.953s`
- `make` 退出码：`0`
- `make down` 退出码：`0`
- TestBatchJob：`24/24` 通过，`0` 失败
- 更新场景：`8/8`
- 提交参数：Kubernetes client QPS/Burst `1000/2000`，`SUBMIT_CONCURRENCY=50`
- 总体状态：通过

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | 非 Gang；Volcano Agent；队列 1，Job 10000，Pod/Job 1 | 2026-08-27 22:28:05 ～ 2026-08-27 22:38:30 | 10m25s | 1787840886064 ～ 1787841427756 | `results/scenario-1` | 通过 |
| 2 | 非 Gang；Volcano Agent；队列 1，Job 500，Pod/Job 20 | 2026-08-27 22:38:30 ～ 2026-08-27 22:46:20 | 7m50s | 1787841510196 ～ 1787841924287 | `results/scenario-2` | 通过 |
| 3 | 非 Gang；Volcano Agent；队列 1，Job 20，Pod/Job 500 | 2026-08-27 22:46:20 ～ 2026-08-27 22:54:03 | 7m43s | 1787841980937 ～ 1787842386105 | `results/scenario-3` | 通过 |
| 4 | 非 Gang；Volcano Agent；队列 1，Job 1，Pod/Job 10000 | 2026-08-27 22:54:03 ～ 2026-08-27 23:02:01 | 7m58s | 1787842443189 ～ 1787842863095 | `results/scenario-4` | 通过 |
| 5 | Gang；Volcano Batch；队列 1，Job 10000，Pod/Job 1 | 2026-08-27 23:02:01 ～ 2026-08-27 23:19:15 | 17m14s | 1787842921511 ～ 1787843865110 | `results/scenario-5` | 通过 |
| 6 | Gang；Volcano Batch；队列 1，Job 500，Pod/Job 20 | 2026-08-27 23:19:15 ～ 2026-08-27 23:28:24 | 9m09s | 1787843955272 ～ 1787844449575 | `results/scenario-6` | 通过 |
| 7 | Gang；Volcano Batch；队列 1，Job 20，Pod/Job 500 | 2026-08-27 23:28:24 ～ 2026-08-27 23:37:57 | 9m33s | 1787844504876 ～ 1787845018556 | `results/scenario-7` | 通过 |
| 8 | Gang；Volcano Batch；队列 1，Job 1，Pod/Job 10000 | 2026-08-27 23:37:57 ～ 2026-08-27 23:51:30 | 13m33s | 1787845077202 ～ 1787845830240 | `results/scenario-8` | 通过 |

## 3. 问题说明

未发现影响本轮通过结论的问题。八个场景均更新了 `envs.txt`、`result-window.txt` 和 `job-submission.png`，24 个 Case 无失败或超时，所有结果采集步骤成功。

非阻断风险：场景 5 的 YuniKorn `TestBatchJob` 耗时 `428.76s`，距离 `430s` 测试超时仅余约 `1.24s`。本轮 Case 正常通过，但该余量很小，后续重复运行需要重点观察其稳定性。证据位于本轮临时工作目录的 `make.log`。

测试结束后的资源零残留断言、`verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 均通过；`1001/1001` Node Ready，9 个调度 Deployment 与 Audit Exporter 均恢复为 `1/1 Ready`。

## 4. 最终结论

通过。八个场景全部完成，`24/24` 个 `TestBatchJob` Case 通过，8 个结果目录均由本轮更新；`make down` 成功清理实验资源，调度器组件、Audit Exporter、基础集群和监控均恢复到固定空闲基线。
