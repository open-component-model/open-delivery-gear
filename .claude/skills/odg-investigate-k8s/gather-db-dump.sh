#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${1:?missing report dir}"
NS="${2:?missing namespace}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
REMOTE="/tmp/db-dump-${TIMESTAMP}.dump"
OUT="${REPORT_DIR}/db-dump-${TIMESTAMP}.dump"

cleanup() {
    kubectl exec -n "${NS}" delivery-db-0 -- rm -f "${REMOTE}" 2>/dev/null || true
}
trap cleanup EXIT

# Dump in custom format (compressed) directly on the pod, then copy out.
# Avoids piping 2+ GB over the kubectl exec websocket which times out.
kubectl exec -n "${NS}" delivery-db-0 -- pg_dump -U postgres -Fc -f "${REMOTE}"
kubectl cp "${NS}/delivery-db-0:${REMOTE}" "${OUT}"

echo "Written: ${OUT}"
