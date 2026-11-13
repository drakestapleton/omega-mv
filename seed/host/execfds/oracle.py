#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# seed/host/execfds/oracle.py: ORACLE and TEST INSTRUMENT only (Python 3, ctypes). It is never built, linked,
# shipped or placed on a product path; seed/host/execfds/check.sh runs it beside the seeded fixture.
# Independent of omc: it decodes the fixture's own packets with its own framing code, makes the documented
# descriptor changes with the C library and the kernel, and execs through ctypes execve with raw argv/envp
# arrays (a Python dict environment would lose the duplicate entries the scenarios carry). System call numbers
# and flag values are read from the kernel headers, never typed here.
#   oracle.py execfds S BIN       scenario S (1..6) of BIN's "launch S"; stdout and exit status must equal it
#   oracle.py selftest            the framing validator accepts/refuses the documented boundary packets
#   oracle.py order TRACE BIN     strace order of one execfds (BIN "order"): exit 0 PASS, 1 FAIL, 2 checker error
#   oracle.py memtrace KIND TRACE BIN [N M K]  strace memory check of BIN malbig|lying (no mapping at all) or
#                                 bigok (at least one mapping, total length <= 5(N+M)+65+K plus a page each)
#   oracle.py subst FROM TO SRC OUT   SRC with the bytes of FROM (present exactly once) replaced by TO
# Failures are explicit exits with a message on stderr; nothing relies on assert.
import ctypes
import os
import re
import resource
import subprocess
import sys

HDR = "/usr/include"


def die(code, msg):
    sys.stderr.write("oracle.py: %s\n" % msg)
    sys.exit(code)


def define(path, name, seen=()):
    """Value of '#define NAME VALUE' in HDR/path, following one-word aliases inside the same header."""
    try:
        txt = open(os.path.join(HDR, path)).read()
    except OSError as e:
        die(2, "ORACLE INVALID: cannot read %s: %s" % (path, e))
    m = re.search(r"^#define\s+%s\s+(\S+)" % re.escape(name), txt, re.M)
    if not m:
        die(2, "ORACLE INVALID: %s not defined in %s" % (name, path))
    v = m.group(1).strip("()")
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", v):
        return int(v, 16)
    if re.fullmatch(r"0[0-7]+", v):
        return int(v, 8)
    if re.fullmatch(r"[0-9]+", v):
        return int(v)
    m2 = re.fullmatch(r"([0-9]+)<<([0-9]+)", v)
    if m2:
        return int(m2.group(1)) << int(m2.group(2))
    if v in seen:
        die(2, "ORACLE INVALID: alias loop at %s" % v)
    return define(path, v, seen + (name,))


NR_UNSHARE = define("asm-generic/unistd.h", "__NR_unshare")
NR_FCNTL = define("asm-generic/unistd.h", "__NR_fcntl")
NR_CLOSE_RANGE = define("asm-generic/unistd.h", "__NR_close_range")
CLONE_FILES = define("linux/sched.h", "CLONE_FILES")
F_GETFD = define("asm-generic/fcntl.h", "F_GETFD")
F_SETFD = define("asm-generic/fcntl.h", "F_SETFD")
FD_CLOEXEC = define("asm-generic/fcntl.h", "FD_CLOEXEC")
O_CLOEXEC = define("asm-generic/fcntl.h", "O_CLOEXEC")

libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long
libc.execve.restype = ctypes.c_int
libc.execve.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p)]


def sc(nr, *args):
    ctypes.set_errno(0)
    r = libc.syscall(ctypes.c_long(nr), *[ctypes.c_long(a) for a in args])
    if r < 0:
        return -ctypes.get_errno()
    return r


class Trap(Exception):
    pass


def packet(b, env):
    """Records of a u16 packed list: count >= 1, each record inside the packet, no NUL, no trailing bytes;
    the first record nonempty (argv) or every record nonempty (environment)."""
    if len(b) < 2:
        raise Trap("short packet")
    count = b[0] | b[1] << 8
    if count == 0:
        raise Trap("count 0")
    p = 2
    recs = []
    for i in range(count):
        if p + 2 > len(b):
            raise Trap("truncated length")
        n = b[p] | b[p + 1] << 8
        p += 2
        if p + n > len(b):
            raise Trap("truncated record")
        r = b[p:p + n]
        if b"\0" in r:
            raise Trap("embedded zero")
        if n == 0 and (env or i == 0):
            raise Trap("empty record")
        recs.append(bytes(r))
        p += n
    if p != len(b):
        raise Trap("trailing bytes")
    return recs


def keeplist(k):
    if len(k) % 4:
        raise Trap("keep length not a multiple of 4")
    fds = []
    prev = 2
    for i in range(0, len(k), 4):
        v = int.from_bytes(k[i:i + 4], "little")
        if v <= prev or v > 2147483647:
            raise Trap("keep entry %d" % v)
        fds.append(v)
        prev = v
    return fds


def isopen(fd):
    return sc(NR_FCNTL, fd, F_GETFD) >= 0


def out(s):
    b = s.encode() if isinstance(s, str) else s
    while b:
        n = os.write(1, b)
        b = b[n:]


def fdlines(top):
    out("".join("fd %d %s\n" % (f, "open" if isopen(f) else "closed") for f in range(top + 1)))


def failed(r):
    out("result -%d\n" % -r)
    fdlines(24)
    os._exit(0)


def cstrs(recs):
    arr = (ctypes.c_char_p * (len(recs) + 1))()
    for i, r in enumerate(recs):
        arr[i] = r
    arr[len(recs)] = None
    return arr


def launch(a, e, k):
    """The documented execfds contract, implemented independently: framing first (trap 3 = exit 103), then
    a private descriptor table, every kept fd checked, FD_CLOEXEC cleared on the kept, every other fd above 2
    closed, execve. A failing step returns its -errno (here: the in-process report, exit 0)."""
    try:
        argv = packet(a, False)
        envp = packet(e, True)
        keep = keeplist(k)
    except Trap:
        os._exit(103)
    r = sc(NR_UNSHARE, CLONE_FILES)
    if r < 0:
        failed(r)
    for fd in keep:
        r = sc(NR_FCNTL, fd, F_GETFD)
        if r < 0:
            failed(r)
    for fd in keep:
        fl = sc(NR_FCNTL, fd, F_GETFD)
        if fl < 0:
            failed(fl)
        r = sc(NR_FCNTL, fd, F_SETFD, fl & ~FD_CLOEXEC)
        if r < 0:
            failed(r)
    soft = resource.getrlimit(resource.RLIMIT_NOFILE)[0]
    lo = 3
    for fd in keep:
        if fd > lo:
            os.closerange(lo, fd)
        lo = fd + 1
    os.closerange(lo, max(lo, soft))
    ctypes.set_errno(0)
    libc.execve(argv[0], cstrs(argv), cstrs(envp))
    failed(-ctypes.get_errno())


def prepare(s):
    """The descriptors of the fixture's launch mode, built here with Python's own calls."""
    os.closerange(3, 65)
    os.dup2(1, 7, inheritable=False)
    f = os.open("/dev/null", os.O_RDONLY | O_CLOEXEC)
    if f != 9:
        os.dup2(f, 9, inheritable=True)
        os.close(f)
    else:
        os.set_inheritable(9, True)
    if s == 3:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        if hard != resource.RLIM_INFINITY and hard < 2200:
            os._exit(77)
        resource.setrlimit(resource.RLIMIT_NOFILE, (hard, hard))
        for fd in range(1000, 2100):
            os.dup2(1, fd, inheritable=False)


def blobs(raw):
    res = []
    p = 0
    for _ in range(3):
        if p + 8 > len(raw):
            die(2, "ORACLE INVALID: packet stream truncated")
        n = int.from_bytes(raw[p:p + 8], "little")
        p += 8
        if p + n > len(raw):
            die(2, "ORACLE INVALID: packet truncated")
        res.append(raw[p:p + n])
        p += n
    if p != len(raw):
        die(2, "ORACLE INVALID: trailing bytes after the three packets")
    return res


def cmd_execfds(s, binpath):
    s = int(s)
    if s < 1 or s > 6:
        die(2, "scenario 1..6")
    p = subprocess.run([binpath, "packets", str(s)], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0 or p.stderr:
        die(2, "ORACLE INVALID: %s packets %d exited %d stderr %r" % (binpath, s, p.returncode, p.stderr[:200]))
    a, e, k = blobs(p.stdout)
    pid = os.fork()
    if pid == 0:
        try:
            prepare(s)
            launch(a, e, k)
        except BaseException as x:
            os.write(2, ("oracle child error %r\n" % (x,)).encode())
            os._exit(120)
        os._exit(121)
    _, st = os.waitpid(pid, 0)
    if os.WIFEXITED(st):
        sys.exit(os.WEXITSTATUS(st))
    sys.exit(128 + os.WTERMSIG(st))


def pk(*recs):
    b = bytearray([len(recs) & 255, len(recs) >> 8])
    for r in recs:
        b += bytes([len(r) & 255, len(r) >> 8]) + r
    return bytes(b)


def kl(*fds):
    return b"".join(f.to_bytes(4, "little") for f in fds)


def cmd_selftest():
    good = [("argv one", lambda: packet(pk(b"/bin/true"), False)),
            ("argv empty later record", lambda: packet(pk(b"/x", b""), False)),
            ("env one", lambda: packet(pk(b"A=1"), True)),
            ("env duplicate", lambda: packet(pk(b"A=1", b"A=1"), True)),
            ("keep empty", lambda: keeplist(b"")),
            ("keep 3", lambda: keeplist(kl(3))),
            ("keep 2147483647", lambda: keeplist(kl(2147483647))),
            ("keep 3,7,9", lambda: keeplist(kl(3, 7, 9)))]
    bad = [("argv count 0", lambda: packet(b"\0\0", False)),
           ("argv 1 byte", lambda: packet(b"\1", False)),
           ("argv first empty", lambda: packet(pk(b""), False)),
           ("argv trailing", lambda: packet(pk(b"/x") + b"\0", False)),
           ("argv truncated", lambda: packet(pk(b"/xy")[:-1], False)),
           ("argv nul", lambda: packet(pk(b"/x\0y"), False)),
           ("env count 0", lambda: packet(b"\0\0", True)),
           ("env empty second", lambda: packet(pk(b"A=1", b""), True)),
           ("env nul", lambda: packet(pk(b"A\x001"), True)),
           ("keep len 2", lambda: keeplist(b"\7\0")),
           ("keep len 5", lambda: keeplist(kl(7) + b"\0")),
           ("keep unsorted", lambda: keeplist(kl(9, 7))),
           ("keep duplicate", lambda: keeplist(kl(7, 7))),
           ("keep 2", lambda: keeplist(kl(2))),
           ("keep 0", lambda: keeplist(kl(0))),
           ("keep 2147483648", lambda: keeplist(kl(2147483648)))]
    bad_count = 0
    for name, f in good:
        try:
            f()
            print("PASS accept %s" % name)
        except Trap as t:
            print("FAIL accept %s: %s" % (name, t))
            bad_count += 1
    for name, f in bad:
        try:
            f()
            print("FAIL refuse %s: accepted" % name)
            bad_count += 1
        except Trap:
            print("PASS refuse %s" % name)
    print("ORACLE SELFTEST %s accepted=%d refused=%d failures=%d" %
          ("PASS" if bad_count == 0 else "FAIL", len(good), len(bad), bad_count))
    sys.exit(1 if bad_count else 0)


LINE = re.compile(r"^(?:\[pid\s+)?(\d+\]?\s+)?(\w+)\((.*)\)\s+=\s+(-?\w+)")
ALLONES = ("4294967295", "~0", "-1", "0xffffffff", "UINT_MAX")


def cmd_order(trace, binpath):
    try:
        lines = open(trace).read().splitlines()
    except OSError as e:
        die(2, "cannot read %s: %s" % (trace, e))
    ev = []
    for ln in lines:
        m = LINE.match(ln)
        if m:
            ev.append((m.group(2), m.group(3), m.group(4)))
    first = [i for i, e in enumerate(ev) if e[0] == "execve" and '"order"' in e[1] and binpath in e[1]]
    second = [i for i, e in enumerate(ev) if e[0] == "execve" and '"child", "7"' in e[1] and binpath in e[1]]
    problems = []
    if len(first) != 1 or len(second) != 1 or second[0] <= first[0]:
        print("ORDER FAIL execve pair not found exactly once (order %d, child %d)" % (len(first), len(second)))
        sys.exit(1)
    w = ev[first[0] + 1:second[0] + 1]
    for i, e in enumerate(w):
        print("ORDER %d %s(%s) = %s" % (i, e[0], e[1], e[2]))
    un = [i for i, e in enumerate(w) if e[0] == "unshare"]
    if len(un) != 1 or w[un[0]][1].strip() != "CLONE_FILES" or w[un[0]][2] != "0":
        problems.append("exactly one unshare(CLONE_FILES) = 0 expected")
    getfd = [i for i, e in enumerate(w) if e[0] == "fcntl" and re.fullmatch(r"7,\s*F_GETFD", e[1].strip())]
    setfd = [i for i, e in enumerate(w) if e[0] == "fcntl" and re.match(r"7,\s*F_SETFD", e[1].strip())]
    others = [e for e in w if e[0] == "fcntl" and not re.match(r"7,", e[1].strip())]
    if others:
        problems.append("fcntl on a descriptor other than 7")
    if len(getfd) != 2:
        problems.append("two fcntl(7, F_GETFD) expected (check loop, then clear loop), got %d" % len(getfd))
    if len(setfd) != 1:
        problems.append("one fcntl(7, F_SETFD, 0) expected, got %d F_SETFD" % len(setfd))
    elif not re.fullmatch(r"7,\s*F_SETFD,\s*0", w[setfd[0]][1].strip()):
        problems.append("F_SETFD must clear every flag of 7: %s" % w[setfd[0]][1])
    if un and getfd and getfd[0] < un[0]:
        problems.append("fcntl before unshare")
    if getfd and setfd and setfd[0] < getfd[-1]:
        problems.append("F_SETFD before the second F_GETFD")
    cr = [(i, e) for i, e in enumerate(w) if e[0] == "close_range"]
    spans = []
    for i, e in cr:
        a = [x.strip() for x in e[1].split(",")]
        if len(a) != 3 or e[2] != "0":
            problems.append("close_range(%s) = %s" % (e[1], e[2]))
            continue
        lo = int(a[0])
        hi = 4294967295 if a[1] in ALLONES else int(a[1])
        if a[2] != "0":
            problems.append("close_range flags %s" % a[2])
        if setfd and i < setfd[0]:
            problems.append("close_range before F_SETFD")
        if lo <= 7 <= hi:
            problems.append("close_range %d..%d covers the kept 7" % (lo, hi))
        spans.append((lo, hi))
    if sorted(spans) != [(3, 6), (8, 4294967295)]:
        problems.append("close_range spans %r, expected [(3, 6), (8, 4294967295)]" % sorted(spans))
    if w[-1][0] != "execve" or w[-1][2] != "0":
        problems.append("execve must be last and succeed")
    for p in problems:
        print("ORDER PROBLEM %s" % p)
    print("ORDER %s events=%d problems=%d" % ("PASS" if not problems else "FAIL", len(w), len(problems)))
    sys.exit(1 if problems else 0)


MEM = ("mmap", "munmap", "mremap", "brk")


def cmd_memtrace(kind, trace, binpath, nm):
    """Decode memory against the actual packet bytes. A malformed or lying packet may cost only the reading of
    its bytes: no mmap, mremap or brk at all after the program starts. A valid packet's mappings are bounded by
    the documented decode size, strings n plus pointers 4n + 16 per packet, rounded up to a page per mapping."""
    try:
        lines = open(trace).read().splitlines()
    except OSError as e:
        die(2, "cannot read %s: %s" % (trace, e))
    ev = []
    for ln in lines:
        m = LINE.match(ln)
        if m:
            ev.append((m.group(2), m.group(3), m.group(4)))
    st = [i for i, e in enumerate(ev) if e[0] == "execve" and binpath in e[1] and ('"%s"' % kind) in e[1]]
    if len(st) != 1:
        print("MEMORY FAIL %s: the program's execve not found exactly once" % kind)
        sys.exit(1)
    w = [e for e in ev[st[0] + 1:] if e[0] in MEM]
    for e in w:
        print("MEMORY %s %s(%s) = %s" % (kind, e[0], e[1], e[2]))
    problems = []
    if kind in ("malbig", "lying"):
        if w:
            problems.append("%d memory system calls for a packet that must trap on its framing" % len(w))
    elif kind == "bigok":
        n, m, k = nm
        maps = [e for e in w if e[0] == "mmap"]
        if any(e[0] in ("mremap", "brk") for e in w):
            problems.append("mremap or brk during the decode")
        if not maps:
            problems.append("no decode mapping seen: the observer would not see one (control)")
        total = 0
        for e in maps:
            a = [x.strip() for x in e[1].split(",")]
            try:
                total += int(a[1], 0)
            except (IndexError, ValueError):
                problems.append("unparsed mmap(%s)" % e[1])
        bound = 5 * (n + m) + 65 + k + os.sysconf("SC_PAGE_SIZE") * len(maps)
        print("MEMORY bigok argv=%d env=%d keep=%d mappings=%d total=%d bound=%d" % (n, m, k, len(maps), total, bound))
        if total > bound:
            problems.append("decode mapped %d bytes, above 5(n+m)+65+k plus a page per mapping (%d)" % (total, bound))
    else:
        die(2, "memtrace kind malbig|lying|bigok")
    for p in problems:
        print("MEMORY PROBLEM %s" % p)
    print("MEMORY %s %s calls=%d problems=%d" % (kind, "PASS" if not problems else "FAIL", len(w), len(problems)))
    sys.exit(1 if problems else 0)


def cmd_subst(frm, to, src, outp):
    a = open(frm, "rb").read()
    b = open(to, "rb").read()
    s = open(src, "rb").read()
    n = s.count(a)
    if n != 1 or not a:
        die(2, "subst: %s occurs %d times in %s (exactly once required)" % (frm, n, src))
    open(outp, "wb").write(s.replace(a, b))


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "execfds" and len(sys.argv) == 4:
        cmd_execfds(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 2 and sys.argv[1] == "selftest":
        cmd_selftest()
    elif len(sys.argv) == 4 and sys.argv[1] == "order":
        cmd_order(sys.argv[2], sys.argv[3])
    elif len(sys.argv) in (5, 8) and sys.argv[1] == "memtrace":
        nm = tuple(int(s) for s in sys.argv[5:]) if len(sys.argv) == 8 else (0, 0, 0)
        if (sys.argv[2] == "bigok") != (len(sys.argv) == 8):
            die(2, "memtrace bigok needs N M K; malbig and lying take none")
        cmd_memtrace(sys.argv[2], sys.argv[3], sys.argv[4], nm)
    elif len(sys.argv) == 6 and sys.argv[1] == "subst":
        cmd_subst(*sys.argv[2:])
    else:
        die(2, "usage: oracle.py execfds S BIN | selftest | order TRACE BIN | memtrace KIND TRACE BIN [N M K] | "
               "subst FROM TO SRC OUT")


main()
