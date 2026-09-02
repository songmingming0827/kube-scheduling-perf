# PR Title

```text
perf(scheduler): remove lock contention from parallel node scoring
```

#### What type of PR is this?

/kind feature

/area performance

#### What this PR does and why it is needed

`PrioritizeNodes` already uses `workqueue.ParallelizeUntil` with 16 workers to score nodes in parallel. However, in the original implementation, each worker had to acquire the same `sync.Mutex` after scoring a node before writing the results to `pluginNodeScoreMap` and `nodeOrderScoreMap`. In large clusters, this shared lock causes contention on the node scoring hot path and limits the benefits of parallel scoring.

This PR separates node order scoring from the legacy node map phase:

- `NodeOrderFn` continues to run in parallel. Each worker writes its `orderScore` to an independent index in a preallocated `[]float64`. Errors are only logged, and the corresponding score remains 0, so no shared lock is required.
- After `workqueue.ParallelizeUntil` completes, `PrioritizeNodes` calls `NodeOrderMapFn` serially for every node, in input order. `NodeOrderMapFn` invokes the registered `NodeMapFn` callbacks and returns their per-plugin map scores.
- After collecting the map scores, the existing reduce phase and batch scoring phase continue unchanged.
- When no `NodeMapFn` is registered, `NodeOrderMapFn` returns immediately to avoid unnecessary plugin tier traversal.
- The final aggregation reads each `orderScore` directly by node index, without constructing or looking up `nodeOrderScoreMap`.

This removes the shared `sync.Mutex` from the parallel node order scoring path without executing legacy `NodeMapFn` callbacks concurrently.

As @hzxuzhonghu pointed out during the review of #5491, `NodeMapFn` callbacks do not provide concurrency-safety guarantees and therefore must not be invoked concurrently. This PR addresses that concern directly: only `NodeOrderFn` runs in parallel, while `NodeMapFn` runs serially after the parallel phase completes. Therefore, multiple workers can no longer execute map callbacks concurrently in the `PrioritizeNodes` call path.

The same execution model is applied to both the Volcano scheduler and the agent scheduler.

#### Which issue(s) this PR fixes

Partially addresses #5082.

Partially addresses #5494.

Builds on #5491 and addresses the concurrency safety review feedback raised there.

#### Special notes for reviewers

Compared with #5491, this version preserves lock-free parallel node order scoring while moving legacy `NodeMapFn` callbacks out of the parallel section and executing them serially, addressing the concurrency safety concern raised during review.

AI disclosure: ai assisted with code migration, testing, and PR preparation. I reviewed all changes and completed the tests and benchmarks listed below.

#### Tests

The following unit tests and race test passed:

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

The tests cover the following behavior:

- Combined results from batch scores, order scores, and reduce scores.
- Independent error handling for `NodeOrderFn` and `NodeMapFn`: a failure in one does not suppress the scoring result from the other.
- Behavior when the batch phase or reduce phase returns an error.
- Result integrity when `NodeOrderFn` runs in parallel across a large number of nodes.
- Serial execution of `NodeMapFn` in input node order.

#### Performance test

#5491 demonstrated that removing the worker lock from `PrioritizeNodes` can improve scheduling latency and throughput in large-node scenarios. Because this PR changes the execution model of the map phase, the results from #5491 cannot be directly applied to this version. The updated benchmark results are as follows:

- Environment:

  - VM: single machine with 32 vCPUs and 64 GB of memory

  - KWOK nodes: 1,000

  - Test scenario: 50 jobs, 16 replicas per job, 800 pods in total

  - Pod binding and creation timestamps were read directly from `audit.log` instead of being estimated using Prometheus histograms.

  - Pod latency = binding timestamp - creation timestamp

    P50/P90/P99 were calculated per run using the nearest-rank method. The table reports the averages across five runs.

    Binding window = timestamp of the last binding - timestamp of the first binding

    Throughput = total number of pods / binding window

| Version | Runs | Raw P50 avg | Raw P90 avg | Raw P99 avg | Throughput avg | Binding window avg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| v1.15.1 baseline | 5 | 346.98 ms | 536.64 ms | 605.27 ms | 625.38 pods/s | 1.280s |
| v1.15.1 with this PR | 5 | 322.05 ms | 498.25 ms | 572.17 ms | 679.20 pods/s | 1.178s |
| Improvement | - | 7.19% lower | 7.15% lower | 5.47% lower | 8.61% higher | 7.95% lower |

- The differences from the results in #5491 are expected because the benchmarks used different plugins (this test only enabled `predicate`, `priority`, and `capacity`), different scheduling cycle settings (the scheduling interval was set to 0 to reduce benchmark variance and eliminate phase effects caused by a fixed scheduling interval), and different Volcano versions. Both the v1.15.1 baseline and v1.15.1 with this PR were tested in the same environment.

#### Does this PR introduce a user-facing change?

```release-note
Node order scoring and node map scoring are now decoupled. As a result, `PrioritizeNodes` accepts `NodeOrderFn` separately, and `NodeOrderMapFn` returns only per-plugin map scores. Errors in either phase no longer suppress scores from the other phase.
```
