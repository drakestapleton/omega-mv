# PREREG addendum 3: contamination rows and the clean-block rule (lane ng-bench)

Written 2026-11-07 ~08:30Z, before any timed row of the rounds it governs. Committed locally (GitHub pushes
are suspended); the commit sha and this file's sha256 are posted on the BOARD before the first timed row.
`PREREG.md`, `PREREG-planbreaker.md` and `PREREG-planbreaker-D.md` apply unchanged except where this file
says otherwise.

## Why

omp-queen-ng / Manager 08:21Z: an unpinned rustc (affinity 0-19, which ignores the pool locks) ran on cores
10 and 12 and cargo on 8-9 around 08:18Z; a cargo test started 08:21:39Z. Its start is unknown, so every
round timed so far is POSSIBLY CONTAMINATED and is rerun:

| round | evidence dir | status |
| --- | --- | --- |
| X925 full baseline, 08:05:27-08:11:29 | `evidence/20261107T0810Z-baseline/x925` | POSSIBLY CONTAMINATED |
| A725 full baseline, 08:19:56-08:21:28 | `evidence/20261107T0810Z-baseline/a725-ABORTED-v1` | ABORTED (stopped by ng-bench), not used |
| plan-breaker X925, 08:11:29-08:13:04 | `evidence/20261107T0815Z-planbreaker/x925` | POSSIBLY CONTAMINATED |
| plan-breaker A725, 08:13:04-08:16:47 | `evidence/20261107T0815Z-planbreaker/a725` | POSSIBLY CONTAMINATED |
| D X925, 08:13:26-08:14:50 | `evidence/20261107T0820Z-planbreaker-D/x925` | POSSIBLY CONTAMINATED |
| D A725, 08:16:47-08:19:55 | `evidence/20261107T0820Z-planbreaker-D/a725-CONTAMINATED` | CONTAMINATED (overlaps 08:18Z) |

Their rows stay in the tree; no verdict is taken from them.

## Instrument: ngbench v2

`seed/ng/ngbench.om` source sha256 `9019c99695f07763ae6cbffa0dfc83a0484f55a299cf31a7d27ad6536b10722e`,
built by the pinned `seed/out/omc` to binary sha256
`ba6351527ef844836776dbaff44b782c5957225f35a172205ae4d77904ff0200`. The only change from v1 is the
contamination scan (row formats in the source header):

- the timed core is ngbench's `Cpus_allowed_list` (one number; the rounds are started with `taskset -c N`);
  the cluster is `/sys/devices/system/cpu/cpuN/topology/cluster_cpus_list` (0-9 for core 9, 10-19 for
  core 11);
- before (`s`) and after (`e`) the ABBA sequence of every block and case, every task of `/proc/*/task/*/stat`
  is read: field 3 (state) and field 39 (last processor). ngbench's own tasks are excluded (its child has
  exited before every scan). The scans sit between runs, never inside a timed interval;
- `X` rows name every task last on the timed core (any state) and every task in state R or D last on
  another CPU of the cluster. Sleeping tasks elsewhere on the cluster are not named; the `Y` row of each
  scan counts every task read, every task on the cluster, the X rows, the R tasks on the timed core and
  the stat files that could not be parsed, so nothing is dropped without a count;
- `K BLOCK CASE start=N end=N contaminated=0|1`.

Negative control, run before this addendum (untimed, core 1, the build core while another lane compiled):
`K 0 fib38 start=1 end=1 contaminated=1`, the foreign R task `cc1` on cpu 1 in both scans.

## Rule (fixed before the rows)

1. A block (one BLOCK, one CASE: the ABBA sequence the per-block ratio is computed from) is contaminated
   when any foreign task was in state R with last processor equal to the timed core at its start scan or
   its end scan, that is when its `K` row says `contaminated=1`.
2. Every result is reported twice: over all 31 measured blocks and over the clean measured blocks. Warm
   blocks are discarded as before.
3. The verdict of a case on a core uses its clean blocks when at least 21 remain. With n clean blocks the
   95% interval is [r(k), r(n+1-k)] of the sorted per-block ratios, k from the same binomial rule as
   PREREG.md:
   `Table[With[{k = Max[Select[Range[1, 15], CDF[BinomialDistribution[n, 1/2], # - 1] <= 0.025 &]]}, {n, k, n + 1 - k, N[1 - 2 CDF[BinomialDistribution[n, 1/2], k - 1], 4]}], {n, 21, 31}]`
   -> n 21: (6, 16) 0.9734; 22: (6, 17) 0.9831; 23: (7, 17) 0.9653; 24: (7, 18) 0.9773; 25: (8, 18) 0.9567;
   26: (8, 19) 0.9710; 27: (8, 20) 0.9808; 28: (9, 20) 0.9643; 29: (9, 21) 0.9759; 30: (10, 21) 0.9572;
   31: (10, 22) 0.9706.
4. When any case of a round has fewer than 21 clean measured blocks, the round is rerun once, whole. When
   the rerun also falls short, both rounds are reported with all-block results and the matter goes to
   omp-queen-ng; no verdict is claimed.
5. The A/A control (gccO2aa, baseline rounds) is judged on the clean blocks under the same PREREG.md rule.
6. A block is never dropped for any other reason, and no block is dropped silently: the contaminated
   blocks are listed by BLOCK and CASE in the result.

## Rounds governed (in this order)

1. Plan-breaker, one combined round per core: `ngbench run 31 3 /tmp/ngb/pb2 omc ngA ngB ngD ngE gccO2 --
   fib40 fib38`, core 9 under the exclusive pool-8-9 lock, then core 11 under pool-10-11. The binaries
   are exactly those of `PREREG-planbreaker.md` and `PREREG-planbreaker-D.md` (manifest in the evidence
   dir). Six arms in one ABBA rotation instead of two separate rounds: every ratio of both addenda
   (ngA/omc, ngB/omc, ngE/omc, ngD/ngA, ngD/omc, x/gccO2) is then paired inside the same blocks. Decision
   rules of both addenda unchanged.
2. Full baseline, the PREREG.md command, core 9 then core 11.

Each round records lock request/start/end times, load, and the cluster process lists, as before.
