# 背景

## 调度器版本

![image-20260814102915994](images/versions.png)

## 参数配置	

| 对比方案        | 组件与作用                             | CPU request/limit | Kubernetes client QPS/Burst                               | 并发或Worker                                      | 调度周期                 |
| --------------- | -------------------------------------- | ----------------- | --------------------------------------------------------- | ------------------------------------------------- | ------------------------ |
| Kueue 非 Gang   | `kube-scheduler`                       | `500m / 8`        | `1000/1000`                                               | /                                                 | 事件驱动，无固定调度周期 |
| Kueue 准入      | `kueue-controller-manager`             | `500m / 8`        | `1000/1000`                                               | job、workload等worker均为100                      |                          |
| kueue           | kube-controller-manager                | `500m / 8`        | `1000/1000`                                               | Job Controller Worker=100                         |                          |
| Kueue Gang      | `coscheduling`，实际调度 Pod           | `500m / 8`        | `1000/1000`                                               | /                                                 | 事件驱动，无固定调度周期 |
| Kueue Gang 辅助 | `scheduler-plugins-controller`         | `500m / 8`        | `1000/1000`                                               | workers=100                                       |                          |
| Volcano         | agent-scheduler、Controller、Admission | `500m / 8`        | `1000/1000`（controller 中配置 volcano client 1000/1000） | Controller 的 Job、GC、PodGroup Worker 均为 100； | 事件驱动，无固定调度周期 |
| YuniKorn        | Scheduler                              | `500m / 8`        | `1000/1000`                                               | /                                                 | 200ms (是默认值1s)       |
| YuniKorn        | Admission Controller                   | `500m / 8`        | `1000/1000`                                               | /                                                 |                          |
| YuniKorn        | kube-controller-manager                | `500m / 8`        | `1000/1000`                                               | Job Controller Worker=100                         |                          |

> Job Controller Worker=100 表示 启动 100 个并发 worker，最多同时协调约 100 个不同的 Kubernetes Job

### volcano配置

- 固定 Actions：`allocate`
- 固定 Plugins： `predicates` 和 `nodeorder`；
- agent-scheduler不测试`gang`，`preempt`

## 数据收集方法优化

利用 **audit-exporter** 从 kube-apiserver 中收集信息并记录在 audit.log 来准确地记录具体性能。

使用经过版本优化过后的开源测试工具 **kube-scheduling-perf** 获得测试结果。

# 测试

测试结果图来自：http://104.105.137.213:31005/grafana

## 测试cases

本次测试benchmark如下图，在10k总Pod量下，分别在启用/不启用**Gang** Scheduling的情况下，调整Job数量和每Job的Pod数量。

![image-20260814103140184](images/cases.png)

## 测试结果

> 说明，为了放大三个调度器在初始创建时的细节，可能会截断最慢的调度器，这是有意为之

## 非gang场景

### 场景1

10000个job，每个Job只有1个Pod，有以下现象：

![job-submission](images/agent-scheduler-master/scenario-1/job-submission-agent.png)

- created和scheduled曲线基本重合，调度阶段不是主要瓶颈，此时性能**瓶颈为创建阶段**。
  - 原因：**k8s客户端的qps/burst为100/200**；提交时以job为整体单位提交，故提交耗时最少要(10000 - Burst 200) / QPS 100 ≈ 98 秒。
    - vc-controller创建pod耗时被掩盖：vc-controller的qps/burst为1000/1000，故创建耗时最少要(10000 - Burst 1000) / QPS 1000 ≈ 9 秒。同理vc-Admission ≈ 9 秒。

    - 由于客户端的qps，导致**pod创建速度**因j提交限制到了100pod/s，scheduler的qps是1000所以处理速度大于pod创建速度，所以曲线重合

- **volcano整体耗时100s**

### 场景2

500个job，每个Job有20个Pod，有以下现象：

![job-submission](images/agent-scheduler-master/scenario-2/job-submission-agent.png)

1. kueue、yunikron、volcano均适用原生job、创建job统一由kube-controller负责，所以创建pod速率基本相同；
2. Agent Scheduler 是一个基于worker的并发调度循环 ，这里设置--scheduler-worker-count = 4，测试没有发现“conflict”现象；
3. 分析agent-scheduler慢的原因有两个：
   1. 结合issue：https://github.com/volcano-sh/volcano/issues/5494 提出的snapshot问题，当前 agent-scheduler每调度一个 Pod 都会全量遍历节点两次，并维护、克隆 Volcano/Kubernetes 两套 `NodeInfo`。多 worker 时每个 worker还有独立 snapshot，成本很大。优化建议如下：
      1. **最优**：统一两套 NodeInfo 的数据，修改snapshot为只读操作；
      2. 只复制发生变化的节点，未变化的 `NodeInfo` 直接复用。
   2. 打分路径过于厚重，优化打分路径（已提pr）
   3. 优化binder，agent-scheduler相较于kube-scheduler的优势就是多个worker并发执行，但是由于binder的限制，worker数超过6后，冲突就会变多；特别是优化打分路径后，worker数超过4后，冲突就会限制scheduler的调度性能；优化建议如下：
      1. 当前 Binder 根据 `BindGeneration` 判断，同一代节点基本只允许一个结果通过；其他结果即使节点资源仍足够，也会被判 conflict。可以设计失败则直接尝试第二、第三候选节点，不要先进入 Binder 再重新排队。

### 场景3

20个job，每个Job有500个Pod，有以下现象：

![job-submission](images/agent-scheduler-master/scenario-3/job-submission-agent.png)

- 同场景2

### 场景4

只有1个job，每个Job有10000个Pod，有以下现象：

![job-submission](images/agent-scheduler-master/scenario-4/job-submission-agent.png)

- kube-controller创建pod速度存在瓶颈

  - 三者创建pod的controller都是kube-controller，**环境设置：**job-controller worker为100；1. 单个 Job 每次同步最多创建 `500` 个 Pod。2. 同一个 Job key 不会被多个 worker 同时处理。3. Pod 事件触发的下一轮 Job 同步有 `1s` 批处理周期。
  - 场景 3 有 20 个独立 Job key，每个 Job 正好只需要一轮 500 Pod。
  - 场景 4 只有一个 Job key，需要 `10000 / 500 = 20` 轮同步。从首轮到末轮约有 19 个一秒间隔，实测正好约 19.1–19.5 秒。

  

