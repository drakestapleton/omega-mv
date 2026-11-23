"""Measure each new rewrite separately with the same eight examples and seeded sketcher."""
import argparse
import json
from pathlib import Path
import tempfile
import time

from engines import Engines
import fixture
from measure import digest, json_file, score

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("kit",type=Path)
    p.add_argument("out",type=Path)
    args=p.parse_args()
    args.out.mkdir()
    json_file(args.out/"inputs.json",{"om_sketch":digest(args.kit/"om_sketch"),
                                     "omc":digest(args.kit/"omc"),
                                     "fixture":digest(Path(fixture.__file__))})
    dev=[t for t in fixture.tasks("dev") if t["shape"]==5]
    for mask in range(4):
        results=[]
        for t in dev:
            xs=t["fixed"]
            answers=[fixture.ref(t,x) for x in xs]
            with tempfile.TemporaryDirectory() as d:
                eng=Engines(args.kit,d,t["prompt"])
                start=time.monotonic()
                spec=eng.examples_spec(list(zip(xs,answers)))+f"rewrites {mask}\n".encode()
                body=eng.symbolic("om_sketch",spec)
                if body and eng.predict(body,xs) != answers:
                    raise AssertionError(("emitted rewrite disagrees with native matcher",t["id"],mask))
                seconds=time.monotonic()-start
            row=dict(id=t["id"],family=t["family"],group=t["group"],mask=mask,seconds=seconds,
                     program=body.decode() if body else None,query_count=8)
            results.append(score(t,row,args.kit))
        json_file(args.out/f"mask-{mask}.json",results)
        print(mask,sum(r["verdict"]=="correct" for r in results),len(results))

if __name__=="__main__":
    main()
