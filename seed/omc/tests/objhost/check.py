#!/usr/bin/env python3
"""Host effects in native objects (DRA-542): an independent test oracle, not a linker.

Usage: check.py OMC OUT_DIR. OMC is the compiler under test; the module driver is built from
seed/ng/sha256.om + seed/modules/driver.om by the same OMC. OUT_DIR must not exist.
Checks, each printed PASS or raising with a named contract:
  accept   each word of the object host subset compiles to OMOBJ001 whose code equals the
           function-mode compile of the same source;
  refuse   device words, program-only host words, globals and text still refuse with error 9;
  record   a function's stack record covers its host-word pushes (the private 4096-byte path buffer);
  run      a linked two-module program reads stdin, writes stdout, creates/stats/reads a file,
           reads the clock and exits through a module, matching a single-unit program build;
  stack    the module driver refuses (37, at build) a call chain that fits 8 MiB only if a host push is ignored,
           and links and runs the same chain once the push fits.
"""
import hashlib, os, pathlib, re, shutil, struct, subprocess, sys

P = pathlib.Path
REPO = P(__file__).resolve().parents[4]
OMC = P(sys.argv[1]).resolve()
OUT = P(sys.argv[2]).resolve()
OUT.mkdir(parents=True)
os.chdir(OUT)
MIB8 = 8 * 1024 * 1024
sha = lambda b: hashlib.sha256(b).hexdigest()
COMP = sha(OMC.read_bytes())


def ok(label):
    print("PASS", label, flush=True)


def omc(src, status=0):
    r = subprocess.run([OMC], input=src.encode(), capture_output=True, timeout=60)
    assert r.returncode == status, (src, r.returncode, status, r.stderr.decode())
    if status:
        assert not r.stdout, "refusal wrote output"
    return r.stdout


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def parse(data):
    """OMOBJ001 per spec/omegese-modules.md: returns (functions, calls, code range)."""
    assert data[:8] == b"OMOBJ001", "object-magic"
    start, end, nf, nc = u64(data, 32), u64(data, 40), u64(data, 48), u64(data, 56)
    p, fns = end, []
    for _ in range(nf):
        flags, addr, ret, np, stack, nlen = [u64(data, p + 8 * i) for i in range(6)]
        p += 48
        name = data[p:p + nlen].decode()
        p += nlen
        p += (-p) % 8
        p += 40 * np
        fns.append(dict(flags=flags, name=name, stack=stack))
    calls = []
    for _ in range(nc):
        calls.append([u64(data, p + 8 * i) for i in range(4)])
        p += 32
    assert p == len(data), "object-exact-end"
    return fns, calls, (start, end)


# accept: every word of the subset, and the object's code is the function-mode code.
SUBSET = {
    "write": "n = write 1 b 0 len b\nret n",
    "read": "n = read 0 b 0 len b\nret n",
    "exit": "exit 3",
    "monons": "n = monons\nret n",
    "realns": "n = realns\nret n",
    "sleepns": "n = sleepns long 1000\nret n",
    "fopen+fclose": "fd = fopen b 0 len b 0 0\nc = fclose int fd\nret long c",
    "fstat": "n = fstat int 0 b 0 128\nret n",
    "stat": "n = stat b 0 1 b 0 128\nret n",
    "lstat": "n = lstat b 0 1 b 0 128\nret n",
    "getuid": "n = getuid\nret n",
    "geteuid": "n = geteuid\nret n",
    "getgid": "n = getgid\nret n",
    "getegid": "n = getegid\nret n",
}
OBJDUMP = shutil.which("aarch64-linux-gnu-objdump") or shutil.which("objdump")


def sp_walk(code):
    """Independent decoder (GNU objdump): the deepest SP and the final SP along the emitted words, read in
    order. Valid for the straight-line one-statement bodies below (no early ret, no frame allocation after
    a push), where the record must equal it; in general the record is an upper bound."""
    (OUT / "code.bin").write_bytes(code)
    r = subprocess.run([OBJDUMP, "-D", "-b", "binary", "-m", "aarch64", str(OUT / "code.bin")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    cur = deep = low = 0
    for line in r.stdout.splitlines():
        if re.search(r"\bmov\s+sp\b|\[sp, #-?0x[0-9a-f]+\]!|\[sp\], #-?0x[0-9a-f]+", line):
            raise AssertionError(("object-sp-write-unmodelled", line))
        m = re.search(r"\t(sub|add)\s+sp, sp, #0x([0-9a-f]+)(, lsl #12)?", line)
        if m:
            v = int(m.group(2), 16) << (12 if m.group(3) else 0)
            cur += v if m.group(1) == "sub" else -v
            deep, low = max(deep, cur), min(low, cur)
        elif re.search(r"\t(sub|add)\s+sp,", line):
            raise AssertionError(("object-sp-write-unmodelled", line))
    return deep, cur, low


for word, body in SUBSET.items():
    sig = "to void" if word == "exit" else "to long"
    src = f"om2\nexport fn t b edit uchar * {sig}\n{body}\nend\n"
    obj = omc("object\n" + src)
    fns, calls, (s, e) = parse(obj)
    assert obj[s:e] == omc(src), f"object-code-equals-function-mode {word}"
    walk = sp_walk(obj[s:e]) if OBJDUMP else None
    if walk is None:
        ok(f"accept {word} (objdump cross-check NOT_RUN)")
        continue
    assert walk == (fns[0]["stack"], 0, 0), ("object-host-stack-record", word, fns[0]["stack"], walk)
    ok(f"accept {word}; record {fns[0]['stack']} = deepest SP in objdump's decode, SP back to 0")

# refuse: what still needs state the module linker does not provide.
REFUSE = {
    "device mapdrop": "export fn t to long\nn = mapdrop 1\nret n",
    "program-only argcnt": "export fn t to long\nn = argcnt\nret n",
    "global": "global g uchar 1\nexport fn t to uchar\nret get g 0",
    "text": "text g \"a\"\nexport fn t to uchar\nret get g 0",
}
for label, body in REFUSE.items():
    omc(f"object\nom2\n{body}\nend\n", 9)
    ok(f"refuse {label}")

# record: the stack record covers the 4096-byte private path buffer and its save area.
fns, _, _ = parse(omc("object\nom2\nexport fn t b view uchar * to long\nfd = fopen b 0 len b 0 0\nret fd\nend\n"))
assert fns[0]["stack"] >= 4096 + 16 and fns[0]["stack"] % 16 == 0, ("object-host-stack-record", fns)
ok(f"record fopen stack {fns[0]['stack']} >= 4112")
fns, _, _ = parse(omc("object\nom2\nexport fn t to long\nn = getuid\nret n\nend\n"))
ok(f"record getuid stack {fns[0]['stack']}")

# Nested calls as arguments: measure whether a call's record ever exceeds frame + its own save area.
nest = "object\nom2\nfn g a ulong to ulong\nret add a 1\nend\nexport fn f a ulong to ulong\nret g g g a\nend\n"
fns, calls, _ = parse(omc(nest))
print("MEASURE nested call costs", [c[3] for c in calls], "record f", fns[1]["stack"], flush=True)
assert fns[1]["stack"] >= max(c[3] for c in calls if c[1] == 1), "object-record-covers-calls"
ok("record covers its calls")

# The module driver, built from the seeded sources by the compiler under test.
drv_src = b"om2\n" + (REPO / "seed/ng/sha256.om").read_bytes() + (REPO / "seed/modules/driver.om").read_bytes()
r = subprocess.run([OMC], input=drv_src, capture_output=True)
assert r.returncode == 0, r.stderr.decode()
DRV = OUT / "ommod"
DRV.write_bytes(r.stdout)
DRV.chmod(0o755)
STORE = OUT / "store"
STORE.mkdir()


def drv(args, status=0):
    r = subprocess.run([DRV, *map(str, args)], capture_output=True, timeout=120)
    assert r.returncode == status, (args, r.returncode, status, r.stdout, r.stderr)
    return r


def build(name, text, status=0):
    p = OUT / (name + ".om")
    p.write_text(text)
    h = sha(p.read_bytes())
    r = drv(["build", OMC, COMP, "debug", "aarch64-linux", STORE, p, h], status)
    return h, (r.stdout.decode().split()[-1] if status == 0 else None)


def link(h, art, dest, entry, status=0):
    return drv(["link", STORE, COMP, "debug", "aarch64-linux", h, art, "program", entry, dest], status)


def run(exe, stdin=b""):
    return subprocess.run([str(exe)], input=stdin, capture_output=True, timeout=60)


# run: a two-module program with real I/O, against a single-unit build of the same functions.
IO = """export fn say b view uchar * n ulong to long
w = write 1 b 0 n
ret w
end
export fn hear b edit uchar * to long
n = read 0 b 0 len b
ret n
end
export fn mkfile b edit uchar * to long
fd = fopen b 0 5 577 420
w = write int fd b 0 len b
s = fstat int fd b 0 128
c = fclose int fd
if or lt fd 0 or lt w 0 or lt s 0 lt c 0
ret 0
end
ret long add ulong get b 48 mul ulong get b 49 256
end
export fn later to long
a = monons
b = monons
ret long sub b a
end
export fn stop v int to void
exit v
end
"""
MAIN = """export fn main2 to int
b = new uchar 64 0
n = hear b
w = say b ulong n
f = new uchar 300 0
put f 0 111
put f 1 104
put f 2 111
put f 3 115
put f 4 116
z = mkfile f
d = later
if lt d 0
stop 5
end
if ne z 300
stop 6
end
stop int add 10 n
ret 0
end
"""
ioh, ioart = build("io", "om2\n" + IO)
calls = {"hear": "dep_hear", "say": "dep_say", "mkfile": "dep_mkfile", "later": "dep_later", "stop": "dep_stop"}
root = "om2\n" + "".join(f"import {a} {ioh} {e}\n" for e, a in calls.items())
body = MAIN
for e, a in calls.items():
    body = re.sub(rf"(?m)(^|= ){e}\b", rf"\g<1>{a}", body)
rh, rart = build("root", root + body)
link(rh, rart, OUT / "io.elf", "main2")
got = run(OUT / "io.elf", b"hello module\n")
mono = omc("om2\n" + IO.replace("export fn", "fn") + MAIN.replace("export fn main2", "fn main") )
(OUT / "mono").write_bytes(mono)
(OUT / "mono").chmod(0o755)
(OUT / "ohost").unlink()
want = run(OUT / "mono", b"hello module\n")
assert got.stdout == b"hello module\n" and got.returncode == 23, ("objhost-run", got)
assert (got.stdout, got.returncode) == (want.stdout, want.returncode), ("objhost-differential", got, want)
assert (OUT / "ohost").stat().st_size == 300, "objhost-file"
ok("run linked modules: stdin->stdout, fopen/write/fstat/fclose, monons, exit 23 = single-unit build")


# stack: a chain that fits 8 MiB only if the leaf's host push is ignored must be refused (37).
def chain(mid_bytes, host, status=0):
    word = "fd = fopen b 0 len b 0 0\nret fd" if host else "ret long get a 0"
    leaf = f"om2\nexport fn leaf b view uchar * to long\na = new uchar 4194304 1\n{word}\nend\n"
    lh, la = build(f"leaf{host}{mid_bytes}", leaf)
    mid = (f"om2\nimport dep {lh} leaf\nexport fn top to int\nm = new uchar {mid_bytes} 0\n"
           f"put m 0 47\nput m 1 0\nr = dep part m 0 1\nret int and r 0\nend\n")
    mh, ma = build(f"mid{host}{mid_bytes}", mid, status)
    leafobj = parse(omc("object\n" + leaf))[0][0]["stack"]
    return mh, ma, leafobj


# Find the frame of mid so that frame + call cost + leaf frame lands just under 8 MiB without the push.
midobj = lambda n: parse(omc(f"object\nom2\nextern fn dep b view uchar * to long\nexport fn top to int\nm = new uchar {n} 0\nput m 0 47\nput m 1 0\nr = dep part m 0 1\nret int and r 0\nend\n"))[1][0][3]
size = MIB8 - 4194304 - 4096
while midobj(size) + 4194304 + 2048 > MIB8:
    size -= 16
cost = midobj(size)
mh, ma, leafrec = chain(size, True, 37)
print("MEASURE mid call cost", cost, "leaf record with fopen", leafrec, "sum", cost + leafrec, "limit", MIB8, flush=True)
assert cost + 4194304 <= MIB8 < cost + leafrec, "objhost-chain-shape"
ok("stack: chain over 8 MiB only through the host push is refused 37")
ph, pa, _ = chain(size, False)
link(ph, pa, OUT / "pure.elf", "top")
assert run(OUT / "pure.elf").returncode == 0, "objhost-pure-chain-runs"
ok("stack: same chain without the host push links and runs")
small = size - 8192
sh_, sa, srec = chain(small, True)
assert midobj(small) + srec <= MIB8
link(sh_, sa, OUT / "fits.elf", "top")
res = run(OUT / "fits.elf")
assert res.returncode == 0, ("objhost-deep-fopen-runs", res.returncode)
ok(f"stack: host push deep in an 8 MiB chain that fits links and runs (exit {res.returncode})")
print("OBJHOST PASS", flush=True)
