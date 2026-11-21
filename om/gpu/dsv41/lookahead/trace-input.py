"""Validate a native gate CSV and project its IDs to the ST replay stream."""
import argparse
import csv
import math
import struct
import sys


def project(rows, horizon, output):
    required = {"turn_id", "token_idx", "layer_id", "top_k_experts",
                "gate_weights", "gate_ready_ns", "expert_need_ns"}
    if not required.issubset(rows.fieldnames or []):
        raise ValueError("missing native gate columns")
    output.write(struct.pack("<I", horizon))
    previous = None
    for row in rows:
        turn, token, layer, ready, need = (
            int(row[key]) for key in ("turn_id", "token_idx", "layer_id",
                                     "gate_ready_ns", "expert_need_ns")
        )
        experts = [int(x) for x in row["top_k_experts"].split()]
        weights = [float(x) for x in row["gate_weights"].split()]
        if (len(experts) != 6 or len(set(experts)) != 6 or
                any(e < 0 or e >= 384 for e in experts) or len(weights) != 6 or
                any(not math.isfinite(w) or w < 0 for w in weights)):
            raise ValueError(f"invalid native route at {(turn, token, layer)}")
        if min(turn, token, layer, ready) < 0 or need < ready:
            raise ValueError("invalid coordinates or gate clock")
        if previous is None:
            valid = layer == 0 and token == 0
        else:
            last_turn, last_token, last_layer, last_need = previous
            valid = ready >= last_need and (
                (last_layer < 39 and
                 (turn, token, layer) == (last_turn, last_token, last_layer + 1)) or
                (last_layer == 39 and layer == 0 and
                 ((turn == last_turn and token == last_token + 1) or
                  (turn == last_turn + 1 and token == 0)))
            )
        if not valid:
            raise ValueError(f"discontinuous gate trace at {(turn, token, layer)}")
        output.write(struct.pack("<6I", *experts))
        previous = turn, token, layer, need
    if previous is None or previous[2] != 39:
        raise ValueError("missing final layer")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace")
    parser.add_argument("horizon", type=int, choices=[1, 2, 3, 4, 40, 80])
    args = parser.parse_args()
    with open(args.trace, newline="") as stream:
        project(csv.DictReader(stream), args.horizon, sys.stdout.buffer)
