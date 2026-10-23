#!/usr/bin/env bash
# kind-observability-on — full local observability stack:
#
#   backends (Mac, Docker)         kind cluster (odg-local)
#   ┌────────────────────┐         ┌──────────────────────────────────────────┐
#   │ opensearch   :9200 │◄─push──│ otel-collector (daemonset, telemetry)     │
#   │ dashboards   :5601 │         │   filelog + k8sattributes → logs         │
#   └────────────────────┘         │   metrics-operator → ODG gauges          │
#                                  │ prometheus-operator + kube-state-metrics │
#                                  │   Prometheus :9090 (port-forward)        │
#                                  │   scrapes collector :8889 via            │
#                                  │   ServiceMonitor                         │
#                                  └──────────────────────────────────────────┘
#
# One prometheus, in-cluster. Telemetry chart's prometheus.integration=true
# makes the collector's :8889 exporter show up as a scrape target.
#
# Usage: ./observability-on.sh  (or: make kind-observability-on)
# Env:   ODG_OBSERVABILITY (default: sibling ../odg-observability checkout)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ODG_OBSERVABILITY="${ODG_OBSERVABILITY:-${REPO_ROOT}/../odg-observability}"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_ROOT}/local-setup/kind/kubeconfig}"
# All charts deploy into the one namespace where ODG runs: the Prometheus CR
# selects ServiceMonitors only from its own (target) namespace, so the
# collector's ServiceMonitor must live beside it.
NAMESPACE="${NAMESPACE:-odg}"   # prometheus-operator + telemetry + ODG pods
OBSERVED_NS="${NAMESPACE}"      # backwards-compat alias; same namespace
PROM_RELEASE=prometheus-operator
PROM_CHART="${ODG_OBSERVABILITY}/charts/prometheus-operator"
TEL_RELEASE=telemetry
TEL_CHART="${ODG_OBSERVABILITY}/charts/telemetry"
BACKENDS="${SCRIPT_DIR}/telemetry"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "▶ $*"; }
ok()   { echo "✓ $*"; }

. "${SCRIPT_DIR}/helm-helpers.sh"

command -v docker  >/dev/null || die "docker not found"
command -v helm    >/dev/null || die "helm not found"
command -v kubectl >/dev/null || die "kubectl not found"
command -v curl    >/dev/null || die "curl not found"
[ -f "${KUBECONFIG_FILE}" ] || die "kubeconfig not found at ${KUBECONFIG_FILE} — run 'make kind-up' first"
[ -d "${PROM_CHART}" ] || die "prometheus-operator chart not found at ${PROM_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"
[ -d "${TEL_CHART}" ] || die "telemetry chart not found at ${TEL_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"

k() { kubectl --kubeconfig="${KUBECONFIG_FILE}" "$@"; }

# ─── 1. Log backends on the Mac (opensearch + dashboards) ───────────────────
info "1/5  log backends (docker compose: opensearch :9200, dashboards :5601)"
docker compose -f "${BACKENDS}/compose.yml" up -d >/dev/null
for i in $(seq 1 60); do
  curl -s -o /dev/null localhost:9200 && break
  sleep 2
  [ "$i" = 60 ] && die "opensearch not ready after 2m — docker compose -f ${BACKENDS}/compose.yml logs"
done
# Data view (index pattern) so Discover works out of the box. 2xx = ok.
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST 'localhost:5601/api/saved_objects/index-pattern/logs-otel-v1?overwrite=true' \
    -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
    -d '{"attributes":{"title":"logs-otel-v1","timeFieldName":"@timestamp","name":"otel logs"}}')
  [[ "$code" =~ ^2 ]] && break
  sleep 2
done
[[ "$code" =~ ^2 ]] || info "WARN: dashboards not ready — data view not created (create manually in OS Dashboards)"
ok "backends up"

# ─── 2. prometheus-operator + kube-state-metrics ────────────────────────────
info "2/5  deploy ${PROM_RELEASE} (prometheus-operator + kube-state-metrics)"
build_helm_override_args "${SCRIPT_DIR}"

helm --kubeconfig="${KUBECONFIG_FILE}" dependency build "${PROM_CHART}" >/dev/null

k apply --server-side --force-conflicts -f "${PROM_CHART}/crds/"

# helm template|apply, not helm install: the vendored kube-state-metrics .tgz
# would make the release secret exceed the 1MB secret limit.
helm --kubeconfig="${KUBECONFIG_FILE}" template "${PROM_RELEASE}" "${PROM_CHART}" \
  --namespace "${NAMESPACE}" \
  --skip-crds \
  --set host="localhost" \
  --set image.repository="quay.io/prometheus-operator/prometheus-operator" \
  --set image.tag="v0.94.1" \
  --set prometheus.image.repository="docker.io/prom/prometheus" \
  --set prometheus.image.tag="v3.15.0-distroless" \
  --set "prometheus-config-reloader.image.repository=quay.io/prometheus-operator/prometheus-config-reloader" \
  --set "prometheus-config-reloader.image.tag=v0.94.1" \
  "${HELM_OVERRIDE_ARGS[@]}" \
  | k apply --server-side --force-conflicts -n "${NAMESPACE}" -f - \
  || die "prometheus deploy failed — see above. Rerun is safe (apply)."

k rollout status deployment "${PROM_RELEASE}" -n "${NAMESPACE}" --timeout=120s \
  || die "operator not ready — kubectl -n ${NAMESPACE} logs deploy/${PROM_RELEASE}"
k rollout status deployment "${PROM_RELEASE}-kube-state-metrics" -n "${NAMESPACE}" --timeout=120s \
  || die "kube-state-metrics not ready"
# Prometheus CR is reconciled by the operator — give it a moment to come up
info "    waiting for prometheus statefulset"
k rollout status statefulset prometheus-prometheus -n "${NAMESPACE}" --timeout=180s \
  || die "prometheus not ready — kubectl -n ${NAMESPACE} logs statefulset/prometheus-prometheus"
ok "prometheus-operator deployed"

# ─── 3. telemetry chart (otel-collector + metrics-operator) ─────────────────
info "3/5  deploy ${TEL_RELEASE} (backend=opensearch, prometheus integration on)"
helm --kubeconfig="${KUBECONFIG_FILE}" dependency update "${TEL_CHART}" >/dev/null
helm --kubeconfig="${KUBECONFIG_FILE}" upgrade --install "${TEL_RELEASE}" "${TEL_CHART}" \
  --namespace "${NAMESPACE}" \
  --set backend=opensearch \
  --set opensearch.endpoint=http://host.docker.internal:9200 \
  --set observedNamespace="${NAMESPACE}" \
  --set prometheus.integration.enabled=true \
  --set prometheus.integration.scrapeInterval=15s \
  --set networkPolicies.enabled=false \
  --timeout 5m || die "telemetry install failed — see above. Rerun is safe (upgrade --install)."

info "    waiting for collector daemonset"
COLLECTOR_SVC="${TEL_RELEASE}-opentelemetry-collector"
k -n "${NAMESPACE}" rollout status ds/${COLLECTOR_SVC}-agent --timeout=180s \
  || die "collector not ready — kubectl -n ${NAMESPACE} logs ds/${COLLECTOR_SVC}-agent"
ok "telemetry deployed"

# ─── 4. Opt-in log annotation (pods restarted later must re-apply this) ──────
info "4/5  annotate odg pods with otel.io/pod-logs=true"
k -n "${NAMESPACE}" rollout status deployment delivery-service --timeout=60s 2>/dev/null || true
k -n "${NAMESPACE}" annotate pods -l app=delivery-service otel.io/pod-logs=true --overwrite \
  || info "WARN: no delivery-service pods yet — annotate later or set annotationKey=\"\""

# ─── 5. Port-forwards ────────────────────────────────────────────────────────
info "5/5  port-forwards: :9090 (prometheus UI), :4317 (OTLP for host apps)"
pf() { # pf <local:remote> <svc> <logfile>
  pkill -f "kubectl.*port-forward.*${1}" 2>/dev/null || true; sleep 1
  nohup bash -c '
    while true; do
      kubectl --kubeconfig="'"${KUBECONFIG_FILE}"'" -n '"${2}"' port-forward svc/'"$3"' '"$1"' >>'"$4"' 2>&1
      sleep 2
    done' _ "$1" "$2" "$3" "$4" >/dev/null 2>&1 &
  disown
  sleep 3
  lsof -i tcp:"${1%%:*}" >/dev/null 2>&1 || die "port-forward ${1} for ${3} failed — see $4"
}
pf 9090:9090 "${NAMESPACE}" prometheus-operated /tmp/pf-prometheus.log
pf 4317:4317 "${NAMESPACE}" "${COLLECTOR_SVC}" /tmp/pf-otlp.log
ok "port-forwards up (self-healing loops)"

# ─── Summary ─────────────────────────────────────────────────────────────────
cat <<EOF

  UP ✓  (no logins anywhere — security plugins disabled)

  METRICS — http://localhost:9090 (Graph tab)
    k8s_pods_running                                               # collector host/k8s gauges
    sum(kube_pod_info)                                             # kube-state-metrics
    Status → Targets: 'prometheus-operated' + 'telemetry' ServiceMonitor should be UP within ~30s

  LOGS — http://localhost:5601 (Discover → 'logs-otel-v1', no password)
    only pods annotated otel.io/pod-logs=true ship logs (delivery-service done above)

  PUSH from host apps — grpc://localhost:4317 (traces/metrics)

  Verify: curl -s localhost:9200/logs-otel-v1/_count
          curl -s 'localhost:9090/api/v1/query?query=kube_pod_info'

  Down: make kind-observability-off (or ./local-setup/kind/observability-off.sh)
EOF
