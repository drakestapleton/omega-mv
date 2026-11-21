"""Regression controls for the lookahead receipt reducer."""
import csv
from decimal import Decimal
from pathlib import Path
import tempfile

from audit import reduce, STRIDE


def journal(root, name, columns, rows):
    with (root / (name + ".csv")).open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(columns.split())
        writer.writerows(rows)


def check(root):
    journal(root, "tokens", "turn_id token_idx decode_ns first_return", [(0, 0, 1000, 1)])
    journal(root, "queries", "turn_id token_idx cpu_ns", [(0, 0, 20)])
    journal(root, "reads", "ticket kind issue_ns complete_ns bytes layer_id expert",
            [(1, "prefetch", 0, 9, STRIDE, 0, 0), (2, "prefetch", 0, 10, STRIDE, 0, 1)])
    demands = []
    for layer in range(40):
        for expert in range(6):
            cold = layer == 0 and expert < 2
            ticket = expert + 1 if cold else 0
            demands.append((0, 0, layer, expert, 10, ticket, int(cold), 1, 2))
    journal(root, "gates", "turn_id token_idx layer_id expert need_ns ticket shadow_cold resident_hit zone", demands)
    journal(root, "layers", "turn_id token_idx layer_id stall_ns", [(0, 0, i, i) for i in range(40)])
    journal(root, "evictions", "zone during_detour", [(3, 1), (2, 0)])
    states = ("pending", "duplicate", "rejected")
    journal(root, "hints", "hint_id hint_state resident_keys", [(i, s, "0 1") for i, s in enumerate(states)])
    columns = "hint_id resident_key before_sha256 after_sha256 source_sha256"
    observations = [(i, k, "a" * 64, "a" * 64, "a" * 64) for i in range(3) for k in range(2)]
    journal(root, "payloads", columns, observations)
    result = reduce(root)
    assert result["effective_lead_hit_rate"] == Decimal("0.5")
    assert result["cpu_fraction_p95"] == Decimal("0.02")
    assert result["detour_first_token_z2_hit_rate"] == 1 and result["detour_z2_evictions"] == 0
    assert result["net_stall_ns"] == 780 and result["payload_hash_integrity"] == "PASS"
    for invalid in (observations[:-1], [(*observations[0][:3], "b" * 64, "a" * 64), *observations[1:]]):
        journal(root, "payloads", columns, invalid)
        try:
            reduce(root)
        except ValueError:
            continue
        raise AssertionError("incomplete or corrupt payload evidence accepted")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        check(Path(tmp))
    print("PASS deadline equality, token CPU accounting, detour hits and hash audit controls")
