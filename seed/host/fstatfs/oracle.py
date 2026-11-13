#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# seed/host/fstatfs/oracle.py: ORACLE and TEST INSTRUMENT only (Python 3, ctypes). It is never built, linked,
# shipped or placed on a product path; seed/host/fstatfs/check.sh runs it beside the seeded fixture.
#   oracle.py layout          struct statfs derived from the kernel headers (field order and types, the size of
#                             C long from this ABI) and the size the kernel actually writes, measured with two
#                             sentinel fills around a raw fstatfs system call; both must agree
#   oracle.py selftest        the comparison itself must refuse a changed stable field, a short dump and a
#                             changed count under exact comparison, and accept a changed free count only
#                             where counts are declared volatile
#   oracle.py compare KIND BIN   KIND pipe | memfd | root | cgroup: BIN "dump" (fstatfs of its stdin) against
#                             raw fstatfs on the same descriptor before and after it, plus os.fstatvfs (the C
#                             library) and the filesystem magic from linux/magic.h or coreutils stat -f
#   oracle.py tmpfs BIN       as root (sudo -n): a private mount namespace with a tmpfs of size=1m,nr_inodes=64;
#                             nothing writes there, so all 120 bytes must be equal
# Exact comparison (pipe, memfd, tmpfs): every byte equal. Volatile comparison (root, cgroup: shared
# filesystems that other processes change): every field except f_bfree, f_bavail and f_ffree equal; those
# three are printed as before/native/after snapshots and never claimed equal.
# Failures are explicit exits with a message; nothing relies on assert.
import ctypes
import os
import re
import subprocess
import sys
import tempfile

HDR = "/usr/include"
VOLATILE = ("f_bfree", "f_bavail", "f_ffree")


def die(code, msg):
    sys.stderr.write("oracle.py: %s\n" % msg)
    sys.exit(code)


def text(path):
    try:
        return open(os.path.join(HDR, path)).read()
    except OSError as e:
        die(2, "ORACLE INVALID: cannot read %s: %s" % (path, e))


def define(path, name, seen=()):
    m = re.search(r"^#define\s+%s\s+(\S+)" % re.escape(name), text(path), re.M)
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


def arch_statfs_header():
    """The architecture header must take the generic struct unchanged."""
    for d in ("aarch64-linux-gnu/asm/statfs.h", "asm/statfs.h"):
        if os.path.exists(os.path.join(HDR, d)):
            t = text(d)
            if "#include <asm-generic/statfs.h>" not in t:
                die(2, "ORACLE INVALID: %s does not include asm-generic/statfs.h" % d)
            if re.search(r"^#define\s+__statfs_word", t, re.M):
                die(2, "ORACLE INVALID: %s overrides __statfs_word" % d)
            return d
    die(2, "ORACLE INVALID: no architecture statfs.h")


def layout():
    """[(name, offset, size, kind, count)] and total size of struct statfs from asm-generic/statfs.h."""
    arch = arch_statfs_header()
    g = text("asm-generic/statfs.h")
    if not re.search(r"#if __BITS_PER_LONG == 64\s*\n#define __statfs_word __kernel_long_t", g):
        die(2, "ORACLE INVALID: __statfs_word rule not found in asm-generic/statfs.h")
    pt = text("asm-generic/posix_types.h")
    if not re.search(r"typedef\s+long\s+__kernel_long_t;", pt):
        die(2, "ORACLE INVALID: __kernel_long_t is not long")
    m = re.search(r"typedef\s+struct\s*\{\s*int\s+val\[(\d+)\];\s*\}\s*__kernel_fsid_t;", pt)
    if not m:
        die(2, "ORACLE INVALID: __kernel_fsid_t not found")
    fsid_n = int(m.group(1))
    lsize = ctypes.sizeof(ctypes.c_long)
    word = lsize if 8 * lsize == 64 else 4
    isize = ctypes.sizeof(ctypes.c_int)
    body = re.search(r"struct statfs \{(.*?)\};", g, re.S)
    if not body:
        die(2, "ORACLE INVALID: struct statfs not found")
    fields = []
    off = 0
    maxal = 1
    for ln in body.group(1).splitlines():
        ln = ln.strip()
        if not ln:
            continue
        fm = re.fullmatch(r"(\w+)\s+(\w+)(?:\[(\d+)\])?;", ln)
        if not fm:
            die(2, "ORACLE INVALID: unparsed field line %r" % ln)
        typ, name, cnt = fm.group(1), fm.group(2), int(fm.group(3) or 1)
        if typ == "__statfs_word":
            size, al, kind = word, word, "long"
        elif typ == "__kernel_fsid_t":
            size, al, kind = isize * fsid_n, isize, "fsid"
        else:
            die(2, "ORACLE INVALID: unknown field type %s" % typ)
        off = (off + al - 1) // al * al
        fields.append((name, off, size, kind, cnt))
        off += size * cnt
        maxal = max(maxal, al)
    total = (off + maxal - 1) // maxal * maxal
    return arch, fields, total, isize


NR_FSTATFS = define("asm-generic/unistd.h", "__NR_fstatfs")
libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long


def raw(fd, fill=0xA5, cap=512):
    buf = (ctypes.c_ubyte * cap)(*([fill] * cap))
    ctypes.set_errno(0)
    r = libc.syscall(ctypes.c_long(NR_FSTATFS), ctypes.c_long(fd), ctypes.c_void_p(ctypes.addressof(buf)))
    if r != 0:
        die(2, "ORACLE INVALID: raw fstatfs(%d) = %d errno %d" % (fd, r, ctypes.get_errno()))
    return bytes(buf)


def extent(fd):
    a = raw(fd, 0xA5)
    b = raw(fd, 0x5A)
    last = 0
    for p in range(len(a)):
        if not (a[p] == 0xA5 and b[p] == 0x5A):
            last = p + 1
    return last


def decode(b, fields, isize):
    d = {}
    for name, off, size, kind, cnt in fields:
        vals = []
        for i in range(cnt):
            o = off + i * size
            if kind == "fsid":
                vals.append(tuple(int.from_bytes(b[o + j * isize:o + (j + 1) * isize], "little", signed=True)
                                  for j in range(size // isize)))
            else:
                vals.append(int.from_bytes(b[o:o + size], "little", signed=True))
        d[name] = vals[0] if cnt == 1 else tuple(vals)
    return d


def compare(cls, native, before, after, fields, total, isize):
    """Problems of one comparison; cls is 'exact' or 'volatile'."""
    p = []
    for nm, b in (("native", native), ("oracle before", before), ("oracle after", after)):
        if len(b) != total:
            p.append("%s has %d bytes, the struct has %d" % (nm, len(b), total))
    if p:
        return p
    if cls == "exact":
        if not (native == before == after):
            dn, db, da = (decode(x, fields, isize) for x in (native, before, after))
            for name, _, _, _, _ in fields:
                if not (dn[name] == db[name] == da[name]):
                    p.append("%s native %s before %s after %s" % (name, dn[name], db[name], da[name]))
            if not p:
                p.append("bytes differ outside every field")
        return p
    dn, db, da = (decode(x, fields, isize) for x in (native, before, after))
    for name, _, _, _, _ in fields:
        if name in VOLATILE:
            continue
        if not (dn[name] == db[name] == da[name]):
            p.append("stable field %s native %s before %s after %s" % (name, dn[name], db[name], da[name]))
    return p


def magic(kind):
    if kind == "pipe":
        return define("linux/magic.h", "PIPEFS_MAGIC")
    if kind in ("memfd", "tmpfs"):
        return define("linux/magic.h", "TMPFS_MAGIC")
    if kind == "cgroup":
        return define("linux/magic.h", "CGROUP2_SUPER_MAGIC")
    if kind == "root":
        s = subprocess.run(["stat", "-f", "-c", "%t", "/"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if s.returncode != 0:
            die(2, "ORACLE INVALID: stat -f / exited %d" % s.returncode)
        return int(s.stdout.decode().strip(), 16)
    die(2, "unknown kind %s" % kind)


def opentarget(kind):
    if kind == "pipe":
        r, w = os.pipe2(os.O_CLOEXEC)
        return r, [w]
    if kind == "memfd":
        return os.memfd_create("fstatfs-oracle", os.MFD_CLOEXEC), []
    if kind == "root":
        return os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC), []
    if kind == "cgroup":
        return os.open("/sys/fs/cgroup", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC), []
    die(2, "kind pipe|memfd|root|cgroup")


def run_compare(kind, binpath, fd, extra):
    arch, fields, total, isize = layout()
    cls = "volatile" if kind in ("root", "cgroup") else "exact"
    before = raw(fd)[:total]
    p = subprocess.run([binpath, "dump"], stdin=fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    after = raw(fd)[:total]
    problems = []
    if p.returncode != 0 or p.stderr:
        problems.append("native dump exit %d stderr %r" % (p.returncode, p.stderr[:200]))
    problems += compare(cls, p.stdout, before, after, fields, total, isize)
    d = decode(before, fields, isize) if len(before) == total else {}
    if d:
        want = magic(kind)
        if d["f_type"] != want:
            problems.append("f_type %#x, expected %#x" % (d["f_type"], want))
        v = os.fstatvfs(fd)
        for a, b in (("f_bsize", v.f_bsize), ("f_frsize", v.f_frsize), ("f_blocks", v.f_blocks),
                     ("f_files", v.f_files), ("f_namelen", v.f_namemax)):
            if d[a] != b:
                problems.append("%s %d, C library statvfs %d" % (a, d[a], b))
        if any(d["f_spare"]):
            problems.append("f_spare not zero: %r" % (d["f_spare"],))
        for name, _, _, _, _ in fields:
            print("FIELD %s %s %s" % (kind, name, d[name]))
    if cls == "volatile" and d and len(p.stdout) == total:
        dn = decode(p.stdout, fields, isize)
        da = decode(after, fields, isize)
        for name in VOLATILE:
            print("VOLATILE %s %s before=%d native=%d after=%d (snapshots of a shared filesystem, not compared)"
                  % (kind, name, d[name], dn[name], da[name]))
    for x in extra(d):
        problems.append(x)
    for x in problems:
        print("PROBLEM %s %s" % (kind, x))
    print("COMPARE %s %s %s problems=%d" % (kind, cls, "PASS" if not problems else "FAIL", len(problems)))
    return 1 if problems else 0


def cmd_layout():
    arch, fields, total, isize = layout()
    for name, off, size, kind, cnt in fields:
        print("FIELD %s offset=%d size=%d count=%d %s" % (name, off, size, cnt, kind))
    r, w = os.pipe2(os.O_CLOEXEC)
    ext = extent(r)
    os.close(r)
    os.close(w)
    ok = ext == total
    print("LAYOUT %s size=%d measured=%d (headers asm-generic/statfs.h via %s, sizeof(long)=%d)"
          % ("PASS" if ok else "FAIL", total, ext, arch, ctypes.sizeof(ctypes.c_long)))
    sys.exit(0 if ok else 1)


def cmd_selftest():
    arch, fields, total, isize = layout()
    r, w = os.pipe2(os.O_CLOEXEC)
    base = raw(r)[:total]
    os.close(r)
    os.close(w)
    off = {f[0]: f[1] for f in fields}

    def flip(b, name):
        x = bytearray(b)
        x[off[name]] ^= 1
        return bytes(x)
    cases = [("identical exact", "exact", base, True),
             ("identical volatile", "volatile", base, True),
             ("f_type changed, volatile class", "volatile", flip(base, "f_type"), False),
             ("f_blocks changed, volatile class", "volatile", flip(base, "f_blocks"), False),
             ("f_fsid changed, volatile class", "volatile", flip(base, "f_fsid"), False),
             ("f_bfree changed, volatile class", "volatile", flip(base, "f_bfree"), True),
             ("f_bfree changed, exact class", "exact", flip(base, "f_bfree"), False),
             ("119-byte dump", "exact", base[:-1], False),
             ("121-byte dump", "exact", base + b"\0", False)]
    bad = 0
    for name, cls, nat, accept in cases:
        got = not compare(cls, nat, base, base, fields, total, isize)
        ok = got == accept
        bad += 0 if ok else 1
        print("%s %s: %s" % ("PASS" if ok else "FAIL", name, "accepted" if got else "refused"))
    print("COMPARATOR SELFTEST %s cases=%d failures=%d" % ("PASS" if not bad else "FAIL", len(cases), bad))
    sys.exit(1 if bad else 0)


def cmd_compare(kind, binpath):
    fd, keep = opentarget(kind)
    rc = run_compare(kind, binpath, fd, lambda d: [])
    sys.exit(rc)


def cmd_tmpfs(binpath):
    if os.geteuid() != 0:
        die(3, "NOT_RUN tmpfs: needs root (run through sudo -n)")
    unshare = getattr(os, "unshare", None)
    flags = define("linux/sched.h", "CLONE_NEWNS")
    if unshare is not None:
        unshare(flags)
    else:
        nr = define("asm-generic/unistd.h", "__NR_unshare")
        if libc.syscall(ctypes.c_long(nr), ctypes.c_long(flags)) != 0:
            die(2, "ORACLE INVALID: unshare(CLONE_NEWNS) errno %d" % ctypes.get_errno())
    libc.mount.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_ulong, ctypes.c_char_p]
    ms_rec = define("linux/mount.h", "MS_REC")
    ms_private = define("linux/mount.h", "MS_PRIVATE")
    if libc.mount(None, b"/", None, ms_rec | ms_private, None) != 0:
        die(2, "ORACLE INVALID: make / private errno %d" % ctypes.get_errno())
    d = tempfile.mkdtemp(prefix="fstatfs-oracle-")
    size = 1 << 20
    inodes = 64
    opts = ("size=%d,nr_inodes=%d,mode=0700" % (size, inodes)).encode()
    fl = define("linux/mount.h", "MS_NOSUID") | define("linux/mount.h", "MS_NODEV") | define("linux/mount.h", "MS_NOEXEC")
    if libc.mount(b"fstatfs-oracle", d.encode(), b"tmpfs", fl, opts) != 0:
        os.rmdir(d)
        die(2, "ORACLE INVALID: mount tmpfs errno %d" % ctypes.get_errno())
    fd = os.open(d, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)

    def extra(dd):
        p = []
        if dd and dd["f_blocks"] * dd["f_bsize"] != size:
            p.append("f_blocks*f_bsize %d, mounted size %d" % (dd["f_blocks"] * dd["f_bsize"], size))
        if dd and dd["f_files"] != inodes:
            p.append("f_files %d, mounted nr_inodes %d" % (dd["f_files"], inodes))
        return p
    rc = run_compare("tmpfs", binpath, fd, extra)
    os.close(fd)
    libc.umount2.argtypes = [ctypes.c_char_p, ctypes.c_int]
    libc.umount2(d.encode(), 0)
    os.rmdir(d)
    sys.exit(rc)


def main():
    a = sys.argv[1:]
    if a == ["layout"]:
        cmd_layout()
    elif a == ["selftest"]:
        cmd_selftest()
    elif len(a) == 3 and a[0] == "compare":
        cmd_compare(a[1], a[2])
    elif len(a) == 2 and a[0] == "tmpfs":
        cmd_tmpfs(a[1])
    else:
        die(2, "usage: oracle.py layout | selftest | compare pipe|memfd|root|cgroup BIN | tmpfs BIN")


main()
