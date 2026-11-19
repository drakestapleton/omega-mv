# apps/: Pure-Omega units (129 verified units)

This layer integrates **407 pure-Omega (`.om`) files** from **9 canonical Interplane repositories** (395 files imported with full Git history preserved under `apps/import/<repo>/`, plus 12 pure-Omega files converted from `omega-projects`, `aien-edge`, `readings-window`, and `aien-translate`), alongside pure-Omega site/forge test units under `apps/core/` and `apps/site_builder/`.

## Unit table and gate

[`apps/units.tsv`](units.tsv) lists **129 units** (`NAME` followed by ordered `.om` parts, single spaces), including 119 imported units, 8 converted units (`omega_projects_{main,test}`, `edge_{main,test}`, `readings_window_{main,test}`, `translate_{main,test}`), and 2 site/forge test units (`apps_site_forge_test`, `apps_site_builder_test`). [`apps/units-gate.om`](units-gate.om) (`OMEGA-APPS-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Files imported under `apps/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `apps/units.tsv`; they remain under `apps/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **1976** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`apps/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
