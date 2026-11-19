# core: runtime, memory, RSI, mission orchestration and agent core of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the runtime and agent core layer (`aien-sovereign-core-mv`, `aien`, `cortex`, `spark-rsi-mv`, `omega-mission`, `hive-view`).

Everything moved under `core/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`core/import/`) and tables listing what compiles and what remains non-Omega upstream (`core/NOT-YET-OMEGA.tsv`). **Only pure Omega moved in.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `core/sovereign-core/` | `aien-sovereign-core-mv` (`rad:z44GqrPVAPjZkhoD2MWVjqy18ighN`) | `c030d3646133` | 58 | 42 | 6655 |
| `core/aien/` | `aien` (`rad:zDTnULpiVMniD2etkbUozUP5mn6U`) | `db0cf3d29135` | 6 | 5 | 71 |
| `core/cortex/` | `cortex` (`rad:zDrGjCcXxPwjWNYQj52Y9RYzBq1t`) | `2f5f763d79b2` | 45 | 10 | 68 |
| `core/rsi/` | `spark-rsi-mv` (`rad:z4AauBRPXzPNMiAoHZpRpyCee61A2`) | `2edaf6704304` | 31 | 2 | 181 |
| `core/mission/` | `omega-mission` (`rad:z6HYc7ot5JZD8FSfvU77pWdMUdru`) | `87705b4bc7d5` | 3 | 6 | 10 |
| `core/hive-view/` | `hive-view` (`rad:zimVqDToqH8NL2YvgM8fQBQrvgHa`) | `c9d2d6849f7b` | 8 | 7 | 8 |

Total imported in `core/`: **151 `.om` files** across **72 history-preserving commits** (6993 non-`.om` first-party files stayed upstream and are listed in [`core/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## One compiler

Every unit in [`core/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`core/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `core/units-gate.om` (`OMEGA-CORE-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om core/units-gate.om; } | seed/out/omc > core-units-gate
chmod +x core-units-gate
./core-units-gate seed/out/omc /tmp/core-units-gate-scratch
```

Wiring `OMEGA-CORE-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
