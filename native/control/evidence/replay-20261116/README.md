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

Two fresh Claude Opus 5.5 reviews (medium effort) found, and this revision fixes:

1. The new files were labelled AGPL-3.0-only; the tree is Apache-2.0 since
   d863780eb. All twelve `.om` files now carry Apache-2.0.
2. Guards that survived mutation, now each covered by a test:
   zero generation and zero expiry in `actvalid`; the rights bit-subset check
   replaced by a numeric comparison (a smaller child with a bit the parent
   lacks); `actrecon` accepting a ready record (an unstarted or released attempt
   could be marked performed); reserved words 6 and 7 of the authority facts and
   word 7 of the receipt; a prefix that fills the whole context. The delegation
   test also covers a child whose expiry equals its parent's.
3. The compiler pin, the 2026-10-23 expected counts and the workflow wording were
   stale; `../../README.md` and `../659/README.md` were updated.

Kept as written: `kvmatch` runs `kvvalid` on the expected header as well as the
saved one. Once the saved header is valid and words 1..6 must match, the scalar
checks on the expected header can only change which refusal code is returned,
never whether reuse is admitted. Both headers go through the same validator.

## Results

| Run | Compile exit | Run exit | Output |
|---|---|---|---|
| suite action | 0 | 0 | `action checks=241 000` |
| suite delegate | 0 | 0 | `delegate checks=078 000` |
| suite reuse | 0 | 0 | `reuse checks=075 000` |
| stub action | 0 | 1 | `action checks=241 135` |
| stub delegate | 0 | 1 | `delegate checks=078 063` |
| stub reuse | 0 | 1 | `reuse checks=075 072` |
| refusal wrong-action-size | 7 | not run | `omc: line 169: error 7` |
| refusal aliased-action | 19 | not run | `omc: line 168: error 19` |
| refusal wrong-payload-size | 7 | not run | `omc: line 87: error 7` |
| mutant action-attempt | 0 | 1 | `action checks=241 003` |
| mutant action-authority | 0 | 1 | `action checks=241 008` |
| mutant action-binding | 0 | 1 | `action checks=241 072` |
| mutant action-epoch | 0 | 1 | `action checks=241 003` |
| mutant action-unknown | 0 | 1 | `action checks=241 013` |
| mutant delegate-depth | 0 | 1 | `delegate checks=078 001` |
| mutant delegate-rights | 0 | 1 | `delegate checks=078 031` |
| mutant delegate-scope | 0 | 1 | `delegate checks=078 004` |
| mutant reuse-identity | 0 | 1 | `reuse checks=075 031` |
| mutant reuse-payload | 0 | 1 | `reuse checks=075 004` |
| review mutant: drop generation-0 check (action.om) | 0 | 1 | `action checks=241 002` |
| review mutant: drop expiry-0 check (action.om) | 0 | 1 | `action checks=241 002` |
| review mutant: child expiry gt to ge (delegate.om) | 0 | 1 | `delegate checks=078 001` |
| review mutant: rights subset to numeric gt (delegate.om) | 0 | 1 | `delegate checks=078 003` |
| review mutant: actrecon state guard admits ready (action.om) | 0 | 1 | `action checks=241 009` |
| review mutant: actauth drops reserved c6 and c7 (action.om) | 0 | 1 | `action checks=241 004` |
| review mutant: actrecon drops reserved s7 (action.om) | 0 | 1 | `action checks=241 002` |
| review mutant: kvvalid prefix gt to ge (reuse.om) | 0 | 1 | `reuse checks=075 001` |

Review mutants were applied as exact one-line text substitutions on a scratch
copy of the module:

| Mutant | Original line | Replacement |
|---|---|---|
| drop generation-0 check | `if or eq get r 4 0 eq get r 5 0` | `if eq get r 5 0` |
| drop expiry-0 check | `if or eq get r 6 0 ne get r 7 0` | `if ne get r 7 0` |
| child expiry gt to ge | `if gt get c 4 get p 4` | `if ge get c 4 get p 4` |
| rights subset to numeric gt | `if ne and get c 1 get p 1 get c 1` | `if gt get c 1 get p 1` |
| actrecon state guard admits ready | `if not or eq get r 1 2 eq get r 1 3` | `if eq get r 1 4` |
| actauth drops reserved c6 and c7 | `if or ne get c 3 0 or ne get c 6 0 ne get c 7 0` | `if ne get c 3 0` |
| actrecon drops reserved s7 | `if or gt get s 1 2 or ne get s 6 0 ne get s 7 0` | `if or gt get s 1 2 ne get s 6 0` |
| kvvalid prefix gt to ge | `if gt get p 2 get p 3` | `if ge get p 2 get p 3` |

The landing receipt for the exact landed head (commands, exit codes, log
sha256) is kept with the lane's records; this file is the human-readable copy.

## Still open

Trusted authority and receipt verification, durable store and dispatch
integration, concurrency, crash and restart, and GPU or hardware profiles are
NOT_RUN, as in [../659/README.md](../659/README.md).
