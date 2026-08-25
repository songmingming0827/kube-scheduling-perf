# 完整性测试报告（失败）

## 1. 执行概要

- 测试 Commit：`83e8c19d2cf823e4546f425aa9bb980b3f262b14`
- 命令：`make`（tmux：`full-integrity-20260825171115`）
- CST 开始/结束：2026-08-25 17:12:33 / 2026-08-25 17:22:43；耗时 10 分 10.589 秒
- `make` 退出码：2；`make down` 退出码：0
- 已通过 Case：3/24；当前运行更新的场景：1/8
- 总体状态：失败

## 2. 八个场景的时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---|---|---|---|
| 1 | 非 Gang，1×10000×1 | 2026-08-25 17:12:33 - 2026-08-25 17:22:38 | 10 分 5 秒 | 见 results/scenario-1/result-window.txt | results/scenario-1 | 失败：3 个 Case 通过，Kueue/YuniKorn 结果暂存目录残留 |
| 2 | 非 Gang，1×500×20 | 未执行 | - | - | results/scenario-2（未更新） | 未执行 |
| 3 | 非 Gang，1×20×500 | 未执行 | - | - | results/scenario-3（未更新） | 未执行 |
| 4 | 非 Gang，1×1×10000 | 未执行 | - | - | results/scenario-4（未更新） | 未执行 |
| 5 | Gang，1×10000×1 | 未执行 | - | - | results/scenario-5（未更新） | 未执行 |
| 6 | Gang，1×500×20 | 未执行 | - | - | results/scenario-6（未更新） | 未执行 |
| 7 | Gang，1×20×500 | 未执行 | - | - | results/scenario-7（未更新） | 未执行 |
| 8 | Gang，1×1×10000 | 未执行 | - | - | results/scenario-8（未更新） | 未执行 |

## 3. 问题说明

三个 `TestBatchJob` 均通过：Kueue 138.44s、Volcano 112.55s、YuniKorn 118.42s。结果保存阶段中，`tmp/result-kueue-staging` 和 `tmp/result-yunikorn-staging` 是上一轮失败遗留目录；Makefile 的防覆盖检查在运行结果解析脚本前终止，报 `Scheduler result staging already exists`。因此本轮未能端到端验证新修复。证据位于 `/tmp/full-integrity-20260825171115/make.log` 第 30537-30584 行。

`make down` 已成功执行，实验资源已清理，所有调度器和 Audit Exporter 已恢复为 1/1 空闲基线。

## 4. 最终结论

失败。场景 1 的 3 个 Case 通过，但因前次失败遗留暂存目录而未完成结果保存，后续七个场景没有开始；集群已恢复空闲基线。
