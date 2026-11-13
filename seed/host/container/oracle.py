# SPDX-License-Identifier: Apache-2.0
# seed/host/container/oracle.py: ORACLE (test instrument, never on the product path). It performs the same
# Linux AArch64 system calls as container.om through Python ctypes (libc syscall(2)) and prints the same
# "name value" lines, so check.sh can compare the two outputs byte for byte. Lines that come from the written
# contract instead of the kernel: prctl-op2-refused (prctl admits ops 1, 23, 24, 36, 38 and 39 and returns -22 for
# any other op without a kernel call) and capget-n31 (capget/capset take exactly 32 bytes, else -22 without a call).
# Fail closed: every setup step that later steps depend on (namespace unshare, private propagation, the scratch
# tmpfs, the new directory and its bind, the detached tree and its target) must succeed, otherwise the oracle
# prints "ABORT <step> <result>" and exits 2 before any dependent call.
# Recorder: with OBOX_ORACLE_FAIL=<step> no system call is made at all. Every call is recorded and returns 0
# except the named step, which returns -1; the fork test and the /proc reads are simulated so the recorder follows
# the real continuation to the end (OBOX_ORACLE_FAIL=none fails nothing). On exit the recorded call list is
# printed on stderr ("CALLS name,name,...").
import ctypes, os, sys

libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long
SYS = dict(unshare=97, mount=40, umount2=39, pivot_root=41, sethostname=161, prctl=167, capget=90, capset=91,
           open_tree=428, mount_setattr=442, move_mount=429, openat=56, close=57,
           rt_sigprocmask=135, rt_sigtimedwait=137, mkdirat=34, chdir=49, newfstatat=79, kill=129, getpid=172)
AT_FDCWD = -100
INJECT = os.environ.get("OBOX_ORACLE_FAIL", "")
calls = []
out = []

def sc(name, *args, step=""):
    if INJECT:
        calls.append(step or name)
        return -1 if (step or name) == INJECT else 0
    conv = [ctypes.c_long(a) if isinstance(a, int) else a for a in args]
    r = libc.syscall(SYS[name], *conv)
    return -ctypes.get_errno() if r == -1 else r

def line(n, v):
    out.append("%s %d\n" % (n, v))

def b(s):
    return ctypes.c_char_p(s.encode())

def stat(p, step):
    buf = ctypes.create_string_buffer(128)
    return sc("newfstatat", AT_FDCWD, b(p), buf, 0, step=step)

def prctl(op, arg, step):
    if op not in (1, 23, 24, 36, 38, 39):
        return -22
    return sc("prctl", op, arg, 0, 0, 0, step=step)

def status_has(t):
    return True if INJECT else t in open("/proc/self/status").read()

def done(code):
    sys.stdout.write("".join(out)); sys.stdout.flush()
    if INJECT:
        sys.stderr.write("CALLS %s\n" % ",".join(calls)); sys.stderr.flush()
    os._exit(code)

def need(step, ok):
    if not ok:
        out.append("ABORT %s\n" % step)
        done(2)

def lp(n):
    return "".join("/" if i % 2 == 0 else "a" for i in range(n))

def longpaths():
    p = lp(4095)
    line("mount-long-paths", sc("mount", b(p), b(p), b("none"), 0, None, step="mount-long-paths"))
    line("mount-path-4096", sc("mount", b(lp(2)), b(lp(4096)), b("none"), 0, None, step="mount-path-4096"))
    line("pivroot-long-paths", sc("pivot_root", b(p), b(p), step="pivroot-long-paths"))

def capbuf():
    buf = ctypes.create_string_buffer(32)
    buf[0:4] = (0x20080522).to_bytes(4, "little")
    return buf

def u32(buf, i):
    return int.from_bytes(buf.raw[i:i + 4], "little")

def capsread():
    buf = capbuf()
    a = ctypes.addressof(buf)
    line("capget", sc("capget", a, a + 8, step="capget"))
    line("capget-eff-lo", u32(buf, 8))
    line("capget-eff-hi", u32(buf, 20))
    line("capget-prm-lo", u32(buf, 12))
    line("capget-inh-lo", u32(buf, 16))
    line("capget-n31", -22)
    line("capbset-read-0", prctl(23, 0, "capbset-read-0") if not INJECT else 1)
    line("capbset-read-4096", prctl(23, 4096, "capbset-read-4096") if not INJECT else -22)
    line("get-nnp", prctl(39, 0, "get-nnp"))

def capsdrop():
    buf = capbuf()
    a = ctypes.addressof(buf)
    buf[8:12] = (0x4fb).to_bytes(4, "little"); buf[12:16] = (0x4fb).to_bytes(4, "little")
    line("capset-4fb", sc("capset", a, a + 8, step="capset-4fb"))
    buf = capbuf(); a = ctypes.addressof(buf)
    sc("capget", a, a + 8, step="capget-after")
    line("capget-eff-lo", u32(buf, 8))
    line("capget-prm-lo", u32(buf, 12))
    buf = capbuf(); a = ctypes.addressof(buf)
    buf[8:12] = (0xffffffff).to_bytes(4, "little"); buf[12:16] = (0xffffffff).to_bytes(4, "little")
    line("capset-raise", sc("capset", a, a + 8, step="capset-raise") if not INJECT else -1)

def newapi(d):
    fd = sc("open_tree", AT_FDCWD, b(d + "/new"), 524289, step="opentree")
    line("opentree-ok", 1 if fd >= 0 else 0)
    need("opentree", fd >= 0)
    line("opentree-missing", sc("open_tree", AT_FDCWD, b(d + "/missing/x"), 524289, step="opentree-missing") if not INJECT else -2)
    attr = ctypes.create_string_buffer(32)
    attr[0] = 1
    r = sc("mount_setattr", fd, b(""), 4096, attr, 32, step="mntattr-ro")
    line("mntattr-ro", r)
    need("mntattr-ro", r == 0)
    line("mntattr-size8", sc("mount_setattr", fd, b(""), 4096, attr, 8, step="mntattr-size8") if not INJECT else -22)
    sc("mkdirat", AT_FDCWD, b(d + "/tgt"), 0o755, step="makedir-tgt")
    t = sc("openat", AT_FDCWD, b(d + "/tgt"), 2637824, 0, step="tgt-open")
    line("tgt-open-ok", 1 if t >= 0 else 0)
    need("tgt-open", t >= 0)
    r = sc("move_mount", fd, b(""), t, b(""), 68, step="mntmove")
    line("mntmove", r)
    need("mntmove", r == 0)
    line("mntmove-badfd", sc("move_mount", -1, b(""), t, b(""), 68, step="mntmove-badfd") if not INJECT else -9)
    line("write-tgt", sc("openat", AT_FDCWD, b(d + "/tgt/w"), 577, 0o644, step="write-tgt") if not INJECT else -30)
    w = sc("openat", AT_FDCWD, b(d + "/new/w"), 577, 0o644, step="write-new")
    line("write-new-ok", 1 if w >= 0 else 0)

def pdeathsig():
    if INJECT:
        calls.append("fork-pdeathsig")
        line("pdeathsig-parent-exit", 0)
        line("pdeathsig-grandchild-signal", 9)
        return
    r, w = os.pipe()
    c = os.fork()
    if c == 0:
        g = os.fork()
        if g == 0:
            prctl(1, 9, "pdeathsig")
            os.write(w, b"x")
            import time; time.sleep(10)
            os._exit(9)
        os.read(r, 1)
        os._exit(0)
    _, st = os.waitpid(c, 0)
    line("pdeathsig-parent-exit", st >> 8)
    _, st = os.waitpid(-1, 0)
    line("pdeathsig-grandchild-signal", st & 127)

def sigs():
    ss = ctypes.create_string_buffer(b"\x00\x02" + b"\x00" * 6, 8)
    line("sigmask-block-usr1", sc("rt_sigprocmask", 0, ss, None, 8, step="sigmask-block-usr1"))
    need("sigblk", status_has("SigBlk:\t0000000000000200\n"))
    line("sigmask-size4", sc("rt_sigprocmask", 0, ss, None, 4, step="sigmask-size4") if not INJECT else -22)
    sc("kill", sc("getpid", step="getpid") if not INJECT else 0, 10, step="kill-self")
    line("sigwait", sc("rt_sigtimedwait", ss, None, None, 8, step="sigwait") if not INJECT else 10)
    line("sigwait-size4", sc("rt_sigtimedwait", ss, None, None, 4, step="sigwait-size4") if not INJECT else -22)

def root(d):
    line("unshare-bad-flag", sc("unshare", 1, step="unshare-bad-flag") if not INJECT else -22)
    r = sc("unshare", 0x20000 | 0x4000000, step="unshare")
    line("unshare-ns-uts", r)
    need("unshare", r == 0)
    line("sethost", sc("sethostname", b("obox-gate"), 9, step="sethost"))
    line("hostname-bytes", 10 if INJECT else len(open("/proc/sys/kernel/hostname", "rb").read()))
    line("sethost-65", sc("sethostname", b("a" * 65), 65, step="sethost-65") if not INJECT else -22)
    capsread()
    r = sc("mount", b("none"), b("/"), b("none"), 0x4000 | 0x40000, None, step="private")
    line("mount-private", r)
    need("private", r == 0)
    r = sc("mount", b("tmpfs"), b(d), b("tmpfs"), 0, b("size=1m,mode=755"), step="tmpfs")
    line("mount-tmpfs", r)
    need("tmpfs", r == 0)
    line("mount-missing", sc("mount", b("tmpfs"), b(d + "/missing/x"), b("tmpfs"), 0, None, step="mount-missing") if not INJECT else -2)
    r = sc("mkdirat", AT_FDCWD, b(d + "/new"), 0o755, step="makedir-new")
    line("makedir-new", r)
    need("makedir-new", r == 0)
    r = sc("mount", b(d + "/new"), b(d + "/new"), b("none"), 4096, None, step="mount-bind")
    line("mount-bind", r)
    need("mount-bind", r == 0)
    newapi(d)
    line("prctl-op2-refused", prctl(2, 0, "prctl-op2"))
    line("prctl-subreaper", prctl(36, 1, "prctl-subreaper"))
    pdeathsig()
    line("prctl-nonewprivs", prctl(38, 1, "prctl-nonewprivs"))
    line("get-nnp", prctl(39, 0, "get-nnp-after") if not INJECT else 1)
    sigs()
    sc("mkdirat", AT_FDCWD, b(d + "/new/old"), 0o755, step="makedir-old")
    sc("chdir", b(d + "/new"), step="chdir-new")
    line("pivroot-missing", sc("pivot_root", b("."), b("/missing/x"), step="pivroot-missing") if not INJECT else -2)
    line("pivroot", sc("pivot_root", b("."), b("old"), step="pivroot"))
    line("stat-old-dir", stat("/old" + d, "stat-old-dir"))
    line("umount-detach", sc("umount2", b("/old"), 2, step="umount-detach"))
    line("stat-after-detach", stat("/old" + d, "stat-after-detach") if not INJECT else -2)
    line("umount-not-mounted", sc("umount2", b("/old"), 0, step="umount-not-mounted") if not INJECT else -22)
    capsdrop()
    done(0)

def user():
    line("unshare-ns-uts", sc("unshare", 0x20000 | 0x4000000))
    line("sethost", sc("sethostname", b("obox-gate"), 9))
    line("mount-private", sc("mount", b("none"), b("/"), b("none"), 0x4000 | 0x40000, None))
    line("umount-root", sc("umount2", b("/"), 2))
    line("pivroot", sc("pivot_root", b("."), b(".")))
    capsread()
    line("prctl-nonewprivs", prctl(38, 1, "prctl-nonewprivs"))
    line("get-nnp", prctl(39, 0, "get-nnp-after"))
    capsdrop()
    ss = ctypes.create_string_buffer(b"\x00\x02" + b"\x00" * 6, 8)
    line("sigmask-block-usr1", sc("rt_sigprocmask", 0, ss, None, 8))
    sc("kill", sc("getpid"), 10)
    line("sigwait", sc("rt_sigtimedwait", ss, None, None, 8))
    longpaths()
    done(0)

if sys.argv[1] == "root":
    root(sys.argv[2])
user()
