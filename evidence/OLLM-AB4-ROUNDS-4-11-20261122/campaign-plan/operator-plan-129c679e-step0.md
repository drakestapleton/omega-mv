# 4-Strand Architect–Builder RLVR Plan (Single DGX Spark / GB10)

This specification unifies the **Architect–Builder tandem** (`q36-35b` + `15.8M` looped Omega LLM) with the **4-strand BFT braid** and **`OLLMSP01` DNA multi-helix specialist chains (`spclip`)**. It solves two verified bottlenecks on a single GB10 at once: bypassing `q36-35b`'s fail-closed `omc` rejection on raw zero-shot OM-2 prose (`reward=0`), while expanding effective coding capacity past the `15,833,472`-parameter looped core's current `6 / 159` pass rate without risking catastrophic forgetting or monolithic checkpoint rebuilds.

---

## 1. System Architecture & Role Split

Rather than forcing one model to handle both deep algorithmic reasoning and strict OM-2 syntax, the pipeline separates planning, multi-strand synthesis, deterministic verification, and fault-tolerant promotion across four layers.

| Layer | Component | Verified Baseline / Constraints | Production Role |
| --- | --- | --- | --- |
| **Architect** | `q36-35b` (Zero-CUDA Qwen 3.6 35B-A3B)

 | `~34.7 GB` checkpoint; `67.7 tok/s` Full-W4; `43–72 s` SSD cold-load

 | Produces structured, language-neutral algorithm plans (inputs, state transitions, edge cases, and I/O test vectors)—never raw OM-2 code

 |
| **Multi-Strand Builder** | Frozen `loop_r3` core + 4 chained `OLLMSP01` strands (`spclip MODE=1`)

 | `15,833,472`-param looped core (`16` apps), `96.2%` valid OM-2 compile rate, `0 noend`, `6 / 159` passes; `14.17 MB` per strand (`29.8×` smaller than `422.49 MB` full checkpoint)

 | Translates each Architect plan into candidate OM-2 functions in parallel across four specialized strands while keeping the `126.66 MB` frozen base layers and embeddings 100% bit-identical

 |
| **Deterministic Judge** | `seed/out/omc` + Execution Oracle + `bench seen == 0`

 | Fail-closed compilation and zero-leakage pruning across `165` frozen benchmark tasks (`seen 6` unchanged across Rounds 0–3)

 | Compiles candidates, validates outputs against test cases, captures exact compiler diagnostics, and strips any AST collision with benchmark tasks

 |
| **Governance & Safety** | 4-Strand BFT Braid + Four-Wall RSI Gate

 | Enforces bit-exact `speval` and `spchaineval`, refuses tamper controls (`rc=60/61/62`), and executes `REJECT_OVERFIT_KEEP_P1` rollback on `held.tok` regression

 | Audits every candidate strand update and blocks corrupted, tampered, or overfitting packs from entering the live Merkle chain

 |

---

## 2. 4-Strand DNA Specialist Topology

Clipping four `14.17 MB` `OLLMSP01` layers onto the frozen looped core via live `spclip (MODE=1)` turns the Builder into a modular specialist ensemble. Partitioning harvested training traces across four dedicated strands prevents new problem families from overwriting older skills:

* **Strand 1 — Core Arithmetic & Control (`arith` / `branch`):** Anchors foundational expressions, conditionals, and integer/numeric logic where the `15.8M` looped core already achieves clean passes.


* **Strand 2 — Iteration, State & Aggregation (`fold`):** Specializes in loops, accumulators, and multi-step state transitions over sequences and structured inputs.


* **Strand 3 — Structural & Symbolic Transforms (`rewrite`):** Focuses on AST-style transformations, pattern matching, and clean termination (building on `P1_om2_rlvr_15m.sp`, which cut `rewrite noend` errors from `24` to `2`).


* **Strand 4 — Compiler & Logic Repair (`repair`):** Trains exclusively on `(broken code + omc error / failing test -> verified fix)` transitions to act as a dedicated recovery pass when Strands 1–3 miss on the first try.



---

## 3. Batched Execution Pipeline (Amortizing GB10 Overhead)

Because `gtrainf` flushes the OS page cache and forces `q36-35b` into a `43–72 s` cold read of its `~34.7 GB` checkpoint from SSD, the Architect and Builder never interleave prompt-by-prompt. Each cycle runs in four sequential stages:

1. **Stage 0 — Target Selection & Zero-Leakage Screen:** Generate or queue 100–250 synthetic tasks targeting unsolved logic families beyond the current `6 / 159` passes. Run every task specification through `bench seen == 0` up front so all `165` frozen benchmark tasks remain 100% unseen.


2. **Stage 1 — Single Cold-Boot Architect Batch (`q36-35b`):** Boot `q36-35b` once with a `90–120 s` readiness wait (clearing the earlier 40-second timeout). Generate structured algorithm specs for the entire batch in one continuous session, outputting step lists, edge-case invariants, and 3–5 concrete I/O assertions per task, then shut down `q36-35b` to reclaim unified memory and DRAM bandwidth.


3. **Stage 2 — 4-Strand Parallel Builder Sweep (`spclip`):** Load the frozen `loop` core with all four active `OLLMSP01` strands clipped via `spclip (MODE=1)`. For each Architect plan, sample $K = 4$ to $8$ OM-2 candidates per strand ($16$ to $32$ total candidates per task), leveraging `loop_r3`'s `96.2%` compile rate and `0 noend` discipline to explore multiple syntactic implementations cheaply.


4. **Stage 3 — Mechanical Verification & Multi-Strand Logging:** Run every candidate through `seed/out/omc` and the execution oracle. Record per-strand compilation status, exact `omc` error strings, execution pass/fail vectors, and concrete wrong outputs to drive automated fault attribution.



---

## 4. 4-Strand Fault Attribution & Recovery Matrix

Running all four strands against the same Architect plan turns failure diagnosis into a mechanical consensus check rather than guesswork:

| Verification Signature Across the 4 Strands | Diagnosed Fault | Automated Recovery & Harvest Action |
| --- | --- | --- |
| **1–3 strands pass execution; remaining strand(s) fail** | **Builder strand gap** (Architect plan is verified sound) | Harvest the winning OM-2 code as a gold trace; pair each failing strand's output and `omc` error/wrong output with the winning solution as a repair pair routed to Strand 4 and the failing domain strand

 |
| **All 4 strands fail `seed/out/omc` compilation** | **OM-2 idiom / syntax gap** | Route the best candidate + exact `omc` error string to Strand 4 (`repair`) for 1–2 repair turns; save any recovered `(broken + error -> fixed)` sequence

 |
| **All 4 strands compile cleanly, 0 pass, and all return the *same* wrong output** | **Architect logic flaw** (all four Builders faithfully implemented a buggy plan) | Flag the plan as defective and queue the task plus its failing test case for the next `q36-35b` batch instead of burning more Builder compute |
| **All 4 strands compile cleanly, 0 pass, with divergent wrong outputs** | **Underspecified plan or task complexity ceiling** | Re-queue for the next `q36-35b` batch with a stricter prompt requiring smaller helper sub-functions and explicit intermediate assertions |

---

## 5. Distillation, Anti-Forgetting & Four-Wall BFT Promotion

Verified tandem wins are distilled back into the `15.8M` system so the student learns to solve new tasks *without* calling `q36-35b` at inference time.

### Corpus Formatting & Volume Guardrails

* **Dual-View Trace Extraction:** For every verified win, write a primary direct-distillation sample `(Original Task -> Verified OM-2 Code)` with the Architect plan stripped out, plus a smaller alignment slice `(Architect Plan -> Verified OM-2 Code)` to sharpen future Builder sweeps.
* **Minimum Batch Floor (Eliminating the `P2` Failure Mode):** `P2_helix_repair_15m.sp` proved that updating a specialist on a tiny 16-window repair cache causes severe overfitting, degrading `held.tok` from `3.206` to `4.829`. Do not trigger a strand training job until a target strand accumulates a substantial, diverse batch of verified traces and repair pairs.


* **Arboris Anti-Forgetting Rehearsal:** Blend every strand or core update with the proven `20–32% repo-train.om` Arboris Anti-Forgetting Rehearsal ratio, NUL (`\x00`) EOS delimiters, and shuffled RLVR batches under `ollm-helix-gb10` Ascetic G6 (`XID_DELTA: 0`).



### Four-Wall RSI Gate & BFT Quorum Promotion

Before any newly trained `14.17 MB` strand is clipped permanently onto the Merkle chain, it must clear four non-negotiable gates:

1. **Wall 1 — Bit-Exact Integrity & Tamper Wall:** Confirm all `126.66 MB` of frozen base layers and embeddings remain 100% bit-identical, step-0 `growpro` and `speval`/`spchaineval` stay bit-exact, and all tamper controls are refused (`rc=60/61/62`).


2. **Wall 2 — Retention Wall (`held.tok`):** Run the full `2,475`-window `geval` on `held.tok`. If any strand drifts past the tight retention tolerance (matching the `P1` `+0.144 nats` ceiling rather than `P2`'s collapse), fire `REJECT_OVERFIT_KEEP_P1` immediately to roll back *only* the offending strand while keeping the healthy strands intact.


3. **Wall 3 — Strict Zero-Leakage Wall:** Audit the combined training corpus (`train.om` + harvested traces) via `bench score` to confirm `seen 6` remains unchanged with zero new benchmark overlap.


4. **Wall 4 — Benchmark & BFT Quorum Wall:** Run 16-core parallel CPU sampling across all `165` frozen benchmark tasks. Under the 4-strand BFT braid, a strand is promoted only if it improves or preserves ensemble pass rate without introducing regressions (`0 passcut`, `0 noend`); any faulty strand is quarantined independently.



---

## 6. Post-Cycle Scaling Decision Rule

Execute two full batched Architect–Builder cycles and evaluate the `165`-task benchmark alongside `held.tok`:

* **Continue Scaling Data & Strands (Capacity Sufficient):** If ensemble passes climb steadily above `6 / 159` while `held.tok` holds near `3.128 nats/tok`, the bottleneck was algorithmic exposure rather than parameter saturation. Keep the `15.8M` looped core frozen and continue rotating targeted `q36-35b` harvests into domain-specific `14.17 MB` strands.


* **Widen the Looped Core (Capacity Wall Reached):** If all four strands consistently fail to translate verified, finely decomposed Architect plans even at $K = 32$ samples—or if per-strand `held.tok` degrades as soon as new skills are added—the `15.8M` backbone has hit its representational ceiling. Use the existing `growpro` / checkpoint-growth path to step the looped core up (e.g., into the 50M–125M range, still practical for overnight GB10 windows) and re-attach this exact same 4-strand Architect–Builder factory on top of the larger core.
