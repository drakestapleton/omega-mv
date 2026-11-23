"""Select programs with eight charged answers, seal them, then score them independently."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
import hashlib
import json
from pathlib import Path
import tempfile
import time

from engines import ComponentFailure, Engines
import fixture


def digest(path):
    with path.open("rb") as reader:
        return hashlib.file_digest(reader, "sha256").hexdigest()


def kit_hashes(kit):
    files = ("combined", "solve", "om_formalize", "om_sketch", "om_synth", "predict",
             "omc", "ollm", "merges.bin", "trace.ck", "r6.ck", "r3.ck", "base.ck", "r11.ck",
             "S1_arith.sp", "S2_fold.sp", "S3_rewrite.sp", "S4_repair.sp")
    hashes = {name: digest(kit/name) for name in files}
    if hashes["trace.ck"] != "08fc55505c8fa6a094e30807e616b64e4ea6d186cd4ef769ed877e469bcaac91":
        raise ValueError("private checkpoint differs from the registered baseline")
    return hashes


def select_task(task, kit, mode, diagnostic=False):
    xs = [tuple(x) for x in task["fixed"]]
    pool = list(dict.fromkeys(tuple(x) for x in [*task["pool"], *xs]))
    if len(xs) != 8 or len(set(xs)) != 8 or set(pool).intersection(map(tuple, task["score"])):
        raise ValueError(("invalid input partition", task["id"]))
    observed = {}

    def query(x):
        if len(observed) >= 8 or x in observed or x not in pool:
            raise ValueError(("invalid query", task["id"], x))
        observed[x] = tuple(fixture.ref(task, x))
        return observed[x]

    with tempfile.TemporaryDirectory() as d:
        engine = Engines(kit, d, task["prompt"])
        start = time.monotonic()
        error = None
        try:
            if mode == "baseline":
                for x in xs:
                    query(x)
                body, route = engine.baseline(list(observed.items()))
                trace = []
            else:
                from selection import choose
                body, route, trace = choose(engine, xs, pool, query, mode == "adaptive")
        except ComponentFailure as exc:
            if not diagnostic:
                raise
            error = exc.details
            body, route, trace = None, "component error", []
        elapsed = time.monotonic()-start
    if not error and len(observed) != 8:
        raise ValueError(("unfinished query budget", task["id"]))
    return dict(id=task["id"], family=task["family"], group=task["group"], mode=mode,
                query_count=len(observed), queries=list(observed.items()), route=route,
                program=None if body is None else body.decode(), rounds=trace, seconds=elapsed, **({"error":error} if error else {}))


def score(task, selected, kit):
    start = time.monotonic()
    mismatch = None
    prog = selected["program"]
    if selected.get("error"):
        verdict = "error"
    elif prog is None:
        verdict = "abstain"
    else:
        xs = list(map(tuple, task["score"]))
        with tempfile.TemporaryDirectory() as d:
            predicted = Engines(kit, d, task["prompt"]).predict(prog.encode(), xs)
        for x, got in zip(xs, predicted, strict=True):
            wanted = tuple(fixture.ref(task, x))
            if wanted != got:
                mismatch = dict(x=x, expected=wanted, actual=got)
                break
        verdict = "correct" if mismatch is None else "wrong"
    return {**selected, "verdict": verdict, "first_mismatch": mismatch,
            "scoring_seconds": time.monotonic()-start}


def json_file(path, obj):
    with path.open("x") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("split", choices=("dev", "eval"))
    p.add_argument("output", type=Path)
    p.add_argument("--kit", type=Path, required=True)
    p.add_argument("--improved", type=Path)
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument("--rewrite-only", action="store_true")
    p.add_argument("--diagnose-interruption", action="store_true",
                   help="continue an interrupted run on identical pins with per-task error accounting; ineligible for qualification")
    args = p.parse_args()
    if args.split == "eval" and (not args.improved or args.rewrite_only):
        p.error("final evaluation requires both registered kits and all tasks")
    baseline = args.kit.resolve()
    arms = {"baseline": (baseline, "baseline")}
    if args.improved:
        better = args.improved.resolve()
        arms.update({"improved_cli": (better, "baseline"), "fixed": (better, "fixed"),
                     "adaptive": (better, "adaptive")})
    entries = list(fixture.tasks(args.split))
    if args.rewrite_only:
        entries = [t for t in entries if " edit " in t["prompt"]]
    out = args.output.resolve()
    out.mkdir(exist_ok=args.diagnose_interruption)
    registered = {arm: kit_hashes(k) for arm,(k,_) in arms.items()}
    here = Path(__file__).resolve().parent
    js = {"split":args.split, "fixture":digest(here/"fixture.py"),
          "manifest":digest(here/"manifest.json"), "kits":registered, "jobs":args.jobs}
    if args.diagnose_interruption:
        if json.loads((out/"inputs.json").read_text()) != js:
            raise ValueError("interrupted run has different source data, kit hashes or resource configuration")
        json_file(out/"interruption.json", {"status":"diagnostic", "reason":"registered run stopped on a component failure"})
    else:
        json_file(out/"inputs.json", js)
    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        for arm, (kit, mode) in arms.items():
            path = out/f"{arm}.sealed.jsonl"
            existing = [json.loads(l) for l in path.read_text().splitlines()] if path.exists() else []
            if [r["id"] for r in existing] != [t["id"] for t in entries[:len(existing)]]:
                raise ValueError("sealed prefix does not match frozen task order")
            with path.open("a" if args.diagnose_interruption else "x") as f:
                for row in workers.map(lambda t: select_task(t, kit, mode, args.diagnose_interruption),
                                       entries[len(existing):]):
                    f.write(json.dumps(row)+"\n")
                    f.flush()
        for arm, (kit, _) in arms.items():
            rows = [json.loads(line) for line in (out/f"{arm}.sealed.jsonl").read_text().splitlines()]
            assert [r["id"] for r in rows] == [t["id"] for t in entries]
            results = list(workers.map(lambda t,r: score(t,r,kit), entries, rows))
            json_file(out/f"{arm}.json", results)
            print(arm, dict(Counter(r["verdict"] for r in results)), flush=True)
    if registered != {arm:kit_hashes(k) for arm,(k,_) in arms.items()}:
        raise RuntimeError("kit changed during experiment")


if __name__ == "__main__":
    main()
