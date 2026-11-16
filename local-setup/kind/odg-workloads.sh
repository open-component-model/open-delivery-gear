#!/usr/bin/env bash
# Discovers the ODG workloads that carry the odg-core python image so the
# other kind scripts can patch them (set image, patch env) in one consistent
# place.
#
# Requires $NAMESPACE and the k() wrapper already defined by the caller
# (k() is what helm-helpers.sh and observability-on.sh both define for kubectl).
# Populates three parallel arrays, one entry per (resource, workload, container):
#   ODG_RESOURCE[i]   — k8s resource ref, e.g. "deployment/backlog-controller"
#                       or "cronjob/artefact-enumerator"
#   ODG_WORKLOAD[i]   — workload name (used as OTEL_SERVICE_NAME)
#   ODG_CONTAINER[i]  — container name within that pod template
#
# Picks pods whose container image matches either the released registry
# (europe-docker.pkg.dev/gardener-project/releases/odg/core) or the local
# `odg-core:<tag>` convention. Excludes dashboards, postgres, telemetry's own
# deployments, and monitoring addons.
discover_odg_workloads() {
  ODG_RESOURCE=()
  ODG_WORKLOAD=()
  ODG_CONTAINER=()

  local list
  list=$(k get deployments,cronjobs -n "${NAMESPACE}" -o json | jq -r '
    .items[] as $item
    | select($item.metadata.name
        | test("^(opensearch|kube-state-metrics|perses|prometheus|telemetry|delivery-dashboard|delivery-db|grafana)") | not)
    | (if $item.kind == "CronJob" then $item.spec.jobTemplate.spec.template else $item.spec.template end) as $pod
    | $pod.spec.containers[] as $c
    | select($c.image | test("(releases/odg/core|^odg-core:)"))
    | [($item.kind | ascii_downcase) + "/" + $item.metadata.name, $item.metadata.name, $c.name]
    | @tsv
  ')

  local resource workload container
  while IFS=$'\t' read -r resource workload container; do
    [ -z "${resource}" ] && continue
    ODG_RESOURCE+=("${resource}")
    ODG_WORKLOAD+=("${workload}")
    ODG_CONTAINER+=("${container}")
  done <<< "${list}"
}
