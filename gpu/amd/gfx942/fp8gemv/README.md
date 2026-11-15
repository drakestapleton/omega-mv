# fp8gemv_stream

One wave computes one row of `y = scale * (W x)` for an MI300X decode GEMV.
W is gfx942 FP8. x, the scale and y are binary32, or y is bf16 when flags bit 2
is set. This directory was checked on the CPU. Nothing here was run on a GPU,
and there are no timings.

## The FP8 format

CDNA3 ISA §7.2 Table 30. FP8 is E4M3, bias 8. +0 and −0 are both encoding 0x00.
There is no infinity. NaN is 0x80. The maximum finite value is 240, the minimum
normal is ±2^(−7), and the minimum denormal is ±2^(−10). The table does not use
the name FNUZ. That is the industry name for this encoding. It is not OCP E4M3
(bias 7, NaN at 0x7F and 0xFF, a negative zero, maximum 448).

`SH_MEM_CONFIG` bit 8 must be 1 for the device to treat the bytes as BF8/FP8
(§7.2). The code object does not write that register.

The convert in the kernel is `v_cvt_pk_f32_fp8_e32` (Table 31, VOP1, destination
even). `llvm-mc-18 -mcpu=gfx942` encodes it as opcode 86. The kernel converts the
low 16 bits, shifts the dword down by 16, and converts again, so the four bytes
of a weight dword are consumed in order 0, 1, 2, 3. OCP bytes are decoded only
in `check.om`.

## The kernel

`fp8gemv_stream.isa` is packed by `gpu/amd/gfx942/hsaco.om`. `fp8gemv_stream.s`
is the same words in assembler syntax. `check.sh` refuses the tree if those two
disagree with each other or with the committed golden bytes.

Lane L of the wave owns columns `k + L*16 .. +15`. A tile is 1024 columns: one
`global_load_dwordx4` of weights and four of activations. When `k+2048 <= K` the
kernel issues two tiles before either tile's FMAs (`s_waitcnt vmcnt(5)`, compute
the older tile, `s_waitcnt vmcnt(0)`, compute the newer). A leftover full tile
follows, then a tail of at most 16 columns, one byte and one dword at a time,
masked by `exec` when the column is past K.

Weight loads are `global_load_dwordx4` with nt=1 and no sc bit. Every other load
and both stores leave sc and nt clear. Why that pair, and the bytes, are in
`ENCODING.md`.

The reduction is `v_add_f32_dpp` `row_shr` 8, then 4, then 2, then 1, with
`row_mask` and `bank_mask` 0xf and bounds control clear. ISA §13.3.9: a row shift
right reads lane `n-k`, and BC=0 does not write a lane whose source is outside
the row of 16. The row sum therefore sits in lanes 15, 31, 47 and 63.
`v_readlane_b32` reads those four, and `(lane15+lane31)+(lane47+lane63)` is the
dot product. Per-row scale is one `v_mul_f32` after that.

Split-K is not implemented. M of 4096 is already many waves on a 304-CU MI300X.

### Resource descriptor

The K line carries sgprs 32 and vgprs 52 (highest registers s31 and v51).

- VGPR granule: `ceil(52/8)-1 = 6`.
- SGPR field: VCC adds 2, so 34 registers; `2 * (ceil(34/16)-1) = 4`.
- `rsrc1 = 0xaf0000 | (4<<6) | 6 = 0xaf0106`. The `0xaf0000` base is the vadd
  kernel's `0xaf0081` with its granule fields cleared. The same formula on
  vadd's 9 VGPRs and 20 SGPRs gives that `0xaf0081`.
- `rsrc3` ACCUM_OFFSET: `align(52,4)/4 - 1 = 12`. vadd's 9 VGPRs give 2, which is
  the value in `vadd.isa`.

`check.sh` recomputes this from the K line.

### Kernarg, 64 bytes

| offset | name | |
| --- | --- | --- |
| 0 | W | u8, row-major, M*K |
| 8 | x | f32, K |
| 16 | scale | f32, M (one per row) |
| 24 | y | f32 or bf16 |
| 32 | residual | f32, M |
| 40 | gamma | f32, M |
| 48 | inv_rms | f32 |
| 52 | M | u32 |
| 56 | K | u32 |
| 60 | flags | u32 |

Flag bit 0 selects the row remap below. Bit 1 is the fused epilogue
`y = (y + residual[row]) * inv_rms * gamma[row]`. Bit 2 stores the top 16 bits
after the usual bf16 round-to-nearest-even (`lsb` of the high half, add
`0x7fff+lsb`, store the high half) with `global_store_short`. Otherwise
`global_store_dword`. Only lane 0 stores.

`inv_rms` is a kernarg. One wave cannot see the other rows, so it cannot compute
the RMS. That gap is `PROPOSAL.md`.

### Workgroups and XCDs

ISA Table 7, XCC_ID bits 3:0, is "ID of this XCC". Hardware-ID register 20 is
"ID of the XCC this wave is running on". Neither says that workgroup `i` is
dispatched to XCD `i mod 8`.

The optional remap assumes a round-robin dispatch in which workgroup `i` lands
on XCD `i mod 8`, and then chooses the row so that each XCD's rows are a
contiguous band:

```
span = (M + 7) >> 3
row  = (id & 7) * span + (id >> 3)
```

The launch grid for that mode is `8 * span` workgroups, not M. A row past M
exits. It is a bijection onto `0 .. M-1`. `check.om` checks M=10 and M=16.
HBM stack selection is by address, so this remap does not change which stack
serves a byte. It changes which XCD's L2 sees a band of rows, and only if the
assumption about dispatch is true. Bit 0 clear is the identity map (workgroup id
is the row). Both are in the one kernel.

### What the device kernel does not do

Per-block scales (128 columns) and OCP E4M3 are computed by `check.om` only.
The kernel-order per-block rule is: a lane sums its 16 products from zero,
multiplies by `scale[col >> 7]`, then adds that into the lane accumulator, and
only then does the same DPP reduction. A lane's 16 columns start on a multiple
of 16 and do not cross a multiple of 128. The column-order reference instead
scales each product as it goes. Those two associations agree on the K=256 ones
case because every partial sum is an integer the 24-bit mantissa holds exactly.

## CPU check

```
gpu/amd/gfx942/fp8gemv/check.sh
```

That hashes `seed/out/omc` against `seed/out/omc.sha256`, assembles both `.s`
files, packs both `.isa` files, diffs the bytes against `encprobe.golden` and
`fp8gemv_stream.golden`, recomputes the descriptor fields, and runs `check.om`.
Both references call `fpfma` from `exec/fma.om` (x86linux rejects the `fma`
keyword). `plain` is a column loop. `gemv` is the kernel's lane and tile order.
They are bit-exact when the association is the same: K of 16 or less, and any
dot that produces a NaN. FNUZ NaN is the byte 0x80 only. 0xFF decodes to −240.
Elsewhere `check.om` allows the difference Higham's recursive-summation bound
gives two associations, with a factor of two so the bound itself (computed in
binary32) cannot round down through a difference that estimate allows, plus 8
ulps of the two results. The seeded inputs and the cross-lane cancellation are
required to differ. The fused residual and RMSNorm-scale epilogue, and the bf16
store rounding, run inside both functions.

`check.om` exits 0 after printing `fp8gemv check pass`. Any other exit is the
check number in `main`.

## On an MI300X

```
gpu/amd/gfx942/fp8gemv/bench.sh
```

Correctness first (`check.sh`). If `/dev/kfd` is absent it prints
`BLOCKED_HARDWARE` and exits non-zero. It does not invent a bandwidth. On a
card it runs `hipblaslt-bench` at these shapes (`f8_fnuz_r` times `f8_fnuz_r`,
which is the FP8 combination that library has; the kernel is FP8 times FP32)
and times this kernel with the row-remap bit off and on. Warmup, then 21
samples, then the median, the spread, and GB/s against 5.3 TB/s.
