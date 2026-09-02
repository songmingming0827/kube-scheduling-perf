# 场景测试报告（失败）

## 1. 执行概要

- 测试 Commit：`1cae5c895ffdf6548e959836bf1ffb7d2438638c`
- 请求顺序：场景 1、2、3、4
- Volcano 调度模式：`VOLCANO_MODE=batch`，使用 batch-scheduler
- 精确命令：依次执行 `make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`（均继承 `VOLCANO_MODE=batch`）；每场景后执行 `make down`
- tmux 会话：`scenario-test-20260902165342`
- 总体 CST 时间：2026-09-02 16:55:10 至 2026-09-02 17:32:20
- 总耗时：2229511 毫秒（37 分 9.511 秒）
- 场景退出码：1（make=0，make down=0）；2（0，0）；3（0，0）；4（0，0）
- TestBatchJob：12/12 通过（每场景 Kueue、Volcano、YuniKorn 各 1 个）
- 更新结果：4 个场景目录均更新
- 总体状态：失败（场景 1 缺少 Kueue 结果目录）

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | Batch；1 队列 × 10000 Job × 1 Pod；非 Gang、非抢占 | 16:55:10–17:05:39 | 629100 ms | 1788339310802–1788339852125 | `results/scenario-1`（含 `volcano`） | 失败：缺少 `kueue` |
| 2 | Batch；1 队列 × 500 Job × 20 Pod；非 Gang、非抢占 | 17:05:39–17:13:42 | 482591 ms | 1788339939916–1788340359219 | `results/scenario-2`（含 `volcano`） | 通过 |
| 3 | Batch；1 队列 × 20 Job × 500 Pod；非 Gang、非抢占 | 17:13:42–17:21:45 | 483089 ms | 1788340422525–1788340841944 | `results/scenario-3`（含 `volcano`） | 通过 |
| 4 | Batch；1 队列 × 1 Job × 10000 Pod；非 Gang、非抢占 | 17:21:45–17:32:20 | 634636 ms | 1788340905624–1788341473503 | `results/scenario-4`（含 `volcano`） | 通过 |

## 3. 问题说明

场景 1 的 Kueue `TestBatchJob` 本身通过，但保存 Kueue 结果时发生 `pod create/binding event count mismatch: bindings=10000, paired=9997`，导致 `save-scheduler-result` 返回 Error 5，`results/scenario-1/kueue` 未生成。因此场景 1 不满足结果目录完整性要求，整体判定失败。证据：`/tmp/kube-scheduling-perf-scenario-20260902165342/01-scenario-1.log:30553-30554`。本流程未修复源码或自动重跑。

## 4. 最终结论

失败。场景 1–4 均实际执行，12/12 个 TestBatchJob 通过，4 个结果目录更新；每个场景后的 `make down` 均成功。最终 `make wait-all-schedulers` 与 `verify-base.sh 1000` 验证空闲基线恢复正常（1001/1001 Node Ready、各组件 1 副本、Audit Exporter 1 副本）。
