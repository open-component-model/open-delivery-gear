#!/usr/bin/env bash
# kind-observability-off — remove prometheus-operator + telemetry from kind and
# stop the Mac log backends. Data in opensearch is kept (docker volume); wipe with:
#   docker compose -f local-setup/kind/telemetry/compose.yml down -v

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_ROOT}/local-setup/kind/kubeconfig}"
NAMESPACE="${NAMESPACE:-odg}"   # everything was deployed into the ODG namespace

k() { kubectl --kubeconfig="${KUBECONFIG_FILE}" "$@"; }

if [ -f "${KUBECONFIG_FILE}" ]; then
  helm --kubeconfig="${KUBECONFIG_FILE}" uninstall telemetry -n "${NAMESPACE}" --ignore-not-found || true
  # metrics-operator CRDs are created by the operator, not helm — remove explicitly
  # so re-installs don't wedge on half-migrated CRDs.
  k delete crd metrics.open-control-plane.io datasinks.metrics.open-control-plane.io \
    remoteclusteraccesses.metrics.open-control-plane.io federatedclusteraccesses.metrics.open-control-plane.io \
    managedmetrics.metrics.open-control-plane.io federatedmetrics.metrics.open-control-plane.io \
    federatedmanagedmetrics.metrics.open-control-plane.io --ignore-not-found 2>/dev/null || true
  k annotate pods -n "${NAMESPACE}" otel.io/pod-logs- --all 2>/dev/null || true
  # NOTE: kind-up created the odg namespace with the ODG workloads in it — do
  # NOT delete it here.

  # prometheus-operator was deployed via helm template|apply (no release secret) —
  # re-render and delete instead of helm uninstall.
  ODG_OBSERVABILITY="${ODG_OBSERVABILITY:-${REPO_ROOT}/../odg-observability}"
  if [ -d "${ODG_OBSERVABILITY}/charts/prometheus-operator" ]; then
    helm --kubeconfig="${KUBECONFIG_FILE}" template prometheus-operator \
      "${ODG_OBSERVABILITY}/charts/prometheus-operator" \
      --namespace "${NAMESPACE}" --skip-crds \
      --set host="localhost" \
      --set image.repository="quay.io/prometheus-operator/prometheus-operator" \
      --set image.tag="v0.94.1" \
      --set prometheus.image.repository="docker.io/prom/prometheus" \
      --set prometheus.image.tag="v3.15.0-distroless" \
      --set "prometheus-config-reloader.image.repository=quay.io/prometheus-operator/prometheus-config-reloader" \
      --set "prometheus-config-reloader.image.tag=v0.94.1" \
      | k delete --ignore-not-found -n "${NAMESPACE}" -f - 2>/dev/null || true
  fi
else
  echo "▶ no kubeconfig — skipping cluster teardown"
fi

# kill port-forward loops first (they respawn), then any stray children
pkill -f 'kubectl.*port-forward.*9090:9090' 2>/dev/null || true
pkill -f 'kubectl.*port-forward.*4317:4317' 2>/dev/null || true

docker compose -f "${SCRIPT_DIR}/telemetry/compose.yml" down
echo "✓ observability removed (data kept; 'docker compose -f ${SCRIPT_DIR}/telemetry/compose.yml down -v' to wipe)"
