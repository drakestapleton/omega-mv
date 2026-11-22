#!/usr/bin/env python3
"""Measuring/prep harness (not structural): build a zero-leakage, NUL-EOS, shuffled training mix.

usage: build_mix.py ROUND OUT_DIR REPO_FRAC_PCT EPOCHS name=path:weight ...

Same method as the Round 3 prep (session ed855b80 step 944): split sources into `note .. fn .. end`
records, prune any record whose AST collides with a frozen benchmark task (`bench seen`), weight,
shuffle, blend repo-train.om rehearsal, NUL-join. Writes:
  OUT_DIR/rN_mix.om        the training mix
  OUT_DIR/rN_audit.om      every distinct RLVR record once, newline-joined (for `bench seen` / score)
  OUT_DIR/rN_manifest.txt  counts and sha256 of every input and output
Exits 1 if the final audit is not `seen 0`.
"""
import hashlib, os, random, subprocess, sys, tempfile

CAMP = "/home/drakestapleton/work/ollm-helix-rlvr-20261121"
VLOOP = "/home/drakestapleton/work/ollm-loop-20261121"
BENCH = f"{CAMP}/bin/bench"
TASKS = f"{CAMP}/data/tasks.om"


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def split_by_note(path):
    raw = open(path, "rb").read().replace(b"\x00", b"\n").decode("utf-8", errors="ignore")
    recs, cur = [], []

    def flush():
        if cur and any(l.startswith("fn ") for l in cur):
            s = "\n".join(cur).strip()
            if s.endswith("end"):
                recs.append(s + "\n")

    for line in raw.splitlines():
        if line.startswith("note ") and cur and any(l.startswith("fn ") for l in cur):
            flush()
            cur = [line]
        elif line.strip() != "":
            cur.append(line)
    flush()
    return recs


def seen_out(recs):
    if not recs:
        return "SEENSUM seen 0"
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".om") as tf:
        tf.write("\n".join(recs))
        p = tf.name
    try:
        r = subprocess.run([BENCH, "seen", TASKS, p], capture_output=True, text=True, check=True)
        return r.stdout.strip()
    finally:
        os.unlink(p)


def leaked(recs):
    return "seen 0" not in seen_out(recs)


def prune_seen(recs):
    if not leaked(recs):
        return recs, 0
    if len(recs) <= 1:
        return [], len(recs)
    mid = len(recs) // 2
    a, pa = prune_seen(recs[:mid])
    b, pb = prune_seen(recs[mid:])
    return a + b, pa + pb


def main():
    rnd, out_dir, repo_pct, epochs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    specs = sys.argv[5:]
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(20261122 + int(rnd))
    man = [f"round {rnd} repo_pct {repo_pct} epochs {epochs}"]
    pool, audit, seen_set = [], [], set()
    for spec in specs:
        name, rest = spec.split("=", 1)
        path, weight = rest.rsplit(":", 1)
        weight = int(weight)
        recs = split_by_note(path)
        uniq = list(dict.fromkeys(recs))
        clean, pruned = prune_seen(uniq)
        man.append(f"source {name} path {path} sha256 {sha(path)} parsed {len(recs)} unique {len(uniq)} pruned {pruned} kept {len(clean)} weight {weight}")
        print(man[-1], flush=True)
        pool.extend(clean * weight)
        for r in clean:
            if r not in seen_set:
                seen_set.add(r)
                audit.append(r)
    final = seen_out(audit)
    man.append(f"audit_records {len(audit)} bench_seen: {final.splitlines()[-1]}")
    print(man[-1], flush=True)
    if "seen 0" not in final:
        print("FATAL LEAK", final, file=sys.stderr)
        sys.exit(1)
    chunks = []
    for _ in range(epochs):
        rng.shuffle(pool)
        chunks.extend(pool)
    rlvr_bytes = sum(len(c.encode()) + 1 for c in chunks)
    target_repo = rlvr_bytes * repo_pct // (100 - repo_pct)
    repo_path = f"{VLOOP}/data/repo-train.om"
    slice_mix = os.environ.get("REPO_FROM_MIX", "")
    if slice_mix:
        # ablation: replay the small repo slice of an earlier mix (its non-record documents) until
        # the target share is reached, instead of drawing widely from repo-train.om
        docs = open(slice_mix, "rb").read().split(b"\x00")
        repo_set = set(open(repo_path, "rb").read().split(b"\x00"))
        sl = [d for d in docs if len(d) >= 20 and d in repo_set]
        sl = list(dict.fromkeys(sl))
        man.append(f"repo slice replayed from {slice_mix} sha256 {sha(slice_mix)} distinct_docs {len(sl)} distinct_bytes {sum(len(d) + 1 for d in sl)}")
        pick, got = [], 0
        while got < target_repo:
            rng.shuffle(sl)
            for ch in sl:
                pick.append(ch)
                got += len(ch) + 1
                if got >= target_repo:
                    break
    else:
        repo_raw = open(repo_path, "rb").read().split(b"\x00")
        rng.shuffle(repo_raw)
        pick, got = [], 0
        for ch in repo_raw:
            if len(ch) < 20:
                continue
            pick.append(ch)
            got += len(ch) + 1
            if got >= target_repo:
                break
    combined = [c.encode() for c in chunks] + pick
    rng.shuffle(combined)
    blob = b"\x00".join(combined) + b"\x00"
    mix = f"{out_dir}/r{rnd}_mix.om"
    aud = f"{out_dir}/r{rnd}_audit.om"
    open(mix, "wb").write(blob)
    open(aud, "w").write("\n".join(audit))
    man.append(f"repo source {repo_path} sha256 {sha(repo_path)} docs {len(pick)} distinct_docs {len(set(pick))} bytes {got}")
    man.append(f"mix {mix} bytes {len(blob)} docs {len(combined)} rlvr_docs {len(chunks)} rlvr_bytes {rlvr_bytes} repo_share_pct {100.0 * got / (got + rlvr_bytes):.1f} sha256 {sha(mix)}")
    man.append(f"audit {aud} sha256 {sha(aud)}")
    open(f"{out_dir}/r{rnd}_manifest.txt", "w").write("\n".join(man) + "\n")
    print("\n".join(man[-3:]), flush=True)


if __name__ == "__main__":
    main()
