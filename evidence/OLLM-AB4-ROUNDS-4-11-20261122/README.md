# Evidence: Omega LLM Architect-Builder campaign, Cycle 2 harvest and training rounds 4 to 11 (2026-11-22)

This bundle finishes the campaign that `evidence/OLLM-HELIX-CLOSED-LOOP-20261121/` records through
round 3. The agent that ran rounds 1 to 3 and the Cycle 2 sweep (Gemini 4 Neon through Antigravity,
session `129c679e`) stopped after launching the Cycle 2 sweep (saved campaign context in
`campaign-plan/`). Rounds 4 to 11, the `r0` baseline re-measurement, the pass-at-8 diagnostic and
the failed teacher rewording attempt were run by Claude Fable 5.2 (Claude Code, lane
`claude-agy-finish`) on the same DGX Spark with the same binaries, benchmark and measuring commands;
final packaging and verification after round 11 completed were finished by Gemini 4 Neon
(Antigravity).

`RESULTS.md` and `receipt.json` are generated directly from the raw logs by
`harness/make_receipt.py`. Where this file and a raw file differ, the raw file is authoritative.

## Verdict

**Diminishing returns reached on the frozen benchmark for this model and this data (15.8M looped
core, 1,400-step full-core fine-tuning at `lrmicro=350`, current generator family); held-out
forgetting mostly recovered and plateaued.** Eight post-round-3 training rounds (`r4` to `r11`)
were run and measured on the GB10; none was promoted (`loop_r3.ck` remains the benchmark champion;
this is a documented decision, not an automated promotion-gate binary run).

- **Frozen benchmark (one greedy sample per task, 159 scored tasks):** round 3 passes 6. Rounds 4
  to 11 pass 3, 5, 5, 5, 2, 2, 4 and 2. No round after round 3 matched or beat 6; among rounds 8 to
  11, none reached the 8 / 159 gain criterion registered beforehand in `campaign-plan/PLAN-B.md`
  (written after `r4..r7` scored 3–5, before `r0` and `r8..r11` ran).
- **Held-out loss on `held.tok` (2,475 windows):** the pre-campaign looped checkpoint (`r0`,
  `LOOP.md` step 6000, re-measured in `rounds/geval_loop_r0_ck6000.log`) scores **2.144**
  nats/token (`2,144,233` micro-nats; `LOOP.md` best step 4000 was `2.123075`). Rounds 1 to 3
  pushed `held.tok` up to **3.128** (forgetting). Widening the repository rehearsal draw recovers
  most of that forgetting — bringing `held.tok` back to **2.218** (`r6`), **2.237** (`r8`),
  **2.219** (`r10`) and **2.244** (`r11`), still +0.074 to +0.100 nats above `r0`. This is a
  **recovery of lost ground**, not a net gain over `r0`.
- **Pre-registered criteria (`campaign-plan/PLAN-B.md`, registered before `r8..r11`):**
  - Rehearsal ablation (`r9 - r8`): `+1.477` nats (`> 0.3` threshold) -> confirms **breadth of the
    rehearsal draw** is the cause of the held-out drift.
  - Benchmark gain (`>= 8 / 159` in `r8..r11`): **not met** (best is 4 / 159 in `r10`).
  - Held-out plateau (`|r11 - r10| < 0.05` and both within `0.15` of `r0`): **met** (`r11 - r10 =
    +0.025`, `r10 - r0 = +0.075`, `r11 - r0 = +0.100`).

## Results

Full generated table (with derived passes over mix, window ids, passing task ids and checkpoint
hashes) is in `RESULTS.md`. Summary:

| Round | Parent | What changed | Pass / 159 | `held.tok` loss | vs r0 | Teacher plan text in mix |
|---|---|---|---:|---:|---:|---|
| r0 | — | pre-campaign looped checkpoint (`ck6000.bin`), re-measured today | (not scored) | 2.144 | +0.000 | — |
| r3 | — | state at takeover (earlier agent's round 3) | 6 | 3.128 | +0.984 | — |
| r4 | `loop_r3.ck` | + breadth corpus + Cycle 2 traces (`c2align`, `c2direct`, `c2repair`), narrow rehearsal (163 docs, 29.3%) | 3 | 3.440 | +1.296 | yes (30 `c2align` records) |
| r5 | `loop_r3.ck` | continuation: round 3's exact mix (`r3_mix.tok`, sha256 `c830ff12...`) applied again | 5 | 3.744 | +1.600 | (r3 mix) |
| r6 | `loop_r3.ck` | + generator variants 6–9 (`c2direct` only), wide rehearsal (4,296 docs, 50.0%) | 5 | 2.218 | +0.074 | no |
| r7 | `loop_r6.ck` | round 6 task mix, wide rehearsal at 30.1% (1,798 docs) | 5 | 2.295 | +0.151 | no |
| r8 | `loop_r3.ck` | ablation: round 4 task sources and weights (5x task epochs), wide rehearsal at 50.0% (2,697 docs) | 2 | 2.237 | +0.093 | yes (30 `c2align` records) |
| r9 | `loop_r3.ck` | ablation: round 4 task sources and weights (5x task epochs), round 4's 163-doc slice replayed to 50.3% | 2 | 3.713 | +1.569 | yes (30 `c2align` records) |
| r10 | `loop_r6.ck` | round 6 configuration again, new shuffle seed (4,214 docs, 50.0%) | 4 | 2.219 | +0.075 | no |
| r11 | `loop_r10.ck` | round 6 configuration again, new shuffle seed (4,147 docs, 50.0%) | 2 | 2.244 | +0.100 | no |

Every trained round (`r4..r11`) is 1,400 `gtrainf` steps at `lrmicro=350` on the 15,833,472-parameter
looped core (`U 15833472` in `rounds/gpu_round_r*.out`), then the full 2,475-window `geval`, inside
one `spark-window` with a `spark-receipt`. Every scored row has `seen 6` unchanged and `passcut 0`
(`scores/`). Using `LOOP.md`'s `B=64, T=256`, 1,400 steps is `22,937,600` tokens (derived), giving
`14.34` passes over the mix in `r4`, `11.12` in `r5`, `1.21` in `r6`/`r10`/`r11`, `1.72` in `r7`,
`1.92` in `r8` and `2.02` in `r9` (`RESULTS.md`, `supplement/mix_tokens_r4_r7.txt`).

### GPU error counts across all windows opened by this work

All trained rounds (`r4..r11`) recorded Xid count `516` before and `516` after
(`rounds/gpu_round_r*.out`). Non-zero `nvrm_errors_delta` counts in `spark-receipts/` (non-Xid NVRM
kernel messages):

- `r4, r5, r6, r7, r9, r10, r11`: `nvrm_errors_delta = 0`.
- `r0` (`ollm-r0-baseline-geval`, `20261122T170839Z-2d95d9`): `nvrm_errors_delta = 3`.
- `r8` (`ollm-rlvr-r8-gb10`, `20261122T170915Z-717125`): `nvrm_errors_delta = 20`.
- `ollm-teacher-para-p1` (`20261122T161237Z-75759c`, closed ~2 min before `r7`): `nvrm_errors_delta = 37`.

`supplement/nvrm_dmesg_20261122.txt` records the dmesg excerpt captured at 11:11 local time (last
line 11:09:17 local, partway through `r8`). Every captured line is a non-Xid NVRM memory-allocation
failure/retry (`NV_ERR_NO_MEMORY`), GSP alloc failure, or `vaListDestroy` line; the remaining ~18
NVRM lines from `r8` after 11:09:17 were not captured.

## What the rounds show

1. **Repeating round 3's exact mix (`r5`) did not improve either metric.** Applying `r3_mix.tok`
   byte for byte (`c830ff12...`, `supplement/mix_tokens_r4_r7.txt`) from `loop_r3.ck` moved the
   benchmark from 6 to 5 and raised `held.tok` by `+0.616` nats (`3.128 -> 3.744`).
2. **Controlled ablation (`r8` vs `r9`) isolates rehearsal breadth as the cause of the held-out
   drift.** Both start from `loop_r3.ck`, use round 4's task sources and weights at 5x the task
   epochs (`epochs 10`, `rlvr_bytes 15,488,520` in both vs `epochs 2` in `r4`), and put rehearsal
   at 50% of the mix. Drawing widely from `repo-train.om` (`r8`: 2,697 distinct docs) yields
   `held.tok = 2.237`; replaying round 4's 163-doc slice to the same 50% share (`r9`) yields
   `held.tok = 3.713` (`+1.477` nats).
   - Caveat on `held.tok`: `diagnostics/held_disjoint.txt` verifies 0 shared filenames and 0
     byte-identical documents between `held.tok` and `repo-train.om`, but `train/omega-llm/docs/LOOP.md`
     notes that near-duplicates were not deduplicated, so `held.tok` loss is optimistic relative to
     strictly deduplicated text.
3. **Continuing the wide-rehearsal recipe (`r10`, `r11`) confirms a plateau.** Two consecutive
   rounds of the `r6` configuration with fresh shuffle seeds hold `held.tok` at `2.219` and `2.244`
   (`|r11 - r10| = 0.025 < 0.05`) while benchmark passes fall to 4 and 2.
4. **Disclosure: `q36-35b` Architect plan text entered `r4`, `r8` and `r9`.** `cycle2/align_c2.om.nul`
   (30 records, `source c2align`, weight 1) embeds `note ARCH_PLAN: {plan}` from live `q36-35b`
   Architect plans (`cycle2/run_stage2b_sweep.py` line 158), including leaked teacher reasoning.
   Those 30 records were trained on in `r4`, `r8` and `r9` (`rounds/r{4,8,9}_manifest.txt`). Rounds
   `r6`, `r7`, `r10` and `r11` used `c2direct` only (no `c2align`, no teacher text).
5. **Generator variants diagnostic (`diagnostics/saturation_eval.txt`).** On 24 windows each,
   `loop_r3.ck` scored 1.614 on the r3 RLVR mix and 1.600 on unseen idioms variants 6–9 (two
   different distributions, so not a strict memorization test). After `r6` and `r7` trained on
   variants 6–9, loss on those 24 windows fell to 1.532 and 1.492 — so the model did learn from the
   new generator outputs, even though adding 3,059 distinct records (`6,838 -> 9,897`) did not
   produce a frozen benchmark gain.
6. **Pass-at-8 diagnostic (`passk/`).** With 8 sampled answers per task at temperature 0.7, graded
   by `bench score`, `loop_r3.ck` and `loop_r6.ck` each solve 7 of 159 tasks in at least one sample.
   Across all greedy scores in this bundle, **9** distinct tasks pass at least once (`p-022 p-031
   r-004 r-011 r-025 u-012 u-013 w-004 w-026`); taking the union of all greedy scores and both
   pass-at-8 runs yields **11 of 159** (`+ u-006 u-016`), leaving 148 tasks unsolved across every
   checkpoint and sample here.

## Cycle 2 harvest (finished by the earlier agent, first used here)

`cycle2/c2_task281_summary.txt` holds the summary lines of its task log: 50 validated Architect
plans, 800 candidates (4 strands, 4 samples each, temperature 0.7), 778 compiled, 347 passed their
oracle, 29 of 50 tasks solved, 30 gold traces, 32 repair pairs, 21 tasks re-queued. The matrix,
attribution, re-queue list, NUL-delimited trace files (stored with `.om.nul` extension so data files
do not carry the `.om` source extension) and sweep script as left on the Spark are in `cycle2/`.

Two corrections to earlier descriptions, found while using this data:

- The breadth generator `seed/helix/ollm_factory/rlvr_breadth.om` (commit `9b182ab50`, "936
  verified zero-leakage functions") emits 936 records over its 9 variants, of which **490 are
  distinct** (`rounds/r4_manifest.txt`: `parsed 936 unique 490`).
- The Cycle 2 sweep prompts the builder with the task instruction only (`note {desc}\nfn solve
  {sig}`). The Architect's plan decides which tasks are swept and is written into `align_c2.om.nul`,
  but is not part of the builder's prompt (`cycle2/run_stage2b_sweep.py`, `eval_one_sample`).

## Teacher rewording attempt: FAIL, nothing used

One window (`20261122T161237Z-75759c`, `nvrm_errors_delta = 37`) booted `q36-35b` to reword the
instruction line of verified records while leaving code untouched. `teacher/teacher_p1.out` records
`asked=150`, `http_errors=2398`, `89` lines passing the mechanical filter (which rejected
`{"ascii": 1, "numbers": 36, "shape": 24}`). On reading `teacher/para_p1.om.pairs.tsv`, every one of
the 89 lines was the teacher answering the instruction instead of rewording it. **All 89 were
rejected and 0 teacher-reworded records entered any training mix.**

## What was not run

- GPU training of frozen-core `OLLMSP01` strands: NOT_RUN (`gtrainf` updates all layers). Rounds 4
  to 11 are full-core fine-tunes of the looped model.
- Architect Cycle 3 on the 21 re-queued tasks: NOT_RUN.
- The widened looped core of `campaign-plan/operator-plan-129c679e-step0.md`: NOT_RUN.

## Reproduction and pinned inputs

`harness/` holds the Python and POSIX shell scripts used for data preparation, execution and
measurement on the Spark. This bundle adds no `.om` source code (the three Cycle 2 NUL-delimited
corpus files in `cycle2/` are stored as `*.om.nul`).

- Binary and benchmark pins: `rounds/pins.sha256` (`loop_r3.ck`, `ollm`, `ollm-helix-gb10`, `omc`,
  `bench`, `tasks.om`, `expect.txt`, `held.tok`, merges file).
- Generator binary/source pins and `corpus 6..9` regeneration hashes: `supplement/generator_pins.txt`.
  `rlvr_factory`, `rlvr_idioms` and `rlvr_breadth` rebuilt byte-identical from repository source.
  **Disclosure on `rlvr_compositional`:** the existing Spark binary (`680f7f12...`) regenerates the
  trained `corpus 6..9` file (`d61ecade...`) byte for byte, but rebuilding from today's repository
  source (`b913f06a...`) produces a different binary (`72b45c70...`) whose output differs in 104 of
  3,348 compositional records (`corpus 1..5`: `221f77a2...` vs trained `7c77ab8e...`; `corpus 6..9`:
  `fe740e6c...` vs trained `d61ecade...`). The exact source revision that produced the Spark
  `rlvr_compositional` binary (`680f7f12...`) is unknown; `comp` entered every round `r4..r11` and
  `comp69` entered `r6, r7, r10, r11`.
- Mix token counts and sha256 (including `r5`'s byte copy of `data/r3_mix.tok`):
  `supplement/mix_tokens_r4_r7.txt` and `rounds/r{8..11}_manifest.txt`.
- Benchmark scoring inputs (`seen_corpus` and `answers` sha256 for every scored round and pass-at-8):
  `supplement/score_inputs.tsv`.
- Checkpoints stay on the Spark under `~/work/ollm-helix-rlvr-20261121/ckpt/`; their sha256 are in
  `RESULTS.md` and `receipt.json`.

## Limits

- One benchmark, 159 scored tasks, a single greedy sample each. Across `r3` and `r4..r11`, greedy
  scores varied between 2 and 6 passes.
- One recipe tested (15.8M looped core, 1,400-step full-core fine-tuning at `lrmicro=350`, current
  generator family); frozen-core strands, Architect Cycle 3 and a widened core were not run.
- Part of the compositional training data (`comp` in `r4..r11`, `comp69` in `r6, r7, r10, r11`) came
  from a Spark `rlvr_compositional` binary (`680f7f12...`) whose source revision is unknown (differs
  from current repo source in 104 of 3,348 records; `supplement/generator_pins.txt`).
- `diagnostics/saturation_eval.txt` compares two different distributions on 24 windows each and
  averages instruction and code tokens together.
- The GPU windows took the chip lock without the quiet lock, because these are training runs. No
  timing in this bundle is a speed claim.
