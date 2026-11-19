# protocol/: Pure-Omega units (28 verified units)

This layer integrates **95 pure-Omega (`.om`) files** from **11 canonical Interplane repositories** (82 files imported with full Git history preserved under `protocol/import/<repo>/`, plus 13 pure-Omega files converted from `rad-id-sync`, `open-humanity`, and `synapse`), plus pure-Omega core/extension units under `protocol/aien-protocols/` and `protocol/interplane/`.

## Unit table and gate

[`protocol/units.tsv`](units.tsv) lists **28 units** (`NAME` followed by ordered `.om` parts, single spaces), including 17 imported units, 6 converted units (`rad_id_sync_{main,test}`, `open_humanity_{main,test}`, `synapse_core_{main,test}`), and 5 core/extension units (`aien_protocols_core_{main,test}`, `interplane_core_{main,test}`, `aien_protocols_ext_test`). [`protocol/units-gate.om`](units-gate.om) (`OMEGA-PROTOCOL-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

The gate also runs every unit named in [`protocol/units-run.tsv`](units-run.tsv) (`tests/gates/run.sh protocol-units`): a `run` row must exit 0 from the repository root with stdin `/dev/null`, write no stderr, and end its stdout with the recorded line; a `not_run` row is built only, printed `NOT_RUN` with its reason and never counted as a pass. Every `*_test` unit needs a row. Today: 3 run, 0 not_run.

Note: `protocol/omnet/om/quantity/quantity.om` defines `struct qty`, which collides with keyword `qty` (id 223) added in a later `omc`; `omnet_tkad` is therefore omitted from `protocol/units.tsv` until `omnet` renames that struct.

Files imported under `protocol/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `protocol/units.tsv`; they remain under `protocol/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **5818** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`protocol/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
