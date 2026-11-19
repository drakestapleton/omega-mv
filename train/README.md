# train: training, neural network primitives and kernel labs of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the training and compute-primitive layer (`aien-train` including `ollm` across `aarch64`/`x86linux`/`x86efi`/`a64efi`, `omega-dnn`, `omega-blas`, `openaccel-lab`, `omega-kernel-template`).

Everything moved under `train/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`train/import/`) and tables listing what compiles and what remains non-Omega upstream (`train/NOT-YET-OMEGA.tsv`). **Only pure Omega moved in.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `train/aien-train/` | `aien-train` (`rad:zKrfazKqYNFuXDDkYdptxJicGLEq`) | `b9bafc3c5a45` | 158 | 162 | 1401 |
| `train/dnn/` | `omega-dnn` (`rad:z3EEujVZkpBNXbCVdnrENJuoMKBdg`) | `4114cbff81f5` | 1 | 1 | 14 |
| `train/blas/` | `omega-blas` (`rad:z47VdC9EFsF4dFyH1QJ1C2JNJK4JS`) | `20180faae23c` | 1 | 1 | 123 |
| `train/openaccel-lab/` | `openaccel-lab` (`rad:zv2LrXa7mmHpfSKbS6ZAYMNrm9QS`) | `6623508d7280` | 32 | 1 | 188 |
| `train/kernel-template/` | `omega-kernel-template` (`rad:z22odFP9kDcxcbzmc2vapZy72ztjT`) | `02050226cf24` | 1 | 1 | 14 |

Total imported in `train/`: **193 `.om` files** across **166 history-preserving commits** (1740 non-`.om` first-party files stayed upstream and are listed in [`train/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## One compiler

Every unit in [`train/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`train/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `train/units-gate.om` (`OMEGA-TRAIN-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om train/units-gate.om; } | seed/out/omc > train-units-gate
chmod +x train-units-gate
./train-units-gate seed/out/omc /tmp/train-units-gate-scratch
```

Wiring `OMEGA-TRAIN-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
