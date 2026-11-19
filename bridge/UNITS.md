# bridge/: Pure-Omega units (176 verified units)

This layer integrates **217 pure-Omega (`.om`) files** from **4 canonical Interplane repositories** with full Git history preserved under `bridge/import/<repo>/`, plus `bridge/core/`.

## Unit table and gate

[`bridge/units.tsv`](units.tsv) lists **176 units** (`NAME` followed by ordered `.om` parts, single spaces), including `bridge_abi_ggml_test`. [`bridge/units-gate.om`](units-gate.om) (`OMEGA-BRIDGE-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

The gate also runs every unit named in [`bridge/units-run.tsv`](units-run.tsv) (`tests/gates/run.sh bridge-units`): a `run` row must exit 0 from the repository root with stdin `/dev/null`, write no stderr, and end its stdout with the recorded line; a `not_run` row is built only, printed `NOT_RUN` with its reason and never counted as a pass. Every `*_test` unit needs a row. Today: 1 run, 1 not_run. Units whose names do not end in `_test` (fixtures, harness parts, and test-named units such as `allen_test_*`, `cortex_tests_*`, `rsi_tests_*`, `aien_train_tests_*` or `omega_bridge_tests_*`) need no row and stay compile-only unless a row names them.

Note: existing CUDApp compatibility slices (`bridge/cuda/`, `bridge/nvml/`, `bridge/shlib/`) retain their existing gates untouched; `bridge/units.tsv` covers the newly integrated pure-Omega units from `omega-bridge`, `omega-bridge-kit`, `ggml-omega`, and `babel`.

Files imported under `bridge/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `bridge/units.tsv`; they remain under `bridge/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **316** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`bridge/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
