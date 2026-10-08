#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${1:?missing report dir}"
NS="${2:?missing namespace}"
N="${3:?missing snapshot number}"

SNAP_DIR="${REPORT_DIR}/snapshot-${N}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
mkdir -p "$SNAP_DIR"
echo "Snapshot dir: $SNAP_DIR"

SKILL_DIR="$(dirname "$0")"

# Image tags (snapshot 1 only)
if [[ "$N" == "1" ]]; then
  "$SKILL_DIR/gather-image-tags.sh" "$SNAP_DIR" "$NS"
fi

# Work queue
kubectl get BacklogItem -n "$NS" -o json > "$SNAP_DIR/backlog-${TIMESTAMP}.json" 2>&1
echo "Written: $SNAP_DIR/backlog-${TIMESTAMP}.json"

# K8s warning events
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' -o json \
  > "$SNAP_DIR/events-warnings-${TIMESTAMP}.json"
echo "Written: $SNAP_DIR/events-warnings-${TIMESTAMP}.json"

# Pod health
kubectl get pods -n "$NS" -o json > "$SNAP_DIR/pods-${TIMESTAMP}.json"
kubectl top pod -n "$NS" > "$SNAP_DIR/pods-top-${TIMESTAMP}.txt" 2>&1 || true
echo "Written: $SNAP_DIR/pods-${TIMESTAMP}.json $SNAP_DIR/pods-top-${TIMESTAMP}.txt"

# Delivery-service metrics (one port-forward per pod)
for POD in $(kubectl get pods -n "$NS" -l app=delivery-service \
               -o jsonpath='{.items[*].metadata.name}'); do
  POD_DIR="${SNAP_DIR}/${POD}"
  mkdir -p "$POD_DIR"
  OUT="${POD_DIR}/metrics-${TIMESTAMP}.txt"
  LOCAL_PORT=$((5001 + RANDOM % 500))
  kubectl port-forward "pod/${POD}" -n "$NS" "${LOCAL_PORT}:5000" &>/dev/null &
  PF_PID=$!
  sleep 1
  curl -sf "localhost:${LOCAL_PORT}/metrics" > "$OUT" || true
  kill "$PF_PID" 2>/dev/null || true
  echo "Written: $OUT"
done

# PostgreSQL health
DB_POD="delivery-db-0"
DB_DIR="${SNAP_DIR}/${DB_POD}"
mkdir -p "$DB_DIR"
PG_OUT="${DB_DIR}/pg-health-${TIMESTAMP}.txt"
PSQL="kubectl exec -n ${NS} ${DB_POD} -- psql -U postgres -c"

echo "=== active sessions ===" >> "$PG_OUT"
$PSQL "SELECT pid, now() - xact_start AS age, state, wait_event_type, wait_event, client_addr, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY age DESC;" >> "$PG_OUT"
echo "=== blocker graph ===" >> "$PG_OUT"
$PSQL "SELECT blocked.pid, blocked.query, blocker.pid AS blocking_pid, blocker.query AS blocking_query, now() - blocker.xact_start AS blocking_age, blocker.state AS blocking_state FROM pg_stat_activity AS blocked JOIN pg_stat_activity AS blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) ORDER BY blocking_age DESC;" >> "$PG_OUT"
echo "=== held locks (relation+tuple) ===" >> "$PG_OUT"
$PSQL "SELECT pid, locktype, relation::regclass, page, tuple, mode, granted FROM pg_locks WHERE NOT granted OR locktype IN ('relation','tuple') ORDER BY pid;" >> "$PG_OUT"
echo "=== connection pool ===" >> "$PG_OUT"
$PSQL "SELECT count(*) AS total, count(*) FILTER (WHERE state != 'idle') AS active, count(*) FILTER (WHERE wait_event_type = 'Lock') AS lock_waiting FROM pg_stat_activity;" >> "$PG_OUT"
echo "=== rollback rate ===" >> "$PG_OUT"
$PSQL "SELECT datname, xact_commit, xact_rollback, round(xact_rollback::numeric / nullif(xact_commit + xact_rollback, 0) * 100, 1) AS rollback_pct FROM pg_stat_database WHERE datname NOT IN ('postgres', 'template0', 'template1');" >> "$PG_OUT"
echo "=== table bloat ===" >> "$PG_OUT"
$PSQL "SELECT relname, n_live_tup, n_dead_tup, round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct, last_autovacuum, last_autoanalyze FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 20;" >> "$PG_OUT"
echo "Written: $PG_OUT"

# Per-pod memory (delivery-service pods)
for POD in $(kubectl get pods -n "$NS" -l app=delivery-service \
               -o jsonpath='{.items[*].metadata.name}'); do
  POD_DIR="${SNAP_DIR}/${POD}"
  mkdir -p "$POD_DIR"
  OUT="${POD_DIR}/memory-${TIMESTAMP}.txt"
  kubectl exec -n "$NS" "$POD" -- sh -c '
    cat /proc/1/status | grep -E "VmRSS|VmPeak|VmSwap"
    echo "FDs: $(ls /proc/1/fd | wc -l)"
    echo "--- smaps_rollup ---"
    cat /proc/1/smaps_rollup
  ' >> "$OUT" 2>&1 || echo "  (exec failed)" >> "$OUT"
  echo "Written: $OUT"
done

# Pre-process all artifacts into data.md
python3 "$SKILL_DIR/prepare-report.py" "$SNAP_DIR" "$NS"

echo "Done: $SNAP_DIR/data.md"
