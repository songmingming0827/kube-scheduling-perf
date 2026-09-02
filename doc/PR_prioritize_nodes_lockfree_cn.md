# PR 标题

```text
perf(scheduler): remove lock contention from parallel node scoring
```

#### 这是什么类型的 PR？

/kind feature

/area performance

#### 这个 PR 做了什么？为什么需要它？

`PrioritizeNodes` 已经通过 `workqueue.ParallelizeUntil` 使用 16 个 worker 并行执行逐节点打分。但是在原实现中，每个 worker 完成打分后，都需要获取同一个 `sync.Mutex`，然后才能向 `pluginNodeScoreMap` 和 `nodeOrderScoreMap` 写入结果。在大规模集群中，这个共享锁会导致 node scoring 热路径出现 lock contention，并限制并行打分的收益。

这个 PR 将 node order scoring 与 legacy node map phase 分离：

- `NodeOrderFn` 继续并行执行。每个 worker 将 `orderScore` 写入预分配 `[]float64` 中与节点下标对应的独立位置；错误仅记录日志，对应分数保持为 0，因此不需要共享锁。
- `workqueue.ParallelizeUntil` 完成后，`PrioritizeNodes` 按输入顺序为每个节点串行调用 `NodeOrderMapFn`。`NodeOrderMapFn` 调用已注册的 `NodeMapFn` callback，并返回各插件对应的 map score。
- map score 收集完成后，继续执行原有的 reduce phase 和 batch scoring phase。
- 当没有注册 `NodeMapFn` 时，`NodeOrderMapFn` 会立即返回，避免不必要的 plugin tier 遍历。
- 最终汇总直接按节点下标读取 `orderScore`，不再构造或查询 `nodeOrderScoreMap`。

这个实现从并行 node order scoring 路径中移除了共享 `sync.Mutex`，同时不会并发执行 legacy `NodeMapFn` callback。

@hzxuzhonghu 在 #5491 的 review 中指出，`NodeMapFn` callback 不提供并发安全保证，因此不能并发调用。这个 PR 直接处理了该问题：只有 `NodeOrderFn` 并行执行，`NodeMapFn` 在并行阶段结束后串行执行。因此，在 `PrioritizeNodes` 这条调用路径中，不再存在多个 worker 并发执行 map callback 的风险。

相同的执行模型同时应用于 Volcano scheduler 和 agent scheduler。

#### 这个 PR 修复了哪些 Issue？

Partially addresses #5082.

Partially addresses #5494.

基于 #5491，并处理其中提出的 concurrency safety review feedback。

#### 给 Reviewer 的特别说明

与 #5491 相比，这个版本保留了 lock-free parallel node order scoring，同时将 legacy `NodeMapFn` callback 移出并行区间并改为串行执行，从而处理 review 中提出的 concurrency safety 问题。

AI 使用说明：本 PR 使用 ai 辅助代码迁移、测试和 PR 文档准备；提交者已审查所有修改，并完成下述测试和 benchmark。

#### 测试

以下单元测试和 race test 已通过：

```bash
go test ./pkg/scheduler/util \
  ./pkg/scheduler/framework \
  ./pkg/agentscheduler/framework \
  ./pkg/scheduler/actions/allocate \
  ./pkg/scheduler/actions/backfill \
  ./pkg/scheduler/actions/preempt \
  ./pkg/scheduler/actions/utils \
  ./pkg/agentscheduler/actions/allocate

go test -race ./pkg/scheduler/util \
  -run 'TestPrioritizeNodes(NoRace)?$' \
  -count=1
```

测试覆盖以下行为：

- batch score、order score 和 reduce score 的组合结果。
- `NodeOrderFn` 与 `NodeMapFn` 的错误相互独立：一方失败不会抑制另一方的评分结果。
- batch phase 或 reduce phase 返回错误时的行为。
- 大量节点并行执行 `NodeOrderFn` 时的结果完整性。
- `NodeMapFn` 按输入节点顺序串行执行。

#### 性能测试

#5491 已验证移除 `PrioritizeNodes` 中的 worker lock 可以改善大规模节点场景下的 scheduling latency 和 throughput。由于这个 PR 调整了 map phase 的执行模型，因此需要使用相同测试场景重新测量，不能直接将 #5491 的结果作为这个版本的结果。更新后的 benchmark 结果补充到这里：

- Environment:

  - VM: 32vCPU, 64G single machine

  - KWOK nodes: 1000 nodes

  - Test scenario: 50 jobs, 16 replicas per job, 800 pods total

  - pod的binding时间和create时间直接读取audit.log，而不是使用 Prometheus Histogram 估算

  - Pod 延迟 = binding 时间 − create 时间

    P50/P90/P99 每轮使用 nearest-rank 方法计算，表中为五轮结果的平均值

    binding window  计算公式：最后一个发生binding的时间 - 第一个发生binding的时间

    Throughput 计算公式：总pod / binding window

| Version | Runs | Raw P50 avg | Raw P90 avg | Raw P99 avg | Throughput avg | Binding window avg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| v1.15.1 baseline | 5 | 346.98 ms | 536.64 ms | 605.27 ms | 625.38 pods/s | 1.280s |
| v1.15.1 with this PR | 5 | 322.05 ms | 498.25 ms | 572.17 ms | 679.20 pods/s | 1.178s |
| Improvement | - | 7.19% lower | 7.15% lower | 5.47% lower | 8.61% higher | 7.95% lower |

- 需要提到和 #5491 结果相差较大的原因是包括，使用插件不同（本次测试仅使用了predicate、priority、capacity），调度周期设置不同（为了避免测试波动，消除固定调度周期的相位影响，调度周期间隔设置为0），volcano版本不同等；但v1.15.1 baseline和v1.15.1 with this PR均是基于相同的环境下测试的。

#### 这个 PR 是否引入用户可见的变更？

```release-note
Node order scoring 与 node map scoring 现已解耦。因此，`PrioritizeNodes` 单独接收 `NodeOrderFn`，`NodeOrderMapFn` 仅返回各插件的 map score；任一阶段发生错误时，不再抑制另一阶段的评分结果。
```
