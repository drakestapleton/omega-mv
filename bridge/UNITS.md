# bridge/: Pure-Omega units (175 verified units)

This layer integrates **217 pure-Omega (`.om`) files** from **4 canonical Interplane repositories** with full Git history preserved under `bridge/import/<repo>/`.

## Unit table and gate

[`bridge/units.tsv`](units.tsv) lists **175 units** (`NAME` followed by ordered `.om` parts, single spaces). [`bridge/units-gate.om`](units-gate.om) (`OMEGA-BRIDGE-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

Note: existing CUDApp compatibility slices (`bridge/cuda/`, `bridge/nvml/`, `bridge/shlib/`) retain their existing gates untouched; `bridge/units.tsv` covers the newly integrated pure-Omega units from `omega-bridge`, `omega-bridge-kit`, `ggml-omega`, and `babel`.

Files imported under `bridge/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `bridge/units.tsv`; they remain under `bridge/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **316** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`bridge/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
