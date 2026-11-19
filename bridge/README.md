# bridge: compatibility, conversion and ecosystem bindings of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the compatibility layer (`omega-bridge`, `omega-bridge-kit`, `ggml-omega`, `babel`), alongside the existing CUDApp compatibility slices (`bridge/cuda/`, `bridge/nvml/`, `bridge/shlib/`).

Everything moved under `bridge/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`bridge/import/`) and tables listing what compiles and what remains non-Omega upstream (`bridge/NOT-YET-OMEGA.tsv`). **Only pure Omega moved in.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `bridge/omega-bridge/` | `omega-bridge` (`rad:z3Hr9ZaiKHwwuNzPK5M8c7uw6pj7y`) | `1e24af598fb2` | 181 | 100 | 250 |
| `bridge/kit/` | `omega-bridge-kit` (`rad:z3wKmtAMKXrdg4Lom9W5JeoPBp2iW`) | `3191f50d70dd` | 2 | 1 | 18 |
| `bridge/ggml/` | `ggml-omega` (`rad:zZnK5QhLTtJTmhHuRi2BtRWQdMU4`) | `a30322c90191` | 24 | 2 | 20 |
| `bridge/babel/` | `babel` (`rad:z3NKsT1A9VzBVsa5ycpHG2hKZTriE`) | `fa3206995222` | 10 | 5 | 28 |

Total imported in `bridge/`: **217 `.om` files** across **108 history-preserving commits** (316 non-`.om` first-party files stayed upstream and are listed in [`bridge/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## One compiler

Every unit in [`bridge/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`bridge/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `bridge/units-gate.om` (`OMEGA-BRIDGE-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om bridge/units-gate.om; } | seed/out/omc > bridge-units-gate
chmod +x bridge-units-gate
./bridge-units-gate seed/out/omc /tmp/bridge-units-gate-scratch
```

Wiring `OMEGA-BRIDGE-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
