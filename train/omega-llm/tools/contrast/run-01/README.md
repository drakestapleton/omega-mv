# Spark GB10 contrast experiment

The two training arms started from the same previously mixed checkpoint and ran 800 steps at a learning rate of 0.000350. The control reused the old corpus. The treatment shuffled the old corpus with 1,440 contrast records. The average gave the two sets of trained weights equal weight. The coefficient and test panels were fixed before inspection of the treatment scores.

| Generator | Fresh functions correct | Earlier functions correct |
|---|---:|---:|
| Parent | 5/24 | 28/79 |
| Control | 7/24 | 30/79 |
| Treatment | 5/24 | 30/79 |
| Average | 6/24 | 31/79 |
| First compilable body from parent, control, treatment | 8/24 | 29/79 |
| First body that passed one supplied example in the same order | 9/24 | Untested |

The example-checked chain returned nine functions and abstained on 15. All nine passed their hidden inputs. Seven of the eight fresh composition prompts produced a compilable answer in the three-checkpoint chain. None passed the hidden tests. Single-checkpoint median warm latency on four fixed prompts with three measured repetitions was 166.8 ms for the parent, 163.1 ms for control, 147.9 ms for treatment and 150.6 ms for the average. Three live cold chain calls took 2.27 s for first-checkpoint acceptance, 6.70 s for third-checkpoint acceptance and 7.04 s for abstention.

The archived panels and generations allow independent behavior replay without model weights. Each generation records a body and a grade of 0 for no compilable function, 1 for compiled but incorrect or 2 for correct on every hidden case. The fresh scalar checks cover eight pairs and the array checks cover twelve cases across two arrays. The distinct caller example is visible only to the selector. [Full scores](scores.tsv) include the earlier single-checkpoint and chain comparisons. Identifiers `starting` and `focused` refer to the two members of the previous compile fallback, and `parent` refers to the mixed checkpoint used to start this experiment.

[Artifact digests](artifacts.sha256) identify the original experiment inputs, trained checkpoints and tokenizer held outside Git. The saved experiment directory is named `ollm-contrast-vR2SLMbY` and the parent directory for prerequisite artifacts is `ollm-native-coding-4esuIP3a`.
