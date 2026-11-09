# Native reverse-mode tape (bounded): `native/autodiff664/tape.om`

Status: IMPLEMENTED and EXERCISED on the host (aarch64 Linux, DGX Spark). Not
QUALIFIED on hardware, not MERGED, not DEPLOYED. Tracks omega-mv #664 (native
autograd) and builds on #663 / PR #674 (`native/ecosystem663/metadata.om`).

## What it is

A handwritten seeded `.om` reverse-mode tape for rank-2 IEEE binary32 tensors.
Values and gradients use native `f32` words. It contains no FFI, no C fallback
and no generated code. Build order:
`native/ecosystem663/metadata.om`, `native/autodiff664/tape.om`, then the consumer.

| word | meaning |
|---|---|
| `tpreset` | empty tape (node count, backward flag, arena offset to 0) |
| `tpleaf r c rg` → id | leaf `[r,c]`; `rg` 1 requires grad |
| `tpset n i v` → 0 | write leaf/node value element `i` |
| `tpadd a b`, `tpsub a b`, `tpmul a b` → id | elementwise, equal shapes |
| `tpmm a b` → id | `[m,k]·[k,n]` |
| `tprelu a` → id | `x > 0 ? x : +0` |
| `tpbcast a rows` → id | `[1,c]` → `[rows,c]` |
| `tpsum a axis` → id | axis 0 → `[1,c]`, axis 1 → `[r,1]` (keepdims) |
| `tpback root` → 0 | reverse pass, seed 1.0, once per tape |
| `tpval n i`, `tpgrad n i`, `tphasg n` | read value / gradient / whether a gradient exists |

## Admission and limits

Each recorded node has an M20 metadata-v1 descriptor (`TD`) and an allocator
snapshot (`TS`). Every operand passes `emcheck` from `metadata.om` before an op
runs, so a stale or non-live operand is refused with the metadata error.
The `tests/autodiff664` `tstale` check exercises this path.

| code | condition |
|---|---|
| −30 | capacity: 33rd node, >64 elements, reduced axis >32, arena full |
| −31 | `tpback` already run or failed, or any op after `tpback` |
| −32 | bad id, shape mismatch, bad layout, bad axis |
| −33 | `tpback` root not `[1,1]` or not requiring grad |
| −1..−8 | passed through from `emcheck` |
| exit 97 | `tpval`/`tpgrad` out of range or on a node without a gradient |

A refusal records nothing (the node count is unchanged).

## Numeric order (the contract the fixture oracle checks)

- **Reductions** use one E1 tile: copy the n ≤ 32 inputs, pad lanes n..31 with
  −0.0, then for d = 16, 8, 4, 2, 1 set `t[i] = t[i] + t[i+d]` for `i < d`.
  This mirrors `src/omega_numeric_reduce.c` `cpu_sum_like` (line 124;
  `OMEGA_REDUCE_SUM_PAD_BITS`).
- **Matmul** output `(i,j)` takes the products `A[i,q]·B[q,j]` in q order, then the
  E1 tile. This is the M20 matmul v1 order (FMUL_RNE products, then the E1 tree).
  Backward: `gA = g·Bᵀ` (products `g[i,j]·B[q,j]` in j order) and
  `gB = Aᵀ·g` (products `A[i,q]·g[i,j]` in i order), each followed by the E1 tile.
- **Backward walk** (`src/autodiff/omega_autodiff.c` `omega_ad_backward`,
  line 511): nodes in decreasing index order, `in0` before `in1`. The first
  contribution to a gradient is stored as is; later contributions are added as
  `grad + contrib` (`accumulate`, line 107). Because there is no zero
  initialisation, signed zeros match the C tape bit for bit.
- **Rules:** SUB `in1` takes `neg g`. MUL takes `g·value(other)`. RELU routes
  `g` only where `x > 0`, so `−0`, `+0` and NaN give `+0`; this matches
  `max_routes_to_a` (line 148) against a zeros operand. BROADCAST sums `g` over
  rows with the E1 tile. SUM spreads `g` along the reduced axis.
- **No contraction:** every `a·b + c` is written as `add (mul a b) c`. The
  pinned compiler emits no fused multiply-add for it. `tape-test.om` `tnofma`
  proves this: with `c = −round(a·b)` the result is exactly +0 on all 64
  trials, while an f64 widening of the same expression is nonzero on at least
  one trial.

## Evidence (host)

The recorded host suite used omega-mv `seed/out/omc`, SHA-256
`be8c51301307555254fc59e351d281aae1aa096d91521777e33a41c8b446448a` (main 9920aab1; the suite
first passed with `62775d2a391cfef7cde64e387655caa9809a267093112910ec76bfa568f3712b`).
That pin is historical. The x86efi compiler from PR #1015 is
`b4f45121f6c6d5d8a6ed0f5c4f3934b7cc4bec369bfa89523699bd33928f9b55`
(`seed/omc/omc.om` `16b4ca40a5bd7796ac08b55d1ceadac1260e52298ed123f45418e77b3221c749`).
On 2026-11-04 the tape suite passed against it natively (DGX Spark, Linux aarch64):
`TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=302`, all three compiled mutants failed with status 1.
The compiler of PR #1022 (`efi 14`) is
`3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194`
(`seed/omc/omc.om` `0effe37afc4ddd0507151c9f2afa34b3e6774eae7006cbecd8c59f11bc386db7`).
On 2026-11-04 the tape suite passed against it the same way (DGX Spark, Linux aarch64, core 9):
`TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=302`, all three compiled mutants failed with status 1.
On 2026-11-07, with the signed-zero padding checks and the fourth mutant added (DRA-14
follow-up), the suite passed against the reseeded compiler
`cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a` (main `6efc4572`, DGX Spark,
Linux aarch64, cores 10-11): `TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=351`, all four compiled
mutants failed with status 1. `tape.om` is unchanged (sha256 `1b4ed431…8bde`).

```sh
OMC=<pinned omc> OUT=<scratch> sh tests/autodiff664/run-tape.sh
# TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=351
```

- `tests/autodiff664/tape-test.om` (351 checks). Expected values come from
  separate code paths in the test: a test-local E1 tile, a sequential sum,
  IEEE identities (`x·x` grad is `x + x`, SUB grad is `neg s`, a sum of −0
  values is −0) and the f64 widening control. No expected value is a
  hand-entered constant. `torder`
  requires at least one input where the tree sum differs from the sequential
  sum, and requires the tape to follow the tree on every input. `tnzsum`,
  `tnzmm` and `tnzbc` (49 checks) feed all −0 inputs to `tpsum` on both axes,
  to the matmul forward and both matmul backward reductions, and to the
  broadcast backward reduction, and require the bits `0x80000000`: a +0 pad
  would turn every one of them into +0. Random inputs cannot see the pad value.
  Deviation from
  the plan: these are not Wolfram-computed literal bit patterns. A rounding
  mistake shared by the tape and the test-local tile would pass here. That case
  is covered elsewhere: by the C M21 fixture replay below, and by the
  exact-rational Wolfram oracle on the full training step in aien-train
  `tests/adtrain/gradient.wl`, which gave 58/58 exact.
- `tests/autodiff664/mutate.om`: four compiled source mutants of `tape.om`
  (SUB sign dropped, MUL operand swapped to `value(in0)`, RELU tie `gt`→`ge`,
  E1 pad +0 instead of −0 in `e1tree`).
  Each compiles with rc 0 and makes the test exit 1, at checks 212, 66, 171 and 305.
  The pad mutant passed the earlier 302-check test (found by the DRA-14 replay,
  aien-train `tests/adtrain/replay/padprobe.om`).
- `tests/test_omega_ad_fixture.c` (`make test-autodiff-fixture FIXTURE=…`)
  replays one MLP step written by the native trainer (aien-train
  `tests/adtrain`, mode D) on the C M21 tape over the M20 CPU table.
  Observed: `exact=75/75 max_ulp=0 verdict=PASS`. The `--mutant-sign` control
  fails as required. The C tape is a disclosed test oracle only; nothing in the
  native tape calls C.
- The fixture is 187 u32 words, 748 bytes: a 6-word header, 106 inputs and 75
  expected values. The plan's "179 words" was an arithmetic slip.
- The GB10 arm is `tests/run_ad_chip.sh` (`GB10_CHIP_RUN=1`,
  `/tmp/aien-gb10.lock`, or the lock its `spark-window` already holds when run
  under `spark-window run`; physics at `physics.lock`). It ran once on 2026-10-29
  at 17:07Z, in a window Drake authorised. Result:
  `AD_FIXTURE_CHIP: exact=75/75 max_ulp=0 verdict=PASS`; the sign-flip control
  exits 1. Receipt: aien-train `evidence/ADTRAIN/gb10/`. This is one fixture on
  one device. The GB10 executes the C M21 replay; the native tape runs on the
  host.

## Not claimed

General autograd (rank >2, more than 32 nodes, DIV/SQRT/MEAN/TRANSPOSE), GPU
launch from `.om` (#638 / CUDApp #35), performance, atomic checkpoint
publication, or any hardware qualification.
