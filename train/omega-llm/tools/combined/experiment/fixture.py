"""Frozen CPU-only development and held-out tasks. Only the experiment judge imports ref()."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random

U64 = (1 << 64) - 1
MANIFEST = Path(__file__).with_name("manifest.json")
SIGNATURE = {1: "a ulong", 2: "a ulong b ulong", 3: "a ulong b ulong c ulong",
             4: "a view ulong 8 n ulong", 5: "a edit ulong 8 n ulong"}

# Variants of a template always stay in the same split. K is interpolated in prose and
# passed to a separate reference implementation. Each evaluation family has four variants.
FAMILIES = [
 ("eval","branch","threshold-gap",2,"if the first argument exceeds the second by more than {k}, return their difference, otherwise return the second argument"),
 ("eval","branch","equal-offset",2,"return the sum of the arguments when the first equals the second plus {k}, and the smaller argument otherwise"),
 ("eval","branch","minimum-offset",3,"return the third argument when the first plus {k} is below the second, otherwise return the first"),
 ("eval","branch","masked-choice",3,"return the second argument when the first has bit {k} set, and the third argument otherwise"),
 ("eval","branch","residue-choice",2,"return the first argument if its remainder modulo {k} equals the second argument, and their sum otherwise"),
 ("eval","arithmetic","scaled-sum",2,"return {k} times the first argument plus the second"),
 ("eval","arithmetic","product-offset",2,"return the product of the first argument plus {k} and the second argument plus one"),
 ("eval","arithmetic","floor-before-add",2,"return the first argument divided by {k}, rounded down, plus the second argument"),
 ("eval","arithmetic","binary-mix",2,"return the bitwise exclusive or of the first argument and the second argument multiplied by {k}"),
 ("eval","arithmetic","paired-residue",2,"return the sum of the two remainders after dividing each argument by {k}"),
 ("eval","read","stride-total",4,"sum values at indexes divisible by {k} in the first n items"),
 ("eval","read","larger-step-count",4,"count consecutive pairs in the first n items where the right value exceeds the left value by at least {k}"),
 ("eval","read","scaled-alternates",4,"sum the first n items, multiplying each odd-indexed value by {k} first"),
 ("eval","read","clipped-total",4,"sum the first n values after capping each at {k}"),
 ("eval","read","index-class",4,"count values among the first n whose remainder modulo {k} equals their index modulo {k}"),
 ("eval","rewrite","shifted-index-xor",5,"exclusive-or each of the first n items with its index plus {k}"),
 ("eval","rewrite","alternating-scale",5,"multiply odd-indexed items among the first n by {k} and preserve the others"),
 ("eval","rewrite","pairwise-swap-offset",5,"swap each complete adjacent pair among the first n and add {k} to the new left member; preserve any unpaired item"),
 ("eval","rewrite","local-peaks",5,"add {k} to each strict interior local maximum of the original first n items; leave the endpoints alone"),
 ("eval","rewrite","clipped-gap",5,"replace each of the first n items by its excess above {k}, or by zero if it does not exceed {k}"),
 ("dev","branch","sum-cutoff",2,"return the larger argument if their sum is above {k} and zero otherwise"),
 ("dev","branch","sign-choice",3,"if the first argument is smaller than the second return the third plus {k}, otherwise return the third"),
 ("dev","arithmetic","unary-square",1,"return the square of the argument plus {k}"),
 ("dev","arithmetic","squared-distance",2,"return the squared difference of the arguments plus {k}"),
 ("dev","read","residue-total",4,"sum the remainders modulo {k} of the first n items"),
 ("dev","read","large-item-count",4,"count the first n items that exceed {k}"),
 ("dev","rewrite","adjacent-add",5,"add {k} times the next original item to each of the first n items except the last"),
 ("dev","rewrite","anchor-add",5,"add {k} times the original first item to every item among the first n"),
 ("dev","rewrite","constant-add",5,"add {k} to each of the first n items"),
 ("dev","rewrite","constant-xor",5,"apply bitwise exclusive or with {k} to each of the first n items"),
 ("dev","rewrite","constant-fill",5,"fill the first n items with {k}"),
 ("dev","rewrite","prefix-high",5,"set each of the first n items to the largest original value up to that point plus {k}"),
]


def scalar(f, k, x):
    a, b, c = (*x, 0, 0)[:3]
    if f == "threshold-gap": return a-b if a > b+k else b
    if f == "equal-offset": return a+b if a == b+k else min(a,b)
    if f == "minimum-offset": return c if a+k < b else a
    if f == "masked-choice": return b if a & (1<<k) else c
    if f == "residue-choice": return a if a%k == b else a+b
    if f == "scaled-sum": return k*a+b
    if f == "product-offset": return (a+k)*(b+1)
    if f == "floor-before-add": return a//k+b
    if f == "binary-mix": return a^(b*k)
    if f == "paired-residue": return a%k+b%k
    if f == "sum-cutoff": return max(a,b) if a+b>k else 0
    if f == "sign-choice": return c+k if a<b else c
    if f == "unary-square": return a*a+k
    if f == "squared-distance": return (a-b)**2+k
    raise KeyError(f)


def array(f, k, x, rewrite):
    n, *a = x
    active = a[:n]
    if not rewrite:
        if f == "stride-total": return sum(active[::k])
        if f == "larger-step-count": return sum(right>=left+k for left,right in zip(active,active[1:]))
        if f == "scaled-alternates": return sum(active[::2])+k*sum(active[1::2])
        if f == "clipped-total": return sum(min(v,k) for v in active)
        if f == "index-class": return sum(v%k == i%k for i,v in enumerate(active))
        if f == "residue-total": return sum(v%k for v in active)
        if f == "large-item-count": return sum(v>k for v in active)
        raise KeyError(f)
    out = list(a)
    for i, v in enumerate(active):
        if f == "shifted-index-xor": out[i] = v^(i+k)
        elif f == "alternating-scale": out[i] = k*v if i%2 else v
        elif f == "pairwise-swap-offset":
            if i%2: out[i] = a[i-1]
            elif i+1<n: out[i] = a[i+1]+k
        elif f == "local-peaks":
            if 0<i<n-1 and a[i-1]<v>a[i+1]: out[i] = v+k
        elif f == "clipped-gap": out[i] = max(0,v-k)
        elif f == "adjacent-add": out[i] = v+(k*a[i+1] if i+1<n else 0)
        elif f == "anchor-add": out[i] = v+k*a[0]
        elif f == "constant-add": out[i] = v+k
        elif f == "constant-xor": out[i] = v^k
        elif f == "constant-fill": out[i] = k
        elif f == "prefix-high": out[i] = max(active[:i+1])+k
        else: raise KeyError(f)
    return tuple(v & U64 for v in out)


def ref(task, x):
    f, k, shape = task["family"], task["k"], task["shape"]
    y = scalar(f,k,x) if shape < 4 else array(f,k,x,shape == 5)
    return y if shape == 5 else (y & U64,)


def inputs(shape):
    rng = random.Random(20261123 + shape)
    if shape == 1:
        fixed = [(a,) for a in (23,18,22,27,35,54,81,210)]
        pool = [(i,) for i in range(32)]
        score = [(i,) for i in range(32,64)]
    elif shape in (2,3):
        fixed = [x[:shape] for x in [(2,11,5),(13,3,13),(11,11,11),(21,0,0),
                                      (1,19,26),(32,7,14),(13,26,4),(20,4,1)]]
        pool, score = [], []
        for stream, base in [(pool,0),(score,10)]:
            for a,b in [(0,0),(0,1),(1,0),*((j,0) if base==0 else (0,j) for j in range(2,8)),*((base+j,base+j+d) for j in (6,8,11,16,31,32,33) for d in range(-6,7))]:
                stream.append((a,b) if shape==2 else (a,b,(a+b+base)%13))
            stream.extend(tuple(rng.randrange(33) for _ in range(shape)) for _ in range(54))
    else:
        a,b=(7,0,3,11,3,2,9,13),(9,2,3,2,1,12,0,9)
        fixed = [(n,*v) for v in (a,b) for n in (0,2,5,8)]
        pool,score=[],[]
        for stream, offset in [(pool,0),(score,1)]:
            arrays=[(offset,)*8,(offset,3,3,offset,0,5,5,1),tuple(range(offset,offset+8)),
                    (8,1,9,1,7,2,6,2+offset),tuple(rng.randrange(5) for _ in range(8))]
            stream.extend((n,*v) for n in range(9) for v in arrays)
            stream.extend((i%9,*(rng.randrange(12) for _ in range(8))) for i in range(30))
    pool = list(dict.fromkeys(pool + fixed))
    score = [x for x in dict.fromkeys(score) if x not in set(pool)]
    return {"fixed":fixed,"pool":pool,"score":score}


def make():
    data = {"inputs":{str(s):inputs(s) for s in range(1,6)}, "tasks":[]}
    for split,group,family,shape,description in FAMILIES:
        for k in (2,3,4,5):
            sig = "fn solve "+SIGNATURE[shape]+" to "+("void" if shape==5 else "ulong")
            prompt = "note "+description.format(k=k)+"\n"+sig+"\n"
            data["tasks"].append(dict(id=f"{split}-{family}-{k}", split=split, group=group,
                                      family=family,k=k,shape=shape,prompt=prompt))
    return data


def tasks(split):
    data=json.loads(MANIFEST.read_text())
    for t in data["tasks"]:
        if t["split"] == split:
            yield {**t, **{key:list(map(tuple,xs)) for key,xs in data["inputs"][str(t["shape"])].items()}}


def check():
    assert json.loads(MANIFEST.read_text()) == json.loads(json.dumps(make()))
    dev,ev=list(tasks("dev")),list(tasks("eval"))
    assert Counter(t["group"] for t in ev)==dict.fromkeys(("arithmetic","branch","read","rewrite"),20)
    assert not {t["family"] for t in dev}&{t["family"] for t in ev}
    observed=set()
    for t in [*dev,*ev]:
        assert len(set(t["fixed"]))==len(t["fixed"])==8 and set(t["fixed"])<=set(t["pool"])
        assert not set(t["pool"])&set(t["score"]) and len(t["score"])>=20
        probes=t["pool"]+t["score"]
        signature=(t["shape"],tuple(ref(t,x) for x in probes))
        assert signature not in observed,t["id"]
        observed.add(signature)
        if t["shape"]==5:
            assert {x[0] for x in t["score"]}==set(range(9))
            assert all(ref(t,x)[x[0]:]==x[1+x[0]:] for x in probes)
    print("Verified",len(dev),"development and",len(ev),"evaluation tasks.",
          "Manifest SHA-256",hashlib.sha256(MANIFEST.read_bytes()).hexdigest())


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--create",action="store_true")
    if p.parse_args().create:
        with MANIFEST.open("x") as out:
            json.dump(make(),out,separators=(",",":"))
            out.write("\n")
    check()
