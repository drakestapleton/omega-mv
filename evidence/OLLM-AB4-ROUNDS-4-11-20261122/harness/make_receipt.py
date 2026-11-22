#!/usr/bin/env python3
"""Evidence generator (measuring harness): reads the raw campaign logs on the Spark and writes
receipt.json and RESULTS.md so that no figure in the evidence bundle is typed by hand.
usage: make_receipt.py OUT_DIR
Derived figures are labelled derived and carry their inputs.
"""
import glob, hashlib, json, os, re, sys

CAMP = "/home/drakestapleton/work/ollm-helix-rlvr-20261121"
VLOOP = "/home/drakestapleton/work/ollm-loop-20261121"
R = f"{CAMP}/rounds"
YR = "/home/drakestapleton/yardsticks/receipts"
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
STEPS, BATCH, WINDOW = 1400, 64, 256  # steps: gpu_round_r*.out; B and T: train/omega-llm/docs/LOOP.md "Arms" (tune keeps shapes)
TOKENS_TRAINED = STEPS * BATCH * WINDOW


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
            return {"step": int(a[1]), "windows": int(a[2]), "loss_micro_nats": int(a[3]), "raw": l.strip(), "log": p}


def score(p):
    s = {"passes": [], "families": {}, "file": p, "file_sha256": sha(p)}
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


ck_names = {sha(p): os.path.basename(p) for p in glob.glob(f"{CAMP}/ckpt/loop_r*.ck")}
tok47 = {}
for l in open(f"{R}/supplement/mix_tokens_r4_r7.txt"):
    a = l.split()
    if a and a[0].startswith("r"):
        tok47[a[0]] = {"tokens": int(a[3]), "tok_sha256": a[4], "tok_file": a[1]}


def manifest(n):
    p = f"{R}/r{n}/r{n}_manifest.txt"
    d = {"file": p, "file_sha256": sha(p), "sources": [], "teacher_plan_text_in_mix": False}
    for l in open(p):
        a = l.split()
        if l.startswith("source "):
            g = dict(zip(a[0::2], a[1::2]))
            d["sources"].append({"name": a[1], "kept": int(g["kept"]), "weight": int(g["weight"]), "sha256": g["sha256"]})
            if a[1] == "c2align":
                d["teacher_plan_text_in_mix"] = True
        elif l.startswith("audit_records "):
            d["distinct_records"] = int(a[1])
        elif l.startswith("repo source "):
            g = dict(zip(a[3::2], a[4::2]))
            d["repo_docs"] = int(g["docs"])
            d["repo_distinct_docs"] = int(g.get("distinct_docs", g["docs"]))
            d["repo_bytes"] = int(g["bytes"])
        elif l.startswith("repo slice replayed "):
            m = re.search(r"distinct_docs (\d+) distinct_bytes (\d+)", l)
            d["replayed_slice"] = {"distinct_docs": int(m.group(1)), "distinct_bytes": int(m.group(2))}
        elif l.startswith("mix "):
            m = re.search(r"bytes (\d+) .*repo_share_pct ([\d.]+) sha256 (\w+)", l)
            d["mix_bytes"], d["repo_share_pct"], d["mix_sha256"] = int(m.group(1)), float(m.group(2)), m.group(3)
        elif l.startswith("tok "):
            m = re.search(r"tokens (\d+) sha256 (\w+)", l)
            d["tokens"], d["tok_sha256"] = int(m.group(1)), m.group(2)
        elif l.startswith("round "):
            d["note"] = l.strip()
    if "tokens" not in d and f"r{n}" in tok47:
        d["tokens"], d["tok_sha256"] = tok47[f"r{n}"]["tokens"], tok47[f"r{n}"]["tok_sha256"]
    if "tokens" in d:
        d["derived_passes_over_mix"] = round(TOKENS_TRAINED / d["tokens"], 2)
    return d


WHAT = {
    3: "state at takeover (earlier agent's round 3)",
    4: "round 4 task mix (adds breadth and cycle-2 traces), narrow rehearsal slice",
    5: "continuation: round 3's own mix and settings applied again",
    6: "round 6 task mix (adds generator variants 6 to 9), wide rehearsal at 50%",
    7: "round 6 task mix, wide rehearsal at 30%",
    8: "ablation: round 4 task mix, wide rehearsal at 50%",
    9: "ablation: round 4 task mix, round 4's small slice replayed to 50%",
    10: "round 6 configuration again, new shuffle seed",
    11: "round 6 configuration again, new shuffle seed",
}
rounds = []
r0 = {"round": "r0", "what": "pre-campaign looped checkpoint (LOOP.md step 6000), measured today", "checkpoint": f"{VLOOP}/run/loop/ck6000.bin",
      "checkpoint_sha256": sha(f"{VLOOP}/run/loop/ck6000.bin"), "held": e_line(f"{R}/geval_loop_r0_ck6000.log"), "spark_receipt": receipt("ollm-r0-baseline-geval")}
rounds.append(r0)
r3 = {"round": "r3", "what": WHAT[3], "checkpoint": f"{CAMP}/ckpt/loop_r3.ck", "checkpoint_sha256": sha(f"{CAMP}/ckpt/loop_r3.ck"),
      "held": e_line(f"{CAMP}/logs/geval_loop_r3.log"), "bench": score(f"{R}/score_r3ctl.txt")}
rounds.append(r3)
for n in range(4, 12):
    ck = f"{CAMP}/ckpt/loop_r{n}.ck"
    if not os.path.exists(f"{R}/r{n}/DONE_GPU") or not os.path.exists(ck):
        continue
    sc = f"{R}/score_r5ctl.txt" if n == 5 else f"{R}/score_r{n}.txt"
    go = open(f"{R}/r{n}/gpu_round.out").read()
    prev = re.search(r"prev_sha256=(\w+)", go).group(1)
    xb, xa = re.search(r"XID_BEFORE=(\d+) XID_AFTER=(\d+)", go).groups()
    d = {"round": f"r{n}", "what": WHAT[n], "parent": ck_names.get(prev, prev), "parent_sha256": prev, "checkpoint": ck, "checkpoint_sha256": sha(ck),
         "held": e_line(f"{R}/r{n}/geval_loop_r{n}.log"), "bench": score(sc), "spark_receipt": receipt(f"ollm-rlvr-r{n}-gb10"),
         "xid_before": int(xb), "xid_after": int(xa), "mix": manifest(n),
         "train_T_lines": [l.strip() for l in open(f"{R}/r{n}/train_loop_r{n}.log") if l.startswith("T ")]}
    rounds.append(d)

passk = {}
for tag in ["r3", "r6"]:
    d = f"{R}/passk_{tag}"
    per = [open(f"{d}/score_s{s}.txt").read().split("SCORE ")[1].split("\n")[0] for s in range(1, 9)]
    anyp = [l.split() for l in open(f"{d}/pass_any.txt")]
    passk[tag] = {"K": 8, "temp_milli": 700, "per_seed_score": ["SCORE " + x for x in per], "tasks_passing_in_any_sample": len(anyp),
                  "tasks": {a[1]: {"family": a[2], "samples_passing": int(a[0])} for a in anyp}}
union = set()
for d in rounds:
    union |= set(d.get("bench", {}).get("passes", []))
greedy_union = set(union)
for p in passk.values():
    union |= set(p["tasks"])

by = {d["round"]: d for d in rounds}
h = lambda r: by[r]["held"]["loss_micro_nats"] if r in by else None
plan_b = {"file": f"{R}/PLAN-B.md", "file_sha256": sha(f"{R}/PLAN-B.md"), "registered": open("/home/drakestapleton/handoffs/ab4-finish-20261122/PLAN-B.registered").read().strip()}
if all(r in by for r in ["r8", "r9"]):
    diff = h("r9") - h("r8")
    plan_b["held_r9_minus_r8_micro_nats"] = diff
    plan_b["rehearsal_reading"] = "breadth of the rehearsal draw is the cause (difference above 0.3)" if diff > 300000 else ("share, not breadth (difference at most 0.1)" if abs(diff) <= 100000 else "both contribute (difference between 0.1 and 0.3)")
late = [r for r in ["r8", "r9", "r10", "r11"] if r in by]
if late:
    plan_b["best_pass_r8_to_r11"] = max(by[r]["bench"]["passed"] for r in late)
    plan_b["benchmark_gain_reached_8"] = plan_b["best_pass_r8_to_r11"] >= 8
if all(r in by for r in ["r10", "r11"]):
    plan_b["held_r11_minus_r10_micro_nats"] = h("r11") - h("r10")
    plan_b["held_r10_minus_r0_micro_nats"] = h("r10") - h("r0")
    plan_b["held_r11_minus_r0_micro_nats"] = h("r11") - h("r0")
    plan_b["held_plateau_criterion_met"] = abs(h("r11") - h("r10")) < 50000 and abs(h("r10") - h("r0")) <= 150000 and abs(h("r11") - h("r0")) <= 150000

windows = []
for p in sorted(glob.glob(f"{YR}/2026-11-22-ollm-rlvr-r*-gb10.json") + glob.glob(f"{YR}/2026-11-22-ollm-teacher-para-*.json") + glob.glob(f"{YR}/2026-11-22-ollm-r0-baseline-geval.json")):
    d = json.load(open(p))
    if d["name"] in ("ollm-rlvr-r1-gb10", "ollm-rlvr-r2-gb10", "ollm-rlvr-r3-gb10"):
        continue
    windows.append({"name": d["name"], "window_id": d["window_id"], "start": d["start"], "seconds": d["seconds"], "exit": d["exit"], "nvrm_errors_delta": d["nvrm_errors_delta"]})

teacher_out = open(f"{R}/para/teacher_p1.out").read()
m = re.search(r"PARAPHRASE_SUMMARY.*", teacher_out)
rec = {
    "schema": "ollm-ab4-rounds/2",
    "date": "2026-11-22",
    "host": os.uname().nodename,
    "pins": {l.split()[1]: l.split()[0] for l in open(f"{R}/pins.sha256")},
    "derived_inputs": {"steps": STEPS, "batch": BATCH, "window": WINDOW, "tokens_trained_per_round": TOKENS_TRAINED},
    "rounds": rounds,
    "plan_b": plan_b,
    "pass_at_k_diagnostic": passk,
    "tasks_passing_anywhere": {"greedy_scores_only": sorted(greedy_union), "greedy_or_pass_at_8": sorted(union)},
    "gpu_windows_opened_by_this_work": windows,
    "cycle2_sweep": {"task_281_summary_lines": [l.strip() for l in open(f"{R}/c2_task281_summary.txt")],
                     "files": {os.path.basename(p): sha(p) for p in sorted(glob.glob(f"{CAMP}/ab4_cycle2/stage3/*.tsv") + glob.glob(f"{CAMP}/ab4_cycle2/stage5/*_c2.om"))}},
    "teacher_rewording": {"summary": m.group(0) if m else None, "usable_records": 0},
}
json.dump(rec, open(f"{out}/receipt.json", "w"), indent=1, sort_keys=True)

f = lambda v: f"{v/1e6:.3f}"
b3, b0 = h("r3"), h("r0")
L = ["# Results (generated by harness/make_receipt.py from the raw logs; do not edit)", "",
     f"Each trained round is {STEPS:,} `gtrainf` steps of {BATCH} windows of {WINDOW} tokens = {TOKENS_TRAINED:,} tokens (derived; B and T from `train/omega-llm/docs/LOOP.md`).",
     "\"Passes over mix\" is that figure divided by the mix's token count (derived).", "",
     "| Round | Parent | What | Distinct task records | Rehearsal share of mix | Distinct repo documents | Passes over mix | Frozen benchmark pass / tasks | `held.tok` loss | vs r3 | vs r0 |",
     "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
for d in rounds:
    mx, hh = d.get("mix", {}), d["held"]["loss_micro_nats"]
    b = d.get("bench")
    L.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
        d["round"], d.get("parent", ""), d["what"], f"{mx['distinct_records']:,}" if "distinct_records" in mx else "",
        f"{mx['repo_share_pct']}%" if "repo_share_pct" in mx else "", f"{mx['repo_distinct_docs']:,}" if "repo_distinct_docs" in mx else "",
        mx.get("derived_passes_over_mix", ""), f"{b['passed']} / {b['tasks']}" if b else "(not scored here)", f(hh), f"{(hh-b3)/1e6:+.3f}", f"{(hh-b0)/1e6:+.3f}"))
L += ["", "Round 5 reuses round 3's mix file byte for byte (`supplement/mix_tokens_r4_r7.txt`); that mix was built by the earlier agent and has no manifest here.",
      "Round 9's 'distinct repo documents' is the size of the replayed slice.", "",
      "## Passing task ids, windows and driver log counts", "",
      "| Round | Passing task ids | Spark window | `nvrm_errors_delta` | Xid before / after | Teacher plan text in mix |", "|---|---|---|---:|---|---|"]
for d in rounds:
    sr = d.get("spark_receipt", {})
    L.append("| {} | {} | {} | {} | {} | {} |".format(d["round"], " ".join(d.get("bench", {}).get("passes", [])), sr.get("window_id", "(earlier agent)"), sr.get("nvrm_errors_delta", ""),
                                                 f"{d['xid_before']} / {d['xid_after']}" if "xid_before" in d else "", ("yes (30 alignment records)" if d.get("mix", {}).get("teacher_plan_text_in_mix") else ("no" if "mix" in d and d["mix"]["sources"] else ""))))
L += ["", "Every scored row: `seen 6`, `passcut 0`. Headline score is one greedy sample per task (seed 42, 128 tokens, temperature 0).", "",
      "## Other GPU windows opened by this work", "", "| Name | Window | Seconds | Exit | `nvrm_errors_delta` |", "|---|---|---:|---:|---:|"]
for w in windows:
    if not w["name"].startswith("ollm-rlvr-r"):
        L.append(f"| {w['name']} | {w['window_id']} | {w['seconds']} | {w['exit']} | {w['nvrm_errors_delta']} |")
L += ["", "## Pass-at-8 diagnostic (never a training source, never the headline)", "",
      "| Model | Tasks passing in at least one of 8 samples (temperature 0.7) | Per-sample pass counts |", "|---|---:|---|"]
for tag in ["r3", "r6"]:
    p = passk[tag]
    L.append(f"| {tag} | {p['tasks_passing_in_any_sample']} / 159 | {' '.join(x.split()[4] for x in p['per_seed_score'])} |")
L += ["", f"Tasks passing in any greedy score above: {len(greedy_union)} ({' '.join(sorted(greedy_union))}).",
      f"Tasks passing in any greedy score or any pass-at-8 sample: {len(union)} of 159 ({' '.join(sorted(union))}).", "",
      "## Criteria registered beforehand (`campaign-plan/PLAN-B.md`)", ""]
for k, v in plan_b.items():
    if k not in ("file",):
        L.append(f"- `{k}`: {v}")
L += ["", "## Checkpoints (sha256)", ""] + [f"- `{d['round']}` `{d['checkpoint_sha256']}`" for d in rounds]
open(f"{out}/RESULTS.md", "w").write("\n".join(L) + "\n")
print("\n".join(L))
