# `seed/helix/`: The Proof-Carrying Evolutionary Helix (Phases 1–4)

`seed/helix/` implements the **Proof-Carrying Evolutionary Helix** — a four-organ self-verifying compiler, GPU kernel optimizer, associative nervous system, and adversarial immune architecture grown from **804 bytes of independent hand-written machine-code seeds** (`408 B` Strand A `seed0.hex` + `396 B` Strand B `seedB0.b0`), with **zero C, zero GCC, zero Rust, zero LLVM, zero Python, and zero CUDA** on the cold-regrowth path.

## Four Organs

| Organ | Components | Role |
|---|---|---|
| **Skeleton (The Monk)** | Strand A (`seed0.hex`, 408 B), `monk_check.om`, `dual_checker.om`, `sign_ddc.om`, `proofs/HelixSoundness.lean` | Brutally simple reference compiler + millisecond SM121 proof-rung verifier + standalone Strand A e-graph & launch-gate dual-checker trust anchor + pure-Omega RFC 8032 Ed25519 receipt signer/verifier |
| **Muscles (The Predator)** | Strand B (`seedB0.b0`, 396 B W^X → `hexB1` → `omB2` pure stack-machine compiler → `ng` → `A_fast`), `egraph_opt.om`, `arboris_predator.om`, `extract_q36_kernels.om`, `proofs/HelixKernelIR.lean` | Independent second tiny seed ladder + optimizing SSA compiler + verified equality-saturation GB10 e-graph optimizer + SM121 schedule mutator wired live to local 35B zero-CUDA `q36-serve` over native Omega TCP sockets |
| **Nervous System (Arboris)** | `arboris_nervous_bench.om`, spreading-activation engine in `arboris_predator.om`, live `om/gpu/q36/arboris/prefetch.om` | Three-track system nervous system: Track 3A compiler/proof-search intuition (**96% fewer probes**, **6.65× faster**), Track 3B pure-Omega associative agent memory (**100% vs 40% Recall@1** in **~1 µs**), Track 3C anticipatory Aienux scheduling (**p95 & p99 `400 µs → 12 µs`**, **99% hit rate**, **234 ns overhead**) |
| **Immune System (11 Antibodies)** | `immune.om`, `dual_checker.om`, `proofs/HelixAntibodies.lean` | Automated adversarial red-teamer launching all 11 attack classes (7 SM121 proof-rung attacks + 4 `uor-gpu` launch-gate attacks: smuggled P0 signatures, trailing bytes, misaligned QMDs, zero-generation caps); every attack class is formally proved unpassable in Lean 4 (`0 sorry`, standard axioms only) |

## Phase 1: Dual-Seed Diverse Double Compilation (7-Way Convergence + Ed25519 Receipt)

All **7 independent build routes** across **3 OS/ISA combinations** converge bit-for-bit on `seed/out/omc` (`952,784 B`, SHA-256 `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`):

1. **Linux AArch64 — Strand A (408 B `seed0.hex` → `om4`)**: `708fdc0f...`
2. **Linux AArch64 — Strand B Direct (396 B W^X `seedB0.b0` → `hexB1` 948 B → `omB2` 15,464 B pure value-stack compiler)**: `omc_stage1_B` (`1,111,848 B`, `eb78fc81a100...`) → `omc_stage2_B` = `708fdc0f...`
3. **Linux AArch64 — Double Helix Twist (`seedB0` → `omB2(ng.src)` → `ng_B` `435a19cf...` → `A_fast` `517,784 B` `9be28b25...`, 45.7% smaller)**: `A_fast(omc.om)` = `708fdc0f...`
4. **Linux AArch64 — Third-Party GCC 13.3.0 C Reference (`tools/omega_ref/omega_ref.c`)**: `708fdc0f...`
5. **Linux x86-64 Cross-ISA (`x86_64-linux-gnu-gcc` + `qemu-x86_64`)**: `708fdc0f...`
6. **macOS Darwin ARM64 (XNU kernel, Apple Clang 17, Mach-O)**: `708fdc0f...`
7. **macOS Darwin x86-64 (XNU + Rosetta 2, Apple Clang 17 `-arch x86_64`, Mach-O)**: `708fdc0f...`

Negative control (poisoned NOP in `matconst` via `omB2`): `14e9fac0... != 708fdc0f...` (**CAUGHT**). Canonical DDC manifest signed and verified with pure-Omega RFC 8032 Ed25519 (`seed/helix/sign_ddc.om`, compiled identically by Strand A & Strand B, 1-bit tamper rejected).

## Phase 2: Verified EGP2 Structural E-Graph, Dual-Checker & Production `q36` SM121 Kernels

- **Lean 4.36.0** (`HelixSoundness.lean`, `HelixAntibodies.lean`, `HelixKernelIR.lean`): 23 machine-checked declarations, 0 warnings, 0 `sorry`, standard axioms only.
- **EGP2 Structural Proof Kernel + Strand A Dual-Checker**: `egraph_opt.om` reduces GB10 cost on `q36_bf16_gemv_mac` (`7→2`), `q36_w4_unpack_mac` (`9→2`), and `q36_swiglu_gate` (`10→2`) across 23 proof steps and serializes full e-graph node tables (`EGP2`); standalone `dual_checker.om` replays union-find structurally verifying every rule's exact operands/e-classes/constants, proves `find(root_before) == find(root_after)`, independently recomputes GB10 cost, checks concrete semantic equivalence (`eval_checks=12`), kills BOTH unsound rule `99 (add→mul)` and structural spoof `rule 3 on add(x,1)→x` (`neg_controls=2/2`), and kills all 4 `uor-gpu` launch-gate attacks (`12/12` total antibodies).
- **3 Production `q36` SM121 Kernels** extracted from `om/gpu/q36/emit_fast.om` and verified through `arboris_predator` (parsing live 35B LLM `compact=`/`swap=` proposals) → `monk_check` (full CFG fixed-point scoreboard dataflow + fixed-latency ALU RAW stall preservation + full barrier/reconvergence/predicate-writer anchoring) → `immune` (8 SM121 attacks + 4 `uor-gpu` = `12/12` antibodies):
  - `bf16_gemv_fast` (227 insns): 94 moved, stalls `1044 → 923` (**-121**), `hazards=0`, `12/12` antibodies PASS
  - `fp8_b128_gemv_fast` (207 insns): 102 moved, stalls `895 → 781` (**-114**), `hazards=0`, `12/12` antibodies PASS
  - `w4_b32_gemv_fast` (437 insns): 152 moved, stalls `2118 → 1841` (**-277**), `hazards=0`, `12/12` antibodies PASS

## Phase 4: Single-Command Clean-Room Cold Regrowth

From the repository root on AArch64 Linux (zero C, zero Python, zero CUDA, zero network):

```sh
sh seed/helix/cold-regrowth.sh --lean
```

Regrows both strands from 804 B of seeds, verifies DDC + Ed25519 signature, runs `egraph_opt` + `dual_checker`, extracts and verifies all 3 production `q36` kernels through Predator → Monk → Immune, runs all 3 Arboris nervous-system receipts, compiles `aienux/units-gate.om`, `protocol/units-gate.om`, and `uor-gpu-gate` identically across both strands (and runs `uor-gpu-gate` -> `UOR_GPU_GATE_PASS`), performs 2-generation helical self-recompilation of the zero-CUDA 35B AI server (`Gen0 == Gen1 == Gen2` for `q36-serve` & `q36-native`), and checks all 3 Lean 4 proof files.

Immutable evidence receipts:
- Dual-seed DDC + Live GB10 silicon run (`71.51 tok/s` backbone, `65.89 tok/s` full-token, `11/11` parity, `nvrm_errors_delta: 0`): [`evidence/HELIX-DDC-20261121/`](../../evidence/HELIX-DDC-20261121/)
- Complete Phases 1–4 verification receipt: [`evidence/HELIX-PHASES-1-4-20261121/`](../../evidence/HELIX-PHASES-1-4-20261121/)
- Fine-tooth comb audit & hardening receipt (zero-prebuilt Strand A, full CFG dataflow + fixed-latency RAW stall floor, `EGP2` structural proof kernel, live LLM response parsing, 12/12 antibodies): [`evidence/HELIX-AUDIT-HARDENING-20261121/`](../../evidence/HELIX-AUDIT-HARDENING-20261121/)
- 4-Strand BFT Stem-Cell Braid (`1,612 B` seeds), Four-Wall Loop-1 Helical RSI Gate (`rsi-loop1.sh --lean`, 29 Lean 4.36.0 theorems, RSI V2 P-256 ratchet), and Live GB10 Proof-Carrying SM121 Evolutionary JIT (Antibodies `#13–#15`, `6/6` native genomes + `5/5` real 35B Full-W4 bit-exact parity): [`evidence/HELIX-BRAID4-RSI-JIT-20261121/`](../../evidence/HELIX-BRAID4-RSI-JIT-20261121/)

## Phase 5: 4-Strand BFT Braid, Compiler Mitosis, Four-Wall Loop-1 RSI & Live SM121 Evolutionary JIT

- **4 Independent Stem-Cell Seeds (`1,612 B`, `283` insns, `0` bad encodings)**: Strand 0 Monk (`408 B`), Strand 1 Predator (`396 B` W^X), Strand 2 Trickster (`404 B` W^X, `seedC0.c0`), Strand 3 Ascetic (`404 B` W^X, `seedD0.d0`) all converge bit-for-bit on `seed/out/omc` (`708fdc0f...`). `bft_healer.om` + `braid4-verify.sh` verify `N = 3f+1 = 4` quorum uniqueness, live Byzantine fault quarantine + automatic cold regrowth (`2/2`), `f = 2` fail-closed halt (`exit 20`), Compiler Mitosis, Arboris Predator↔Ascetic hot-swap (`semantic_drift=0`), and `proofs/HelixBFT.lean` (6 Lean 4.36.0 theorems, `29` total across `seed/helix/proofs/`, `0` warnings, `0` `sorry`).
- **Four-Wall Loop-1 Helical RSI (`sh seed/helix/rsi-loop1.sh --lean`)**: Chains Wall 1 (Predator + Arboris sandbox) → Wall 2 (Monk + `EGP2` dual-checker + `12` host + `3` silicon-crystallized Antibodies `#13–#15` + 29 Lean 4 theorems) → Wall 3 (`core/rsi/om/eval/` pure-OM-2 Sealed Judge + dual-strand `q36-helix-native` & `q36-helix-decode`) → Wall 4 (`core/rsi/om/governance/v2_main.om` ECDSA P-256 promotion ratchet + `v2_test` negative controls + RFC 8032 Ed25519 + 4-strand BFT cold regrowth).
- **Live Proof-Carrying SM121 Evolutionary JIT (`helix_jit.om`, `helix-build-jit.sh`)**: Intercepts production `q36` SM121 kernels before VRAM upload without modifying `om/gpu/q36/`. Live GB10 silicon caught three SM121 microarchitectural laws crystallized into Antibodies `#13` (basic-block leader pinning), `#14` (`rawFloor >= 6`), and `#15` (never shave `I2F` fixed-latency stalls), yielding `6/6` native genomes (`G1` `+3.32%` FP8+W4Head `48.25 → 49.85 tok/s`; `G2` Mitosis Hybrid `+1.11%` FullW4 Backbone `72.25 → 73.05 tok/s` / `+1.21%` FullW4+W4Head `66.38 → 67.18 tok/s`) and `5/5` real 35B Full-W4 bit-exact parity (`G1` `67.39 → 67.71 tok/s`, `ZERO_SHARED_LIBS_LOADED=1`, `XID_DELTA=0`).
