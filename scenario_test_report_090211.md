# 场景测试报告（失败）

## 1. 执行概要

- 被测 Commit：`eea4f62c1798bcf6945fff664ddd4a6c4c69eb4e`
- 请求顺序：场景 1 → 场景 2 → 场景 3 → 场景 4
- 精确命令：依次执行 `make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`，每个场景后执行一次 `make down`
- Volcano 模式：`VOLCANO_MODE=agent`，使用 `agent-scheduler`
- tmux 会话：`scenario-test-20260902T112459-2274915`
- CST（UTC+8）总时间：`2026-09-02 11:24:59` 至 `2026-09-02 11:59:01`
- 精确总耗时：`2041646 ms`（`34m01.646s`）
- 场景与清理退出码：场景 1 `0/0`、场景 2 `0/0`、场景 3 `0/0`、场景 4 `0/0`（前者为场景命令，后者为 `make down`）
- Case：`12/12` 个 `TestBatchJob` 通过，无 Case 失败或超时
- 结果更新：`4/4` 个请求场景的结果时间窗已更新；其中 `3/4` 个场景满足必需结果目录完整性
- 总体状态：`失败`

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 场景 1 | Agent；1 队列 × 10000 job × 1 pod；非 Gang、非抢占 | `2026-09-02 11:24:59` → `2026-09-02 11:35:22` | `622808 ms`（`10m22.808s`） | `1788319500166` → `1788320036110` | `results/scenario-1` | 失败：缺少 `kueue` 结果目录 |
| 场景 2 | Agent；1 队列 × 500 job × 20 pod；非 Gang、非抢占 | `2026-09-02 11:35:22` → `2026-09-02 11:43:14` | `472058 ms`（`7m52.058s`） | `1788320122979` → `1788320531370` | `results/scenario-2` | 通过 |
| 场景 3 | Agent；1 队列 × 20 job × 500 pod；非 Gang、非抢占 | `2026-09-02 11:43:14` → `2026-09-02 11:51:00` | `465641 ms`（`7m45.641s`） | `1788320595056` → `1788320997533` | `results/scenario-3` | 通过 |
| 场景 4 | Agent；1 队列 × 1 job × 10000 pod；非 Gang、非抢占 | `2026-09-02 11:51:00` → `2026-09-02 11:59:01` | `481043 ms`（`8m01.043s`） | `1788321060709` → `1788321477904` | `results/scenario-4` | 通过 |

## 3. 问题说明

- 阻断问题：场景 1 的 Kueue Case 本身通过，但保存 Kueue 结果时出现 `pod create/binding event count mismatch: bindings=10000, paired=9999`，随后 `save-scheduler-result` 返回 `Error 5`。因此 `results/scenario-1/kueue` 未生成，场景 1 不满足结果目录完整性要求，导致整体失败。证据为清理前运行日志 `/tmp/scenario-test-20260902T112459-2274915/01-scenario-1.log` 中的上述错误，以及发布结果中 `results/scenario-1/kueue` 的缺失。本流程未修复源码或自动重跑。
- 非阻断异常：监控期间 SSH 控制连接中断一次；重连后确认原 tmux 会话和包装进程持续运行，未重启、未重跑任何场景，对远端测试结果无影响。
- Dashboard：场景 1–4 的 `job-submission-agent.png` 均生成成功，为有效的 `1584 × 762` PNG，没有图片缺失或渲染失败。
- 最终基线：`verify-base.sh 1000`、`verify-schedulers.sh`、`verify-monitoring.sh` 和 Grafana Ingress 验证全部通过；`1001/1001` Node Ready，全部调度组件与 Audit Exporter 均恢复为固定 `1/1` 副本，结果 staging 路径均已清理。

## 4. 最终结论

`失败`。场景 1–4 均实际执行，`12/12` 个 Case 通过，4 个场景结果均发生更新；场景 2–4 通过，但场景 1 因缺少 Kueue 结果目录而失败。最终空闲基线已完整恢复。
