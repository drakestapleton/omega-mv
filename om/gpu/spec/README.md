# Pure Seeded OM-2 Speculative Decoding Scheduler (`om/gpu/spec/`)

Zero-heap, zero-C, zero-CUDA Omega implementation of DeepInfer's confidence-scheduled variable-length speculative verification engine (`MTPVarlen` from `deepseek-ai/DeepInfer/csrc/engine/mtp_varlen.hpp`) plus a zero-training N-gram prompt-lookup drafter calibrated with per-depth EMA acceptance probabilities.

## Modules

- **`mtp_varlen.om`**:
  - Hardware decode throughput curve (`specCurveM`, `specCurveMs`, initialized for GB10 via `specInitGb10DefaultCurve` or live-calibrated via `specAddCurvePoint`).
  - Online `ForwardRuntimeEstimator` (per-graph-size sliding median + median-of-medians slope, clamped `>= 0.0`) and `SamplerRuntimeEstimator` (9-sample sliding median per `num_seqs` with global fallback).
  - `specSchedule(numSeqs)`: exact `N-2` total-budget (`best_bsz`) + `N-1` per-stream (`specOutLens`) async-decoupled scheduler maximizing `expected_accepted / (baseline_ms + slope_ms * graph_size + sampler_ms)`.
  - `specVerifyGreedy(...)`: lossless greedy speculative verification (`a + 1` emitted tokens bit-identical to target greedy decoding).
- **`ngram_draft.om`**:
  - Longest-suffix (4-gram → 2-gram) prompt/context lookup drafter (`k <= 5`) with online per-depth EMA acceptance calibration (`ngObserveResult`), producing cumulative per-position acceptance rates in the same format as a DSpark Confidence Head.
- **`check_mtp_varlen.om`**:
  - Host self-test & negative-control gate (light load full draft, heavy load knee trimming, async `N-2`/`N-1` decoupling, online runtime estimators + negative-slope clamp, lossless greedy verification + N-gram drafter, hostile-input refusal).

## Build and Verify (AArch64 Linux)

```sh
sh seed/omega-from-seed.sh
sh om/gpu/spec/build.sh build/spec
build/spec/check_mtp_varlen
```
