# L835 run 300 measuring instrument (not delivered code) for spec/omegese-om2-measure.md.
# Paired interleaved: 3 discarded warm-up rounds + 31 rounds; per round arms A, B, C run in a seeded
# random order; timed process pinned to cpu 8 (Cortex-X925) under nice 19; this script on cpu 9.
# Records uptime before and after every round, peak RSS of every arm process, cold first-call times
# over 31 fresh processes per arm and size, and 41 interleaved compile times per arm. Every timed
# call's digest is checked by the driver; its printed digest is checked here against sha256sum.
import json, os, random, subprocess, sys, time
M = sys.argv[1]; OUT = sys.argv[2]
SEED = 20261109; ROUNDS = 31; WARM = 3; REPS = 31; COLD = 31; COMPILES = 41
random.seed(SEED)
CORE = ["taskset", "-c", "8", "nice", "-n", "19"]
ARMS = ["A", "B", "C"]
def up():
    return open("/proc/loadavg").read().split()[:3]
# oracle digests from sha256sum over the same bytes the drivers hash
buf = bytes((i * 31 + 7) & 255 for i in range(1 << 24))
def oracle(n):
    return subprocess.run(["sha256sum"], input=buf[:n], capture_output=True).stdout.split()[0].decode()
SIZES = [0,1,31,32,55,56,63,64,65,127,128,1024,4096,65536,1048576,16777216]
ref = {f"hash:{n}": oracle(n) for n in SIZES}
# the stream loop feeds whole chunks while offset < 2^20, so a chunk size that does not divide 2^20
# hashes ceil(2^20/c)*c bytes (c=7: 1048579); the oracle hashes exactly those bytes
for c in (1, 7, 64, 4096): ref[f"stream:{c}"] = oracle(-(-(1 << 20) // c) * c)
def bench(a):
    p = subprocess.run(["/usr/bin/time", "-f", "RSS %M"] + CORE + [f"{M}/bin/bench-{a}", str(REPS)],
                       capture_output=True, text=True)
    if p.returncode != 0: sys.exit(f"VOID: arm {a} rc={p.returncode} {p.stderr[:300]}")
    rss = int([l for l in p.stderr.splitlines() if l.startswith("RSS ")][-1].split()[1])
    rows = {}
    for line in p.stdout.strip().splitlines():
        f = line.split()
        if f[0] == "hash": k = f"hash:{f[1]}"; vals = f[2:7]; dig = f[8]
        else: k = f"stream:{f[1]}"; vals = f[3:8]; dig = f[8]
        if dig != ref[k]: sys.exit(f"VOID: arm {a} {k} digest {dig} != sha256sum {ref[k]}")
        rows[k] = dict(zip(["min", "p10", "med", "p90", "max"], map(float, vals)))
    return rows, rss
data = {"protocol": "spec/omegese-om2-measure.md sha256 507702d0e69ccc76cefb3675e2b22f7279497d362b42ee3043f3a1057aa17bad",
        "seed": SEED, "core": "cpu8 Cortex-X925", "rounds": [], "cold": [], "compile": []}
for r in range(WARM + ROUNDS):
    order = ARMS[:]; random.shuffle(order)
    rec = {"round": r, "warmup": r < WARM, "order": order, "load_before": up(), "t0": time.time()}
    for a in order:
        rows, rss = bench(a); rec[a] = rows; rec["rss_" + a] = rss
    rec["load_after"] = up(); rec["t1"] = time.time()
    data["rounds"].append(rec)
    print(f"round {r} {''.join(order)} load {rec['load_before'][0]}->{rec['load_after'][0]}", flush=True)
# cold: first call after process start
jobs = [(a, n) for a in ARMS for n in (64, 1048576) for _ in range(COLD)]
random.shuffle(jobs)
data["cold_load_before"] = up()
for a, n in jobs:
    p = subprocess.run(CORE + [f"{M}/bin/cold-{a}", str(n)], capture_output=True, text=True)
    f = p.stdout.split()
    if p.returncode != 0 or f[3] != oracle(n): sys.exit(f"VOID: cold {a} {n}")
    data["cold"].append({"arm": a, "n": n, "ns": float(f[2])})
data["cold_load_after"] = up()
# compile time of the SHA unit with each arm's own omc (C has no unit)
src = {"A": (f"{M}/A/seed/out/omc", f"{M}/A/om/sha256/sha256.om"),
       "B": (f"{M}/B/seed/out/omc", f"{M}/B/om/sha256/sha256-om2.om")}
jobs = [a for a in ("A", "B") for _ in range(COMPILES)]; random.shuffle(jobs)
data["compile_load_before"] = up()
for a in jobs:
    omc, s = src[a]
    with open(s, "rb") as fi:
        t0 = time.perf_counter_ns()
        p = subprocess.run(CORE + [omc], stdin=fi, stdout=subprocess.DEVNULL)
        t = time.perf_counter_ns() - t0
    if p.returncode != 0: sys.exit(f"VOID: compile {a}")
    data["compile"].append({"arm": a, "ns": t})
data["compile_load_after"] = up()
json.dump(data, open(OUT, "w"), indent=0)
print("DONE")
