# 完整性测试报告（通过）

## 1. 执行概要

- 测试 Commit：`61b4a0aabdfd7a4447a19b458608d512426545d4`
- 命令：`VOLCANO_MODE=batch bash /tmp/full-integrity-20260829093344-312f8c/run-full-test.sh /root/github/kube-scheduling-perf /tmp/full-integrity-20260829093344-312f8c`
- tmux 会话：`full-integrity-20260829093412`
- CST 开始时间：2026-08-29 09:34:12
- CST 结束时间：2026-08-29 10:57:11
- 持续时间：1 小时 22 分 59.289 秒
- `make` 退出码：0
- `make down` 退出码：0
- 通过 Case：24/24
- 更新场景：8/8
- Volcano 调度器模式：`batch-scheduler`（`VOLCANO_MODE=batch`）
- 总体状态：通过

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | 非 Gang；10000 Job × 1 Pod；Volcano batch | 2026-08-29 09:34:12 – 09:44:41 | 00:10:29 | 1787967253007–1787967797294 | results/scenario-1 | 通过 |
| 2 | 非 Gang；500 Job × 20 Pod；Volcano batch | 2026-08-29 09:44:41 – 09:52:28 | 00:07:47 | 1787967881696–1787968297413 | results/scenario-2 | 通过 |
| 3 | 非 Gang；20 Job × 500 Pod；Volcano batch | 2026-08-29 09:52:28 – 10:00:13 | 00:07:45 | 1787968348291–1787968761787 | results/scenario-3 | 通过 |
| 4 | 非 Gang；1 Job × 10000 Pod；Volcano batch | 2026-08-29 10:00:13 – 10:10:35 | 00:10:22 | 1787968814178–1787969381459 | results/scenario-4 | 通过 |
| 5 | Gang；10000 Job × 1 Pod；Volcano batch | 2026-08-29 10:10:35 – 10:24:57 | 00:14:22 | 1787969435659–1787970204784 | results/scenario-5 | 通过 |
| 6 | Gang；500 Job × 20 Pod；Volcano batch | 2026-08-29 10:24:57 – 10:33:56 | 00:08:59 | 1787970297968–1787970779757 | results/scenario-6 | 通过 |
| 7 | Gang；20 Job × 500 Pod；Volcano batch | 2026-08-29 10:33:56 – 10:43:28 | 00:09:32 | 1787970836799–1787971349101 | results/scenario-7 | 通过 |
| 8 | Gang；1 Job × 10000 Pod；Volcano batch | 2026-08-29 10:43:28 – 10:57:11 | 00:13:43 | 1787971408311–1787972164722 | results/scenario-8 | 通过 |

## 3. 问题说明

未发现影响结论的问题。八个场景均生成结果文件，24/24 个 `TestBatchJob` Case 通过，无失败或超时。Dashboard 结果文件已生成；未发现非阻塞的 Dashboard 镜像异常。测试结束后结果暂存目录均已清理。

## 4. 最终结论

通过。完整八场景测试全部完成，24/24 个 Case 通过；Volcano 全程使用 `batch-scheduler`。测试后的 `make down` 成功，实验资源已清理，Kueue、Coscheduling、Volcano、YuniKorn 及 Audit Exporter 均恢复到固定的一副本空闲基线。
