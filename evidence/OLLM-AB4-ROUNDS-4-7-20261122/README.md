# Evidence: Omega LLM Architect-Builder campaign, Cycle 2 harvest and training rounds 4 to 7 (2026-11-22)

This bundle finishes the campaign that `evidence/OLLM-HELIX-CLOSED-LOOP-20261121/` records through
round 3. The agent that ran rounds 1 to 3 and the Cycle 2 sweep (Gemini 4 Neon through Antigravity,
session `129c679e`) stopped at 2026-11-22 09:15 local time, after the operator had approved GPU
rounds until diminishing returns. Its last background job, the Cycle 2 sweep, finished after the
session had ended (the session's own records on the operator's Mac, not part of this bundle), and no
training had used its output. Rounds 4 to 7 below were run
by Claude Fable 5.2 (Claude Code) on the same DGX Spark, with the same binaries, benchmark and
measuring commands.

The round table below is copied from `RESULTS.md`, which `harness/make_receipt.py` generates
together with `receipt.json` from the raw logs. Every other figure names the file in this bundle
that it comes from. Where this file and a raw file differ, the raw file is right.

## Verdict

**Diminishing returns reached.** Rounds 4 to 7 were run and measured on the GB10; none was promoted.

- Frozen benchmark (one greedy sample per task, 159 scored tasks): round 3 passes 6. Rounds 4, 5, 6
  and 7 pass 3, 5, 5 and 5. No round after round 3 gained a pass. The campaign's stop rule was two
  consecutive rounds without a gain; there are four.
- Held-out loss on `held.tok` (2,475 windows): 3.128 at round 3, 2.218 at round 6. That is a real
  gain in general Omega modeling, and it came from changing how rehearsal text is drawn, not from
  more GPU time.
- `loop_r3.ck` stays the benchmark champion. `loop_r6.ck` has the best held-out loss but passes 5,
  one fewer than round 3, so under Wall 4 of the campaign's promotion gate ("improves or preserves
  ensemble pass rate") it is **not promoted**. Nothing was promoted in rounds 4 to 7.

## Results

See `RESULTS.md` for the generated table with window ids, task ids and checkpoint hashes.

| Round | What changed | Pass / 159 | `held.tok` loss |
|---|---|---:|---:|
| r3 | state at takeover | 6 | 3.128 |
| r4 | + breadth corpus + Cycle 2 traces, same narrow rehearsal as rounds 1 to 3 | 3 | 3.440 |
| r5 | control: round 3's own mix and recipe run again from `loop_r3.ck` | 5 | 3.744 |
| r6 | 9,897 distinct records, rehearsal widened to 50% of the mix | 5 | 2.218 |
| r7 | continued from r6, rehearsal at 30% of the mix | 5 | 2.295 |

Rounds 4 to 7: `seen 6` unchanged and `passcut 0` (`scores/`), `nvrm_errors_delta 0`
(`spark-receipts/`), Xid count 516 before and after (`rounds/gpu_round_r*.out`). Each of those rounds
is 1,400 `gtrainf` steps at learning rate 0.00035 on the 15,833,472-parameter looped core (`lrmicro=350`
and `U 15833472` in `rounds/gpu_round_r*.out`), then the full 2,475-window `geval`, inside one
`spark-window` with a `spark-receipt`. The round 3 row is the earlier agent's checkpoint: its
held-out figure is from its own log (`rounds/geval_loop_r3.log`) and its benchmark figure is a
re-score with the current sampler (`scores/score_r3ctl.txt`), which reproduced the recorded 6.

## What the rounds show

1. **Round 4 regressed** (3 passes, held-out loss up 0.313). Under the gate's retention wall it was
   rejected and `loop_r3.ck` kept.
2. **The control (round 5) shows the recipe itself overfits when repeated.** The same data and
   settings that produced round 3, applied once more, lost one pass and raised held-out loss by
   0.616. So a change of one or two passes between rounds is inside the noise of retraining, and the
   rise in held-out loss is not caused by the new data.
3. **The cause was the rehearsal slice.** Rounds 1 to 5 mixed in a small slice of
   `repo-train.om` (round 4: 163 documents, 1,281,698 bytes, out of 29,620,863) and replayed it for
   the whole round. Round 6 drew 4,296 documents (24,196,590 bytes) so that each repository document
   is seen about once. Held-out loss fell from 3.128 to 2.218. `diagnostics/held_disjoint.txt`
   checks that this is not leakage: 0 file names shared between the held-out and training lists, 0
   held-out documents byte-identical to a training document.
4. **The generated task data is saturated.** `diagnostics/saturation_eval.txt`: `loop_r3.ck` has nearly
   the same loss on records it trained on (1.614) as on generator variants it had never seen (1.600).
   More output from the same generators carries no new information. Rounds 6 and 7 used 3,059
   more distinct records than round 4 (6,838 to 9,897, `audit_records` in `rounds/r4_manifest.txt` and
   `rounds/r6_manifest.txt`) and the benchmark did not move.
5. **Extra tries do not unlock more tasks.** `passk/`: with 8 sampled answers per task at
   temperature 0.7, graded by the same `bench score`, `loop_r3.ck` and `loop_r6.ck` each solve 7 of
   159 tasks in at least one sample. This diagnostic was never a training source and is not the
   headline score. It matters because the campaign's method (harvest the model's own verified wins)
   has nothing to harvest for the other 152 tasks.

## Cycle 2 harvest (finished by the earlier agent, first used here)

`cycle2/c2_task281_summary.txt` holds the summary lines of its task log: 50 validated Architect
plans, 800 candidates (4 strands, 4 samples each, temperature 0.7), 778 compiled, 347 passed their
oracle, 29 of 50 tasks solved, 30 gold traces, 32 repair pairs, 21 tasks re-queued. The matrix,
attribution, re-queue list, traces and the sweep script as left on the Spark are in `cycle2/`.

Two corrections to earlier descriptions, found while using this data:

- The breadth generator `seed/helix/ollm_factory/rlvr_breadth.om` (commit `9b182ab50`, "936
  verified zero-leakage functions") emits 936 records over its 9 variants, of which **490 are
  distinct** (`rounds/r4_manifest.txt`: `parsed 936 unique 490`).
- The Cycle 2 sweep prompts the builder with the task instruction only. The Architect's plan decides
  which tasks are swept and is written into the alignment view, but is not part of the builder's
  prompt (`cycle2/run_stage2b_sweep.py`, `eval_one_sample`).

## Teacher rewording attempt: FAIL, nothing used

One window (`20261122T161237Z-75759c`) booted the `q36-35b` teacher to reword the instruction line
of verified records, leaving the code untouched. `teacher/teacher_p1.out`: 150 requests answered in
720 s, 2,398 HTTP errors, 89 lines passed the mechanical filter. On reading them
(`teacher/para_p1.om.pairs.tsv`) every one was the teacher answering the instruction instead of
rewording it. The filter in `harness/teacher_paraphrase.py` only compared the numbers in the two
lines, which is not enough. **All 89 were rejected and no teacher text entered any training mix.**

## What was not run

- GPU training of frozen-core `OLLMSP01` strands: NOT_RUN (`gtrainf` still updates all layers, as
  the earlier bundle records). Rounds 4 to 7 are full-core fine-tunes of the looped model.
- Architect Cycle 3 on the 21 re-queued tasks: NOT_RUN.
- The widened looped core of the campaign plan's section 6: NOT_RUN. The findings above say width
  alone would not be enough: the task data would have to change first.

## Reproduction

`harness/` holds the scripts exactly as run. They are Python and POSIX shell used for data
preparation and measurement on the Spark; nothing in them is a structural part of Omega, and this
bundle adds no `.om` source.

```sh
python3 build_mix.py N OUT_DIR REPO_PCT EPOCHS name=path:weight ...   # leakage-checked mix + manifest
sh gpu_round.sh N PREV.ck 1400 350 18                                 # tune, window, gtrainf, geval
sh score_round.sh TAG CK CORPUS                                       # 165 greedy samples + bench score
sh passk.sh TAG CK 8 700 CORPUS                                       # diagnostic only
python3 make_receipt.py OUT_DIR                                       # receipt.json and RESULTS.md
```

Inputs and tools are pinned in `rounds/pins.sha256` (`loop_r3.ck`, `ollm`, `ollm-helix-gb10`, `omc`,
`bench`, `tasks.om`, `expect.txt`, `held.tok`, the merges file). Each mix's sources, counts and
sha256 are in `rounds/r{4,6,7}_manifest.txt`; round 5 reuses `r3_mix.tok`. Checkpoints are on the
Spark under `~/work/ollm-helix-rlvr-20261121/ckpt/` and are not in this repository; their sha256 are
in `RESULTS.md`.

## Limits

- One benchmark, 159 scored tasks, a single greedy sample each. At 3 to 6 passes the score moves by
  one or two between retrainings of the same recipe (round 5), so only a larger change would count
  as a gain.
- `diagnostics/saturation_eval.txt` averages loss over instruction and code tokens together, on 24
  windows. It supports "no memorization gap", not a statement about code tokens alone.
- The windows took the chip lock without the quiet lock, because these are training runs. No timing
  in this bundle is a speed claim.
