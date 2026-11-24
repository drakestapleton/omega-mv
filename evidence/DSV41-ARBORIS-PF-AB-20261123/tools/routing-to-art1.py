#!/usr/bin/env python3
"""Convert a stored routing.bin (60-byte records: turn, token, layer, 6 expert ids, 6 gate weights) into the
ART1 stream that tests/arboris/online_adapt_bench.om replays.
usage: routing-to-art1.py ROUTING_BIN BUDGET BUCKET CACHECAP > out.art1"""
import struct, sys


def art1(raw, budget, bucket, cap):
    recs = []
    for i in range(len(raw) // 60):
        turn, tok, layer = struct.unpack_from("<3I", raw, i * 60)
        recs.append((turn, tok, layer, struct.unpack_from("<6I", raw, i * 60 + 12)))
    recs.sort(key=lambda r: (r[0], r[1], r[2]))
    layers, topk, experts = 40, 6, 384
    tokens = len(recs) // layers
    assert len(recs) == tokens * layers and tokens > 0
    for t in range(tokens):
        for l in range(layers):
            assert recs[t * layers + l][2] == l
    out = [struct.pack("<8I", 0x31545241, layers, experts, topk, tokens, budget, bucket, cap)]
    out.extend(struct.pack("<6I", *r[3]) for r in recs)
    return b"".join(out)


if __name__ == "__main__":
    data = open(sys.argv[1], "rb").read()
    sys.stdout.buffer.write(art1(data, int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])))
