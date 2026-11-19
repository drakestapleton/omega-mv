#!/usr/bin/env python3
"""Local M2 CPU `ollm spsamp` + `omc` millisecond compile-retry feedback loop
and `omc` compile latency benchmark.

Demonstrates the local feedback-loop leg:
  generate .om via `ollm spsamp` -> compile with local `omc` -> feed exact `omc`
  stderr refusal back into the next prompt on non-zero exit.

Never executes refused compiler output. Does not touch any GPU.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple


def compile_omc(omc: Path, src: str, timeout: int = 15) -> Tuple[int, str, int, float]:
    """Compile .om source via stdin to omc. Returns (rc, stderr, out_bytes, elapsed_ms)."""
    t0 = time.perf_counter()
    p = subprocess.run(
        [str(omc)],
        input=src.encode("utf-8"),
        capture_output=True,
        timeout=timeout,
    )
    dt_ms = (time.perf_counter() - t0) * 1000.0
    stderr = p.stderr.decode("utf-8", errors="replace").strip()
    out_bytes = len(p.stdout) if p.returncode == 0 else 0
    return p.returncode, stderr, out_bytes, dt_ms


def run_spsamp(
    ollm: Path,
    base_ck: Path,
    pack_sp: Path,
    n_toks: int,
    temp_milli: int,
    prompt: str,
    seed: int,
    merges: Optional[Path] = None,
    timeout: int = 120,
) -> Tuple[int, str, str, float]:
    """Run `ollm spsamp BASE.ck PACK.sp N TEMPMILLI PROMPT SEED [MERGES]`."""
    cmd = [
        str(ollm),
        "spsamp",
        str(base_ck),
        str(pack_sp),
        str(n_toks),
        str(temp_milli),
        prompt,
        str(seed),
    ]
    if merges is not None and merges.is_file():
        cmd.append(str(merges))
    t0 = time.perf_counter()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    dt_ms = (time.perf_counter() - t0) * 1000.0
    return p.returncode, p.stdout, p.stderr.strip(), dt_ms


def extract_om_candidate(raw_output: str, prompt: str) -> str:
    """Extract .om source lines from spsamp output, stripping any leading prompt echo."""
    text = raw_output
    if text.startswith(prompt):
        text = text[len(prompt) :]
    # Keep printable lines; stop at NUL if present
    if "\x00" in text:
        text = text.split("\x00", 1)[0]
    return text.strip() + "\n"


def run_compile_loop(
    ollm: Path,
    base_ck: Path,
    pack_sp: Path,
    omc: Path,
    prompt: str,
    merges: Optional[Path] = None,
    max_retries: int = 3,
    n_toks: int = 64,
    temp_milli: int = 200,
    seed: int = 42,
) -> dict:
    """Execute generate -> compile -> refusal-feedback retry loop."""
    cur_prompt = prompt
    attempts: List[dict] = []
    compiled = False

    for attempt in range(max_retries + 1):
        rc_s, out_s, err_s, samp_ms = run_spsamp(
            ollm=ollm,
            base_ck=base_ck,
            pack_sp=pack_sp,
            n_toks=n_toks,
            temp_milli=temp_milli,
            prompt=cur_prompt,
            seed=seed + attempt,
            merges=merges,
        )
        if rc_s != 0:
            raise RuntimeError(f"ollm spsamp failed (rc={rc_s}): {err_s}")

        cand = extract_om_candidate(out_s, cur_prompt)
        rc_c, err_c, bin_bytes, omc_ms = compile_omc(omc, cand)

        rec = {
            "attempt": attempt,
            "seed": seed + attempt,
            "spsamp_ms": round(samp_ms, 2),
            "omc_ms": round(omc_ms, 3),
            "omc_rc": rc_c,
            "omc_stderr": err_c,
            "bin_bytes": bin_bytes,
            "candidate_preview": cand[:160],
        }
        attempts.append(rec)

        if rc_c == 0:
            compiled = True
            break

        # Feed exact omc refusal back into the next prompt
        cur_prompt = f"{prompt}\nnote omc refusal: {err_c}\nnote fix:\n"

    return {
        "compiled": compiled,
        "attempts_used": len(attempts),
        "max_retries": max_retries,
        "pack": pack_sp.name,
        "attempts": attempts,
    }


def cmd_bench(args: argparse.Namespace) -> int:
    omc = Path(args.omc).expanduser()
    runs = args.runs
    targets: List[Tuple[str, str]] = []

    if args.files:
        for f in args.files:
            p = Path(f).expanduser()
            targets.append((p.name, p.read_text(encoding="utf-8")))
    else:
        # Built-in representative standalone .om units spanning small/medium/large LOC
        small = (
            "note small standalone unit\n"
            "fn main to int\n"
            "x = int 40\n"
            "y = add x 2\n"
            "ret y\n"
            "end\n"
        )
        medium_lines = ["note medium standalone unit (100-line loop + helpers)"]
        for i in range(10):
            medium_lines.append(f"fn h{i} a ulong b ulong to ulong")
            medium_lines.append(f"r = add a b")
            medium_lines.append(f"r = xor r ulong {i + 1}")
            medium_lines.append("ret r")
            medium_lines.append("end")
        medium_lines.append("fn main to int")
        medium_lines.append("acc = ulong 0")
        medium_lines.append("for i ulong 64")
        for i in range(10):
            medium_lines.append(f"acc = h{i} acc i")
        medium_lines.append("end")
        medium_lines.append("ret int and acc 255")
        medium_lines.append("end")
        medium = "\n".join(medium_lines) + "\n"

        large_lines = ["note large standalone unit (564-line compute unit)"]
        for i in range(80):
            large_lines.append(f"fn step{i} x ulong y ulong to ulong")
            large_lines.append("a = add x y")
            large_lines.append("b = xor a shl y 1")
            large_lines.append("c = add b shr x 1")
            large_lines.append(f"ret xor c ulong {i + 7}")
            large_lines.append("end")
        large_lines.append("fn main to int")
        large_lines.append("s = ulong 1")
        for i in range(80):
            large_lines.append(f"s = step{i} s ulong {i + 1}")
        large_lines.append("ret int and s 255")
        large_lines.append("end")
        large = "\n".join(large_lines) + "\n"

        targets = [
            ("small_6loc", small),
            ("medium_67loc", medium),
            ("large_564loc", large),
        ]

    # Warm up once
    compile_omc(omc, targets[0][1])

    results = []
    print(f"{'UNIT':22s} {'LOC':>5s} {'RUNS':>4s} {'MIN_MS':>8s} {'MED_MS':>8s} {'P95_MS':>8s} {'MAX_MS':>8s} {'BIN_B':>8s}")
    for name, src in targets:
        loc = src.count("\n")
        times: List[float] = []
        bin_b = 0
        for _ in range(runs):
            rc, err, b, dt = compile_omc(omc, src)
            if rc != 0:
                raise RuntimeError(f"Benchmark unit {name} failed to compile: rc={rc} {err}")
            times.append(dt)
            bin_b = b
        st = sorted(times)
        p95 = st[min(len(st) - 1, int(0.95 * len(st)))]
        row = {
            "unit": name,
            "loc": loc,
            "runs": runs,
            "min_ms": round(min(times), 3),
            "median_ms": round(statistics.median(times), 3),
            "p95_ms": round(p95, 3),
            "max_ms": round(max(times), 3),
            "bin_bytes": bin_b,
        }
        results.append(row)
        print(
            f"{name:22s} {loc:5d} {runs:4d} {row['min_ms']:8.3f} {row['median_ms']:8.3f} "
            f"{row['p95_ms']:8.3f} {row['max_ms']:8.3f} {bin_b:8d}"
        )

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(results, indent=2) + "\n")
    return 0


def cmd_loop(args: argparse.Namespace) -> int:
    res = run_compile_loop(
        ollm=Path(args.ollm).expanduser(),
        base_ck=Path(args.base_ck).expanduser(),
        pack_sp=Path(args.pack).expanduser(),
        omc=Path(args.omc).expanduser(),
        prompt=args.prompt,
        merges=Path(args.merges).expanduser() if args.merges else None,
        max_retries=args.max_retries,
        n_toks=args.tokens,
        temp_milli=args.temp_milli,
        seed=args.seed,
    )
    print(json.dumps(res, indent=2))
    return 0


def cmd_selftest(args: argparse.Namespace) -> int:
    omc = Path(args.omc).expanduser()
    ollm = Path(args.ollm).expanduser()
    base_ck = Path(args.base_ck).expanduser()
    pack_sp = Path(args.pack).expanduser()
    merges = Path(args.merges).expanduser() if args.merges else None

    # Part A: deterministic refusal -> feedback -> repair check against real omc
    broken = "fn main to int\nx = 5\nret x\nend\n"
    rc0, err0, _, ms0 = compile_omc(omc, broken)
    assert rc0 == 11 and "error 11" in err0, f"Expected error 11, got rc={rc0} err={err0!r}"
    repaired = "fn main to int\nx = int 5\nret x\nend\n"
    rc1, err1, bin1, ms1 = compile_omc(omc, repaired)
    assert rc1 == 0 and bin1 > 0, f"Expected clean compile, got rc={rc1} err={err1!r}"

    # Part B: live ollm spsamp + omc compile-retry loop on M2 CPU
    loop_res = run_compile_loop(
        ollm=ollm,
        base_ck=base_ck,
        pack_sp=pack_sp,
        omc=omc,
        prompt="fn main to int\n",
        merges=merges,
        max_retries=2,
        n_toks=32,
        temp_milli=200,
        seed=7,
    )

    out = {
        "deterministic_refusal_repair": {
            "attempt0_rc": rc0,
            "attempt0_stderr": err0,
            "attempt0_omc_ms": round(ms0, 3),
            "attempt1_rc": rc1,
            "attempt1_bin_bytes": bin1,
            "attempt1_omc_ms": round(ms1, 3),
        },
        "live_spsamp_omc_loop": loop_res,
    }
    print(json.dumps(out, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Local ollm spsamp + omc compile-retry feedback loop & latency bench.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pb = sub.add_parser("bench", help="Benchmark local omc compile latency across representative .om units")
    pb.add_argument("--omc", default=str(Path.home() / ".local/bin/omc"))
    pb.add_argument("--runs", type=int, default=20)
    pb.add_argument("--files", nargs="*", default=[])
    pb.add_argument("--json-out", default="")
    pb.set_defaults(func=cmd_bench)

    pl = sub.add_parser("loop", help="Run live ollm spsamp + omc compile-retry loop")
    pl.add_argument("--ollm", default=str(Path.home() / ".local/bin/ollm"))
    pl.add_argument("--base-ck", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/omega-v2.ck"))
    pl.add_argument("--pack", default=str(Path.home() / "workspace/aien-train-macbook/specialists/packs/omega-code_pro.sp"))
    pl.add_argument("--merges", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/merges4096.bin"))
    pl.add_argument("--omc", default=str(Path.home() / ".local/bin/omc"))
    pl.add_argument("--prompt", default="fn main to int\n")
    pl.add_argument("--max-retries", type=int, default=3)
    pl.add_argument("--tokens", type=int, default=64)
    pl.add_argument("--temp-milli", type=int, default=200)
    pl.add_argument("--seed", type=int, default=42)
    pl.set_defaults(func=cmd_loop)

    ps = sub.add_parser("selftest", help="Verify deterministic refusal-repair + live ollm spsamp -> omc loop")
    ps.add_argument("--ollm", default=str(Path.home() / ".local/bin/ollm"))
    ps.add_argument("--base-ck", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/omega-v2.ck"))
    ps.add_argument("--pack", default=str(Path.home() / "workspace/aien-train-macbook/specialists/packs/omega-code_pro.sp"))
    ps.add_argument("--merges", default=str(Path.home() / "workspace/aien-train-macbook/local-mac/merges4096.bin"))
    ps.add_argument("--omc", default=str(Path.home() / ".local/bin/omc"))
    ps.set_defaults(func=cmd_selftest)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
