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
# Pin the kind kubeconfig: do NOT fall back to the caller's KUBECONFIG — users
# often export merged kubeconfigs (kind + gardener + ...); kubectl `config` writes
# against a merged view then stamp foreign current-contexts (e.g. odg-dev-p0) into
# this file, breaking later scripted kubectl calls. Only opt-in overrides via
# KUBECONFIG pointing at a real file; anything else => repo-local file.
KUBECONFIG_FILE="${REPO_ROOT}/local-setup/kind/kubeconfig"
case "${KUBECONFIG:-}" in
  *:*) echo "note: multi-file KUBECONFIG detected (${KUBECONFIG##*:} + more) —\n      pinned to ${KUBECONFIG_FILE} instead" >&2 ;;
esac
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
command -v jq      >/dev/null || die "jq not found"
command -v yq      >/dev/null || die "yq (mikefarah v4) not found — brew install yq"
[ -f "${KUBECONFIG_FILE}" ] || die "kubeconfig not found at ${KUBECONFIG_FILE} — run 'make kind-up' first"
[ -d "${PROM_CHART}" ] || die "prometheus-operator chart not found at ${PROM_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"
[ -d "${TEL_CHART}" ] || die "telemetry chart not found at ${TEL_CHART} — checkout odg-observability beside $(basename "${REPO_ROOT}")"

k() { kubectl --kubeconfig="${KUBECONFIG_FILE}" "$@"; }

# ─── 1. opensearch + dashboards manifests ────────────────────────────────────
info "1/6  opensearch + opensearch dashboards (in-cluster, in namespace ${NAMESPACE})"
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

info "1b/6  data-prepper (otel_trace_source :21890 -> otel-v1-apm-span-* in opensearch)"
k -n "${NAMESPACE}" apply -f "${BACKENDS}/data-prepper.yaml"
info "    waiting for data-prepper (first pull ~30s)"
k -n "${NAMESPACE}" rollout status deployment data-prepper --timeout=240s \
  || die "data-prepper not ready — kubectl -n ${NAMESPACE} logs deploy/data-prepper"
ok "data-prepper up (http://data-prepper.${NAMESPACE}:4900 health, :21890 otlp-grpc)"

patch_collector_for_data_prepper() {
  # Local-only fan-out: add otlp/data-prepper to the collector's traces pipeline
  # (the telemetry chart has no multi-backend switch, and prod needs no Data
  # Prepper — BTP Cloud Logging runs its own). Idempotent; `helm upgrade` in
  # step 3 re-renders the ConfigMap, so this runs again after every upgrade.
  local cm_name="${TEL_RELEASE}-override"
  local cfg
  cfg=$(k -n "${NAMESPACE}" get cm "${cm_name}" -o jsonpath='{.data.relay}') \
    || die "collector ConfigMap ${cm_name} not found"
  if [ "$(yq '.service.pipelines.traces.exporters | contains(["otlp/data-prepper"])' <<<"${cfg}")" = "true" ]; then
    info "    collector already fans out to data-prepper"
    return 0
  fi
  cfg=$(DP_ENDPOINT="data-prepper.${NAMESPACE}.svc.cluster.local:21890" yq '
    .exporters["otlp/data-prepper"] = {"endpoint": strenv(DP_ENDPOINT), "tls": {"insecure": true}}
    | .service.pipelines.traces.exporters += ["otlp/data-prepper"]
  ' <<<"${cfg}") || die "yq failed to patch collector config"
  k -n "${NAMESPACE}" patch cm "${cm_name}" --type=merge \
    -p "{\"data\":{\"relay\":$(jq -Rs . <<<"${cfg}")}}" >/dev/null \
    || die "patching ${cm_name} failed"
  # collector pods do not reload on ConfigMap change
  k -n "${NAMESPACE}" rollout restart ds "${TEL_RELEASE}-opentelemetry-collector-agent" >/dev/null
  ok "collector fans out traces to data-prepper"
}

# ─── 2. prometheus-operator + kube-state-metrics + perses ───────────────────
info "2/6  deploy ${PROM_RELEASE} (prometheus-operator + kube-state-metrics + perses)"
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
info "3/6  deploy ${TEL_RELEASE} (backend=opensearch, endpoint=cluster service)"
helm --kubeconfig="${KUBECONFIG_FILE}" dependency update "${TEL_CHART}" >/dev/null
# --force-conflicts: patch_collector_for_data_prepper (kubectl) co-owns the
# ConfigMap's .data.relay after the first run; helm must take it back on re-runs.
helm --kubeconfig="${KUBECONFIG_FILE}" upgrade --install "${TEL_RELEASE}" "${TEL_CHART}" \
  --namespace "${NAMESPACE}" \
  --force-conflicts \
  --set backend=opensearch \
  --set opensearch.endpoint=http://opensearch.${NAMESPACE}.svc.cluster.local:9200 \
  --set observedNamespace="${NAMESPACE}" \
  --set 'excludePodPrefixes={opensearch-,opensearch-dashboards-,data-prepper-}' \
  --set prometheus.integration.enabled=true \
  --set prometheus.integration.scrapeInterval=15s \
  --timeout 5m || die "telemetry install failed — see above. Rerun is safe (upgrade --install)."

info "    waiting for collector daemonset"
COLLECTOR_SVC="${TEL_RELEASE}-opentelemetry-collector"
k -n "${NAMESPACE}" rollout status ds/${COLLECTOR_SVC}-agent --timeout=180s \
  || die "collector not ready — kubectl -n ${NAMESPACE} logs ds/${COLLECTOR_SVC}-agent"
ok "telemetry deployed"

patch_collector_for_data_prepper
info "    waiting for collector to pick up the data-prepper fan-out"
k -n "${NAMESPACE}" rollout status ds/${COLLECTOR_SVC}-agent --timeout=180s \
  || die "collector restart after data-prepper patch failed"

# ─── 4. start trace ingest on the already-running ODG workloads ─────────────
# Patch the OTEL env vars onto every odg-core container in the namespace.
# Touches neither helm releases nor container images: `make kind-up` and
# `make kind-update` stay using stock published charts, and running
# `kind-local-image <tag>` before this gets you local code *and* tracing.
# Warns when it patches a workload on the released registry image so that
# the absence of spans has an obvious explanation (the SDK may not be in
# that build yet).
info "4/6  wiring traces into ODG workloads"
OTLP_ENDPOINT="http://${COLLECTOR_SVC}.${NAMESPACE}:4317"
. "${SCRIPT_DIR}/odg-workloads.sh"
discover_odg_workloads

if [ "${#ODG_RESOURCE[@]}" -eq 0 ]; then
  warn "no ODG workloads found in ${NAMESPACE} — nothing patched"
else
  for i in "${!ODG_RESOURCE[@]}"; do
    res="${ODG_RESOURCE[$i]}"
    workload="${ODG_WORKLOAD[$i]}"
    container="${ODG_CONTAINER[$i]}"

    res_json=$(k get -n "${NAMESPACE}" "${res}" -o json)
    image=$(jq -r --arg c "${container}" '
          (if .kind == "CronJob" then .spec.jobTemplate.spec.template else .spec.template end)
          | .spec.containers[] | select(.name == $c) | .image' <<<"${res_json}")
    if [[ "${image}" == europe-docker.pkg.dev/* ]]; then
      warn "${workload}: on released image ${image} — published odg-core builds predate the OTEL SDK, so no spans will be emitted until you run 'kind-local-image <tag>' first"
    fi

    # Same env block as the odg-core charts (extensions helpers.tpl,
    # delivery-service deployment.yaml). Released charts lack it, so mirror it
    # here. Order matters: Kubernetes expands $(VAR) only from vars defined
    # EARLIER in the list, so K8S_POD_* (downward API) must precede
    # OTEL_RESOURCE_ATTRIBUTES. `kubectl set env` can't create fieldRef vars,
    # hence a JSON patch that rewrites the container's env: drop our seven names,
    # re-append them in order. Idempotent; other env vars stay untouched.
    env_patch=$(jq -c --arg c "${container}" --arg ep "${OTLP_ENDPOINT}" --arg svc "${workload}" '
      (if .kind == "CronJob" then "/spec/jobTemplate/spec/template" else "/spec/template" end) as $tpl_path
      | (if .kind == "CronJob" then .spec.jobTemplate.spec.template else .spec.template end) as $tpl
      | ($tpl.spec.containers | map(.name) | index($c)) as $idx
      | ["K8S_POD_NAME", "K8S_POD_UID", "K8S_POD_NAMESPACE",
         "OTEL_EXPORTER_OTLP_ENDPOINT", "OTEL_SERVICE_NAME", "OTEL_SEMCONV_STABILITY_OPT_IN",
         "OTEL_RESOURCE_ATTRIBUTES"] as $ours
      | def field($path): {valueFrom: {fieldRef: {fieldPath: $path}}};
      [{
        op: "add",
        path: "\($tpl_path)/spec/containers/\($idx)/env",
        value: (
          ($tpl.spec.containers[$idx].env // [] | map(select(.name as $n | $ours | index($n) | not)))
          + [
            ({name: "K8S_POD_NAME"} + field("metadata.name")),
            ({name: "K8S_POD_UID"} + field("metadata.uid")),
            ({name: "K8S_POD_NAMESPACE"} + field("metadata.namespace")),
            {name: "OTEL_EXPORTER_OTLP_ENDPOINT", value: $ep},
            {name: "OTEL_SERVICE_NAME", value: $svc},
            # emit http.server.request.duration (seconds, with http.route) instead
            # of the old-semconv http.server.duration (ms, no route) — the perses
            # odg-http-server dashboard queries the new one
            {name: "OTEL_SEMCONV_STABILITY_OPT_IN", value: "http"},
            {name: "OTEL_RESOURCE_ATTRIBUTES",
             value: "k8s.pod.name=$(K8S_POD_NAME),k8s.pod.uid=$(K8S_POD_UID),k8s.namespace.name=$(K8S_POD_NAMESPACE),k8s.container.name=\($c)"}
          ]
        )
      }]' <<<"${res_json}")
    k -n "${NAMESPACE}" patch "${res}" --type=json -p "${env_patch}" >/dev/null \
      || die "patching env of ${workload} failed"
    if [[ "${res}" == deployment/* ]]; then
      k -n "${NAMESPACE}" rollout status "${res}" --timeout=120s \
        || info "    ${workload} still rolling out; traces start when Ready"
    fi
    ok "${workload} now pushes to ${OTLP_ENDPOINT}"
  done
fi

# ─── 4. Port-forwards + data view ────────────────────────────────────────────
# (no log-annotation step: the telemetry chart's annotationKey is "" = gate off,
# all odg-namespace pods ship logs except the chart's built-in noisy excludes)
info "5/6  port-forwards: :9090 prometheus, :8080 perses, :5601 dashboards, :4317 OTLP, :3000 dashboard, :5000 delivery-service"
. "${SCRIPT_DIR}/port-forwards.sh"
pf() { # pf <local:remote> <ns> <svc> <logfile>
  port_forward "${KUBECONFIG_FILE}" "$2" "$3" "$1" "$4" || die "port-forward ${1} for ${3} failed — see $4"
}
pf 9090:9090 "${NAMESPACE}" prometheus-operated /tmp/pf-prometheus.log
pf 8080:8080 "${NAMESPACE}" perses /tmp/pf-perses.log
pf 5601:5601 "${NAMESPACE}" opensearch-dashboards /tmp/pf-dashboards.log
pf 4317:4317 "${NAMESPACE}" "${COLLECTOR_SVC}" /tmp/pf-otlp.log
# step 4 restarted delivery-service/-dashboard pods -> the plain forwards from
# kind-up are dead; replace them with self-healing ones
odg_port_forwards "${KUBECONFIG_FILE}" "${NAMESPACE}"

# Data views (index patterns) so Discover works out of the box for logs AND
# traces. Spans ship to traces-otel-v1 (collector opensearch/traces exporter),
# logs to logs-otel-v1 (filelog -> opensearch/logs). 2xx = ok.
#
# Why the sleep: index patterns save an empty field list when the backing index
# doesn't exist yet. Collector only creates logs-otel-v1/traces-otel-v1 on
# first payload. We wait for both, derive fields via _fields_for_wildcard, and
# store them inline — otherwise Discover breaks with "Could not locate that
# index-pattern-field (id: startTime)" on a fresh cluster.
for pattern in logs-otel-v1 traces-otel-v1; do
  # traces use startTime: the collector's opensearch/traces exporter writes
  # @timestamp as the 0001-01-01T00:00:00Z sentinel; logs keep @timestamp
  timefield="@timestamp"; [[ "$pattern" == traces-* ]] && timefield="startTime"
  # wait for the index to exist (collector creates on first payload)
  for i in $(seq 1 60); do
    kubectl --kubeconfig="${KUBECONFIG_FILE}" -n "${NAMESPACE}" exec statefulset/opensearch -- \
      curl -s -o /dev/null -w '%{http_code}' "localhost:9200/${pattern}" 2>/dev/null | grep -q '^2' && break
    sleep 2
  done
  # fetch the OS mapping -> build the index-pattern fields blob
  fields_json=$(curl -s "localhost:5601/api/index_patterns/_fields_for_wildcard?pattern=${pattern}&meta_fields=_source&meta_fields=_id&meta_fields=_index&meta_fields=_score" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('fields', [])))")
  # create the saved object with fields embedded (overwrite=true for re-runs)
  for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' \
      -X POST "localhost:5601/api/saved_objects/index-pattern/${pattern}?overwrite=true" \
      -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
      -d "{\"attributes\":{\"title\":\"${pattern}\",\"timeFieldName\":\"${timefield}\",\"name\":\"otel ${pattern%%-otel-v1}\",\"fields\":$(python3 -c "import json,sys; print(json.dumps(json.dumps(json.load(sys.stdin))))" <<<"${fields_json}")}}")
    [[ "$code" =~ ^2 ]] && break
    sleep 2
  done
  [[ "$code" =~ ^2 ]] || info "WARN: data view ${pattern} not created (create manually in OS Dashboards)"
done
ok "port-forwards up (self-healing loops)"

# ─── Summary ─────────────────────────────────────────────────────────────────
cat <<EOF

  UP ✓  (no logins anywhere — security plugins disabled)

  Open: http://localhost:8080 (perses, Dashboards → odg)
        http://localhost:5601 (Discover → logs-otel-v1; Observability → Trace Analytics)
        http://localhost:9090 (prometheus)

    all odg-namespace pods ship logs (delivery-dashboard + delivery-db excluded by the chart)

  PUSH from host apps — grpc://localhost:4317 (traces/metrics)
  SET in your shell to trace locally-run ODG processes into the kind collector:
      export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

  Verify: kubectl -n ${NAMESPACE} exec statefulset/opensearch -- curl -s localhost:9200/logs-otel-v1/_count
          kubectl -n ${NAMESPACE} exec statefulset/opensearch -- curl -s localhost:9200/traces-otel-v1/_count
          kubectl -n ${NAMESPACE} exec statefulset/opensearch -- curl -s localhost:9200/otel-v1-apm-span/_count
          curl -s 'localhost:9090/api/v1/query?query=kube_pod_info'

  Down: make kind-down (the stack is part of the throwaway kind cluster)
EOF
