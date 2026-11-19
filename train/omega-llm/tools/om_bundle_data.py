#!/usr/bin/env python3
"""Audit local .om corpus, generate live omc refusal-repair pairs (errors 1..30),
and build deterministic, zero-leakage OLLM specialist bundle datasets (.tok + .msk).

Bundles:
  - om-core:       core .om language, stdlib, compiler, OLLM CPU, omc refusal-repair pairs
  - gb20b-mmio:    GB20B / Blackwell / GPU / CUDApp / GSP / SEC2 / MMIO / VFIO / KFD
  - aienux-kernel: Aienux OS / ARM64/x86 EFI / boot / MMU / drivers (e.g. rtl8127)
  - libos-rpc:     LibosLog / RPC / HTTP / JSON / wire protocols / IPC / net

Zero machine-specific paths are hardcoded; override via CLI flags.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

T_CTX = 256
BUNDLES = ("om-core", "gb20b-mmio", "aienux-kernel", "libos-rpc")

CANONICAL_REPO_ORDER = (
    "omega-mv",
    "aien-train",
    "aienux-arm64-model",
    "aienux-macbook",
    "omega-arm64efi",
    "omega-harness",
    "rtl8127-omega",
    "interplane-forge",
    "ipl-hop",
    "ggml-omega-macbook",
    "astra-inference-cache",
    "omega-bridge-macbook",
    "si-plain-start",
    "aien-train-voice-ui",
    "interplane.io",
)

SKIP_DIRS = {".git", "node_modules", "__pycache__", "target", "build", ".venv"}

NEGATIVE_FILE_RE = re.compile(
    r"(^|/)(err\d{2}_|mistake_|.*-mut\d*\.om$|.*mutants\.om$|.*_bad\.om$|.*_fail\.om$)",
    re.IGNORECASE,
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_negative_control(rel_path: str) -> bool:
    p = rel_path.lower()
    if "/controls/" in p and ("mut" in p or "e13" in p or "bad" in p):
        return True
    return bool(NEGATIVE_FILE_RE.search(p))


def classify_domain(repo: str, rel_path: str, head_lower: str) -> Tuple[str, str]:
    """Return (bundle_name, audit_category).

    audit_category separates OLLM CPU from general om-core for reporting,
    while bundle_name maps every file to one of the 4 specialist bundles.
    """
    p = rel_path.lower()

    # 1. GB20B / GPU / MMIO / CUDApp / GSP / SEC2
    if (
        "/gpu/" in p
        or any(
            k in p
            for k in (
                "gb20",
                "blackwell",
                "cudapp",
                "nvrm",
                "gsp",
                "sec2",
                "mmio",
                "vfio",
                "kfd",
                "uvm",
            )
        )
        or (
            "omegallm/gpu/" in p
            or any(
                p.endswith(s)
                for s in (
                    "/gg.om",
                    "/gk.om",
                    "/gr.om",
                    "/gb.om",
                    "/launch.om",
                    "/vector.om",
                    "/context.om",
                    "/batch.om",
                )
            )
        )
    ):
        return "gb20b-mmio", "gb20b-mmio"

    if any(
        w in head_lower
        for w in ("devctl ", "devcall ", "uvmctl ", "vfioctl ", "mapget ", "mapset ", "kfdctl ")
    ):
        return "gb20b-mmio", "gb20b-mmio"

    # 2. LibosLog / RPC / net / HTTP / JSON / wire / IPC
    if any(
        k in p
        for k in (
            "libos",
            "rpc",
            "/net/",
            "http",
            "json",
            "wire",
            "serve.om",
            "ipc",
            "proto",
            "sock",
            "tls-",
        )
    ):
        return "libos-rpc", "libos-rpc"

    # 3. Aienux kernel / EFI / MMU / bare-metal drivers (excluding benchmark kernels/)
    if (
        repo in ("aienux-arm64-model", "aienux-macbook", "omega-arm64efi", "rtl8127-omega")
        or any(k in p for k in ("aienux", "mmu", "a64efi", "x86efi", "efirt", "pagetable", "rtl8127"))
        or ("target a64efi" in head_lower or "target x86efi" in head_lower)
    ):
        return "aienux-kernel", "aienux-kernel"

    # 4. OLLM CPU / native trainer (audited separately, bundled into om-core)
    if (
        "omegallm" in p
        or repo in ("aien-train", "aien-train-macbook", "ggml-omega-macbook", "astra-inference-cache")
    ):
        return "om-core", "ollm"

    return "om-core", "om-core"


def scan_workspace(workspace: Path) -> dict:
    """Scan all .om files under workspace, deduplicating by SHA-256 content hash."""
    if not workspace.is_dir():
        raise FileNotFoundError(f"Workspace not found: {workspace}")

    entries = sorted(
        d for d in os.listdir(workspace) if not d.startswith(".") and (workspace / d).is_dir()
    )
    ordered_repos = [r for r in CANONICAL_REPO_ORDER if r in entries]
    ordered_repos += [r for r in entries if r not in ordered_repos]

    by_repo = defaultdict(lambda: {"files": 0, "loc": 0, "bytes": 0})
    by_category = defaultdict(lambda: {"files": 0, "loc": 0, "bytes": 0, "clean_files": 0, "clean_loc": 0})
    by_bundle = defaultdict(lambda: {"files": 0, "loc": 0, "bytes": 0, "clean_files": 0, "clean_loc": 0})

    seen_hashes: Dict[str, dict] = {}
    total_files = total_loc = total_bytes = dup_files = 0

    for repo in ordered_repos:
        rpath = workspace / repo
        for dirpath, dirnames, filenames in os.walk(rpath):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            for fn in sorted(filenames):
                if not fn.endswith(".om"):
                    continue
                fpath = Path(dirpath) / fn
                if fpath.is_symlink():
                    continue
                try:
                    data = fpath.read_bytes()
                except OSError:
                    continue
                loc = data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)
                nbytes = len(data)
                total_files += 1
                total_loc += loc
                total_bytes += nbytes
                by_repo[repo]["files"] += 1
                by_repo[repo]["loc"] += loc
                by_repo[repo]["bytes"] += nbytes

                h = sha256_bytes(data)
                if h in seen_hashes:
                    dup_files += 1
                    continue

                rel = str(fpath.relative_to(workspace))
                head_lower = data[:8192].decode("latin1").lower()
                bundle, cat = classify_domain(repo, rel, head_lower)
                neg = is_negative_control(rel)

                rec = {
                    "sha256": h,
                    "repo": repo,
                    "rel": rel,
                    "path": str(fpath),
                    "loc": loc,
                    "bytes": nbytes,
                    "bundle": bundle,
                    "category": cat,
                    "negative_control": neg,
                }
                seen_hashes[h] = rec

                by_category[cat]["files"] += 1
                by_category[cat]["loc"] += loc
                by_category[cat]["bytes"] += nbytes
                by_bundle[bundle]["files"] += 1
                by_bundle[bundle]["loc"] += loc
                by_bundle[bundle]["bytes"] += nbytes
                if not neg:
                    by_category[cat]["clean_files"] += 1
                    by_category[cat]["clean_loc"] += loc
                    by_bundle[bundle]["clean_files"] += 1
                    by_bundle[bundle]["clean_loc"] += loc

    unique_recs = list(seen_hashes.values())
    return {
        "total_all_dirs": {
            "files": total_files,
            "loc": total_loc,
            "bytes": total_bytes,
            "duplicates": dup_files,
        },
        "unique_dedup": {
            "files": len(unique_recs),
            "loc": sum(r["loc"] for r in unique_recs),
            "bytes": sum(r["bytes"] for r in unique_recs),
            "clean_files": sum(1 for r in unique_recs if not r["negative_control"]),
            "clean_loc": sum(r["loc"] for r in unique_recs if not r["negative_control"]),
        },
        "by_repo": dict(sorted(by_repo.items(), key=lambda kv: -kv[1]["loc"])),
        "by_category": dict(by_category),
        "by_bundle": dict(by_bundle),
        "records": unique_recs,
    }


def refusal_specs(include_err24: bool = False) -> List[dict]:
    """Controlled defective/repaired .om pairs spanning omc error codes 1..30
    plus common out-of-distribution mistakes (infix, C calls, comments, etc.).
    """
    specs: List[dict] = [
        {
            "id": "err01_stdin_dir",
            "code": 1,
            "kind": "io",
            "desc": "stdin read failed (directory passed as stdin)",
            "bad": "fn main to int\nret 0\nend\n",
            "good": "fn main to int\nret 0\nend\n",
            "trigger": "stdin_dir",
        },
        {
            "id": "err02_stdout_ro",
            "code": 2,
            "kind": "io",
            "desc": "stdout write failed (read-only stdout descriptor)",
            "bad": "fn main to int\nret 0\nend\n",
            "good": "fn main to int\nret 0\nend\n",
            "trigger": "stdout_ro",
        },
        {
            "id": "err03_unknown_name",
            "code": 3,
            "kind": "source",
            "desc": "unknown variable name",
            "bad": "fn main to int\nret foo\nend\n",
            "good": "fn main to int\nfoo = int 0\nret foo\nend\n",
        },
        {
            "id": "err03_char_literal",
            "code": 3,
            "kind": "source",
            "desc": "C char literal instead of uchar byte value",
            "bad": "fn main to int\nc = 'A'\nret int c\nend\n",
            "good": "fn main to int\nc = uchar 65\nret int c\nend\n",
        },
        {
            "id": "err03_rotr_without_om2",
            "code": 3,
            "kind": "source",
            "desc": "rotr used without om2 header",
            "bad": "fn main to int\nx = rotr uint 1 1\nret int x\nend\n",
            "good": "om2\nfn main to int\nx = rotr uint 1 1\nret int x\nend\n",
        },
        {
            "id": "err04_line_ends_early",
            "code": 4,
            "kind": "source",
            "desc": "missing operand in prefix add",
            "bad": "fn main to int\nx = add int 1\nret x\nend\n",
            "good": "fn main to int\nx = add int 1 2\nret x\nend\n",
        },
        {
            "id": "err05_extra_words",
            "code": 5,
            "kind": "source",
            "desc": "extra trailing token on line",
            "bad": "fn main to int\nx = int 1 2\nret x\nend\n",
            "good": "fn main to int\nx = int 1\nret x\nend\n",
        },
        {
            "id": "err05_infix_plus",
            "code": 5,
            "kind": "source",
            "desc": "infix x + 1 instead of prefix add x 1",
            "bad": "fn main to int\nx = int 1\ny = x + 1\nret y\nend\n",
            "good": "fn main to int\nx = int 1\ny = add x 1\nret y\nend\n",
        },
        {
            "id": "err05_else_if",
            "code": 5,
            "kind": "source",
            "desc": "else if on one line instead of nested if inside else",
            "bad": "fn main to int\nx = int 1\nif eq x 0\nret 0\nelse if eq x 1\nret 1\nend\nret 2\nend\n",
            "good": "fn main to int\nx = int 1\nif eq x 0\nret 0\nelse\nif eq x 1\nret 1\nend\nend\nret 2\nend\n",
        },
        {
            "id": "err06_semicolon",
            "code": 6,
            "kind": "source",
            "desc": "trailing semicolon on number literal",
            "bad": "fn main to int\nx = int 1;\nret x\nend\n",
            "good": "fn main to int\nx = int 1\nret x\nend\n",
        },
        {
            "id": "err06_upper_hex",
            "code": 6,
            "kind": "source",
            "desc": "uppercase hex literal in om2",
            "bad": "om2\nfn main to int\nx = uint 0xFF\nret int x\nend\n",
            "good": "om2\nfn main to int\nx = uint 0xff\nret int x\nend\n",
        },
        {
            "id": "err07_type_mismatch",
            "code": 7,
            "kind": "source",
            "desc": "implicit int + ulong mismatch without explicit cast",
            "bad": "fn main to int\na = int 1\nb = ulong 2\nret add a b\nend\n",
            "good": "fn main to int\na = int 1\nb = ulong 2\nret add a int b\nend\n",
        },
        {
            "id": "err07_value_as_stmt",
            "code": 7,
            "kind": "source",
            "desc": "non-void function called as bare statement",
            "bad": "fn f x int to int\nret add x 1\nend\nfn main to int\nf 1\nret 0\nend\n",
            "good": "fn f x int to int\nret add x 1\nend\nfn main to int\nv = f 1\nret v\nend\n",
        },
        {
            "id": "err08_out_of_range",
            "code": 8,
            "kind": "source",
            "desc": "uchar literal exceeds 255",
            "bad": "fn main to int\nx = uchar 300\nret int x\nend\n",
            "good": "fn main to int\nx = uchar 255\nret int x\nend\n",
        },
        {
            "id": "err08_bound_zero",
            "code": 8,
            "kind": "source",
            "desc": "while loop bound 0 is out of range",
            "bad": "fn main to int\nwhile false bound 0\nend\nret 0\nend\n",
            "good": "fn main to int\nwhile false bound 1\nend\nret 0\nend\n",
        },
        {
            "id": "err09_free_disallowed",
            "code": 9,
            "kind": "source",
            "desc": "free is refused (no heap in Omega)",
            "bad": "fn main to int\na = new uchar 4 0\nfree a\nret 0\nend\n",
            "good": "fn main to int\na = new uchar 4 0\nret int get a 0\nend\n",
        },
        {
            "id": "err09_main_params",
            "code": 9,
            "kind": "source",
            "desc": "fn main cannot take parameters (use argcnt/argread)",
            "bad": "fn main argc int to int\nret argc\nend\n",
            "good": "fn main to int\nn = argcnt\nret int n\nend\n",
        },
        {
            "id": "err10_duplicate_fn",
            "code": 10,
            "kind": "source",
            "desc": "duplicate function name",
            "bad": "fn main to int\nret 0\nend\nfn main to int\nret 1\nend\n",
            "good": "fn helper to int\nret 1\nend\nfn main to int\nret helper\nend\n",
        },
        {
            "id": "err11_ambiguous_bare_number",
            "code": 11,
            "kind": "source",
            "desc": "bare untyped integer literal on new variable",
            "bad": "fn main to int\nx = 5\nret x\nend\n",
            "good": "fn main to int\nx = int 5\nret x\nend\n",
        },
        {
            "id": "err12_register_pool",
            "code": 12,
            "kind": "source",
            "desc": "more than 16 live registers in one function",
            "bad": "fn main to int\n" + "".join(f"v{i} = int {i}\n" for i in range(18)) + "ret v0\nend\n",
            "good": "fn main to int\ns = int 0\nfor i int 18\ns = add s i\nend\nret s\nend\n",
        },
        {
            "id": "err13_name_too_long",
            "code": 13,
            "kind": "source",
            "desc": "identifier exceeds 63-byte limit",
            "bad": "fn main to int\n" + ("a" * 64) + " = int 1\nret 0\nend\n",
            "good": "fn main to int\nval = int 1\nret val\nend\n",
        },
        {
            "id": "err14_export_capacity",
            "code": 14,
            "kind": "source",
            "desc": "more than 32 export fn entries in om2 unit",
            "bad": "om2\n" + "".join(f"export fn f{i} to int\nret {i}\nend\n" for i in range(33)),
            "good": "om2\nexport fn f0 to int\nret 0\nend\n",
        },
        {
            "id": "err15_missing_end",
            "code": 15,
            "kind": "source",
            "desc": "unclosed block missing end",
            "bad": "fn main to int\nif true\nret 0\nend\n",
            "good": "fn main to int\nif true\nret 0\nend\nret 1\nend\n",
        },
        {
            "id": "err16_reserved_name",
            "code": 16,
            "kind": "source",
            "desc": "reserved keyword len used as variable name",
            "bad": "fn main to int\nlen = int 1\nret 0\nend\n",
            "good": "fn main to int\nn = int 1\nret n\nend\n",
        },
        {
            "id": "err17_after_ret",
            "code": 17,
            "kind": "source",
            "desc": "unreachable statement after ret",
            "bad": "fn main to int\nret 0\nx = int 1\nend\n",
            "good": "fn main to int\nx = int 1\nret x\nend\n",
        },
        {
            "id": "err18_missing_ret",
            "code": 18,
            "kind": "source",
            "desc": "non-void function missing ret (also catches silent return x typo)",
            "bad": "fn main to int\nx = int 1\nreturn x\nend\n",
            "good": "fn main to int\nx = int 1\nret x\nend\n",
        },
        {
            "id": "err19_global_arg",
            "code": 19,
            "kind": "source",
            "desc": "global array passed as function argument",
            "bad": "global g uchar 4\nfn f a view uchar 4 to int\nret int get a 0\nend\nfn main to int\nret f g\nend\n",
            "good": "global g uchar 4\nfn f to int\nret int get g 0\nend\nfn main to int\nret f\nend\n",
        },
        {
            "id": "err20_readonly_text",
            "code": 20,
            "kind": "source",
            "desc": "put into read-only text array",
            "bad": "text s \"hi\"\nfn main to int\nput s 0 uchar 65\nret 0\nend\n",
            "good": "fn main to int\ns = new uchar 2 0\nput s 0 uchar 65\nret int get s 0\nend\n",
        },
        {
            "id": "err21_const_index_oob",
            "code": 21,
            "kind": "source",
            "desc": "constant array index out of bounds",
            "bad": "fn main to int\na = new uchar 4 0\nret int get a 4\nend\n",
            "good": "fn main to int\na = new uchar 4 0\nret int get a 3\nend\n",
        },
        {
            "id": "err22_bad_text_escape",
            "code": 22,
            "kind": "source",
            "desc": "unsupported escape sequence in text literal",
            "bad": "text s \"bad\\x\"\nfn main to int\nret 0\nend\n",
            "good": "text s \"ok\\n\"\nfn main to int\nret 0\nend\n",
        },
        {
            "id": "err23_size_capacity",
            "code": 23,
            "kind": "source",
            "desc": "global array exceeds 16777216-element limit",
            "bad": "global big uchar 16777217\nfn main to int\nret 0\nend\n",
            "good": "global big uchar 1024\nfn main to int\nret 0\nend\n",
        },
        {
            "id": "err25_target_hostword",
            "code": 25,
            "kind": "source",
            "desc": "Linux host word write used under target a64efi",
            "bad": "target a64efi\ntext s \"a\"\nfn main to int\nk = write 1 s 0 1\nret 0\nend\n",
            "good": "fn main to int\ntext_ok = int 0\nret text_ok\nend\n",
        },
        {
            "id": "err26_bad_memory_max",
            "code": 26,
            "kind": "env",
            "desc": "malformed OMC_MEMORY_MAX environment variable",
            "bad": "fn main to int\nret 0\nend\n",
            "good": "fn main to int\nret 0\nend\n",
            "env": {"OMC_MEMORY_MAX": "abc"},
        },
        {
            "id": "err27_fresh_uninit_read",
            "code": 27,
            "kind": "source",
            "desc": "OM-2 fresh scratch array read before write",
            "bad": "om2\nfn f s edit uchar 4 fresh to int\nret int get s 0\nend\nfn main to int\na = new uchar 4 0\nret f edit a\nend\n",
            "good": "om2\nfn f s edit uchar 4 fresh to int\nput s 0 uchar 1\nret int get s 0\nend\nfn main to int\na = new uchar 4 0\nret f edit a\nend\n",
        },
        {
            "id": "err28_seal_outside_ctor",
            "code": 28,
            "kind": "source",
            "desc": "OM-2 abstract type sealed outside NAME+mk constructor",
            "bad": "om2\nabstract Tok uint\nfn main to int\nt = seal Tok uint 1\nret int open t\nend\n",
            "good": "om2\nabstract Tok uint\nfn Tokmk v uint to Tok\nret seal Tok v\nend\nfn main to int\nt = Tokmk uint 1\nret int open t\nend\n",
        },
        {
            "id": "err29_layout_after_fn",
            "code": 29,
            "kind": "source",
            "desc": "OM-2 layout declared after first fn",
            "bad": "om2\nfn main to int\nret 0\nend\nlayout Hdr 4\nfield x uint at 0 little\nend\n",
            "good": "om2\nlayout Hdr 4\nfield x uint at 0 little\nend\nfn main to int\nret 0\nend\n",
        },
        {
            "id": "err30_impure_contract",
            "code": 30,
            "kind": "source",
            "desc": "OM-2 requires clause calls a function (must be pure)",
            "bad": "om2\nfn helper to bool\nret true\nend\nfn f x int to int\nrequires helper\nret x\nend\nfn main to int\nret f int 1\nend\n",
            "good": "om2\nfn f x int to int\nrequires ge x 0\nret x\nend\nfn main to int\nret f int 1\nend\n",
        },
    ]

    if include_err24:
        specs.append(
            {
                "id": "err24_branch_range",
                "code": 24,
                "kind": "generated",
                "desc": "branch displacement > 1 MiB inside single loop (split into helper fn)",
                "bad": (
                    "fn main to int\nx = ulong 0\nc = true\nwhile c bound 1\n"
                    + ("x = add x 1\n" * 270000)
                    + "c = false\nend\nret int and x 1\nend\n"
                ),
                "bad_display": (
                    "fn main to int\nx = ulong 0\nc = true\nwhile c bound 1\n"
                    "note 270000 repeated x = add x 1 lines (>1 MiB branch)\n"
                    "c = false\nend\nret int and x 1\nend\n"
                ),
                "good": (
                    "fn step x ulong to ulong\nret add x 270000\nend\n"
                    "fn main to int\nx = step ulong 0\nret int and x 1\nend\n"
                ),
            }
        )
    return specs


def compile_with_omc(omc: Path, src: str, trigger: Optional[str] = None, env_extra: Optional[dict] = None) -> Tuple[int, str]:
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    if trigger == "stdin_dir":
        fd = os.open("/tmp", os.O_RDONLY)
        try:
            p = subprocess.run([str(omc)], stdin=fd, capture_output=True, env=env, timeout=15)
        finally:
            os.close(fd)
    elif trigger == "stdout_ro":
        fd = os.open("/dev/null", os.O_RDONLY)
        try:
            p = subprocess.run([str(omc)], input=src.encode("utf-8"), stdout=fd, stderr=subprocess.PIPE, env=env, timeout=15)
        finally:
            os.close(fd)
    else:
        p = subprocess.run([str(omc)], input=src.encode("utf-8"), capture_output=True, env=env, timeout=15)
    return p.returncode, p.stderr.decode("utf-8", errors="replace").strip()


def generate_verified_refusals(omc: Path, include_err24: bool = False) -> List[dict]:
    """Compile every refusal-repair spec against real omc and assert exact error code + valid fix."""
    results = []
    for sp in refusal_specs(include_err24=include_err24):
        rc_bad, err_bad = compile_with_omc(omc, sp["bad"], trigger=sp.get("trigger"), env_extra=sp.get("env"))
        if rc_bad != sp["code"]:
            raise RuntimeError(
                f"Refusal spec {sp['id']} expected rc={sp['code']}, got rc={rc_bad} stderr={err_bad!r}"
            )
        rc_good, err_good = compile_with_omc(omc, sp["good"])
        if rc_good != 0:
            raise RuntimeError(
                f"Repair spec {sp['id']} failed to compile: rc={rc_good} stderr={err_good!r}"
            )
        results.append(
            {
                "id": sp["id"],
                "code": sp["code"],
                "kind": sp["kind"],
                "desc": sp["desc"],
                "omc_stderr": err_bad,
                "bad": sp.get("bad_display", sp["bad"]),
                "good": sp["good"],
                "sha256": sha256_bytes((sp["id"] + "\n" + sp["good"]).encode("utf-8")),
            }
        )
    return results


def extract_fn_examples(text: str, rel_path: str, max_examples: int = 8) -> List[Tuple[str, str]]:
    """Extract (prompt, completion) pairs from clean .om source at fn boundaries."""
    lines = text.splitlines()
    examples: List[Tuple[str, str]] = []
    i = 0
    n = len(lines)
    while i < n and len(examples) < max_examples:
        line = lines[i]
        if line.startswith("fn ") or line.startswith("export fn "):
            # Include up to 2 preceding note lines as context
            start = i
            while start > 0 and i - start < 2 and lines[start - 1].startswith("note "):
                start -= 1
            prompt = f"note file {Path(rel_path).name}\n" + "\n".join(lines[start : i + 1]) + "\n"
            # Scan until matching top-level end
            depth = 1
            j = i + 1
            while j < n and depth > 0:
                s = lines[j].strip()
                if s.startswith(("if ", "while ", "for ")):
                    depth += 1
                elif s == "end":
                    depth -= 1
                j += 1
            body = "\n".join(lines[i + 1 : j]) + "\n"
            if 10 <= len(body) <= 700 and depth == 0:
                examples.append((prompt, body))
            i = j
        else:
            i += 1
    return examples


def is_held_out(content_sha256: str, held_mod: int = 10) -> bool:
    """Deterministic split by SHA-256 hash: ~10% held-out, zero content leakage."""
    return (int(content_sha256[:8], 16) % held_mod) == 0


def encode_bpe_batch(ollm: Path, merges: Path, texts: List[str], vocab: int = 4096) -> List[List[int]]:
    """Encode a list of UTF-8 strings with ollm bpeenc via a NUL-separated temp file."""
    if not texts:
        return []
    with tempfile.TemporaryDirectory(prefix="om-bpe-") as tmp:
        in_path = Path(tmp) / "in.txt"
        out_path = Path(tmp) / "out.tok"
        # Use NUL byte (token 0) as exact record separator
        joined = b"\x00".join(t.replace("\x00", "").encode("utf-8", errors="ignore") for t in texts)
        in_path.write_bytes(joined)
        p = subprocess.run(
            [str(ollm), "bpeenc", str(merges), str(vocab), str(in_path), str(out_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if p.returncode != 0:
            raise RuntimeError(f"ollm bpeenc failed (rc={p.returncode}): {p.stderr}")
        raw = out_path.read_bytes()
        toks = list(struct.unpack("<" + "H" * (len(raw) // 2), raw))
    # Split on token 0 (NUL)
    records: List[List[int]] = []
    cur: List[int] = []
    for t in toks:
        if t == 0:
            records.append(cur)
            cur = []
        else:
            cur.append(t)
    records.append(cur)
    if len(records) != len(texts):
        raise RuntimeError(f"bpeenc record count mismatch: expected {len(texts)}, got {len(records)}")
    return records


def pack_aligned_masked(
    pairs: List[Tuple[str, str]], ollm: Path, merges: Path, ctx: int = T_CTX
) -> Tuple[bytes, bytes, int, int]:
    """Pack (prompt, completion) pairs into BOS-aligned ctx-token windows with 1-byte-per-token mask.

    Mask byte = 0 on BOS, prompt, and padding tokens; 1 on completion tokens.
    Appends 1 trailing 0 token + 0 mask byte so obrow(w * T) reads T+1 tokens cleanly.
    """
    if not pairs:
        return b"", b"", 0, 0
    prompts = [p for p, _ in pairs]
    comps = [c for _, c in pairs]
    p_toks = encode_bpe_batch(ollm, merges, prompts)
    c_toks = encode_bpe_batch(ollm, merges, comps)

    blocks_t: List[List[int]] = []
    blocks_m: List[List[int]] = []
    blk_t: List[int] = []
    blk_m: List[int] = []
    used_examples = 0

    for pt, ct in zip(p_toks, c_toks):
        ex_t = [0] + pt + ct
        ex_m = [0] + ([0] * len(pt)) + ([1] * len(ct))
        if len(ex_t) >= ctx or len(ct) == 0:
            continue
        used_examples += 1
        if len(blk_t) + len(ex_t) > ctx:
            pad = ctx - len(blk_t)
            blk_t.extend([0] * pad)
            blk_m.extend([0] * pad)
            blocks_t.append(blk_t)
            blocks_m.append(blk_m)
            blk_t = list(ex_t)
            blk_m = list(ex_m)
        else:
            blk_t.extend(ex_t)
            blk_m.extend(ex_m)

    if blk_t:
        pad = ctx - len(blk_t)
        blk_t.extend([0] * pad)
        blk_m.extend([0] * pad)
        blocks_t.append(blk_t)
        blocks_m.append(blk_m)

    flat_t: List[int] = []
    flat_m: List[int] = []
    for bt, bm in zip(blocks_t, blocks_m):
        flat_t.extend(bt)
        flat_m.extend(bm)
    if flat_t:
        flat_t.append(0)
        flat_m.append(0)

    tok_bytes = struct.pack("<" + "H" * len(flat_t), *flat_t)
    msk_bytes = bytes(flat_m)
    return tok_bytes, msk_bytes, len(blocks_t), used_examples


def cmd_audit(args: argparse.Namespace) -> int:
    report = scan_workspace(Path(args.workspace).expanduser())
    print(f"Workspace: {args.workspace}")
    t = report["total_all_dirs"]
    u = report["unique_dedup"]
    print(f"Total (.om across all dirs): {t['files']} files, {t['loc']} LOC, {t['bytes']} bytes (dups={t['duplicates']})")
    print(
        f"Unique (SHA-256 dedup):      {u['files']} files, {u['loc']} LOC, {u['bytes']} bytes "
        f"(clean positive: {u['clean_files']} files, {u['clean_loc']} LOC)"
    )
    print("\nBy audit category (SHA-256 dedup):")
    print(f"{'CATEGORY':16s} {'FILES':>6s} {'LOC':>9s} {'CLEAN_F':>8s} {'CLEAN_LOC':>10s}")
    for cat in ("om-core", "ollm", "gb20b-mmio", "aienux-kernel", "libos-rpc"):
        c = report["by_category"].get(cat, {"files": 0, "loc": 0, "clean_files": 0, "clean_loc": 0})
        print(f"{cat:16s} {c['files']:6d} {c['loc']:9d} {c['clean_files']:8d} {c['clean_loc']:10d}")
    print("\nBy specialist bundle (SHA-256 dedup):")
    print(f"{'BUNDLE':16s} {'FILES':>6s} {'LOC':>9s} {'CLEAN_F':>8s} {'CLEAN_LOC':>10s}")
    for b in BUNDLES:
        c = report["by_bundle"].get(b, {"files": 0, "loc": 0, "clean_files": 0, "clean_loc": 0})
        print(f"{b:16s} {c['files']:6d} {c['loc']:9d} {c['clean_files']:8d} {c['clean_loc']:10d}")

    if args.json_out:
        out_obj = {k: v for k, v in report.items() if k != "records"}
        Path(args.json_out).write_text(json.dumps(out_obj, indent=2) + "\n")
        print(f"\nWrote audit summary to {args.json_out}")
    return 0


def cmd_refusals(args: argparse.Namespace) -> int:
    omc = Path(args.omc).expanduser()
    pairs = generate_verified_refusals(omc, include_err24=args.include_err24)
    codes = sorted({p["code"] for p in pairs})
    print(f"Verified {len(pairs)} live omc refusal-repair pairs covering {len(codes)} error codes: {codes}")
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8") as f:
            for p in pairs:
                f.write(json.dumps(p) + "\n")
        print(f"Wrote {out}")
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    workspace = Path(args.workspace).expanduser()
    out_dir = Path(args.out_dir).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    omc = Path(args.omc).expanduser()
    ollm = Path(args.ollm).expanduser() if args.ollm else None
    merges = Path(args.merges).expanduser() if args.merges else None
    base_ck = Path(args.base_ck).expanduser() if args.base_ck else None

    report = scan_workspace(workspace)
    refusals = generate_verified_refusals(omc, include_err24=args.include_err24)

    summary = {"bundles": {}, "refusal_pairs": len(refusals), "refusal_codes": sorted({r["code"] for r in refusals})}

    for bundle in BUNDLES:
        train_pairs: List[Tuple[str, str]] = []
        held_pairs: List[Tuple[str, str]] = []
        train_hashes = set()
        held_hashes = set()

        recs = [r for r in report["records"] if r["bundle"] == bundle and not r["negative_control"]]
        for r in recs:
            try:
                text = Path(r["path"]).read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            exs = extract_fn_examples(text, r["rel"], max_examples=args.max_per_file)
            if not exs:
                continue
            if is_held_out(r["sha256"]):
                held_hashes.add(r["sha256"])
                held_pairs.extend(exs)
            else:
                train_hashes.add(r["sha256"])
                train_pairs.extend(exs)

        # Mix live omc refusal-repair pairs into om-core (deterministically split)
        if bundle == "om-core":
            for rp in refusals:
                prompt = (
                    f"note fix omc refusal ({rp['omc_stderr']})\n"
                    f"note broken:\n{rp['bad']}note fixed:\n"
                )
                comp = rp["good"]
                if is_held_out(rp["sha256"]):
                    held_hashes.add(rp["sha256"])
                    held_pairs.append((prompt, comp))
                else:
                    train_hashes.add(rp["sha256"])
                    train_pairs.append((prompt, comp))

        # Assert zero content leakage between train and held-out
        overlap = train_hashes.intersection(held_hashes)
        if overlap:
            raise AssertionError(f"Leakage detected in bundle {bundle}: {len(overlap)} overlapping hashes")

        # Cap if requested for fast smoke builds
        if args.max_examples > 0:
            train_pairs = train_pairs[: args.max_examples]
            held_pairs = held_pairs[: max(20, args.max_examples // 5)]

        # Write JSONL splits
        for split_name, split_pairs in (("train", train_pairs), ("held", held_pairs)):
            jpath = out_dir / f"{bundle}_{split_name}.jsonl"
            with jpath.open("w", encoding="utf-8") as f:
                for pr, co in split_pairs:
                    f.write(json.dumps({"prompt": pr, "completion": co}) + "\n")

        binfo = {
            "train_files": len(train_hashes),
            "held_files": len(held_hashes),
            "train_examples": len(train_pairs),
            "held_examples": len(held_pairs),
            "leakage_hashes": 0,
        }

        # Optional BPE tokenization + fcachem verification
        if ollm and merges and ollm.is_file() and merges.is_file():
            tr_tok, tr_msk, tr_wins, tr_used = pack_aligned_masked(train_pairs, ollm, merges)
            he_tok, he_msk, he_wins, he_used = pack_aligned_masked(held_pairs, ollm, merges)
            tr_tok_p = out_dir / f"{bundle}_aligned.tok"
            tr_msk_p = out_dir / f"{bundle}_aligned.msk"
            he_tok_p = out_dir / f"{bundle}_held.tok"
            he_msk_p = out_dir / f"{bundle}_held.msk"
            tr_tok_p.write_bytes(tr_tok)
            tr_msk_p.write_bytes(tr_msk)
            he_tok_p.write_bytes(he_tok)
            he_msk_p.write_bytes(he_msk)
            binfo.update(
                {
                    "train_windows": tr_wins,
                    "train_packed_examples": tr_used,
                    "held_windows": he_wins,
                    "held_packed_examples": he_used,
                }
            )
            if args.verify_fcachem and base_ck and base_ck.is_file() and tr_wins >= 1:
                hc_path = out_dir / f"{bundle}_verify.hc"
                w_check = min(2, tr_wins)
                p = subprocess.run(
                    [str(ollm), "fcachem", str(base_ck), str(tr_tok_p), str(tr_msk_p), str(w_check), str(hc_path)],
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
                if p.returncode != 0:
                    raise RuntimeError(f"fcachem verification failed for {bundle} (rc={p.returncode}): {p.stderr}")
                binfo["fcachem_verify"] = p.stdout.strip()
                hc_path.unlink(missing_ok=True)

        summary["bundles"][bundle] = binfo
        print(f"[{bundle:14s}] {json.dumps(binfo)}")

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Wrote manifest to {manifest_path}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Build .om specialist bundle datasets and live omc refusal pairs.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pa = sub.add_parser("audit", help="Audit .om corpus across workspace")
    pa.add_argument("--workspace", default=str(Path.home() / "workspace"))
    pa.add_argument("--json-out", default="")
    pa.set_defaults(func=cmd_audit)

    pr = sub.add_parser("refusals", help="Generate live omc refusal-repair pairs (errors 1..30)")
    pr.add_argument("--omc", default=str(Path.home() / ".local/bin/omc"))
    pr.add_argument("--include-err24", action="store_true")
    pr.add_argument("--out", default="")
    pr.set_defaults(func=cmd_refusals)

    pb = sub.add_parser("build", help="Build leak-free bundle splits, tokenize, and optionally verify fcachem")
    pb.add_argument("--workspace", default=str(Path.home() / "workspace"))
    pb.add_argument("--omc", default=str(Path.home() / ".local/bin/omc"))
    pb.add_argument("--out-dir", required=True)
    pb.add_argument("--ollm", default=str(Path.home() / ".local/bin/ollm"))
    pb.add_argument("--merges", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/merges4096.bin"))
    pb.add_argument("--base-ck", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/omega-v2.ck"))
    pb.add_argument("--verify-fcachem", action="store_true")
    pb.add_argument("--include-err24", action="store_true")
    pb.add_argument("--max-per-file", type=int, default=6)
    pb.add_argument("--max-examples", type=int, default=0, help="0 = all; >0 caps examples per bundle")
    pb.set_defaults(func=cmd_build)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
