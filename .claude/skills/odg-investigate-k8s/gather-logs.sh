#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${1:?missing report dir}"
NS="${2:?missing namespace}"
POD="${3:?missing pod name}"
LINES="${4:-500}"

kubectl logs "$POD" -n "$NS" --tail="$LINES" > "${REPORT_DIR}/logs-${POD}.txt" 2>&1
echo "Written: ${REPORT_DIR}/logs-${POD}.txt"

kubectl logs "$POD" -n "$NS" --previous --tail="$LINES" \
  > "${REPORT_DIR}/logs-${POD}-prev.txt" 2>&1 || true
echo "Written: ${REPORT_DIR}/logs-${POD}-prev.txt"
