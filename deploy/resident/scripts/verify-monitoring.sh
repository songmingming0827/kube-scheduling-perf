#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"

kc() {
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
}

kc rollout status deployment/kube-apiserver-audit-exporter -n kube-system --timeout=2m
kc rollout status deployment/monitoring-grafana -n monitoring --timeout=2m
kc rollout status deployment/monitoring-grafana-image-renderer -n monitoring --timeout=5m
kc rollout status deployment/monitoring-kube-prometheus-operator -n monitoring --timeout=2m
kc rollout status deployment/monitoring-kube-state-metrics -n monitoring --timeout=2m
kc rollout status statefulset/prometheus-monitoring-kube-prometheus-prometheus -n monitoring --timeout=2m

audit_metrics="$(kc get --raw '/api/v1/namespaces/kube-system/services/kube-apiserver-audit-exporter:8080/proxy/metrics')"
grep -q 'pod_scheduling_latency_seconds' <<<"${audit_metrics}"

curl -fsS --retry 12 --retry-delay 5 http://127.0.0.1:31003/-/ready >/dev/null
curl -fsS --retry 12 --retry-delay 5 http://127.0.0.1:31004/grafana/api/health >/dev/null
curl -fsS --retry 12 --retry-delay 5 http://127.0.0.1:8080/grafana/api/health >/dev/null

perf_uid="$(kc get configmap scheduling-perf-dashboard -n monitoring \
  -o jsonpath='{.data.perf\.json}' | jq -r '.uid')"
[[ "${perf_uid}" == "perf" ]]

render_file="$(mktemp)"
trap 'rm -f "${render_file}"' EXIT
curl -fsS --retry 3 --retry-delay 5 \
  -o "${render_file}" \
  'http://127.0.0.1:8080/grafana/render/d-solo/perf?var-namespace=$__all&panelId=panel-1&width=300&height=200&scale=1'
[[ "$(od -An -tx1 -N8 "${render_file}" | tr -d ' \n')" == "89504e470d0a1a0a" ]]

printf 'audit_exporter_metrics=true\n'
printf 'prometheus_ready=true\n'
printf 'grafana_ready=true\n'
printf 'grafana_image_renderer_ready=true\n'
printf 'grafana_perf_dashboard=true\n'
