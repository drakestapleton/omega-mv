# PAYOFF: which compiler passes buy the most speed (M3 payoff map, lane ng-bench)

Question (omp-queen-ng, 2026-11-07T11:31:44Z): for the 13 baseline kernels, why is omc slower than gcc -O2, and
which missing compiler passes would close the most of that gap, ranked by expected geometric-mean gain per core
type.

Method in one paragraph: omc's own binary of each kernel was edited by hand into a ladder of arms, each rung adding
what one pass would emit (`hand/*.spec`, written by `hand.om`, every word checked against objdump, every arm's
output checked against the kernel's referee hash). The ladders were timed with ngbench v2 on one X925 core and one
A725 core under the pre-registration `PREREG-payoff.md` (commit b5f46745, posted 11:54:28Z before any timing row).
A step factor is a rung's time over the time of the rung below it on the same block; below 1 means faster.
Kernels without a hand ladder: fib38/fib40 cite the plan-breaker v2 round; sha and chacha are MODELED from an
instruction census (section 5). Every statistic and every number derived from the rows was computed by Wolfram;
queries and results are in `evidence/20261107T1155Z-payoff/`.

Status words: the step factors are CHIP_TESTED, one Spark, core 9 (X925) and core 11 (A725), these frozen inputs,
these hand-built arms. They are not QUALIFIED and not NG output: the arms show what a pass is worth when it is done
perfectly by hand on the hot loop, an upper bound for what NG's pass can earn on the same code.

## The answer, in plain words

Ranked by expected geometric-mean gain over the 13 baseline kernels (1.10 means the 13 kernels together run 10%
faster when that one pass is added and nothing else changes). Every arm is judged against the same-round A/A copy
`ngA` (a byte-identical copy of omc timed in the same blocks), and each rung against the rung below it.
"Measured" uses only timed hand arms and the cited fib round; "with MODELED" adds the sha and chacha estimates of
section 5. Both rounds ran beside GPU training and CPU model jobs (section 2). The A/A controls pass on all 9
cases on both cores, so neither round is marked CONTAMINATED under the queen's rule; that does not clear them of
memory-bandwidth contention, which slows both A/A copies alike (section 2). The rounds are not contention-cleared.

| rank | X925 (core 9) | gain measured | with MODELED | A725 (core 11) | gain measured | with MODELED |
|---|---|---|---|---|---|---|
| 1 | VEC | 1.2367 | 1.2367 | LICM+ROT | 1.2116 | 1.2214 |
| 2 | CALL | 1.1741 | 1.1745 | VEC | 1.1971 | 1.1971 |
| 3 | LICM+ROT | 1.1401 | 1.1418 | BCE | 1.1091 | 1.1276 |
| 4 | DIV | 1.0882 | 1.0882 | DIV | 1.0755 | 1.0755 |
| 5 | REC | 1.0804 | 1.0804 | REC | 1.0698 | 1.0698 |
| 6 | BCE | 1.0237 | 1.0268 | CALL | 1.0635 | 1.0656 |
| 7 | INL | 1.0138 | 1.0138 | ISEL | 1.0251 | 1.0251 |
| 8 | IFC | 1.0086 | 1.0086 | IFC | 1.0210 | 1.0210 |
| 9 | ISEL | 1.0075 | 1.0075 | INL | 1.0156 | 1.0156 |

All passes together: 2.062 (X925) and 2.149 (A725). The baseline gap omc/gcc -O2 was 2.846 and 2.920, so the
nine passes, done perfectly, close about half the gap in time terms and leave omc 1.380 (X925) and 1.359 (A725)
times slower than gcc -O2 by geometric mean (Wolfram, `wolfram-summary-*`).

What it means for NG:

1. The two core types want different passes first. The big X925 core already hides most of the cost of omc's
   extra instructions (its out-of-order window absorbs rebuilt constants and bounds checks): one removed loop
   instruction is worth e = 0.12 of its share of the time there, against e = 0.63 on the A725 (section 5). On the
   X925 the wins come from work the core cannot hide: whole calls (CALL, leafcall 0.363), one byte at a time
   (VEC, bcopy 0.063), a slow divide (DIV, arith 0.333). On the A725 plain instruction removal (LICM+ROT, BCE)
   pays almost as much as those.
2. LICM+ROT is the safest first pass: it is in the top three on both cores and applies to 8 of the 13 kernels.
3. VEC's score comes from one kernel (bcopy, 16 bytes per pass); it is large because omc copies one byte at a
   time. chacha's XOR step has the same shape and is not in the score.
4. CALL on the X925 is three measurements that agree (leafcall 0.363, fib40 0.578, fib38 0.591); on the A725 the
   fib38 arm is the plan-breaker's placement case (1.087), which drags CALL down to sixth there.
5. Some passes cost time where the loop is waiting on one long chain of dependent work rather than on the number
   of instructions (section 4). A compiler that removes instructions without watching code placement will see
   a few percent lost there.

## 1. Where the time goes: omc's hot loops against gcc -O2

Instructions per pass of the hot loop, from `objdump -D -b binary -m aarch64` of omc's binary (cfd96b48 and
5f90edea emit the same bytes) and `objdump -d` of the baseline gcc -O2 binary. "Loop body" is the static size from
the loop head to its back branch, both included; loops with a forward branch inside (branch, the Collatz step)
count both sides.

| kernel | omc | ngL | ngB | top rung | gcc -O2 | what omc spends the difference on |
|---|---|---|---|---|---|---|
| bcopy | 18 per byte | 11 | 7 | ngV 9 per 16 bytes | 6 per 16 bytes (NEON) | 3 bounds checks (6), the 10^6 `while` bound counter (3), limit constant rebuilt each pass (MOV+MOVK), top test plus back branch, one byte per pass |
| arith | 17 | 11 | (no BCE rung) | ngM 14 | 14 | UDIV+MSUB for `% 1000003` where gcc multiplies by the reciprocal (UMULH); 5 constants rebuilt per pass |
| branch | 18 inner, 31 outer | 12 / 24 | (counter kept) | ngC 11 / 22 | 7, branchless CSINC | Collatz step as branches; CSET/AND boolean lowering; constants rebuilt |
| isort | 28 inner | 14 | 7 | | about 6, inlined | 2 bounds checks per access pair, rebuilt limits, top test plus back branch |
| sort | 24 inner | 14 | 7 | | | same pattern as isort |
| leafcall | 27 per call plus the callee | | | ngR 8, ngI 8 | about 5, inlined | per-call frame, stack check, 5 STR + 5 LDR of live values around the call |
| matmul | 22 inner | 13 | 9 | | about 7 | 2 checks, rebuilt 2400-byte stride and limits; the column walk is memory-bound in both |
| sieve | 19 per mark | 9 | 4 | | about 4 | check, counter, rebuilt limit 2000000 |
| linear | 20 | 17 | 13 | ngF 11 | | f32 load as LDR W + FMOV + FCVT; checks per pass; the FADD chain sets the floor |

sha and chacha are straight-line after omc's `unroll`; their executed instructions per 64-byte block, by class
(MODELED inputs, section 5):

| kernel | instructions per block | constant rebuild (LICM) | bounds checks (BCE) | spill, reload around calls (CALL) | register copies |
|---|---|---|---|---|---|
| sha | 3650 = s256 1299 + r256 2279 + block loop 72 | 9 | 136 | 52 | 592 (r256 renames 9 per round) |
| chacha | 6871 = 10 x dround 486 + block 646 + xor step 1320 + run 45 | 1072 | 1902 | 178 | 1 |

## 2. What else was running, and the controls

The rounds shared the machine with GPU training legs (ownmodel own1-leg23, leg24, leg25: `ollm-gb10 gtrain4`),
CPU model jobs (wsp `ollm train`, ownmodel-gates6 `ollm serve` on ports 18291/18292, wsp `wpolicy`), listed per
round with times and sources in `evidence/20261107T1155Z-payoff/OVERLAP.md`. They were seen only on other cores
in the cluster snapshots at round start and end. The per-block scans (one before and one after each case in each
block, not continuous) found a foreign runnable task on the timed core itself 3 times on X925 and 12 times on A725;
those 3 and 11 (block, case) pairs were dropped as contaminated. All of the jobs share memory bandwidth and the
system-level cache, which ngbench's per-core scan cannot see; the A725 round also had a CPU-bound `ollm` on core 19
of its own cluster.

What protects the ratios: every block runs all arms of a case back to back in a palindrome (ABBA), so a slow minute
slows every arm of that block together, and the A/A copy measures what is left. Same-round A/A, ngA/omc, clean-block
median [95% interval] (Wolfram, `{x925,a725}/wolfram-ngA-*`; the rule passes when the interval contains 1 or the
median lies in [0.99, 1.01]):

| kernel | X925 ngA/omc | A725 ngA/omc |
|---|---|---|
| bcopy | 1.0005 [0.9991, 1.0015] | 1.0004 [0.9993, 1.0140] |
| arith | 1.0000 [0.9951, 1.0011] | 0.9997 [0.9945, 1.0045] |
| branch | 1.0003 [0.9977, 1.0016] | 0.9992 [0.9913, 1.0152] |
| isort | 0.9992 [0.9970, 1.0026] | 1.0002 [0.9978, 1.0082] |
| sort | 0.9995 [0.9902, 1.0008] | 1.0002 [0.9917, 1.0077] |
| leafcall | 0.9999 [0.9985, 1.0011] | 1.0004 [0.9982, 1.0013] |
| matmul | 0.9969 [0.9867, 1.0035] | 1.0006 [0.9919, 1.0084] |
| sieve | 0.9997 [0.9969, 1.0019] | 0.9989 [0.9948, 1.0056] |
| linear | 0.9995 [0.9985, 1.0004] | 0.9996 [0.9851, 1.0060] |

All 18 pass, so neither round is CONTAMINATED under the rule. This check has a blind spot: ngA and omc are the same
bytes, so a load that steals memory bandwidth slows both equally and the A/A ratio stays at 1. Contention can
still bias steps between arms that use memory differently. A second check: omc/gcc -O2 in this round over the same ratio in
the baseline round (20261107T0830Z, clean medians), Wolfram geometric mean 0.9878 on X925 and 0.9943 on A725:

| kernel | X925 this/baseline | A725 this/baseline |
|---|---|---|
| bcopy | 0.9644 | 0.9800 |
| arith | 0.9911 | 0.9955 |
| branch | 0.9925 | 0.9962 |
| isort | 0.9922 | 1.0015 |
| sort | 1.0013 | 0.9980 |
| leafcall | 0.9905 | 0.9923 |
| matmul | 0.9872 | 0.9875 |
| sieve | 0.9761 | 0.9989 |
| linear | 0.9951 | 0.9994 |

The largest moves are bcopy (0.964 on X925, 0.980 on A725) and sieve on X925 (0.976): those are the kernels that
move the most memory, and gcc's arm lost ground against omc's, which fits bandwidth contention slowing the faster
arm more. The pass step factors are taken within one round and one block, so this shift does not enter them
directly, but bcopy's VEC factor and the X925 bcopy steps (whose intervals are wide: LICM+ROT [0.674, 0.793], BCE
[0.665, 0.780]) are the numbers most exposed to it. The bcopy and sieve shifts are evidence that contention was
present. A rerun of the top ranks with the GPU line and the ollm jobs idle would settle how much it moved them.

## 3. Measured step factors

Clean-block median [95% interval], n = 31 blocks less the contaminated ones (`stats-wall-ngA.tsv` and
`stats-wall.tsv`, Wolfram queries `wolfram-ngA-query.wl` and `wolfram-wall-query.wl`). First rungs are judged
against the same-round A/A copy ngA; later rungs against the rung below. Below 1 is faster.

| kernel | pass | ratio | X925 (core 9) | A725 (core 11) |
|---|---|---|---|---|
| bcopy | LICM+ROT | ngL/ngA | 0.6846 [0.6739, 0.7932] | 0.7414 [0.7367, 0.7493] |
| bcopy | BCE | ngB/ngL | 0.7719 [0.6647, 0.7798] | 0.6116 [0.6064, 0.6125] |
| bcopy | VEC | ngV/ngB | 0.0632 [0.0623, 0.0648] | 0.0964 [0.0955, 0.0979] |
| arith | LICM+ROT | ngL/ngA | 0.9964 [0.9950, 0.9968] | 1.0175 [1.0094, 1.0405] |
| arith | DIV | ngM/ngL | 0.3333 [0.3317, 0.3344] | 0.3882 [0.3854, 0.3917] |
| branch | LICM+ROT | ngL/ngA | 0.9374 [0.9359, 0.9405] | 0.6003 [0.5895, 0.6030] |
| branch | IFC | ngC/ngL | 0.8952 [0.8939, 0.8981] | 0.7630 [0.7470, 0.7696] |
| isort | LICM+ROT | ngL/ngA | 0.6837 [0.6825, 0.6865] | 0.6140 [0.6063, 0.6229] |
| isort | BCE | ngB/ngL | 0.9775 [0.9748, 0.9795] | 0.7144 [0.7056, 0.7209] |
| sort | LICM+ROT | ngL/ngA | 0.6818 [0.6802, 0.6853] | 0.7314 [0.7240, 0.7356] |
| sort | BCE | ngB/ngL | 0.9809 [0.9796, 0.9817] | 0.6993 [0.6974, 0.7023] |
| leafcall | CALL | ngR/ngA | 0.3634 [0.3618, 0.3653] | 0.4655 [0.4635, 0.4673] |
| leafcall | INL | ngI/ngR | 0.8369 [0.8320, 0.8456] | 0.8173 [0.8146, 0.8206] |
| matmul | LICM+ROT | ngL/ngA | 0.7611 [0.7511, 0.7807] | 0.6926 [0.6904, 0.6971] |
| matmul | BCE | ngB/ngL | 1.0346 [1.0156, 1.0457] | 0.8812 [0.8768, 0.8847] |
| sieve | LICM+ROT | ngL/ngA | 0.7826 [0.7777, 0.7888] | 0.6774 [0.6693, 0.6801] |
| sieve | BCE | ngB/ngL | 0.9747 [0.9663, 0.9803] | 0.8698 [0.8636, 0.8849] |
| linear | LICM+ROT | ngL/ngA | 1.0246 [1.0223, 1.0262] | 0.8646 [0.8616, 0.8690] |
| linear | BCE | ngB/ngL | 0.9875 [0.9862, 0.9889] | 1.1109 [1.1039, 1.1145] |
| linear | ISEL | ngF/ngB | 0.9077 [0.9047, 0.9092] | 0.7249 [0.7225, 0.7356] |

Where each kernel ends up (clean medians): ngA (= omc) over gcc -O2, the top rung against ngA, the top rung
against gcc -O2.

| kernel | X925 ngA/gcc | top rung | X925 top/ngA | X925 top/gcc | A725 ngA/gcc | A725 top/ngA | A725 top/gcc |
|---|---|---|---|---|---|---|---|
| bcopy | 28.9690 | ngV | 0.0330 | 0.9810 | 29.6030 | 0.0437 | 1.2930 |
| arith | 3.4092 | ngM | 0.3311 | 1.1294 | 2.5548 | 0.3948 | 1.0070 |
| branch | 1.8485 | ngC | 0.8392 | 1.5524 | 3.3663 | 0.4498 | 1.5145 |
| isort | 1.9640 | ngB | 0.6686 | 1.3122 | 2.7156 | 0.4395 | 1.1963 |
| sort | 2.7135 | ngB | 0.6684 | 1.8136 | 2.4341 | 0.5111 | 1.2321 |
| leafcall | 3.3651 | ngI | 0.3053 | 1.0251 | 2.7641 | 0.3812 | 1.0511 |
| matmul | 1.6434 | ngB | 0.7942 | 1.3059 | 2.2229 | 0.6097 | 1.3529 |
| sieve | 2.0183 | ngB | 0.7627 | 1.5453 | 2.4795 | 0.5894 | 1.4614 |
| linear | 1.2396 | ngF | 0.9174 | 1.1390 | 1.8223 | 0.6977 | 1.2707 |

leafcall with CALL+INL and bcopy with VEC reach gcc -O2 (within 5% on X925: 1.025 and 0.981). The loops that stay
1.3 to 1.8 times slower than gcc after their ladder (sort, sieve, branch, matmul on X925) still run more
instructions per pass than gcc's (section 1: rungs stop at 4 to 13, gcc's loops are about 4 to 7, branch's
Collatz step is branchless CSINC in gcc). Which gcc transformations make up that rest was not taken apart in this
round.

## 4. Steps that were slower, and why that matters

Four of the 40 step factors are above 1 with their whole interval:

| core | kernel | step | factor | what the loop waits on |
|---|---|---|---|---|
| X925 | linear | LICM+ROT (ngL/ngA) | 1.0246 | the FADD chain (each sum waits for the previous one) |
| X925 | matmul | BCE (ngB/ngL) | 1.0346 | the 2400-byte column stride (memory) |
| A725 | arith | LICM+ROT (ngL/ngA) | 1.0175 | the UDIV chain (one divide per pass) |
| A725 | linear | BCE (ngB/ngL) | 1.1109 | the FADD chain |

All four are loops bound by one long chain (a divide, a floating-point add, or a cache miss per pass), where the
number of other instructions matters little, as pre-registered for matmul and linear. Removing instructions also
moves the loop's head and its branch to new addresses; the plan-breaker D arm already showed that placement alone
moves fib38 by 18% on the A725. These factors are kept as measured and enter the ranking as they are. The
smallest experiment that would separate placement from the pass: one control arm per case with omc's own loop
moved to the rung's loop address (same instructions, new placement), timed in the same blocks.

## 5. sha and chacha: MODELED, not measured

Both are straight-line after omc unrolls them, so a hand ladder would mean rewriting thousands of words; the
pre-registered model is used instead. Inputs:

- p(P): the fraction of the hot code's executed instructions per 64-byte block that pass P removes, from the
  census in section 1 (each instruction of the hot functions in omc's disassembly put in one class: constant
  rebuild = LICM+ROT, bounds-check compare and branch plus the `while` bound counter = BCE, spill and reload around
  calls = CALL). sha: 3650 instructions per block; chacha: 6871.
- e(core): how much time a removed loop instruction is worth on that core, the median over this round's measured
  LICM+ROT and BCE steps of (1 - step factor) / f, where f is the fraction of the loop's instructions that step
  removed (loop sizes in section 1).
- Model: step factor = 1 - e(core) p(P).

What the model cannot see: the 592 register copies in sha's rounds (9 per round, the a..h rotation that a register
allocator renames away) belong to no measured pass; both cores eliminate many moves at rename, so their worth is
not estimated here. chacha's 64-byte XOR step would also vectorise (VEC); only bcopy measures VEC, and its loop is
the same shape, so it is reported as an analogy, not folded into the ranking.

Results (Wolfram, `{x925,a725}/wolfram-rank-ngA-*`):

| | X925 | A725 |
|---|---|---|
| e(core) = median of (1 - step) / f over 14 measured LICM+ROT and BCE steps | 0.1205 | 0.6288 |
| sha LICM+ROT (p = 0.0025) | 0.9997 | 0.9984 |
| sha BCE (p = 0.0373) | 0.9955 | 0.9766 |
| sha CALL (p = 0.0142) | 0.9983 | 0.9910 |
| chacha LICM+ROT (p = 0.1560) | 0.9812 | 0.9019 |
| chacha BCE (p = 0.2768) | 0.9667 | 0.8259 |
| chacha CALL (p = 0.0259) | 0.9969 | 0.9837 |

The per-step values of (1 - step) / f range from -0.47 to 1.20 (the four slower steps give the negative ones), so
e is a rough central value; the modeled factors are MODELED, not measured, and move the ranking only for BCE on
the A725 (1.109 to 1.128).

## 6. fib38 and fib40 (cited, not re-measured)

From `evidence/20261107T0830Z-planbreaker-v2/RESULTS.md`, clean medians: ngA (CALL: callee-saved registers instead
of omc's spills) over omc X925 0.578 (fib40) and 0.591 (fib38), A725 0.888 and 1.087; ngE (the second recursive
call turned into a loop, named REC here) over omc X925 0.350 and 0.357, A725 0.633 and 0.634. In the ranking CALL
uses ngA/omc and REC uses (ngE/omc) / (ngA/omc), a quotient of two cited medians, not a per-block step.
The A725 fib38 CALL factor above 1 is a placement effect (ngD, the same code with fib aligned to 64 bytes, is
0.816 of ngA there).

## 7. Validity

- Rows: X925 3196 and A725 3196, all `ok`, no `fail`, no `refused`; rc 0 on both rounds.
- A/A: 18 of 18 pass (section 2); A/A cannot detect contention that slows both copies alike, so the rounds are
  not contention-cleared. Neighbouring jobs: `OVERLAP.md`.
- Contamination scan: 3 (block, case) pairs flagged on X925 and 11 on A725; clean n is 29 to 31 for every case,
  above the 21 the verdict needs.
- Records: `x925/` and `a725/` hold start and end time, load, the cluster's processes at start and end, MIDR
  (X925 0x410fd851, A725 0x410fd871), the exact command (`command.txt`, `round.sh.txt`), raw rows, stderr.
- X925 ran 12:09:07Z to 12:15:29Z under pool-8-9.lock (after bench399 released it); A725 ran 11:54:55Z to
  12:09:06Z under pool-10-11.lock. The two rounds did not overlap each other.
- The first analysis judged the first rungs against omc instead of ngA (`wolfram-rank-*`, kept); the ngA-based
  ranking (`wolfram-rank-ngA-*`) is the result, and differs from it only in the fourth decimal.
- Limits: one machine, one core of each type, time only (no counters: perf_event_paranoid is 4). The hand arms
  are input-specific binaries, so nothing here is QUALIFIED. The loop sizes behind f and p are static counts
  (section 1), not executed-instruction counts.

## 8. Receipts

- `PREREG-payoff.md` (commit b5f46745, BOARD 11:54:28Z), `hand.om`, `hand/*.spec`, `hand/*.words`,
  `hand/payoff-manifest.sha256`.
- `evidence/20261107T1155Z-payoff/{x925,a725}/wolfram-ngA-{query.wl,result.txt}`: every arm against ngA, A/A.
- `evidence/20261107T1155Z-payoff/{x925,a725}/wolfram-wall-{query.wl,result.txt}`: rung-to-rung steps.
- `evidence/20261107T1155Z-payoff/{x925,a725}/wolfram-rank-ngA-{query.wl,result.txt}`: A/A verdict and intervals,
  this-round over baseline omc/gcc, e(core), modeled factors, slower steps, ranking, all passes together.
- `evidence/20261107T1155Z-payoff/wolfram-summary-{query.wl,result.txt}`: removed fractions f and p, residual gap.
- `evidence/20261107T1155Z-payoff/OVERLAP.md`: the jobs that ran beside each round.
