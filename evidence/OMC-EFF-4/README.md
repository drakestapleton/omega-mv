# OMC-EFF-4 evidence (lane ng-bench, 2026-11-07)

Status: HOST_TESTED on the Spark, core 1 (`taskset -c 1 nice -n 10`), a shared build core. No timing claim
is made from any row here; the raw files are kept to show the drivers' behaviour.

Pins: omc `seed/out/omc` sha256 `5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df`
(omega-mv 943d9555). Source: branch `perf/omc-efficiency-baseline` at `d26bb9f2` (commit `3a49c653` merged
with main 943d9555), clean tree (`source_dirty 0` in each provenance). Drivers built from that tree by that omc:
`run` sha256 `559994d51a83db19a565acb2ae5802b77d61bec7c6ccbed580da39eb98c66309`, `selftest` sha256
`36374f66a9c0185b6827b1058e3bbc7b08444e92057cd9961e999b5a0a23bb3a`.
`perf_event_paranoid` is 4 on this host, so counters are off and the counter check is NOT_RUN.

| file | command | result |
|---|---|---|
| `selftest-fixed-conductor.txt` | `selftest OMC HERE SCRATCH` | 16 PASS, `NOT_RUN counters_nonzero`, `SELFTEST fails=0 not_run=1`, rc 0 |
| `selftest-old-conductor-d11a7177.txt` | same, HERE = `bench/omc_efficiency` from d11a7177 (old conductor) | `SELFTEST fails=9 not_run=1`, rc 1; the two control checks show `ctl_detected=1` for a control that never produced a valid run |
| `run-om1/` | `run HERE OMC OUT 1` | rc 0, `build_rc 0`, `run_rc 0` |
| `run-om2ab/` | `run --profile om2 --ab HERE OMC OMC 5 OUT 1` | rc 0, `om1-identity.txt` says `same` seven times |
| `run-fail/` | `run HERE' OMC OUT 1`, HERE' = this tree with `want/fib.out` changed to `1` | rc 1, `run_rc 1`, `S rows=672 ok=432 fail=72 ctl_detected=168` |
| `run-fail-old-runsh.txt` | `sh run.sh OMC OUT 1` from d11a7177 with the same `want/fib.out` change | the old script on the same failing conductor run (negative control for finding 2) |
| `run-refusals/` | existing OUTDIR; no arguments; `--profile om3`; `--ab` seed 0; CPU `1x` | each rc 64 with its message; no directory created |
| `equivalence-run-sh.txt` | run.sh (d11a7177) and run.om on the same omc and HERE, om1 baseline and om2 A/B | `arms.sha256`, `sizes.txt`, all 28 arm binaries, the 7 mutants and the C disassembly identical; same `S` rows |
