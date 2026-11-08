# hunt.py REPO SITES_TSV OUT: one-token mutations of small accepted programs; keep each one that reaches
# an unreached omc error site (proved by that site's mutant compiler exiting 97). Test harness only (python3 -I),
# never part of an Omega build. SITES_TSV is seed/omc/sitecov.sh's build/seed/sitecov/sites.tsv. Found
# files still need a refuse line in sites.cases and a sitecov.sh rerun; target lines must stay first.
import os, subprocess, sys, random
from concurrent.futures import ThreadPoolExecutor
repo, sites_tsv, out = sys.argv[1:4]
omc = os.path.join(repo, "seed/out/omc")
src = open(os.path.join(repo, "seed/omc/omc.om")).read().split("\n")
mdir = os.path.join(out, "m"); os.makedirs(mdir, exist_ok=True)
un = {}
for row in open(sites_tsv):
    ln, fn, w, code, by = row.rstrip("\n").split("\t")
    if by == "-":
        un.setdefault(int(code), []).append(int(ln))
def build(ln):
    p = os.path.join(mdir, str(ln))
    if not os.path.exists(p):
        s = list(src); w = s[ln - 1].split()[0]; s[ln - 1] = w + " 97"
        r = subprocess.run([omc], input="\n".join(s).encode(), capture_output=True)
        open(p, "wb").write(r.stdout); os.chmod(p, 0o755)
    return p
with ThreadPoolExecutor(8) as ex:
    list(ex.map(build, [l for v in un.values() for l in v]))
def run(exe, data):
    try:
        return subprocess.run([exe], input=data, capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        return -1
seeds = []
for f in subprocess.run(["git", "-C", repo, "ls-files", "*.om"], capture_output=True, text=True).stdout.split():
    t = open(os.path.join(repo, f), "rb").read()
    if t.count(b"\n") <= 40 and run(omc, t) == 0:
        seeds.append((f, t.decode("utf-8", "replace")))
vocab = "ulong long uchar uint bool f64 f32 int 0 1 -1 255 256 65536 4294967296 1.5f64 1.5f32 \"a\" x a b s if end ret get put len new seal open view edit add sub eq lt not neg min max and shl rotr part fork trap 5 9999999 abcdefghij".split()
rnd = random.Random(20261108)
found = {}
print("seeds", len(seeds), "unreached", sum(len(v) for v in un.values()), flush=True)
def cands():
    for f, t in seeds:
        lines = t.split("\n")
        for i, l in enumerate(lines):
            toks = l.split(" ")
            if not l.strip() or toks[0] == "note":
                continue
            for j in range(len(toks)):
                for v in rnd.sample(vocab, 12):
                    nt = list(toks); nt[j] = v
                    nl = list(lines); nl[i] = " ".join(nt)
                    yield f, "\n".join(nl).encode()
                nl = list(lines); nl[i] = " ".join(toks[:j]); yield f, "\n".join(nl).encode()
def test(c):
    f, data = c
    rc = run(omc, data)
    if rc not in un:
        return None
    for ln in un[rc]:
        if ln in found:
            continue
        if run(os.path.join(mdir, str(ln)), data) == 97:
            return ln, rc, f, data
    return None
n = 0
with ThreadPoolExecutor(8) as ex:
    for r in ex.map(test, cands(), chunksize=64):
        n += 1
        if r and r[0] not in found:
            ln, rc, f, data = r
            found[ln] = 1
            open(os.path.join(out, "h%d-c%d.om" % (ln, rc)), "wb").write(data)
            print("site", ln, "code", rc, "from", f, flush=True)
print("candidates", n, "found", len(found))
