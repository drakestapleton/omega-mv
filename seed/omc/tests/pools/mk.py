#!/usr/bin/env python3
# mk.py OUTDIR -- the test-data generator of seed/omc/tests/pools (run by seed/omc/gate-pools.sh, which
# checks that `python3 seed/omc/tests/pools/mk.py DIR` gives the committed .om and .want files byte for
# byte). Writes every hand-written case and its expected output, computed here; fuzz.py writes the rest.
import os, sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

PNUM = """fn pnum v ulong to void
put ob 23 10
i = ulong 23
x = v
go = true
while go bound 21
i = sub i 1
put ob i uchar add rem x 10 48
x = div x 10
go = ne x 0
end
k = write 1 ob i sub 24 i
end
fn plong v long to void
if lt v 0
put ob 0 uchar 45
k = write 1 ob 0 1
pnum ulong neg v
else
pnum ulong v
end
end
"""

RSS = """fn hit i ulong to bool
a = and eq get sb i 86 eq get sb add i 1 109
b = and eq get sb add i 2 82 eq get sb add i 5 58
ret and a b
end
fn rss to ulong
fd = fopen pth 0 len pth 0 0
if lt fd 0
ret 0
end
n = read int fd sb 0 4096
fd = fclose int fd
if le n 0
ret 0
end
lim = ulong n
i = ulong 0
while lt add i 6 lim bound 4096
if hit i
break
end
i = add i 1
end
i = add i 6
v = ulong 0
while lt i lim bound 4096
ch = get sb i
if and ge ch 48 le ch 57
v = add mul v 10 ulong sub ch 48
else
if and ne ch 32 ne ch 9
break
end
end
i = add i 1
end
ret v
end
"""


WROTE = []


def put(name, src, want=None):
    with open(os.path.join(OUT, name + ".om"), "w") as f:
        f.write(src)
    WROTE.append(name + ".om")
    if want is not None:
        with open(os.path.join(OUT, name + ".want"), "w") as f:
            f.write(want)
        WROTE.append(name + ".want")


def W(lines, status):
    return "".join(str(x) + "\n" for x in lines) + "status %d\n" % status


# ---------------------------------------------------------------- gate 1: growth and contents
g1 = """note gate-pools 1: growth and contents. P grows 0 -> 1 -> 2 -> 512 -> 513 -> 4096 (then 10 and 4096,
note which change nothing) -> 2^20 -> 2^27 elements; Q (uchar) grows past 16777216 elements, then to 2^27.
note Old values are kept and new elements are 0 at every step.
global P ulong *
global Q uchar *
global ob uchar 24
""" + PNUM + """fn psum a ulong b ulong to ulong
s = ulong 0
i = a
while lt i b bound 200000000
s = add s get P i
i = add i 1
end
ret s
end
fn qsum a ulong b ulong to ulong
s = ulong 0
i = a
while lt i b bound 200000000
s = add s ulong get Q i
i = add i 1
end
ret s
end
fn main to int
pnum len P
r = enlarge P ulong 1
plong r
pnum len P
pnum get P 0
put P 0 7
r = enlarge P ulong 2
plong r
pnum len P
pnum get P 0
pnum get P 1
put P 1 8
r = enlarge P ulong 512
plong r
pnum len P
pnum psum 2 512
r = enlarge P ulong 513
plong r
pnum len P
pnum get P 0
pnum get P 1
pnum get P 512
r = enlarge P ulong 4096
plong r
pnum len P
pnum psum 2 4096
i = ulong 0
while lt i 4096
put P i add i 1
i = add i 1
end
r = enlarge P ulong 10
plong r
pnum len P
pnum psum 0 4096
r = enlarge P ulong 4096
plong r
pnum len P
r = enlarge P ulong 1048576
plong r
pnum len P
pnum psum 0 4096
pnum psum 4096 1048576
i = ulong 4096
while lt i 1048576 bound 2000000
put P i i
i = add i 1
end
pnum psum 0 1048576
r = enlarge P ulong 134217728
plong r
pnum len P
pnum psum 0 1048576
s = ulong 0
i = ulong 1048576
while lt i 134217728 bound 200000
s = add s get P i
i = add i 4096
end
pnum s
put P 134217727 5
pnum get P 134217727
pnum get P 1048575
r = enlarge Q ulong 16777217
plong r
pnum len Q
i = ulong 0
while lt i 16777217 bound 20000000
put Q i uchar and i 255
i = add i 1
end
pnum qsum 0 16777217
pnum ulong get Q 16777216
r = enlarge Q ulong 134217728
plong r
pnum len Q
pnum qsum 0 16777217
pnum qsum 16777217 134217728
ret 0
end
"""
o = []
P = []
o.append(0)
P = [0] * 1; o += [0, 1, 0]; P[0] = 7
P += [0]; o += [0, 2, 7, 0]; P[1] = 8
P += [0] * 510; o += [0, 512, sum(P[2:512])]
P += [0]; o += [0, 513, 7, 8, 0]
P += [0] * (4096 - 513); o += [0, 4096, sum(P[2:4096])]
for i in range(4096):
    P[i] = i + 1
o += [0, 4096, sum(P[0:4096])]
o += [0, 4096]
o += [0, 1048576, sum(P[0:4096]), 0]
M = 2**64
fill = sum(range(4096, 1048576))
tot = (sum(P[0:4096]) + fill) % M
o += [tot]
o += [0, 134217728, tot, 0, 5, 1048575]
qs = sum(i & 255 for i in range(16777217))
o += [0, 16777217, qs, 16777216 & 255]
o += [0, 134217728, qs, 0]
put("g1", g1, W(o, 0))

gf = """note gate-pools 1: float pools. F (f64) and G (f32) grow by 4096 elements 40 times, a blocker pool B above
note them forcing moves; each value written is read back after every grow. Prints 2*F[k] and 4*G[k] (as
note ulong), their sums, both lengths, the last elements (0), then G at its length traps 3.
global B uchar *
global F f64 *
global G f32 *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge B ulong 1
r = enlarge F ulong 1
r = enlarge G ulong 1
pnum ulong get F 0
k = ulong 0
while lt k 40
r = enlarge B add len B 4096
r = enlarge F add len F 4096
r = enlarge G add len G 4096
put F k add f64 k 0.5f64
put G k add f32 k 0.25f32
pnum ulong mul get F k 2.0f64
pnum ulong mul get G k 4.0f32
k = add k 1
end
s = ulong 0
t = ulong 0
k = ulong 0
while lt k 40
s = add s ulong mul get F k 2.0f64
t = add t ulong mul get G k 4.0f32
k = add k 1
end
pnum s
pnum t
pnum len F
pnum len G
pnum ulong get F sub len F 1
pnum ulong get G 40
n = len G
pnum ulong get G n
ret 0
end
"""
o = [0]
for k in range(40):
    o += [2 * k + 1, 4 * k + 1]
o += [sum(2 * k + 1 for k in range(40)), sum(4 * k + 1 for k in range(40)), 1 + 40 * 4096, 1 + 40 * 4096, 0, 0]
put("gf", gf, W(o, 103))

# ---------------------------------------------------------------- gate 2: range
g2a = """note gate-pools 2: an index equal to the length (a variable) traps 3 before any store; len + 1 is in range
note after a grow. With the compare removed the put lands and the next lines print 9.
global P ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 10
put P 9 1
pnum get P 9
r = enlarge P ulong 11
put P 10 5
pnum get P 10
i = len P
put P i 9
r = enlarge P ulong 12
pnum get P 11
ret 0
end
"""
put("g2a", g2a, W([1, 5], 103))
g2b = """note gate-pools 2: a number index past the length compiles (no error 21) and traps 3 at run time (put).
global P ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 4
put P 3 6
pnum get P 3
put P 100 1
pnum get P 100
ret 0
end
"""
put("g2b", g2b, W([6], 103))
g2c = """note gate-pools 2: a number index equal to the length traps 3 at run time (get), also when length 0.
global P ulong *
global Q ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 4
pnum get P 3
pnum len Q
pnum get P 4
ret 0
end
"""
put("g2c", g2c, W([0, 0], 103))
g2d = """note gate-pools 2: a read or write slice past the length traps 3 (uchar pool, write path).
global U uchar *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge U ulong 3
put U 0 79
put U 1 75
put U 2 10
k = write 1 U 0 3
n = len U
k = write 1 U 1 n
pnum 9
ret 0
end
"""
put("g2d", g2d, "OK\nstatus 103\n")

# ---------------------------------------------------------------- gate 3: stale base
ROUNDS = 40
STDIN = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"


def g3src(inline):
    il = " inline" if inline else ""
    head = "om2\n" if inline else ""
    return head + """note gate-pools 3: enlarge runs inside the value of put, the index of get, and the counts of read and
note write; every call grows the pool it serves by 4096 elements and a blocker pool beside it, so mremap
note moves the regions and later mappings reuse the old addresses (the gate counts both with strace).
note stdin: the 40 bytes abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN.%s
global P ulong *
global Q ulong *
global U uchar *
global V uchar *
global ob uchar 24
""" % (" Every grower is an OM-2 inline body." if inline else "") + PNUM + """fn gv v ulong to ulong%s
r = enlarge P add len P 4096
r = enlarge Q add len Q 4096
ret v
end
fn gi j ulong to ulong%s
r = enlarge P add len P 4096
r = enlarge Q add len Q 4096
ret j
end
fn gu n ulong to ulong%s
r = enlarge U add len U 4096
r = enlarge V add len V 4096
ret n
end
fn main to int
r = enlarge Q ulong 1
r = enlarge P ulong 1
r = enlarge V ulong 1
r = enlarge U ulong 64
j = ulong 0
while lt j %d
put P j gv add mul j 3 1
x = get P gi j
pnum x
k = read 0 U j gu 1
k = write 1 U j gu 1
pnum ulong k
j = add j 1
end
k = write 1 U 0 %d
s = ulong 0
j = ulong 0
while lt j %d
s = add s get P j
j = add j 1
end
pnum s
pnum len P
pnum len U
ret 0
end
""" % (il, il, il, ROUNDS, ROUNDS, ROUNDS)


o3 = []
for j in range(ROUNDS):
    o3.append(3 * j + 1)
    o3.append(STDIN[j] + "1")
last = STDIN + str(sum(3 * j + 1 for j in range(ROUNDS)))
o3.append(last)
o3.append(1 + 2 * ROUNDS * 4096)
o3.append(64 + 2 * ROUNDS * 4096)
put("g3", g3src(False), W(o3, 0))
put("g3i", g3src(True), W(o3, 0))

# ---------------------------------------------------------------- gate 4: pinning
g4 = """om2
note gate-pools 4: the first global is a pool, sized globals follow. The pool takes no pinned register: the
note set of X18..X26 written by this unit equals that of g4base.om (the same unit without the pool).
global P ulong *
global g ulong 10
global h ulong 5000
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 1000
put P 999 5
put g 9 6
put h 4999 7
r = enlarge P ulong 1000000
put P 999999 8
pnum get P 999
pnum get g 9
pnum get h 4999
pnum get P 999999
pnum len P
ret 0
end
"""
put("g4", g4, W([5, 6, 7, 8, 1000000], 0))
g4base = """om2
note gate-pools 4 baseline: g4.om without the pool (compiled only, for the pinned register set).
global g ulong 10
global h ulong 5000
global ob uchar 24
""" + PNUM + """fn main to int
put g 9 6
put h 4999 7
pnum get g 9
pnum get h 4999
ret 0
end
"""
put("g4base", g4base, W([6, 7], 0))

# ---------------------------------------------------------------- gate 5: contracts
g5a = """om2 diag
note gate-pools 5: requires eq len P 0 is kept (rule=runtime) and holds before the grow, fails after it.
global P ulong *
global ob uchar 24
""" + PNUM + """fn f k ulong to ulong
requires eq len P 0
ret k
end
fn main to int
x = f 1
pnum x
r = enlarge P ulong 8
x = f 2
pnum x
ret 0
end
"""
put("g5a", g5a, W([1], 109))
g5b = """om2 diag
note gate-pools 5: invariant le i len P is kept (rule=runtime): true for i 0..8, false at 9.
global P ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 8
i = ulong 0
while lt i 12
invariant le i len P
pnum i
i = add i 1
end
ret 0
end
"""
put("g5b", g5b, W(list(range(9)), 110))
g5c = """om2
note gate-pools 5: a constant index under unroll keeps its run-time check (length 8, copies 0..11).
global P ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 8
for j ulong 12 unroll
put P j add j 1
pnum get P j
end
ret 0
end
"""
put("g5c", g5c, W(list(range(1, 9)), 103))
g5d = """om2
note gate-pools 5: a constant index in an inline body keeps its run-time check (7 in range, 9 not).
global P ulong *
global ob uchar 24
""" + PNUM + """fn g7 to ulong inline
ret get P 7
end
fn g9 to ulong inline
ret get P 9
end
fn main to int
r = enlarge P ulong 8
put P 7 4
pnum g7
pnum g9
ret 0
end
"""
put("g5d", g5d, W([4], 103))
g5ctl = """om2 diag
note gate-pools 5 control: len of a sized global folds, so the same clause is erased rule=constant-true.
global G ulong 8
fn f k ulong to ulong
requires eq len G 8
ret k
end
fn main to int
x = f 1
ret int x
end
"""
put("g5ctl", g5ctl, W([], 1))

# ---------------------------------------------------------------- gate 8: host refusal
g8a = """note gate-pools 8: run under prlimit --as=268435456: an 8 GiB enlarge returns -12, the pool is unchanged,
note the program goes on and ends with its own status 7. Without the limit the first 8 GiB enlarge gives 0.
global P ulong *
global Q ulong *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 1000
plong r
put P 5 42
r = enlarge P ulong 1073741824
plong r
pnum len P
pnum get P 5
r = enlarge Q ulong 1073741824
plong r
pnum len Q
r = enlarge P ulong 2000
plong r
pnum len P
pnum get P 5
ret 7
end
"""
put("g8a", g8a, W([0, -12, 1000, 42, -12, 0, 0, 2000, 42], 7))
g8b = """note gate-pools 8: n times the element size at or past 2^63 is -22 with nothing changed; just below it the
note host refuses (-12).
global P ulong *
global U uchar *
global ob uchar 24
""" + PNUM + """fn main to int
r = enlarge P ulong 1152921504606846976
plong r
pnum len P
r = enlarge P ulong 18446744073709551615
plong r
r = enlarge P ulong 1152921504606846975
plong r
pnum len P
r = enlarge U ulong 9223372036854775808
plong r
r = enlarge U ulong 9223372036854775807
plong r
pnum len U
r = enlarge P ulong 3
plong r
put P 2 11
r = enlarge P ulong 2305843009213693952
plong r
pnum len P
pnum get P 2
ret 5
end
"""
put("g8b", g8b, W([-22, 0, -22, -12, 0, -22, -12, 0, 0, -22, 3, 11], 5))
g8c = """note gate-pools 8 (recorded): touch 128 MiB of a pool, one byte per page. Under
note systemd-run --user --scope -p MemoryMax=64M the expected result is the kernel's OOM kill (137).
global U uchar *
fn main to int
r = enlarge U ulong 134217728
if ne r 0
ret 3
end
i = ulong 0
while lt i 134217728 bound 40000
put U i 1
i = add i 4096
end
ret 0
end
"""
put("g8c", g8c)

# ---------------------------------------------------------------- gate 9: untouched pages
g9 = """note gate-pools 9: a 2 GiB pool with one page touched adds about one page of VmRSS. Prints the length,
note then VmRSS (kB) before the grow, after touching one page, and after touching 1024 more (the control).
global P uchar *
global sb uchar 4096
global ob uchar 24
text pth "/proc/self/status"
""" + PNUM + RSS + """fn main to int
a = rss
a = rss
r = enlarge P ulong 2147483648
if ne r 0
ret 3
end
put P 12345678 1
b = rss
i = ulong 0
while lt i 1024
put P add 1000000000 mul i 4096 1
i = add i 1
end
c = rss
pnum len P
pnum a
pnum b
pnum c
ret 0
end
"""
put("g9", g9)

# ---------------------------------------------------------------- section S: server
NREQ = 2000
srv = """note gate-pools S (design section 11): 2000 requests of growing and shrinking sizes (a fixed 64-bit LCG,
note 1 byte .. 64 MiB; the first 8 ramp to the 64 MiB high-water mark) served from one pool that is enlarged
note only past its high-water mark and reused. Prints the high-water mark, enlarge calls, new marks, VmRSS (kB)
note after the high-water point (request 8) and at the end, and a checksum of the bytes served.
note Control: with the byte L on stdin, requests 8..23 are served from fresh memory past the old end (a
note server that enlarges per request); its VmRSS must rise past the high-water mark.
global P uchar *
global sb uchar 4096
global mb uchar 1
global ob uchar 24
text pth "/proc/self/status"
""" + PNUM + RSS + """fn serve q ulong b ulong sz ulong to ulong
cs = ulong 0
o = ulong 0
while lt o sz bound 20000
put P add b o uchar and add q o 255
cs = add cs ulong get P add b o
o = add o 4096
end
ret cs
end
fn main to int
leak = false
k = read 0 mb 0 1
if gt k 0
leak = eq get mb 0 76
end
x = ulong 12345
hw = ulong 0
calls = ulong 0
marks = ulong 0
rhw = ulong 0
cs = ulong 0
q = ulong 0
while lt q %d
x = add mul x 6364136223846793005 1442695040888963407
sz = add rem shr x 33 67108864 1
if lt q 8
sz = mul add q 1 8388608
end
b = ulong 0
if and leak ge q 8
if eq q 24
break
end
sz = add rem sz 4194304 1
b = len P
r = enlarge P add b sz
calls = add calls 1
if ne r 0
ret 4
end
end
if gt sz hw
r = enlarge P sz
calls = add calls 1
if ne r 0
ret 3
end
hw = sz
marks = add marks 1
end
cs = add cs serve q b sz
if eq q 8
rhw = rss
end
q = add q 1
end
pnum hw
pnum calls
pnum marks
pnum rhw
pnum rss
pnum cs
ret 0
end
""" % NREQ
put("srv", srv)
x = 12345
hw = calls = marks = cs = 0
for q in range(NREQ):
    x = (x * 6364136223846793005 + 1442695040888963407) % M
    sz = ((x >> 33) % 67108864) + 1
    if q < 8:
        sz = (q + 1) * 8388608
    if sz > hw:
        calls += 1; hw = sz; marks += 1
    cs += (q & 255) * ((sz + 4095) // 4096)
with open(os.path.join(OUT, "srv.want"), "w") as f:
    f.write("hw %d\ncalls %d\nmarks %d\ncs %d\n" % (hw, calls, marks, cs % M))
WROTE.append("srv.want")

# ---------------------------------------------------------------- gate 10: refusals
PM = "global P ulong *\n"
errs = {
    # name: (source, line or '*', code)
    "err-fnmode": (PM + "fn f to long\nr = enlarge P ulong 4\nret r\nend\n", "*", 9),
    "err-ir": ("ir\n" + PM + "fn main to int\nret 0\nend\n", 2, 9),
    "err-x86": ("target x86efi\n" + PM + "fn main to int\nr = enlarge P ulong 4\nput P 0 1\nret int get P 0\nend\n", "*", 25),
    "err-arg": ("om2\n" + PM + "fn f a view ulong * to ulong\nret len a\nend\nfn main to int\nr = enlarge P ulong 4\nx = f P\nret 0\nend\n", 8, 19),
    "err-part": ("om2\n" + PM + "fn f a view ulong * to ulong\nret len a\nend\nfn main to int\nr = enlarge P ulong 4\nx = f part P 0 2\nret 0\nend\n", 8, 19),
    "err-expr": (PM + "fn main to int\nif eq enlarge P ulong 4 0\nret 1\nend\nret 0\nend\n", 3, 9),
    "err-sum": (PM + "fn main to int\nr = add enlarge P ulong 4 0\nret 0\nend\n", 3, 9),
    "err-stmt": (PM + "fn main to int\nenlarge P ulong 4\nret 0\nend\n", 3, 16),
    "err-sized": ("global G ulong 4\nfn main to int\nr = enlarge G ulong 8\nret 0\nend\n", 3, 7),
    "err-local": ("fn main to int\na = new ulong 4 0\nr = enlarge a ulong 8\nret 0\nend\n", 3, 7),
    "err-view": ("om2\nfn f a edit ulong * to long\nr = enlarge a ulong 8\nret r\nend\nfn main to int\nret 0\nend\n", 3, 7),
    "err-bool": ("global P bool *\nfn main to int\nret 0\nend\n", 1, 9),
    "err-nint": (PM + "fn main to int\nr = enlarge P int 4\nret 0\nend\n", 3, 7),
    "err-nlong": (PM + "fn main to int\nn = long 4\nr = enlarge P n\nret 0\nend\n", 4, 7),
    "err-rint": (PM + "fn main to int\nr = int 0\nr = enlarge P ulong 4\nret 0\nend\n", 4, 7),
    "err-devctl": ("global P uchar *\nfn main to int\nr = devctl neg int 1 uint 21531 P 0 8\nret 0\nend\n", 3, 7),
    "err-mapwrite": ("global P uchar *\nfn main to int\nh = long 0\nr = mapwrite h 0 P 0 1\nret 0\nend\n", 4, 7),
    "err-struct": ("om2\nstruct Pr a ulong b ulong end\n" + PM + "fn f p view Pr to ulong\nret 0\nend\nfn main to int\nx = f P\nret 0\nend\n", 8, 7),
}
for n, (src, ln, code) in errs.items():
    put(n, src + "note gate-pools 10: refused with error %d\n" % code,
        "omc: line %s: error %d\n" % (ln, code))

# ---------------------------------------------------------------- gate 3: read from a pipe across grows
gr = """note gate-pools 3: a uchar pool filled by read 0 P off n from a pipe, n given by a function that enlarges P
note (and a blocker B above it) by 65536 elements before every read; then the bytes are written back and their
note count printed. The gate feeds it `seq 1 200000` through a pipe; its expected output is built there.
global B uchar *
global P uchar *
global ob uchar 24
""" + PNUM + """fn gn n ulong to ulong
r = enlarge B add len B 4096
r = enlarge P add len P n
ret n
end
fn main to int
r = enlarge B ulong 1
r = enlarge P ulong 1
used = ulong 0
go = true
while go bound 100000
k = read 0 P used gn 65536
if lt k 0
ret 2
end
if eq k 0
go = false
else
used = add used ulong k
end
end
o = ulong 0
while lt o used bound 100000
k = write 1 P o sub used o
if le k 0
ret 3
end
o = add o ulong k
end
pnum used
ret 0
end
"""
put("gr", gr)
print("wrote", len(WROTE), "files")
