# OMC-EFF-4: Omega drivers and two corrected checks (additive)

Status: frozen in the commit that adds this file. `PROTOCOL.md`, `PROTOCOL-2.md`, `PROTOCOL-3.md` and their
evidence are not edited. Arms, rounds, warm-ups, seeds, metrics, statistics, validity rules, the
PROTOCOL-2 section 4 thresholds and the PROTOCOL-3 profile apply unchanged. This file replaces the two
shell drivers with Omega programs and corrects two checks that could pass when they should fail.

## 1. Findings corrected

1. **A control was credited without an output mismatch.** `conductor.om` counted a negative control as
   detected whenever its run was not ok, which includes a control that crashed, exited nonzero or printed no
   runtime line. Such a run proves nothing about the output check. A control is now detected only when the
   run is valid (status 0 and, for timed runs, exactly one runtime line) and its output differs from
   `want/`. A control that does not run validly counts as a failed run (`fail=` in the `S` row), never as a
   detection.
2. **The coordinator dropped conductor failures.** `run.sh` ran the conductor and exited 0 whatever the
   conductor returned, so a run with failed rows looked like a clean run to any caller. `run.om` records
   every conductor exit status in `provenance.txt` (`build_rc`, `build_B_rc`, `build_C_rc`, `run_rc`) and
   exits 1 when any of them is nonzero.

## 2. Counters

The conductor reads `/proc/sys/kernel/perf_event_paranoid`. When it is above 2 an unprivileged `perf stat`
cannot count user-space instructions and cycles; the conductor then writes no `P` rows and its `H` row says
`counters=off`. With counters off, instruction ratios are NOT_RUN, never zero and never a pass.

## 3. Drivers

`run.sh` and `selftest.sh` are removed. Their Omega ports are built by the omc under test (or the pinned
omc) and take absolute paths or paths relative to the working directory:

```sh
omc < bench/omc_efficiency/run.om > run && chmod +x run
./run [--profile om1|om2] HERE OMC OUTDIR [CPU]
./run [--profile om1|om2] --ab HERE BASE CAND SEED OUTDIR [CPU]
omc < bench/omc_efficiency/selftest.om > selftest && chmod +x selftest
./selftest OMC HERE SCRATCH
```

`HERE` is `bench/omc_efficiency`. Every step of `run.sh` is kept with the same files, names, commands and
arguments: provenance, `inputs.sha256`, the PROTOCOL-3 om2 check, the seven mutants, the arm builds,
`disasm-c/`, `arms.sha256`, `om1-identity.txt`, `sizes.txt`, the conductor build and run pinned with
`taskset -c CPU nice -n 19`. The differences:

- `inputs.sha256` lists `run.om` and `selftest.om` in place of the two scripts, and every `PROTOCOL*.md`.
- `provenance.txt` adds `protocol4_sha256`.
- Paths are made absolute against the working directory; symbolic links are not resolved.
- Exit status: 0, 1 (a conductor invocation failed, section 1.2), 64 bad usage, 70 a setup step failed.

`selftest` keeps every check of `selftest.sh` and adds two control checks: a control whose output equals
`want/` but prints no runtime line, and a control that crashes, are each a failed run with
`ctl_detected=0`. Against the conductor before this change both checks fail (`ctl_detected=1`).

## 4. Evidence

`evidence/OMC-EFF-4/`: `selftest` output against the corrected conductor and against the previous one, and
a `run` smoke on a non-timing core showing the files above and the exit status on a forced conductor
failure. No timing claim is made from these runs.
