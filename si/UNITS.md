# si/: Pure-Omega units (499 verified units)

This layer integrates **720 pure-Omega (`.om`) files** from **16 canonical Interplane repositories** (706 files imported with full Git history preserved under `si/import/<repo>/`, plus 14 pure-Omega files converted from `omega-seed-challenge`, `homebrew-omega`, `harvester`, `aien-harness`, `agent-archive`, and `spark-inquisitor`).

## Unit table and gate

[`si/units.tsv`](units.tsv) lists **499 units** (`NAME` followed by ordered `.om` parts, single spaces), including 487 imported units and 12 converted units (`seed_challenge_{main,test}`, `homebrew_formula_{main,test}`, `harvester_{main,test}`, `aien_harness_{main,test}`, `agent_archive_{main,test}`, `inquisitor_{main,test}`). [`si/units-gate.om`](units-gate.om) (`OMEGA-SI-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Note: `si/front-door/tools/ledger.om` uses the `count` word from SI's local patch (`seed/LOCAL.patch`), which is not in `omega-mv` `main`; it is omitted from `si/units.tsv` until `count` lands in `seed/omc/omc.om`. Deliberate negative-control/refusal fixtures in `si/harness/` and `si/rosetta/` are likewise omitted from `si/units.tsv`.

Files imported under `si/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `si/units.tsv`; they remain under `si/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **7222** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`si/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
