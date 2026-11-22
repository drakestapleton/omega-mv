# Evidence: 4-Strand BFT Stem-Cell Braid, Four-Wall Loop-1 Helical RSI & Live GB10 Proof-Carrying SM121 Evolutionary JIT (`2026-11-21`)

This immutable evidence bundle records host, formal Lean 4, and live NVIDIA GB10 silicon verification for three integrated extensions of `seed/helix/`:

1. **4-Strand Byzantine Self-Healing Stem-Cell Braid (`N = 3f + 1 = 4`, `f = 1`) + Compiler Mitosis + Arboris Predator↔Ascetic Hot-Swap** (`seed/helix/strand3_trickster/`, `seed/helix/strand4_ascetic/`, `seed/helix/bft_healer.om`, `seed/helix/braid4-verify.sh`, `seed/helix/proofs/HelixBFT.lean`)
2. **Four-Wall Loop-1 Helical RSI Containment Gate** (`seed/helix/rsi-loop1.sh`) snapping together Wall 1 (Untrusted Proposer), Wall 2 (Strand A Monk + `EGP2` Dual-Checker + 15 Antibodies + 29 Lean 4.36.0 theorems), Wall 3 (pure-OM-2 `core/rsi/om/eval/` Sealed Judge + live GB10 silicon receipts), and Wall 4 (pure-OM-2 `core/rsi/om/governance/v2_main.om` ECDSA P-256 promotion ratchet + RFC 8032 Ed25519 receipt verification + 4-strand BFT cold regrowth)
3. **In-Process Zero-CUDA Proof-Carrying SM121 Evolutionary JIT** (`seed/helix/helix_jit.om`, `seed/helix/helix-build-jit.sh`) wired directly into the production Qwen 3.6 35B-A3B zero-CUDA stack (`q36-helix-native` & `q36-helix-decode`) without modifying any file in `om/gpu/q36/`

---

## 1. Four Independent Hand-Assembled AArch64 Stem-Cell Seeds (`1,612 B` Total)

All four seeds use distinct ELF load addresses, distinct source delimiters/comment syntaxes, and disjoint register banks; all four pass `objdump -D -b binary -m aarch64 --start-address=0x78` with **`bad = 0`**, pass self-rebuild and malformed-input negative controls, and converge **bit-for-bit** on `seed/out/omc` (`708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`, `952,784 B`):

| Strand | Persona | Seed Source | Size | `objdump` Insns (`bad`) | Load Addr / W^X | Syntax / Registers | Seed Binary SHA-256 |
|---|---|---|---:|---:|---|---|---|
| **0** | **The Monk** | `seed/rung0/seed0.hex` | `408 B` | `72` (`0`) | `0x400000` (RWX) | `#` comments | `aca00cf3677236809f0f223437398c6bb429e4c65f13d58762bcf96d13799474` |
| **1** | **The Predator** | `seed/helix/rung0/seedB0.b0` | `396 B` | `69` (`0`) | `0x500000` (W^X) | `;` comments | `dc2edfb38f735309e7596961333d0f4c40f8e615bde348fc1a29bdf8c6645c84` |
| **2** | **The Trickster** | `seed/helix/strand3_trickster/seedC0.c0` | `404 B` | `71` (`0`) | `0x600000` (W^X) | `%` comments, `:` sep, `x19..x23` | `b5b848f516aa114743062a7a740edb1e00a5d7c4a79a1b2f10fc46ea1a40e38c` |
| **3** | **The Ascetic** | `seed/helix/strand4_ascetic/seedD0.d0` | `404 B` | `71` (`0`) | `0x700000` (W^X) | `!` comments, `,` sep, `x24..x28` | `bc68d95f039ab40aa9e6bd1d116b4c8dfe86981d70fb0d1261d0863358690f76` |

- **Live BFT Auto-Healing (`braid4-verify.sh`)**: `4/4 UNANIMOUS` → poisoned Strand 1 (`3/4 QUARANTINE_AND_REGROW`) → cold-regrown from `396 B` `seedB0.b0` → `4/4 UNANIMOUS` → poisoned Strand 2 (`3/4 QUARANTINE_AND_REGROW`) → cold-regrown from `404 B` `seedC0.c0` → `4/4 UNANIMOUS`; `f = 2` simultaneous faults → `NO_QUORUM_HALT` fail-closed (`exit 20`, **PASS**).
- **Compiler Mitosis & Arboris Predator↔Ascetic Hot-Swap**: `children_tested=5 harvested=2 killed=2 (1 Monk, 1 Trickster) retired=1 hotswaps=4 semantic_drift=0`.

---

## 2. Four-Wall Loop-1 Helical RSI Gate (`sh seed/helix/rsi-loop1.sh --lean`) — **PASS**

- **Wall 1 & 2 (`cold-regrowth.sh --lean`)**: Zero-prebuilt Strand A + independent Strand B Wheeler DDC + RFC 8032 Ed25519 receipt verify (`tamper_rejected=1`) + `EGP2` structural e-graph (`verified_steps=23`, `eval_checks=12`, `neg_controls=2/2`) + 3 production `q36` SM121 kernels (`a` 227 insns / `-113` stalls, `b` 207 insns / `-111` stalls, `m` 437 insns / `-273` stalls, `hazards=0`) + `12/12` host antibodies + Arboris 3A (`96%` probe reduction) / 3B (`100%` vs `40%`, `308 ns`) / 3C (`p95/p99 400 µs → 12 µs`, `99%` hit) + dual-strand `aienux`/`protocol`/`uor-gpu-gate` (`UOR_GPU_GATE_PASS`) + `Gen0==Gen1==Gen2` `q36-serve` & `q36-native`.
- **Wall 3 (Sealed Judge)**: Pure-OM-2 `rsi_eval_test` (`RSI EVAL CANARY ROLLBACK TEST SUITE PASS`, dual-strand identical `93afbbe22c984918df28d201f98101c704604673d549625828736e7349d9c055`) + dual-strand static zero-CUDA JIT binaries:
  - `q36-helix-native`: `488,036 B`, SHA-256 `d28652e5a7b2e85714597334aa842715bf2786bd73977e7888b3f6757695bb88`, `ldd: not a dynamic executable`
  - `q36-helix-decode`: `558,504 B`, SHA-256 `e82ccd631810c36e337cfa4cfe5f455db61e38c82adeb8a2ef02d42cd07bd611`, `ldd: not a dynamic executable`
- **Wall 4 (Cryptographic Ratchet)**:
  - Pure-OM-2 `rsi_v2_gate` ECDSA P-256 (`PROMOTE digest=43a6aaa45e731bc808652b0abad96af659d841d6079df421d3a62de76a7c4200`, dual-strand identical `b114e29d3a17d6afe7557e072d04fe356c5880e57eba00438f9b6a088c803900`)
  - Pure-OM-2 `rsi_v2_test` negative controls (`RSI V2 P256 PROMOTION GATE TEST SUITE PASS`, dual-strand identical `7d1f8463e785d776b4f514e3e4f068d7ba14c096a66c08117e70cefb0295ac44`)
- **Lean 4.36.0 Formal Proofs (`29` theorems across 4 files, `0` warnings, `0` `sorry`, standard axioms only)**:
  - `HelixSoundness.lean` (4), `HelixAntibodies.lean` (13), `HelixKernelIR.lean` (6), `HelixBFT.lean` (6: `bft_quorum_unique`, `bft_survives_single_fault`, `bft_quarantine_regrow_restores_unanimity`, `ascetic_predator_hotswap_sound`, `mitosis_monotonic_and_safe`, `bft_double_fault_counterexample`).

---

## 3. Three Blackwell SM121 Microarchitectural Laws Caught on Live GB10 Silicon & Crystallized into Permanent Antibodies (`#13–#15`)

| Antibody | Failure Caught on Live GB10 Silicon | Root Cause on Blackwell SM121 | Permanent Immunity Crystallized |
|---|---|---|---|
| **#13** | Run 1 (`20261122T041809Z-3e5cfc`): `G1` failed parity test #2 | `BRA` target basic-block leaders (`mSx`, `mStage`) were swapped across loop boundaries | `hxMarkTargets`/`mkMarkTargets`/`prMarkTargets`/`imMarkTargets` pin `pc=0`, every `BRA` target, and every `BRA` fall-through |
| **#14** | Run 2 (`20261122T042834Z-e6a79b`): `G2/G3/G4` (`rawFloor=4`) timed out | General fixed-latency SM121 ALU pipe floor is `6` cycles, not `4` | `hxRawFloor = 6` enforced unconditionally (`XID_DELTA=0`, zero timeouts across all genomes) |
| **#15** | Run 3 (`20261122T044158Z-a4156d`): `G2/G3` failed test #9 (`21` stalls shaved on `I2F`) | `I2F` (`nm==31`) is fixed-latency on SM121 even when `wbar<6`; shaving `4→1` corrupts W4 unpack | Removed `hxIsVarBurst` `I2F` stall shaving; all `6/6` native genomes + `5/5` real 35B genomes pass `100%` |

---

## 4. Final Clean Live GB10 Silicon Verification (`window 20261122T044711Z-fbabd9`)

- **Spark Receipt**: `/home/drakestapleton/yardsticks/receipts/2026-11-21-helix-rsi-loop1-final.json` (`exit: 0`, `seconds: 245.784`, `lock_holders_max: 1`, `XID_DELTA: 0`, `nvrm_errors_delta: 24` benign per-process RM teardown notices across 11 separate zero-CUDA exits — identical to the `G0`-only control run which also had `24` notices and `0` Xids).
- **Zero-CUDA Proof**: Live `/proc/3767257/maps` during GB10 execution recorded **`shared_libs=0`** (`ZERO_SHARED_LIBS_LOADED=1`).

### A. `q36-helix-native` (`6/6` Genomes `11/11` Parity PASS, `3/3` In-Process Monk Mutants Killed)

| Genome | Role | Kernels Proved | Swaps | Stalls (`ref → cand`) | Yields Tuned | FP8+W4Head (`2.86 GB`) | W4MoE+W4Head (`2.13 GB`) | FullW4 Backbone (`0.79 GB`) | FullW4+W4Head (`1.07 GB`) |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|
| **`G0`** | Monk Reference | `0` (baseline) | `0` | `0 → 0` | `0` | `20,723 µs` (`48.25 tok/s`) | `18,305 µs` (`54.62 tok/s`) | `13,839 µs` (`72.25 tok/s`) | `15,064 µs` (`66.38 tok/s`) |
| **`G1`** | Predator (`rawFloor=6`) | `9/13` | `421` | `12,596 → 8,718` | `0` | **`20,058 µs` (`49.85 tok/s`, +3.32%)** | **`18,033 µs` (`55.45 tok/s`, +1.52%)** | `13,757 µs` (`72.69 tok/s`, +0.61%) | `14,944 µs` (`66.91 tok/s`, +0.80%) |
| **`G2`** | Mitosis Hybrid (`G1+G6`) | `9/13` | `421` | `12,596 → 8,718` | `235` | `20,392 µs` (`49.03 tok/s`, +1.62%) | `18,182 µs` (`54.99 tok/s`, +0.68%) | **`13,689 µs` (`73.05 tok/s`, +1.11%)** | **`14,885 µs` (`67.18 tok/s`, +1.21%)** |
| **`G3`** | Mitosis 2-Pass | `9/13` | `892` | `12,596 → 8,784` | `235` | `20,230 µs` (`49.43 tok/s`, +2.45%) | `18,225 µs` (`54.86 tok/s`, +0.44%) | `13,821 µs` (`72.35 tok/s`, +0.14%) | `15,093 µs` (`66.25 tok/s`, -0.20%) |
| **`G5`** | Trickster Chaos | `9/13` | `425` rev | `12,596 → 13,040` | `727` | `21,177 µs` (`47.22 tok/s`) | `18,335 µs` (`54.54 tok/s`) | `13,942 µs` (`71.72 tok/s`) | `15,141 µs` (`66.04 tok/s`) |
| **`G6`** | Ascetic Energy | `9/13` | `0` | `12,596 → 8,980` | `235` | `20,247 µs` (`49.39 tok/s`, +2.36%) | `18,088 µs` (`55.28 tok/s`, +1.21%) | `13,746 µs` (`72.74 tok/s`, +0.68%) | `14,937 µs` (`66.94 tok/s`, +0.84%) |

### B. Real-Weight 35B Qwen 3.6 Full-W4 `q36-helix-decode` (`5/5` Genomes `EXACT_MATCH` on All 24 Tokens)

All 5 genomes produced `W4 Two-Pass Exact lm_head PARITY=EXACT vs Full BF16 (tok=271)`, `arboris_real_hit_pct=42`, and the exact same 24 token IDs (`271 760 6511 314 9338 369 2972 57590 159034 248046 198 248044 248045 248045 198 248045 198 248046 198 248045 846 198 248046 198`, `ALL_5_GENOMES_PARITY=1`):

| Genome | Role | Kernels Proved | Swaps | Stalls (`ref → cand`) | Yields Tuned | Real 35B Full-W4 Speed | Delta vs `G0` |
|---|---|---:|---:|---|---:|---:|---:|
| **`G0`** | Monk Reference | `0` | `0` | `0 → 0` | `0` | `14,837 µs/tok` (`67.39 tok/s`) | baseline |
| **`G1`** | Predator | `22/25` | `1,011` | `30,398 → 21,819` | `0` | **`14,767 µs/tok` (`67.71 tok/s`)** | **`+0.47%` (fastest)** |
| **`G6`** | Ascetic Energy | `22/25` | `0` | `30,398 → 22,474` | `728` | `14,814 µs/tok` (`67.50 tok/s`) | `+0.16%` |
| **`G2`** | Mitosis Hybrid | `22/25` | `1,011` | `30,398 → 21,819` | `728` | `14,823 µs/tok` (`67.46 tok/s`) | `+0.10%` |
| **`G5`** | Trickster Chaos | `22/25` | `1,019` rev | `30,398 → 31,561` | `1,766` | `14,944 µs/tok` (`66.91 tok/s`) | `-0.71%` (chaos pass) |

## 5. Honest Scope & `NOT_RUN` Disclosures

- **External third-party human cold-regrowth**: `NOT_RUN` (all cold-regrowth runs were executed by our agent on DGX Spark AArch64 + Darwin cross-ISA verification).
- **Physical multi-silicon BFT network across distinct physical CPUs (e.g., RISC-V + x86 + ARM talking over Interplane)**: `NOT_RUN` (current 4-strand BFT verification runs all 4 independent stem-cell strands on Spark AArch64; cross-ISA DDC across 7 build routes / 3 OS-ISA targets was separately verified in `evidence/HELIX-DDC-20261121/`).
- **Loop-2 / Loop-3 weight-level neural RSI**: `NOT_RUN` (this evidence covers Loop-1 Substrate RSI: compiler, SM121 kernels, and runtime).
