# NG bench baseline: seeded omc against gcc -O2 on GB10 (lane ng-bench)

Status: CHIP_TESTED on one DGX Spark (GB10), one X925 core and one A725 core, 2026-11-07. Not QUALIFIED: the
held-out inputs (PREREG.md, D9) have not been timed.

Rules: `PREREG.md` (arms, metric, A/A control, validity), `PREREG-contamination.md` (addendum 3: ngbench v2
scans what else ran, verdicts on clean blocks). Every number below was computed by the Wolfram evaluator; the
queries and results are saved beside the rows.

## Rounds

| core | type | window (UTC) | rows | exit | contaminated measured blocks | evidence |
|---|---|---|---|---|---|---|
| 9 | X925 | 2026-11-07 08:44:45..08:51:11 | 3672 ok, `fail=0 refused=0` | 0 | matmul 32 | `evidence/20261107T0830Z-baseline-v2/x925/` |
| 11 | A725 | 2026-11-07 08:51:11..09:04:24 | 3672 ok, `fail=0 refused=0` | 0 | arith 10; branch 19; fib38 6, 25; fib40 11, 18; isort 25, 31; leafcall 28, 31; linear 19, 22; matmul 9, 28, 31; omcself 12; sha 20, 23; sort 17; x25519 6, 9, 22, 25, 31 | `evidence/20261107T0830Z-baseline-v2/a725/` |

Every case keeps at least 21 clean blocks (lowest: A725 x25519, 26), so every verdict uses clean blocks with the
interval index k from the addendum 3 table. Raw rows: `rows.txt` in each directory (`H`, `T`, `X`, `Y`, `K`, `S`
rows as described in `seed/ng/ngbench.om`). Per-case statistics: `stats-wall.tsv` (wall) and `stats-inproc.tsv`
(in-process ns of the 7 OMC-EFF kernels), each with all-block and clean-block columns; Wolfram queries and results
in `wolfram-{wall,inproc,summary}-{query.wl,result.txt}`.

Earlier rounds `20261107T0810Z-baseline/x925` and `a725-ABORTED-v1` ran with ngbench v1 and are POSSIBLY
CONTAMINATED (v1 did not record what else ran; another lane's work was found on core 11 during those windows,
and the A725 round was stopped). They are kept unchanged and no verdict is taken from them. For the record, the X925
v1 medians of omc/gccO2 differ from v2 by 0.02% to 0.60% on 12 cases and by 2.01% on bcopy (Wolfram, `100 Abs[v2/v1 - 1]`);
bcopy's A/A control failed in v1 (0.986 [0.968, 0.995]) and passes in v2.

## Result: omc / gcc -O2, median of per-block wall ratios [95% interval], clean blocks

Above 1 means omc is slower. "x" is how many times longer omc takes.

| case | X925 (core 9) | n | A725 (core 11) | n |
|---|---|---|---|---|
| arith | 3.445 [3.428, 3.461] | 31 | 2.564 [2.551, 2.568] | 30 |
| branch | 1.864 [1.861, 1.869] | 31 | 3.382 [3.376, 3.420] | 30 |
| fib38 | 3.997 [3.989, 4.007] | 31 | 2.521 [2.507, 2.528] | 29 |
| isort | 1.983 [1.974, 1.986] | 31 | 2.723 [2.709, 2.733] | 29 |
| leafcall | 3.395 [3.362, 3.411] | 31 | 2.786 [2.758, 2.799] | 29 |
| matmul | 1.663 [1.644, 1.670] | 30 | 2.243 [2.197, 2.2525] | 28 |
| sieve | 2.074 [2.058, 2.088] | 31 | 2.483 [2.473, 2.492] | 31 |
| fib40 | 3.710 [3.704, 3.713] | 31 | 2.271 [2.268, 2.290] | 29 |
| sort | 2.719 [2.714, 2.723] | 31 | 2.440 [2.436, 2.441] | 30 |
| bcopy | 30.38 [30.13, 30.53] | 31 | 30.19 [29.445, 30.495] | 31 |
| sha | 1.465 [1.462, 1.466] | 31 | 1.483 [1.479, 1.488] | 29 |
| chacha | 2.413 [2.406, 2.424] | 31 | 2.684 [2.618, 2.717] | 31 |
| linear | 1.245 [1.243, 1.247] | 31 | 1.825 [1.817, 1.828] | 29 |
| geometric mean of the 13 medians | 2.846 | | 2.920 | |

omc is slower than gcc -O2 on every case on both core types (every interval lies above 1).

omc-only cases, per-block mean of the two omc walls, median [95% interval], clean blocks:

| case | X925 | n | A725 | n |
|---|---|---|---|---|
| omcself (omc compiling `seed/omc/omc.om`, the self-compile) | 17.10 ms [16.98, 17.25] | 31 | 34.74 ms [34.60, 35.62] | 30 |
| x25519 | 349.1 ms [349.0, 349.3] | 31 | 637.2 ms [636.9, 638.8] | 26 |

In-process ns (the time each OMC-EFF kernel measures inside itself, omc/gccO2, clean): X925 arith 3.488,
branch 1.873, fib38 4.050, isort 1.997, leafcall 3.482, matmul 1.714, sieve 2.088; A725 arith 2.590, branch 3.423,
fib38 2.545, isort 2.761, leafcall 2.855, matmul 2.324, sieve 2.497 (intervals in `stats-inproc.tsv`).

## Controls and context

- Validity rule 1: both rounds exit 0 with `fail=0 refused=0`: every timed run exited 0 with the expected output
  hash, and every binary matched the manifest before and after timing.
- A/A control (`gccO2aa`, the same gcc -O2 bytes under a second label): passes on all 13 cases on both cores.
  On A725, matmul's interval [0.986, 0.9985] excludes 1 but its median 0.996 lies in [0.99, 1.01], which passes
  under rule 2. One failure would still be allowed; there is none.
- gcc -O3 against -O2 (information only; `-march=native` adds nothing on gcc 13.3 here): geometric mean 1.253
  (X925) and 1.227 (A725). -O3 is more than 10% slower than -O2 on branch, isort and bcopy on both cores
  (bcopy: 15.27x on X925, 10.18x on A725). Both builds of bcopy's `main` use 128-bit vector loads and stores
  (`objdump -d`), so the cause of the -O3 slowdown is not established here.
- bcopy, at about 30x on both cores, is the largest gap.

## Hardware and software identity

`evidence/20261107T0830Z-baseline-v2/hwid.txt` holds the full `lscpu`, `lscpu -e` and toolchain output. Summary:

| item | value |
|---|---|
| host | `spark-b87b`, DGX Spark, NVIDIA GB10; Linux 7.0.0-1019-nvidia #19~24.04.2-Ubuntu aarch64 |
| core 9 | Cortex-X925, MIDR_EL1 `0x410fd851`, max 3.900 GHz, governor performance, cluster cpus 0-9 |
| core 11 | Cortex-A725, MIDR_EL1 `0x410fd871`, max 2.808 GHz, governor performance, cluster cpus 10-19 |
| counters | `kernel.perf_event_paranoid` = 4: no cycle or instruction counts, time only |
| omc | `seed/out/omc` at omega-mv `943d955531b9d4d9f70deb41756c0b46441dd5e0`, sha256 `5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df` |
| ngbench | `seed/ng/ngbench.om` v2 sha256 `9019c99695f07763ae6cbffa0dfc83a0484f55a299cf31a7d27ad6536b10722e`, built by that omc to sha256 `ba6351527ef844836776dbaff44b782c5957225f35a172205ae4d77904ff0200` |
| gcc | Ubuntu 13.3.0-6ubuntu2~24.04.1: `/usr/bin/gcc-13` `a20520ee21543f243d40636a9181a142c45ecd989de31ab86b99a8ea5ada870d`, `cc1` `64edfe466dd55c4216c006e9fa237af012e4974281dd4d11640aacfc3b3693af` |
| binutils | 2.42-4ubuntu2.10: `as` `1ffda50efb6d91b6b05ef933aced099595c36577594c0296c91161f2d13db374`, `ld.bfd` `1e4d3369b76845fa8e099b83513bf28f6f722e046f9b2cde1378c9e27f96d19c` |
| libc | libc6-dev 2.39-0ubuntu8.9 (static link) |

## Exact commands

Builds (cwd = the omega-mv checkout, core 1, K = case; from PREREG.md "Arms"):

```
taskset -c 1 nice -n 10 seed/out/omc < seed/ng/bench/kernels/K.om > DIR/bin/omc/K; chmod 755 DIR/bin/omc/K
taskset -c 1 nice -n 10 gcc -O2 -static -o DIR/bin/gccO2/K seed/ng/bench/kernels/K.c
cp DIR/bin/gccO2/K DIR/bin/gccO2aa/K
taskset -c 1 nice -n 10 gcc -O3 -march=native -static -o DIR/bin/gccO3n/K seed/ng/bench/kernels/K.c
cp seed/out/omc DIR/bin/omc/omcself; cp seed/omc/omc.om DIR/in/omcself
(cd DIR && ngbench sum bin/*/*) > DIR/manifest.sha256
```

The 54-line manifest of that DIR is `evidence/20261107T0830Z-baseline-v2/manifest.sha256`.

Timing (DIR = `/tmp/ngb/base`; CORE 9 with `pool-8-9.lock`, CORE 11 with `pool-10-11.lock`):

```
flock -x -w 3600 ~/handoffs/hive/queen/pool-CORES.lock sh -c 'cd DIR && taskset -c CORE nice -n 10 ngbench run 31 3 DIR \
  omc gccO2 gccO2aa gccO3n -- arith branch fib38 isort leafcall matmul sieve fib40 sort bcopy sha chacha linear x25519 omcself \
  > rows.txt 2> stderr.txt'
```

Load average and the cluster's processes before and after each round: `start.txt`, `end.txt`,
`cluster-start.txt`, `cluster-end.txt` in each round directory.

## What this means for NG

On these 13 refereed kernels, today's seeded compiler takes 2.8 to 2.9 times as long as gcc -O2 (geometric mean),
from 1.2x (linear, X925) to 30x (bcopy). The omc self-compile takes 17 ms on an X925 core and 35 ms on an A725
core. Any NG speedup claim on this harness is measured against these numbers with the decision rule in PREREG.md,
on each core type separately, and repeated on the held-out inputs before it is called QUALIFIED.
