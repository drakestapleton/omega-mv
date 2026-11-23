# OmegaLLM synthesizer repair and eight-query rerun

The normal comparison completed all 320 decisions on Spark CPU with zero component errors. Each method answered the same 80 tasks and used exactly eight reference queries per task. The preceding diagnostic recorded 17 errors across the four methods.

Adaptive selection remains experimental. All four methods gave 19 wrong branch answers. The protocol requires a reduction. All four methods used the previously published frozen tasks, which had already been scored during the first run's diagnostic continuation.

## What changed

The previous synthesizer stopped with exit 104 while traversing 4,140 admitted nodes in a loop capped at 4,096. Both search phases now iterate over their actual admitted ranges and stop when the bounded pool fills. At depth three and beyond, a commutative operation also considers earlier-level partners whose reversed pair has no subsequent turn. The node arena still holds 32,768 entries.

On the exact eight-row input that stopped the original run, the repaired native solver emitted a branch program computing the smaller argument. The seed compiler built it and all eight supplied rows passed. All four methods still answered `eval-equal-offset-4` incorrectly on the independent final inputs. For example, the adaptive program returned 14 for arguments 18 and 14, where the reference returned 32.

## Frozen evaluation

| Method | Correct | Wrong | Abstained | Errors | Wrong branches | Queries per task | Median selection seconds | Cumulative selection seconds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| CLI, original sketches | 19 | 23 | 38 | 0 | 19 | 8 | 0.095 | 3763.6 |
| CLI, both rewrite additions | 19 | 23 | 38 | 0 | 19 | 8 | 0.137 | 4316.7 |
| Candidate selection, fixed inputs | 26 | 20 | 34 | 0 | 19 | 8 | 0.022 | 5.0 |
| Candidate selection, adaptive inputs | 26 | 20 | 34 | 0 | 19 | 8 | 0.069 | 9.0 |

Times include selecting the program and querying the reference. Cumulative seconds sum overlapping task times across eight workers. Final scoring is timed separately. [Per-task results and timings](tasks.4f8c32b525cd364928bc411c99cb57091f93be0470aa97a9a2e2376abd48554b.csv)

The protocol compares adaptive selection against the CLI with the original sketches. Compared with fixed candidate selection, the adaptive method used a different set of inputs on 17 tasks and selected a different program on eight. All 80 final grades matched task by task. Candidate selection gained five arithmetic tasks and two rewrite tasks over the CLI.

| Registered criterion | CLI | Adaptive | Met |
|---|---:|---:|---|
| More correct answers | 19 | 26 | Yes |
| At most as many wrong answers | 23 | 20 | Yes |
| Fewer wrong branch answers | 19 | 19 | No |
| At most eight queries per task | 8 | 8 | Yes |

| Group | Original CLI | CLI with rewrites | Fixed candidates | Adaptive candidates |
|---|---:|---:|---:|---:|
| branch | 1 / 19 / 0 | 1 / 19 / 0 | 1 / 19 / 0 | 1 / 19 / 0 |
| arithmetic | 15 / 3 / 2 | 15 / 3 / 2 | 20 / 0 / 0 | 20 / 0 / 0 |
| read | 1 / 1 / 18 | 1 / 1 / 18 | 1 / 1 / 18 | 1 / 1 / 18 |
| rewrite | 2 / 0 / 18 | 2 / 0 / 18 | 4 / 0 / 16 | 4 / 0 / 16 |

Each group contains 20 tasks. Entries give correct, wrong and abstained counts.

## Tasks that previously raised errors

| Method | Prior errors | Now correct | Now wrong | Now abstained | Still errors |
|---|---:|---:|---:|---:|---:|
| CLI, original sketches | 3 | 1 | 2 | 0 | 0 |
| CLI, both rewrite additions | 3 | 1 | 2 | 0 | 0 |
| Candidate selection, fixed inputs | 7 | 2 | 5 | 0 | 0 |
| Candidate selection, adaptive inputs | 4 | 1 | 3 | 0 | 0 |

## Historical replay and rewrite measurements

| Historical condition | Previous passes | Current passes | Newly passing | Previously passing lost |
|---|---:|---:|---|---|
| Eight supplied examples | 106/165 | 106/165 | None | None |
| Prompt only | 78/165 | 78/165 | None | None |

On the 24 development rewrite tasks, the repaired baseline CLI returned 13 correct programs, 0 wrong programs and 11 abstentions. Its two most frequently missed families were `adjacent-add` and `anchor-add`.

The two development rewrite patterns were also measured again on all 24 rewrite tasks. The sketcher solved 6 with both disabled, 10 with only the scaled next-item update, 10 with only the scaled first-item update and 14 with both enabled. Every emitted program had the same bytes and verdict as in the original ablation. Each configuration produced zero wrong programs.

## Reproduction and controls

Tested solver source `a5ec28b33a5950bbd98fa30f19945cb47f9932a9`. The previous signed main was `a4aec7ed5cc8a37f3bea9f851a19f2473c9183b4`. All four methods kept the original task manifest, split, private model fingerprint and eight-worker setting. In each method, the only executable or model fingerprint that changed from the first experiment was `om_synth`. All four methods sealed every selection before final scoring opened. The receipt includes every selected body, answer, query, trace, counterexample, timing and build fingerprint. [Comparison receipt](comparison.ea5646c2e30039d0ccdb9eefa4c9928525731e32af21f25ddfd6baf92fb75516.json) · [Earlier interruption](../OMEGALLM-SELECTION-20261123/REPORT.md) · [Build and rerun instructions](../../train/omega-llm/tools/combined/experiment/README.md)

The native gate compiles and runs the exact failed input and a constructed wide-frontier case. The public controls check the original exit 104 and reject three deliberately incorrect search implementations with distinct return codes. The Lean file proves coverage of the frozen index range, the commutative ordering rule and monotone pool closure in a model of the search. The native tests exercise the implementation. [Mutation controls](controls.py) · [Lean model](Frontier.lean)

A separate deterministic diagnostic supplied 36 scalar tasks, six examples each, and eight additional scoring inputs. The previous synthesizer trapped on 12 tasks. The repaired synthesizer emitted 35 programs and exhausted its pool normally on one. It retained all 24 previously emitted programs byte for byte and passed all eight scoring inputs on 24 tasks, up from 20. Every emitted program in both builds fit all six supplied examples. These task results are supplemental to the 80-task comparison. The public replay regenerates both engine outputs and checks their grades using the seeded runner. [Sample replay](replay_samples.py)

From an AArch64 Linux checkout with the public audit kit in `KIT`, replay the separate diagnostic with the following commands.

```sh
E=evidence/OMEGALLM-FRONTIER-20261123
D=$(mktemp -d)
git show a4aec7ed5cc8a37f3bea9f851a19f2473c9183b4:seed/helix/ollm_factory/om_synth.om > "$D/previous.om"
"$KIT/omc" < "$D/previous.om" > "$D/previous"
chmod 700 "$D/previous"
python3 "$E/replay_samples.py" "$E"/comparison.*.json "$D/previous" "$KIT"
python3 "$E/controls.py"
lean +leanprover/lean4:v4.35.0 "$E/Frontier.lean"
```
