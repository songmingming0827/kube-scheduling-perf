#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"
CHART="${DEPLOY_DIR}/downloads/kube-prometheus-stack-${KUBE_PROMETHEUS_STACK_VERSION}.tgz"

"${DEPLOY_DIR}/scripts/prepare-monitoring-artifacts.sh"

helm upgrade --install monitoring "${CHART}" \
  --kubeconfig "${KUBECONFIG_PATH}" \
  --namespace monitoring \
  --create-namespace \
  --values "${DEPLOY_DIR}/values/monitoring.yaml" \
  --set-string "grafana.imageRenderer.image.tag=${GRAFANA_IMAGE_RENDERER_VERSION}" \
  --wait --timeout 15m

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" create configmap scheduling-perf-dashboard \
  --namespace monitoring \
  --from-file="perf.json=${DEPLOY_DIR}/manifests/perf-dashboard.json" \
  --dry-run=client -o yaml | \
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" apply -f -
"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" label configmap \
  --namespace monitoring scheduling-perf-dashboard grafana_dashboard=1 --overwrite

"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" apply \
  -f "${DEPLOY_DIR}/manifests/audit-exporter.yaml" \
  -f "${DEPLOY_DIR}/manifests/audit-dashboard.yaml"
"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" rollout status \
  deployment/kube-apiserver-audit-exporter -n kube-system --timeout=5m
"${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" rollout status \
  deployment/monitoring-grafana-image-renderer -n monitoring --timeout=10m

install -m 0644 "${DEPLOY_DIR}/systemd/benchmark-grafana-port-forward.service" \
  /etc/systemd/system/benchmark-grafana-port-forward.service
systemctl daemon-reload
systemctl enable --now benchmark-grafana-port-forward.service
