# PREREG addendum: D8 plan-breaker, hand-built NG fib vs omc vs gcc -O2 (lane ng-bench)

Written 2026-11-07 ~08:10Z, committed and its sha256 posted on the BOARD before the first timed row. Everything
in `PREREG.md` (harness, block design, interval, validity rules, decision rule, Wolfram-only statistics) applies
unchanged; this file names only what differs.

## Question

DECISIONS.md D8: does a fib with callee-saved registers and liveness-based call saves (fewer stores and loads per
call) run faster than omc's fib? "If save traffic falls and time does not, re-plan from measured cycles." Cycle
counters are not readable on this host (`perf_event_paranoid` = 4), so this round measures time only.

## Arms

Binaries built by ng-a64 (not rebuilt here), copied from `~/handoffs/hive-ng/a64/evidence/fib-planbreaker/` and
checked against its `SHA256SUMS` before copying. Sources there: `fib.om` = frozen `kernels/fib40.om`,
`fibeff.om` = frozen `kernels/fib38.om` (byte-identical, checked with `cmp`).

| arm | fib40 binary (sha256) | fib38 binary (sha256) | what it is (ng-a64, BOARD 08:05:54Z) |
| --- | --- | --- | --- |
| `omc` | `fib_omc` `6d59acdc9b76de74673efbd0553d7b6fa7e2f34675abcf2d6b6b1bab3f0f4407` | `fibeff_omc` `d46713018d37786e6205f72cc309ceeb82c456b53034cbbc89b0a7db2adc662a` | omc 5f90edea output; identical to the baseline omc arm |
| `ngA` | `fib_A` `047b30b2f8bfa9719a3e1ad2b31a435ad1afe87fef93bb01a7c2f3e873624f24` | `fibeff_A` `6c1da7a551e87d09115a02101351cd723d6a85688e2fe66519f98167520075dd` | omc output with only `fib` replaced: x19 callee-saved, one 16 B frame, STP/LDP, leaf path frameless |
| `ngB` | `fib_B` `b13be267f79178c0973499949bbaefb596dde3a79a70d68e9633b7a42b819217` | `fibeff_B` `9aea19844d1cd798e3c3b818d9688e6dcbfaf834ae32a802822be34821fb4078` | A with STR/LDR instead of STP/LDP |
| `ngE` | `fib_E` `1915931f4211a8e5ba96877b0c76530eed8f12a55ef92b7099c025eb8c8d3d5b` | `fibeff_E` `31fb760ca041d69fea5a3eff68d6041e42f319fb57d279e682d6b0f2f6276a49` | A with the second recursive call turned into a loop (gcc -O2 shape) |
| `gccO2` | built here from frozen `kernels/fib40.c` | built here from frozen `kernels/fib38.c` | `gcc -O2 -static`, as in PREREG.md (ng-a64's `fib_gcc` is not used) |

Cases: `fib40` (stdout only) and `fib38` (stdout plus one in-process ns line on stderr). Wants: frozen
`kernels/want/fib40.sha256`, `fib38.sha256`.

## Rounds

Same command shape as PREREG.md, own bench DIR (`/tmp/ngb/pb`), arms `omc ngA ngB ngE gccO2`:
`ngbench run 31 3 DIR omc ngA ngB ngE gccO2 -- fib40 fib38`, first on core 9 (X925) under
`flock -x -w 3600 ~/handoffs/hive/queen/pool-8-9.lock`, then core 11 (A725) under
`flock -x -w 3600 ~/handoffs/hive/queen/pool-10-11.lock`, `taskset -c N nice -n 10`. Load and cluster processes
recorded at start and end of each round, as in PREREG.md.

## Reported

Per case per core, with the PREREG.md interval [r(10), r(22)] over 31 blocks: ngA/omc, ngB/omc, ngE/omc (the
plan-breaker ratios), ngA/gccO2, ngE/gccO2 and omc/gccO2 (context). Secondary: the fib38 in-process ns ratios.

## Decision (fixed now)

Per PREREG.md: ngX is faster than omc on a core when the interval's upper end is below 1, slower when its lower
end is above 1, otherwise no difference detected. The D8 plan-breaker fires for a core type when ngA is slower or
not faster than omc on both fib40 and fib38 on that core type; the result is reported to omp-queen-ng as measured,
and the re-plan decision is the queen's.
