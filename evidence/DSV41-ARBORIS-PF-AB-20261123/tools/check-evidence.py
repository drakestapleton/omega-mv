#!/usr/bin/env python3
"""Checks that need no Spark: (1) every figure and hash quoted in REPORT.md appears in a generated or
recorded file of this folder; (2) the replay inputs named in replay.txt are what routing-to-art1.py
produces from the stored routing record.  usage: check-evidence.py EVIDENCE_DIR"""
import hashlib, importlib.util, os, re, sys

root = sys.argv[1]
bad = []


def text(name):
    return open(os.path.join(root, name)).read()


# (1) REPORT.md figures. Sources: generated results plus files recorded on the Spark or listing references.
sources = "\n".join(text(n) for n in ("RESULTS.md", "host.txt", "replay.txt", "refs.txt", "inputs.sha256", "envcheck.txt", "layer0-parity.log"))
report = re.sub(r"```.*?```", "", text("REPORT.md"), flags=re.S)
figures = set(re.findall(r"(?<![\w.,-])\d[\d,]*\.\d+(?![\w])|(?<![\w.,-])\d{1,3}(?:,\d{3})+(?![\w.])", report))
for f in sorted(figures):
    if not re.search(r"(?<![\d.,])" + re.escape(f) + r"(?![\d])", sources):
        bad.append("REPORT.md figure not found in the recorded or generated files: " + f)
for h in sorted(set(re.findall(r"(?<![0-9a-f])[0-9a-f]{9,64}(?![0-9a-f])", report))):
    if not re.search(r"(?<![0-9a-f])" + h, sources):
        bad.append("REPORT.md hash not found in the recorded or generated files: " + h)

# (2) Replay inputs.
spec = importlib.util.spec_from_file_location("r2a", os.path.join(root, "tools", "routing-to-art1.py"))
r2a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r2a)
replay = text("replay.txt")
want = re.search(r"^routing_sha256 ([0-9a-f]{64})$", replay, re.M)[1]
routing = None
for dirpath, _, files in sorted(os.walk(root)):
    if "routing.bin" in files:
        data = open(os.path.join(dirpath, "routing.bin"), "rb").read()
        if hashlib.sha256(data).hexdigest() == want:
            routing = data
            break
if routing is None:
    bad.append("replay.txt routing_sha256 matches no stored routing.bin")
else:
    lines = re.findall(r"^budget=(\d+) bucket=(\d+) cacheCap=(\d+) input_sha256=([0-9a-f]{64}):", replay, re.M)
    if len(lines) != 3:
        bad.append("replay.txt does not hold three replay lines")
    for budget, bucket, cap, digest in lines:
        if hashlib.sha256(r2a.art1(routing, int(budget), int(bucket), int(cap))).hexdigest() != digest:
            bad.append("replay input differs for budget=%s cacheCap=%s" % (budget, cap))

for b in bad:
    print("FAIL " + b)
print("figures checked: %d" % len(figures))
sys.exit(1 if bad else 0)
