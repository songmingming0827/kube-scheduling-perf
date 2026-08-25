# Resident cluster deployment bundle

This directory versions the reproducible configuration used by the resident
`volcano-benchmark-1348` Kind cluster.

The operational copy is `/root/benchmark-1348-deploy` on the benchmark server.
Copy this directory there before creating or rebuilding the cluster. Generated
runtime data is intentionally excluded from Git:

- `bin/`
- `downloads/`
- `logs/`
- `kubeconfig`

Run the scripts in this order for a fresh deployment:

1. `scripts/install-tooling.sh`
2. `scripts/prepare-scheduler-artifacts.sh`
3. `scripts/prepare-monitoring-artifacts.sh`
4. `scripts/create-canary-cluster.sh`
5. `scripts/install-kwok-canary.sh`
6. `scripts/install-schedulers.sh`
7. `scripts/install-monitoring.sh`
8. `scripts/scale-kwok-nodes.sh 1000`
9. `scripts/verify-base.sh 1000`
10. `scripts/verify-schedulers.sh`
11. `scripts/verify-monitoring.sh`

The Audit Policy and all local scheduler, monitoring, and KWOK overrides are
included under `manifests/`; no second source repository is required.
