# 场景测试报告（失败）

## 1. 执行概要

- 测试 Commit：`de464bde49710025ed2940c11ca64f4e2eb7d8c0`
- 请求顺序：场景 1、2、3、4
- 执行命令：依次执行 `make scenario-1`、`make scenario-2`、`make scenario-3`、`make scenario-4`；每个场景后执行 `make down`
- tmux 会话：`scenario-test-20260828235833`
- CST 开始：`2026-08-28 23:58:33`
- CST 结束：`2026-08-29 00:32:39`
- 总耗时：`2046725` 毫秒（34 分 6.725 秒）
- 场景命令状态：1/2/3/4 均为 `0`
- 清理命令状态：1/2/3/4 均为 `0`
- TestBatchJob：12/12 通过，无失败或超时
- 更新结果场景数：4
- 总体状态：失败

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | `make scenario-1`，默认三调度器，Volcano Agent | 2026-08-28 23:58:33 – 2026-08-29 00:08:54 | 621423 | `from=1787932713666 to=1787933246794` | `results/scenario-1` | 失败：缺少 `kueue` 结果目录 |
| 2 | `make scenario-2`，默认三调度器，Volcano Agent | 2026-08-29 00:08:54 – 2026-08-29 00:16:46 | 472392 | `from=1787933334716 to=1787933743321` | `results/scenario-2` | 通过 |
| 3 | `make scenario-3`，默认三调度器，Volcano Agent | 2026-08-29 00:16:46 – 2026-08-29 00:24:39 | 472652 | `from=1787933807123 to=1787934215838` | `results/scenario-3` | 通过 |
| 4 | `make scenario-4`，默认三调度器，Volcano Agent | 2026-08-29 00:24:39 – 2026-08-29 00:32:39 | 480160 | `from=1787934279789 to=1787934696132` | `results/scenario-4` | 通过 |

## 3. 问题说明

场景 1 的 `make scenario-1`、三个 `TestBatchJob` 和 `make down` 均成功，但最终 `results/scenario-1` 缺少技能要求的 `kueue` 结果目录，因此按结果完整性规则判定场景 1 不通过，整体结论为失败。直接证据位于 `/tmp/scenario-test-20260828235833-gv8P3Q/01-scenario-1.log`、`scenario-status.tsv` 及远端仓库 `results/scenario-1` 目录清单。场景 2–4 的必需结果目录均存在。未发现影响结论的 Dashboard 图片异常。

## 4. 最终结论

失败。实际执行场景 1、2、3、4；12 个 TestBatchJob 全部通过，4 个场景均完成并成功恢复 idle baseline，4 个场景结果均发生更新。但场景 1 缺少必需的 `results/scenario-1/kueue` 结果目录，因此未满足整体通过条件。
