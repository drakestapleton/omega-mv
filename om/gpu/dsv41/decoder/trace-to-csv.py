#!/usr/bin/env python3
"""Convert a native 80-byte binary router trace archive to CSV for lookahead A/B."""
import csv
import hashlib
import struct
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit("Usage: trace-to-csv.py TRACE.bin OUT.csv [EXPECTED_SHA256]")
    src, dst = sys.argv[1], sys.argv[2]
    expected = sys.argv[3] if len(sys.argv) > 3 else None
    raw = open(src, "rb").read()
    if len(raw) % 80 != 0 or len(raw) == 0:
        sys.exit(f"Invalid trace size: {len(raw)}")
    digest = hashlib.sha256(raw).hexdigest()
    if expected and digest != expected:
        sys.exit(f"SHA-256 mismatch: got {digest}, expected {expected}")
    n = len(raw) // 80
    with open(dst, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["turn_id", "token_idx", "layer_id", "top_k_experts", "gate_weights", "gate_ready_ns", "expert_need_ns"])
        for i in range(n):
            rec = struct.unpack_from("<4I6I6f2Q", raw, i * 80)
            turn_id, token_idx, layer_id, _res = rec[:4]
            ids = rec[4:10]
            wts = rec[10:16]
            ready_ns, need_ns = rec[16:18]
            w.writerow([
                turn_id,
                token_idx,
                layer_id,
                " ".join(str(x) for x in ids),
                " ".join(f"{x:.7g}" for x in wts),
                ready_ns,
                need_ns,
            ])
    print(f"CONVERTED records={n} tokens={n // 40} sha256={digest}")


if __name__ == "__main__":
    main()
