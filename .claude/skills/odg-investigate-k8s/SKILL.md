---
name: odg-investigate-k8s
description: Investigate anomalies in ODG on Kubernetes
allow-tools: Bash, Read, Write
---

You are orchestrating an investigation of ODG running on Kubernetes. Each phase runs in an
isolated subagent with only the instructions and data it needs — subagents must not read
reports from prior iterations.

## Setup

1. Ask the user to describe the observed issue.
2. Verify the active cluster context and confirm it is the intended target. Run all of the
   following commands and show their combined output to the user:
   ```sh
   kubectl config view --minify
   ```
   Extract from the output and present the results in a small table:

   | Field | Value |
   |-------|-------|
   | Context | ... |
   | User | ... |
   | Server | ... |
   | Shoot | ... |

   Ask: "Is this the correct cluster?"
   Record the confirmed cluster name for use in TASK.md. Do not proceed until the user confirms.
3. Verify cluster access: `kubectl get ns`
4. Ask for the namespace ODG runs in (default: `delivery`). Store as `$NS`.
5. Ask if this should be a one-off snapshot or a loop. Make a suggestion.
   - If loop: suggest interval (e.g. `5m`) and spawn each snapshot as a separate subagent.
6. Create the report folder and TASK.md:

```sh
mkdir -p ${CLAUDE_SKILL_DIR}/reports/<num>-<short-title>
```

Write `${CLAUDE_SKILL_DIR}/reports/<num>-<short-title>/TASK.md` using the write tool with this content, filling in
the actual values.

```markdown
# Investigation: <short-title>

| Field | Value |
|-------|-------|
| User | <username> |
| Server | <server-url> |
| Shoot | <shoot-name> |
| Context | <cluster-context> |
| Namespace (NS) | <namespace> |
| Report dir (REPORT_DIR) | ${CLAUDE_SKILL_DIR}/reports/<num>-<short-title> |


## Snapshots
| # | Timestamp | Report | Noteworthy |
|---|-----------|--------|------------|

## Anomalous pods
<!-- Populated by orchestrator as snapshots complete -->

## Status
<!-- pending / running / final-gather / observations / analysis / done -->
pending
```

## Analysis loop — one subagent per snapshot

Before spawning each snapshot subagent, update TASK.md:
- Set `Status` to `running`
- Note the snapshot number and start timestamp in the Snapshots table

Spawn a **`odg-investigate-k8s-gather-snapshot`** subagent. Its entire brief is:
- The path to `TASK.md` (the subagent reads params from it)
- The snapshot number `N`

**Do not pass prior iteration reports to the subagent.** Each snapshot is independent.

After each snapshot subagent returns:
- Write its output to `$REPORT_DIR/snapshot-$N/report.md`
- Append the report path and one-line noteworthy summary to the Snapshots table in TASK.md
- Update the Anomalous pods list in TASK.md
- Present noteworthy findings to the user as a progress update

## Final data gathering

Update TASK.md status to `final-gather`. Spawn a **`odg-investigate-k8s-gather-final`** subagent with:
- The path to `TASK.md`

**Do not pass prior iteration reports to the subagent.**

When the report returns:
* Update TASK.md status to `observations`
* Never read any of the log files or raw data!
* Use the returned reports and write `${CLAUDE_SKILL_DIR}/reports/<num>-<short-title>/observations.md` with this structure:

```markdown
# Observations: <short-title>

## Initial user observation
<!-- Verbatim or close paraphrase of what the user reported -->

## Top anomalies
<!-- Ordered by severity/relevance. Each entry: what, which snapshots, likely evidence -->

1. **<anomaly title>**
   - Observed snapshot N–M, pods: ...

2. ...

## Supporting evidence index
- Pod memory: `${CLAUDE_SKILL_DIR}/reports/.../snapshot-*/<pod>/memory-*.txt`
- Logs: `${CLAUDE_SKILL_DIR}/reports/.../logs/<pod>/logs-<pod>.txt`
- DB health: `${CLAUDE_SKILL_DIR}/reports/.../snapshot-*/delivery-db-0/pg-health-*.txt`
- Metrics: `${CLAUDE_SKILL_DIR}/reports/.../snapshot-*/<pod>/metrics-*.txt`
```

## Anomaly analysis

Ask the user which anomaly to analyse first.
Update TASK.md status to `analysis: <name>`

Spawn a **`odg-investigate-k8s-analyse-anomaly`** subagent with:
- The path to `TASK.md`
- The name/description of the evidence
- Relevant context and file pointers (only for the selected anomaly)

Do not read the files or data!

When finished, write `$REPORT_DIR/analysis-<anomaly-short-title>.md` using the returned output.
You may add links and additional context.

If finished, ask the user if further anomalies should be analysed.

Update TASK.md status to `done` when complete.

## Rules

- Never run other commands without user permission.
- Never modify cluster state.
- Never fix code or issues — only analyse.
- Never stop processes or free up resources — only analyse.
- Never suggest fixes, workarounds or recommended actions — only observations, evidence, and hypotheses.
- Only start anomaly analysis when final data gathering and the observations report are complete.
