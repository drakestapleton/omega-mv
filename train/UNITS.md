# train/: Pure-Omega units (80 verified units)

This layer integrates **195 pure-Omega (`.om`) files** from **5 canonical Interplane repositories** with full Git history preserved under `train/import/<repo>/`.

## Unit table and gate

[`train/units.tsv`](units.tsv) lists **80 units** (`NAME` followed by ordered `.om` parts, single spaces). [`train/units-gate.om`](units-gate.om) (`OMEGA-TRAIN-UNITS`, mirroring `gpu/units-gate.om`) checks `seed/out/omc.sha256`, compiles every unit twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`. Two of the units were written in this repository rather than imported: the Omega coding benchmark tool and its task file (`train/omega-llm/tools/bench/`).

`ollm_aarch64`, `ollm_x86linux`, `ollm_x86efi` and `ollm_a64efi` compose `spec.om` between `bpe.om` and `cli.om` (aien-train `f1bebdf` `tests/omegallm/build.sh` order); the refreshed `cli.om` does not compile without it. `ollm_darwin` is the Darwin `<plat>` slot: the same core parts with `mio.om` in place of `lio.om`, then `noserve.om` and `nogpu.om` (upstream `ollm-darwin.om` composition). `seed/out/omc` has no `target a64macos` (it refuses that line with error 25), so the row carries no target line and compiles for this compiler's default Linux AArch64 target; a Darwin Mach-O build of it is `NOT_RUN` here.

Files imported under `train/` that are library parts composed only by external harnesses, older-pin units, or deliberate compiler-refusal fixtures are not listed as standalone rows in `train/units.tsv`; they remain under `train/` with their upstream history for direct porting onto `seed/out/omc`.

## Not here yet

All **1730** non-Omega first-party files (outside `evidence/` and `vendor/`) from these repositories stayed upstream and are catalogued in [`train/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv).
