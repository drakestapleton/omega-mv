# NG bench pre-registration: baseline omc vs gcc on GB10 (lane ng-bench)

Written 2026-11-07 ~08:05Z, committed and its sha256 posted on `~/handoffs/BOARD.md` before the first timed row.
Nothing in this file changes after that post; a deviation is written into BASELINE.md as a deviation.

## What is measured

How long the programs that today's Omega compiler (omc) produces take to run, compared with the same programs
written in C and compiled by gcc, on both GB10 CPU core types. This is the baseline NG must beat. No hypothesis is
tested; the decision rule below is fixed now for the later NG A/B runs that use the same harness.

## Pins

| item | pin |
| --- | --- |
| repository | aien-dev/omega-mv, kernels frozen at branch `ng/bench-baseline` commit `6d348a1b3f6da1054ada9d340819b488fe5a695f` (re-authored copy of `f446201b`, identical tree), harness at `d2d1715636394349bd2554be39ee6d4037d8f346` |
| omc | `seed/out/omc` at main `943d955531b9d4d9f70deb41756c0b46441dd5e0`, sha256 `5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df` |
| harness | `seed/ng/ngbench.om` sha256 `19be4ff690a949fbdadb5e5fcb4e45faac668f259c9184b66ab1684f407e77b6`; omc output sha256 `1a67a09d7a03a04cb168e33086db40324bf80055e97156085c1e1872b3f47e07` |
| gcc | Ubuntu 13.3.0-6ubuntu2~24.04.1; sha256: `/usr/bin/aarch64-linux-gnu-gcc-13` `a20520ee21543f243d40636a9181a142c45ecd989de31ab86b99a8ea5ada870d`, `/usr/libexec/gcc/aarch64-linux-gnu/13/cc1` `64edfe466dd55c4216c006e9fa237af012e4974281dd4d11640aacfc3b3693af`, `/usr/bin/aarch64-linux-gnu-as` (binutils 2.42-4ubuntu2.10) `1ffda50efb6d91b6b05ef933aced099595c36577594c0296c91161f2d13db374`, `/usr/bin/aarch64-linux-gnu-ld.bfd` `1e4d3369b76845fa8e099b83513bf28f6f722e046f9b2cde1378c9e27f96d19c`; libc6-dev 2.39-0ubuntu8.9 |
| kernels | `seed/ng/bench/kernels/*.om`, `*.c`, `want/*.sha256`; sources and hashes in `kernels/PROVENANCE.md` |

## Arms

| arm | build (cwd = omega-mv checkout, K = case) | role |
| --- | --- | --- |
| `omc` | `taskset -c 1 nice -n 10 seed/out/omc < seed/ng/bench/kernels/K.om > DIR/bin/omc/K; chmod 755` | measured |
| `gccO2` | `taskset -c 1 nice -n 10 gcc -O2 -static -o DIR/bin/gccO2/K seed/ng/bench/kernels/K.c` | referee, denominator |
| `gccO2aa` | `cp DIR/bin/gccO2/K DIR/bin/gccO2aa/K` (same bytes, second label) | A/A timing control |
| `gccO3n` | `taskset -c 1 nice -n 10 gcc -O3 -march=native -static -o DIR/bin/gccO3n/K seed/ng/bench/kernels/K.c` | information only |

Recorded before the run: on this host gcc 13.3 does not know the X925 or A725 cores, and `-march=native` resolves
to no `-march`/`-mcpu` at all (the `cc1` command line of `gcc -O3 -march=native -v` carries only `-mlittle-endian
-mabi=lp64 -O3`), so `gccO3n` is plain `-O3` for generic ARMv8-A. Ubuntu's gcc also adds `-D_FORTIFY_SOURCE=3
-fstack-protector-strong -fstack-clash-protection` by default; the gcc arms carry those.

Cases (15): `arith branch fib38 isort leafcall matmul sieve fib40 sort bcopy sha chacha linear` (omc and all gcc
arms), `x25519` (omc only: no C referee) and `omcself` (omc only: binary `DIR/bin/omc/omcself` = `seed/out/omc`,
stdin `DIR/in/omcself` = `seed/omc/omc.om` at 943d9555, want = its own sha256 `5f90edea…`, the fixpoint).
`DIR/manifest.sha256` = `ngbench sum bin/*/*` run inside DIR after the builds; `DIR/want/` = copy of
`kernels/want/*.sha256`.

## Cores, locks and rounds

| round | core | type (MIDR) | command prefix |
| --- | --- | --- | --- |
| X925 | 9 (cluster 0-9) | 0x410fd851 | `flock -x -w 3600 ~/handoffs/hive/queen/pool-8-9.lock taskset -c 9 nice -n 10` |
| A725 | 11 (cluster 10-19) | 0x410fd871 | `flock -x -w 3600 ~/handoffs/hive/queen/pool-10-11.lock taskset -c 11 nice -n 10` |

Both cores run the `performance` governor (max 3.9 GHz on cpu9, 2.808 GHz on cpu11). Never cores 3, 7 or 15.
Each round is one invocation:
`ngbench run 31 3 DIR omc gccO2 gccO2aa gccO3n -- arith branch fib38 isort leafcall matmul sieve fib40 sort bcopy sha chacha linear x25519 omcself`
that is 3 warm blocks (declared, discarded from all statistics) then 31 measured blocks. Inside a block every case
runs every present arm twice in palindromic order, the start arm rotating by block (see the controls evidence,
nc9). The lock is held only for the invocation and released after; the release is posted on the BOARD.

At each round start and end, recorded into the evidence directory: `cat /proc/loadavg`; the processes on the
timed core's cluster (`ps -eo pid,psr,pcpu,stat,comm` filtered to psr in the cluster); `lscpu`; the MIDR file of
the timed core; `hostname`; `uname -a`; `gcc --version`; sha256 of omc, ngbench and every arm binary (the
manifest). ngbench also writes `/proc/loadavg` in its H, L (every block) and E rows.

## Metric

Primary: wall nanoseconds per run (ngbench T row field 6: `monons` before fork to after waitpid).
For a case c, a core and a measured block b:

  r(b) = (wall of the two `omc` runs in b) / (wall of the two `gccO2` runs in b)

Reported per case per core: the median of r over the 31 blocks with a distribution-free 95% confidence interval
from the order statistics [r(10), r(22)] of the sorted ratios. Coverage, computed by Wolfram:
`n = 31; k = Max[Select[Range[1, 15], CDF[BinomialDistribution[n, 1/2], # - 1] <= 0.025 &]]; {k, n + 1 - k, N[1 - 2 CDF[BinomialDistribution[n, 1/2], k - 1], 6]}`
-> `{10, 22, 0.970551}`.
The same statistic for `gccO3n`/`gccO2` (information) and `gccO2aa`/`gccO2` (A/A control).
Summary per core: the geometric mean of the 13 per-case medians of omc/gccO2 (descriptive, no interval).
`omcself` (the omc self-compile) and `x25519`: per-block mean of the two omc walls, median with [x(10), x(22)].
Secondary: the in-process ns that the 7 OMC-EFF kernels print on stderr (T row field 9), same ratio statistic.

All arithmetic (sorting, medians, ratios, geometric means, coverage) is done in the Wolfram MCP evaluator; each
query and result is saved in the evidence directory.

## Validity rules (fixed now)

1. A round is valid only if ngbench exits 0 and its S row reads `fail=0 refused=0`: every timed run had exit status
   0 and the stdout sha256 of its want, and every binary's sha256 matched the manifest before and after timing.
2. A/A control: for each refereed case, `gccO2aa`/`gccO2` passes if its 95% interval contains 1 or its median lies
   in [0.99, 1.01]. If more than 1 of the 13 cases fails, the round is flagged NOISY; it is rerun once, and both
   rounds are reported.
3. An invalid or noisy round is never silently dropped: its rows stay in the evidence and BASELINE.md says why it
   was rerun.
4. No case, block or run is removed after the fact. Warm blocks are the only discarded rows, and they are declared
   above.

## Decision rule for later A/B runs (NG vs omc, NG vs gcc) on this harness

For arm X against arm Y on a case and core, with r(b) = X walls / Y walls per block and the interval above:
X is faster if the interval's upper end is below 1; X is slower if its lower end is above 1; otherwise no
difference is detected. A claimed speedup is the median and its interval, never a single run, and is CHIP_TESTED
on that core type only. A result on these 15 frozen cases is repeated on the held-out inputs below before it is
called QUALIFIED.

## Held-out inputs (D9), frozen before any NG tuning

14 held-out variants, one per kernel (different sizes, seeds, moduli or patterns; omc and gcc -O2 stdout agree on
all 13 with a C twin; fib37 = 24157817 and fib39 = 63245986 checked by Wolfram `{Fibonacci[37], Fibonacci[39]}`),
kept outside the repository in `~/handoffs/hive-ng/bench/heldout/` (mode 0700) so that NG lanes do not tune on
them. Commitment: `MANIFEST.sha256` there (41 lines: sha256 of 14 `.om`, 13 `.c`, 14 `want/*.sha256`) has sha256
`e3df0b8c6cf24d9dbc01bd74b85c70087cd7b3a0c98792d7a4fc334161645dc6`. They are revealed (committed) when the NG
M1+M2 slice freezes its passes, and a reviewer checks the files against this hash.

## Known limits, stated before the run

- Cycle and instruction counters are not available: `kernel.perf_event_paranoid` is 4 on the Spark. Time only.
- `x25519` and `omcself` have no C referee, so they give omc's absolute time only.
- The MLP row is one linear layer (`linear`, M/K/N = 64/256/256, from omega-bridge d8174edd) with a C twin; PyTorch
  is not installed, so there is no PyTorch arm. clang is not installed, so there is no clang arm.
- The Spark is shared. Other agents may run on the other cores of the cluster during a round; that load is recorded,
  not prevented.
