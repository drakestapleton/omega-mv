# `omega-vsa` — 10,240-Bit Hyperdimensional Vector-Symbolic Associative Program Memory (`OMVSA1`)

> **Status: `HOST-VERIFIED`** (DGX Spark AArch64 Grace CPU 5 + `@ng opt` + `@ng a64` NEON SIMD + Lean 4.36.0 `-DwarningAsError=true`; `NOT_RUN` on GB10 GPU or bare-metal UEFI).
> Built in **100% pure seeded Omega (OM-2)** compiled by pinned `seed/out/omc` (`85b84c6d...`) — zero `.c`, `.h`, `.py`, `.rs`, or `gcc`.

## Plain-English Explainer: What This Is

Traditional program memory works like a numbered wall of bank deposit boxes: ask for box `#42` and you get box `#42`, but if a single bit of your address flips or you want to overlap five records in one slot, the lookup breaks or collides.

**Vector-Symbolic Architecture (`OMVSA1`)** works more like **mixing transparent colored stencils across 10,240 pixels**:

1. Every concept (`opcode`, `role`, `register`, `slot`) gets its own random-looking `10,240`-bit pattern (`160 × u64`). Two unrelated random patterns differ on roughly half their bits (`~5,120 / 10,240`), so they sit nearly perpendicular in `10,240`-dimensional space.
2. **Bind (`XOR` / bipolar `FMUL.4S`)**: combines a key and value (`B = key ⊕ val`) into a composite vector that looks unrelated to either input, yet is **exactly self-inverse**: binding again with `key` cancels `key` back to `val` with **0-bit loss**.
3. **Bundle (coordinate-wise majority vote)**: superimposes multiple bound pairs into **one single `10,240`-bit vector**. Even after flipping `512` random bits (`5%` corruption), unbinding with a member key still recovers its exact partner (`5 / 5` hits, minimum margin `1,526` bits over nearest distractor).
4. **Cyclic Permutation (`permute` / `unpermute`)**: rotates all `10,240` bits by `shift ∈ [0, 10240)` to encode sequence order, separating `[A, B]` from `[B, A]` by `5,078 / 10,240` bits while remaining strictly bijective (`unpermute(permute(v, s), s) == v`).

## Side-by-Side Comparison vs Scalar Lookup

| Property | Traditional Scalar Table / Hash Lookup | `OMVSA1` 10,240-Bit Associative Memory |
|---|---|---|
| Addressing | Exact index / hash match only | Content-addressable nearest Hamming neighbor (`10,240` bits) |
| Composite records | Extra pointer structs / hash buckets | Fixed `1,280 B` superposition (`bundle` of multiple bound pairs) |
| Bit-flip tolerance | 1 flipped bit breaks lookup or hits wrong bucket | Recovers `5/5` bundled records under `512` bit flips (`min_margin=1526`) |
| Sequence sensitivity | Separate list/array metadata | Single `permute` step (`dist([A,B], [B,A]) = 5078/10240`) |
| SIMD execution | Branchy hash probes / cache chasing | Bounds-check-free `FMUL.4S` / `FMLA.4S` / `FADD.4S` (`bce=92`) + packed SWAR |
| Mathematical proof | Unit tests only | Machine-checked Lean 4.36.0 theorems (`0 sorry`, standard axioms only) |

## Files Owned by This Module

| File | Role |
|---|---|
| [`apps/omega-vsa/emit_vsa_ir.om`](emit_vsa_ir.om) | Pure OM-2 ΩIR generator emitting static `vsa_worker` (`FMUL.4S` bind, 4-accumulator `FMLA.4S` similarity, `FADD.4S` bundle, and packed `u64` SWAR path) with constant-bound guards yielding `bce=92`, `hoisted=447`, `rotated=40` under `@ng opt`. |
| [`apps/omega-vsa/vsa_core.om`](vsa_core.om) | Pure OM-2 engine: PRNG, `bind`, `bundle`, `permute`/`unpermute`, `OMVSA1` serialization + SHA-256 tag verifier, Grace CPU-5 pinned worker coordinator, `0-bit diff` cross-engine parity checker, and `1 warmup + 9 timed` (`med9`) benchmark. |
| [`apps/omega-vsa/gate_vsa.om`](gate_vsa.om) | Pure OM-2 verification gate checking 2× build determinism (`vsa_core`, `vsa_worker`, `emit_vsa_ir`), 3 positive checks, and 11 fail-closed negative/fault-injection controls. |
| [`seed/helix/proofs/VsaSoundness.lean`](../../seed/helix/proofs/VsaSoundness.lean) | Import-free Lean 4.36.0 soundness proof (bind group laws, Hamming metric axioms + XOR-isometry, permutation bijectivity, majority recoverability, associative recall soundness). |
| [`evidence/WAVE3-VSA-20261127/RECEIPT.txt`](../../evidence/WAVE3-VSA-20261127/RECEIPT.txt) | Immutable Spark receipt covering 2× SHA-256 hashes, `ngcheck`, `opt-count`, `readelf -d`, `med9` timings, gate controls, and Lean 4.36.0 axiom check. |

## Canonical `OMVSA1` Container Layout (`160 × u64 = 10,240 bits`)

| Offset | Size | Field | Invariant & Fail-Closed Exit Code |
|---|---|---|---|
| `0..5` | `6 B` | `magic` | Exact ASCII `"OMVSA1"`, else `exit 41` (`VSA_ERR_MAGIC`) |
| `6..7` | `2 B` | `version` | `u16` LE `== 1`, else `exit 41` (`VSA_ERR_MAGIC`) |
| `8..11` | `4 B` | `dim_bits` | `u32` LE `== 10240`, else `exit 42` (`VSA_ERR_DIM`) |
| `12..15` | `4 B` | `word_lanes` | `u32` LE `== 160`, else `exit 42` (`VSA_ERR_DIM`) |
| `16..19` | `4 B` | `num_records` | `u32` LE in `1..64`, else `exit 44` (`VSA_ERR_SIZE`) |
| `20..23` | `4 B` | `flags` | `u32` LE `= 1` (degenerate guard policy enabled) |
| `24..31` | `8 B` | `payload_bytes` | `u64` LE `== num_records * 1280` and `64 + payload_bytes == file_len`, else `exit 44` |
| `32..63` | `32 B` | `sha256_tag` | `SHA-256(hdr[0..32) \|\| payload[0..payload_bytes))`, else `exit 45` (`VSA_ERR_SHA`) |
| `64..end` | `N × 1,280 B` | `records` | `N × 160 × u64` LE; popcount must lie in `[1024, 9216]` (rejects all-0/all-1/collapsed with `exit 46`) |

Additional runtime guards:
- Out-of-range cyclic shift (`shift >= 10240`): `exit 43` (`VSA_ERR_SHIFT`)
- Failed associative margin (`best_dist > 3200` or `second_dist - best_dist < 400`): `exit 47` (`VSA_ERR_MARGIN`)

## Build & Verify on AArch64 Host (Spark)

```sh
# 1. Build NG tools from pinned seed/out/omc (or make seed-ng)
# 2. Build & run ΩIR generator -> @ng opt -> @ng a64 static ELF worker
cat seed/ng/src/ir.om apps/omega-vsa/emit_vsa_ir.om | seed/out/omc > build/emit_vsa_ir
chmod +x build/emit_vsa_ir
./build/emit_vsa_ir > build/vsa_worker.ir
tools/ngcheck < build/vsa_worker.ir
{ printf "@ng opt-count\n"; cat build/vsa_worker.ir; } | tools/ng
{ printf "@ng opt\n"; cat build/vsa_worker.ir; } | tools/ng > build/vsa_worker.opt.ir
tools/ngcheck < build/vsa_worker.opt.ir
{ printf "@ng a64\n"; cat build/vsa_worker.opt.ir; } | tools/ng > build/vsa_worker
chmod +x build/vsa_worker
readelf -d build/vsa_worker   # "There is no dynamic section in this file."

# 3. Build pure OM-2 engine and verification gate
cat si/directives/om2.om seed/ng/sha256.om apps/omega-vsa/vsa_core.om | seed/out/omc > build/vsa_core
cat si/directives/om2.om seed/ng/sha256.om apps/omega-vsa/gate_vsa.om | seed/out/omc > build/gate_vsa
chmod +x build/vsa_core build/gate_vsa

# 4. Run full gate (2x determinism + 3 positive + 11 fault-injection controls)
mkdir -p build/vsa-scratch
./build/gate_vsa ./build/vsa_core ./build/vsa_core ./build/vsa_worker ./build/vsa_worker ./build/vsa-scratch ./build/emit_vsa_ir ./build/emit_vsa_ir

# 5. Machine-checked Lean 4.36.0 proof
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/VsaSoundness.lean

# 6. Verify evidence checksums from repo root
shasum -a 256 -c evidence/WAVE3-VSA-20261127/SHA256SUMS.txt
```

## Measured Host Verification Results (Cortex-X925 CPU 5, `Q=64` queries × `M=64` codebook, `1 warmup + 9 timed`)

- `@ng opt-count`: `opt fns=29 loops=41 inloop=1049->605 phi=0 bce=92 hoisted=447 merged=163 rotated=40 preheaders=0`
- Parity across `scalar_f32`, `scalar_u64`, `ng_a64_neon` (`cmd=2`), and `ng_a64_swar` (`cmd=4`): **0-bit difference** on all `64 × 10,240` unbound bits and all `64 × 3` recall tuples (`(best_idx, best_dist, second_dist)`), plus **0-bit difference** on `cmd=3` NEON bundle vs scalar bundle.
- `med9` latency (including full Linux pipe IPC for `ng_*` workers):
  - `scalar_f32` (OM-2 scalar bipolar reference): `19,764,758 ns` (`19.76 ms`)
  - `ng_neon_pipe` (`@ng opt` + `@ng a64` `FMUL.4S`/`FMLA.4S` worker): `8,694,274 ns` (`8.69 ms` — **`2.27x`** faster than `scalar_f32`, including bit unpack/repack + pipe IPC)
  - `scalar_u64` (OM-2 packed 64-bit SWAR): `1,747,341 ns` (`1.75 ms`)
  - `ng_swar_pipe` (`@ng opt` + `@ng a64` packed 64-bit SWAR worker): `1,082,056 ns` (`1.08 ms` — **`1.61x`** faster than `scalar_u64`, **`18.27x`** faster than `scalar_f32`)
- Lean 4.36.0 (`-DwarningAsError=true`): exit `0`, `0` warnings, `0` `sorry`, standard axioms only (`propext`, `Classical.choice`, `Quot.sound`).

## Scope & What Is NOT Built Yet

- **Verified today (`HOST-VERIFIED`)**: Linux AArch64 CPU host execution on DGX Spark Grace Cortex-X925 (CPU 5), `@ng opt` + `@ng a64` NEON worker parity and speedup, `11/11` fail-closed negative controls, and Lean 4.36.0 soundness proofs.
- **NOT built / NOT run yet**:
  - GB10 SM121 GPU SASS kernel execution (`VSA` kernels on GPU) — `NOT_RUN`
  - Multi-core 20-core X925+A725 sharded parallel coordinator inside `vsa_core` (current benchmark pins 1 worker + reference to CPU 5 for apples-to-apples single-core SIMD comparison) — `NOT_BUILT`
  - Bare-metal `Aienux` / `target a64efi` integration — `NOT_RUN`
