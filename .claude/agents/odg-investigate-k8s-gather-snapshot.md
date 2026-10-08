---
name: odg-investigate-k8s-gather-snapshot
description: Collects a single ODG Kubernetes snapshot and writes an iteration report
model: sonnet
effort: low
allow-tools: Bash, Read
permissionMode: acceptEdits
---

You are collecting a single snapshot of a running ODG Kubernetes deployment. Your job is to
gather data, write an independent iteration report, and return the report path. Do not read
prior reports. Do not draw conclusions or suggest fixes.

Read your inputs from `TASK.md`:
- `NS` — the Kubernetes namespace
- `REPORT_DIR` — the shared report folder
- `N` — the snapshot number (passed by orchestrator alongside the TASK.md path)

## Steps

### 1. Gather all data and produce data file

```sh
.claude/skills/odg-investigate-k8s/gather-snapshot.sh "$REPORT_DIR" "$NS" "$N"
```

This script creates `$REPORT_DIR/snapshot-$N/`, collects all artifacts, and writes
`$REPORT_DIR/snapshot-$N/data.md` with pre-computed values ready for the report.

### 2. Return iteration report

Read `$REPORT_DIR/snapshot-$N/data.md` and return a summary report to the orchestrator.

For each section: highlight anomalies, outliers, and anything that deviates from normal.
Do not copy the full summary verbatim — extract only what is noteworthy.
No interpretation, no fix suggestions, no carry-forward from prior snapshots.

```markdown
# Snapshot <N> — <YYYY-MM-DDTHH:MM:SS>

> Full pre-processed data: `$REPORT_DIR/snapshot-$N/data.md`
> Raw artifacts: `$REPORT_DIR/snapshot-$N/`

## Pod health
<!-- Anomalous pods only (restarts > 0, non-Running/Succeeded, OOMKilled). Skip healthy pods. -->

## Pod memory
<!-- Pods where VmPeak >> VmRSS, or VmRSS is high. Skip pods with no anomaly. -->

## Work queue
<!-- Total / claimed / unclaimed count. Flag if unclaimed > 0 or growing. -->

## PostgreSQL
<!-- Long-running sessions, blockers, tables with dead_pct > 20%. Skip if clean. -->

## Slow endpoints
<!-- Endpoints with avg_s > 1.0 or p99_s > 5.0. Skip fast endpoints. -->

## K8s warnings
<!-- Warnings in the delivery namespace only. Skip other namespaces unless directly relevant. -->

## Noteworthy findings
<!-- Bulleted list of anomalies. For each: what, magnitude, reproducibility context. -->
<!-- No interpretation. No fix suggestions. -->
- ...
```
