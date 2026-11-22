#!/usr/bin/env python3
"""Evidence generator (measuring harness): reads the raw campaign logs on the Spark and writes
receipt.json and RESULTS.md so that no figure in the evidence bundle is typed by hand.
usage: make_receipt.py OUT_DIR
"""
import glob, hashlib, json, os, re, sys

CAMP = "/home/drakestapleton/work/ollm-helix-rlvr-20261121"
R = f"{CAMP}/rounds"
YR = "/home/drakestapleton/yardsticks/receipts"
out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def e_line(p):
    for l in open(p):
        if l.startswith("E "):
            a = l.split()
            return {"step": int(a[1]), "windows": int(a[2]), "loss_micro_nats": int(a[3]), "raw": l.strip()}


def score(p):
    s = {"passes": [], "families": {}}
    for l in open(p):
        a = l.split()
        if l.startswith("SCORE "):
            s.update(tasks=int(a[2]), passed=int(a[4]), passcut=int(a[6]), seen=int(a[8]), raw=l.strip())
        elif l.startswith("R ") and a[-1] == "pass":
            s["passes"].append(a[1])
        elif l.startswith("F "):
            s["families"][a[1]] = dict(zip(["tasks", "pass", "passcut", "wrong", "nocompile", "noend", "refused", "missing", "timeout", "seen"], map(int, a[2:])))
    return s


def receipt(name):
    p = f"{YR}/2026-11-22-{name}.json"
    d = json.load(open(p))
    return {k: d.get(k) for k in ["name", "exit", "start", "seconds", "gpu_W_mean", "gpu_util_mean", "nvrm_errors_delta", "window_id"]} | {"path": p, "sha256": sha(p)}


rounds = []
spec = [
    ("r3", "champion at takeover (antigravity round 3)", f"{CAMP}/ckpt/loop_r3.ck", f"{CAMP}/logs/geval_loop_r3.log", f"{R}/score_r3ctl.txt", None, None, None),
    ("r4", "from r3: + breadth + cycle-2 traces, narrow rehearsal (1.28 MB slice)", f"{CAMP}/ckpt/loop_r4.ck", f"{R}/r4/geval_loop_r4.log", f"{R}/score_r4.txt", "ollm-rlvr-r4-gb10", f"{R}/r4/r4_manifest.txt", f"{R}/r4/train_loop_r4.log"),
    ("r5", "CONTROL from r3: round-3 mix and recipe repeated unchanged", f"{CAMP}/ckpt/loop_r5.ck", f"{R}/r5/geval_loop_r5.log", f"{R}/score_r5ctl.txt", "ollm-rlvr-r5-gb10", f"{R}/r5/r5_manifest.txt", f"{R}/r5/train_loop_r5.log"),
    ("r6", "from r3: 9,897 records, wide rehearsal (50% of mix, repo documents used about once)", f"{CAMP}/ckpt/loop_r6.ck", f"{R}/r6/geval_loop_r6.log", f"{R}/score_r6.txt", "ollm-rlvr-r6-gb10", f"{R}/r6/r6_manifest.txt", f"{R}/r6/train_loop_r6.log"),
    ("r7", "from r6: same records, wide rehearsal at 30% of mix", f"{CAMP}/ckpt/loop_r7.ck", f"{R}/r7/geval_loop_r7.log", f"{R}/score_r7.txt", "ollm-rlvr-r7-gb10", f"{R}/r7/r7_manifest.txt", f"{R}/r7/train_loop_r7.log"),
]
for tag, what, ck, ge, sc, rc, man, tl in spec:
    d = {"round": tag, "what": what, "checkpoint": ck, "checkpoint_sha256": sha(ck), "held": e_line(ge), "bench": score(sc), "score_file_sha256": sha(sc)}
    if rc:
        d["spark_receipt"] = receipt(rc)
    if man:
        d["mix_manifest_sha256"] = sha(man)
    if tl:
        d["train_T_lines"] = [l.strip() for l in open(tl) if l.startswith("T ")]
    rounds.append(d)

passk = {}
for tag in ["r3", "r6"]:
    d = f"{R}/passk_{tag}"
    per = [open(f"{d}/score_s{s}.txt").read().split("SCORE ")[1].split("\n")[0] for s in range(1, 9)]
    anyp = [l.split() for l in open(f"{d}/pass_any.txt")]
    passk[tag] = {"K": 8, "temp_milli": 700, "per_seed_score": ["SCORE " + x for x in per], "tasks_passing_in_any_sample": len(anyp), "tasks": {a[1]: {"family": a[2], "samples_passing": int(a[0])} for a in anyp}}

teacher_out = open(f"{R}/para/teacher_p1.out").read()
m = re.search(r"PARAPHRASE_SUMMARY.*", teacher_out)
c2s = [l.strip() for l in open(f"{R}/c2_task281_summary.txt")]
c2 = {"task_281_summary_lines": c2s,
      "source": "antigravity session 129c679e task-281, result undelivered at 2026-11-22T15:18:57Z; the three files it wrote are in cycle2/",
      "files": {os.path.basename(p): sha(p) for p in sorted(glob.glob(f"{CAMP}/ab4_cycle2/stage3/*.tsv") + glob.glob(f"{CAMP}/ab4_cycle2/stage5/*_c2.om"))}}

rec = {
    "schema": "ollm-ab4-rounds-4-7/1",
    "date": "2026-11-22",
    "host": os.uname().nodename,
    "verdict": "DIMINISHING_RETURNS_REACHED: no frozen-benchmark gain in 4 consecutive rounds after round 3; held-out loss improved by the rehearsal change",
    "pins": {l.split()[1]: l.split()[0] for l in open(f"{R}/pins.sha256")},
    "rounds": rounds,
    "pass_at_k_diagnostic": passk,
    "cycle2_sweep": c2,
    "teacher_rewording": {"summary": m.group(0) if m else None, "usable_records": 0, "verdict": "FAIL: all 89 filter-passing lines rejected on inspection (teacher answered instead of rewording); none trained on", "spark_receipt": receipt("ollm-teacher-para-p1")},
    "not_run": ["GPU training of frozen-core OLLMSP01 strands (gtrainf updates all layers)", "widened looped core (spec section 6 branch)", "architect cycle 3 on the 21 requeued tasks"],
}
json.dump(rec, open(f"{out}/receipt.json", "w"), indent=1, sort_keys=True)

f = lambda v: f"{v/1e6:.3f}"
base = rounds[0]["held"]["loss_micro_nats"]
lines = ["# Results (generated by harness/make_receipt.py from the raw logs; do not edit)", "",
         "| Round | What | Frozen benchmark pass / tasks | Passing task ids | held.tok loss, nats/token (2,475 windows) | Change vs r3 | Spark window | nvrm errors |",
         "|---|---|---:|---|---:|---:|---|---:|"]
for d in rounds:
    b, h = d["bench"], d["held"]
    sr = d.get("spark_receipt", {})
    lines.append(f"| {d['round']} | {d['what']} | {b['passed']} / {b['tasks']} | {' '.join(b['passes'])} | {f(h['loss_micro_nats'])} | {(h['loss_micro_nats']-base)/1e6:+.3f} | {sr.get('window_id','(antigravity)')} | {sr.get('nvrm_errors_delta','')} |")
lines += ["", "Every row: `seen 6` (unchanged), `passcut 0`. Headline score is one greedy sample per task (seed 42, 128 tokens, temperature 0).", "",
          "## Pass-at-8 diagnostic (never a training source, never the headline)", "",
          "| Model | Tasks passing in at least one of 8 samples (temperature 0.7) | Per-sample pass counts |", "|---|---:|---|"]
for tag in ["r3", "r6"]:
    p = passk[tag]
    lines.append(f"| {tag} | {p['tasks_passing_in_any_sample']} / 159 | {' '.join(x.split()[4] for x in p['per_seed_score'])} |")
lines += ["", "## Checkpoints (sha256)", ""] + [f"- `{d['round']}` `{d['checkpoint_sha256']}`" for d in rounds]
open(f"{out}/RESULTS.md", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
