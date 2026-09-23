# Resident cluster deployment bundle

This directory contains the reproducible configuration for the resident
`volcano-benchmark-1348` Kind + KWOK benchmark cluster.

The operational copy is fixed at `/root/benchmark-1348-deploy`. The monitoring
systemd unit and Grafana Ingress currently depend on that path. Generated
runtime data is intentionally excluded from Git:

- `bin/`
- `downloads/`
- `logs/`
- `kubeconfig`

## Prerequisites

- Linux `x86_64` with systemd and root access
- A running Docker daemon
- Kind `v0.32.0`
- Helm v3, curl, jq, Make, tar, sha256sum, ss, and install
- Network access to the pinned artifact sources and container registries
- Free host ports `31003`, `31004`, `31005`, and loopback port `8080`

`scripts/install-tooling.sh` installs only the pinned kubectl. It does not
install the other host prerequisites.

## One-command fresh installation

Run this as root from the repository root:

```bash
make setup
```

The installer stages this bundle and `deploy/grafana-ingress/` under
`/root/benchmark-1348-deploy`, creates a 100-node KWOK canary environment,
installs and smoke-tests all scheduler stacks, installs monitoring and the
persistent Grafana Ingress, scales to 1000 KWOK nodes, and performs the final
verification.

This command is for a fresh deployment only. It refuses to overwrite an
existing `volcano-benchmark-1348` cluster and never deletes or rolls back a
cluster automatically.

## Step-by-step installation

Stage only the versioned deployment files:

```bash
make stage-resident
```

Continue as root and run the following commands in order:

```bash
cd /root/benchmark-1348-deploy

# 1. Validate the host and install the pinned kubectl.
bash scripts/check-prerequisites.sh
./scripts/install-tooling.sh

# 2. Download scheduler and monitoring artifacts and verify pinned checksums.
./scripts/prepare-scheduler-artifacts.sh
./scripts/prepare-monitoring-artifacts.sh

# 3. Create the Kind control plane.
./scripts/create-canary-cluster.sh

# 4. Install KWOK, create 100 canary nodes, and verify the canary baseline.
./scripts/install-kwok-canary.sh
./scripts/verify-base.sh 100

# 5. Install and validate all scheduler stacks.
./scripts/install-schedulers.sh
./scripts/verify-schedulers.sh
./scripts/run-scheduler-smoke-tests.sh

# 6. Install and validate monitoring and the persistent Grafana endpoint.
./scripts/install-monitoring.sh
./scripts/verify-monitoring.sh
./grafana-ingress/install.sh

# 7. Scale to the formal baseline and run the final verification.
./scripts/scale-kwok-nodes.sh 1000
./scripts/verify-base.sh 1000
./scripts/verify-schedulers.sh
./scripts/verify-monitoring.sh
./grafana-ingress/verify.sh
```

The smoke test creates and removes real benchmark resources. The full setup is
not an idempotent update workflow: cluster creation intentionally fails when
the cluster already exists, and the canary-node step should not be rerun after
scaling to 1000 nodes. After a partial failure, inspect the failure and resume
from the corresponding step instead of restarting the complete setup. If the
Kind cluster appeared but control-plane creation did not finish, verify and
complete the missing control-plane configuration first, or explicitly delete
the incomplete cluster only after confirming that it contains no data to keep.

## Baseline details

The Audit Policy and all scheduler, monitoring, and KWOK overrides are included
under `manifests/`; no second source repository is required.

The resident baseline sets kube-controller-manager, the default kube-scheduler,
and all scheduler Deployments to CPU request/limit `500m/8` without memory
request/limit. Control-plane client QPS/Burst is `1000/1000`. Coscheduling keeps
the official scheduler image at `v0.34.7` and uses
`crpi-ldgaqlsrparac7fl.cn-hangzhou.personal.cr.aliyuncs.com/mingm/scheduler-plugins-controller:v0.34.7-qpsfix`
for the Controller. That image is built from the official `v0.34.7` source with
only upstream fix `4cd26c48` applied, so its Kubernetes dependencies remain at
`v0.34.7`.

The installer verifies fixed SHA-256 values for the Kueue manifest, Scheduler
Plugins source, and kube-prometheus-stack chart. Volcano and YuniKorn chart
scripts currently print their checksums but do not compare them with pinned
expected values; KWOK manifests are applied from their versioned release URLs.
