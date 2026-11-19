#!/usr/bin/env python3
"""One entry point for the UXL checks. Python 3.8+ standard library only.

  python3 tools/uxl/run_all.py
  py tools\\uxl\\run_all.py

Optional: --level1 DIR, --evidence URL (Zenodo API record; default 24237047).
SKIP, NOT_RUN, and MISSING are reported and do not count as passes.
Exit 0 only when nothing FAILed.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZENODO_API = "https://zenodo.org/api/records/24237047"
ZENODO_DOI = "10.5281/zenodo.24237047"
PINNED_OMC_SHA256 = "34d611ca0415eab1728d3234911d90e74af17ba9ab0c581d559f48274d7ca6d3"
SHA256_RE = re.compile(r"sha256=([0-9a-fA-F]{64})")


class Tee(object):
    def __init__(self, path):
        self.file = path.open("w", encoding="utf-8", newline="\n")
        self.stdout = sys.stdout

    def write(self, text):
        self.stdout.write(text)
        self.stdout.flush()
        self.file.write(text)
        self.file.flush()

    def flush(self):
        self.stdout.flush()
        self.file.flush()


def run(cmd, cwd=None, timeout=120):
    try:
        return subprocess.run(
            cmd,
            cwd=None if cwd is None else str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except OSError as exc:
        proc = subprocess.CompletedProcess(cmd, 127, b"", str(exc).encode())
        return proc
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or b""
        err = exc.stderr or b"timeout"
        return subprocess.CompletedProcess(cmd, 124, out, err)


def text_of(proc):
    return proc.stdout.decode("utf-8", "replace")


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def git_head():
    proc = run(["git", "rev-parse", "HEAD"], ROOT)
    if proc.returncode != 0:
        return "unknown"
    return text_of(proc).strip()


def git_autocrlf():
    values = []
    for args in (
        ["git", "config", "--local", "--get", "core.autocrlf"],
        ["git", "config", "--global", "--get", "core.autocrlf"],
    ):
        proc = run(args, ROOT)
        got = text_of(proc).strip()
        if proc.returncode == 0 and got:
            values.append(got)
    if not values:
        return "unset"
    return values[0]


def tool_version(cmd):
    proc = run(cmd, timeout=30)
    if proc.returncode not in (0, 1):
        return "not found"
    line = text_of(proc).strip().splitlines()
    err = proc.stderr.decode("utf-8", "replace").strip().splitlines()
    if line:
        return line[0]
    if err:
        return err[0]
    return "not found"


def binfmt_aarch64():
    path = Path("/proc/sys/fs/binfmt_misc/qemu-aarch64")
    if not path.is_file():
        return "not registered"
    try:
        body = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return "unreadable (%s)" % exc
    first = body.splitlines()[0] if body else "present"
    return first


def qemu_note():
    names = []
    for name in ("qemu-aarch64", "qemu-aarch64-static"):
        found = shutil.which(name)
        if found:
            names.append(found)
    binfmt = binfmt_aarch64()
    if names:
        return "binfmt=%s; qemu=%s" % (binfmt, ", ".join(names))
    return "binfmt=%s; qemu=not on PATH" % binfmt


def opencl_probe():
    details = []
    present_gpu = False
    present_runtime = False
    clinfo = shutil.which("clinfo")
    if clinfo:
        proc = run([clinfo], timeout=40)
        body = text_of(proc) + proc.stderr.decode("utf-8", "replace")
        present_runtime = True
        details.append("clinfo exit %s" % proc.returncode)
        for line in body.splitlines():
            low = line.lower()
            if "intel" in low and ("device" in low or "name" in low or "vendor" in low):
                present_gpu = True
                details.append(line.strip())
                break
        if not present_gpu and "intel" in body.lower():
            present_gpu = True
            details.append("clinfo output mentions Intel")
    else:
        details.append("clinfo not on PATH")
    icd_dirs = [
        Path("/etc/OpenCL/vendors"),
        Path("/usr/lib/x86_64-linux-gnu/OpenCL/vendors"),
    ]
    icds = []
    for directory in icd_dirs:
        if directory.is_dir():
            icds.extend(sorted(directory.glob("*.icd")))
    if icds:
        present_runtime = True
        details.append("ICD " + ", ".join(path.name for path in icds))
        for path in icds:
            try:
                blob = path.read_text(encoding="utf-8", errors="replace").lower()
            except OSError:
                blob = path.name.lower()
            if "intel" in blob or "intel" in path.name.lower():
                present_gpu = True
    loader = shutil.which("libOpenCL.so")
    if loader:
        present_runtime = True
        details.append(loader)
    return present_gpu, present_runtime, "; ".join(details) if details else "no OpenCL probe data"


def header():
    omc = ROOT / "seed/out/omc"
    omc_hash = sha256_file(omc) if omc.is_file() else "MISSING"
    print("uxl-run log")
    print("git HEAD %s" % git_head())
    print("omc sha256 %s" % omc_hash)
    print("python %s" % sys.version.replace("\n", " "))
    print("git %s" % tool_version(["git", "--version"]))
    print("qemu %s" % tool_version(["qemu-aarch64-static", "--version"]))
    print("uname %s %s %s" % (platform.system(), platform.release(), platform.machine()))
    print("")


def stage(title):
    print("")
    print("=== %s ===" % title, flush=True)


def host_stage():
    stage("1. host check")
    system = platform.system()
    arch = platform.machine()
    print("os %s %s" % (system, platform.release()))
    print("arch %s" % arch)
    print("python %s" % platform.python_version())
    print("git core.autocrlf %s" % git_autocrlf())
    print("qemu-aarch64/binfmt %s" % qemu_note())
    gpu, runtime, detail = opencl_probe()
    print("intel gpu %s" % ("present" if gpu else "not present"))
    print("opencl runtime %s" % ("present" if runtime else "not present"))
    print("opencl detail %s" % detail)
    omc = ROOT / "seed/out/omc"
    got = sha256_file(omc) if omc.is_file() else "MISSING"
    verdict = "MATCH" if got == PINNED_OMC_SHA256 else "MISMATCH"
    print("HASH seed/out/omc expected %s computed %s %s" % (PINNED_OMC_SHA256, got, verdict))
    scan = subprocess.run([sys.executable, str(ROOT / "tools/uxl/windows_paths.py")])
    if got != PINNED_OMC_SHA256:
        print("host counts: pass=0 fail=1 skip=0")
        return "FAIL", "seed/out/omc sha256 %s" % verdict, 0, 1, 0
    if scan.returncode:
        print("host counts: pass=0 fail=1 skip=0")
        return "FAIL", "windows-paths reported findings", 0, 1, 0
    print("host counts: pass=1 fail=0 skip=0")
    return "PASS", "os=%s arch=%s autocrlf=%s" % (system, arch, git_autocrlf()), 1, 0, 0


def level1_dir(arg):
    if arg:
        return Path(arg).resolve()
    return ROOT / "tools/uxl/level1"


def level1_stage(directory):
    stage("2. Level 1 hash checks")
    print("source %s" % directory)
    manifest = directory / "SHA256.json"
    verify = directory / "verify.py"
    if not manifest.is_file() or not verify.is_file():
        print("SKIP Level 1: %s has no SHA256.json and verify.py" % directory)
        print("level1 counts: pass=0 fail=0 skip=1")
        return "SKIP", "Level 1 file set not found at %s" % directory, 0, 0, 1
    hashes = json.loads(manifest.read_text(encoding="utf-8"))
    on_disk = set()
    for path in directory.rglob("*"):
        if path.is_file() and path.name != "SHA256.json":
            on_disk.add(path.relative_to(directory).as_posix())
    passed = 0
    failed = 0
    missing = sorted(set(hashes) - on_disk)
    extra = sorted(on_disk - set(hashes))
    for name in sorted(hashes):
        expected = hashes[name]
        path = directory.joinpath(*name.split("/"))
        if not path.is_file():
            print("HASH %s expected %s computed MISSING MISMATCH" % (name, expected))
            failed += 1
            continue
        computed = sha256_file(path)
        verdict = "MATCH" if computed == expected else "MISMATCH"
        print("HASH %s expected %s computed %s %s" % (name, expected, computed, verdict))
        if verdict == "MATCH":
            passed += 1
        else:
            failed += 1
    for name in extra:
        print("HASH %s expected ABSENT computed %s MISMATCH" % (name, sha256_file(directory.joinpath(*name.split("/")))))
        failed += 1
    if missing:
        print("level1 paths missing from disk: %s" % ", ".join(missing))
    proc = subprocess.run(
        [sys.executable, "-I", str(verify)],
        cwd=str(directory),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    body = text_of(proc).rstrip("\n")
    if body:
        print(body)
    if proc.returncode != 0:
        failed += 1
        print("FAIL verify.py exit %s" % proc.returncode)
    print("level1 counts: pass=%d fail=%d skip=0" % (passed, failed))
    if failed:
        return "FAIL", "%d hash or verify failures" % failed, passed, failed, 0
    return "PASS", "%d hashed files; verify.py exit 0" % passed, passed, 0, 0


def level2_stage():
    stage("3. Level 2 rebuild")
    print("driver tests/amd-kfd-launch/check.py")
    print("hashes gpu/amd/card.tsv, cross-checked against Zenodo %s for launch-x86 and vadd" % ZENODO_DOI)
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "tests/amd-kfd-launch/check.py")],
        cwd=str(ROOT),
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
    counts = ""
    skips = []
    for line in lines:
        if line.startswith("LEVEL2_COUNTS "):
            counts = line
        if line.startswith("SKIP "):
            skips.append(line)
    stage("4. arm64-only tests")
    arm_skips = [line for line in skips if "trace.c" in line]
    if arm_skips:
        for line in arm_skips:
            print(line)
        print("arm64 counts: pass=0 fail=0 skip=%d" % len(arm_skips))
        arm = ("SKIP", "%d arm64-only test(s) not run" % len(arm_skips), 0, 0, len(arm_skips))
    elif code == 0:
        print("arm64 counts: pass=0 fail=0 skip=0")
        arm = ("PASS", "no arm64-only skip on this host", 0, 0, 0)
    else:
        print("arm64 counts: pass=0 fail=0 skip=0")
        arm = ("SKIP", "Level 2 did not reach the arch check", 0, 0, 1)
    if code == 77:
        reason = "omc cannot execute on this host"
        for line in skips:
            if line.startswith("SKIP Level 2"):
                reason = line[len("SKIP "):]
        print("level2 counts: pass=0 fail=0 skip=1")
        return ("SKIP", reason, 0, 0, 1), arm
    if code != 0:
        print("level2 counts: pass=0 fail=1 skip=0")
        return ("FAIL", "check.py exit %s %s" % (code, counts), 0, 1, 0), arm
    print("level2 counts: pass=1 fail=0 skip=0")
    return ("PASS", counts or "check.py exit 0", 1, 0, 0), arm


def omc_can_run(omc):
    if not omc.is_file():
        return False, "seed/out/omc is not in this checkout"
    try:
        proc = subprocess.run(
            [str(omc)],
            input=b"fn main to int\nret 7\nend\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
    except OSError as exc:
        return False, "cannot execute seed/out/omc (%s)" % exc
    except subprocess.TimeoutExpired:
        return False, "seed/out/omc timed out"
    err = proc.stderr.decode("utf-8", "replace").strip().splitlines()
    if proc.returncode != 0 or not proc.stdout.startswith(b"\x7fELF"):
        detail = err[0] if err else "no ELF output"
        return False, "seed/out/omc did not run (%s)" % detail
    return True, "seed/out/omc executed"


def qemu_install_line():
    return (
        "omc is the pinned AArch64 binary sha256 %s. On x86 Linux install "
        "qemu-user-static and binfmt-support, mount binfmt_misc, and register "
        "/usr/lib/binfmt.d/qemu-aarch64.conf so the kernel runs qemu-aarch64. "
        "On Windows, use WSL with that binfmt setup."
        % PINNED_OMC_SHA256
    )


def spirv_val_install_line():
    return (
        "spirv-val is not on PATH. Install SPIRV-Tools "
        "(Debian/Ubuntu: sudo apt-get install spirv-tools), which provides spirv-val."
    )


def child_env():
    env = dict(os.environ)
    env["OMC"] = "seed/out/omc"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def stream(cmd, cwd):
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            env=child_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        print("MISMATCH %s (%s)" % (" ".join(cmd), exc), flush=True)
        return 127, ["%s" % exc]
    assert proc.stdout is not None
    lines = []
    for raw in proc.stdout:
        line = raw.decode("utf-8", "replace").rstrip("\n")
        print(line, flush=True)
        if line.startswith("PASS "):
            print("MATCH %s" % line[5:], flush=True)
        elif line.startswith("FAIL "):
            print("MISMATCH %s" % line[5:], flush=True)
        elif line.startswith("CONFORM ") and "wrong=0" in line:
            print("MATCH %s" % line, flush=True)
        elif line.startswith("CONFORM "):
            print("MISMATCH %s" % line, flush=True)
        lines.append(line)
    return proc.wait(), lines


def sha_from_lines(lines):
    found = None
    for line in lines:
        for match in SHA256_RE.finditer(line):
            found = match.group(1).lower()
    return found


def parse_plan(path):
    rows = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return rows, "empty"
    header = lines[0].split("\t")
    required = ("id", "command", "expect_sha256")
    for name in required:
        if name not in header:
            return [], "header missing %s" % name
    for raw in lines[1:]:
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = raw.split("\t")
        if len(cols) < len(header):
            cols = cols + [""] * (len(header) - len(cols))
        rows.append({header[i]: cols[i] for i in range(len(header))})
    return rows, None


def row_argv(command):
    argv = shlex.split(command)
    if argv and argv[0] in ("python3", "python", "py"):
        argv[0] = sys.executable
    return argv


def run_plan(path):
    rows, err = parse_plan(path)
    passed = 0
    failed = 0
    not_run = 0
    if err:
        print("MISMATCH %s %s" % (path.name, err))
        return passed, failed + 1, not_run
    for row in rows:
        name = row.get("id") or path.name
        prereq = row.get("prerequisite") or ""
        expected = (row.get("expect_sha256") or "").lower()
        phrase = row.get("pass") or ""
        stdout_need = phrase.split("stdout ", 1)[1] if "stdout " in phrase else ""
        print("ROW %s prerequisite %s" % (name, prereq or "none"), flush=True)
        print("reference sha256 %s" % (expected or "none"), flush=True)
        argv = row_argv(row.get("command") or "")
        print("RUN %s" % " ".join(argv), flush=True)
        if not argv:
            print("HASH %s expected %s computed MALFORMED MISMATCH" % (name, expected or "exit 0"))
            failed += 1
            continue
        code, lines = stream(argv, ROOT)
        digest = sha_from_lines(lines)
        computed = digest if digest else "NONE"
        if code == 2:
            print(
                "HASH %s expected %s computed NOT_RUN NOT_RUN" % (name, expected or "sha256"),
                flush=True,
            )
            print("NOT_RUN %s exit 2 (prerequisite %s missing; not a pass)" % (name, prereq or "runtime"))
            not_run += 1
            continue
        phrase_ok = (not stdout_need) or any(stdout_need in line for line in lines)
        hash_ok = (not expected) or computed == expected
        if code == 0 and phrase_ok and hash_ok:
            print(
                "HASH %s expected %s computed %s MATCH" % (name, expected or "exit 0", computed),
                flush=True,
            )
            passed += 1
        else:
            print(
                "HASH %s expected %s computed %s MISMATCH" % (name, expected or "exit 0", computed),
                flush=True,
            )
            print("FAIL %s exit %s" % (name, code))
            failed += 1
    return passed, failed, not_run


def plan_status(passed, failed, not_run, empty_reason):
    if failed:
        return "FAIL", "%d failed, %d not_run, %d passed" % (failed, not_run, passed), passed, failed, not_run
    if not_run:
        return "NOT_RUN", "%d not_run, %d passed (NOT_RUN is not a pass)" % (not_run, passed), passed, 0, not_run
    if passed == 0:
        return "MISSING", empty_reason, 0, 0, 0
    return "PASS", "%d rows matched" % passed, passed, 0, 0


def spirv_stage():
    stage("5. SPIR-V spirv-val, mutants, conform")
    check = ROOT / "gpu/spirv/check.sh"
    if not check.is_file():
        print("MISSING gpu/spirv/check.sh")
        print("spirv counts: pass=0 fail=0 skip=0")
        return "MISSING", "gpu/spirv/check.sh is not in this checkout", 0, 0, 0
    reasons = []
    spirv_val = os.environ.get("SPIRV_VAL", "spirv-val")
    if shutil.which(spirv_val) is None and not Path(spirv_val).is_file():
        reasons.append(spirv_val_install_line())
    omc = ROOT / "seed/out/omc"
    ok, detail = omc_can_run(omc)
    print("OMC %s" % detail)
    if not ok:
        reasons.append("%s. %s" % (detail, qemu_install_line()))
    if reasons:
        print("SKIP " + " ".join(reasons))
        print("spirv counts: pass=0 fail=0 skip=1")
        return "SKIP", " ".join(reasons), 0, 0, 1
    print("RUN OMC=seed/out/omc sh gpu/spirv/check.sh", flush=True)
    code, _lines = stream(["sh", "gpu/spirv/check.sh"], ROOT)
    verdict = "MATCH" if code == 0 else "MISMATCH"
    print("HASH gpu/spirv/check.sh expected exit 0 computed exit %s %s" % (code, verdict))
    print("spirv counts: pass=%d fail=%d skip=0" % (1 if code == 0 else 0, 0 if code == 0 else 1))
    if code == 0:
        return "PASS", "gpu/spirv/check.sh exit 0", 1, 0, 0
    return "FAIL", "gpu/spirv/check.sh exit %s" % code, 0, 1, 0


def spirv_rmsnorm_stage():
    stage("6. SPIR-V RMSNorm (gpu/spirv/intel-rmsnorm.tsv)")
    path = ROOT / "gpu/spirv/intel-rmsnorm.tsv"
    print(
        "reference sha256 144c89820d5d005af741dfcace8f9882bae481d72f1745aef36b5014cbaadb46"
    )
    if not path.is_file():
        print("MISSING gpu/spirv/intel-rmsnorm.tsv")
        print("spirv-rmsnorm counts: pass=0 fail=0 not_run=0")
        return "MISSING", "gpu/spirv/intel-rmsnorm.tsv is not in this checkout", 0, 0, 0
    print("PLAN gpu/spirv/intel-rmsnorm.tsv")
    passed, failed, not_run = run_plan(path)
    print("spirv-rmsnorm counts: pass=%d fail=%d not_run=%d" % (passed, failed, not_run))
    return plan_status(passed, failed, not_run, "gpu/spirv/intel-rmsnorm.tsv has no rows")


def intel_opencl_stage():
    stage("7. Intel OpenCL vadd/fsum16/gemm16")
    plan = ROOT / "gpu/spirv/intel-opencl.tsv"
    print("expect %s" % plan.relative_to(ROOT).as_posix())
    gemm = []
    for base in (ROOT / "gpu", ROOT / "tests"):
        if not base.is_dir():
            continue
        for found in base.rglob("*"):
            if found.is_file() and "gemm16" in found.name.lower():
                gemm.append(found.relative_to(ROOT).as_posix())
    if gemm:
        print("found gemm16 files: %s" % ", ".join(sorted(gemm)))
    else:
        print("MISSING gemm16 under gpu/ and tests/ (no file name contains gemm16)")
    conform = ROOT / "gpu/spirv/conform.om"
    emit = ROOT / "gpu/spirv/emit.om"
    if conform.is_file():
        body = conform.read_text(encoding="utf-8", errors="replace")
        print("gpu/spirv/conform.om gemm16 %s" % ("present" if "gemm16" in body else "absent"))
    else:
        print("MISSING gpu/spirv/conform.om")
    if emit.is_file():
        body = emit.read_text(encoding="utf-8", errors="replace")
        print("gpu/spirv/emit.om gemm16 %s" % ("present" if "gemm16" in body else "absent"))
    else:
        print("MISSING gpu/spirv/emit.om")
    print(
        "gpu/spirv/conform.om has host references for vadd and fsum16. "
        "Those run in the spirv stage via gpu/spirv/check.sh. "
        "There is no OpenCL device plan for vadd, fsum16, and gemm16."
    )
    print(
        "Zenodo %s uxl-brief.tex does not define those Intel OpenCL rows "
        "(its vadd is the AMD hsaco). No result was invented."
        % ZENODO_DOI
    )
    if not plan.is_file():
        print("MISSING gpu/spirv/intel-opencl.tsv")
        print("intel counts: pass=0 fail=0 not_run=0 missing=1")
        return "MISSING", "gpu/spirv/intel-opencl.tsv is not in this checkout", 0, 0, 0
    print("PLAN gpu/spirv/intel-opencl.tsv")
    passed, failed, not_run = run_plan(plan)
    print("intel counts: pass=%d fail=%d not_run=%d" % (passed, failed, not_run))
    return plan_status(passed, failed, not_run, "gpu/spirv/intel-opencl.tsv has no rows")


def zenodo_record(api):
    try:
        with urllib.request.urlopen(api, timeout=45) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        return None, str(exc)
    return payload, None


def file_digest(path, algo):
    digest = hashlib.new(algo)
    with path.open("rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def evidence_stage(argument):
    stage("8. Zenodo record file checksums")
    api = argument or ZENODO_API
    print("GET %s" % api)
    payload, err = zenodo_record(api)
    if err or payload is None:
        print("SKIP Zenodo %s could not be read (%s). Offline: no file was checked." % (ZENODO_DOI, err))
        print("evidence counts: pass=0 fail=0 skip=1")
        return "SKIP", "Zenodo record unreadable: %s" % err, 0, 0, 1
    files = payload.get("files") or []
    if not files:
        print("SKIP Zenodo %s returned no files" % ZENODO_DOI)
        print("evidence counts: pass=0 fail=0 skip=1")
        return "SKIP", "Zenodo record has no files", 0, 0, 1
    names = [item.get("key", "") for item in files]
    print("zenodo files: %s" % ", ".join(names))
    print("no evidence archive is published on this record; each file is checked against its API checksum")
    work = Path(tempfile.mkdtemp(prefix="uxl-zenodo-"))
    passed = 0
    failed = 0
    try:
        for item in files:
            key = item.get("key") or "file"
            checksum = item.get("checksum") or ""
            link = (item.get("links") or {}).get("self") or ""
            if ":" not in checksum or not link:
                print("HASH %s expected %s computed MALFORMED MISMATCH" % (key, checksum or "MISSING"))
                failed += 1
                continue
            algo, expected = checksum.split(":", 1)
            expected = expected.lower()
            dest = work / key
            dest.parent.mkdir(parents=True, exist_ok=True)
            print("download %s" % key, flush=True)
            try:
                with urllib.request.urlopen(link, timeout=120) as response:
                    dest.write_bytes(response.read())
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                print("SKIP download %s failed (%s)" % (key, exc))
                print("evidence counts: pass=%d fail=%d skip=1" % (passed, failed))
                return "SKIP", "offline or download failed for %s: %s" % (key, exc), passed, failed, 1
            try:
                computed = file_digest(dest, algo)
            except ValueError as exc:
                print("HASH %s expected %s computed UNSUPPORTED MISMATCH" % (key, checksum))
                print("MISMATCH %s (%s)" % (key, exc))
                failed += 1
                continue
            verdict = "MATCH" if computed == expected else "MISMATCH"
            print("HASH %s expected %s computed %s:%s %s" % (key, checksum, algo, computed, verdict))
            if verdict == "MATCH":
                passed += 1
            else:
                failed += 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("evidence counts: pass=%d fail=%d skip=0" % (passed, failed))
    if failed:
        return "FAIL", "%d Zenodo files mismatched" % failed, passed, failed, 0
    return "PASS", "%d Zenodo files matched their API checksums" % passed, passed, 0, 0


def summary(rows):
    stage("summary")
    print("%-16s %-8s %s" % ("STEP", "RESULT", "REASON"))
    fails = 0
    for name, status, reason, _passed, failed, _skipped in rows:
        print("%-16s %-8s %s" % (name, status, reason))
        fails += failed
    status_fails = sum(1 for row in rows if row[1] == "FAIL")

    def count(status):
        return sum(1 for row in rows if row[1] == status)

    print("")
    print(
        "steps pass=%d fail=%d skip=%d not_run=%d missing=%d"
        % (count("PASS"), status_fails, count("SKIP"), count("NOT_RUN"), count("MISSING"))
    )
    print("SKIP is not a pass. NOT_RUN is not a pass. MISSING is not a pass.")
    return 1 if status_fails or fails else 0


def log_path():
    host = platform.node() or "host"
    safe = "".join(ch if ch.isalnum() or ch in ("-", "_") else "-" for ch in host)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return Path.cwd() / ("uxl-run-%s-%s.log" % (safe or "host", stamp))


def main(argv):
    sys.dont_write_bytecode = True
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    parser = argparse.ArgumentParser(description="Run the UXL checks")
    parser.add_argument("--level1", help="directory with SHA256.json and verify.py")
    parser.add_argument("--evidence", help="Zenodo API record URL (default: record 24237047)")
    args = parser.parse_args(argv)
    path = log_path()
    tee = Tee(path)
    sys.stdout = tee
    try:
        header()
        rows = []
        rows.append(("host",) + host_stage())
        rows.append(("level1",) + level1_stage(level1_dir(args.level1)))
        level2, arm = level2_stage()
        rows.append(("level2",) + level2)
        rows.append(("arm64-only",) + arm)
        rows.append(("spirv",) + spirv_stage())
        rows.append(("spirv-rmsnorm",) + spirv_rmsnorm_stage())
        rows.append(("intel-opencl",) + intel_opencl_stage())
        rows.append(("evidence",) + evidence_stage(args.evidence))
        code = summary(rows)
        print("")
        print("log %s" % path.resolve())
        return code
    finally:
        sys.stdout = tee.stdout
        tee.file.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
