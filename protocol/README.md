# protocol: security networking, wire protocols and Synapse coordination of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the protocol, networking and coordination layer (`omnet`, `aien-protocols-mv`, `interplane-mv`, `synapse-map`, `synapse-board`, `synapse-claims`, `synapse-pulse`, `synapse-mcp`).

Everything moved under `protocol/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`protocol/import/`) and tables listing what compiles and what remains non-Omega upstream (`protocol/NOT-YET-OMEGA.tsv`). **Only pure Omega moved in.**

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

Total imported in `protocol/`: **82 `.om` files** across **42 history-preserving commits** (5818 non-`.om` first-party files stayed upstream and are listed in [`protocol/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

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
