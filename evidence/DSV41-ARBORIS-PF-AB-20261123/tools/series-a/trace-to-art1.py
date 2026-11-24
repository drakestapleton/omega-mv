#!/usr/bin/env python3
"""Measuring instrument: convert a dsv41-decode 80-byte router trace into the ART1 stream that
tests/arboris/online_adapt_bench.om replays. usage: trace-to-art1.py TRACE BUDGET BUCKET CACHECAP > out.art1
Also prints residency facts to stderr: distinct (layer, expert) pairs and first-use counts."""
import struct, sys

path, budget, bucket, cap = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
raw = open(path, "rb").read()
recs = []
for i in range(len(raw) // 80):
    r = struct.unpack_from("<4I6I", raw, i * 80)
    recs.append((r[0], r[1], r[2], r[4:10]))
recs.sort(key=lambda r: (r[0], r[1], r[2]))
layers, topk, experts = 40, 6, 384
tokens = len(recs) // layers
assert len(recs) == tokens * layers
for t in range(tokens):
    for l in range(layers):
        assert recs[t * layers + l][2] == l
out = sys.stdout.buffer
out.write(struct.pack("<8I", 0x31545241, layers, experts, topk, tokens, budget, bucket, cap))
seen = set()
first = 0
for r in recs:
    out.write(struct.pack("<6I", *r[3]))
    for e in r[3]:
        if (r[2], e) not in seen:
            seen.add((r[2], e))
            first += 1
print(f"tokens={tokens} lookups={len(recs) * topk} distinct_layer_expert={len(seen)}", file=sys.stderr)
