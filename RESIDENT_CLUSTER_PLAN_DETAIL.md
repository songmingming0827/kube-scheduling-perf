# 常驻集群方案细节

## 1. 目标

将 kube-scheduling-perf 的被测环境改为固定复用远端常驻集群 `volcano-benchmark-1348`，三套调度方案继续串行运行，不再为 Kueue、Volcano 和 YuniKorn 分别创建临时 Kind 集群。

最终执行模型：

```text
Kueue + Coscheduling
  -> 清理并恢复
Volcano（场景 1～4 使用 Agent Scheduler，场景 5～8 使用 Batch Scheduler）
  -> 清理并恢复
YuniKorn
  -> 清理并恢复
保存汇总结果
```

## 2. 运行使用方式

### 2.1 完整运行

运行八个场景和三个调度器：

```bash
make
```

`make` 串行调用 `scenario-1` 至 `scenario-8`。每个场景依次运行 Kueue、Volcano 和 YuniKorn；Volcano 在场景 1～4 默认使用 Agent Scheduler，在场景 5～8 默认使用 Batch Scheduler。每个场景完成后生成相对 Dashboard、图片、元数据和三套调度器报告。

> Skill：run-full-integrity-test，自动运行完整性测试，生成结果报告，对比图

### 2.2 单场景运行

运行一个场景和全部调度器：

```bash
make scenario-2
```

该命令载入场景 2 的固定参数，再通过 `serial-test` 依次运行三个调度器。`VOLCANO_MODE=auto` 将场景 2 解析为 Agent 模式。完成后更新相对 Dashboard 和以下结果目录：

```text
results/scenario-2/kueue/
results/scenario-2/volcano-agent/
results/scenario-2/yunikorn/
```

> Skill：run-scenario-test，自动运行指定场景，一次会运行三个调度器，然后生成结果报告，对比图

### 2.3 单场景、单调度器运行

例如只使用 Volcano 运行场景 2：

```bash
make scenario-2 SCHEDULERS=volcano
```

单调度器运行仍执行对应的 `prepare → start → end` 流程，但只保存该调度器的结果。例如 Volcano 仅更新：

```text
results/scenario-2/volcano-agent/
├── window.txt
└── report.txt
```

单调度器运行不更新三调度器相对 Dashboard，也不覆盖已有的完整对比结果。Agent 和 Batch 共用逻辑名称 `volcano`、审计标签和 `bench-volcano` namespace，但结果分别写入 `volcano-agent` 和 `volcano` 目录。实际模式同时记录在完整场景的 `envs.txt` 中。将 `SCHEDULERS` 改为 `kueue` 或 `yunikorn` 时写入对应目录。

`scenario-1` 至 `scenario-8` 分别对应八个固定场景。运行异常中断后执行 `make down` 恢复常驻集群基线。

> Skill：run-single-scheduler-scenario-test，自动运行单场景+单调度器，生成结果报告

### 2.4 单场景、单调度器运行用于性能测试

场景自定义，例如使用volcano调度器运行（如不指定参数，如下参数也是默认参数）

```
make scenario-custom \
  SCHEDULERS=volcano \
  VOLCANO_MODE=batch \
  JOBS_SIZE_PER_QUEUE=50 \
  PODS_SIZE_PER_JOB=16 \
  GANG=false \
  TEST_TIMEOUT_SECONDS=300
```

该场景运行也不更新三调度器相对 Dashboard，也不覆盖已有的完整对比结果。结果独立写入如下目录，重复运行只覆盖 `scenario-custom`，不影响 scenario-1～8。

```
results/scenario-custom/envs.txt
results/scenario-custom/result-window.txt
results/scenario-custom/volcano/report.txt
```

> Skill：run-custom-scenario-test，自动运行指定场景+指定调度器，其中“指定场景”可以自定义要测试的指标，用于性能测试

## 3. Makefile 方案细节

### 3.1 常驻集群参数

在顶层 Makefile 中固定常驻集群操作入口：

```makefile
KIND_CLUSTER_NAME = volcano-benchmark-1348
KUBECONFIG = /root/benchmark-1348-deploy/kubeconfig
KUBECTL = /root/benchmark-1348-deploy/bin/kubectl
scenario-N
SCHEDULERS
VOLCANO_MODE = auto
```

`scenario-N` 表示用户选择测试场景，例如scenario-1 ～ scenario-8，表示测试单场景

`SCHEDULERS` 接受调度器，和 `scenario-N` 一起配合使用，表示测试单场景+单调度器

`VOLCANO_MODE` 接受 `auto`、`agent` 和 `batch`。`auto` 根据 `RELATIVE_DASHBOARD_SCENARIO` 将场景 1～4 解析为 `agent`、场景 5～8 解析为 `batch`；显式传值可以覆盖默认选择。Agent 不支持 Gang，因此 `GANG=true` 与 Agent 模式的组合直接拒绝执行。

节点数量和单节点容量属于常驻集群基线，由部署包的验证脚本检查，不再作为测试 Makefile 参数暴露。

### 3.2 `serial-test`

保留当前从 `prepare-<scheduler>` 开始的串行结构，不增加顶层 `make up` 调用。由于不再创建临时 Kind 集群，删除 `bin/kind` 前置依赖：

```makefile
serial-test: ensure-directories
```

执行顺序调整为：

```text
prepare-kueue
start-kueue
end-kueue

prepare-volcano
start-volcano
end-volcano

prepare-yunikorn
start-yunikorn
end-yunikorn

update-relative-dashboard（仅本轮运行三个调度器时）
save-result（仅本轮运行三个调度器时，保存 Dashboard 图片和元数据）
save-scheduler-result（为本轮每个调度器保存时间窗口和统计报告）
```

本轮不增加自动退出恢复机制。异常中断后由人工执行：

```bash
make down
```

### 3.3 `prepare-<scheduler>`

#### 3.3.1 `up-<scheduler>`

每轮不再保存调度组件副本数、当前调度器或 ConfigMap。`up-<scheduler>` 将本轮目标组件设置为 `1` 副本后对其全部 Deployment 执行 `rollout restart`，将其他调度组件设置为 `0` 副本，等待新 Pod Ready、旧 Pod 和非目标 Pod 全部退出，再清理对应测试资源；不重复应用任何调度器配置。Volcano 目标组件由 `VOLCANO_MODE` 决定，实验配置统一由后续 `test-init-<scheduler>` 原地更新。

##### `up-kueue`

- 将两套 Volcano Scheduler、Volcano Controller、Admission 和 YuniKorn 相关 Deployment 缩容到 0
- 将 Kueue Controller、Coscheduling Scheduler 和 Controller 恢复到 1
- 重启 Kueue Controller、Coscheduling Scheduler 和 Controller
- 等待非目标 Deployment 和 Pod 全部归零、目标新 Pod Ready 且旧 Pod 完全退出
- 清理上次遗留的 Kueue、Coscheduling 测试资源并确认零残留

##### `up-volcano`

- 将 Kueue、Coscheduling 和 YuniKorn 相关 Deployment 缩容到 0
- Agent 模式：将 Batch Scheduler、Controller 和 Admission 缩容到 0，将 Agent Scheduler 恢复到 1 并重启
- Batch 模式：将 Agent Scheduler 缩容到 0，将 Batch Scheduler、Controller 和 Admission 恢复到 1 并重启
- 等待非目标 Deployment 和 Pod 全部归零、目标新 Pod Ready 且旧 Pod 完全退出
- 清理上次遗留的原生 Kubernetes Job、Volcano Job 和 Pod，并确认零残留

##### `up-yunikorn`

- 将两套 Volcano Scheduler、Volcano Controller、Admission、Kueue 和 Coscheduling 相关 Deployment 缩容到 0
- 将 YuniKorn Scheduler 和 Admission 设置为 1，并保留 ConfigMap
- 重启 YuniKorn Scheduler 和 Admission
- 等待非目标 Deployment 和 Pod 全部归零、目标新 Pod Ready 且旧 Pod 完全退出
- 清理上次遗留的 YuniKorn 测试资源并确认零残留

#### 3.3.2 `wait-<scheduler>`

删除原来等待临时集群所有 Pod Ready 的逻辑，改为只等待本轮必要组件。

##### Kueue

- `kueue-controller-manager`
- `coscheduling`
- `scheduler-plugins-controller`

##### Volcano

- Agent 模式只等待 `volcano-agent-scheduler`，并确认 `volcano-scheduler`、`volcano-controllers` 和 `volcano-admission` 均为 0
- Batch 模式等待 `volcano-scheduler`、`volcano-controllers` 和 `volcano-admission`，并确认 `volcano-agent-scheduler` 为 0

##### YuniKorn

- `yunikorn-scheduler`
- `yunikorn-admission-controller`

除等待目标组件外，还必须确认全部非目标 Deployment 状态副本和对应 Pod 已归零；完成后再次确认 `1001/1001` Node Ready。

#### 3.3.3 `test-init-<scheduler>`

继续执行现有 `TestInit`，但统一使用常驻集群 kubeconfig。

`TestInit` 只负责创建或更新本轮实验配置。Volcano 和 YuniKorn ConfigMap 不存在时创建、内容变化时原地更新并重启对应 Scheduler；内容一致时跳过更新和重启。Volcano 继续复用现有 `init.yaml`，ConfigMap 内容变化时根据 `VOLCANO_MODE` 重启本轮 Agent 或 Batch Scheduler：

- Kueue：ResourceFlavor、WorkloadPriorityClass、ClusterQueue、LocalQueue
- Volcano：Scheduler ConfigMap、`benchmark-root`、子 Queue、PriorityClass
- YuniKorn：`yunikorn-configs`（`kubernetes.qps/burst=1000/1000`、`service.schedulingInterval=200ms`）

`TestInit` 不再创建 Node。

Kueue、Volcano 和 YuniKorn 均在 `TestInit` 完成后固定等待 `5` 秒，让目标组件和实验配置稳定，再进入 Job 提交阶段。

### 3.4 `start-<scheduler>`

保留现有执行结构：

1. `reset-auditlog-<scheduler>`
2. `test-batch-job-<scheduler>`

两者统一使用常驻集群和常驻控制面容器。

#### 3.4.1 `reset-auditlog-<scheduler>`

沿用当前源码的处理时机，不在 `make up` 中统一清理日志。每个目标在对应调度器任务开始前：

1. 将 Exporter 缩容到 0 并等待 Pod 完全退出。
2. 不删除或截断 API Server 审计文件，也不重启 API Server。
3. 使用本轮调度器名称作为 `--cluster-label`，并通过 `--start-at-end` 从当前审计文件末尾启动全新 Exporter 进程。
4. 等待 Exporter Deployment Ready 后再创建本轮 Job。

审计文件为：

```text
/var/log/kubernetes/kube-apiserver-audit.log
```

每轮使用全新的 Exporter 进程，使 Counter、Histogram 和对象关联状态从空状态开始；`--start-at-end` 跳过测试前已有的审计事件，因此无需清空日志或重启 API Server。运行期间发生 kube-apiserver 日志轮转时，Exporter 先读完旧文件尾部，再切换到新的主日志文件。Kueue、Volcano、YuniKorn 分别生成独立 `cluster` 标签。源码不创建 `./logs/kube-apiserver-audit.<scheduler>.log`。Exporter 本轮结束后保持当前参数和 `1` 副本运行，下一轮开始时直接切换标签。

#### 3.4.2 `test-batch-job-<scheduler>`

统一使用：

```text
/root/benchmark-1348-deploy/kubeconfig
```

测试参数继续由 Makefile 传入，Job 只创建在对应测试命名空间。Volcano Agent 模式读取独立的 `agent_job.yaml` 并创建 `batch/v1` Job，Batch 模式继续读取 `batch_job.yaml` 并创建 `batch.volcano.sh/v1alpha1` Job。

### 3.5 `end-<scheduler>`

调整为：

1. 等待 Exporter 指标稳定，并确认 Prometheus 中存在晚于稳定时刻的最终抓取样本
2. 以 epoch 毫秒记录本轮结果时间窗结束时间
3. 保持本轮 Exporter 以 `1` 副本运行
4. 调用 `down-<scheduler>`

本步骤不再复制或归档 API Server 审计日志。

#### 3.5.1 `down-<scheduler>`

##### `down-kueue`

- 使用 `kubectl delete --wait=false` 异步提交 `bench-kueue` 中 Job、Pod、Workload、LocalQueue 和 PodGroup 的删除请求
- 默认等待最多 `600` 秒，确认上述命名空间资源全部归零
- 删除测试创建的 ClusterQueue、ResourceFlavor、WorkloadPriorityClass
- 对命名空间和集群级测试资源执行最终零残留断言
- 将全部调度相关 Deployment 设置为 `1` 副本并等待 Ready

##### `down-volcano`

- 使用 `kubectl delete --wait=false` 异步提交 `bench-volcano` 中原生 Kubernetes Job、Volcano Job 和 Pod 的删除请求
- 等待并确认上述命名空间资源全部归零
- 删除测试创建的子 Queue、`benchmark-root` 和 PriorityClass
- 对命名空间和集群级测试资源执行最终零残留断言
- 保留 `TestInit` 原地更新后的 Volcano Scheduler ConfigMap
- 将包括 Agent 和 Batch 在内的全部调度相关 Deployment 设置为 `1` 副本并等待 Ready

##### `down-yunikorn`

- 使用 `kubectl delete --wait=false` 异步提交 `bench-yunikorn` 中 Kubernetes Job 和 Pod 的删除请求
- 等待并确认上述命名空间资源全部归零
- 对命名空间测试资源执行最终零残留断言
- 保留 `TestInit` 原地更新后的 `yunikorn-configs`
- 将全部调度相关 Deployment 设置为 `1` 副本并等待 Ready

### 3.6 结果保存

#### 3.6.1 `save-result`

删除其中的：

```makefile
make down
```

`save-result` 只负责：

- 完整运行三个调度器时，等待 Grafana Sidecar 加载本轮相对 Dashboard，并尝试保存其中的 `Job Submission — Created vs Scheduled` 面板；截图失败只告警，不改变测试结果
- Agent 模式将图片写入 `job-submission-agent.png`，Batch 模式写入 `job-submission.png`；归档时保留另一模式已有的同级图片
- 保存 `envs.txt` 和完整串行实验的 `result-window.txt`
- 在 `envs.txt` 中记录解析后的实际 `VOLCANO_MODE`，而不是 `auto`
- 将单张图片和结果元数据写入独立 staging 目录后原子归档，不移动整个 `./tmp`

单调度器运行不调用 `save-result`，因此不会替换已有的完整场景目录。

#### 3.6.2 `save-scheduler-result`

每个被选中的调度器完成后，根据 `result-<scheduler>-from-millis` 和 `result-<scheduler>-to-millis` 保存：

- `window.txt`：使用 CST 的 `YYYY-MM-DD HH:MM:SS 至 YYYY-MM-DD HH:MM:SS` 格式记录本轮时间窗口
- `report.txt`：保存 Pod 调度延迟 P50、P90、P99、实际调度 Pod 数、调度吞吐和吞吐时间窗

延迟分位数、调度数量和吞吐均直接来自本轮原始审计事件，不使用 Prometheus Histogram 估算。脚本按 Pod 名称配对成功的 `pods` create 与 `pods/binding` 事件，以精确时间戳计算每个 Pod 的创建到绑定延迟，排序后使用 nearest-rank 计算 P50、P90、P99；吞吐按成功 binding 数除以第一和最后 binding 的时间差计算。YuniKorn 排除 `tg-` 开头的 placeholder Pod。Audit Exporter 的 Prometheus 指标继续用于抓取屏障和 Dashboard 展示。

`start-<scheduler>` 和 `end-<scheduler>` 同时记录审计文件 inode 与字节位置。inode 相同时，报告脚本读取同一文件的起止字节区间；测试期间发生一次 kube-apiserver 审计日志轮转时，脚本按起始 inode 找到已轮转文件，拼接旧文件尾部与新文件头部后统一解析。因此正常的单次轮转不会再导致报告保存失败。

结果写入 `results/scenario-<n>/<result-scheduler>`。Volcano Agent 的结果名为 `volcano-agent`，Volcano Batch 保持 `volcano`；Kueue 和 YuniKorn 保持逻辑调度器名。完整场景运行保存三个调度器目录；单调度器运行只原子替换本轮对应模式的结果目录，不修改同场景的其他结果。

### 3.7 顶层 `make down`

将顶层 `down` 改为固定副本基线收敛入口：

- 将全部调度组件和 Audit Exporter 设置为 `1` 副本，其中两套 Volcano Scheduler 均恢复到 1
- 依次执行三套调度器资源清理
- 不恢复或删除调度器 ConfigMap，不修改 Audit Exporter 当前标签
- 等待全部组件 Ready
- 阻塞清理并确认三套测试资源全部为零
- 验证 `1001/1001` Node Ready

`down` 不再移动结果目录，也不执行任何 Kind 集群删除操作。

## 4. Go 测试方案细节

### 4.1 限定测试命名空间

固定使用：

| 调度方案 | 命名空间 |
|---|---|
| Kueue + Coscheduling | `bench-kueue` |
| Volcano | `bench-volcano` |
| YuniKorn | `bench-yunikorn` |

所有 Job、LocalQueue、PodGroup 和其他 namespaced 测试资源都改到对应命名空间。

### 4.2 调整完成等待逻辑

`WaitDeployment` 增加目标 namespace 参数，只检查对应测试命名空间中带 `test-instance=1` 的 Pod，避免被其他调度器或历史资源干扰。

`RestartDeployment` 使用 Pod template annotation 触发真实 rollout，并等待 generation 和 updated/ready/available replicas 全部收敛；原副本数为 0 时直接保持停用状态。

Volcano Provider 根据解析后的 `VOLCANO_MODE` 选择 Job 类型和完成条件：

- Agent：创建原生 `batch/v1` Job，等待每个 Job 出现 `Complete=True`
- Batch：创建 `batch.volcano.sh/v1alpha1` Job，继续等待 `status.state.phase=Completed`

## 5. Kueue 测试资源方案细节

- 测试资源使用 `kueue.x-k8s.io/v1beta2` API。
- ClusterQueue 使用 `cohortName`，其 `namespaceSelector` 只匹配 `bench-kueue`。
- Gang 场景继续通过 Coscheduling PodGroup 表达整组调度约束。

## 6. Volcano 测试资源方案细节

### 6.1 模式选择

`volcano` 继续作为三调度器对比中的逻辑名称。场景 1～4 默认使用原生 Kubernetes Job 和 Agent Scheduler；场景 5～8 默认使用 VCJob 和 Batch Scheduler。两种模式使用相同的 Job 数、每 Job Pod 数、资源请求、PriorityClass、KWOK NodeSelector、Toleration 和完成延迟，只改变 Job Controller 路径和实际 Scheduler。

Agent 模式的原生 Job 使用 `parallelism` 和 `completions` 表达每 Job Pod 数，Pod 模板固定 `schedulerName=agent-scheduler`。Agent 不提供 Gang、Queue、Capacity 或 Batch Session 语义，因此只用于非 Gang 的场景 1～4。

### 6.2 专用父队列

不修改内置 `root` Queue。测试统一创建 `benchmark-root` 作为 `root` 的可回收子队列，将全部测试队列共享的 CPU 和内存总上限设置在该队列，并让所有 `test-queue-*` 以 `benchmark-root` 为父队列。

### 6.3 Batch Scheduler 配置

- 固定 Actions：`enqueue`、`allocate`、`backfill`、`reclaim`
- 固定 Plugins：第一层使用 `priority`，第二层使用 `predicates` 和 `capacity`；`capacity.enableHierarchy` 固定为 `true`
- Gang 场景在第一层增加 `gang`，并设置 `enablePreemptable: false`
- Preemption 场景在 Actions 中增加 `preempt`
- 仅在内容变化时原地更新 `volcano-scheduler-configmap` 并重启 Scheduler；内容一致时不操作

### 6.4 Agent Scheduler 配置

- 固定 Action：`allocate`
- 固定 Plugins：`predicates` 和 `nodeorder`
- 固定 `schedulerName=agent-scheduler`、Scheduler Worker 数 `1`
- 使用事件驱动队列，不设置 `schedule-period`
- 不启用 Sharding，使用全部 KWOK Node；Batch Scheduler 在 Agent 测试期间为 0，不存在节点争用

## 7. YuniKorn 测试资源方案细节

- 调度配置保存在 `yunikorn` namespace 的 `yunikorn-configs` ConfigMap 中。
- Job 保留 application ID、queue 和 gang scheduling annotations。

## 8. 结果采集方案细节

### 8.1 结果图片与元数据归档

每个场景的三套调度方案测试完成并生成相对 Dashboard 后，等待 Grafana API 返回与本轮一致的时间窗，再通过 `127.0.0.1:8080/grafana` 渲染相对 Dashboard。结果图片统一截取顶部场景说明和 `Job Submission — Created vs Scheduled` 两个面板，并保留固定的上下留白。原 `perf` Dashboard 继续在 Grafana 中展示，但不作为结果图片来源。

完整测试结果目录固定为 `results/scenario-1` 至 `results/scenario-8`，每个目录直接保存本轮的 `envs.txt`、`result-window.txt`、模式对应的 Dashboard 图片，以及 `kueue`、`yunikorn` 和一个 Volcano 结果子目录。Agent 模式图片名为 `job-submission-agent.png`、结果目录为 `volcano-agent`；Batch 模式图片名为 `job-submission.png`、结果目录为 `volcano`。两种图片可以在场景根目录共存，每轮只替换当前模式图片并保留另一模式的已有图片。每个调度器子目录保存 `window.txt` 和 `report.txt`，`envs.txt` 同时记录实际 `VOLCANO_MODE`。完整场景制品先写入独立 staging 目录后原子替换；单调度器运行只原子替换对应模式的调度器子目录，不生成 Dashboard 图片。完整 `make` 每轮生成 8 张当前模式图片和 24 组调度器报告；图片渲染失败只记录警告，不影响元数据和结果目录归档。

### 8.2 八个相对时间 Dashboard 模板

相对时间 Dashboard 模板用于将同一场景下 Kueue、Volcano 和 YuniKorn 的指标曲线放到统一时间轴上，直接比较三套调度方案的任务创建和调度速度。时间范围定义如下：

- 起始时间：将 Kueue 场景中首次出现实际工作 Pod Created 指标的时间记为 A，将 Volcano 和 YuniKorn 的对应时间分别记为 B、C。Kueue 曲线保持不变，Volcano 和 YuniKorn 曲线分别按 B、C 与 A 的差值整体平移，使三套曲线的首个实际工作 Pod Created 样本统一对齐到 A，并以 A 作为共同 T+0。
- 终止时间：取三套调度方案中第二套达到当前场景任务要求的时间，即已有任意两套方案达到目标的时刻，再向后增加 `5s`。允许最慢方案尚未完成的后续曲线被截断。

每套调度方案在 Audit Exporter 重置完成后记录指标起点，在最终指标确认被 Prometheus 抓取后记录终点。生成阶段以 `100ms` 查询步长在各自时间窗内查找首个实际工作 Pod Created 样本，并按毫秒计算时间偏移。YuniKorn 的 Created 曲线只统计 Controller Manager 创建的实际工作 Pod；Scheduled 曲线使用 Audit Exporter 关联 Controller Manager 创建事件与对应 Pod binding 事件生成的专用 Counter，因此不会计入 placeholder Pod，也不会因两类累计指标相减而下降。三套方案均按实际工作 Pod 判断是否达到场景目标。四个指标面板的最小查询步长均为 `100ms`。

Audit Exporter 的 ServiceMonitor 抓取间隔和超时均为 `100ms`，并保持 `honorLabels=false`，使实验资源命名空间稳定写入 `exported_namespace`。原 `perf` Dashboard 的 8 个面板和相对 Dashboard 的 4 个指标面板最小查询步长均为 `100ms`；`rate` 计算窗口保持 `5s`，避免瞬时速率曲线过度抖动。

仓库保存一份统一模板。默认完整 `make` 为八个场景依次传入场景编号；每个场景的三套调度方案全部成功后，根据本轮实际指标生成并更新对应 Dashboard，确认 Grafana 加载后再截图和归档。单调度器测试不会生成或覆盖这些 Dashboard。

八个场景统一更新 `scheduling-perf-relative-s1-s8` ConfigMap 中各自的 JSON。八个 Dashboard 的标签统一为 `benchmark`、`relative-time` 和各自的 `scenario-N`。Dashboard UID 固定为 `perf-relative-s1` 至 `perf-relative-s8`，继续支持 Scheduler 多选和 Grafana 原生时间缩放；原 `perf` Dashboard 不受影响。完整 `make` 全部成功时八个 Dashboard 均刷新为本轮数据，任一场景失败时不会为该失败场景生成配置。

## 附录

### 1. VCJob 创建 Pod 的链路

```
提交 Volcano Job
  → kube-apiserver
  → Volcano Admission：/jobs/mutate，/jobs/validate
  → 写入 etcd → vc-controller vcjob Informer 发现 Job 
  → vc-controller 初始化 Job Status，执行 Job 插件，并通过 kube-apiserver 按需创建 Service、ConfigMap、PVC、PodGroup 等资源
  → PodGroup Admission：/podgroups/validate
  → 写入 etcd → Volcano scheduler Informer 发现 podgroup
  → Volcano Scheduler 通过 kube-apiserver 将 PodGroup 设置为 Inqueue
  → 写入 etcd → vc-controller PodGroup Informer 发现状态变化并重新处理 VC Job
  → vc-controller 并发调用 kube-apiserver CREATE Pod
  → Volcano Admission：/pods/mutate，/pods/validate
  → 写入 etcd
  → Pod 创建完成，进入 Pending/等待调度状态
```

### 2. 原生 Kubernetes Job 创建 Pod 的链路

```
提交 batch/v1 Job
→ kube-apiserver
→ Admission（内置准入及已注册的 Webhook）
→ 写入 etcd → kube-controller-manager 的 Job Controller 通过 Informer 发现 Job
→ Job Controller 分批/并发调用 kube-apiserver CREATE Pod
→ Pod Admission
→ 写入 etcd
→ Pod 创建完成，进入 Pending/等待调度状态
```

#### 2.1 原生 Job + Volcano Scheduler

原生 Kubernetes Job 使用 Volcano Scheduler，最基本、最常用的是在 Pod 模板中指定volcano调度器

Volcano 的 PodGroup Controller 会发现这些 Pod，并自动创建 PodGroup、补写 `scheduling.k8s.io/group-name` Annotation。

```
提交 Pod 模板中指定 schedulerName=volcano 的原生 batch/v1 Job
→ kube-apiserver
→ Admission（内置准入及已注册的 Webhook）
→ 写入 etcd → kube-controller-manager 的 Job Controller 通过 Informer 发现 Job
→ Job Controller 分批/并发调用 kube-apiserver CREATE Pod
→ Pod Admission
→ 写入 etcd → Pod 创建完成，进入 Pending/等待调度状态
→ vc-controller 的 PodGroup Controller 通过 Pod Informer 发现 Pod
→ vc-controller 根据 Pod 及其所属 Job 信息，通过 kube-apiserver 创建 PodGroup
→ PodGroup Admission：/podgroups/validate
→ PodGroup 写入 etcd
→ vc-controller 为 Pod 写入 scheduling.k8s.io/group-name Annotation 关联 PodGroup
→ Pod 更新写入 etcd → Volcano Scheduler 通过 Informer 发现更新后的 Pod 和 PodGroup
→ Volcano Scheduler 将 PodGroup 设置为 Inqueue，并对组内 Pod 执行调度和 Binding
```

##### VCJob 与原生 Job 的创建速度对比

1. 大量 Job、每个 Job 只有 1 个 Pod：原生 Job + `schedulerName: volcano` 通常创建更快。它不需要等待 PodGroup 先进入 `Inqueue`，Job Controller 可以直接创建 Pod。

2. 少量 Job、每个 Job 包含大量 Pod：VCJob 通常更快。VCJob 在 PodGroup 进入 `Inqueue` 后会高度并发创建该 Job 的全部缺失 Pod；原生 Job Controller 使用 `1、2、4、8...` slow-start，并且单次同步最多创建 500 个 Pod。

3. 从“创建后立即可被 Volcano 调度”看：VCJob 链路更直接。原生 Job 创建 Pod 后，还要等待 vc-controller 创建 PodGroup并回写关联 Annotation。

   | 场景 | 结构              | 更可能创建得快  |
   | ---- | ----------------- | --------------- |
   | 1/5  | 10000 Job × 1 Pod | 原生 Job        |
   | 2/6  | 500 Job × 20 Pod  | 原生 Job或接近  |
   | 3/7  | 20 Job × 500 Pod  | VCJob           |
   | 4/8  | 1 Job × 10000 Pod | VCJob，优势明显 |

#### 2.2 原生 Job + Kueue Controller

```
提交带 Kueue Queue Label、且 suspend=true 的原生 batch/v1 Job
→ kube-apiserver
→ Admission（内置准入及 Kueue Webhook）
→ 写入 etcd → Kueue Controller 通过 Informer 发现 Job
→ Kueue Controller 根据 Job 创建对应的 Workload
→ Workload 写入 etcd 并进入对应 LocalQueue、ClusterQueue 等待准入
→ Kueue Controller 检查配额和 ResourceFlavor，将满足条件的 Workload 设置为 Admitted
→ Kueue Controller 更新 Job 并将 suspend 设置为 false
→ Job 更新写入 etcd → kube-controller-manager 的 Job Controller 通过 Informer 发现 Job 已解除挂起
→ Job Controller 分批/并发调用 kube-apiserver CREATE Pod
→ Pod Admission
→ 写入 etcd
→ Pod 创建完成，进入 Pending/等待调度状态
```

#### 2.3 原生 Job + Agent Scheduler

AgentScheduler 本身不需要 PodGroup。它采用类似原生 kube-scheduler 的逐 Pod 调度模型，Pod 由 Kubernetes Job Controller 创建，AgentScheduler 负责逐 Pod 调度。

```
提交 Pod 模板中指定 schedulerName=agent-scheduler 的原生 batch/v1 Job
→ kube-apiserver
→ Admission（内置准入及已注册的 Webhook）
→ 写入 etcd → kube-controller-manager 的 Job Controller 通过 Informer 发现 Job
→ Job Controller 分批/并发调用 kube-apiserver CREATE Pod
→ Pod Admission
→ 写入 etcd
→ Pod 创建完成，进入 Pending/等待调度状态
→ AgentScheduler 通过 Pod Informer 发现未调度 Pod并加入调度队列
→ AgentScheduler Worker 从队列取出 Pod，执行节点过滤和打分
→ AgentScheduler 选择节点并通过 kube-apiserver Binding
→ Binding 写入 etcd，Pod 完成调度
```

### 3. Volcano 调度周期

Volcano 一轮调度的核心范围是：

```
OpenSession
→ 依次执行 enqueue / allocate / backfill 等 Action
→ CloseSession
```

当前代码使用：

```
wait.Until(pc.runOnce, pc.schedulePeriod, stopCh)
```

而 `wait.Until` 是滑动周期：在 `runOnce` 完全结束后才开始计算等待时间。因此默认 `schedule-period=1s` 的含义就是：

```
本轮CloseSession结束
→ 等待1秒
→ 下一轮开始
```

常驻测试中的 Batch Scheduler 将 `schedule-period` 固定为 `200ms`。Agent Scheduler 不使用该循环，它在 Pod 进入调度队列后由 Worker 事件驱动执行调度，因此不设置对应间隔。

### 4. Volcano Controller 的 Kubernetes Client 与 Volcano Client

虽然只有一组启动参数：

```
--kube-api-qps=1000
--kube-api-burst=1000
```

但Controller用这个配置分别创建两个Client：[server.go (line 143)](/Users/csmvic/Downloads/volcano-versions/volcano/cmd/controller-manager/app/server.go:143)

```
KubeClient    = kubeclientset.NewForConfigOrDie(config)
VolcanoClient = vcclientset.NewForConfigOrDie(config)
```

每次`NewForConfig`都会基于相同的`QPS/Burst`分别创建一个令牌桶，所以实际是：

```
Kubernetes Client
QPS/Burst = 1000/1000
用于Pod、Service、ConfigMap等原生资源

Volcano Client
QPS/Burst = 1000/1000
用于Volcano Job、PodGroup、Queue等CRD
```

两个令牌桶相互独立，不是共同分享1000 QPS。理论上：

```
Kube Client 请求上限     ≈ 1000 QPS
Volcano Client 请求上限  ≈ 1000 QPS
```

### 5. Volcano 的 reclaim 与 backfill

在场景 2、3 的非 Gang、资源充足且无队列争抢条件下：

- `reclaim` 基本没有实际回收工作，主要增加一次扫描。
- `backfill` 通常也只产生少量额外遍历。

### 6. Pod 删除机制

- Job、Deployment 等控制器资源被删除后，Kubernetes Garbage Collector 根据 `ownerReferences` 删除所属 Pod。
- 普通 Pod 由用户直接向 API Server 发起删除请求。

#### 6.1 场景 3 的 Volcano 吞吐波动

VCJob 设置 `ttl=1`，完成 1 秒后进入清理流程：

```text
vc-controller 判断 Job TTL 到期并删除 Job
→ Kubernetes Garbage Collector 删除所属 Pod
→ API Server 通知 vc-scheduler
→ vc-scheduler 从 cache 移除 Pod
```

Scheduler 的调度周期和资源事件处理并行进行：前者执行 Session 与 Actions，后者接收 Pod 增删通知并更新 cache。场景 3 中每个 Job 包含 500 个 Pod；集中删除通知与调度周期重叠时，会占用 cache 和运行时资源。若重叠发生在最后一轮 Session，最后一次 binding 可能延后，从而拉长吞吐统计窗口：

```text
吞吐 = Pod 数量 /（最后 binding 时间 - 第一个 binding 时间）
```

### 7. `podPlayStageParallelism=1`

**定义**：podplaystageparallelism是kwok控制器推进pod生命周期的并发控制设置

**解释定义**：podplaystageparallelism默认值是4，含义是能最多并行处理4个pod的阶段推进，主要推进的阶段包括：running、succeed、deleted

```
对应主要推进的阶段
`pod-ready`：把 Pod 状态更新为 Running，并填写 IP、Conditions、ContainerStatuses。
`pod-complete`：把 Pod 更新为 Succeeded。
`pod-delete`：处理 finalizer 并删除 Pod。
```

**podplaystageparallelism是怎么影响scheduler调度的**：

1. kwok会更新pod状态(running、succeed、failed、deleted)，scheduler 收到该通知后，会调用updatepod来同步cache中的pod信息，例如如果是pod变成deleted后，scheduler需要额外的处理把cache中的pod移出去，这个过程中会涉及 竞争cache锁、内存分配、CPU cache等。

2. 而scheduler的gomaxprocs设置为32，最大并发goroutine也只有32，如果updatepod发生在scheduler的session期间时，就会和调度相关的goroutine抢占P，主要可观测到的现象就是runnable goroutine等待变多，从而可能会拖慢scheduler的调度。

   > 观测结果：runnable goroutine等待时间超过1ms的记为RG，podplaystageparallelism=4（3772）比=1（2132）多了77%左右；
   >
   > 结果来自文档<volcano-v1.15.1-scenario3-throughput-variance-report.md "与 `podPlayStageParallelism=4` 的 trace6 对比">
   >
   > > 注意：虽然update的事件相关的goroutine一般只有一个，那为什么runnable goroutine等待时间会变多这么多呢？
   > >
   > > 虽然 `UpdatePod` 回调通常由一个 informer handler顺序执行，但在 `=4` 时它会更频繁地参与运行：
   > >
   > > ```
   > > UpdatePod处理一个事件
   > > → 让出或阻塞
   > > → 再次被唤醒处理下一个事件
   > > → 与调度worker交替执行
   > > ```
   > >
   > > 

**podplaystageparallelism会导致波动**

scheduler的session期间发生updatepod的数量是有波动的，甚至会在10 ～ 1000的范围内波动，这就导致调度耗时、吞吐和尾延迟发生波动；

> scheduler的session期间发生updatepod的数量这个通常没有办法控制，
>
> 1. go的goroutine没有优先级，每次调度运行时都是排队进行，所以有一定的随机性

**podplaystageparallelism=1会减小波动**

设置为1后，只能并行处理一个pod的阶段推进，这会显著减少 kwok 对pod的状态更新速度，从而在session窗口内updatepod的数量也会变得少很多，这样即使出现波动，那么波动的范围也是在有限的可控范围内的

**podplaystageparallelism=1会影响我们关心的调度过程吗**

并不会，我们针对所有阶段一一展开说明

1. kwok更新pod的running状态，这种情况的发生过程是这样的：在scheduler的action中，pod被更新为binding状态后，然后向api-server发送bind请求，这个bind请求是异步发生的，api-server收到请求后写入 `Pod.spec.nodeName`并持久化到etcd，scheduler 收到Pod 更新，**执行 UpdatePod，更新scheduler cache，把task更新到bound**。KWOK 观察到 Pod.spec.nodeName 已写入后，按 pod-ready stage 将 Pod 状态推进为 Running，scheduler收到pod更新为running的通知，**执行updatepod，更新scheduler cache，把task更新到running**； 重要的是，**scheduler 进入 `Binding` 后，就已经把它从后续调度候选中排除**，并继续处理其他 Pod；它不会等待 Bind API 返回，更不会等待 KWOK 更新 `Running`。所以也不会影响scheduler对pod状态的判断。
2. kwok更新pod的succeed状态，发生在已binding、已 Running 的 Pod 后续生命周期，所以不影响该 Pod 的选点
3. kwok更新pod的failed、deleted状态，这些不在正常调度内考虑范围。

但是可能会影响pod complete、job complete等，这个我们可以暂时不考虑

**最后的说明**

我们使用的机器的CPU当前是32核，所以gomaxprocs最大只能设置为32；如果未来使用更多物理CPU，并同步提高scheduler的CPU limit和GOMAXPROCS，可能进一步降低UpdatePod与调度goroutine之间的运行时竞争；但当前实验表明主要改善来自将KWOK状态更新摊平，尚不能证明GOMAXPROCS=32是主要瓶颈，也不能断定设置为64后影响会基本消失。

> 为什么GOMAXPROCS=64核也不一定有效
>
> 1. 因为从实验结果来看所以存在runnable goroutine的排队，但是即使是排队时仍存在idle P；
> 2. 更多 `UpdatePod` 事件不等于同时产生更多 `UpdatePod` goroutine。Pod informer 通常由一个事件处理链顺序调用 `UpdatePod`，事件多主要形成连续处理或积压，而不是上千个 `UpdatePod` goroutine同时争抢 32 个 P。
> 3. `UpdatePod` 还会涉及 scheduler cache 锁、内存分配、CPU cache 和 Go runtime 干扰。这些串行或共享路径不能通过把 `GOMAXPROCS` 从 32 提高到 64直接消除。
>    1. cache锁：等待共享资源，例如
>       1. **创建 session 时的 `Snapshot()`** 每轮 session 开始前，scheduler 要锁住 cache，复制 Jobs、Tasks、Nodes、Queues 等数据形成快照。 如果 `UpdatePod` 正在持锁，`Snapshot()` 就要等待；反过来，大规模 Snapshot 期间 `UpdatePod` 也要等待。
>       2. **`AddBindTask()`** Pod 选中节点后，scheduler 要锁住 cache，把 Task 标记为 `Binding`、加入目标 Node，并放进 Bind 队列。 这和 `UpdatePod` 使用同一把锁，因此集中到来的状态更新可能推迟 Task 进入 Binding 流程。 提醒：通常不是同一个 Task，也仍会竞争同一把锁
>    2. 内存分配：增加分配和GC工作；`UpdatePod` 通常会重新构造 `TaskInfo`、更新 map、复制部分 Pod/资源信息，产生内存分配。大量更新集中发生时，会增加 allocator 和 GC assist 工作，使正在执行 Predicate/Prioritize 的 goroutine也分担部分内存回收成本。
>    3. CPU cache：是 goroutine虽然能运行，但每次运行的效率降低。`UpdatePod` 与调度热循环交替运行，会反复读写不同内存区域，可能挤出 Predicate/Prioritize 正在使用的 CPU cache 数据。
>    4. Go runtime：Go runtime需要调度这些 goroutine、维护运行队列并进行 work stealing，使调度热路径的单位执行成本发生变化。
