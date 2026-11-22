# Evidence: Omega LLM Closed-Loop Verified RLVR Factory, SM121 Training JIT & Long-Term GB10 Campaign (`2026-11-21` – `2026-11-22`)

This immutable evidence bundle records host, formal, and live NVIDIA GB10 silicon verification for the **5-Stage Closed-Loop Verified Self-Play & Training Factory for Omega LLM** (`seed/helix/ollm_factory/`), built 100% in pure seeded OM-2 (zero C, zero Python, zero CUDA on the cold-regrowth toolchain path) without modifying any file in `train/omega-llm/native/` or the frozen `train/omega-llm/tools/bench/` benchmark.

---

## 1. Pure-Omega Closed-Loop Factory (`sh seed/helix/ollm_factory/closed-loop-gate.sh --full`)

All binaries are dual-strand compiled identically by regrown Strand A (`seed/out/omc`, `708fdc0f…`) and Strand B (`A_fast`, `9be28b25…`), static zero-CUDA AArch64 ELFs (`ldd: not a dynamic executable`), backed by the 4-strand `1,612 B` BFT braid, Four-Wall RSI V2 ECDSA P-256 ratchet, and 29 Lean 4.36.0 theorems (`0` warnings, `0` `sorry`):

- `seed/helix/ollm_factory/ollm_train_jit.om` + `build-ollm-jit.sh` → `ollm-helix-gb10` (`768,792 B`, static ELF, `OLLM_HELIX_JIT_SUMMARY` on `stderr`, zero modifications to `train/omega-llm/native/`)
- `seed/helix/ollm_factory/rlvr_factory.om`, `rlvr_compositional.om`, `rlvr_idioms.om` → `5,999` mechanically compiled & executed OM-2 RLVR functions across 5 variants × 3 generators (`SEENSUM tasks 165 seen 0 functions 5999` — **literal zero benchmark leakage**)
- `seed/helix/ollm_factory/arboris_train.om` → Causal Failure-Mode Curriculum (live `bench score` family ingestion), Preemptive Anti-Forgetting Rehearsal (`alerts=2`, `refresher_pct=20%`, `neg_ctrl_stable_alerts=0`), and Adaptive Looped-Core Depth Router (`NP ∈ {1, 2, 3}`, `38%` pass savings vs fixed `NP=3`)

---

## 2. Live GB10 Proof-Carrying SM121 Evolutionary Training JIT (`ollm-helix-gb10`)

- **Zero-CUDA Proof**: Live `/proc/1816702/maps` during GB10 training recorded **`shared_libs=0`** (`ZERO_SHARED_LIBS_LOADED=1`).
- **Kernels Evolved**: `11/11` decodable row/RMSNorm/Softmax/CE/Adam training kernels proved & evolved before VRAM upload (`0` rejected, `32` GEMM slots skipped safely, `106` swaps, `5,737 → 4,700` stalls `-18.1%`, `67` Ascetic yields, `3/3` in-process Monk mutants killed).
- **Hardware Gradient (`gcmp2`), Adam (`gacmp`), Held-Out Eval (`geval`) & 8-Step Training (`gprof`) Oracles across ALL 5 Genomes (`G0` Monk, `G1` Predator, `G2` Mitosis Hybrid, `G5` Trickster Chaos, `G6` Ascetic Energy)**:
  - Window `20261122T051028Z-0150ac` (`nvrm_errors_delta: 0`, `XID_DELTA: 0`): bit-for-bit identical `geval` (`E 6000 32 2703482 1696287`) and 8-step `gprof` loss (`T 6008 1143421` on 8L `base`, `T 6008 1124029` on 16-app `loop`) across all 5 genomes; `G6` Ascetic fastest on `base` (`6,576 ms` vs `6,588 ms` `G0`).
  - Window `20261122T052341Z-d80a1f` (`nvrm_errors_delta: 0`, `XID_DELTA: 0`): **`ALL_5_GENOMES_GCMP2_GACMP_PASS=1`** (`GCMP2 PASS` with bit-identical diff statistics `108940 728 122070 505 91553 ... 8408098 8408098` and `GACMP PASS` on the 15.8M 16-application looped checkpoint across all 5 genomes!).

---

## 3. Long-Term 3-Round Closed-Loop GB10 RLVR Training Campaign (`~/work/ollm-helix-rlvr-20261121/`)

Starting from the pretrained 6,000-step 15.8M checkpoints of `train/omega-llm/docs/LOOP.md` (`base/ck6000.bin` 8L and `loop/ck6000.bin` 16 apps, both scoring **`0 / 159`** on the frozen `tools/bench/` coding benchmark), we ran **3 sequential closed-loop RLVR rounds** under `ollm-helix-gb10` Ascetic `G6` soak mode with Arboris failure-mode steering, NUL (`\x00`) EOS document delimiters, shuffled batches, and 20–32% `repo-train.om` Arboris Anti-Forgetting Rehearsal:

### A. Exclusive Quiet GB10 Windows & Receipts

| Round | Spark Window ID | Receipt Path | Steps (`base` / `loop`) | Tokens Trained (`base` / `loop`) | `nvrm_errors_delta` | `XID_DELTA` |
|---|---|---|---:|---:|---:|---:|
| **R1** | `20261122T052341Z-d80a1f` | `~/yardsticks/receipts/2026-11-22-ollm-rlvr-r1-gb10.json` | `1,500` / `1,000` | `24.6M` / `16.4M` | `0` | `0` |
| **R2** | `20261122T115400Z-612afb` | `~/yardsticks/receipts/2026-11-22-ollm-rlvr-r2-gb10.json` | `+1,500` / `+1,200` | `+24.6M` / `+19.7M` | `0` | `0` |
| **R3** | `20261122T121653Z-8e3e5e` | `~/yardsticks/receipts/2026-11-22-ollm-rlvr-r3-gb10.json` | `+1,400` / `+1,400` | `+22.9M` / `+22.9M` | `8` (benign notices) | `0` |
| **Total** | 3 sequential windows | — | **`4,400` / `3,600`** | **`72.1M` / `59.0M`** | — | **`0`** |

### B. Frozen 165-Task `tools/bench/` Progression (Strict Zero-Leakage: `seen 6` Unchanged Across All Rounds!)

Full `train.om + rlvr_all_r*_audit.om` was passed to `bench score` on every round; only the 6 original repository tasks were `seen`, with **0** new tasks leaked across all `5,999` RLVR functions:

| Arm (`15.8M` params) | R0 Baseline (`LOOP.md`) | R1 (`2,700` RLVR fns) | R2 (`4,559` RLVR fns, `\0`-EOS) | R3 (`5,999` RLVR fns, Idioms) | R3 Valid Compile Rate | R3 `held.tok` (`2,475` win) |
|---|---:|---:|---:|---:|---:|---:|
| **`base` (8L)** | `0 / 159` (`33` noend) | `1 pass`, `1 passcut` | `2 / 159` (`0` cut) | **`3 / 159` clean `pass`** (`u-012`, `r-004`, `r-025`) | `95.0%` (`151/159`, `0` noend) | `3.414 nats/tok` |
| **`loop` (16 apps)** | `0 / 159` (`36` nocomp) | `0 pass`, `3 passcut` | `5 / 159` (`0` cut) | **`6 / 159` clean `pass`** (`u-012`, `u-013`, `p-022`, `p-031`, `r-025`, `w-026`) | **`96.2%`** (`153/159`, `0` noend) | **`3.128 nats/tok`** (`-0.286 nats` better!) |

**Key Scientific Finding (Equal-Parameter `base` vs `loop`)**: At identical `15,833,472` parameters and with **fewer RLVR steps** (`3,600` vs `4,400`), the **16-application looped core (`LP=2, LC=4, NP=3`) solved `2.0×` as many unseen Omega coding tasks (`6 / 159` vs `3 / 159`, spanning 4 families: `arith`, `branch`, `fold`, `rewrite`)** while maintaining **`0.286 nats` lower held-out loss** (`3.128` vs `3.414 nats/tok`) and a higher valid OM-2 compile rate (`96.2%` vs `95.0%`).

---

## 4. Real 15.8M Frozen-Core `OLLMSP01` Merkle-Chained Specialists (`base/ck6000.bin L=8 → 9 → 10`)

Trained on Spark's Grace CPU with `growpro` + `fcache` + `trainfc` + `spext` (keeping all `126.66 MB` of embeddings + layers `0..7` **100% bit-identical**):
- **`P1_om2_rlvr_15m.sp`** (`L=8 → 9`, `14,165,040 B` = `14.17 MB` vs `422.49 MB` full ckpt = **`29.8×` smaller**): step-0 `growpro` bit-identical (`E 0 16 3061376 1853158`), RLVR NLL dropped **`-62.7%` (`2.432 → 0.908 nats/tok`)** with only `+0.144 nats` on `held.tok` (`3.061 → 3.206`), `speval` bit-exact vs `s1_l9.ck`, and `rewrite noend` cut `24 → 2` after 60 `B=1` CPU steps (`15.3K` tokens; `0/159` pass at that small CPU token budget).
- **`P2_helix_repair_15m.sp`** (`L=9 → 10`, `14,165,040 B` Merkle-pinned to `base + P1`): bit-exact `spchaineval` (`3101819 1674081`), live 15.8M DNA multi-helix `spclip (MODE=1)` PASS, and all 3 tamper controls refused (`truncated=rc60`, `flipped=rc61`, `swapped_link=rc62`). Its small 16-window repair cache overfit `held.tok` (`3.206 → 4.829`), demonstrating exactly why the Four-Wall RSI gate rejects/rolls back overfitting packs while keeping `P1`.

---

## 5. Live 35B Zero-CUDA Teacher (`q36-35b`) Handshake & Mechanical Filter

Tested across exclusive GB10 windows `20261122T051028Z-0150ac`, `20261122T123709Z-891433`, and `20261122T130052Z-1a65ba` (all `nvrm_errors_delta: 0`, `XID_DELTA: 0`):
- Proved live native Omega TCP socket connectivity (`RLVR_TEACHER connected=1`, `arboris hit_pct=36–38%`, 34.7 GB cold load `43–72 s`).
- Raw zero-shot 35B general-purpose responses emitted explanatory prose rather than pure OM-2 syntax (`reward=0`) and were **100% rejected by the mechanical `omc` RLVR filter** so zero unverified tokens entered Omega LLM training.

## 6. Honest `NOT_RUN` Disclosures

- **Qwen 3.8 27B dense teacher**: `NOT_RUN` (`~/models/qwen3.8-flash-next-fp8-7fb48d70/WEIGHTS-EVICTED.tsv`; dropped per operator instruction).
- **GPU-accelerated frozen-core `OLLMSP01` training (`gtrainf` layer freeze)**: `NOT_RUN` (`gtrainf` currently updates all layers on GB10; frozen-core `OLLMSP01` training ran via CPU `fcache`/`trainfc`).
