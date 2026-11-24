#!/usr/bin/env python3
"""Summarize dsv41 Arboris prefetch A/B runs. usage: summarize.py RUNS_DIR RUN_ID... > summary.json"""
import hashlib, json, os, re, statistics, struct, sys


def routing_sha(path):
    """SHA-256 over (turn, token, layer, 6 expert ids, 6 gate weights) per 80-byte record; no timestamps."""
    raw = open(path, "rb").read()
    h = hashlib.sha256()
    for i in range(len(raw) // 80):
        h.update(raw[i * 80:i * 80 + 12])
        h.update(raw[i * 80 + 16:i * 80 + 64])
    return h.hexdigest(), len(raw) // 80

runs_dir, ids = sys.argv[1], sys.argv[2:]
rows = []
for rid in ids:
    r = os.path.join(runs_dir, rid)
    rd = lambda f: open(os.path.join(r, f)).read().strip()
    stats = rd("stats")
    m = re.search(r"STATS hits=(\d+) misses=(\d+) nvme_ns=(\d+) gpu_ns=(\d+) engram_ns=(\d+) trace_sha256=([0-9a-f]{64})", stats)
    a = re.search(r"ARBORIS pf_dispatched=(\d+) pf_hits=(\d+) pf_enabled=(\d)", stats)
    tokens = rd("tokens").split()
    rsha, nrec = routing_sha(os.path.join(r, "trace.bin"))
    rows.append({
        "routing_sha256": rsha, "trace_records": nrec,
        "run": rid, "arm": int(rd("arm")), "rc": int(rd("rc")), "wall_ns": int(rd("wall_ns")),
        "cache_before": rd("cache-before"),
        "preflight": rd("preflight") if os.path.exists(os.path.join(r, "preflight")) else None,
        "binary_sha256": rd("binary.sha256").split()[0] if os.path.exists(os.path.join(r, "binary.sha256")) else None,
        "hits": int(m[1]), "misses": int(m[2]), "nvme_ns": int(m[3]), "gpu_ns": int(m[4]), "engram_ns": int(m[5]),
        "trace_sha256": m[6], "pf_dispatched": int(a[1]), "pf_hits": int(a[2]), "pf_enabled": int(a[3]),
        "n_tokens": len(tokens), "tokens": " ".join(tokens),
    })

def arm(k):
    sel = [x for x in rows if x["arm"] == k]
    out = {"n": len(sel)}
    for f in ("wall_ns", "nvme_ns", "gpu_ns", "misses", "hits", "pf_dispatched", "pf_hits"):
        v = [x[f] for x in sel]
        out[f] = {"median": statistics.median(v), "min": min(v), "max": max(v), "values": v}
    return out

summary = {"runs": rows, "off": arm(0), "on": arm(1),
           "checks": {
               "all_rc_zero": all(x["rc"] == 0 for x in rows),
               "all_cold": all(x["cache_before"].split()[0] == "0" for x in rows),
               "arm_label_matches": all(x["pf_enabled"] == x["arm"] for x in rows),
               "off_dispatched_nothing": all(x["pf_dispatched"] == 0 and x["pf_hits"] == 0 for x in rows if x["arm"] == 0),
               "on_dispatched_something": all(x["pf_dispatched"] > 0 for x in rows if x["arm"] == 1),
               "tokens_identical": len({x["tokens"] for x in rows}) == 1,
               "routing_identical": len({x["routing_sha256"] for x in rows}) == 1,
               "one_binary": len({x["binary_sha256"] for x in rows}) == 1,
               "preflight_matches_arm": all(x["preflight"] in (None, "ARBORIS pf_enabled=%d" % x["arm"]) for x in rows),
           }}
json.dump(summary, sys.stdout, indent=1)
print()
