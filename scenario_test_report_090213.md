# 场景测试报告（通过）

## 1. 执行概要

- 测试 Commit：2873e44
- 请求场景顺序：1、2、3、4
- 精确命令：make scenario-1、make scenario-2、make scenario-3、make scenario-4
- Volcano 调度模式：VOLCANO_MODE=agent，使用 agent-scheduler
- tmux 会话：scenario-test-20260902131453
- 总体 CST 时间：2026-09-02 13:14:53 至 2026-09-02 13:48:57
- 总耗时：00:34:03.744
- 场景退出码：场景 1（make 0，down 0）；场景 2（make 0，down 0）；场景 3（make 0，down 0）；场景 4（make 0，down 0）
- 通过 Case：12/12（每个场景 3 个 TestBatchJob Case）
- 更新结果：4/4 个请求场景
- 总体状态：通过

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | agent；队列 1、Job 10000、每 Job Pod 1 | 13:14:53–13:25:18 | 624.419 秒 | 1788326094082–1788326629981 | results/scenario-1（含 volcano-agent） | 通过 |
| 2 | agent；队列 1、Job 500、每 Job Pod 20 | 13:25:18–13:33:08 | 470.351 秒 | 1788326718514–1788327126136 | results/scenario-2（含 volcano-agent） | 通过 |
| 3 | agent；队列 1、Job 20、每 Job Pod 500 | 13:33:08–13:40:55 | 466.543 秒 | 1788327188877–1788327592607 | results/scenario-3（含 volcano-agent） | 通过 |
| 4 | agent；队列 1、Job 1、每 Job Pod 10000 | 13:40:55–13:48:57 | 482.332 秒 | 1788327655434–1788328073878 | results/scenario-4（含 volcano-agent） | 通过 |

## 3. 问题说明

未发现影响结论的问题。所有场景的 make 与后续 make down 均成功；最终常驻集群基线验证通过。运行证据保存在 /tmp/kube-scheduling-perf-scenario-20260902131453，其中包含各场景 CST 日志、退出码和状态记录。

## 4. 最终结论

通过。场景 1 至场景 4 全部执行成功，12/12 个 Case 通过，4 个结果目录均已更新并包含 volcano-agent 结果；每个场景后均成功执行 make down，最终调度器、Audit Exporter、1001 个节点和基础组件均恢复到空闲基线。
