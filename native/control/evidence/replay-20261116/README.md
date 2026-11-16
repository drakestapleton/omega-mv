# Replay onto omega-mv main, 2026-11-16

Evidence class: **EXERCISED** on the Spark host CPU (aarch64 Linux, native, no
QEMU). No GPU, timing, production dispatch or power-loss claim.

- Base: omega-mv `main` at `50feb135306176947a999362dd637d37c907f6fc`.
- Source: the 2026-10-23 branch `feat/om-control-contracts` (19e8168bb,
  6923da4c3), cherry-picked onto that base, then the review fixes below.
- Compiler: in-tree `seed/out/omc`, sha256
  `34d611ca0415eab1728d3234911d90e74af17ba9ab0c581d559f48274d7ca6d3`.
- Commands: those in [../659/README.md](../659/README.md) with `seed/out/omc`
  run directly and no QEMU wrapper. Live record: Linear DRA-312.

## Review fixes in this revision

A fresh Claude Opus 5.5 review (medium effort) of the cherry-picked head found:

1. The new files were labelled AGPL-3.0-only; the tree is Apache-2.0 since
   d863780eb. All twelve `.om` files now carry Apache-2.0.
2. Two guards survived mutation: removing the zero-generation check in
   `actvalid` and removing the zero-expiry check. `tests/action.om` now covers
   both; the delegation test also covers a child whose expiry equals its parent's.
3. The compiler pin and workflow wording were stale; `../../README.md` and
   `../659/README.md` were updated.

## Results

| Run | Compile exit | Run exit | Output |
|---|---|---|---|
| suite action | 0 | 0 | `action checks=225 000` |
| suite delegate | 0 | 0 | `delegate checks=075 000` |
| suite reuse | 0 | 0 | `reuse checks=074 000` |
| stub action | 0 | 1 | `action checks=225 128` |
| stub delegate | 0 | 1 | `delegate checks=075 060` |
| stub reuse | 0 | 1 | `reuse checks=074 072` |
| refusal wrong-action-size | 7 | not run | `omc: line 169: error 7` |
| refusal aliased-action | 19 | not run | `omc: line 168: error 19` |
| refusal wrong-payload-size | 7 | not run | `omc: line 87: error 7` |
| mutant action-attempt | 0 | 1 | `action checks=225 003` |
| mutant action-authority | 0 | 1 | `action checks=225 008` |
| mutant action-binding | 0 | 1 | `action checks=225 072` |
| mutant action-epoch | 0 | 1 | `action checks=225 003` |
| mutant action-unknown | 0 | 1 | `action checks=225 013` |
| mutant delegate-depth | 0 | 1 | `delegate checks=075 001` |
| mutant delegate-rights | 0 | 1 | `delegate checks=075 028` |
| mutant delegate-scope | 0 | 1 | `delegate checks=075 004` |
| mutant reuse-identity | 0 | 1 | `reuse checks=074 031` |
| mutant reuse-payload | 0 | 1 | `reuse checks=074 004` |
| review mutant: drop generation-0 check (action.om) | 0 | 1 | `action checks=225 002` |
| review mutant: drop expiry-0 check (action.om) | 0 | 1 | `action checks=225 002` |
| review mutant: `gt` to `ge` on child expiry (delegate.om) | 0 | 1 | `delegate checks=075 001` |

Review mutants were applied as exact one-line text substitutions on a scratch
copy of the module:
`if or eq get r 4 0 eq get r 5 0` to `if eq get r 5 0`;
`if or eq get r 6 0 ne get r 7 0` to `if ne get r 7 0`;
`if gt get c 4 get p 4` to `if ge get c 4 get p 4`.

## Still open

Trusted authority and receipt verification, durable store and dispatch
integration, concurrency, crash and restart, and GPU or hardware profiles are
NOT_RUN, as in [../659/README.md](../659/README.md).
