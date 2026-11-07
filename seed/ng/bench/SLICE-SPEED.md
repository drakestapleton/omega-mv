# SLICE SPEED S1: the first Omega NG slice against omc and gcc -O2 (lane ng-bench)

Question (omp-queen-ng, 2026-11-07): how fast is code from the NG slice, front-m3 `3353ad67` to a64-m2 `e70c1234`,
in both save forms, against omc and gcc -O2, on arith branch leafcall fib38 fib40 isort sieve sort matmul, on one
X925 core and one A725 core, on an idle machine, with Wolfram intervals. Pre-registered in `PREREG-slice.md`
(commit ecfe3b0b, amended 0d853c82 and 9f67a3cc before any timing row). Evidence: `evidence/20261107T1416Z-s1/`.

Status: CHIP_TESTED for these exact binaries (`slice/slice-manifest.sha256`), one Spark, core 9 and core 11. The NG
heads timed here are local lane heads (front-m3, a64-m2); this is a measurement of their output, not a review
or qualification of them. Placement is not controlled: NG aligns function entries to 64 bytes and omc does not.

## The answer, in plain words

A ratio below 1 means the first-named binary is faster. `ngA` is a byte copy of omc's binary timed in the same
blocks; every NG arm is judged against it.

| core | NG paired (ngS) over omc | NG split (ngT) over omc | split over paired | NG paired over gcc -O2 | omc over gcc -O2 |
|---|---|---|---|---|---|
| X925 (core 9) | 0.9600 | 0.9475 | 0.9875 | 2.4936 | 2.5927 |
| A725 (core 11) | 1.1478 | 1.1234 | 0.9786 | 2.9694 | 2.5826 |

Geometric means over the 9 cases of the clean-block medians (descriptive, no interval; Wolfram, `wolfram-s1-*`).

1. NG wins where calls dominate and loses where loops dominate. leafcall, fib38 and fib40 run in about half of
   omc's time on the X925 (0.51 to 0.58) and in 0.80 to 0.91 of it on the A725. branch, isort, sieve, sort and
   matmul are slower under NG on both cores (1.16 to 1.86 on the X925, 1.26 to 1.47 on the A725). arith is within
   1% on both.
2. Overall NG is slightly faster than omc on the X925 (0.960 paired, 0.948 split) and slower on the A725 (1.148,
   1.123): the call wins are bigger on the X925, the loop losses bigger on the A725.
3. The split save form is never slower than the paired one: it is faster on leafcall X925 (0.918), fib38 and
   fib40 A725 (0.912), branch on both cores (0.984, 0.987) and arith X925 (0.9993, at the edge), and no
   different elsewhere.
4. Against gcc -O2 NG is 2.49 (X925) and 2.97 (A725) times slower by geometric mean; omc is 2.59 and 2.58 in the
   same blocks. The payoff map (`PAYOFF.md`) says which passes close that: the loop kernels NG loses here are the
   ones LICM+ROT and BCE speed up there.

Why NG is slower on the loop kernels was not examined in this round (no disassembly attribution); that is the
next measurement, as section 1 of `PAYOFF.md` did for omc.

## Conditions

X925 core 9 under `pool-8-9.lock`, 2026-11-07T17:18:15Z to 17:25:22Z; A725 core 11 under `pool-10-11.lock`,
18:42:07Z to 18:57:47Z. The A725 rounds waited for the queen's pool-10-11 hold; it was released by omp-queen-spark's
14:48:10Z line "INF-4 END (not run: window not opened within 6 min, rc 124); sched may start" (`hold-release.txt`):
INF-4 ended without running, so nothing of it was disturbed. ngbench v3 (sha256 2a01e610...0f30), 31 measured
blocks after 1 warm-up (blocks 0 to 31 all present in `rows.txt`), 5 arms x 9 cases, 2 runs per arm per block. The
PREREG's duration estimate (about 52 min on the X925) was sized from a core-1 single shot; core 9 ran the kernels
much faster (arith omc 120 ms per run against 497 ms in that shot), so the X925 round took 7 min.

- Idle condition held at start (in-lock recheck) and at end on both cores (`idle-start.txt`, `idle-end.txt`), and
  the per-case busy count was 0 in every block-case pair (288 per core).
- Foreign runnable task on the timed core: 0 pairs on the X925, 18 on the A725, dropped. Clean blocks per case:
  31 on the X925; 27 to 31 on the A725, above the 21 needed.
- A/A (ngA/omc) passes on all 9 cases on both cores.
- Not covered by the idle rule: other CPU jobs. During the A725 round rust compiles and a browser ran on cores 14
  to 18 of the same A725 cluster (`a725/cluster-*.txt`, load 7.6 at start, 5.9 at end); the X925 round started at
  load 9.5. On the A725 the two runs of an arm in one block differed by more than 25% in up to 9 of 31 blocks per
  case and arm, omc and gcc included (43 of the 45 case-arm pairs had at least one such block; on the X925, 11,
  mostly gcc's short runs); the per-block ratio and the median absorb this, and the intervals are wider there.

## X925 (core 9): clean-block median [r(10), r(22)]

| case | ngS/ngA | ngT/ngA | ngT/ngS | ngA/omc (A/A) | ngS/gccO2 | ngT/gccO2 | ngA/gccO2 | clean blocks |
|---|---|---|---|---|---|---|---|---|
| arith | 1.0064 [1.0060, 1.0081] | 1.0062 [1.0057, 1.0076] | 0.9993 [0.9987, 1.0000] | 1.0004 [0.9994, 1.0350] | 3.4143 [3.1871, 3.4906] | 3.4124 [3.1848, 3.4894] | 3.3925 [3.1666, 3.4648] | 31 |
| branch | 1.8602 [1.8411, 1.8752] | 1.8218 [1.7933, 1.8486] | 0.9839 [0.9716, 0.9878] | 1.0026 [1.0003, 1.0289] | 3.4053 [3.3377, 3.4909] | 3.3628 [3.2389, 3.4444] | 1.8184 [1.7884, 1.8685] | 31 |
| leafcall | 0.5784 [0.5758, 0.5795] | 0.5296 [0.5287, 0.5314] | 0.9178 [0.9151, 0.9213] | 1.0017 [1.0002, 1.0043] | 1.9528 [1.9408, 1.9613] | 1.7964 [1.7785, 1.8008] | 3.3754 [3.3636, 3.4006] | 31 |
| fib38 | 0.5099 [0.5081, 0.5240] | 0.5108 [0.5080, 0.5157] | 0.9970 [0.9575, 1.0115] | 0.9996 [0.9979, 1.0002] | 1.9907 [1.9051, 2.0274] | 2.0148 [1.8315, 2.0428] | 3.9139 [3.5279, 3.9914] | 31 |
| fib40 | 0.5113 [0.5075, 0.5178] | 0.5072 [0.5057, 0.5141] | 0.9930 [0.9766, 1.0021] | 1.0002 [0.9999, 1.0007] | 1.8764 [1.8275, 1.8841] | 1.8362 [1.7925, 1.8796] | 3.6208 [3.5282, 3.7033] | 31 |
| isort | 1.3308 [1.3153, 1.3333] | 1.3294 [1.3151, 1.3326] | 0.9999 [0.9608, 1.0012] | 1.0014 [1.0001, 1.0546] | 2.5778 [2.4563, 2.6401] | 2.5758 [2.3600, 2.6375] | 1.9296 [1.7928, 1.9825] | 31 |
| sieve | 1.1962 [1.1922, 1.2005] | 1.1949 [1.1786, 1.1994] | 0.9997 [0.9968, 1.0001] | 0.9999 [0.9997, 1.0010] | 2.4697 [2.4123, 2.4877] | 2.4470 [2.4031, 2.4806] | 2.0670 [2.0198, 2.0835] | 31 |
| sort | 1.1645 [1.1630, 1.1666] | 1.1665 [1.1642, 1.1783] | 1.0002 [0.9998, 1.0119] | 0.9999 [0.9861, 1.0004] | 3.1280 [3.0829, 3.1721] | 3.1543 [3.0901, 3.1742] | 2.6943 [2.6524, 2.7205] | 31 |
| matmul | 1.3238 [1.3196, 1.3282] | 1.3212 [1.3186, 1.3282] | 1.0000 [0.9972, 1.0018] | 0.9992 [0.9961, 1.0054] | 2.2074 [2.1986, 2.2269] | 2.2101 [2.1992, 2.2311] | 1.6697 [1.6557, 1.6767] | 31 |

## A725 (core 11): clean-block median [r(10), r(22)]

| case | ngS/ngA | ngT/ngA | ngT/ngS | ngA/omc (A/A) | ngS/gccO2 | ngT/gccO2 | ngA/gccO2 | clean blocks |
|---|---|---|---|---|---|---|---|---|
| arith | 1.0000 [0.9992, 1.0099] | 1.0004 [0.9770, 1.0020] | 0.9997 [0.9770, 1.0015] | 1.0009 [0.9998, 1.0253] | 2.5608 [2.4631, 2.5813] | 2.5357 [2.4648, 2.5680] | 2.5326 [2.4340, 2.5683] | 27 |
| branch | 1.4521 [1.4396, 1.4579] | 1.4333 [1.4174, 1.4399] | 0.9871 [0.9808, 0.9874] | 0.9999 [0.9978, 1.0028] | 4.9243 [4.8202, 4.9409] | 4.8616 [4.8159, 4.8822] | 3.3943 [3.3673, 3.4294] | 30 |
| leafcall | 0.9064 [0.9007, 0.9091] | 0.9106 [0.9084, 0.9151] | 1.0036 [0.9981, 1.0118] | 1.0005 [0.9984, 1.0015] | 2.5320 [2.5212, 2.5397] | 2.5446 [2.5319, 2.5537] | 2.7871 [2.7784, 2.7993] | 31 |
| fib38 | 0.8801 [0.8786, 0.8804] | 0.8019 [0.7992, 0.8033] | 0.9118 [0.9103, 0.9129] | 1.0006 [0.9996, 1.0022] | 2.2190 [2.2059, 2.2213] | 2.0224 [2.0174, 2.0281] | 2.5233 [2.5129, 2.5273] | 28 |
| fib40 | 0.8837 [0.8800, 0.8860] | 0.8054 [0.8042, 0.8078] | 0.9121 [0.9102, 0.9178] | 0.9998 [0.9929, 1.0019] | 2.0033 [1.9654, 2.0054] | 1.8258 [1.7977, 1.8288] | 2.2686 [2.2427, 2.2700] | 30 |
| isort | 1.4317 [1.4297, 1.4326] | 1.4316 [1.4207, 1.4326] | 1.0002 [0.9990, 1.0005] | 1.0001 [0.9998, 1.0009] | 3.9031 [3.7765, 3.9097] | 3.9033 [3.7135, 3.9123] | 2.7248 [2.6751, 2.7325] | 30 |
| sieve | 1.2743 [1.2720, 1.2783] | 1.2722 [1.2632, 1.2768] | 1.0000 [0.9938, 1.0011] | 1.0003 [0.9966, 1.0080] | 3.1765 [3.1165, 3.2030] | 3.1816 [3.1330, 3.2001] | 2.4951 [2.4550, 2.5206] | 27 |
| sort | 1.4728 [1.4651, 1.4842] | 1.4747 [1.4618, 1.4847] | 0.9996 [0.9944, 1.0006] | 1.0003 [0.9995, 1.0078] | 3.6000 [3.5005, 3.6248] | 3.6014 [3.5474, 3.6243] | 2.4382 [2.3889, 2.4614] | 29 |
| matmul | 1.2567 [1.2530, 1.2601] | 1.2587 [1.2536, 1.2610] | 0.9997 [0.9977, 1.0010] | 1.0013 [1.0002, 1.0045] | 2.8332 [2.8089, 2.8537] | 2.8324 [2.8150, 2.8511] | 2.2484 [2.2334, 2.2652] | 29 |

Verdicts per case (pre-registered rule: FASTER when the interval lies wholly below 1, SLOWER wholly above):

| case | X925 ngS vs omc | X925 ngT vs omc | X925 ngT vs ngS | A725 ngS vs omc | A725 ngT vs omc | A725 ngT vs ngS |
|---|---|---|---|---|---|---|
| arith | SLOWER | SLOWER | FASTER | NO DIFFERENCE | NO DIFFERENCE | NO DIFFERENCE |
| branch | SLOWER | SLOWER | FASTER | SLOWER | SLOWER | FASTER |
| leafcall | FASTER | FASTER | FASTER | FASTER | FASTER | NO DIFFERENCE |
| fib38 | FASTER | FASTER | NO DIFFERENCE | FASTER | FASTER | FASTER |
| fib40 | FASTER | FASTER | NO DIFFERENCE | FASTER | FASTER | FASTER |
| isort | SLOWER | SLOWER | NO DIFFERENCE | SLOWER | SLOWER | NO DIFFERENCE |
| sieve | SLOWER | SLOWER | NO DIFFERENCE | SLOWER | SLOWER | NO DIFFERENCE |
| sort | SLOWER | SLOWER | NO DIFFERENCE | SLOWER | SLOWER | NO DIFFERENCE |
| matmul | SLOWER | SLOWER | NO DIFFERENCE | SLOWER | SLOWER | NO DIFFERENCE |

## Receipts

- Arms and pins: `PREREG-slice.md`; every IR unit and ELF in `slice/slice-manifest.sha256`, rebuilt from the two
  commits by `slice/mkslice.sh.txt` (the gate repeats that rebuild from a fresh clone).
- Per core: `rows.txt`, `wl-data.m` (rows reformatted by `slice/wl3.awk.txt`, no arithmetic), `wolfram-s1-query.wl`,
  `wolfram-s1-result.txt`, `stats-s1.tsv`, idle, cluster, lock and start/end records, the driver as text.
