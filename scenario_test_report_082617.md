# 场景测试报告（失败）

## 1. 执行概要

- 测试提交：`0489ce50a8b342a374a73e6f2b9cc72a8c9c9ce0`
- 请求顺序：场景 1、2、3、4
- 执行命令：依次执行 `make scenario-1`、`make down`，直至 `make scenario-4`、`make down`
- tmux 会话：`scenario-test-20260826172837`
- CST 起止：`2026-08-26 17:28:37` 至 `2026-08-26 18:01:12`
- 总耗时：`00:32:35.156`
- 场景/清理退出码：1/0/0，2/0/0，3/0/0，4/0/0（格式为场景/ make / down）
- 通过 Case：`12/12`（每个场景的 Kueue、Volcano、YuniKorn `TestBatchJob` 均通过）
- 更新结果场景：`4`；四个场景均缺少 Kueue 结果子目录
- 最终状态：`失败`

## 2. 场景时间边界与结果目录

| 场景 | 模式与参数 | CST（UTC+8）时间边界 | 耗时 | 指标时间窗（毫秒） | 结果目录 | 结果 |
|---|---|---|---:|---|---|---|
| 1 | `VOLCANO_MODE=agent`；`queues=1, jobs/queue=10000, pods/job=1` | `17:28:37`–`17:38:30` | `592.946s` | `1787736517952`–`1787737035525` | `results/scenario-1`（缺 `kueue`） | 失败：结果不完整 |
| 2 | `VOLCANO_MODE=agent`；`queues=1, jobs/queue=500, pods/job=20` | `17:38:30`–`17:46:02` | `451.991s` | `1787737110913`–`1787737505686` | `results/scenario-2`（缺 `kueue`） | 失败：结果不完整 |
| 3 | `VOLCANO_MODE=agent`；`queues=1, jobs/queue=20, pods/job=500` | `17:46:02`–`17:53:31` | `449.135s` | `1787737562913`–`1787737954492` | `results/scenario-3`（缺 `kueue`） | 失败：结果不完整 |
| 4 | `VOLCANO_MODE=agent`；`queues=1, jobs/queue=1, pods/job=10000` | `17:53:31`–`18:01:12` | `460.986s` | `1787738012070`–`1787738415151` | `results/scenario-4`（缺 `kueue`） | 失败：结果不完整 |

## 3. 问题说明

四个场景的三项 `TestBatchJob` 均通过，四次 `make down` 均成功，且每次清理后的 `verify-base.sh 1000` 通过。阻断问题发生在结果保存阶段：`make save-scheduler-result SCHEDULER=kueue` 因 `./tmp/result-kueue-staging` 已存在而失败，随后流程仍继续保存 Volcano/YuniKorn 结果，因此四个 `results/scenario-N/kueue` 目录均缺失。该问题使结果目录不满足测试判定条件。`job-submission.png` 四个场景均存在，不属于非阻断图片异常。未在本流程中修复源代码、清理 staging 或重跑场景。

最终基线核验通过：`verify-base.sh 1000` 与 `verify-schedulers.sh` 均成功；节点为 `1001/1001 Ready`，调度器和 Audit Exporter 恢复到一副本基线。

## 4. 最终结论

`失败`。场景 1–4 均实际执行，12/12 个 `TestBatchJob` Case 通过，四个结果目录有更新，且每个场景后的空闲基线恢复成功；但四个场景均缺少必需的 Kueue 结果子目录，不能判定整体通过。
