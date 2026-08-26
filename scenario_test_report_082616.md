# 场景测试报告（失败）

## 1. 执行概要

- 测试 Commit：`9d3218283f7c624d5fd2bdff195d4db027182b74`
- 请求顺序：场景 1、2、3、4
- 实际命令：`make scenario-1`；场景 2—4 未执行
- tmux 会话：`scenario-test-20260826165337`
- 整体 CST 时间：`2026-08-26 16:55:25` 至 `2026-08-26 17:07:xx`（用户要求停止）
- 清理：手动 `make down`，退出码 `0`
- 通过 Case：0 个；更新结果：0 个；整体状态：失败

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 1 | `make scenario-1` | `2026-08-26 16:55:25` 至用户停止 | 用户停止 | `1787713204022`—`1787713728869` | `results/scenario-1` | 失败（Volcano） |
| 2 | — | — | — | — | — | 未执行 |
| 3 | — | — | — | — | — | 未执行 |
| 4 | — | — | — | — | — | 未执行 |

## 3. 问题说明

Volcano 执行失败的直接证据位于 `/tmp/scenario-test-20260826165337.1sU5Q5/01-scenario-1.log`：

- `TestInit` 在 `2026-08-26 16:59:08` 调用 Volcano Admission Webhook 时失败：`failed to call webhook ... connect: connection refused`，随后 `TestInit`、`prepare-volcano` 失败。
- 后续 `TestBatchJob` 在 `2026-08-26 17:05:02` 报告 `panic: test timed out after 5m50s`，对应 `make scenario-1` 的 Volcano 测试失败。
- 用户要求停止后终止剩余执行，并手动运行 `make down`；清理退出码为 `0`，基线组件恢复为一副本，`verify-base.sh 1000` 通过。

## 4. 最终结论

失败。仅执行场景 1；场景 2—4 未执行。Volcano Admission Webhook 连接拒绝并导致后续 BatchJob 超时；清理已成功，空闲基线已恢复。未进行源码修复或自动重跑。
