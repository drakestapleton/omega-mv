# Evidence Receipt: Proof-Carrying Evolutionary Helix Dual-Seed DDC & Live GB10 Silicon Run (2026-11-21)

- **Base commit verified on Spark**: `783eb4ab6d525901ac4417910dea61dafaa584db` (clean isolated clone)
- **Host**: `spark-b87b` (NVIDIA GB10 Grace Blackwell superchip, Ubuntu 24.04 AArch64 Linux, driver `580.173.02`)
- **Exclusive GB10 window**: `20261122T030151Z-c7483f` (receipt `/home/drakestapleton/yardsticks/receipts/2026-11-21-helix-gb10-live.json`, `nvrm_errors_delta: 0`, `exit: 0`)
- **Total dual-seed weight**: `804 bytes` (`408 B` Strand A `seed/rung0/seed0.hex` + `396 B` Strand B `seed/helix/rung0/seedB0.b0`)

## 1. Dual-Seed Diverse Double Compilation & Helix Twist (4-Way Bit-for-Bit Convergence)

| Artifact | Route / Producer | Bytes | SHA-256 |
|---|---|---:|---|
| `seed0.bin` | `load0.sh` (Strand A, 408 B) | 408 | `aca00cf3677236809f0f223437398c6bb429e4c65f13d58762bcf96d13799474` |
| `seedB0.bin` | `loadB0.sh` (Strand B, 396 B W^X, 69 insns audited by `objdump -D`, self-rebuilds) | 396 | `dc2edfb38f735309e7596961333d0f4c40f8e615bde348fc1a29bdf8c6645c84` |
| `hexB1.bin` | `seedB0 < hexB1.b0 == hexB1 < hexB1.b1` | 948 | `e2fe5955a174e334efb3c897a9aab9cf569fec3f1a1ed146c3ad5f3b995467f8` |
| `omB2.bin` | `hexB1 < omB2.b1` (independent pure value-stack Omegese compiler, W^X) | 15,464 | `fd4d8e83459cb94f6a59951d572ad317070e61cd1b59aa83c5da0be4a1cf397d` |
| `omc_stage1_B` | `omB2(omc.om)` — **whole different stack-machine binary!** | 1,111,848 | `eb78fc81a100e84c9707590013c799275248ed4f43908ae3b5611175509179e0` |
| `omc_stage2_B` | `omc_stage1_B(omc.om)` — **Route B direct DDC** | 952,784 | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` |
| `ng_stage1_B` | `omB2(ng.src)` — **Strand B birthed with ZERO Strand A bytes!** | 916,604 | `74dffdf15fda763dee6bb11fa65cf315254dadc538a2f86b7114eaeb6e7dc4c1` |
| `ng_B == ng_B2 == ng_from_A_gen2` | Strand B self-hosting fixpoint (seedB0-born == Strand A-born!) | — | `435a19cf58381f3628c7e2b64a0b678055deb082e2ebc5006afe9b61cd55a713` |
| `A_fast` | `ng_B(omc.om)` — **45.7% smaller optimized Strand A** (`min 17.60 ms` vs `20.53 ms`) | 517,784 | `9be28b252be585f242669db20a31169992fcd832148c84186a2a82b17263629e` |
| `A_from_B` | `A_fast(omc.om)` — **Helix Twist DDC** | 952,784 | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` |
| `A_seed == seed/out/omc` | Strand A (`om4(omc.om)` fixpoint) | 952,784 | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` |
| `ref` (`ddc650`) | Route I (`gcc 13.3.0` + `tools/omega_ref/omega_ref.c`) | 952,784 | `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3` |
| Control 1 (poisoned stage1) | NOP injected in `matconst` of `omc.om` via `omB2` | 978,916 | `14e9fac0f17889eca4203e0682b42fa46a65e26c4fe13ade3ff66b2034ed024f` (**CAUGHT**) |

## 2. Lean 4.35.0 Machine-Checked Proofs (12/12 PASS, ZERO `sorry`, ZERO non-standard axioms)

- `seed/helix/proofs/HelixSoundness.lean`:
  - `independent_swap_commutes`: `[propext, Quot.sound]`
  - `dag_preserving_perm_sound`: `[propext, Quot.sound]`
  - `helix_ddc_correspondence`: no axioms
  - `raw_violation_counterexample` (non-vacuity negative control): no axioms
- `seed/helix/proofs/HelixAntibodies.lean`:
  - All 7 antibodies (`antibody_digest_spoof`, `antibody_non_bijection`, `antibody_opcode_smuggle`, `antibody_anchor_escape`, `antibody_dep_inversion`, `antibody_hazard_smuggle`, `antibody_length_mismatch`) + positive witness `antibody_valid_rung_admitted`: `[propext]` or `[propext, Quot.sound]` only.

## 3. Live GB10 Silicon Closed-Loop (Window `20261122T030151Z-c7483f`, ZERO CUDA)

- **Dual-strand zero-CUDA AI server & runner bit-for-bit identity** (`ldd: not a dynamic executable`):
  - `q36-serve` (Strand A `seed0` == Strand B `seedB0` == Gen2 self-recompile): `71527a3f9689ad5e213a442285641ba058dee45c29603cd7fb0e8f15135b8d85`
  - `q36-native` (Strand A `seed0` == Strand B `seedB0` == Gen2 self-recompile): `e4746000cc87d8f060f6c0b064ee03b04a4538aa52ccc13cc7ee59da3ffe0cf2`
- **Live local 35B Omega LLM (`q36-serve` Full-W4 on port 18099) + Arboris + Predator + Monk + Immune**:
  - `PREDATOR_LLM connected=1 port=18099 resp_bytes=375`
  - Live `q36-serve` Arboris telemetry moved from `hits=0/0` to `arboris_hits=3393, arboris_total=9520 (35%)` during Predator's live prompt.
  - `ARBORIS_NERVOUS intuition_ms_lt1 shape=3 top_trick=6 top_tactic=8 act_score=1522`
  - `ARBORIS_ASSOC dual_cue=(shape=3,symptom=STALL_PRESSURE) collision_node=6 collision_energy=2122`
  - `MONK PASS rung=976a90df9b70a004791c5c4b364a697894377181a43fc09487cbbb39181b86e6 insns=32 swapped=10 stall_ref=71 stall_cand=71 hazards=0`
  - `IMMUNE PASS legit=PASS attacks=7 killed=7 antibodies=7/7` (exit codes 12, 13, 14, 15, 16, 17, 11)
- **Live GB10 Silicon Parity & Timing (`q36-native` born from 396 B `seedB0`)**:
  - `11/11` live GB10 SM121 kernel parity self-test PASS + Arboris 40L×256E online prefetcher (`102 µs/tok`, `93%` hit rate) PASS
  - `40L Full-W4 Backbone (0.79 GB/tok)`: `13.983 ms/tok` (**`71.51 tok/s`**), `finite=OK`
  - `40L Full-W4 + W4 Two-Pass Exact lm_head (1.07 GB/tok)`: `15.176 ms/tok` (**`65.89 tok/s`**), `finite=OK`
  - `40L W4-MoE + W4 Head (2.13 GB/tok)`: `18.361 ms/tok` (`54.46 tok/s`), `finite=OK`
  - `40L FP8 + W4 Head (2.86 GB/tok)`: `20.575 ms/tok` (`48.60 tok/s`), `finite=OK`
  - `nvrm_errors_delta: 0`, `exit: 0`.
