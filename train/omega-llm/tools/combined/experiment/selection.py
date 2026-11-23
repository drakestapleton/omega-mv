"""Experimental symbolic program selection. This module receives only answered queries."""
from collections import Counter
from itertools import permutations
import hashlib
import re


def candidates(engine, rows):
    xs, ys = zip(*rows)
    seen, kept = set(), []
    constants = tuple(dict.fromkeys([0,1,2,3] + [int(v) for v in
        re.findall(r"\b[0-9]{1,2}\b", engine.prompt.read_text().splitlines()[0])]))
    full = engine.examples_spec(rows, constants)
    english = engine.formal_spec()

    def admit(name, result):
        if result is None:
            return
        body = b"\n".join(b" ".join(line.split()) for line in result.splitlines() if line.strip())+b"\n"
        if body in seen:
            return
        seen.add(body)
        if engine.predict(body, xs) == list(ys):
            kept.append((name, body))

    # Give both engines a seat before later proposals. Proposals from descriptions
    # also have to pass every observed row in the seeded execution sandbox.
    generators = ("om_sketch", "om_synth") if engine.shape != 5 else ("om_sketch",)
    for spec in dict.fromkeys(s for s in (full, english) if s is not None):
        for name in generators:
            admit(name, engine.symbolic(name, spec))
    ordinal = 1
    while len(kept) < 8:
        body = engine.symbolic("om_sketch", full+f"skip {ordinal}\n".encode())
        if body is None:
            break
        admit("om_sketch", body)
        ordinal += 1
    if "om_synth" in generators:
        # Observation-equivalent expressions merge inside the native synthesizer.
        # Change its search order and project the examples to obtain alternatives.
        # Every proposal is still checked on all rows.
        for subset in (rows,rows[::2],rows[1::2],rows[:-1],rows[1:],rows[:2],rows[-2:]):
            if len(kept) == 8:
                break
            spec = engine.examples_spec(subset, tuple(reversed(constants)))
            admit("om_synth", engine.symbolic("om_synth", spec))
    if engine.shape in (2,3):
        # Argument order also determines which representative survives observation
        # deduplication in the expression search. Undo that permutation on its body.
        names = (b"a",b"b",b"c")[:engine.shape]
        for order in permutations(range(engine.shape)):
            if len(kept) == 8:
                break
            if order == tuple(range(engine.shape)):
                continue
            permuted = [(tuple(x[i] for i in order),y) for x,y in rows]
            source = engine.symbolic("om_synth",engine.examples_spec(permuted,constants))
            if source:
                rename = dict(zip(names,(names[i] for i in order)))
                restored = b"\n".join(b" ".join(rename.get(w,w) for w in line.split())
                                        for line in source.splitlines())
                admit("om_synth",restored)
    return kept


def disagreement(values):
    total = len(values)
    return total*(total-1)//2 - sum(n*(n-1)//2 for n in Counter(values).values())


def choose(engine, fixed, pool, query, adaptive):
    rows, rounds = [], []
    for x in fixed[:4 if adaptive else 8]:
        rows.append((x,query(x)))
    survivors = candidates(engine, rows)
    rounds.append({"answers":len(rows),"generated":len(survivors)})
    while len(rows) < 8:
        used = {x for x,_ in rows}
        unused = [x for x in pool if x not in used]
        choice = next(x for x in fixed if x not in used)
        pairs = 0
        if len(survivors) >= 2:
            predictions = [engine.predict(body,unused) for _,body in survivors]
            for x, values in zip(unused,zip(*predictions,strict=True),strict=True):
                score = disagreement(values)
                if score > pairs:
                    choice,pairs = x,score
        y = query(choice)
        rows.append((choice,y))
        survivors = [(name,body) for name,body in survivors if engine.predict(body,[choice])==[y]]
        record = {"answers":len(rows),"disagreeing_pairs":pairs,"survived":len(survivors)}
        if not survivors:
            survivors = candidates(engine,rows)
            record["generated"] = len(survivors)
        rounds.append(record)
    rounds[-1]["finalists"] = [{"engine":name,"bytes":len(body),"sha256":hashlib.sha256(body).hexdigest()}
                              for name,body in survivors]
    if not survivors:
        return None,"abstain",rounds
    name,body=min(survivors,key=lambda item:len(item[1]))
    return body,name,rounds
