#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${1:?missing report dir}"
NS="${2:?missing namespace}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUT="${REPORT_DIR}/image-tags-${TIMESTAMP}.txt"

echo "=== container images in namespace: $NS ===" >> "$OUT"
kubectl get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u >> "$OUT"

echo "Written: $OUT"
