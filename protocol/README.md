# protocol: security networking, wire protocols and Synapse coordination of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the protocol, networking and coordination layer (`omnet`, `aien-protocols-mv`, `interplane-mv`, `synapse-map`, `synapse-board`, `synapse-claims`, `synapse-pulse`, `synapse-mcp`, plus pure-Omega conversions of `rad-id-sync`, `open-humanity`, and `synapse`).

Everything under `protocol/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`protocol/import/`) and tables listing what compiles and what remains non-Omega upstream (`protocol/NOT-YET-OMEGA.tsv`). **Only pure Omega lives here.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `protocol/omnet/` | `omnet` (`rad:z2Q1eD3rqPUGnsxnhd4dDzFDMQqu`) | `b8128f2dfff6` | 47 | 11 | 143 |
| `protocol/aien-protocols/` | `aien-protocols-mv` (`rad:zzxgxYRc5tw6VwYXkQNLC2hqKkfb`) | `6d71e81b5c84` | 3 | 2 | 1046 |
| `protocol/interplane/` | `interplane-mv` (`rad:zNhNbqYvgSBEHBq9vvE8xpbcBzGa`) | `0a468827d3e4` | 3 | 10 | 4544 |
| `protocol/synapse/map/` | `synapse-map` (`rad:z3p7NNQByiXZGsJC4cCifdTybaajY`) | `945934bb3277` | 10 | 2 | 22 |
| `protocol/synapse/board/` | `synapse-board` (`rad:z4GbvxiCiGHVJdjHjodUSBkjSYKxw`) | `7564cafa9ec1` | 7 | 5 | 16 |
| `protocol/synapse/claims/` | `synapse-claims` (`rad:z49HbHSymTiZKMLfpMKRHJcuq2NQv`) | `27b8023f1fe5` | 7 | 5 | 15 |
| `protocol/synapse/pulse/` | `synapse-pulse` (`rad:z3aHmQm9aSg8rD5jEcxJFCSQRh21i`) | `f4d088e97048` | 3 | 5 | 14 |
| `protocol/synapse/mcp/` | `synapse-mcp` (`rad:z3WKv88a3DbKEkvxsu2uDSR7a22ap`) | `bcd37a1ceb8a` | 2 | 2 | 18 |
| `protocol/rad-id-sync/` | `rad-id-sync` (`rad:z4YVa7BSf1MGTrHoJewK8iWQcyHbC`) | `cd94ae76281a` | 3 | converted | 22 |
| `protocol/open-humanity/` | `open-humanity` (`rad:z2jftNw1LLYTNgj8DNoh1TGGNmEmP`) | `54778b62acf7` | 6 | converted | 42 |
| `protocol/synapse/core/` | `synapse` (`rad:zMGRREr2tmtRqpo4mMjpzkZdUGXN`) | `f9aebaa73925` | 7 | converted | 755 |

Total in `protocol/`: **102 `.om` files** (82 imported across 42 history-preserving commits + 20 newly converted pure-Omega `.om` files across `rad-id-sync`, `open-humanity`, `synapse`, `aien-protocols-mv`, `interplane-mv` v0.3.0 conformance & AIEN adapter, and `crumb-spec` legacy/archived BLAKE3 ledger verifier; active workflow `.crumb` files remain retired per DRA-97; non-`.om` upstream files for the imported repos are listed in [`protocol/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## One compiler

Every unit in [`protocol/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`protocol/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `protocol/units-gate.om` (`OMEGA-PROTOCOL-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om protocol/units-gate.om; } | seed/out/omc > protocol-units-gate
chmod +x protocol-units-gate
./protocol-units-gate seed/out/omc /tmp/protocol-units-gate-scratch
```

Wiring `OMEGA-PROTOCOL-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
