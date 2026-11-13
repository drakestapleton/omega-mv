#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# TEST INSTRUMENT only: Linux/AArch64 ptrace control for execfds' keep-list snapshot.
# The fixture's snapshot mode writes the caller's [7] before execfds. Capture that buffer address,
# stop on unshare(CLONE_FILES)'s return, replace caller K with [9], then observe descriptor syscalls
# and /proc/PID/fd at execve entry. The image's own report independently observes survival across exec.
# 0 PASS, 1 semantic mismatch (mutant killed), 2 instrument/launch/protocol failure, 3 NOT_RUN ptrace.
import ctypes
import errno
import os
import platform
import signal
import struct
import sys

libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.restype = ctypes.c_long
TRACEME, SYSCALL, SETOPTIONS, GETREGSET = 0, 24, 0x4200, 0x4204
OPTIONS = 1 | 0x10 | 0x100000  # TRACESYSGOOD | TRACEEXEC | EXITKILL

class Iovec(ctypes.Structure):
    _fields_ = [("base", ctypes.c_void_p), ("length", ctypes.c_size_t)]

def ptrace(request, pid, addr=0, data=0):
    ctypes.set_errno(0)
    r = libc.ptrace(ctypes.c_uint(request), ctypes.c_int(pid), ctypes.c_void_p(addr), ctypes.c_void_p(data))
    if r == -1 and ctypes.get_errno():
        e = ctypes.get_errno()
        raise OSError(e, os.strerror(e))
    return r

def regs(pid):
    a = (ctypes.c_ulonglong * 34)()  # user_pt_regs: x0..x30, sp, pc, pstate
    v = Iovec(ctypes.addressof(a), ctypes.sizeof(a))
    ptrace(GETREGSET, pid, 1, ctypes.addressof(v))  # NT_PRSTATUS
    if v.length != ctypes.sizeof(a):
        raise RuntimeError("unexpected NT_PRSTATUS size %d" % v.length)
    return list(a)

def main():
    if len(sys.argv) != 2:
        raise RuntimeError("usage: snapshot.py COMPILED_FIXTURE")
    if platform.system() != "Linux" or platform.machine() not in ("aarch64", "arm64"):
        print("SNAPSHOT NOT_RUN requires Linux/AArch64 ptrace", flush=True)
        return 3
    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path) or not os.access(path, os.X_OK):
        raise RuntimeError("fixture is absent or not executable: " + path)
    # Child setup errors travel over a CLOEXEC pipe, never masquerade as a killed compiler mutant.
    er, ew = os.pipe2(os.O_CLOEXEC)
    outfd, outpath = __import__("tempfile").mkstemp(prefix="snapshot-", dir=".")
    pid = os.fork()
    if pid == 0:
        os.close(er)
        try:
            ptrace(TRACEME, 0)
        except OSError as e:
            msg = ("NOT_RUN " if e.errno in (errno.EPERM, errno.EACCES, errno.ENOSYS) else "FAIL ") + str(e)
            os.write(ew, msg.encode())
            os._exit(125)
        try:
            os.dup2(outfd, 1)
            os.dup2(outfd, 2)
            os.execv(path, [path, "snapshot"])
        except BaseException as e:
            os.write(ew, ("FAIL launch: " + str(e)).encode())
        os._exit(125)
    os.close(ew)
    alive = True
    try:
        _, st = os.waitpid(pid, 0)
        error = os.read(er, 4096).decode()
        os.close(er)
        if error:
            print("SNAPSHOT " + error, flush=True)
            return 3 if error.startswith("NOT_RUN ") else 2
        if not os.WIFSTOPPED(st) or os.WSTOPSIG(st) != signal.SIGTRAP:
            raise RuntimeError("initial exec stop absent: status %d" % st)
        try:
            ptrace(SETOPTIONS, pid, 0, OPTIONS)
        except OSError as e:
            if e.errno in (errno.EPERM, errno.EACCES, errno.ENOSYS):
                print("SNAPSHOT NOT_RUN ptrace options: " + str(e), flush=True)
                return 3
            raise
        entry, caller, mutated, observed = True, None, False, None
        calls, unshares, execs = [], 0, 0
        pending_signal = 0
        while True:
            ptrace(SYSCALL, pid, 0, pending_signal)
            pending_signal = 0
            _, st = os.waitpid(pid, 0)
            if os.WIFEXITED(st) or os.WIFSIGNALED(st):
                alive = False
                status = os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128 + os.WTERMSIG(st)
                break
            if not os.WIFSTOPPED(st):
                raise RuntimeError("unexpected wait status %d" % st)
            sig, event = os.WSTOPSIG(st), st >> 16
            if event == 4:  # PTRACE_EVENT_EXEC: between entry and exit; no phase toggle
                continue
            if sig != signal.SIGTRAP | 0x80:
                if sig == signal.SIGTRAP:
                    raise RuntimeError("unexpected plain SIGTRAP")
                pending_signal = sig
                continue
            r = regs(pid)
            nr = r[8]
            if entry:
                if nr == 64 and r[0] == 1 and r[2] == 4 and caller is None and not mutated:
                    with open("/proc/%d/mem" % pid, "rb", buffering=0) as f:
                        if os.pread(f.fileno(), 4, r[1]) != struct.pack("<I", 7):
                            raise RuntimeError("fixture marker is not caller K=[7]")
                    caller = r[1]
                    print("SNAPSHOT captured caller K=%#x" % caller, flush=True)
                if nr in (25, 97, 436, 221):
                    calls.append((nr, r[:3]))
                    print("SNAPSHOT syscall %d args=%s" % (nr, r[:3]), flush=True)
                if nr == 221:
                    execs += 1
                    if not mutated:
                        raise RuntimeError("execve reached without unshare mutation")
                    current = {int(s) for s in os.listdir("/proc/%d/fd" % pid)}
                    observed = sorted(current & {7, 9})
                    print("SNAPSHOT observed kept=%s closed=%s before execve" % (observed, sorted({7, 9} - current)), flush=True)
            elif nr == 97:
                unshares += 1
                if mutated or caller is None or r[0] != 0:
                    raise RuntimeError("unshare return lacks captured caller, is repeated, or failed: %d" % r[0])
                with open("/proc/%d/mem" % pid, "r+b", buffering=0) as f:
                    saved = struct.unpack("<Q", os.pread(f.fileno(), 8, r[31] + 64))[0]
                    if os.pread(f.fileno(), 4, saved) != struct.pack("<I", 7):
                        raise RuntimeError("frame keep list was not [7] before mutation")
                    if os.pwrite(f.fileno(), struct.pack("<I", 9), caller) != 4:
                        raise RuntimeError("short rewrite of caller K")
                    if os.pread(f.fileno(), 4, caller) != struct.pack("<I", 9):
                        raise RuntimeError("caller K rewrite did not stick")
                    copied = struct.unpack("<I", os.pread(f.fileno(), 4, saved))[0]
                print("SNAPSHOT rewrote caller [7]->[9] at unshare return; frame K=%#x value=%d" % (saved, copied), flush=True)
                mutated = True
            entry = not entry
        os.lseek(outfd, 0, os.SEEK_SET)
        output = os.read(outfd, 65536)
        print("SNAPSHOT child status=%d output=%r" % (status, output), flush=True)
        if not mutated or unshares != 1 or execs != 1 or observed is None:
            raise RuntimeError("missing unique mutation/unshare/exec observation")
        if status != 0 or not output.startswith(struct.pack("<I", 7)):
            raise RuntimeError("fixture did not report successfully after marker")
        report = output[4:].splitlines()
        getfds = [a[0] for nr, a in calls if nr == 25 and a[1] == 1]
        gaps = [a[:2] for nr, a in calls if nr == 436]
        if observed != [7] or b"fd 7 open" not in report or b"fd 9 closed" not in report or getfds != [7, 7] or gaps != [[3, 6], [8, 4294967295]]:
            print("SNAPSHOT MISMATCH caller mutation changed kept/closed descriptors", flush=True)
            return 1
        print("SNAPSHOT PASS caller mutation did not change kept=[7] closed=[9]", flush=True)
        return 0
    finally:
        if alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass
        os.close(outfd)
        os.unlink(outpath)

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, struct.error) as e:
        print("SNAPSHOT INSTRUMENT FAIL: " + str(e), file=sys.stderr, flush=True)
        sys.exit(2)
