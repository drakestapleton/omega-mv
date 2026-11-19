# apps/: Pure-Omega units (119 verified units)

This layer integrates **395 pure-Omega (`.om`) files** from **5 canonical Interplane repositories** with full Git history preserved under `apps/import/<repo>/`.

## Unit table and gate

[`apps/units.tsv`](units.tsv) lists **119 units** (`NAME` followed by ordered `.om` parts, single spaces). [`apps/units-gate.om`](units-gate.om) (`OMEGA-APPS-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Files imported under `apps/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `apps/units.tsv`; they remain under `apps/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **1976** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`apps/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
