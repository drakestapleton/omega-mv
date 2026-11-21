# Looped core

A looped model runs some of its layers more than once with the same weights. Depth then costs time and activation memory, not parameters.

The loop is a property of the checkpoint. Training, evaluation, sampling and the CPU server read it from the file; nothing else changes on the command line.

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
- A core that is empty or does not fit in the `L` layers is exit 12. So is a loop whose activations or attention rows do not fit the pools.
- `train`, `eval`, `sample`, `grad`, `gcheck`, `tune`, `kvcmp` and `serve` run a looped checkpoint.
- Every other command refuses one with exit 17: `grow`, the specialist commands and all GB10 commands, `gserve` and `gsample` included. They apply each layer once and would compute a different model.

## Checkpoint

A looped model is saved as `OLLMCK03`. Its header is 144 bytes: the `OLLMCK02` fields, then `LP`, `LC` and `NP` at bytes 112, 120 and 128, then the payload FNV-1a 64 at byte 136. The payload is unchanged: parameters, then both Adam moments, 24 bytes per parameter.

A model without a loop is still written as `OLLMCK01` or `OLLMCK02`, byte for byte as before. A `OLLMCK03` file with `NP` below 2 is refused (exit 12).

## How it is built

The layer index used to choose both a layer's parameters and its activations. It now chooses the activations only; `olp` in `native/model.om` maps a layer application to its parameter layer.

- Activations, attention probabilities and the decode's row cache are kept per application, so the cached decode works unchanged.
- Every gradient write adds, so a core weight's gradient is the sum over its passes with no new backward code.
- The output projections are initialised at 1/sqrt(2 × applications) instead of 1/sqrt(2 L).

## What has been checked

All on AArch64 Linux in a virtual machine, CPU only, with toy shapes (V 256 or 300, T 16, D 16), on 2026-11-21. No looped model has been trained on real data, and nothing here ran on a GPU.

| Check | Result |
| --- | --- |
| Models without a loop: 19 commands and 4 checkpoints against the binary from before the change | Same output and checkpoint bytes (`kvcmp` apart from its timings) |
| `init` with `NP` 1 against `init` without loop numbers | Same file |
| `gcheck` on a looped checkpoint, at step 0 and after 12 steps | Passes (largest relative error 6.7e-4 against a tolerance of 1e-3) |
| Mutant l (a core weight keeps only its first pass's gradient) | `gcheck` exits 40 |
| Forward against an unrolled twin: a model without a loop holding one copy of the weights per application | Same loss bits, same sampled bytes |
| Gradient against the twin's, with the copies summed | Largest relative difference 6e-13 |
| Training 0→20 in one run, in two runs, and with 2 worker processes | Same checkpoint |
| `kvcmp` (cached decode against the full forward) on a looped checkpoint | 0 differing logits; mutant i exits 43 |
| Small bank capacities, so core layers and activations cross into the second banks | Same loss, gradient file and trained checkpoint |
| `serve` with a looped checkpoint | Served text equals `sample` for the same seed |
| Refusals | Exit 12, 2 and 17 as listed above; a flipped payload bit is exit 14 |

The twin is the independent check of the loop's meaning: it is built outside `ollm` by copying parameter blocks, and it shares no code with the loop.

## What is not done

- The GB10 path does not run loops, so a looped model trains on the CPU only for now.
- There is no measurement of whether a loop helps. The comparison to run is `L` 8 with `LP` 2, `LC` 4, `NP` 3 against the 8-layer model at equal parameters and a 16-layer model at equal compute, scored on held-out loss and on the coding benchmark (`tools/bench/`).
- Per-token exit from the loop and messages between passes are not built.
