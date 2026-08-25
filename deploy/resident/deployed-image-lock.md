# 正式基线镜像摘要

以下摘要来自 `volcano-benchmark-1348` 集群实际运行的 `amd64` 容器镜像。

| 组件 | 版本镜像 | 运行时摘要 |
|---|---|---|
| KWOK | `registry.k8s.io/kwok/kwok:v0.7.0` | `sha256:2bb52d4cdd8b3e22e53ec86643a02ee84abdd8cec825269acdf7706d54c0ad6e` |
| Volcano Scheduler | `volcanosh/vc-scheduler:v1.15.1` | `sha256:e79dc85279b5fd2c5e431571b4683f819ff0dfeacdf230fca49e6ce1f4509ae1` |
| Volcano Controller | `volcanosh/vc-controller-manager:v1.15.1` | `sha256:555245dd5c73524dee627ad0c2e308c9dd95af234df791d11e6bcdfa2f33a4ef` |
| Volcano Webhook | `volcanosh/vc-webhook-manager:v1.15.1` | `sha256:569e3671b6d9619c175062e6d3e82bfe3bb4bc3628b36347406ccc07f10fe12c` |
| Kueue | `registry.k8s.io/kueue/kueue:v0.19.0` | `sha256:6fe2cbe4c7799eed1a8d49898c38b8bd73f1572df1825d7cf266ec9e2af70bec` |
| Coscheduling Scheduler | `registry.k8s.io/scheduler-plugins/kube-scheduler:v0.34.7` | `sha256:ae94c1224ef5677ae54bc25b4161a602b4365f479610d550f972e829f7c5b1b6` |
| Coscheduling Controller | `registry.k8s.io/scheduler-plugins/controller:v0.34.7` | `sha256:2b9b6c185b84d003b700506674ed09a37c08b7a62c42efd02f16c2ea3f102e30` |
| YuniKorn Scheduler | `apache/yunikorn:scheduler-1.9.0` | `sha256:96832082e9cfb97cb4d85349ada6243e7c2e3176f167cdde94ad37879f3c815f` |
| YuniKorn Admission | `apache/yunikorn:admission-1.9.0` | `sha256:fe8f5ec91f6c73be4af36afbc41f349ff7bee532593107a80ad90ab3d680a911` |
| Prometheus | `quay.io/prometheus/prometheus:v3.13.2-distroless` | `sha256:64f71bb84e03c855948418b0fc5dea53e9543d8e3fc9931598f583805507f05e` |
| Prometheus Operator | `quay.io/prometheus-operator/prometheus-operator:v0.93.0` | `sha256:a001ed10a3823bbf2410ea347796d0e35ff8decd24fb98acbe7ab9e98d431c39` |
| Prometheus Config Reloader | `quay.io/prometheus-operator/prometheus-config-reloader:v0.93.0` | `sha256:0ccb22ca9f3f6fd9f76ce95585d18bd2e363d421c534dde710be4bd13caa551d` |
| Grafana | `grafana/grafana:13.1.1` | `sha256:7cb8c64c4d57a57e734073f3cc94620adb24a0acb929bd80ba9f14017e3a975b` |
| Grafana Image Renderer | `grafana/grafana-image-renderer:v5.11.1` | `sha256:37e6ed8d55426f80d8d00a839df2cc02568b5877ffa2964f3ec09fa9a295c0a9` |
| Grafana Sidecar | `quay.io/kiwigrid/k8s-sidecar:2.10.0` | `sha256:21b9fe7bb29d65caf2445ccbf96ff6eda5e589a92bd8f5188f957fe75b551d72` |
| Traefik | `docker.io/traefik:v3.7.1` | `sha256:6b9cbca6fac42ab0075f5437d8dc1685cfd188626d8d515839ea94f8b6271c42` |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.19.1` | `sha256:85108987d044b18a098126732f98602df408888c0f7d456241f5abefb9744bc1` |
| Audit Exporter | `ghcr.io/csmvic/kube-apiserver-audit-exporter:v0.0.29` | `sha256:00f3e0cc955239969ccffbeac8a81a8e81563fd89052f85a8d8320ff590a1b34` |
