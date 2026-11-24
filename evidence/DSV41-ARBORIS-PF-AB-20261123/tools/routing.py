#!/usr/bin/env python3
"""Measuring instrument: strip timestamps from a dsv41-decode 80-byte router trace.
usage: routing.py TRACE OUT
OUT holds, per record, bytes 0..11 (turn, token, layer) and 16..63 (6 expert ids, 6 gate weights): 60 bytes.
Runs with the same routing produce byte-identical OUT files."""
import sys

raw = open(sys.argv[1], "rb").read()
if len(raw) == 0 or len(raw) % 80:
    sys.exit("bad trace size %d" % len(raw))
with open(sys.argv[2], "wb") as f:
    for i in range(len(raw) // 80):
        f.write(raw[i * 80:i * 80 + 12])
        f.write(raw[i * 80 + 16:i * 80 + 64])
