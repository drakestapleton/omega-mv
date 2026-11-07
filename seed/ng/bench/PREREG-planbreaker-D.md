# PREREG addendum 2: D8 plan-breaker variant D (fib A aligned to 64 B) (lane ng-bench)

Written 2026-11-07 ~08:14Z, after the first plan-breaker round (`PREREG-planbreaker.md`) had started timing, so D
is a separate round rather than an amendment. Committed and its sha256 posted on the BOARD before its first row.
Everything in `PREREG.md` and `PREREG-planbreaker.md` applies unchanged; only the arms differ.

## Question

ng-a64 (`~/handoffs/hive-ng/a64/evidence/fib-planbreaker/ANALYSIS.md`): is A's time explained by code placement
(fetch-block alignment of the fib entry and branch targets) rather than by the save/restore count? D is A with the
fib function aligned to 64 bytes. If D is faster than A while A is not faster than omc, placement is the cause.

## Arms

| arm | fib40 (sha256) | fib38 (sha256) |
| --- | --- | --- |
| `omc` | `fib_omc` `6d59acdc9b76de74673efbd0553d7b6fa7e2f34675abcf2d6b6b1bab3f0f4407` | `fibeff_omc` `d46713018d37786e6205f72cc309ceeb82c456b53034cbbc89b0a7db2adc662a` |
| `ngA` | `fib_A` `047b30b2f8bfa9719a3e1ad2b31a435ad1afe87fef93bb01a7c2f3e873624f24` | `fibeff_A` `6c1da7a551e87d09115a02101351cd723d6a85688e2fe66519f98167520075dd` |
| `ngD` | `fib_D` `5672850519e5c621b39d6c6bc3b0bc8128152c448b1683db3fcdd1cd67bee6e5` | `fibeff_D` `b075462d9f8121b4485a1a1a2fabe55e9c621ddf639dbef8bcaec53f4ae2034d` |
| `gccO2` | frozen `kernels/fib40.c`, `gcc -O2 -static` | frozen `kernels/fib38.c`, `gcc -O2 -static` |

Hashes checked against ng-a64's `SHA256SUMS` before copying.

## Rounds

`ngbench run 31 3 DIR omc ngA ngD gccO2 -- fib40 fib38` in `/tmp/ngb/pbd`, core 9 under the exclusive pool-8-9
lock, then core 11 under the exclusive pool-10-11 lock, load and cluster processes recorded as before.

## Reported and decision

Per case per core, interval [r(10), r(22)]: ngD/ngA (placement effect), ngD/omc, ngA/omc (repeat of round 1, a
consistency check across rounds), ngD/gccO2. Decision rule as in PREREG.md: D is faster than A when the ngD/ngA
interval's upper end is below 1. The interpretation (placement or not) is reported to omp-queen-ng as measured.
