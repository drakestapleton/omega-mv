"""Audit the sealed per-task decisions and decide whether the registered method advances."""
from collections import Counter
import json
from pathlib import Path
import statistics
import sys


def summarize(directory):
    counts={}
    for arm in ("baseline","improved_cli","fixed","adaptive"):
        rows=json.loads((directory/f"{arm}.json").read_text())
        sealed=list(map(json.loads,(directory/f"{arm}.sealed.jsonl").read_text().splitlines()))
        assert all(all(row[key]==value for key,value in choice.items())
                   for row,choice in zip(rows,sealed,strict=True))
        ids=[r["id"] for r in rows]
        assert len(set(ids))==len(ids)==80
        groups={}
        for group,n in Counter(r["group"] for r in rows).items():
            assert n==20
            groups[group]=dict(Counter(r["verdict"] for r in rows if r["group"]==group))
        budget=max(r["query_count"] for r in rows)
        assert all(len({tuple(q[0]) for q in r["queries"]})==r["query_count"]<=8 for r in rows)
        assert all(r["query_count"]==8 for r in rows if r["verdict"]!="error")
        times=[r["seconds"] for r in rows]
        counts[arm]=dict(verdicts=dict(Counter(r["verdict"] for r in rows)),groups=groups,
                         query_max=budget,selection_total_seconds=sum(times),
                         selection_median_seconds=statistics.median(times),
                         final_scoring_total_seconds=sum(r["scoring_seconds"] for r in rows))
    a,b=counts["adaptive"],counts["baseline"]
    criteria=dict(more_correct=a["verdicts"].get("correct",0)>b["verdicts"].get("correct",0),
                  no_more_wrong=a["verdicts"].get("wrong",0)<=b["verdicts"].get("wrong",0),
                  fewer_wrong_branches=a["groups"]["branch"].get("wrong",0)<b["groups"]["branch"].get("wrong",0),
                  within_budget=a["query_max"]<=8)
    interrupted = (directory/"interruption.json").exists()
    return dict(arms=counts,criteria=criteria,interrupted=interrupted,
                decision="advance" if all(criteria.values()) and not interrupted else "experimental")


if __name__=="__main__":
    print(json.dumps(summarize(Path(sys.argv[1])),indent=2))
