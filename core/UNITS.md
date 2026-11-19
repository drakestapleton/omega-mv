# core/: Pure-Omega units (51 verified units)

This layer integrates **173 pure-Omega (`.om`) files** from **12 canonical Interplane repositories** (151 files imported with full Git history preserved under `core/import/<repo>/`, plus 22 pure-Omega files converted from `hive-not-swarm`, `spark-dream`, `spark-hive`, `mobhub`, `openclaw-rs`, and `aegis-runtime-mv`), plus pure-Omega `sovereign-core` and `rsi` subsystem test units.

## Unit table and gate

[`core/units.tsv`](units.tsv) lists **51 units** (`NAME` followed by ordered `.om` parts, single spaces), including 32 imported units, 12 converted units (`hive_not_swarm_{main,test}`, `dream_{main,test}`, `hive_{main,test}`, `mobhub_{main,test}`, `openclaw_{main,test}`, `aegis_{main,test}`), and 7 subsystem test units (`sovereign_core_{scheduler,serve,runtime,kv_store,closure}_test`, `rsi_{governance,eval}_test`). [`core/units-gate.om`](units-gate.om) (`OMEGA-CORE-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

The gate also runs every unit named in [`core/units-run.tsv`](units-run.tsv) (`tests/gates/run.sh core-units`): a `run` row must exit 0 from the repository root with stdin `/dev/null`, write no stderr, and end its stdout with the recorded line; a `not_run` row is built only, printed `NOT_RUN` with its reason and never counted as a pass. Every `*_test` unit needs a row. Today: 6 run, 0 not_run.

Files imported under `core/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `core/units.tsv`; they remain under `core/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **6993** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`core/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
