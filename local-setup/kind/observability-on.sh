#!/usr/bin/env bash
# kind-observability-on — full local observability stack, entirely in-cluster:
#
#   kind cluster (odg-local / namespace odg)
#   ┌──────────────────────────────────────────────────────┐
#   │ opensearch :9200  ◄──push── otel-collector (daemonset)│
#   │ opensearch-dashboards :5601 (Discover UI)             │
#   │ prometheus :9090  ◄──scrape── collector :8889         │
#   │ perses :8080      ◄──query── prometheus :9090         │
#   └──────────────────────────────────────────────────────┘
#
# No docker, no host.docker.internal, no host ports — everything talks over
# cluster services. kubectl port-forwards expose prometheus/perses/dashboards
# on localhost.
#
# Usage: ./observability-on.sh  (or: make kind-observability-on)
# Env:   ODG_OBSERVABILITY (default: sibling ../odg-observability checkout)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ODG_OBSERVABILITY="${ODG_OBSERVABILITY:-${REPO_ROOT}/../odg-observability}"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_ROOT}/local-setup/kind/kubeconfig}"
# All charts deploy into the one namespace where ODG runs: the Prometheus CR
# selects ServiceMonitors only from its own namespace, so the collector's
# ServiceMonitor must live beside it.
NAMESPACE="${NAMESPACE:-odg}"
PROM_RELEASE=prometheus-operator
PROM_CHART="${ODG_OBSERVABILITY}/charts/prometheus-operator"
TEL_RELEASE=telemetry
TEL_CHART="${ODG_OBSERVABILITY}/charts/telemetry"
BACKENDS="${SCRIPT_DIR}/telemetry"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "▶ $*"; }
ok()   { echo "✓ $*"; }

. "${SCRIPT_DIR}/helm-helpers.sh"

command -v helm    >/dev/null || die "helm not found"
command -v kubectl >/dev/null || die "kubectl not found"
command -v curl    >/dev/null || die "curl not found"
[ -f "${KUBECONFIG_FILE}" ] || die "kubeconfig not found at ${KUBECONFIG_FILE} — run 'make kind-up' first"
[ -d "${PROM_CHART}" ] || die "prometheus-operator chart not found at ${PROM_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"
[ -d "${TEL_CHART}" ] || die "telemetry chart not found at ${TEL_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"

k() { kubectl --kubeconfig="${KUBECONFIG_FILE}" "$@"; }

# ─── 1. opensearch + dashboards manifests ────────────────────────────────────
info "1/5  opensearch + opensearch dashboards (in-cluster, in namespace ${NAMESPACE})"
# images pull straight from docker hub (~2GB total on first node boot; pods
# schedule fine while the pull runs, so no pre-load step)
k -n "${NAMESPACE}" apply -f "${BACKENDS}/opensearch.yaml"
k -n "${NAMESPACE}" apply -f "${BACKENDS}/dashboards.yaml"
k -n "${NAMESPACE}" apply -f "${BACKENDS}/networkpolicies.yaml"

info "    waiting for opensearch (single node, ~1m first boot)"
k -n "${NAMESPACE}" rollout status statefulset opensearch --timeout=240s \
  || die "opensearch not ready — kubectl -n ${NAMESPACE} logs statefulset/opensearch"
info "    waiting for dashboards (first boot optimizes bundles, ~1-2m)"
k -n "${NAMESPACE}" rollout status deployment opensearch-dashboards --timeout=300s \
  || die "dashboards not ready — kubectl -n ${NAMESPACE} logs deploy/opensearch-dashboards"
ok "backends up (http://opensearch.${NAMESPACE}:9200, http://opensearch-dashboards.${NAMESPACE}:5601)"

# ─── 2. prometheus-operator + kube-state-metrics + perses ───────────────────
info "2/5  deploy ${PROM_RELEASE} (prometheus-operator + kube-state-metrics + perses)"
build_helm_override_args "${SCRIPT_DIR}"

# SKIP dependency management: the perses .tgz under charts/ is vendored WITH the
# ODG patch applied (see odg-observability/scripts/patch-perses-chart.sh). Any
# helm dependency build/update would re-download the pristine upstream chart and
# lose the patch, breaking perses-app.image.repository/tag --set flags below.
[ -f "${PROM_CHART}/charts/perses-0.23.3.tgz" ] || die "vendored perses tgz missing under ${PROM_CHART}/charts/ — do NOT run helm dependency build/update on this chart"

k apply --server-side --force-conflicts -f "${PROM_CHART}/crds/"

# helm template|apply, not helm install: the vendored kube-state-metrics .tgz
# would make the release secret exceed the 1MB secret limit. --set-string on the
# image values: plain --set treats "~"-looking values as literals, and the chart
# defaults them to null — helm schema then rejects the perses-app.image block
# ("repository/tag not allowed") against the vendored patch's extra keys.
helm --kubeconfig="${KUBECONFIG_FILE}" template "${PROM_RELEASE}" "${PROM_CHART}" \
  --namespace "${NAMESPACE}" \
  --skip-crds \
  --set host="localhost" \
  --set perses-app.enabled=true \
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
k rollout status deployment kube-state-metrics -n "${NAMESPACE}" --timeout=120s \
  || die "kube-state-metrics not ready"   # fullnameOverride: kube-state-metrics (no release prefix)
info "    waiting for prometheus statefulset"
k rollout status statefulset prometheus-prometheus -n "${NAMESPACE}" --timeout=180s \
  || die "prometheus not ready — kubectl -n ${NAMESPACE} logs statefulset/prometheus-prometheus"
info "    waiting for perses statefulset"
k rollout status statefulset perses -n "${NAMESPACE}" --timeout=180s \
  || die "perses not ready — kubectl -n ${NAMESPACE} logs statefulset/perses"
ok "prometheus + perses deployed"

# ─── 3. telemetry chart (otel-collector + metrics-operator) ─────────────────
info "3/5  deploy ${TEL_RELEASE} (backend=opensearch, endpoint=cluster service)"
helm --kubeconfig="${KUBECONFIG_FILE}" dependency update "${TEL_CHART}" >/dev/null
helm --kubeconfig="${KUBECONFIG_FILE}" upgrade --install "${TEL_RELEASE}" "${TEL_CHART}" \
  --namespace "${NAMESPACE}" \
  --set backend=opensearch \
  --set opensearch.endpoint=http://opensearch.${NAMESPACE}.svc.cluster.local:9200 \
  --set observedNamespace="${NAMESPACE}" \
  --set prometheus.integration.enabled=true \
  --set prometheus.integration.scrapeInterval=15s \
  --timeout 5m || die "telemetry install failed — see above. Rerun is safe (upgrade --install)."

info "    waiting for collector daemonset"
COLLECTOR_SVC="${TEL_RELEASE}-opentelemetry-collector"
k -n "${NAMESPACE}" rollout status ds/${COLLECTOR_SVC}-agent --timeout=180s \
  || die "collector not ready — kubectl -n ${NAMESPACE} logs ds/${COLLECTOR_SVC}-agent"
ok "telemetry deployed"

# ─── 4. Port-forwards + data view ────────────────────────────────────────────
# (no log-annotation step: the telemetry chart's annotationKey is "" = gate off,
# all odg-namespace pods ship logs except the chart's built-in noisy excludes)
info "4/4  port-forwards: :9090 prometheus, :8080 perses, :5601 dashboards, :4317 OTLP"
pf() { # pf <local:remote> <ns> <svc> <logfile>
  pkill -f "kubectl.*port-forward.*${1}" 2>/dev/null || true; sleep 1
  nohup bash -c '
    fails=0
    while [ "$fails" -lt 3 ]; do
      kubectl --kubeconfig="'"${KUBECONFIG_FILE}"'" -n '"${2}"' port-forward svc/'"$3"' '"$1"' >>'"$4"' 2>&1
      # cluster gone (kind-down / reboot / kubeconfig deleted)? 3 consecutive
      # connection failures = exit instead of retrying forever. Transient drops
      # (pod restart, laptop sleep) fail once, recover on the next attempt.
      kubectl --kubeconfig="'"${KUBECONFIG_FILE}"'" get namespace '"${2}"' >/dev/null 2>&1 \
        && fails=0 || fails=$((fails+1))
      sleep 2
    done
    echo "$(date): cluster unreachable 3× — giving up" >>'"$4"'' _ "$1" "$2" "$3" "$4" >/dev/null 2>&1 &
  disown
  sleep 3
  lsof -i tcp:"${1%%:*}" >/dev/null 2>&1 || die "port-forward ${1} for ${3} failed — see $4"
}
pf 9090:9090 "${NAMESPACE}" prometheus-operated /tmp/pf-prometheus.log
pf 8080:8080 "${NAMESPACE}" perses /tmp/pf-perses.log
pf 5601:5601 "${NAMESPACE}" opensearch-dashboards /tmp/pf-dashboards.log
pf 4317:4317 "${NAMESPACE}" "${COLLECTOR_SVC}" /tmp/pf-otlp.log

# Data view (index pattern) so Discover works out of the box. 2xx = ok.
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST 'localhost:5601/api/saved_objects/index-pattern/logs-otel-v1?overwrite=true' \
    -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
    -d '{"attributes":{"title":"logs-otel-v1","timeFieldName":"@timestamp","name":"otel logs"}}')
  [[ "$code" =~ ^2 ]] && break
  sleep 2
done
[[ "$code" =~ ^2 ]] || info "WARN: data view not created (create manually in OS Dashboards)"
ok "port-forwards up (self-healing loops)"

# ─── Summary ─────────────────────────────────────────────────────────────────
cat <<EOF

  UP ✓  (no logins anywhere — security plugins disabled)

  Open: http://localhost:8080 (perses, Dashboards → odg)
        http://localhost:5601 (Discover → logs-otel-v1)
        http://localhost:9090 (prometheus)

    all odg-namespace pods ship logs (delivery-dashboard + delivery-db excluded by the chart)

  PUSH from host apps — grpc://localhost:4317 (traces/metrics)

  Verify: kubectl -n ${NAMESPACE} exec statefulset/opensearch -- curl -s localhost:9200/logs-otel-v1/_count
          curl -s 'localhost:9090/api/v1/query?query=kube_pod_info'

  Down: make kind-down (the stack is part of the throwaway kind cluster)
EOF
