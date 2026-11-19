#!/usr/bin/env python3
"""One entry point for the UXL checks. Python 3.8+ standard library only.

  python3 tools/uxl/run_all.py
  py tools\\uxl\\run_all.py

Optional: --level1 DIR, --evidence PATH (a SHA256SUMS tree, a .tar.gz, or a URL).
SKIPs are reported and do not count as passes. Exit 0 only when nothing FAILed.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZENODO_API = "https://zenodo.org/api/records/24237047"
ZENODO_DOI = "10.5281/zenodo.24237047"


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
    scan = subprocess.run([sys.executable, str(ROOT / "tools/uxl/windows_paths.py")])
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


def intel_plans():
    directory = ROOT / "gpu"
    found = sorted(directory.glob("spirv/intel-*.tsv"))
    named = directory / "spirv/intel-gpu.tsv"
    if named.is_file() and named not in found:
        found.append(named)
    return found


def run_plan_rows(path):
    passed = 0
    failed = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            print("HASH plan %s expected row computed MALFORMED MISMATCH" % path.name)
            failed += 1
            continue
        name = parts[0]
        cmd = parts[1:]
        print("RUN %s %s" % (name, " ".join(cmd)), flush=True)
        proc = subprocess.run(cmd, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        body = text_of(proc).rstrip("\n")
        if body:
            print(body)
        if proc.returncode == 0:
            print("HASH %s expected exit 0 computed exit 0 MATCH" % name)
            passed += 1
        else:
            print("HASH %s expected exit 0 computed exit %s MISMATCH" % (name, proc.returncode))
            failed += 1
    return passed, failed


def intel_stage():
    stage("5. Intel OpenCL vadd/fsum16/gemm16")
    plans = intel_plans()
    check = ROOT / "gpu/spirv/check.sh"
    gpu, runtime, detail = opencl_probe()
    print("opencl %s" % detail)
    if not plans and not check.is_file():
        print("SKIP no gpu/spirv/intel-*.tsv and no gpu/spirv/check.sh in this checkout")
        print("intel counts: pass=0 fail=0 skip=1")
        return "SKIP", "Intel plan files are not in this checkout (vadd/fsum16/gemm16 runner absent)", 0, 0, 1
    if not gpu or not runtime:
        why = []
        if not gpu:
            why.append("no Intel GPU detected")
        if not runtime:
            why.append("no OpenCL runtime (clinfo or ICD)")
        print("SKIP " + "; ".join(why))
        print("intel counts: pass=0 fail=0 skip=1")
        return "SKIP", "; ".join(why), 0, 0, 1
    passed = 0
    failed = 0
    if check.is_file():
        print("RUN gpu/spirv/check.sh", flush=True)
        proc = subprocess.run([str(check)], cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        body = text_of(proc).rstrip("\n")
        if body:
            print(body)
        if proc.returncode == 0:
            print("HASH check.sh expected exit 0 computed exit 0 MATCH")
            passed += 1
        else:
            print("HASH check.sh expected exit 0 computed exit %s MISMATCH" % proc.returncode)
            failed += 1
    for path in plans:
        print("PLAN %s" % path.relative_to(ROOT).as_posix())
        row_pass, row_fail = run_plan_rows(path)
        passed += row_pass
        failed += row_fail
    print("intel counts: pass=%d fail=%d skip=0" % (passed, failed))
    if failed:
        return "FAIL", "%d Intel plan rows failed" % failed, passed, failed, 0
    if passed == 0:
        print("SKIP plan files had no runnable rows")
        return "SKIP", "plan files had no runnable rows", 0, 0, 1
    return "PASS", "%d Intel rows matched" % passed, passed, 0, 0


def spirv_stage():
    stage("6. RMSNorm SPIR-V (gpu/spirv/intel-*.tsv)")
    plans = sorted((ROOT / "gpu/spirv").glob("intel-*.tsv")) if (ROOT / "gpu/spirv").is_dir() else []
    rms = [path for path in plans if "rms" in path.name.lower()]
    if not plans:
        print("SKIP gpu/spirv/intel-*.tsv is not in this checkout")
        print("spirv counts: pass=0 fail=0 skip=1")
        return "SKIP", "gpu/spirv/intel-*.tsv absent (RMSNorm plan is on another branch)", 0, 0, 1
    if not rms:
        print("SKIP intel-*.tsv exists but none is an RMSNorm plan: %s" % ", ".join(p.name for p in plans))
        print("spirv counts: pass=0 fail=0 skip=1")
        return "SKIP", "no RMSNorm intel-*.tsv", 0, 0, 1
    gpu, runtime, detail = opencl_probe()
    print("opencl %s" % detail)
    if not gpu or not runtime:
        print("SKIP RMSNorm plan present but Intel GPU or OpenCL runtime is not")
        print("spirv counts: pass=0 fail=0 skip=1")
        return "SKIP", "RMSNorm plan present; Intel GPU or OpenCL runtime is not", 0, 0, 1
    passed = 0
    failed = 0
    for path in rms:
        row_pass, row_fail = run_plan_rows(path)
        passed += row_pass
        failed += row_fail
    print("spirv counts: pass=%d fail=%d skip=0" % (passed, failed))
    if failed:
        return "FAIL", "%d RMSNorm rows failed" % failed, passed, failed, 0
    return "PASS", "%d RMSNorm rows matched" % passed, passed, 0, 0


def looks_like_evidence(name):
    low = name.lower()
    if low.endswith((".tar.gz", ".tgz", ".tar")):
        return True
    if "evidence" in low or low == "sha256sums":
        return True
    return False


def zenodo_files():
    try:
        with urllib.request.urlopen(ZENODO_API, timeout=45) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        return None, str(exc)
    files = payload.get("files") or []
    return files, None


def download(url, dest):
    with urllib.request.urlopen(url, timeout=120) as response:
        dest.write_bytes(response.read())


def extract_archive(archive, dest):
    dest.mkdir(parents=True, exist_ok=True)
    if tarfile.is_tarfile(str(archive)):
        with tarfile.open(str(archive)) as handle:
            handle.extractall(str(dest))
        return
    raise OSError("not a tar archive: %s" % archive)


def find_sums(directory):
    direct = directory / "SHA256SUMS"
    if direct.is_file():
        return direct
    found = sorted(directory.rglob("SHA256SUMS"))
    if found:
        return found[0]
    return None


def parse_sums(path):
    rows = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # GNU sha256sum: "<64 hex><two spaces or space-star><name>"
        if len(line) < 66:
            rows.append((None, line, "short"))
            continue
        digest = line[:64]
        rest = line[64:]
        if len(digest) == 64 and rest[:1] in (" ", "\t") and all(
            ch in "0123456789abcdefABCDEF" for ch in digest
        ):
            name = rest.lstrip(" \t")
            binary = False
            if name.startswith("*"):
                binary = True
                name = name[1:]
            rows.append((digest.lower(), name, "ok" if not binary else "binary"))
        else:
            rows.append((None, line, "malformed"))
    return rows


def check_sums(sums_path):
    base = sums_path.parent
    rows = parse_sums(sums_path)
    passed = 0
    failed = 0
    for digest, name, kind in rows:
        if kind == "malformed" or kind == "short" or digest is None:
            print("%s: FAILED" % name)
            failed += 1
            continue
        path = base / name
        if not path.is_file():
            print("%s: FAILED" % name)
            print("HASH %s expected %s computed MISSING MISMATCH" % (name, digest))
            failed += 1
            continue
        computed = sha256_file(path)
        if computed == digest:
            print("%s: OK" % name)
            print("HASH %s expected %s computed %s MATCH" % (name, digest, computed))
            passed += 1
        else:
            print("%s: FAILED" % name)
            print("HASH %s expected %s computed %s MISMATCH" % (name, digest, computed))
            failed += 1
    return passed, failed


def evidence_stage(argument):
    stage("7. evidence archive SHA256SUMS")
    work = Path(tempfile.mkdtemp(prefix="uxl-evidence-"))
    target = None
    source = "argument" if argument else "zenodo"
    if argument:
        arg = argument
        if arg.startswith("http://") or arg.startswith("https://"):
            dest = work / "download"
            try:
                download(arg, dest)
            except Exception as exc:
                print("SKIP could not download %s (%s)" % (arg, exc))
                print("evidence counts: pass=0 fail=0 skip=1")
                return "SKIP", "evidence URL failed: %s" % exc, 0, 0, 1
            target = dest
        else:
            target = Path(arg).resolve()
            if not target.exists():
                print("SKIP evidence path does not exist: %s" % target)
                print("evidence counts: pass=0 fail=0 skip=1")
                return "SKIP", "evidence path not found", 0, 0, 1
    else:
        files, err = zenodo_files()
        if err:
            print("SKIP Zenodo %s could not be read (%s)" % (ZENODO_DOI, err))
            print("evidence counts: pass=0 fail=0 skip=1")
            return "SKIP", "Zenodo record unreadable: %s" % err, 0, 0, 1
        names = [item.get("key", "") for item in files]
        print("zenodo files: %s" % ", ".join(names))
        chosen = None
        for item in files:
            key = item.get("key") or ""
            if looks_like_evidence(key):
                chosen = item
                break
        if chosen is None:
            print(
                "SKIP Zenodo %s has no evidence archive (looked for a tarball, "
                "SHA256SUMS, or a name containing 'evidence'). Pass --evidence PATH."
                % ZENODO_DOI
            )
            print("evidence counts: pass=0 fail=0 skip=1")
            return "SKIP", "no evidence archive in Zenodo %s (%s)" % (ZENODO_DOI, ", ".join(names)), 0, 0, 1
        link = (chosen.get("links") or {}).get("self") or ""
        dest = work / chosen["key"]
        print("download %s" % chosen["key"])
        try:
            download(link, dest)
        except Exception as exc:
            print("SKIP download failed (%s)" % exc)
            print("evidence counts: pass=0 fail=0 skip=1")
            return "SKIP", "evidence download failed: %s" % exc, 0, 0, 1
        target = dest
    sums = None
    tree = target
    if target.is_file():
        unpacked = work / "unpacked"
        try:
            extract_archive(target, unpacked)
        except Exception as exc:
            if target.name == "SHA256SUMS":
                sums = target
                tree = target.parent
            else:
                print("SKIP not a tar archive and not SHA256SUMS (%s)" % exc)
                print("evidence counts: pass=0 fail=0 skip=1")
                return "SKIP", "evidence file is not a tar archive", 0, 0, 1
        else:
            tree = unpacked
    if sums is None:
        sums = find_sums(tree)
    if sums is None:
        print("SKIP no SHA256SUMS in %s" % target)
        print("evidence counts: pass=0 fail=0 skip=1")
        return "SKIP", "archive has no SHA256SUMS", 0, 0, 1
    print("SHA256SUMS %s (source %s)" % (sums, source))
    passed, failed = check_sums(sums)
    print("evidence counts: pass=%d fail=%d skip=0" % (passed, failed))
    if failed:
        return "FAIL", "%d evidence files mismatched" % failed, passed, failed, 0
    if passed == 0:
        return "SKIP", "SHA256SUMS had no file rows", 0, 0, 1
    return "PASS", "%d evidence files OK" % passed, passed, 0, 0


def summary(rows):
    stage("summary")
    print("%-18s %-6s %s" % ("STEP", "RESULT", "REASON"))
    fails = 0
    for name, status, reason, _passed, failed, _skipped in rows:
        print("%-18s %-6s %s" % (name, status, reason))
        fails += failed
        if status == "FAIL":
            fails += 0  # already counted; keep FAIL even if failed count was left 0
    # A FAIL status with a zero item count still fails the run.
    status_fails = sum(1 for row in rows if row[1] == "FAIL")
    print("")
    print(
        "steps pass=%d fail=%d skip=%d"
        % (
            sum(1 for row in rows if row[1] == "PASS"),
            status_fails,
            sum(1 for row in rows if row[1] == "SKIP"),
        )
    )
    print("SKIP is not a pass.")
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
    parser.add_argument("--evidence", help="evidence archive path or URL, or a directory containing SHA256SUMS")
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
        rows.append(("intel-opencl",) + intel_stage())
        rows.append(("spirv-rmsnorm",) + spirv_stage())
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
