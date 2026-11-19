# si: Sovereign Intelligence front door, architecture, verification, MCP, harness and master ledger

Mirrors [gpu/README.md](../gpu/README.md) for the Sovereign Intelligence front-door tools, architecture/benchmark/receipt checkers, MCP server, harness examples, Rosetta corpus, editor fixtures and master integration ledger (`si/STACK.tsv`).

Everything moved under `si/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`si/import/`) and tables listing what compiles and what remains non-Omega upstream (`si/NOT-YET-OMEGA.tsv`). **Only pure Omega moved in.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `si/front-door/` | `sovereign-intelligence` (`rad:z2JJz4RDfZZxKGBLn6UhmW5p9VJQj`) | `6e44b5cfc22c` | 27 | 29 | 839 |
| `si/architecture/` | `aien-architecture-mv` (`rad:z37zcFYooiuCCZsf5L74eeFJYiwWM`) | `a692b38a28d4` | 27 | 23 | 1327 |
| `si/benchmarks/` | `benchmarks-mv` (`rad:z2nYCN9XZAPjNohqT8bz46rcs9zvZ`) | `033d0149cbfe` | 31 | 10 | 2895 |
| `si/receipts/` | `aien-receipts` (`rad:z4HXNamwwXyfN11ZBJXAQpdMKvojz`) | `53eefaaa3860` | 1 | 1 | 826 |
| `si/mcp/` | `omega-mcp` (`rad:z3e8UBQVfwEcESJrcTWEbyMAHWFBZ`) | `bb2ba1e28668` | 96 | 15 | 34 |
| `si/harness/` | `omega-harness` (`rad:z39gvwWsnkRZsAConQLjaKiNVLHfW`) | `041ba4d59f74` | 150 | 32 | 360 |
| `si/rosetta/` | `omega-rosetta` (`rad:z3ZYVx6LRT6gkwLc13zR94wtENPn3`) | `54e42583435b` | 367 | 3 | 836 |
| `si/editors/tree-sitter/` | `tree-sitter-omega` (`rad:z3Jfv1utyaw4Nm83pgmJ4yQfVmpse`) | `7b9820da408f` | 3 | 2 | 62 |
| `si/editors/vscode/` | `vscode-omega` (`rad:z2cJRW4NtoaUva2wZCPiqxXpMBktn`) | `74ac113b48bb` | 3 | 1 | 22 |
| `si/packages/` | `omega-packages` (`rad:z2BMvbfiNQ7fxq2A3E1vAUsXDDE8r`) | `b7feeb499770` | 1 | 1 | 21 |

Total imported in `si/`: **706 `.om` files** across **117 history-preserving commits** (7222 non-`.om` first-party files stayed upstream and are listed in [`si/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## Master Sovereign Intelligence Ledger

[`si/STACK.tsv`](STACK.tsv) indexes every public Sovereign Intelligence repository across all layers of `omega-mv`:

- **46 repositories integrated** (pure `.om` moved with full Git history): `omega-mv` itself, `CUDApp` (`gpu/`, `bridge/`), `aienux` (`aienux/`), plus all 43 remaining `.om`-bearing repositories across `aienux/`, `gpu/`, `bridge/`, `core/`, `train/`, `protocol/`, `apps/`, and `si/`.
- **39 repositories with 0 `.om` files** (`NOT_YET_OMEGA`, including `physics-mv`, `atlas`, `aegis-runtime-mv`, `synapse`, `open-humanity`, `aienix`, `spark-hive`, `spark-dream`, `spark-debugger`, `openclaw-rs`, etc.): stayed upstream with zero foreign code imported, awaiting pure-Omega rewrites.
- **1 repository not hosted on Interplane** (`.github`): recorded as `NOT_ON_INTERPLANE`.
- **2 local-only crypto repositories** (`omega-pearl`, `aien-crypto`): excluded by standing rule (`EXCLUDED_LOCAL_CRYPTO`).

`si/directives/` holds four 1-line Omega directive files (`om2.om`, `target-a64efi.om`, `target-x86efi.om`, `target-x86linux.om`) so multi-part `units.tsv` rows across all layers compose with zero shell wrappers.

## One compiler

Every unit in [`si/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`si/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `si/units-gate.om` (`OMEGA-SI-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om si/units-gate.om; } | seed/out/omc > si-units-gate
chmod +x si-units-gate
./si-units-gate seed/out/omc /tmp/si-units-gate-scratch
```

Wiring `OMEGA-SI-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
