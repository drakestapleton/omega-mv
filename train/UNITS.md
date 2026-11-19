# train/: Pure-Omega units (77 verified units)

This layer integrates **193 pure-Omega (`.om`) files** from **5 canonical Interplane repositories** with full Git history preserved under `train/import/<repo>/`.

## Unit table and gate

[`train/units.tsv`](units.tsv) lists **77 units** (`NAME` followed by ordered `.om` parts, single spaces). [`train/units-gate.om`](units-gate.om) (`OMEGA-TRAIN-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Files imported under `train/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `train/units.tsv`; they remain under `train/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **1740** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`train/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
