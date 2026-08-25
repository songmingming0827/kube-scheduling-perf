#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${DEPLOY_DIR}/versions.env"

KUBECTL="${DEPLOY_DIR}/bin/kubectl"
KUBECONFIG_PATH="${DEPLOY_DIR}/kubeconfig"

kc() {
  "${KUBECTL}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
}

kc wait --for=condition=Established crd/jobs.batch.volcano.sh --timeout=2m
kc wait --for=condition=Established crd/workloads.kueue.x-k8s.io --timeout=2m
kc wait --for=condition=Established crd/podgroups.scheduling.x-k8s.io --timeout=2m
kc wait --for=condition=Established crd/elasticquotas.scheduling.x-k8s.io --timeout=2m

kc rollout status deployment/volcano-scheduler -n volcano-system --timeout=2m
kc rollout status deployment/volcano-controllers -n volcano-system --timeout=2m
kc rollout status deployment/volcano-admission -n volcano-system --timeout=2m
kc rollout status deployment/kueue-controller-manager -n kueue-system --timeout=2m
kc rollout status deployment/coscheduling -n coscheduling --timeout=2m
kc rollout status deployment/scheduler-plugins-controller -n coscheduling --timeout=2m
kc rollout status deployment/yunikorn-scheduler -n yunikorn --timeout=2m
kc rollout status deployment/yunikorn-admission-controller -n yunikorn --timeout=2m

for target in \
  kueue-system/kueue-controller-manager/manager \
  coscheduling/coscheduling/scheduler-plugins-scheduler \
  coscheduling/scheduler-plugins-controller/scheduler-plugins-controller \
  volcano-system/volcano-scheduler/volcano-scheduler \
  volcano-system/volcano-controllers/volcano-controllers \
  volcano-system/volcano-admission/admission \
  yunikorn/yunikorn-scheduler/yunikorn-scheduler-k8s \
  yunikorn/yunikorn-admission-controller/yunikorn-admission-controller; do
  IFS=/ read -r namespace deployment container <<<"${target}"
  kc get deployment "${deployment}" -n "${namespace}" -o json |
    jq -e --arg container "${container}" '
      .spec.template.spec.containers[] |
      select(.name == $container) |
      .resources == {"limits":{"cpu":"8"},"requests":{"cpu":"500m"}}
    ' >/dev/null
done

kc get mutatingwebhookconfiguration yunikorn-admission-controller-mutations -o json |
  jq -e '
    .webhooks | length > 0 and all(
      .[];
      any(.namespaceSelector.matchExpressions[]?;
        .key == "benchmark.scheduling/base" and
        .operator == "In" and
        .values == ["yunikorn"])
    )
  ' >/dev/null
kc get validatingwebhookconfiguration yunikorn-admission-controller-validations -o json |
  jq -e '
    .webhooks | length > 0 and all(
      .[];
      any(.namespaceSelector.matchExpressions[]?;
        .key == "kubernetes.io/metadata.name" and
        .operator == "In" and
        .values == ["yunikorn"])
    )
  ' >/dev/null

printf 'volcano_release=%s\n' "$(helm --kubeconfig "${KUBECONFIG_PATH}" list -n volcano-system --short)"
printf 'kueue_image=%s\n' "$(kc get deployment kueue-controller-manager -n kueue-system -o jsonpath='{.spec.template.spec.containers[0].image}')"
printf 'coscheduling_image=%s\n' "$(kc get deployment coscheduling -n coscheduling -o jsonpath='{.spec.template.spec.containers[0].image}')"
printf 'yunikorn_image=%s\n' "$(kc get deployment yunikorn-scheduler -n yunikorn -o jsonpath='{.spec.template.spec.containers[0].image}')"
printf 'scheduler_resources=cpu_500m_8_no_memory\n'
printf 'yunikorn_webhooks_scoped=true\n'
