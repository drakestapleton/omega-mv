# FR-8 kernel words

First slice of the language words for a GPU kernel on the GB10 (sm_121). The completion table in `docs/one_layer/OM_COMPLETION.md` lists FR-8 as absent because it needs a target kernel interface. This file is that interface. The words are Omega functions in `seed/kernel/fr8.om`. They are not new keywords in `omc`. They call the existing sm_121 encoder `gpu/nvidia/om/encoder/bw_enc_sm121.om` (`enc1`) and publish four 32-bit words per instruction.

DRA-248 asks for three CPU words: NEON SIMD lanes, shared-memory threads, and a CPU-affinity host word. Those are not this slice. The lane word below is the GPU shuffle the reconvergence design already refuses inside an open divergent region (`docs/gpu-reconvergence-308.md`).

Checked on the host against `enc1` and read back with `nvdisasm -b SM121 -hex` (a decoder; it does not launch the chip). The chip launch is NOT_RUN.

## Words

| Word | What it names | Encoder op | Instruction |
|---|---|---|---|
| `idx 0` | thread index x | 3, special register 33 | `S2R Rd, SR_TID.X` |
| `idx 1` | thread index y | 3, special register 34 | `S2R Rd, SR_TID.Y` |
| `idx 2` | block index x | 3, special register 37 | `S2R Rd, SR_CTAID.X` |
| `idx 3` | block index y | 3, special register 38 | `S2R Rd, SR_CTAID.Y` |
| `gline` | grid index x | two S2R plus op 8 | `Rd = SR_CTAID.X * ntx + SR_TID.X` |
| `shld` | shared load, 32-bit | 49 | `LDS Rd, [Ra+URZ]` |
| `shst` | shared store, 32-bit | 50 | `STS [Ra+URZ], Rb` |
| `lane` | SIMD lane shuffle | 42 | `SHFL.DOWN PT, Rd, Ra, off, 0x1f` |
| `bars` | block barrier | 48 | `BAR.SYNC.DEFER_BLOCKING 0x0` |

Special-register numbers are `BlackwellSR` in `src/omega_blackwell_codegen.h`: `BW_SR_TID_X = 0x21`, `BW_SR_TID_Y = 0x22`, `BW_SR_CTAID_X = 0x25`, `BW_SR_CTAID_Y = 0x26`. Opcode numbers are `BlackwellIROpcode` in the same header. The block index is the block's place in the grid (CUDA `blockIdx`). The grid index in this slice is the linear x index a kernel uses to name an element.

`idx` of 4 or more is refused. `TID.Z` and `CTAID.Z` are not in `BlackwellSR`, and this slice does not invent a special-register number for them. A y grid index and the grid dimensions are not in this slice.

## How each word lowers

`enc1` takes one 16-word record. The fields this slice sets are op, destination, sources, and the immediate. The control word and the always-true guard stay the encoder's defaults. `enc1` patches a predicate into word 0 only when the record asks for one (`o[9]`). `bars` never asks.

S2R (`enc_a`, op 3). Word 0 is `31001` with the destination at bits 16..23. Word 1 is 0. Word 2 is the special register in bits 8..15. Word 3 is `926208`.

For destination R4 and `SR_TID.X` the words are `293145, 0, 8448, 926208`. `nvdisasm` reads `S2R R4, SR_TID.X`. The same form with R5 / 34, R6 / 37 and R7 / 38 reads `SR_TID.Y`, `SR_CTAID.X` and `SR_CTAID.Y`.

`gline dst ntx tr br` emits three instructions into `gc`: S2R of `SR_TID.X` into `tr`, S2R of `SR_CTAID.X` into `br`, then IMAD (`enc_a`, op 8, immediate form) `dst = br * ntx + tr`. The worked case `gline 8 32 4 6` is:

| Words | `nvdisasm` |
|---|---|
| `293145, 0, 8448, 926208` | `S2R R4, SR_TID.X` |
| `424217, 0, 9472, 926208` | `S2R R6, SR_CTAID.X` |
| `101218340, 32, 126747140, 2083328` | `IMAD R8, R6, 0x20, R4` |

`ntx` of 0, or `ntx` above 1024, is refused and nothing is written. 1024 is the maximum threads per block in the CUDA C Programming Guide, Release 13.4, Table 27, page 487 ("Maximum number of threads per block 1024"), for every compute capability that table lists, including 12.0. The IMAD immediate is 32 bits; this slice refuses before encode, so a block size the chip cannot launch is not truncated into that field.

Shared memory is the 32-bit pair, not the byte forms (ops 43 and 44) and not `LDS.128`.

`shld dst adr` is op 49. Word 0 is `31108` with `dst` at bits 16..23 and `adr` at bits 24..31. Word 1 is `255` (URZ). Word 2 is `134219776`. Word 3 is `927744`. `shld 9 10` is `168393092, 255, 134219776, 927744`, which reads `LDS R9, [R10+URZ]`.

`shst adr val` is op 50. Word 0 is `31112` with `adr` at bits 24..31. Word 1 is `val`. Word 2 is `134220031`. Word 3 is `1040896`. `shst 10 9` is `167803272, 9, 134220031, 1040896`, which reads `STS [R10+URZ], R9`.

`lane dst src off dvg` is op 42. Word 0 is `32649` with `dst` at bits 16..23 and `src` at bits 24..31. Word 1 is `134225664` with `off` in bits 21..25 (the field keeps 5 bits). Word 2 is `917504`. Word 3 is `926720`. `lane 11 4 1 0` is `67862409, 136322816, 917504, 926720`, which reads `SHFL.DOWN PT, R11, R4, 0x1, 0x1f`.

`bars dvg grd` is op 48. The four words are fixed: `31517, 0, 65536, 1043456`. Word 0 `31517` is `0x7B1D`, whose guard bits 12..15 are 7 (always). `nvdisasm` reads `BAR.SYNC.DEFER_BLOCKING 0x0`.

## Refusals

The encoder would emit `BAR.SYNC` and `SHFL.DOWN` even inside a divergent region, and it would patch a predicate onto the barrier. The word layer refuses before `enc1`. A refusal clears `fw` and, for a bad `ntx`, clears `gc`.

| Code | When |
|---|---|
| 2 | `bars` or `lane` while `dvg` is 1. `docs/gpu-reconvergence-308.md` section 3 refuses `BAR.SYNC` and `SHFL` inside an open divergent region. |
| 3 | `idx` axis above 3. |
| 4 | `bars` with a predicate. A CTA barrier is not a per-lane skip. |
| 5 | `gline` with `ntx` 0 or above 1024. |
| 6 | `lane` with a distance of 32 or more. |

`seed/kernel/fr8_host.om` checks the accepted words above and each refusal. A wrong expected word for `SR_TID.X` exits 11.

## Check

From the repository root, with `seed/out/omc` matching `seed/out/omc.sha256`:

```sh
sh seed/kernel/fr8-check.sh
```

Exit 0 prints `FR8 HOST PASS`. The script compiles the encoder and the two kernel files with `seed/out/omc` and runs the result. It opens no device.

## Not this slice

New `omc` keywords, a cubin, a launch, y and z grid indexes, grid dimensions, byte and 128-bit shared memory, and the three CPU words in DRA-248.

The effects pin in `om/units.sh` (`OMC_PIN`) does not match `seed/out/omc` (`34d611ca…`) on base `9cf07015`. This slice does not change that pin. The `omc-pin` lane owns the update on `omc/effects-pin-34d611ca`.

## Chip, NOT_RUN

Do not run this while another job holds the GPU. It launches the existing vector-add kernel. It does not run these words; this slice has no launcher.

```sh
quiet-measure flock /tmp/aien-gb10.lock spark-receipt seed-sm121-run -- sh seed/sm121/chip6.sh evidence/SEED-0/sm121/chip
```

Status: NOT_RUN.
