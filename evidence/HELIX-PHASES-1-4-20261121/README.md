# Evidence Receipt: Proof-Carrying Evolutionary Helix Phases 1–4 Complete Verification (2026-11-21)

- **Base commit verified on Spark**: `08acddf86b4933fc747f9f01204d2775948a16b3` (clean isolated clone `git clone --shared ~/git/omega-mv.git`)
- **Command executed**: `PATH="$HOME/.elan/bin:$PATH" sh seed/helix/cold-regrowth.sh --lean` (exit `0`, zero C, zero Python, zero CUDA)
- **Lean toolchain**: `Lean (version 4.36.0, aarch64-unknown-linux-gnu, commit 611c117bfaf7b7ae1cfcf246ce6fba31e8f509e9, Release)` (0 warnings, 0 `sorry`, 0 `native_decide`, standard axioms only)
- **Total dual-seed weight**: `804 bytes` (`408 B` Strand A `seed/rung0/seed0.hex` + `396 B` Strand B `seed/helix/rung0/seedB0.b0`)
- **Live GB10 silicon receipt (prior authorized window)**: `20261122T030151Z-c7483f` (`evidence/HELIX-DDC-20261121/`, `nvrm_errors_delta: 0`, `exit: 0`)

---

## Phase 1: Dual-Seed DDC + Cross-OS/Cross-ISA Environment Diversity + RFC 8032 Ed25519 Signed Receipt

### 7-Way Bit-for-Bit Convergence on `seed/out/omc` (`952,784 B`, SHA-256 `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`)

| Route | Host OS / Kernel | Host ISA / Compiler | Stage-1 / Intermediate | Stage-2 `omc` SHA-256 | Verdict |
|---|---|---|---|---|---|
| **1. Strand A (The Monk)** | Ubuntu 24.04 Linux | AArch64 (`seed0.hex` 408 B -> `om4`) | `om4` | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **2. Strand B Direct (The Predator)** | Ubuntu 24.04 Linux | AArch64 (`seedB0.b0` 396 B W^X -> `hexB1` -> `omB2` 15,464 B stack-machine) | `omc_stage1_B` (`1,111,848 B`, `eb78fc81a100...`) | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **3. Double Helix Twist** | Ubuntu 24.04 Linux | AArch64 (`seedB0` -> `omB2(ng.src)` -> `ng_B` -> `A_fast` `517,784 B`) | `ng_B` (`435a19cf5838...`), `A_fast` (`9be28b252be5...`) | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **4. Linux AArch64 Reference C** | Ubuntu 24.04 Linux | AArch64 (`gcc 13.3.0`, `tools/omega_ref/omega_ref.c`) | `ddc650` | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **5. Linux x86-64 Cross-ISA** | Ubuntu 24.04 Linux | x86-64 (`x86_64-linux-gnu-gcc` + `qemu-x86_64` on Spark) | x86-64 ELF `omega_ref` | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **6. macOS Darwin ARM64** | macOS (XNU kernel) | Apple Silicon ARM64 (`Apple Clang 17`, Mach-O) | Darwin arm64 Mach-O | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **7. macOS Darwin x86-64** | macOS (XNU + Rosetta 2) | x86-64 (`Apple Clang 17 -arch x86_64`, Mach-O) | Darwin x86_64 Mach-O | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` | **PASS** |
| **Negative Control 1** | Ubuntu 24.04 Linux | Poisoned NOP in `matconst` via `omB2` | `978,916 B` | `14e9fac0f178...` (`!= 708fdc0f...`) | **CAUGHT** |

### Pure-Omega RFC 8032 Ed25519 Receipt Signature (`seed/helix/sign_ddc.om`)

- Binary `sign_ddc` compiled identically by Strand A (`omc_A`) and Strand B (`omc_B_fast`).
- Public reproducible self-test authority key (`SHA-512("HELIX-DDC-RFC8032-PUBLIC-TEST-AUTHORITY-V1")[0..32)` — explicitly NOT an operator secret):
  - **Public key (32 B hex)**: `bd002b746d3864433026901f3e2581503127d36349919f99c4816523d8adaada`
  - **Canonical 373-byte DDC manifest signed**: `seedA=baaf081f...`, `seedB=da2e6b00...`, `omc_stage2=708fdc0f...`, `ng_B=435a19cf...`, `A_fast=9be28b25...`
  - **Ed25519 signature (64 B hex)**: `894d4e7f84526c7e72e4ff7195b658eb6243815658df032fd51d83cc1d3272ac50774ab1d738219618d8acc97f7a3e14560755c13f6db4b4f3f6f5d5252eb203`
  - **Verification**: `DDC_ED25519_SELFTEST PASS bytes=373 ... verify_valid=1 tamper_rejected=1` + `DDC_ED25519_VERIFY PASS bytes=373` (1-bit tamper control rejected).

---

## Phase 2: Proof-Carrying Optimization Rungs, E-Graph Optimizer, Dual-Checker & 11-Antibody Immune System

### 1. Lean 4.36.0 Machine-Checked Proofs (23 Checked Declarations, ZERO `sorry`, ZERO non-standard axioms)

- **`seed/helix/proofs/HelixSoundness.lean`** (4 theorems):
  - `independent_swap_commutes`, `dag_preserving_perm_sound` (`[propext, Quot.sound]`), `helix_ddc_correspondence`, `raw_violation_counterexample` (no axioms).
- **`seed/helix/proofs/HelixAntibodies.lean`** (11 permanent antibodies + 2 positive witnesses):
  - 7 SM121 schedule rung antibodies (`antibody_digest_spoof`, `antibody_non_bijection`, `antibody_opcode_smuggle`, `antibody_anchor_escape`, `antibody_dep_inversion`, `antibody_hazard_smuggle`, `antibody_length_mismatch`, `antibody_valid_rung_admitted`).
  - 4 `uor-gpu` launch-gate antibodies (`antibody_p0_sig_smuggle`, `antibody_trailing_bytes`, `antibody_misaligned_qmd`, `antibody_zero_gen_cap`, `antibody_valid_launch_admitted`).
- **`seed/helix/proofs/HelixKernelIR.lean`** (inductive SM121/host kernel IR `KExpr`, `eval`, `gb10Cost`, 12 semantic-preservation rewrite theorems, `EGraphStep`/`EGraphEquiv`, `egraph_extract_sound`, `ex_gemv_mac_equiv`, `ex_gemv_mac_strictly_faster`, `unsound_rewrite_counterexample`).

### 2. Verified Equality-Saturation E-Graph Optimizer + Strand A Dual-Checker Trust Anchor

- **`seed/helix/egraph_opt.om`** (compiled by Strand B `A_fast`):
  - `q36_bf16_gemv_mac`: GB10 cost `7 -> 2` (7 proof steps)
  - `q36_w4_unpack_mac`: GB10 cost `9 -> 2` (8 proof steps)
  - `q36_swiglu_gate`: GB10 cost `10 -> 2` (8 proof steps)
  - Emits compact `EGP1` proof certificate (`23` total verified rewrite steps).
- **`seed/helix/dual_checker.om`** (compiled strictly by Strand A `omc_A`, zero shared code):
  - Independently re-verifies all `23` e-graph rewrite steps (`DUAL_CHECK_EGRAPH: PASS kernels=3 verified_steps=23`).
  - Kills injected unsound rule `add -> mul` (`DUAL_CHECK_NEG_CONTROL: KILLED`).
  - Kills all 4 `uor-gpu` adversarial launch-gate probes (`ANTIBODY 8..11: KILLED codes 21..24`) -> `total_helix_antibodies=11/11`.

### 3. Three Real Production `q36` SM121 Kernels Verified Through Predator -> Monk -> 11 Antibodies

Extracted directly from `om/gpu/q36/emit_fast.om` via `seed/helix/extract_q36_kernels.om`:

| Production `q36` Kernel | Instructions | Swapped | Ref Stalls -> Cand Stalls | Stalls Saved | Hazards | Rung Digest | Immune Attacks Killed |
|---|---:|---:|---|---:|---:|---|---|
| `bf16_gemv_fast` (mode `a`) | 227 | 102 | `1044 -> 981` | **-63** | `0` | `e8e7e7a3bd4c...` | `7/7` (+4 dual-checker = `11/11`) |
| `fp8_b128_gemv_fast` (mode `b`) | 207 | 102 | `895 -> 825` | **-70** | `0` | `317ce3367628...` | `7/7` (+4 dual-checker = `11/11`) |
| `w4_b32_gemv_fast` (mode `m`) | 437 | 170 | `2118 -> 1921` | **-197** | `0` | `c5dd90453758...` | `7/7` (+4 dual-checker = `11/11`) |

*(Live GB10 silicon execution of all 11 `q36` kernels + live `q36-serve` + Arboris already verified in window `20261122T030151Z-c7483f`: `11/11` parity PASS, `71.51 tok/s` backbone / `65.89 tok/s` full-token, `nvrm_errors_delta: 0`.)*

---

## Phase 3: Arboris System Nervous System Benchmarks (`seed/helix/arboris_nervous_bench.om`)

All three Phase 3 receipts verified in one standalone pure-Omega static ELF compiled by Strand B:

1. **Track 3A (Compiler & Proof-Search Intuition)**:
   - `ARBORIS_3A_RECEIPT targets=64 brute_probes=2080 arboris_probes=64 brute_ns=170546 arboris_ns=25648 probe_reduction_pct=96`
   - **96% fewer proof-search probes** (`2080 -> 64`) and **`6.65x` faster wall-clock time** (`170.5 us -> 25.6 us`).
2. **Track 3B (Pure-Omega Associative Agent Memory)**:
   - `ARBORIS_3B_RECEIPT queries=10 arboris_recall_at_1_pct=100 vector_recall_at_1_pct=40 avg_arboris_query_ns=1068`
   - **100% Recall@1 vs 40% token/vector baseline** on 2-hop dual-cue root-cause collision queries in **`1.07 us/query`** (0.31–1.07 us across runs).
3. **Track 3C (Anticipatory Scheduling in Aienux)**:
   - `ARBORIS_3C_RECEIPT steps=8000 streams=8 reactive_p95_us=400 arboris_p95_us=12 reactive_p99_us=400 arboris_p99_us=12 arboris_hit_pct=99 arboris_overhead_ns=234`
   - **Both p95 and p99 tail latency reduced `400 us -> 12 us` (`33.3x`)**, **99% anticipatory hit rate**, bounded **`234 ns`** scheduler overhead per step.

---

## Phase 4: Single-Command Clean-Room Cold Regrowth & Two-Generation Helical Self-Recompilation

Executed via `sh seed/helix/cold-regrowth.sh --lean` inside a fresh clean clone with zero C, zero Python, zero CUDA, zero network:

- **Dual-strand pure-Omega OS & GPU gate compilation**:
  - `aienux/units-gate.om`: bit-for-bit identical across Strand A & Strand B (`4e097221d8396db6f3af564855edbb17382000eaad47ec711de2ef9431c56ba3`)
  - `protocol/units-gate.om`: bit-for-bit identical across Strand A & Strand B (`652ba774dd53686d1d4ca505706f2b851f19bc2a9d33e49fecfefee1d77a5d55`)
  - `uor-gpu-gate`: bit-for-bit identical across Strand A & Strand B (`3d4a32d09c7064cc9e7580ede260e5f1c31463d804168a0e9c5ecf34e75c5555`) AND executed live -> `UOR_GPU_GATE_PASS` (`policy_level: P3`, `reason_code: 0`).
- **2-Generation Helical Self-Recompilation of Zero-CUDA 35B AI Server (`Gen0 == Gen1 == Gen2`)**:
  - `q36-serve`: `71527a3f9689ad5e213a442285641ba058dee45c29603cd7fb0e8f15135b8d85` (static ELF, zero CUDA)
  - `q36-native`: `e4746000cc87d8f060f6c0b064ee03b04a4538aa52ccc13cc7ee59da3ffe0cf2` (static ELF, zero CUDA)
- **Honest External-Engineer Status**:
  - Clean-room regrowth on Spark AArch64 + cross-OS/ISA DDC on macOS ARM64, macOS x86-64, and Linux x86-64: **PASS**.
  - Execution of `sh seed/helix/cold-regrowth.sh --lean` by an independent third-party human engineer on an external physical AArch64 machine: **NOT_RUN** (ready to run as a single command from this commit).
