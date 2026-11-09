# PREREG: the M3 payoff map, hand-edited pass arms (lane ng-bench)

Committed and posted on the BOARD before any timing row of this round. Task: omp-queen-ng 2026-11-07T11:31:44Z
("for each of the 13 kernels, read omc's disassembly vs gcc -O2 and attribute the gap to causes, with a
measured estimate where a hand-edited binary can test it"). Base: Radicle main `da8b7e66`. The harness,
metric, interval and clean-block rule are the ones of `PREREG.md` and `PREREG-contamination.md`, unchanged.

## What is measured

For 9 kernels, omc's own binary is edited by hand into a ladder of arms, each rung adding one compiler pass
(or one bundle, named below) to the rung before it. Each rung is what that pass would emit on this code; the
edit touches only the hot function or loop, everything else is omc's bytes. A rung's step factor is the time
of the rung over the time of the rung below it, on the same block. The arms are models of passes, built by
hand; they are not NG output.

| kernel | ladder (rung = previous + pass) | pass names used in the ranking |
|---|---|---|
| bcopy | omc, ngL, ngB, ngV | LICM+ROT, BCE, VEC |
| arith | omc, ngL, ngM | LICM+ROT, DIV |
| branch | omc, ngL, ngC | LICM+ROT, IFC |
| isort | omc, ngL, ngB | LICM+ROT, BCE |
| sort | omc, ngL, ngB | LICM+ROT, BCE |
| matmul | omc, ngL, ngB | LICM+ROT, BCE |
| sieve | omc, ngL, ngB | LICM+ROT, BCE |
| linear | omc, ngL, ngB, ngF | LICM+ROT, BCE, ISEL |
| leafcall | omc, ngR, ngI | CALL, INL |

Pass meanings (the spec files in `hand/` state, per kernel, exactly what each rung changes and why it is legal):

- LICM+ROT: constants, limits and array bases computed once before the loop instead of every pass; every loop
  tested at the bottom (one branch per pass); immediates folded into CMP/TST/ADD forms; boolean conditions
  lowered to branches instead of CSET/AND (`and` operands here are side-effect free). Bounds checks and `while`
  iteration-bound counters are kept.
- BCE: bounds checks and `while` iteration-bound counters removed where a range argument (stated in the spec)
  proves they cannot fire; for `linear`, the per-iteration checks become one range check before the loop.
- VEC: 16 bytes per pass with SIMD (LDR Q, REV64+EXT, EOR, STR Q).
- DIV: remainder by a constant through a multiply by its reciprocal (UMULH); the constant is gcc's.
- IFC: if-conversion, both Collatz branches and the max update become CSEL.
- CALL: register allocation across the call (no per-call frame, stack check, spill and reload).
- INL: the callee inlined.
- ISEL: f32 loads straight into FP registers (LDR S) instead of LDR W + FMOV.

Control arm `ngA` on every kernel: a byte-identical copy of omc's binary (A/A control, judged like `gccO2aa` in
PREREG.md rule 2: its interval against omc contains 1 or its median lies in [0.99, 1.01]).
Context arm `gccO2`: the baseline gcc -O2 binary.

## Arms and binaries

Built by `seed/ng/bench/hand.om` (this commit; compiled by `seed/out/omc` sha256 `cfd96b48…0d8a` to `hand`
sha256 `f352309bee8789f37cb494f604042ba20dc695174cd9dfef2c742aa6de41a9d3`) from three inputs per arm:

1. `hand/K-V.spec`: the edit (directives `@old` check omc's original words, `@at`, `@word`, `@nop`), one
   instruction per case line with the expected disassembly after `|`.
2. `hand/K-V.words`: the instruction words, encoded by the ng-a64 lane's encoder `ng a64-enc` (omega-mv
   ng/a64-m2 `9c1bc18c2ed270010ac687cda9182436e66f192d`, `seed/ng/src/{ir,a64,main}.om`, built by omc
   cfd96b48 to `ng` sha256 `7221cc0d4a622db74975418bf5cace5789995516259cf77768c7b186e578a510`). Words the
   encoder has no form for (the 6 SIMD words of bcopy-V) are literal `@word` lines.
3. omc's binary of the kernel (`seed/out/omc` cfd96b48 and the baseline's 5f90edea emit identical bytes for
   all 9 kernels).

`hand splice SPEC WORDS IN OUT` writes the arm; `objdump -D -b binary -m aarch64 --adjust-vma=0x400000 OUT |
hand check SPEC` must pass (every written word's disassembly equals the spec's text; objdump is the referee);
the arm's stdout must have the kernel's `kernels/want/K.sha256`. All 20 arms pass all three (smoke on core 1,
not a timing). The 47 binaries of the round, with their sha256, are `hand/payoff-manifest.sha256`.

## Round

Fixture DIR `/tmp/ngb/payrun`: `bin/ARM/CASE` as in the manifest, `want/` copied from `kernels/want/`.
One invocation per core, ngbench v2 (binary sha256 `ba6351527ef844836776dbaff44b782c5957225f35a172205ae4d77904ff0200`):

`ngbench run 31 3 DIR omc ngA ngL ngB ngV ngM ngC ngR ngI ngF gccO2 -- bcopy arith branch isort sort leafcall matmul sieve linear`

| round | core | prefix |
|---|---|---|
| X925 | 9 | `flock -x -w 3600 ~/handoffs/hive/queen/pool-8-9.lock taskset -c 9 nice -n 10` |
| A725 | 11 | `flock -x -w 3600 ~/handoffs/hive/queen/pool-10-11.lock taskset -c 11 nice -n 10` |

Absent arm/case pairs are skipped by ngbench. Start/end records as in PREREG.md. Rows go to
`evidence/<ts>-payoff/{x925,a725}/rows.txt`, unedited.

## Metric and statistics (fixed now)

Per block b, case c: r(X/Y, b) = (sum of X's two walls) / (sum of Y's two walls). Reported: median and the
distribution-free 95% interval [r(k), r(n+1-k)] (PREREG.md; n = 31 gives k = 10), on all measured blocks and on
the clean blocks (PREREG-contamination.md; the verdict uses the clean blocks when at least 21 remain).

Per case and core: every rung against omc, every rung against the rung below it (the step factor), every rung
against gccO2, ngA/omc.

Ranking, per core type: for pass P, the measured step factors s(P, k) on the kernels where P has a rung; for every
other of the 13 baseline kernels the factor is 1. Expected geomean gain of P = 1 / (product over the 13 kernels of
s(P, k))^(1/13). Passes are ranked by it. Step factors depend on the ladder order (BCE is measured after
LICM+ROT); that order is part of the result.

## Kernels without a hand ladder in this round

- fib38, fib40: the measured plan-breaker v2 round (`evidence/20261107T0830Z-planbreaker-v2/RESULTS.md`) is cited:
  ngA = CALL (callee-saved convention), ngD = CALL+ALIGN, ngE = CALL + the second recursive call as a loop.
- sha, chacha (and x25519, which has no C referee and is outside the 13): MODELED, labelled so. Method fixed
  now: classify every instruction of the hot function in omc's disassembly into the categories a pass removes
  (bounds-check compare/branch and its limit constant: BCE; constant and address rematerialisation: LICM;
  per-call spill/reload, frame and stack check: CALL), take the fraction p(P) of the hot function's executed
  instructions that P removes, and model the step factor as 1 - e(core) p(P), where e(core) is the median, over
  the measured LICM+ROT and BCE steps of this round, of (1 - step factor) / (fraction of the loop's executed
  instructions that step removed). The removed fractions come from the instruction counts per loop pass in
  the specs and omc's disassembly. All arithmetic in Wolfram.

## Decision rules

- Validity: PREREG.md rules 1, 3, 4; contamination rules of PREREG-contamination.md. A round with any `fail` or
  `refused` row is invalid.
- A/A: more than 1 of the 9 `ngA/omc` controls failing flags the round NOISY; it is rerun once and both are kept.
- A rung is faster than the rung below if its step interval's upper end is below 1; slower if the lower end is
  above 1; otherwise no difference is detected (its factor still enters the geomean, marked).
- Status words: the step factors are CHIP_TESTED on the core type measured, for these frozen inputs and these
  hand-built arms. They are not QUALIFIED (no held-out run: the arms are input-specific binaries) and they are
  not NG results.

## Expectations, stated before the round

From the instruction counts per loop pass (omc vs each rung), every rung is expected to be faster than the rung
below on both cores, with two exceptions where no difference is plausible: matmul (2400-byte column stride,
expected to be memory-bound) and linear ngF (the loop is bound by the FADD latency chain). The core-1 smoke
runs of bcopy were seen while building (omc 964 ms, ngL 720, ngB 272, ngV 42, gccO2 31 ms on a shared core);
they are not evidence.

## Known limits

- Hand arms change code placement as well as instruction count; the plan-breaker D arm showed placement alone
  moving fib38 by 18% on A725. Arms of one kernel are edited in place at omc's address, except arith, whose
  rungs are both rebuilt at a 64-byte-aligned loop head past the end of the file (the M rung does not fit).
- One machine, two core types, time only (no counters: `perf_event_paranoid` = 4).
