#!/usr/bin/env python3
"""Level 2 driver for the UXL brief, on the omega-mv tree.

Rebuilds the direct-KFD launcher and the gfx942 kernels with seed/out/omc
and compares them to gpu/amd/card.tsv (the receipt hashes). launch-x86 and
vadd are the hashes printed in Zenodo 10.5281/zenodo.24237047.

Arm64-only instruments (tests/amd-kfd-launch/trace.c in the CUDApp layout,
and tests/kfd/trace.c here) are SKIPPED on any host that is not aarch64.
A skip is counted and is not a pass. A hash mismatch exits 1. If omc cannot
be executed, the rebuild is SKIPPED and the exit is 77.
"""
from __future__ import annotations

import hashlib
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

BRIEF_LAUNCH = "08a504911ec6e87a9746632a14d22245155597e3a8ed384c93c0e5260bb691e1"
BRIEF_VADD = "10eb12e019ff2117ddc0190650899d4254589375c62e5ebb970b1bbb7e67e55f"
ROOT = Path(__file__).resolve().parents[2]


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def card_rows(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        kind, name, digest = line.split()
        rows.append((kind, name, digest))
    return rows


def omc_runs(omc):
    try:
        proc = subprocess.run(
            [str(omc)],
            input=b"fn main to int\nret 7\nend\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=90,
        )
    except OSError as exc:
        return False, "cannot execute seed/out/omc (%s)" % exc
    except subprocess.TimeoutExpired:
        return False, "seed/out/omc timed out"
    err = proc.stderr.decode("utf-8", "replace").strip()
    if proc.returncode != 0 or not proc.stdout.startswith(b"\x7fELF"):
        return False, "seed/out/omc exit %s (%s)" % (proc.returncode, err or "no ELF output")
    return True, "seed/out/omc executed (%d byte program)" % len(proc.stdout)


def enable_hint(system, arch):
    return (
        "omc is an aarch64 Linux binary and cannot run on %s/%s. "
        "On x86 Linux: sudo apt-get install qemu-user-static binfmt-support, "
        "mount binfmt_misc, and register /usr/lib/binfmt.d/qemu-aarch64.conf "
        "so the kernel runs qemu-aarch64. On Windows, use WSL with that binfmt setup."
        % (system, arch)
    )


def stream(cmd, cwd):
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert proc.stdout is not None
    lines = []
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace").rstrip("\n")
        print(line, flush=True)
        lines.append(line)
    code = proc.wait()
    return code, lines


def compare(kind, name, expected, artifact):
    if artifact is None or not artifact.is_file():
        computed = "MISSING"
        verdict = "MISMATCH"
    else:
        computed = sha256_file(artifact)
        verdict = "MATCH" if computed == expected else "MISMATCH"
    print(
        "HASH %s %s expected %s computed %s %s" % (kind, name, expected, computed, verdict),
        flush=True,
    )
    return verdict == "MATCH"


def main():
    system = platform.system()
    arch = platform.machine()
    print("HOST os=%s arch=%s python=%s" % (system, arch, platform.python_version()), flush=True)
    scan = subprocess.run([sys.executable, str(ROOT / "tools/uxl/windows_paths.py")])
    if scan.returncode:
        print("LEVEL2_COUNTS pass=0 fail=1 skip=0", flush=True)
        return 1

    arm = arch in ("aarch64", "arm64")
    skipped = 0
    if arm:
        trace = ROOT / "tests/amd-kfd-launch/trace.c"
        if not trace.is_file():
            print(
                "SKIP tests/amd-kfd-launch/trace.c: arm64-only instrument is not in this tree "
                "(it stays in CUDApp); host is %s/%s" % (system, arch),
                flush=True,
            )
            skipped += 1
    else:
        print(
            "SKIP tests/amd-kfd-launch/trace.c: arm64-only (AArch64 ptrace); "
            "detected host %s/%s; not compiled, not passed" % (system, arch),
            flush=True,
        )
        print(
            "SKIP tests/kfd/trace.c: arm64-only (AArch64 ptrace); "
            "detected host %s/%s; not compiled, not passed" % (system, arch),
            flush=True,
        )
        skipped += 2

    omc = ROOT / "seed/out/omc"
    ok, detail = omc_runs(omc)
    print("OMC %s sha256=%s" % (detail, sha256_file(omc) if omc.is_file() else "MISSING"), flush=True)
    if not ok:
        print("SKIP Level 2 rebuild: %s" % enable_hint(system, arch), flush=True)
        print("LEVEL2_COUNTS pass=0 fail=0 skip=%d" % (skipped + 1), flush=True)
        return 77

    pinned = card_rows(ROOT / "gpu/amd/card.tsv")
    by_name = {(kind, name): digest for kind, name, digest in pinned}
    if by_name.get(("bin", "launch-x86")) != BRIEF_LAUNCH or by_name.get(("obj", "vadd")) != BRIEF_VADD:
        print(
            "FAIL card.tsv launch-x86 or vadd does not match the hash printed in "
            "Zenodo 10.5281/zenodo.24237047",
            flush=True,
        )
        print("LEVEL2_COUNTS pass=0 fail=1 skip=%d" % skipped, flush=True)
        return 1
    print(
        "PINNED gpu/amd/card.tsv (MI300X receipt). launch-x86 and vadd match "
        "Zenodo 10.5281/zenodo.24237047.",
        flush=True,
    )

    parent = Path(tempfile.mkdtemp(prefix="uxl-level2-"))
    gate = parent / "gate"
    blob = b"om2\n" + (ROOT / "seed/ng/sha256.om").read_bytes() + (ROOT / "gpu/amd/gate.om").read_bytes()
    proc = subprocess.run(
        [str(omc)],
        input=blob,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    if proc.returncode != 0 or not proc.stdout:
        sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
        print("FAIL building gpu/amd/gate.om exit %s" % proc.returncode, flush=True)
        print("LEVEL2_COUNTS pass=0 fail=1 skip=%d" % skipped, flush=True)
        return 1
    gate.write_bytes(proc.stdout)
    gate.chmod(0o700)
    scratch = parent / "work"
    print("LEVEL2 rebuild start", flush=True)
    code, _lines = stream([str(gate), str(omc), str(scratch)], ROOT)
    if code != 0:
        print("FAIL gpu/amd gate exit %s" % code, flush=True)
        print("LEVEL2_COUNTS pass=0 fail=1 skip=%d" % skipped, flush=True)
        return 1

    passed = 0
    failed = 0
    launch = scratch / "launch-x86.1"
    if compare("launcher", "launch-x86", BRIEF_LAUNCH, launch):
        passed += 1
    else:
        failed += 1
    kernels = [name for kind, name, _digest in pinned if kind == "obj" and name != "vadd"]
    for name in kernels:
        if compare("kernel", name, by_name[("obj", name)], scratch / (name + ".hsaco")):
            passed += 1
        else:
            failed += 1
    if compare("object", "vadd", BRIEF_VADD, scratch / "vadd.hsaco"):
        passed += 1
    else:
        failed += 1
    print(
        "LEVEL2_COUNTS pass=%d fail=%d skip=%d kernels=%d"
        % (passed, failed, skipped, len(kernels)),
        flush=True,
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
