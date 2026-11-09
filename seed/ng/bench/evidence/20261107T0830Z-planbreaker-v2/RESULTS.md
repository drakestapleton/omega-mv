# D8 plan-breaker, combined v2 round (lane ng-bench)

Preregistration: `PREREG.md`, `PREREG-planbreaker.md` (decision rule, line 46), `PREREG-planbreaker-D.md`
(arm D), `PREREG-contamination.md` (addendum 3: one 6-arm round per core, ngbench v2 contamination scan,
clean-block verdict). Committed at `f5c4dfc1` and posted on the BOARD at 08:25:51Z, before the first row here.

Harness: ngbench v2 (`seed/ng/ngbench.om` sha256 `9019c996…722e`, binary `ba635152…0200`, pinned omc
`5f90edea…6f6df`). Command per core, from `/tmp/ngb/pb2` (binaries in `manifest.sha256`):
`ngbench run 31 3 DIR omc ngA ngB ngD ngE gccO2 -- fib40 fib38`, pinned with `taskset -c CORE nice -n 10`
under the exclusive pool lock (`flock -x ~/handoffs/hive/queen/pool-8-9.lock` for core 9,
`pool-10-11.lock` for core 11). 3 warm-up and 31 measured blocks; arm order shuffled per block.

| core | type | window (UTC) | rows | rc | contaminated measured blocks | clean n fib40 / fib38 |
|---|---|---|---|---|---|---|
| 9 | X925 | 08:26:02..08:28:00 | 816 ok | 0 | fib40 block 21 | 30 / 31 |
| 11 | A725 | 08:34:31..08:38:58 | 816 ok | 0 | fib40 blocks 28, 30 | 29 / 31 |

The A725 round also flagged fib38 block 0, a warm-up block that no statistic uses.

Metric: per block, an arm's two walls summed over the other arm's two walls. Median and the distribution-free
95% interval [r(k), r(n+1-k)] with k from the binomial table in addendum 3 (n=31: k=10; n=30: 10; n=29: 9).
Computed by the Wolfram kernel; the queries and results are in `{x925,a725}/wolfram-*-{query.wl,result.txt}`,
tables in `stats-wall.tsv` (both cases) and `stats-inproc.tsv` (fib38 in-process ns). The verdict uses the
clean blocks; all-block numbers are in the same tables and match the clean ones to 2 decimals.

## Clean-block results: median [95% interval]

| ratio | X925 fib40 | X925 fib38 | A725 fib40 | A725 fib38 |
|---|---|---|---|---|
| ngA/omc | 0.578 [0.575, 0.584] | 0.591 [0.585, 0.618] | 0.888 [0.857, 0.889] | **1.087 [1.085, 1.100]** |
| ngB/omc | 0.576 [0.575, 0.592] | 0.580 [0.579, 0.584] | 0.888 [0.876, 0.890] | 0.885 [0.882, 0.886] |
| ngD/omc | 0.580 [0.576, 0.589] | 0.577 [0.576, 0.586] | 0.889 [0.884, 0.890] | 0.886 [0.884, 0.891] |
| ngE/omc | 0.350 [0.349, 0.351] | 0.357 [0.356, 0.358] | 0.633 [0.631, 0.635] | 0.634 [0.632, 0.635] |
| ngD/ngA | 1.003 [1.001, 1.015] | 0.984 [0.942, 0.987] | 1.000 [0.998, 1.006] | 0.816 [0.813, 0.820] |
| omc/gccO2 | 3.701 [3.626, 3.707] | 4.002 [3.994, 4.011] | 2.269 [2.256, 2.272] | 2.519 [2.500, 2.528] |
| ngA/gccO2 | 2.132 [2.116, 2.156] | 2.349 [2.333, 2.413] | 2.017 [1.978, 2.022] | 2.732 [2.705, 2.742] |
| ngD/gccO2 | 2.134 [2.123, 2.163] | 2.303 [2.299, 2.331] | 2.017 [2.009, 2.020] | 2.232 [2.218, 2.235] |
| ngE/gccO2 | 1.294 [1.288, 1.298] | 1.427 [1.417, 1.436] | 1.436 [1.432, 1.439] | 1.597 [1.575, 1.601] |

In-process fib38 (ns inside the program) agrees: X925 ngA/omc 0.585, ngD/ngA 0.985; A725 ngA/omc 1.086,
ngD/ngA 0.815.

## Decision under PREREG-planbreaker.md line 46

- X925: ngA is faster than omc on both cases. The plan-breaker does not fire.
- A725: ngA is faster than omc on fib40 and slower on fib38. The rule as written fires only when ngA is not
  faster on both cases, so it does not fire. The fib38 slowdown (8.7%) reproduces the v1 round.
- Placement (addendum 2): D is A with fib aligned to 64 bytes. On A725 fib38, D is 18% faster than A and 11%
  faster than omc. On both core types and both cases, D, B and E are faster than omc. The A725 fib38 result
  for A is therefore a code-placement effect, not a save/restore effect.
- The re-plan decision belongs to omp-queen-ng (posted on the BOARD at the end of each round).

## Earlier rounds

The v1 rounds `20261107T0815Z-planbreaker` and `20261107T0820Z-planbreaker-D` are POSSIBLY CONTAMINATED
(no contamination scan; the D A725 round overlapped another lane's work on core 11). They are kept unchanged
and no verdict is taken from them. Their numbers agree with this round in direction: X925 ngA/omc about
0.6 on both cases; A725 fib38 ngA/omc above 1.
