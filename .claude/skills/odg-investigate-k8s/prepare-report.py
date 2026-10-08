#!/usr/bin/env python3
"""
Pre-process raw snapshot artifacts into a single compact markdown summary.
Usage: prepare-report.py <SNAP_DIR> <NS>
Writes: <SNAP_DIR>/data.md
"""

import sys, os, re, glob, json
from collections import defaultdict

SNAP_DIR = sys.argv[1]
NS = sys.argv[2] if len(sys.argv) > 2 else sys.exit("Usage: prepare-report.py <SNAP_DIR> <NS>")
AVG_THRESHOLD_S = 0.1
BLOAT_THRESHOLD_PCT = 10.0


def find_latest(pattern):
    files = glob.glob(os.path.join(SNAP_DIR, pattern))
    return max(files) if files else None


def table(headers, rows):
    """Return markdown table lines."""
    lines = ["| " + " | ".join(headers) + " |",
             "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(c) for c in row) + " |")
    return lines


# ── Pod health ────────────────────────────────────────────────────────────────

def pods_summary(pods_json, top_txt):
    top = {}
    if top_txt and os.path.exists(top_txt):
        with open(top_txt) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[0] != "NAME":
                    top[parts[0]] = {"cpu": parts[1], "mem": parts[2]}

    with open(pods_json) as f:
        items = json.load(f)["items"]

    pods = []
    for item in items:
        name = item["metadata"]["name"]
        phase = item["status"].get("phase", "Unknown")
        cs = item["status"].get("containerStatuses", [{}])[0]
        restarts = cs.get("restartCount", 0)
        last_state = cs.get("lastState", {})
        last_reason = list(last_state.values())[0].get("reason", "") if last_state else ""
        t = top.get(name, {})
        pods.append({"name": name, "phase": phase, "restarts": restarts,
                     "last_reason": last_reason or "-",
                     "cpu": t.get("cpu", "-"), "mem": t.get("mem", "-")})

    out = []
    bad = [p for p in pods if p["phase"] not in ("Running", "Succeeded") or p["restarts"] > 0]
    if bad:
        out.append("**Anomalous pods**")
        out.extend(table(
            ["Pod", "Phase", "Restarts", "Last reason", "CPU", "Mem"],
            [[p["name"], p["phase"], p["restarts"], p["last_reason"], p["cpu"], p["mem"]] for p in bad]
        ))
        out.append("")
    out.append("**All pods**")
    out.extend(table(
        ["Pod", "Phase", "Restarts", "CPU", "Mem"],
        [[p["name"], p["phase"], p["restarts"], p["cpu"], p["mem"]] for p in pods]
    ))
    return out


# ── BacklogItems ──────────────────────────────────────────────────────────────

def backlog_summary(path):
    with open(path) as f:
        items = json.load(f).get("items", [])
    claimed, unclaimed = [], []
    for item in items:
        name = item["metadata"]["name"]
        ts = item["metadata"].get("creationTimestamp", "")
        is_claimed = bool(item.get("spec", {}).get("claimed") or item.get("status", {}).get("claimed"))
        (claimed if is_claimed else unclaimed).append((name, ts))
    # sort unclaimed oldest-first (longest time in queue)
    unclaimed.sort(key=lambda x: x[1])
    claimed.sort(key=lambda x: x[1])
    return claimed, unclaimed


# ── Memory ────────────────────────────────────────────────────────────────────

def memory_row(path):
    with open(path) as f:
        content = f.read()
    d = {}
    for key in ("VmRSS", "VmPeak", "VmSwap"):
        m = re.search(rf"{key}:\s+(\d+)", content)
        d[key] = int(m.group(1)) // 1024 if m else 0
    m = re.search(r"FDs:\s+(\d+)", content)
    d["FDs"] = int(m.group(1)) if m else 0
    return d


# ── Prometheus outliers ───────────────────────────────────────────────────────

def metrics_outliers(path):
    buckets = defaultdict(list)
    sums, counts = {}, {}
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            m = re.match(r'request_latency_seconds_bucket\{endpoint="([^"]+)",le="([^"]+)",method="([^"]+)"\}\s+([\d.e+]+)', line)
            if m:
                ep, le_s, meth, val = m.groups()
                le = float("inf") if le_s == "+Inf" else float(le_s)
                buckets[(ep, meth)].append((le, float(val)))
                continue
            m = re.match(r'request_latency_seconds_(sum|count)\{endpoint="([^"]+)",method="([^"]+)"\}\s+([\d.e+]+)', line)
            if m:
                kind, ep, meth, val = m.groups()
                (sums if kind == "sum" else counts)[(ep, meth)] = float(val)

    def percentile(key, p):
        n = counts.get(key, 0)
        if not n:
            return None
        bkts = sorted(buckets.get(key, []))
        target, prev_le, prev_c = n * p, 0.0, 0.0
        for le, c in bkts:
            if c >= target:
                if le == float("inf"):
                    return prev_le
                return prev_le + (le - prev_le) * (target - prev_c) / max(c - prev_c, 1)
            prev_le, prev_c = le, c
        return prev_le

    rows = []
    for key, n in counts.items():
        if not n:
            continue
        avg = sums.get(key, 0) / n
        if avg < AVG_THRESHOLD_S:
            continue
        rows.append({"endpoint": key[0], "method": key[1], "count": int(n), "avg_s": avg,
                     "p50_s": percentile(key, 0.50), "p99_s": percentile(key, 0.99)})
    return sorted(rows, key=lambda r: r["avg_s"], reverse=True)


# ── PostgreSQL health ─────────────────────────────────────────────────────────

def pg_summary(path):
    with open(path) as f:
        content = f.read()

    def section(name):
        if f"=== {name} ===" not in content:
            return ""
        return content.split(f"=== {name} ===")[1].split("===")[0]

    long_sessions = []
    for line in section("active sessions").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 2 and re.match(r"\d+", parts[0]):
            m = re.search(r"(\d+):(\d+):(\d+)", parts[1])
            if m:
                secs = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))
                if secs > 60:
                    long_sessions.append([
                        parts[0],
                        parts[1],
                        parts[2] if len(parts) > 2 else "?",
                        parts[4] if len(parts) > 4 else "?",
                        (parts[-1][:80] if parts else ""),
                    ])

    blockers = []
    for line in section("blocker graph").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 3 and re.match(r"\d+", parts[0]):
            blockers.append([parts[0], parts[2] if len(parts) > 2 else "?",
                             parts[4] if len(parts) > 4 else "?"])

    pool_line = "?"
    for line in section("connection pool").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 3 and re.match(r"\d+", parts[0]):
            pool_line = f"total={parts[0]}  active={parts[1]}  lock_waiting={parts[2]}"
            break

    rollback = "(0 rows — no data)"
    for line in section("rollback rate").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 4 and re.match(r"\w", parts[0]) and parts[0] != "datname":
            rollback = f"{parts[0]}: rollback_pct={parts[3]}"
            break

    bloat = []
    for line in section("table bloat").splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 4 and re.match(r"\w", parts[0]):
            try:
                pct = float(parts[3])
                if pct >= BLOAT_THRESHOLD_PCT:
                    bloat.append([parts[0], parts[1], parts[2], f"{pct}%",
                                  parts[4].strip() if len(parts) > 4 else "?"])
            except ValueError:
                pass

    return pool_line, rollback, long_sessions, blockers, bloat


# ── K8s events (Warning + Error) ─────────────────────────────────────────────

def events_summary(warnings_json, ns):
    if not warnings_json or not os.path.exists(warnings_json):
        return [], []
    with open(warnings_json) as f:
        items = json.load(f).get("items", [])
    items = sorted(items, key=lambda e: e.get("lastTimestamp") or e["metadata"].get("creationTimestamp", ""))[-25:]
    delivery, other = [], []
    for e in items:
        event_ns = e["metadata"]["namespace"]
        etype = e.get("type", "")
        reason = e.get("reason", "")
        obj = e["involvedObject"].get("name", "")
        msg = e.get("message", "")[:100]
        ts = e.get("lastTimestamp") or e["metadata"].get("creationTimestamp", "")
        row = [etype, ts, reason, obj, msg]
        (delivery if event_ns == ns else other).append(row)
    return delivery, other


# ── Assemble summary ──────────────────────────────────────────────────────────

out = []

# Pod health
pods_json = find_latest("pods-*.json")
pods_top = find_latest("pods-top-*.txt")
if pods_json:
    out.append("## Pod health")
    out.extend(pods_summary(pods_json, pods_top))
    out.append("")

# BacklogItems
f = find_latest("backlog-*.json")
if f:
    claimed, unclaimed = backlog_summary(f)
    total = len(claimed) + len(unclaimed)
    out.append("## BacklogItems")
    out.append(f"**total={total}  claimed={len(claimed)}  unclaimed={len(unclaimed)}**")
    out.append("")
    if unclaimed:
        # top 10 (oldest) + ellipsis + last 5 (newest)
        rows = []
        show = unclaimed[:10]
        tail = unclaimed[-5:] if len(unclaimed) > 15 else []
        for name, ts in show:
            rows.append([name, ts])
        if tail:
            rows.append(["...", f"({len(unclaimed) - 15} more)"])
            for name, ts in tail:
                rows.append([name, ts])
        out.extend(table(["Name", "Queued at (oldest first)"], rows))
        out.append("")
    if claimed:
        out.extend(table(["Name", "Queued at"], [[n, ts] for n, ts in claimed]))
        out.append("")

# Pod memory
mem_files = sorted(glob.glob(os.path.join(SNAP_DIR, "*/memory-*.txt")))
if mem_files:
    out.append("## Pod memory")
    rows = []
    for mf in mem_files:
        pod = os.path.basename(os.path.dirname(mf))
        d = memory_row(mf)
        rows.append([pod, d["VmRSS"], d["VmPeak"], d["VmSwap"], d["FDs"]])
    out.extend(table(["Pod", "VmRSS (MB)", "VmPeak (MB)", "VmSwap (MB)", "FDs"], rows))
    out.append("")

# Slow endpoints
metrics_files = sorted(glob.glob(os.path.join(SNAP_DIR, "*/metrics-*.txt")))
if metrics_files:
    out.append(f"## Slow endpoints (avg > {AVG_THRESHOLD_S}s)")
    for mf in metrics_files:
        pod = os.path.basename(os.path.dirname(mf))
        rows = metrics_outliers(mf)
        out.append(f"\n**{pod}**")
        if not rows:
            out.append("_none_")
            continue
        out.extend(table(
            ["Endpoint", "Method", "Count", "avg (s)", "p50 (s)", "p99 (s)"],
            [[r["endpoint"], r["method"], r["count"],
              f"{r['avg_s']:.3f}",
              f"{r['p50_s']:.3f}" if r["p50_s"] is not None else "?",
              f"{r['p99_s']:.3f}" if r["p99_s"] is not None else "?"] for r in rows]
        ))
    out.append("")

# PostgreSQL health
f = find_latest("delivery-db-0/pg-health-*.txt")
if f:
    pool, rollback, long_sessions, blockers, bloat = pg_summary(f)
    out.append("## PostgreSQL")
    out.append(f"**Connections:** {pool}  **Rollback rate:** {rollback}")
    out.append("")
    if long_sessions:
        out.append("**Long-running sessions (> 1 min)**")
        out.extend(table(["PID", "Age", "State", "Wait event", "Query (truncated)"], long_sessions))
        out.append("")
    if blockers:
        out.append("**Blockers**")
        out.extend(table(["Blocked PID", "Blocking PID", "Blocking age"], blockers))
        out.append("")
    out.append(f"**Table bloat (> {BLOAT_THRESHOLD_PCT}% dead tuples)**")
    if bloat:
        out.extend(table(["Table", "Live rows", "Dead rows", "Dead %", "Last autovacuum"], bloat))
    else:
        out.append("_none_")
    out.append("")

# K8s Warning/Error events
warnings_json = find_latest("events-warnings-*.json")
delivery_w, other_w = events_summary(warnings_json, NS)
out.append("## K8s warning/error events")
out.append(f"\n**`{NS}` namespace**")
if delivery_w:
    out.extend(table(["Type", "Timestamp", "Reason", "Object", "Message"], delivery_w))
else:
    out.append("_none_")
out.append("\n**Other namespaces**")
if other_w:
    out.extend(table(["Type", "Timestamp", "Reason", "Object", "Message"], other_w))
else:
    out.append("_none_")

# Write
out_path = os.path.join(SNAP_DIR, "data.md")
with open(out_path, "w") as f:
    f.write("\n".join(out) + "\n")
print(f"Written: {out_path}")
