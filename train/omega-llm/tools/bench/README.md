# Omega coding benchmark

This benchmark measures whether Omega LLM can write an Omega function it has not seen. It has 165 tasks, one behaviour each, and gives the model no help: one sample at temperature 0, no filtering by examples, and the model has to end its own function.

The earlier coding panels reworded a few trained templates, so their scores measured recall. Here no two tasks compute the same thing, and a task whose reference occurs in a training corpus is counted apart.

## Files

| File | What it is |
| --- | --- |
| `bench.om` | The tool, in seeded Omega. Its head lists every command, verdict and exit code. |
| `tasks.om` | The shared inputs and the 165 tasks: an instruction and a reference function each. It is Omega source. |
| `expect.txt` | The frozen result of every reference on every shared input, one row per task. |

A score is comparable only with scores from the same `tasks.om` and `expect.txt`.

## The tasks

| Shape | Signature after `fn solve` | Tasks | Cases per task |
| --- | --- | ---: | ---: |
| one argument | `a ulong to ulong` | 35 | 44 |
| two arguments | `a ulong b ulong to ulong` | 34 | 33 |
| three arguments | `a ulong b ulong c ulong to ulong` | 32 | 30 |
| array, read | `a view ulong 8 n ulong to ulong` | 32 | 54 |
| array, changed in place | `a edit ulong 8 n ulong to void` | 32 | 54 |

The prompt is the instruction as a `note` line followed by the `fn solve` line, the format of the training records. The answer is whatever the model writes after it.

Every task of a shape runs on the same inputs. `bench check` fails when two tasks of a shape agree on all of them, so the cases tell every task from every other. The closest pair differs in 2 cases.

## Build and run

On AArch64 Linux, from the repository root:

```sh
seed/out/omc < train/omega-llm/tools/bench/bench.om > bench && chmod +x bench
d=train/omega-llm/tools/bench
mkdir work
./bench check $d/tasks.om $d/expect.txt seed/out/omc work     # CHECK PASS tasks 165 inputs 122 minsep 2
./bench sample $d/tasks.om work ./ollm sample CK MERGES        # work/answer-ID, one per task
./bench score $d/tasks.om $d/expect.txt seed/out/omc work [CORPUS]
```

`sample` runs `OLLM CMD CK 42 128 0 PROMPT [MERGES]` once per task; leave MERGES out for a byte checkpoint. On the GB10 use `./ollm-gb10 gsample` inside an authorized Spark window. To sample some other way, write the prompts with `./bench prompts $d/tasks.om work` and put each answer in `work/answer-ID`.

`score` prints one `R ID FAMILY VERDICT` line per task, one `F` line per family and a final line:

```
SCORE tasks 165 pass 0 passcut 0 seen 0
```

| Verdict | Meaning |
| --- | --- |
| `pass` | The answer is exactly one function body and every case holds. Only this counts. |
| `passcut` | The body passes, but the model kept writing after it. |
| `wrong` | A case fails, the program traps, or it runs out of CPU time. |
| `nocompile` | The compiler refuses the function. |
| `noend` | The answer never closes the function. |
| `refused` | The body says `exit` or `trap`, which could fake a result. |
| `missing` | There is no answer file. |
| `timeout` | The compile or the run passed its deadline. |
| `seen` | The task's reference occurs in CORPUS, so it measures recall. Left out of the totals. |

Give `score` the training text as CORPUS to exclude tasks the model was trained on. A reference counts as seen when a function in the corpus has the same text after its names are renamed. `./bench seen $d/tasks.om CORPUS` lists them without scoring.

Candidate programs run under `execpure`: no files, no processes, a CPU and a memory ceiling. If that sandbox is not available the run stops with exit 70 instead of grading.

## What has been checked

Checked on AArch64 Linux in a virtual machine, with `seed/out/omc` `708fdc0f…`, on 2026-11-21:

- `bench check` passes on the committed files. It fails on an `expect.txt` with one changed value, and on a task file with a duplicated behaviour (`SAME_BEHAVIOUR`).
- The table equals an independent calculation of all 165 tasks written from the instructions in another language. That comparison found nothing; the duplicate check found one pair of tasks that were the same function, and one of them was replaced.
- Scoring every reference as its own answer gives 165 of 165. Giving every task the answer of the next task of its shape gives 0 of 165.
- No task is seen in the 1,440-record contrast training corpus (`tools/contrast/contrast.om`).

## Scores

Scores of this task set (165 tasks; `tasks.om` and `expect.txt` as committed on 2026-11-21):

| Date | Model | Corpus given to `score` | Pass | Seen, set apart |
| --- | --- | --- | ---: | ---: |
| 2026-11-21 | 8 layers, 15.8M parameters, 6,000 steps on this repository's Omega source | that training text | 0 of 159 | 6 |
| 2026-11-21 | the same with a looped core (16 layer applications) | that training text | 0 of 159 | 6 |
| 2026-11-21 | 16 layers, 30.0M parameters, the same training | that training text | 0 of 159 | 6 |

All were sampled with CPU `sample`; the looped model's answers sampled on the GB10 with `gsample` were byte-identical. The run is described in [the looped-core notes](../../docs/LOOP.md). Six tasks have their reference function somewhere in this repository's Omega source (`u-007`, `u-009`, `u-030`, `p-004`, `p-006`, `t-003`), so a model trained on that source is scored on the other 159.

## Changing the tasks

Add the task to `tasks.om`, regenerate the table with `./bench table $d/tasks.om seed/out/omc work > $d/expect.txt`, and run `check`. A changed input line changes every row of its shapes, so earlier scores stop being comparable; say so where the scores are kept.
