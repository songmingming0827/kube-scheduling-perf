# 完整性测试报告（失败）

## 1. 执行概要

- 执行时间：2026-08-25 17:26:29 ～ 18:52:08（Asia/Shanghai）
- 测试提交：c3ee866
- 批任务结果：24/24 通过，0 失败
- 回收：`make down` 返回 0；Kueue、Volcano、YuniKorn 和 audit exporter 均恢复为 1/1。
- 完整性结论：失败。场景 4、8 的 Volcano 审计指标等待失败，且后续结果保存受到遗留 staging 目录影响，导致部分 scheduler 结果未落盘。

## 2. 八个场景的时间边界与结果目录

| 场景 | 时间边界（epoch ms） | 已保存结果 |
| --- | --- | --- |
| scenario-1 | 1787650015473 ～ 1787650543546 | kueue、volcano、yunikorn |
| scenario-2 | 1787650625514 ～ 1787651039110 | kueue、volcano、yunikorn |
| scenario-3 | 1787651096527 ～ 1787651498620 | kueue、volcano、yunikorn |
| scenario-4 | 1787651557560 ～ 1787652125164 | kueue、yunikorn |
| scenario-5 | 1787652174089 ～ 1787653005744 | volcano、yunikorn |
| scenario-6 | 1787653097960 ～ 1787653567153 | volcano、yunikorn |
| scenario-7 | 1787653622520 ～ 1787654122575 | volcano、yunikorn |
| scenario-8 | 1787654181489 ～ 1787655011801 | yunikorn |

## 3. 问题说明

1. 场景 4 和场景 8 的 Volcano 批任务均通过，但结束阶段 `wait-audit-metrics-scraped` 返回 Error 1，进而使 `end-volcano` 失败。
2. 该失败使相应结果保存不完整；遗留的 `tmp/result-*-staging` 随后阻断 Kueue 或 YuniKorn 的保存。
3. 因此批任务通过不代表结果采集完整，本轮不能作为完整性能数据集使用。

## 4. 最终结论

执行流程与环境回收完成，所有 24 个批任务通过，基线恢复正常；但结果落盘不完整，完整性测试失败。需先修复 Volcano 审计指标等待及 staging 清理链路，再重新执行完整性测试。
