#!/usr/bin/env python3
"""External experiment instrument: compile Omega realizers and deliberate faults.

Python is an independent measuring/build instrument, never the arithmetic realizer.
All emitted executable arithmetic and GPU launch code is seeded Omega.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--canonical", type=Path)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    compiler = root / "seed/out/omc"
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    compiler_bytes = compiler.read_bytes()
    expected = (root / "seed/out/omc.sha256").read_text().split()[0]
    if digest(compiler_bytes) != expected:
        raise RuntimeError("compiler differs from its source tree's compiler digest")
    canonical = None
    if args.canonical:
        cmd = ["git", f"--git-dir={args.canonical}"]
        canonical = subprocess.check_output(cmd + ["rev-parse", "main"], text=True).strip()
        current = subprocess.check_output(cmd + ["show", "main:seed/out/omc"])
        if digest(current) != expected:
            raise RuntimeError("compiler is behind canonical main; rebuild from the newest compiler")
    args.out.mkdir(parents=True, exist_ok=False)
    worker = (here / "worker.om").read_text()
    cpu = (here / "cpu.om").read_text()
    injection = "value = si_result opcode lhs rhs"
    if worker.count(injection) != 1:
        raise RuntimeError("fault injection site missing or ambiguous")
    variants = {
        "worker": worker,
        "worker-clock": worker.replace(injection, injection + "\nvalue = rem ulong monons 65521"),
        "worker-random": worker.replace(injection, injection + "\nr = random si_output 0 1 0\nif ne r 1\nret 28\nend\nvalue = ulong get si_output 0"),
        "worker-state": worker.replace(injection, injection + "\nvalue = rem add value get si_state 0 65521\nput si_state 0 add get si_state 0 1"),
        "worker-hardcode": worker.replace(injection, injection + "\nif eq si_word 0 2\nvalue = ulong 14\nend"),
    }
    native_paths = ["gpu/nvidia/native/nvrm/context.om", "gpu/nvidia/native/blackwell/vector.om", "gpu/nvidia/native/blackwell/launch.om"]
    variants["worker-gpu"] = "".join((root / p).read_text() + "\n" for p in native_paths) + (here / "gpu.om").read_text() + "\n" + worker
    cache_site = "m = nvalloc size eq i 7"
    if variants["worker-gpu"].count(cache_site) != 1:
        raise RuntimeError("GPU input-cache mutation site missing or ambiguous")
    variants["worker-gpu-cache"] = variants["worker-gpu"].replace(cache_site, "m = nvalloc size ge i 5")
    manifest = {
        "source_head": head,
        "source_dirty": bool(subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"])),
        "canonical_main_at_build": canonical,
        "compiler_sha256": expected,
        "python_version": os.sys.version,
        "source_sha256": {str(p.relative_to(root)): digest(p.read_bytes()) for p in sorted(here.glob("*")) if p.is_file()},
        "native_source_sha256": {p: digest((root / p).read_bytes()) for p in native_paths},
        "binaries": {},
        "gpu_executed_by_build": False,
    }
    for name, text in variants.items():
        source = text if name.startswith("worker-gpu") else cpu + "\n" + text
        (args.out / (name + ".om")).write_text(source)
        result = subprocess.run([str(compiler)], input=source.encode(), capture_output=True, check=False)
        (args.out / (name + ".compile.stderr")).write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(f"{name} compile refused: {result.returncode}; output not executable")
        binary = args.out / name
        binary.write_bytes(result.stdout)
        binary.chmod(0o755)
        manifest["binaries"][name] = {"sha256": digest(result.stdout), "source_sha256": digest(source.encode()), "compile_exit": result.returncode}
    (args.out / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"build": str(args.out), "compiler_sha256": expected, "variants_built": list(variants)}))


if __name__ == "__main__":
    main()
