# 完整性测试报告（失败）

## 1. 执行概要

- 测试 Commit：`940cde49cb0f946760e2aabf4a9c32077c52a65c`
- 命令：`make`，结束后自动执行 `make down`
- tmux 会话：`full-integrity-r2-20260828T000908`
- CST 开始：`2026-08-28 00:09:08`
- CST 结束：`2026-08-28 01:38:37`
- 精确耗时：`1h29m28.875s`
- `make` 退出码：`0`，但内部存在未传播的 Case 与结果保存错误
- `make down` 退出码：`0`
- TestBatchJob：`22/24` 通过，`2` 个超时失败
- 更新场景目录：`8/8`，但场景 1、5 的 YuniKorn Case 不完整，场景 2～8 缺少本轮 Kueue 报告
- 提交参数：Kubernetes client QPS/Burst `1000/2000`，`SUBMIT_CONCURRENCY=50`
- 总体状态：失败

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | 非 Gang；Volcano Agent；队列 1，Job 10000，Pod/Job 1 | 2026-08-28 00:09:08 ～ 2026-08-28 00:23:58 | 14m50s | 1787846948624 ～ 1787847744424 | `results/scenario-1` | 失败：YuniKorn 超时 |
| 2 | 非 Gang；Volcano Agent；队列 1，Job 500，Pod/Job 20 | 2026-08-28 00:23:58 ～ 2026-08-28 00:31:47 | 7m49s | 1787847838618 ～ 1787848250391 | `results/scenario-2` | Case 通过；Kueue 报告保存失败 |
| 3 | 非 Gang；Volcano Agent；队列 1，Job 20，Pod/Job 500 | 2026-08-28 00:31:47 ～ 2026-08-28 00:39:43 | 7m56s | 1787848307507 ～ 1787848731945 | `results/scenario-3` | Case 通过；Kueue 报告缺失 |
| 4 | 非 Gang；Volcano Agent；队列 1，Job 1，Pod/Job 10000 | 2026-08-28 00:39:43 ～ 2026-08-28 00:47:35 | 7m52s | 1787848783345 ～ 1787849202002 | `results/scenario-4` | Case 通过；Kueue 报告缺失 |
| 5 | Gang；Volcano Batch；队列 1，Job 10000，Pod/Job 1 | 2026-08-28 00:47:35 ～ 2026-08-28 01:05:25 | 17m50s | 1787849255310 ～ 1787850215748 | `results/scenario-5` | 失败：YuniKorn 超时；Kueue 报告缺失 |
| 6 | Gang；Volcano Batch；队列 1，Job 500，Pod/Job 20 | 2026-08-28 01:05:25 ～ 2026-08-28 01:14:54 | 9m29s | 1787850325994 ～ 1787850838776 | `results/scenario-6` | Case 通过；Kueue 报告缺失 |
| 7 | Gang；Volcano Batch；队列 1，Job 20，Pod/Job 500 | 2026-08-28 01:14:54 ～ 2026-08-28 01:24:43 | 9m49s | 1787850894461 ～ 1787851425025 | `results/scenario-7` | Case 通过；Kueue 报告缺失 |
| 8 | Gang；Volcano Batch；队列 1，Job 1，Pod/Job 10000 | 2026-08-28 01:24:43 ～ 2026-08-28 01:38:30 | 13m47s | 1787851483800 ～ 1787852249001 | `results/scenario-8` | Case 通过；Kueue 报告缺失 |

## 3. 问题说明

场景 1 的 YuniKorn `TestBatchJob` 在 `350s` 超时，场景 5 的同一 Case 在 `430s` 超时。两次 goroutine 栈都停在 `utils.WaitJobsCompleted(..., expected=10000)`，说明 10,000 个 YuniKorn Job 未能在场景超时前全部完成。场景 1 和场景 5 的 YuniKorn 指标与报告只覆盖未完成运行，不能作为完整性能结果。

场景 2 保存 Kueue 报告时，审计事件校验失败：`bindings=10000, paired=9999`。该失败留下 `tmp/result-kueue-staging`，随后场景 3～8 的 Kueue 保存步骤均以 `Scheduler result staging already exists` 失败。wrapper 在最终 `make down` 后清除了 staging，但 `results/scenario-2` 至 `results/scenario-8` 没有本轮 Kueue `report.txt` 和 `window.txt`，因此这些场景的逐调度器结果不完整。

上述两个 Case 超时和七个 Kueue 保存错误均未传播到顶层：串行 `foreach` 配方继续执行后续命令，最终 `make` 仍返回 `0`。因此本轮不能依据顶层退出码判定通过，直接证据位于本轮临时工作目录的 `make.log`。

恢复流程正常：`make down` 返回 `0`，实验资源零残留，`verify-base.sh 1000`、`verify-schedulers.sh` 和 `verify-monitoring.sh` 均通过；`1001/1001` Node Ready，9 个调度 Deployment 与 Audit Exporter 均恢复为 `1/1 Ready`。

## 4. 最终结论

失败。八个场景均执行并更新顶层元数据，但只有 `22/24` 个 `TestBatchJob` Case 通过；场景 1、5 的 YuniKorn 超时，场景 2～8 的本轮 Kueue 报告不完整。集群和监控已成功恢复到固定空闲基线。本轮按要求只记录并发布失败结果，不修改源码，也不自动重跑。
