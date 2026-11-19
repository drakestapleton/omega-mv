# core/: Pure-Omega units (44 verified units)

This layer integrates **173 pure-Omega (`.om`) files** from **12 canonical Interplane repositories** (151 files imported with full Git history preserved under `core/import/<repo>/`, plus 22 pure-Omega files converted from `hive-not-swarm`, `spark-dream`, `spark-hive`, `mobhub`, `openclaw-rs`, and `aegis-runtime-mv`).

## Unit table and gate

[`core/units.tsv`](units.tsv) lists **44 units** (`NAME` followed by ordered `.om` parts, single spaces), including 32 imported units and 12 converted units (`hive_not_swarm_{main,test}`, `dream_{main,test}`, `hive_{main,test}`, `mobhub_{main,test}`, `openclaw_{main,test}`, `aegis_{main,test}`). [`core/units-gate.om`](units-gate.om) (`OMEGA-CORE-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Files imported under `core/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `core/units.tsv`; they remain under `core/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **6993** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`core/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
