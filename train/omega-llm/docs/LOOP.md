# Looped core

A looped model runs some of its layers more than once with the same weights. Depth then costs time and activation memory, not parameters.

The loop is a property of the checkpoint. Training, evaluation, sampling and serving read it from the file, on the CPU and on the GB10; nothing else changes on the command line.

## Shape

`L` stays the number of parameter layers. Three more numbers describe the loop:

| Number | Meaning |
| --- | --- |
| `LP` | Layers before the core (the prelude), run once. |
| `LC` | Layers in the core, starting at layer `LP`. |
| `NP` | How many times the core runs. |

The `L - LP - LC` layers after the core (the coda) run once. A sequence passes `L + LC (NP - 1)` layer applications.

With `L` 8, `LP` 2, `LC` 4 and `NP` 3 the model applies layers 0 1, then 2 3 4 5 three times, then 6 7: 16 applications with the parameters of 8 layers.

Each pass feeds the next: the core's output is its next input. This is the plain loop. It has no learned messages between passes and no exit gate.

## Commands

```sh
ollm init CK V T D H F L B SEED TOTAL LRMICRO G LP LC NP
```

- `NP` 1 means no loop and writes the same bytes as `init` without the three numbers. `NP` 0 is exit 2.
- A core that is empty or does not fit in the `L` layers is exit 12. So is a loop whose activations or attention rows do not fit the pools: at V 4096, T 256, D 384, H 12, F 1536 the pools hold 16 applications, the same as a 16-layer model.
- `train`, `eval`, `sample`, `grad`, `gcheck`, `tune`, `kvcmp` and `serve` run a looped checkpoint. So do the GB10 commands of `ollm-gb10` (`gtrain`, `gtrainf`, `geval`, `gcmp`, `gcmp2`, `gacmp`, `gprof`, `gdiag`, `gsample`, `gserve`, `gscmp`, `gdbench` and the BF16 commands).
- `grow` and the specialist commands refuse one with exit 17. They apply each layer once and would compute a different model.

## Checkpoint

A looped model is saved as `OLLMCK03`. Its header is 144 bytes: the `OLLMCK02` fields, then `LP`, `LC` and `NP` at bytes 112, 120 and 128, then the payload FNV-1a 64 at byte 136. The payload is unchanged: parameters, then both Adam moments, 24 bytes per parameter.

A model without a loop is still written as `OLLMCK01` or `OLLMCK02`, byte for byte as before. A `OLLMCK03` file with `NP` below 2 is refused (exit 12).

## How it is built

The layer index used to choose both a layer's parameters and its activations. It now chooses the activations only; `olp` in `native/model.om` maps a layer application to its parameter layer.

- Activations, attention probabilities and the decode's row cache are kept per application, so the cached decode works unchanged.
- Every gradient write adds, so a core weight's gradient is the sum over its passes with no new backward code.
- The output projections are initialised at 1/sqrt(2 × applications) instead of 1/sqrt(2 L).

The GB10 path (`native/gpu/gg.om`) follows the same split. Its arena holds one activation block per application, so memory grows with the applications; the weights, the Adam moments and the gradient stay one per parameter layer. Every weight-gradient launch already added into the gradient buffer, which is zeroed once per step, so a core's gradient is the sum over its passes there too. No kernel changed: the emitted code image is byte-identical to the one before the change.

## What has been checked on the CPU

All on AArch64 Linux in a virtual machine, CPU only, with toy shapes (V 256 or 300, T 16, D 16), on 2026-11-21.

| Check | Result |
| --- | --- |
| Models without a loop: 19 commands and 4 checkpoints against the binary from before the change | Same output and checkpoint bytes (`kvcmp` apart from its timings) |
| `init` with `NP` 1 against `init` without loop numbers | Same file |
| `gcheck` on a looped checkpoint, at step 0 and after 12 steps | Passes (largest relative error 6.7e-4 against a tolerance of 1e-3) |
| Mutant lp (a core weight keeps only its first pass's gradient; `model.om` `OMUTLP`) | `gcheck` exits 40 |
| Forward against an unrolled twin: a model without a loop holding one copy of the weights per application | Same loss bits, same sampled bytes |
| Gradient against the twin's, with the copies summed | Largest relative difference 6e-13 |
| Training 0→20 in one run, in two runs, and with 2 worker processes | Same checkpoint |
| `kvcmp` (cached decode against the full forward) on a looped checkpoint | 0 differing logits; mutant i exits 43 |
| Small bank capacities, so core layers and activations cross into the second banks | Same loss, gradient file and trained checkpoint |
| `serve` with a looped checkpoint | Served text equals `sample` for the same seed |
| Refusals | Exit 12, 2 and 17 as listed above; a flipped payload bit is exit 14 |

The twin is the independent check of the loop's meaning: it is built outside `ollm` by copying parameter blocks, and it shares no code with the loop.

## What has been checked on the GB10

On the DGX Spark's GB10 on 2026-11-21, in two `spark-window`s opened `--gb10 shared --quiet none` (`20261121T161721Z-92fb64`, `20261121T162300Z-dbd0bd`). The expectations were written before each window. The binary is the `ollm_gb10` row built by `seed/out/omc` `708fdc0f…` (sha256 `3dd4aad2…`). Small shape: V 256, T 32, D 64, H 2, F 128, B 4, `L` 4 with `LP` 1, `LC` 2, `NP` 3 (8 applications). Large shape: V 4096, T 256, D 384, H 12, F 1536, `L` 8 with `LP` 2, `LC` 4, `NP` 3 (16 applications, 15,833,472 parameters), B 64, or B 8 where the CPU reference gradient is needed.

| Check | Result |
| --- | --- |
| Emitted kernel code image (`tests/gpu-dump.om`, host only) at the small and the large dims, before and after the change | Byte-identical |
| Model without a loop, small: `gcmp2` with the binary from before the change and with the new one | `GCMP2 PASS` twice; same `GC2` line apart from its time field |
| Model without a loop, large (rung 7's start checkpoint `fc8835fe…`): `geval` at step 0 | `E 0 2243 8398671`, the rung-7 receipt's value |
| The same, `gtrainf` 0→250 with the old and the new binary | Byte-identical checkpoints, equal to rung 7's `1ab162bf…`; `geval` prints rung 7's `E 250 2243 2773849` |
| Looped, small: chip gradient against the CPU's (`gcmp`, `gcmp2`) | `GCMP PASS`, `GCMP2 PASS` (relative error 1.06e-7 against a bound of 7.63e-6) |
| Mutant lg (the chip skips the `w2` gradient of repeated applications; `gg.om` `OMUTLG`), small | `gcmp` exits 45, `gcmp2` exits 47; on the model without a loop it passes with the product's line |
| Looped, small: chip Adam against the CPU's (`gacmp`) | `GACMP PASS` |
| Looped, small: `geval` against CPU `eval`, before and after 34 `gtrainf` steps | The same E line both times |
| Looped, small: `gtrainf` twice from one file; `gtrain` (CPU Adam) beside it | Byte-identical checkpoints; the same T lines |
| Looped, large (B 8): `gcmp2` | `GCMP2 PASS` (relative error 7.9e-7 under the chip's ReLU mask, against a bound of 1.22e-4); mutant lg exits 47 |
| Looped, large: `gacmp` | `GACMP PASS` |
| Looped, large: `geval` of 16 windows against CPU `eval` | The same E line (`E 0 16 8380244 3107895`) |
| Looped, large: `gtrainf` 0→250 on the rung-7 data | 2.852559 nats held out, from 8.38 (0.48 s per step, shared machine) |
| Looped, large: chip decode against the CPU forward (`gscmp`, 6 steps) | Largest logit difference 8.5e-6 (limit 2e-3) |
| A variant whose chip decode runs only the first 8 of the 16 applications | `gscmp` exits 40 (difference 5.38) |
| Looped, large: the per-token decode against the full forward (`gdbench` mode 2) | 0 differing logits, bit for bit |
| Looped, large: `gsample` against CPU `sample`, 24 tokens at temperature 0 | The same text |
| Looped, large: BF16 (`gbcmp`: every BF16 GEMM of a step against a host reference; `gdbench` mode 8) | `GBCMP PASS` (259 GEMMs, 0 bad); decode within 0.0143 of f32 (limit 0.25) |

Two things these checks do not cover. `gbcmp` ends with exit 84 on the small shape, with and without a loop and with the binary from before the change, so BF16 has only been run at the large shape. `gbcmp2`'s step bound grows with the applications and is 1.28 at 16 of them, too loose to catch a wrong gradient: BF16 training of a looped model has no gradient check with teeth.

The windows held the chip lock shared and no quiet lock, so every time above is from a shared machine.

## Looped against unlooped on Omega source

Trained on the GB10 with `gtrainf` (f32) on 2026-11-21, with the binary of the checks above, in windows opened `--gb10 shared --quiet none`: nine for base and loop, seven for deep, one for the final checks. The data, the arms and what would be claimed were written down before the first window; the deep arm was added to that record when only the first base result was known. One seed.

**Data.** Every tracked `.om` file of this repository at `f1f782afe`, except `train/omega-llm/tools/bench/`, with exact duplicate files dropped: 5,539 files. One file in twenty (by a checksum of its path) is held out. The training text is the other 5,262 files plus the 1,440 instruction-and-function records of `tools/contrast/contrast.om`: 29,808,159 bytes, 12,149,245 tokens under a 4096-token tokenizer fitted on it. The held-out text is 277 files, 633,611 tokens, 2,475 windows of 256. Near-duplicate files (vendored copies, test corpora) were not removed, so the held-out loss is optimistic for every arm alike.

**Arms.** V 4096, T 256, D 384, H 12, F 1536, B 64, seed 1, learning rate 0.003, 6,000 steps (8.09 passes over the training tokens):

| Arm | `init` tail | Layers | Applications | Parameters |
| --- | --- | ---: | ---: | ---: |
| base | `8 64 1 6000 3000 16` | 8 | 8 | 15,833,472 |
| loop | `8 64 1 6000 3000 16 2 4 3` | 8 | 16 | 15,833,472 |
| deep | `16 64 1 6000 3000 16` | 16 | 16 | 29,995,392 |

Loop against base is the comparison at equal parameters; loop against deep is the comparison at equal compute.

**Held-out loss** (chip `geval`, nats per token, all 2,475 windows):

| Step | base | loop | deep |
| ---: | ---: | ---: | ---: |
| 250 | 3.934575 | 4.066976 | 4.043863 |
| 1000 | 2.880189 | 2.892167 | 3.001488 |
| 2000 | 2.356329 | 2.309174 | 2.372067 |
| 3000 | 2.233483 | 2.193294 | 2.207980 |
| 4000 | 2.138132 | 2.123075 | 2.170525 |
| 5000 | 2.126762 | 2.125378 | 2.154437 |
| 6000 | 2.152378 | 2.144233 | 2.209630 |

Against base: at step 6000 the looped model is 0.38% below it. The rule written beforehand calls a gap under 1% no measured difference, and one seed cannot tell it from noise. The looped model was ahead by 2.0% at step 2000 and 1.8% at step 3000.

Against deep: the looped model is 2.96% below it at step 6000, and 1.46% below it when each arm is taken at its best stop (2.123075 at step 4000 against 2.154437 at step 5000). The rule written beforehand was that sharing weights cost nothing if the looped model ended no more than 1% above the 16-layer one; it ended below it.

No arm improves after step 5000 and every arm is worse at step 6000, the largest model most: the batch loss at step 6000 is about 1.18 for base and loop and 1.08 for deep, against 2.14 to 2.21 held out. The corpus is too small for these models, and the 16-layer model loses because it fits the training text hardest. That is a result about this corpus, not evidence that shared weights match real depth when data is plentiful.

Wall time per step on a shared machine: base 0.246 s, loop 0.452 s, deep 0.466 s (66,600, 36,300 and 35,200 tokens per second). The loop costs 1.84 times base and about the same as deep.

**Coding benchmark** (`tools/bench/`, step-6000 checkpoints, CPU `sample`, one answer per task at temperature 0, training text given as the corpus):

| Arm | Pass | Wrong result | Does not compile | Never ends the function | Refused | Seen in the corpus, set apart |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| base | 0 of 159 | 119 | 5 | 33 | 2 | 6 |
| loop | 0 of 159 | 123 | 36 | 0 | 0 | 6 |
| deep | 0 of 159 | 134 | 15 | 10 | 0 | 6 |

No model solves a task it has not seen. Most answers are well-formed Omega that ends its own function and computes something else: asked for the argument squared plus one, the base model returns the argument plus one. Neither the loop nor real depth changes that. Six tasks have their reference function somewhere in the repository's source, so they are set apart and not scored.

The looped model's answers were also sampled on the chip (`gsample`) in the final window: all 165 answer files are byte-identical to the CPU sampler's.

**CPU against chip on the trained checkpoints.** `eval` and `geval` on the first 64 held-out windows print the same line for base (`E 6000 64 2409293 1579672`) and for loop (`E 6000 64 2354518 1543758`).

What this run does not show:

- That a loop helps. At equal parameters there is no measured difference in held-out loss, at 1.84 times the cost.
- That shared weights are as good as real depth in general. They were here, on a corpus all three models overfit.
- Anything about coding ability: 0 of 159 for every arm.

Two receipts hold every hash, window and result line: `evidence/omega-llm-gb10-loop.9cc64757bce18e0f1525a45110f492de1861cab5ebeab7bafb33bc5f8d772150.json` (the checks, base and loop) and `evidence/omega-llm-gb10-loop-deep.0aaa7af54916a38ea763418db90c2dd1f25907347df564198dbcaeecb3f3c258.json` (deep and the final window); both name source commit `688d278e`. The pre-registrations, logs and checkpoints are on the Spark under `~/work/ollm-loop-20261121/` (`gate/`, `run/`); the checkpoints are not in this repository.

## What is not done

- Per-token exit from the loop and messages between passes are not built.
- More seeds, a corpus large enough that the arms do not overfit, and BF16 training of a looped model.
