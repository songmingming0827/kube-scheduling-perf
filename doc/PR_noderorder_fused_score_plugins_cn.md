# PR 标题

```text
perf(nodeorder): run score plugins in a single node traversal
```

#### 这是什么类型的 PR？

/kind feature

/area performance

#### 这个 PR 做了什么？为什么需要它？

我观察到在原实现中，BatchNodeOrderFn的打分逻辑如下

(代码位置：pkg/scheduler/plugins/predicates/predicates.go ，pkg/scheduler/plugins/nodeorder/nodeorder.go)

```
遍历所有注册的插件plugins {
    prescore
    如果prescore返回skip，则continue
    对每个不被跳过的插件执行一次打分CalculatePluginScore{
        16并发遍历所有候选node进行score -> nodeScoreList记录每个node的分数
        如果plugin定义了ScoreExtensions，则执行NormalizeScore，原地修改nodeScoreList
        遍历nodeScoreList按照plugin的weight，计算最终nodeScores，返回nodeScores
    }
    获取到该plugin的nodeScores后，累加进总的nodeScores（记录node和分数的映射关系）
}
```

每个插件都要对node进行打分，如果有N个插件，M个node，则需要打分N*M次，并且使用 `nodeScoreList` 记录每个插件对M个node的打分情况，方便执行则执行 `NormalizeScore` ，这样的思路本身没有问题；但是原实现由如下问题：

1. 每个插件单独启动一轮节点并发，重复创建 worker、context、error channel，造成额外开销
2. 同一批 `NodeInfo` 被不同插件反复遍历和读取，增加内存访问并降低 CPU Cache 局部性。
3. 单个插件的 Score 是 16 路并发，但各插件 `Normalize` 串行执行，且下一个插件的 Score 也必须等待 `Normalize `完成。



这个 PR 在一个16路并发循环中，给所有候选node打分，并对每个候选node，一次执行所有plugins的打分算法，具体逻辑如下：

(由于改造后的 `CalculatePluginScore` 语义上不再是对单个plugin打分，所以改成 `RunScorePlugins`)

```
组装 prescore、score插件列表
RunScorePlugins{
    串行 prescore，记录 skip 插件，得到activePlugins
    16并发遍历所有候选node{
        遍历所有activePlugins{
            将当前插件对当前node的原始分数记录到activePlugins[pluginIndex].scores[index]
        }
    }  
    并行遍历activePlugins执行NormalizeScore
    再进行weight处理得到nodeScores，即得到每个node的加权总分
}
```

PR相对于原实现：

1. 同样打分N*M次，但是只用启动一轮节点并发
2. `NodeInfo` 只会被一路并发读取
3. 并行遍历 node，每个 node 内依次执行插件；并行计算`Normalize `；并行计算每个节点在每个plugin下基于weight的总得分情况；这在大集群中受益非常明显

#### 这个 PR 修复了哪些 Issue？

无

#### 给 Reviewer 的特别说明

本 PR 使用 ai 辅助代码编写和测试；提交者已审查所有修改，并完成下述测试和 benchmark。

#### 测试

以下单元测试和 race test 已通过：

```bash
go test ./pkg/scheduler/plugins/util/nodescore \
  ./pkg/scheduler/plugins/nodeorder \
  ./pkg/scheduler/plugins/predicates \
  ./pkg/agentscheduler/plugins/predicates

go test -race ./pkg/scheduler/plugins/util/nodescore \
  ./pkg/scheduler/plugins/nodeorder \
  ./pkg/scheduler/plugins/predicates \
  ./pkg/agentscheduler/plugins/predicates
```

测试覆盖以下行为：

- 所有 `PreScore` 完成后才开始 `Score`，所有 `Score` 完成后才开始 `NormalizeScore`
- `PreScore` 返回 `Skip` 时，只跳过对应插件的 `Score` 和 `NormalizeScore`
- 原始分数经过 `NormalizeScore` 和 weight 处理后正确汇总，任一阶段出错时不返回打分结果，已计算的部分结果全部丢弃。
- `nodeorder` 和 `predicates` 融合前后的打分结果一致，包括 `LeastAllocated` / `MostAllocated` 同时启用的情况
- agent-scheduler 只对候选node执行 `PreScore` 和 `Score`

#### 性能测试

这里通过对比benchmark实验对比，原实现和优化后的性能差异；为了防止波动，每个版本执行7次，去除吞吐量最高和最低各1次，对剩余5次取平均值。

- Environment:

  - VM: 32vCPU, 64G single machine

  - KWOK nodes: 1000 nodes

  - Test scenario: 20 jobs, 500 replicas per job, 10000 pods total

  - Pod 延迟 = binding 时间 − create 时间

    P50/P90/P99 每轮使用 nearest-rank 方法计算，表中为五轮结果的平均值

    binding window  计算公式：最后一个发生binding的时间 - 第一个发生binding的时间

    Throughput 计算公式：总pod / binding window

  - pod的binding时间和create时间直接读取audit.log，而不是使用 Prometheus Histogram 估算，保证数据读取更精确

| Version | Runs | Raw P50 avg | Raw P90 avg | Raw P99 avg | Throughput avg | Binding window avg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| master baseline | 5 | 2265.296 ms | 3704.348 ms | 3961.418 ms | 762.772 pods/s | 13.1102 s |
| master with this PR | 5 | 1115.628 ms | 1554.856 ms | 1637.436 ms | 936.232 pod/s | 10.6820 s |
| Improvement | - | 50.75% lower | 58.03% lower | 58.67% lower | 22.74% higher | 18.52% lower |

- 本次测试使用了的调度器：agent-scheduler；Agent Scheduler Worker：`4` ；为了避免测试波动，消除固定调度周期的相位影响，调度周期间隔设置为0）；volcano版本使用master分支。

#### 这个 PR 是否引入用户可见的变更？

```release-note
无
```
