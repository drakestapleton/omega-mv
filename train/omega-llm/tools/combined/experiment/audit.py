"""Audit the published per-task comparison and replay final grades without model weights."""
import argparse
from collections import Counter
import json
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import fixture
from measure import digest, score
from engines import Engines, ComponentFailure
from selection import choose


def require(condition, message):
    if not condition:
        raise ValueError(message)


def replay_selection(task, row, kit):
    # Consume the sealed transcript in order. An unexpected new question stops replay.
    answers = iter(row["queries"])
    def recorded(x):
        entry = next(answers, None)
        require(entry is not None and tuple(entry[0]) == x, (task["id"], "query diverged"))
        return tuple(entry[1])

    with tempfile.TemporaryDirectory() as scratch:
        engine = Engines(kit, scratch, task["prompt"])
        try:
            body, route, rounds = choose(engine, task["fixed"], task["pool"], recorded,
                                          row["mode"] == "adaptive")
        except ComponentFailure as error:
            require(error.details == row.get("error"), (task["id"], "component exit differs"))
        else:
            require(not row.get("error"), (task["id"], "missing component failure"))
            require((body.decode() if body else None) == row["program"], (task["id"], "selected body"))
            require((route, rounds) == (row["route"], row["rounds"]), (task["id"], "selection trace"))
    require(next(answers, None) is None, (task["id"], "unused answers"))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("receipt",type=Path)
    p.add_argument("kit",type=Path,help="public kit containing the seeded omc and predict instrument")
    p.add_argument("--replay-selection", action="store_true", help="also reproduce every fixed and adaptive symbolic decision from its sealed answers")
    p.add_argument("--jobs", type=int, default=1)
    args=p.parse_args()
    require(digest(args.receipt) in args.receipt.name,"receipt digest")
    report=json.loads(args.receipt.read_text())
    pins=report["inputs"]
    require(digest(fixture.MANIFEST)==pins["manifest"],"task manifest digest")
    require(digest(Path(fixture.__file__))==pins["fixture"],"reference digest")
    for name in ("omc","predict"):
        require(digest(args.kit/name)==pins["kits"]["baseline"][name],name+" digest")
    tasks=list(fixture.tasks("eval"))
    for arm,rows in report["evaluation"].items():
        require([r["id"] for r in rows]==[t["id"] for t in tasks],"task IDs")
        totals=Counter()
        for task,row in zip(tasks,rows,strict=True):
            queried=[tuple(x) for x,_ in row["queries"]]
            require(len(set(queried))==row["query_count"]==len(queried)<=8,"query budget")
            require(set(queried)<=set(task["pool"]),"outside input pool")
            fixed=task["fixed"][:4 if arm=="adaptive" else 8]
            require(queried[:len(fixed)]==fixed,"opening queries")
            for x,y in row["queries"]:
                require(tuple(y)==fixture.ref(task,x),"query label")
            if row.get("error"):
                require(row["verdict"]=="error" and row["program"] is None,"component failure")
            else:
                require(len(queried)==8,"incomplete successful selection")
                replay=score(task,row,args.kit)
                require(replay["verdict"]==row["verdict"],(task["id"],"held-out grade"))
                require(json.loads(json.dumps(replay["first_mismatch"]))==row["first_mismatch"],"mismatch")
            totals[row["verdict"]]+=1
        require(dict(totals)==report["summary"]["arms"][arm]["verdicts"],"reported totals")
        if args.replay_selection and arm in ("fixed", "adaptive"):
            for name in ("om_formalize", "om_sketch", "om_synth"):
                require(digest(args.kit/name)==pins["kits"][arm][name], name+" digest")
            with ThreadPoolExecutor(max_workers=args.jobs) as workers:
                list(workers.map(lambda t,r: replay_selection(t,r,args.kit), tasks, rows))
            print(arm,"PASS sealed query sequence and selection trace")
        print(arm,dict(totals))
    print("PASS public task inputs, charged answers, all emitted programs and reported totals")


if __name__=="__main__":
    main()
