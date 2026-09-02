# PR Title

```text
perf(nodeorder): run score plugins in a single node traversal
```

#### What type of PR is this?

/kind feature

/area performance

#### What this PR does / why we need it:

Before this change, `BatchNodeOrderFn` runs the scoring phase roughly as follows:

(Relevant code: `pkg/scheduler/plugins/predicates/predicates.go` and `pkg/scheduler/plugins/nodeorder/nodeorder.go`)

```text
for each registered plugin {
    run PreScore
    if PreScore returns Skip {
        continue
    }

    CalculatePluginScore {
        score all candidate nodes with 16 workers
        store the score of each node in nodeScoreList

        if the plugin implements ScoreExtensions {
            run NormalizeScore to update nodeScoreList in place
        }

        apply the plugin weight to nodeScoreList and return the per-node scores
    }

    add the plugin's scores to the total score of each node
}
```

With `N` score plugins and `M` candidate nodes, the scheduler still needs to execute `N * M` `Score` calls. Using a separate `NodeScoreList` for each plugin is also necessary because each plugin may implement `NormalizeScore`. The main issue is how these calls are organized:

1. Each plugin starts a separate parallel node traversal, repeatedly creating workers, contexts, and error channels.
2. The same set of `NodeInfo` objects is traversed again for every plugin, increasing memory access and reducing CPU cache locality.
3. Although each plugin scores nodes with 16 workers, plugins are processed one at a time. The next plugin cannot start scoring until the current plugin completes `NormalizeScore`.

This PR scores all candidate nodes in a single 16-worker traversal. Each worker runs all active score plugins for its current node:

(`CalculatePluginScore` no longer describes the new multi-plugin behavior, so it is replaced by `RunScorePlugins`.)

```text
build the PreScore and Score plugin lists

RunScorePlugins {
    run PreScore plugins serially and record skipped plugins
    build activePlugins

    score all candidate nodes with 16 workers {
        for each plugin in activePlugins {
            store the plugin's raw score for the current node in
            activePlugins[pluginIndex].scores[nodeIndex]
        }
    }

    run NormalizeScore for active plugins in parallel
    validate scores, apply plugin weights, and aggregate each node's total score in parallel
}
```

Compared with the previous implementation, this PR:

1. Score N*M times as well, but only starts  one parallel node traversal for all score plugins.
2. Processes all plugins for the same `NodeInfo` within one worker, improving CPU cache locality.
3. Normalizes plugins in parallel and aggregates weighted totals across nodes in parallel.

This reduces repeated parallelization and synchronization overhead and improves scheduling performance in large clusters.

#### Which issue(s) this PR fixes:

N/A

#### Special notes for your reviewer:

AI tools were used to assist with the implementation and tests. I reviewed all generated changes and completed the tests and benchmark documented below.

#### Tests

The following unit and race tests passed. They cover the shared scoring helper, the volcano-scheduler `nodeorder` and `predicates` paths, and the agent-scheduler `predicates` adapter:

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

The tests cover the following behavior:

- All `PreScore` calls complete before `Score` starts, and all `Score` calls complete before `NormalizeScore` starts.
- When `PreScore` returns `Skip`, only the corresponding plugin's `Score` and `NormalizeScore` phases are skipped.
- Raw scores are normalized, weighted, and aggregated correctly. If any phase fails, no scores are returned and all partially computed results are discarded.
- The fused `nodeorder` and `predicates` paths produce the same results as the previous per-plugin execution, including when `LeastAllocated` and `MostAllocated` are enabled together.
- The agent-scheduler runs `PreScore` and `Score` only for candidate nodes.

#### Performance benchmark

The benchmark compares the original implementation with this PR. Each version was run seven times. The runs with the highest and lowest throughput were excluded, and the remaining five runs were averaged.

- Environment:

  - Machine: one VM with 32 vCPUs and 64 GiB of memory
  - Nodes: 1,000 KWOK nodes
  - Workload: 20 jobs, 500 replicas per job, 10,000 pods in total
  - Scheduler: agent-scheduler with 4 workers
  - Scheduling cycle interval: `0`, to avoid phase effects from a fixed scheduling interval
  - Volcano version: `master`

- Metrics:

  - Pod latency = binding timestamp - creation timestamp
  - P50/P90/P99 are calculated for each run using the nearest-rank method; the table reports the average of the five retained runs
  - Binding window = timestamp of the last binding - timestamp of the first binding
  - Throughput = total number of pods / binding window
  - Pod creation and binding timestamps are read directly from `audit.log` instead of being estimated from Prometheus histograms

| Version | Runs | Raw P50 avg | Raw P90 avg | Raw P99 avg | Throughput avg | Binding window avg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| master baseline | 5 | 2265.296 ms | 3704.348 ms | 3961.418 ms | 762.772 pods/s | 13.1102 s |
| master with this PR | 5 | 1115.628 ms | 1554.856 ms | 1637.436 ms | 936.232 pods/s | 10.6820 s |
| Improvement | - | 50.75% lower | 58.03% lower | 58.67% lower | 22.74% higher | 18.52% lower |

#### Does this PR introduce a user-facing change?

```release-note
NONE
```
