#!/usr/bin/env bash
# kind-local-image.sh <tag> — patch every ODG workload in the kind cluster
# to run the locally built odg-core:<tag> image instead of the released one.
#
# Use this *before* make kind-observability-on when developing against a local
# odg-core checkout (the published charts pin the previous release's image,
# which may not yet contain the feature under development, e.g. OTEL SDK).
#
# The tag must exist in the kind node: `kind load docker-image odg-core:<tag>`.
# This script does not touch OTEL env vars — that is kind-observability-on's
# job. Each script does exactly one thing.

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. "${SCRIPT_DIR}/helm-helpers.sh"
. "${SCRIPT_DIR}/odg-workloads.sh"

TAG="${1:-}"
if [ -z "${TAG}" ] || [[ "${TAG}" == -* ]]; then
  echo "usage: $0 <tag>   # e.g. $0 0.1391.0" >&2
  exit 1
fi

NAMESPACE="${NAMESPACE:-odg}"
KUBECONFIG_FILE="${SCRIPT_DIR}/kubeconfig"

k() { kubectl --kubeconfig="${KUBECONFIG_FILE}" "$@"; }

# Pre-flight: refuse to point pods at an image nobody loaded. Use crictl's
# JSON output (whitespace in the table view shifts across cri versions).
if ! docker exec "${CLUSTER_NAME:-odg-local}-worker" crictl images -o json 2>/dev/null \
    | jq -e --arg tag "odg-core:${TAG}" '[.images[].repoTags[]? | select(endswith($tag))] | length > 0' >/dev/null; then
  echo "ERROR: odg-core:${TAG} not loaded in kind cluster '${CLUSTER_NAME:-odg-local}'" >&2
  echo "       fix: kind load docker-image odg-core:${TAG} --name ${CLUSTER_NAME:-odg-local}" >&2
  exit 1
fi

discover_odg_workloads

if [ "${#ODG_RESOURCE[@]}" -eq 0 ]; then
  echo "No ODG workloads found in ${NAMESPACE}."
  exit 0
fi

echo ">>> Patching ${#ODG_RESOURCE[@]} workload(s) to odg-core:${TAG}"
for i in "${!ODG_RESOURCE[@]}"; do
  res="${ODG_RESOURCE[$i]}"
  container="${ODG_CONTAINER[$i]}"
  echo "    ${res}  container=${container}"
  k set image -n "${NAMESPACE}" "${res}" "${container}=odg-core:${TAG}"
done

echo ">>> Waiting for Deployments to roll out"
for i in "${!ODG_RESOURCE[@]}"; do
  res="${ODG_RESOURCE[$i]}"
  [[ "${res}" == deployment/* ]] || continue
  deploy="${res#deployment/}"
  k -n "${NAMESPACE}" rollout status "deployment/${deploy}" --timeout=180s || true
done

echo "✓ odg-core:${TAG} live on ${#ODG_RESOURCE[@]} workload(s)"

. "${SCRIPT_DIR}/port-forwards.sh"
odg_port_forwards "${KUBECONFIG_FILE}" "${NAMESPACE}"
