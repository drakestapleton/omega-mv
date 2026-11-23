"""Exercise both emitted programs and reject a contradictory inactive tail."""
from pathlib import Path
import sys
import tempfile

import fixture
from engines import Engines


def main(kit):
    for family,mask in (("adjacent-add",1),("anchor-add",2)):
        task=next(t for t in fixture.tasks("dev") if t["family"]==family and t["k"]==3)
        inputs=[(n,*a) for n in (0,1,4,8) for a in
                [(7,7,2,2,9,1,3,3),((1<<64)-1,1,0,2,1,7,5,8)]]
        rows=[(x,fixture.ref(task,x)) for x in inputs]
        with tempfile.TemporaryDirectory() as d:
            eng=Engines(kit,d,task["prompt"])
            def generate(cases):
                spec=eng.examples_spec(cases)+f"rewrites {mask}\n".encode()
                return eng.symbolic("om_sketch",spec)
            body=generate(rows)
            assert body and eng.predict(body,inputs)==[y for _,y in rows]
            invalid=rows.copy()
            x,y=invalid[0]
            invalid[0]=(x,(*y[:-1],y[-1]^1))
            assert generate(invalid) is None, "an empty active prefix cannot change the tail"
    print("PASS both emitted rewrites on empty, partial, repeated, wrapping and full vectors; changed tail rejected")


if __name__=="__main__":
    main(Path(sys.argv[1]))
