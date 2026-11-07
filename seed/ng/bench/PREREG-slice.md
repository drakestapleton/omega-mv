# PREREG: idle-machine rounds R2 (payoff rerun) and S1 (first slice speed) (lane ng-bench)

Committed and posted on the BOARD before any timing row of either round. Task: omp-queen-ng 2026-11-07, after the
payoff correction ("rerun the top payoff ranks when the GPU line and ollm jobs are idle ... record it per block";
"first SLICE SPEED round: ng (front-m3 3353ad67 -> a64-m2 e70c1234, both save forms) vs omc vs gcc -O2 on arith
branch leafcall fib38 fib40 isort sieve sort matmul, X925 core 9 and A725 core 11 under the pool locks, same idle
condition, Wolfram intervals"). Branch ng/bench-slice on ng/bench-payoff `f4d82f3a`. Metric, interval and
contamination rule are those of `PREREG.md` and `PREREG-contamination.md`; what changes is listed here.

## Why

Round 20261107T1155Z (PAYOFF.md) ran beside GPU training legs and ollm serve and train jobs. Its A/A controls
passed, but A/A compares two identical binaries, which a memory-bandwidth load slows alike, so that round is not
contention-cleared. These two rounds run only on an idle machine, and every block records whether it stayed idle.

## Idle condition (both rounds)

Checked by the round driver before it asks for the pool lock, and again inside the lock immediately before ngbench
starts; written to `idle-start.txt` (and `idle-end.txt` after the round):

1. `spark-window status` shows no `window` line (no GB10 or quiet window held) and an empty waiting line;
2. no process on the machine whose name (`/proc/PID/comm`) starts with `ollm` (ollm serve, train, `ollm-gb10`
   gtrain4, ollm-mut-*);
3. `nvidia-smi --query-compute-apps` is recorded (not a condition: the long-running tool-model servers hold GPU
   memory while idle).

If the check fails inside the lock, the lock is released at once and the driver checks again every 60 s. It never
pauses, signals or asks anyone else's job to stop.

Per block: ngbench v3 (this commit, `seed/ng/ngbench.om`) adds to each Y row `ollm=N gpuline=N`, the processes
anywhere on the machine whose name starts with `ollm` or `spark-window`, counted before and after each case of
each block, and to each K row `busy=0|1` (1 when either scan counted one). A (block, case) is clean when
`contaminated=0` and `busy=0`. The verdict for a case uses its clean blocks when at least 21 of 31 remain; with fewer,
that case on that core is CONTENDED (rows kept, no verdict) and the round is rerun when the machine is idle again.

Blind spots, stated now: jobs with other names that load memory (compiles, other benches, the `wpolicy` runs) are
not in the busy count; the cluster's processes at start and end and the load average at every block (L rows) are
recorded for them.

## A/A rule

Each case has `ngA`, a byte-identical copy of omc's binary under a second label. ngA/omc passes when its 95%
interval contains 1 or its median lies in [0.99, 1.01]. More than 1 of a round's 9 A/A controls failing on a core
marks that core's round CONTAMINATED: it is rerun once on an idle machine and both are kept. Every arm is judged
against the same-round ngA.

## Round R2: payoff rerun

Identical to round 20261107T1155Z in everything except the harness version (v3 adds the busy count; timing and the
other rows are unchanged) and the idle condition: the 20 hand arms of `hand/` and omc, ngA, gccO2, fixture checked
against `hand/payoff-manifest.sha256`; `ngbench run 31 3 DIR omc ngA ngL ngB ngV ngM ngC ngR ngI ngF gccO2 --
bcopy arith branch isort sort leafcall matmul sieve linear`, core 9 (X925, pool-8-9.lock) and core 11 (A725,
pool-10-11.lock), `taskset -c CORE nice -n 10`.

Analysis (Wolfram, as PAYOFF.md: the first rung against ngA, later rungs against the rung below, the same e(core)
model and the same ranking with fib cited from planbreaker-v2) over R2's clean blocks. Reported beside round
20261107T1155Z: each step factor of both rounds with its interval, and the ranking of both. R2 replaces the earlier
round in PAYOFF.md when R2's A/A passes and no case is CONTENDED; otherwise both are shown and neither is called
contention-cleared.

## Round S1: first slice speed

Arms, per case:

| arm | what it is |
|---|---|
| omc | the kernel compiled by `seed/out/omc` (sha256 cfd96b48...0d8a; the pinned 5f90edea emits the same bytes) |
| ngA | byte-identical copy of omc's binary (A/A) |
| ngS | Omega NG: `@ng front-ir` (ng-front ng/front-m3 3353ad67) -> ngcheck ACCEPT -> `@ng a64`, the default save form (paired STP/LDP) |
| ngT | the same ΩIR through `@ng a64 split`, the other save form |
| gccO2 | the baseline gcc -O2 binary (evidence/20261107T0830Z-baseline-v2/manifest.sha256) |

Cases: arith branch leafcall fib38 fib40 isort sieve sort matmul, the queen's list (linear is floats, M4; bcopy
also passes through the slice at these pins with the want stdout, but is not in the list and is left out). The
kernel sources are byte-identical to ng-front's copies at 3353ad67.

Pins: ng front built by ngbuild from 3353ad670f60bcd8ed2510c6cd2cb1cf0b7b199e (`ng-front` sha256 78cb2aed...b309),
ng back end from e70c1234658d3256ceff4d0ae1a7954e6047767b (`ng-a64` sha256 04f374f9...0011), ngcheck from
e70c1234 (sha256 b21fd1af...7adc), each built by that commit's own `seed/out/omc` (5f90edea). Every ΩIR unit,
ELF and want is listed in `slice/slice-manifest.sha256`; `slice/mkslice.sh.txt` rebuilds them from the two commits
and the fresh-clone gate checks that the rebuild equals the manifest. All 18 ng binaries give the want stdout
(SHA-256) and exit 0 on core 1 before timing (dry run, 1 block, 90 rows ok).

Command: `ngbench run 31 1 DIR omc ngA ngS ngT gccO2 -- arith branch leafcall fib38 fib40 isort sieve sort matmul`
(one warm-up block instead of three: one block takes about 98 s on core 1, so the round is about 52 min on X925
and longer on A725), core 9 then core 11 under their pool locks, `taskset -c CORE nice -n 10`.

Ratios per case and core, median of per-block ratios with the [r(10), r(22)] interval over clean blocks (Wolfram):
ngS/ngA, ngT/ngA, ngT/ngS, ngA/omc (A/A), ngS/gccO2, ngT/gccO2, ngA/gccO2. Summary per core: geometric mean over the
9 cases of each ratio's median (descriptive, no interval).

Verdict words per case: ng FASTER than omc when the ngS/ngA interval lies wholly below 1, SLOWER when wholly above,
NO DIFFERENCE otherwise; the same for ngT and for ngT against ngS (save form). No numeric prediction is made; the
single core-1 runs used to size the round are not results and are not cited.

Placement (D13 item 3): ng aligns function entries to 64 bytes and omc does not; S1 measures the binaries as each
compiler emits them and makes no placement claim. A placement control is out of scope for this round.

## Records per round and core

`start.txt`/`end.txt` (time, load), `idle-start.txt`/`idle-end.txt`, `cluster-start.txt`/`cluster-end.txt`, `midr.txt`,
`lock-request.txt`, `rows.txt`, `stderr.txt`, `rc.txt`, the Wolfram queries and results, and the driver text. Lock
taken and released lines go to the BOARD automatically.
