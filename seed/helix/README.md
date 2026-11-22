# `seed/helix/`: The Proof-Carrying Evolutionary Helix (Dual-Seed DDC + Monk + Predator + Arboris + Immune)

`seed/helix/` implements the **Proof-Carrying Evolutionary Helix** — a four-organ self-verifying compiler and SM121 GPU optimization architecture grown from **804 bytes of independent hand-written machine-code seeds** (`408 B` Strand A `seed0.hex` + `396 B` Strand B `seedB0.b0`), with **zero C, zero GCC, zero Rust, zero LLVM, and zero Python** on either bootstrap path.

## Four Organs

| Organ | Component | Source | Role |
|---|---|---|---|
| **Skeleton (The Monk)** | Strand A (`seed0.hex`, 408 B) + `monk_check.om` + `HelixSoundness.lean` | `seed/rung0..4`, `seed/omc/omc.om`, `seed/helix/monk_check.om`, `seed/helix/proofs/HelixSoundness.lean` | Brutally simple reference compiler + millisecond mathematical proof verifier for SM121 schedule certificates (`helix-proof-v1`) |
| **Muscles (The Predator)** | Strand B (`seedB0.b0`, 396 B W^X) → `hexB1` → `omB2` (stack-machine compiler) → `ng` → `A_fast` + `arboris_predator.om` | `seed/helix/rung0..2/`, `seed/ng/`, `seed/helix/arboris_predator.om` | Completely independent second tiny seed ladder + optimizing SSA compiler + SM121 schedule mutator wired live to local 35B zero-CUDA `q36-serve` over native Omega TCP sockets |
| **Nervous System (Arboris)** | Spreading-activation graph inside `arboris_predator.om` + live `q36-serve` Arboris prefetcher | `seed/helix/arboris_predator.om`, `om/gpu/q36/arboris/prefetch.om` | 12-node Q10 sum-over-paths spreading activation steering `(kernel_shape → SM121_trick → Lean4_tactic)` intuition, dual-cue associative memory collision recall, and 40L×256E online expert prefetching (`93%` hit rate) |
| **Immune System (Antibodies)** | Automated adversarial red-teamer `immune.om` + 7 permanent Lean 4 Antibody Theorems | `seed/helix/immune.om`, `seed/helix/proofs/HelixAntibodies.lean` | Launches all 7 attack classes against every Proof Rung before lock-in; each attack class is formally proved unpassable in Lean 4.35.0 (`ZERO sorry`, standard axioms only) |

## Independent Second Tiny Seed Ladder (`seedB0` → `hexB1` → `omB2`)

Strand B's seed shares **zero bytes, zero input grammar, zero register allocation, and zero memory layout** with Strand A:

| Rung | Strand A (`seed/rung0..4`) | Strand B (`seed/helix/rung0..2`) |
|---|---|---|
| **Rung 0** | `seed0.hex` (408 B, 32-bit LE words, `#` comments, RWX `p_flags=7`, `0x400000`, static BSS buffers) | `seedB0.b0` (**396 B**, byte-pair hex `XX`, `;` comments, **pure W^X `p_flags=5`**, `0x500000`, stack `[sp]` scratch buffer, SHA-256 `dc2edfb38f73...`) |
| **Rung 1** | `hex1.hex` (776 B, 1-char labels, 19-bit branch only) | `hexB1.b0` / `hexB1.b1` (**948 B**, 16-char named labels, `=word`, `@b19`, `^b26`, `$` auto-filesz, SHA-256 `e2fe5955a174...`, self-rebuilds identically) |
| **Rung 2** | `asm2` + `om4` (16-register-allocating compiler, `0x400000`) | `omB2.b1` (**15,464 B**, **pure software value-stack compiler** using `x26` mmap'd value stack, zero register allocator, `0x500000`, W^X `p_flags=5`, SHA-256 `fd4d8e83459c...`) |

## Strict Bit-for-Bit Diverse Double Compilation (4-Way Convergence at `783eb4ab6`)

All four independent routes converge bit-for-bit on `seed/out/omc` (`952,784` bytes, SHA-256 `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`):

1. **Strand A (Seed A — 408 B `seed0.hex`)**: `om4(omc.om)` → `708fdc0f...`
2. **Strand B Direct (Seed B — 396 B `seedB0.b0`)**:
   - `omB2(omc.om)` → `omc_stage1_B` (`1,111,848 B`, SHA-256 `eb78fc81a100...` — **whole different stack-machine binary!**)
   - `omc_stage1_B(omc.om)` → `708fdc0f...` (**exact bit-for-bit match!**)
3. **Double Helix Twist (Strand B `ng` born 100% from `seedB0` ↔ Strand A)**:
   - `omB2(ng.src)` → `ng_stage1_B` (`916,604 B`, SHA-256 `74dffdf15fda...` — **zero Strand A bytes!**)
   - `ng_stage1_B(ng.src)` → `ng_B` (`435a19cf58381f3628c7e2b64a0b678055deb082e2ebc5006afe9b61cd55a713` — **exact bit-for-bit self-hosting fixpoint == Strand A-born `ng`!**)
   - `ng_B(omc.om)` → `A_fast` (`517,784 B`, SHA-256 `9be28b252be5...` — **45.7% smaller** optimized binary, min `17.60 ms` vs `20.53 ms`!)
   - `A_fast(omc.om)` → `708fdc0f...` (**exact bit-for-bit match!**)
4. **Route I (Third-party GCC 13.3.0 C spec interpreter `tools/omega_ref/omega_ref.c`)**:
   - `omega_ref(omc.om)` → `708fdc0f...` (**exact bit-for-bit match!**)

Furthermore, building the **zero-CUDA 35B Qwen 3.6 AI server (`q36-serve`)** and **native GB10 runner (`q36-native`)** from Strand A (`seed0`) and independently from Strand B (`seedB0` → `A_fast`) produces **bit-for-bit identical static AArch64 ELFs** (`ldd: not a dynamic executable`):
- `q36-native`: `e4746000cc87d8f060f6c0b064ee03b04a4538aa52ccc13cc7ee59da3ffe0cf2`
- `q36-serve`: `71527a3f9689ad5e213a442285641ba058dee45c29603cd7fb0e8f15135b8d85`

## Run

On AArch64 Linux from the repository root:

```sh
sh seed/helix/helix-from-seeds.sh
```

To verify the 12 Lean 4.35.0 theorems (`HelixSoundness.lean` + `HelixAntibodies.lean`, zero `sorry`, standard axioms only):

```sh
lean seed/helix/proofs/HelixSoundness.lean
lean seed/helix/proofs/HelixAntibodies.lean
```

Full live GB10 silicon + dual-seed receipt: `evidence/HELIX-DDC-20261121/`.
