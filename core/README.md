# core: runtime, memory, RSI, mission orchestration and agent core of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the runtime and agent core layer (`aien-sovereign-core-mv`, `aien`, `cortex`, `spark-rsi-mv`, `omega-mission`, `hive-view`, plus pure-Omega conversions of `hive-not-swarm`, `spark-dream`, `spark-hive`, `mobhub`, `openclaw-rs`, and `aegis-runtime-mv`).

Everything under `core/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`core/import/`) and tables listing what compiles and what remains non-Omega upstream (`core/NOT-YET-OMEGA.tsv`). **Only pure Omega lives here.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `core/sovereign-core/` | `aien-sovereign-core-mv` (`rad:z44GqrPVAPjZkhoD2MWVjqy18ighN`) | `c030d3646133` | 58 | 42 | 6655 |
| `core/aien/` | `aien` (`rad:zDTnULpiVMniD2etkbUozUP5mn6U`) | `db0cf3d29135` | 6 | 5 | 71 |
| `core/cortex/` | `cortex` (`rad:zDrGjCcXxPwjWNYQj52Y9RYzBq1t`) | `2f5f763d79b2` | 45 | 10 | 68 |
| `core/rsi/` | `spark-rsi-mv` (`rad:z4AauBRPXzPNMiAoHZpRpyCee61A2`) | `2edaf6704304` | 31 | 2 | 181 |
| `core/mission/` | `omega-mission` (`rad:z6HYc7ot5JZD8FSfvU77pWdMUdru`) | `87705b4bc7d5` | 3 | 6 | 10 |
| `core/hive-view/` | `hive-view` (`rad:zimVqDToqH8NL2YvgM8fQBQrvgHa`) | `c9d2d6849f7b` | 8 | 7 | 8 |
| `core/hive-not-swarm/` | `hive-not-swarm` (`rad:z3vAshKTvZpS5xnsPZHjiHobz4U2p`) | `bc6d30e5a1be` | 3 | converted | 39 |
| `core/dream/` | `spark-dream` (`rad:z4UHi17ttdBX6qAfFutgFaL6s1Aga`) | `1bdd98342487` | 3 | converted | 15 |
| `core/hive/` | `spark-hive` (`rad:z2RVudShJWi3She9WLw3DNZDwYvnB`) | `e10a5c84b7bb` | 3 | converted | 20 |
| `core/mobhub/` | `mobhub` (`rad:z3Konv8McLhn67ZBUiCE4bFR5r9tC`) | `ae23cc7f34f6` | 3 | converted | 28 |
| `core/openclaw/` | `openclaw-rs` (`rad:z21SQF1DVwRmpxbTMnSiYxXveiRp1`) | `d491aff96f6a` | 3 | converted | 29 |
| `core/aegis/` | `aegis-runtime-mv` (`rad:z6hhF5wGXCqvkcvxYdcBb12qm3FB`) | `08bb1d97767b` | 7 | converted | 120 |

Total in `core/`: **173 `.om` files** (151 imported across 72 history-preserving commits + 22 newly converted pure-Omega `.om` files across 6 repositories; non-`.om` upstream files for the imported repos are listed in [`core/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

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
