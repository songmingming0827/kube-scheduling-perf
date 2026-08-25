# 完整性测试报告（失败）

## 1. 执行概要

- 测试 Commit：`6bc0be0454826bbb318a8a5a93a72323dc029fe5`
- 命令：`make`（tmux：`full-integrity-20260825163436`）
- CST 开始/结束：2026-08-25 16:36:21 / 2026-08-25 16:46:17；耗时 9 分 55.879 秒
- `make` 退出码：2；`make down` 退出码：0
- 已通过 Case：3/24；当前运行更新的场景：1/8
- 总体状态：失败

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 1 | 非 Gang，1×10000×1 | 2026-08-25 16:36:21 - 2026-08-25 16:46:11 | 9 分 50 秒 | from=1787646981936, to=1787647511509 | results/scenario-1 | 失败：仅 3 个调度器的 Case 通过，保存 Kueue/YuniKorn 指标失败 |
| 2 | 非 Gang，1×500×20 | 未执行 | - | - | results/scenario-2（未更新） | 未执行 |
| 3 | 非 Gang，1×20×500 | 未执行 | - | - | results/scenario-3（未更新） | 未执行 |
| 4 | 非 Gang，1×1×10000 | 未执行 | - | - | results/scenario-4（未更新） | 未执行 |
| 5 | Gang，1×10000×1 | 未执行 | - | - | results/scenario-5（未更新） | 未执行 |
| 6 | Gang，1×500×20 | 未执行 | - | - | results/scenario-6（未更新） | 未执行 |
| 7 | Gang，1×20×500 | 未执行 | - | - | results/scenario-7（未更新） | 未执行 |
| 8 | Gang，1×1×10000 | 未执行 | - | - | results/scenario-8（未更新） | 未执行 |

## 3. 问题说明

场景 1 的 Kueue、Volcano、YuniKorn 三个 `TestBatchJob` 均通过（分别为 138.42s、114.21s、119.99s），但结果保存阶段的 Kueue 和 YuniKorn `save-scheduler-result.sh` 失败，直接错误为 `jq: Cannot index object with null`，Makefile 第 542 行返回 Error 5。Volcano 的调度器指标目录已生成；因三调度器结果不完整，场景 1 判失败，后续七个场景没有开始。证据位于 `/tmp/full-integrity-20260825163436/make.log` 第 30538-30607 行。

`make down` 已成功执行：三类实验资源均已清空，全部调度器和 Audit Exporter 已恢复为 1/1 空闲基线。未发现影响结论的图片采集异常。

## 4. 最终结论

失败。当前运行仅完成场景 1 的 3 个 Case，未达到八个场景、24 个 Case 的完整性测试要求；但集群已完成资源清理并恢复空闲基线。
