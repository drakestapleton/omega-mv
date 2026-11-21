"""Reduce one arm's gate, read, query and payload journals to a CSV receipt row."""
import argparse
from collections import defaultdict
import csv
from decimal import Decimal
import math
from pathlib import Path
import re
import sys

SHA256 = re.compile(r"[0-9a-f]{64}")
STRIDE = 18_800_640


def records(directory, name):
    with (directory / (name + ".csv")).open(newline="") as stream:
        yield from csv.DictReader(stream)


def integer(row, key):
    n = int(row[key])
    if n < 0:
        raise ValueError(f"negative {key}")
    return n


def flag(row, key):
    n = integer(row, key)
    if n > 1:
        raise ValueError(f"invalid flag {key}")
    return n


def token(row):
    return integer(row, "turn_id"), integer(row, "token_idx")


def percentile(values, percent):
    return sorted(values)[math.ceil(len(values) * percent / 100) - 1]


def ratio(n, d):
    return Decimal(n) / Decimal(d) if d else None


def reduce(directory):
    reads = {}
    for r in records(directory, "reads"):
        ticket = integer(r, "ticket")
        category = r["kind"]
        issue, done, size = (integer(r, k) for k in ("issue_ns", "complete_ns", "bytes"))
        if (not ticket or ticket in reads or category not in {"demand", "prefetch"}
                or done <= issue or size != STRIDE):
            raise ValueError("invalid or duplicate read")
        reads[ticket] = (category, done, size, integer(r, "layer_id"), integer(r, "expert"))

    timeline = {}
    for r in records(directory, "tokens"):
        t = token(r)
        if t in timeline or not integer(r, "decode_ns"):
            raise ValueError("invalid token timing")
        timeline[t] = (integer(r, "decode_ns"), flag(r, "first_return"))
        if timeline[t][1] and t[1] != 0:
            raise ValueError("return marker past first token")

    cpu = dict.fromkeys(timeline, 0)
    timed = set()
    for r in records(directory, "queries"):
        t = token(r)
        cpu[t] += integer(r, "cpu_ns")
        timed.add(t)
    if timed != timeline.keys():
        raise ValueError("missing token CPU accounting")

    cold = lead = hits = z2 = returns = requests = stalls = 0
    grouped = defaultdict(set)
    for r in records(directory, "gates"):
        t = token(r)
        layer, expert = integer(r, "layer_id"), integer(r, "expert")
        group = grouped[t, layer]
        if t not in timeline or layer >= 40 or expert >= 384 or expert in group:
            raise ValueError("invalid gate demand")
        group.add(expert)
        need = integer(r, "need_ns")
        ticket = integer(r, "ticket")
        shadow = flag(r, "shadow_cold")
        hit = flag(r, "resident_hit")
        zone = integer(r, "zone")
        if zone not in {0, 2, 3}:
            raise ValueError("unknown zone")
        cold += shadow
        hits += hit
        if ticket:
            kind, done, _, read_layer, read_expert = reads[ticket]
            if (read_layer, read_expert) != (layer, expert):
                raise ValueError("read identity mismatch")
            if kind == "prefetch" and done < need and shadow and hit:
                lead += 1
        if not hit and not ticket:
            raise ValueError("miss without exact read")
        if timeline[t][1]:
            returns += 1
            z2 += hit and zone == 2
        requests += 1
    if (not timeline or len(grouped) != 40 * len(timeline)
            or any(len(route) != 6 for route in grouped.values())):
        raise ValueError("incomplete routed token")

    stall_groups = set()
    for r in records(directory, "layers"):
        key = token(r), integer(r, "layer_id")
        if key in stall_groups or key not in grouped:
            raise ValueError("unexpected layer stall")
        stall_groups.add(key)
        stalls += integer(r, "stall_ns")
    if stall_groups != grouped.keys():
        raise ValueError("missing layer stalls")

    expected_audits = {}
    detour_evictions = 0
    for r in records(directory, "hints"):
        hint = integer(r, "hint_id")
        if hint in expected_audits:
            raise ValueError("duplicate hint")
        state = r["hint_state"]
        residents = set()
        for value in r["resident_keys"].split():
            key = int(value)
            if not 0 <= key < 40 * 384 or key in residents:
                raise ValueError("invalid resident key")
            residents.add(key)
        expected_audits[hint] = (state, residents)
    for r in records(directory, "evictions"):
        detour_evictions += integer(r, "zone") == 2 and flag(r, "during_detour")
    audits = defaultdict(int)
    for r in records(directory, "payloads"):
        before, after, expected = (r[k] for k in ("before_sha256", "after_sha256", "source_sha256"))
        if not SHA256.fullmatch(expected) or before != expected or after != expected:
            raise ValueError("resident payload mismatch")
        state, remaining = expected_audits[integer(r, "hint_id")]
        remaining.remove(integer(r, "resident_key"))
        audits[state] += 1
    if any(pending for _, pending in expected_audits.values()):
        raise ValueError("missing resident payload observations")
    prefetched = sum(r[2] for r in reads.values() if r[0] == "prefetch")
    demand = sum(r[2] for r in reads.values() if r[0] == "demand")
    # Demand-only arms have no advisory events. Speculative arms must exercise
    # all three states before their integrity claim can support a verdict.
    coverage = all(audits[k] for k in ("pending", "duplicate", "rejected"))
    return {
        "tokens": len(timeline), "routed_requests": requests, "shadow_cold": cold,
        "on_time_cold_fills": lead, "effective_lead_hit_rate": ratio(lead, cold),
        "detour_z2_evictions": detour_evictions, "return_z2_hits": z2, "return_requests": returns,
        "detour_first_token_z2_hit_rate": ratio(z2, returns),
        "prefetch_bytes": prefetched, "demand_bytes": demand,
        "consumed_bytes": requests * STRIDE,
        "read_amplification": ratio(prefetched + demand, requests * STRIDE),
        "adjusted_hit_rate": 1 - ratio(len(reads), requests),
        "loads_per_token": ratio(len(reads), len(timeline)),
        "net_stall_ns": stalls,
        "predictor_cpu_us_p50": ratio(percentile(cpu.values(), 50), 1000),
        "predictor_cpu_us_p95": ratio(percentile(cpu.values(), 95), 1000),
        "cpu_fraction_p95": percentile([ratio(cpu[t], timeline[t][0]) for t in cpu], 95),
        "resident_digest_checks": sum(audits.values()),
        "payload_hash_integrity": "PASS" if coverage else "NOT_RUN",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journal_dir", type=Path)
    args = parser.parse_args()
    row = reduce(args.journal_dir)
    writer = csv.DictWriter(sys.stdout, row.keys())
    writer.writeheader()
    writer.writerow(row)
