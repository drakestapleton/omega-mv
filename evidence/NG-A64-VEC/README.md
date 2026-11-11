# NG-A64-VEC: ARMv9.2-A 128-Bit Packed Float Vector Lowering in `seed/ng`

Evidence Level: `HOST_TESTED` (Linux AArch64 host CPU, Cortex-X925 + Cortex-A725; `gate.om` + `rgate.om` + `ngbuild/gate.om` + Lean 4 host check + Wolfram MCP; native x86, GPU, and target-device qualification `NOT_RUN`)

## 1. Seed Lineage (`MEASURED`)

- `seed/rung0/seed0.hex` SHA-256: `baaf081fe6055a768485c5d25d7435681ce00b04cfa80b26c48169f78944e14d` (408-byte loader)
- Rebuilt via `sh seed/omega-from-seed.sh` in an isolated scratch tree (`RC=0`):
  - `stage1 == stage2 == stage3` SHA-256: `f4fa7951816bbd09c5eaaae6692852a70c3c305164b365027c5b683dec7d63e9` (`674,212` bytes, `cmp`-identical to tracked `seed/out/omc` at `3f71977099c5129aecf0feca88d4894dc3764b3e`, unmodified in commit)
- Refreshed `seed/ng` unit manifests (`ngbuild sums`):
  - `seed/ng/src/a64.om`: `89ac6559cd9775972ae4b806698f64c1582b52b94f6249baef7e12954ab7ff10` (`ng.units` composed SHA-256 `c04b90183e23921aec69fc08f9df2e7206ac6bb0a6f81c07aaa07795269c9e9b`)
  - `seed/ng/ngrun.om`: `685a97425cb77240928cac1a7fa09cb2101558de0f0f50d8ab8ccaadb2d51caf` (`ngrun.units` composed SHA-256 `71c4e300abe42052dd9abb7bc1b57ba143dd9fa5d476c71db1431b2871e78665`)

## 2. ARMv9.2-A Advanced SIMD Lowering and Safety Invariants

`seed/ng/src/a64.om` and the differential reference interpreter `seed/ng/ngrun.om` support 16-byte packed IEEE-754 float vectors `vec f32 4` (`i_tk=1, i_t1=13, i_t2=4`) and `vec f64 2` (`i_tk=1, i_t1=14, i_t2=2`):

1. **Memory (`58 vload`, `59 vstore`)**: `LDR Qt, [Xn, #imm12*16]` / `STR Qt, [Xn, #imm12*16]` (`0x3dc00000` / `0x3d800000`) for constant 16B-aligned offsets in `[0, 65520]`, and `ADD x15, XZR, idx, LSL #sz` + `LDR/STR Qt, [base, x15]` (`0x3ce06800` / `0x3c806800`) for dynamic or unaligned element indices across `REF` and `SLICE`.
2. **Broadcast and Lane Extraction (`100 vsplat`, `101 vextract`)**: `DUP Vd.4S, Vn.S[0]` (`0x4e040400`), `DUP Vd.2D, Vn.D[0]` (`0x4e080400`), `DUP Sd, Vn.S[imm]` (`0x5e040400 | (imm << 19)`), and `DUP Dd, Vn.D[imm]` (`0x5e080400 | (imm << 20)`).
3. **Packed IEEE-754 Arithmetic (`10 add`, `11 sub`, `12 mul`, `46 fma`)**: `FADD`, `FSUB`, `FMUL`, and single-rounding `FMLA` on `.4S` (`sz=0`) and `.2D` (`sz=1`). Because `FMLA Vd, Va, Vb` computes `Vd + Va * Vb`, `a6_vfma` emits `FMLA` in place when `Vd == Vc`, routes through scratch `v31` when `Vd` aliases `Va` or `Vb`, and copies `Vc` to `Vd` via `ORR Vd.16B, Vc.16B, Vc.16B` otherwise.
4. **AAPCS64 `BL` Clobber Safety, 16B Stack Slots, and Disjoint Parallel-Move Scratches**: AAPCS64 preserves only the low 64 bits (`d8..d15`) of `v8..v15` across subroutine calls; `a6_alloc` spills every 128-bit `VEC` (`a_vf[w] == 2`) live across a `BL` to a 16-byte even-aligned frame slot (`a6_slot`). Allocated 128-bit `V` registers occupy `600..628` (`v0..v28`), `a6_mvbrk` reserves `631` (`v31`) exclusively as the parallel-move cycle breaker, and `a6_mvq` uses disjoint scratch `v30` for 16B slot-to-slot copies (`700..955`) so 2-slot backedge swaps across `BL` preserve both 128-bit vectors; 16B stack ABI arguments past `v0..v7` use `3000 + ks`.

## 3. Lean 4 Formal Verification (`MODELED`, Host-Checked)

- File: `evidence/NG-A64-VEC/lean/NgA64Vec.lean` (`0d33513fe60ebc312560d87cd9f3fb796cf482abdfad1db874deb39ff6d597f9`)
- Check command: `PATH=$HOME/.elan/bin:$PATH taskset -c 0,1 nice -n 10 lake env lean evidence/NG-A64-VEC/lean/NgA64Vec.lean` (`RC=0`)
- Log: `evidence/NG-A64-VEC/lean/lean-check.log` (`bbfbab32807531b6cb1dbeb7f110dc6ce0c1c6cc6644292200f81f7e60201dbe`)
- **24 kernel-checked theorems** (`#print axioms` shows only subsets of `[propext, Classical.choice, Quot.sound]`; **zero `sorryAx`**, **zero `native_decide`**; verifies the modeled encodings, lane homomorphisms, `a6_vfma` alias schedule, and `a6_mvq`/`a6_mvbrk` 2-cycle swap semantics, while end-to-end compiler binaries are tested by `gate.om` and `rgate.om`):
  - `enc_reference_words`: verifies all 16 base/sample AArch64 machine words.
  - `fmla4s_injective`, `fmla2d_injective`: proves `(Rd, Rn, Rm)` injectivity of R3 packed SIMD encodings.
  - `fadd_4s_2d_disjoint`, `fsub_4s_2d_disjoint`, `fmul_4s_2d_disjoint`, `fmla_4s_2d_disjoint`, `fadd4s_fmla4s_disjoint`: proves strict encoding disjointness across all `32^6` register combinations.
  - `dups_lane_roundtrip`, `dupd_lane_roundtrip`: proves scalar `DUP` element lane index round-trip.
  - `vextract_vsplat4s`, `vextract_vsplat2d`, `vextract_vbin4s`, `vextract_vbin2d`, `vextract_vfma4s`, `vextract_vfma2d`: proves exact lane-parallel homomorphism on 128-bit `Vec128`.
  - `a6_vfma_correct`: proves `a6_vfma` register-aliasing schedule computes `vfma a b c` for every `(d, a, b, c)` with `a, b != v31`, including `d = a` and `d = b`.
  - `alignSlotEven_16b_aligned`: proves 16-byte stack offset divisibility (`16 | 8 * alignSlotEven s`).
  - `a6_mvq_single_correct`, `a6_pmove_swap2_correct`: proves `a6_mvq` (`v30`) + `a6_mvbrk` (`v31`) 2-cycle parallel swaps preserve both 128-bit vectors and all non-scratch locations across register and 16B stack-slot pairs.
  - **Load-bearing negative controls**:
    1. `neg_aapcs64_d8_truncates_upper_lanes`: proves 64-bit `d8` save/restore clobbers upper 64 bits across `BL`.
    2. `neg_naive_vfma_clobbers_alias`: proves omitting the `v31` alias guard corrupts `fma` when `d = a`.
    3. `neg_drop_sz_bit_collides`: proves dropping bit 22 (`sz`) makes `4S` and `2D` encodings collide.
    4. `neg_mvq_shared_v31_clobbers_slot_swap`: proves sharing `v31` between `a6_mvq` slot copy and `a6_mvbrk` overwrites one vector during a 2-slot swap.

## 4. Wolfram MCP Verification (`MODELED` + `MEASURED` Ratio Check)

- Query: `evidence/NG-A64-VEC/wolfram-query.wl`
- Raw MCP receipt (`https://agenttools.wolfram.com/mcp`, `WolframLanguageEvaluator`): `evidence/NG-A64-VEC/wolfram-raw.json`
- Verified results:
  - `encodings_all_16_match -> True` across all 16 Advanced SIMD forms.
  - Single-rounding IEEE-754 `fma` vs unfused `mul+add`:
    - `f32`: `(1 + 2^-23)*(1 - 2^-23) - 1` gives `0xa8800000` (`-2^-46`) fused vs `0x00000000` unfused.
    - `f64`: `(1 + 2^-52)*(1 - 2^-52) - 1` gives `0xb970000000000000` (`-2^-104`) fused vs `0x0000000000000000` unfused; `(1 + 2^-52)^2 - (1 + 2^-51)` gives `0x3970000000000000` (`+2^-104`) fused vs `0x0000000000000000` unfused.

## 5. Cortex-X925 Host CPU Speedup (`HOST_TESTED` / `MEASURED`)

Pinned to a dedicated ARMv9.2-A Cortex-X925 core (`3.900 GHz`, `taskset -c 19 nice -n 10` under exclusive pool lock), 200 warmup sweeps followed by 5 timed trials of `40,960,000` element FMAs (`81,920,000` FLOPs) per trial (`48 KiB` working set in L1D), measured with `monons` (`CLOCK_MONOTONIC`), zero manual loop unrolling:

| Kernel | Compiler | Trials (`ns`) | Median (`ns`) | Min (`ns`) | Throughput (`GFLOP/s`, median) | Cycles / elem-FMA (`3.9 GHz`) | Median Speedup | Output Bit Checksum |
|---|---|---|---|---|---|---|---|---|
| `bench-f32-omc.om` (`N=4096 x 10000`) | `seed/out/omc` (scalar `FMADD S`) | `23870052, 23794820, 23299439, 23338512, 23301407` | `23,338,512` | `23,299,439` | `3.51008` | `2.22253` | `1.00000x` | `13209710276162606135` |
| `bench-v4f32.oir` (`N=4096 x 10000`) | `@ng opt` + `@ng a64` (`FMLA V.4S`) | `7585465, 6914418, 6797249, 6932482, 6806833` | `6,914,418` | `6,797,249` | `11.8477` | `0.658355` | **`3.37534x`** (`3.42777x` min) | `13209710276162606135` |
| `bench-f64-omc.om` (`N=2048 x 20000`) | `seed/out/omc` (scalar `FMADD D`) | `23833604, 22990748, 22971068, 23003500, 22918923` | `22,990,748` | `22,918,923` | `3.56317` | `2.18941` | `1.00000x` | `2097136` |
| `bench-v2f64.oir` (`N=2048 x 20000`) | `@ng opt` + `@ng a64` (`FMLA V.2D`) | `14088439, 13636195, 13673235, 13655539, 13632899` | `13,655,539` | `13,632,899` | `5.99903` | `1.30021` | **`1.68362x`** (`1.68115x` min) | `2097136` |

No new compiled binaries are committed (benchmark and gate ELFs were built in scratch; `bench-v4f32` and `bench-v2f64` ELF SHA-256s are unchanged under the v2 `ng.units` pin); exact source/compiler/binary/stdout SHA-256 digests are recorded in `evidence/NG-A64-VEC/receipt.tsv`.

## 6. Gate Verdicts (`HOST_TESTED` / `MEASURED`)

- `seed/ng/tests/ngbuild/gate.om`: `NGBUILDGATE PASS` (`19/19` cases, `RC=0`, log SHA-256 `9c4a3e8a63bc2f3bc1dcd2b90b2b3f25857d5b041ee22190ff3494bae9f2a0f3`), `ngbuild build` verified `seed/ng/ng.units` (`c04b90183e23921aec69fc08f9df2e7206ac6bb0a6f81c07aaa07795269c9e9b`) and `seed/ng/ngrun.units` (`71c4e300abe42052dd9abb7bc1b57ba143dd9fa5d476c71db1431b2871e78665`).
- `seed/ng/a64/gate.om`: `cases 263 / match 263 / words 263 / mutant mismatches 3 / refusal cases 37 / refused as written 37 / mutant M-A refusal failures 19 / PASS` (`RC=0`, log SHA-256 `ed71be79a2f8cb35ba8dbe640ebffad992243a8e64c022b55604cad6da4db615`).
- `seed/ng/a64/rgate.om`: `fixtures ok 14/14`, `ngrun fixtures ok 90/90` (including `v-f32-ops`, `v-f64-ops`, `v-fma-alias`, `v-call-clobber`, `v-spill-loop`, `v-spill-swap`, `v-swap-nocall`), `refusal fixtures ok 8/8` (including `u-selvec`), `front cases ok 25/25`, `random seeds ok 1000/1000`, `float edges ok 66/66`, `float seeds ok 1000/1000`, `mutants caught 85/85` (mutants `80..85` caught `1, 3, 1, 3, 5, 1`), `PASS` (`RC=0`, log SHA-256 `3e487943f06e9967f474a0a2a7563af3b502dc3c00f7d76606c94409476fb12f`).
