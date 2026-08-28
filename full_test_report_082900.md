# 完整性测试报告（通过）

## 1. 执行概要

- 测试 Commit：`2b9b7371a09c16037c2e4d20756aa946c04c636e`
- 命令：`VOLCANO_MODE=batch ./run-full-test.sh /root/github/kube-scheduling-perf /tmp/full-integrity-20260828164556-FVQqrd`
- tmux 会话：`full-integrity-20260828164556`
- CST 开始时间：2026-08-29 00:46:35
- CST 结束时间：2026-08-29 02:13:15
- 持续时间：1 小时 26 分 39.979 秒
- `make` 退出码：0
- `make down` 退出码：0
- 通过 Case：24/24
- 更新场景：8/8
- Volcano 调度器模式：`batch-scheduler`（`VOLCANO_MODE=batch`）
- 总体状态：通过

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | 非 Gang；10000 Job × 1 Pod；Volcano batch | 2026-08-29 00:46:35 – 00:57:15 | 00:10:40 | 1787935595374–1787936151904 | results/scenario-1 | 通过 |
| 2 | 非 Gang；500 Job × 20 Pod；Volcano batch | 2026-08-29 00:57:15 – 01:06:03 | 00:08:48 | 1787936235927–1787936707031 | results/scenario-2 | 通过 |
| 3 | 非 Gang；20 Job × 500 Pod；Volcano batch | 2026-08-29 01:06:03 – 01:14:09 | 00:08:06 | 1787936763717–1787937191447 | results/scenario-3 | 通过 |
| 4 | 非 Gang；1 Job × 10000 Pod；Volcano batch | 2026-08-29 01:14:09 – 01:24:36 | 00:10:27 | 1787937249541–1787937817146 | results/scenario-4 | 通过 |
| 5 | Gang；10000 Job × 1 Pod；Volcano batch | 2026-08-29 01:24:36 – 01:40:26 | 00:15:50 | 1787937876520–1787938705393 | results/scenario-5 | 通过 |
| 6 | Gang；500 Job × 20 Pod；Volcano batch | 2026-08-29 01:40:26 – 01:49:30 | 00:09:04 | 1787938826991–1787939306562 | results/scenario-6 | 通过 |
| 7 | Gang；20 Job × 500 Pod；Volcano batch | 2026-08-29 01:49:30 – 01:59:10 | 00:09:40 | 1787939370294–1787939887031 | results/scenario-7 | 通过 |
| 8 | Gang；1 Job × 10000 Pod；Volcano batch | 2026-08-29 01:59:10 – 02:13:15 | 00:14:05 | 1787939950832–1787940720369 | results/scenario-8 | 通过 |

## 3. 问题说明

未发现影响结论的问题。八个场景均生成结果文件，24/24 个 `TestBatchJob` Case 通过，无失败或超时。Dashboard 结果文件已生成；未发现非阻塞的 Dashboard 镜像异常。

## 4. 最终结论

通过。完整八场景测试全部完成，24/24 个 Case 通过；Volcano 全程使用 `batch-scheduler`。测试后的 `make down` 成功，实验资源已清理，Kueue、Coscheduling、Volcano、YuniKorn 及 Audit Exporter 均恢复到固定的一副本空闲基线。

