# Arboris prefetch off versus on: DeepSeek-V4.1 decoder on GB10, 2026-11-23

Status: EXERCISED. Measured on one machine (DGX Spark, GB10) with one workload. Not independently reproduced.

## Result

On a 256-token greedy generation, turning the Arboris prefetcher on made the run slower.

| | Prefetch off (`DSV41_ARBORIS_PREFETCH=0`) | Prefetch on (`=1`, the default) |
| --- | --- | --- |
| Wall time, three runs each | 402.8 s, 410.1 s, 415.6 s | 438.0 s, 442.5 s, 453.8 s |
| Wall time, median | 410.1 s | 442.5 s |
| Expert load time (`nvme_ns`), median | 266.8 s | 307.2 s |
| GPU time (`gpu_ns`), median | 66.4 s | 66.3 s |
| Expert lookups | 62,640 | 62,640 |
| Expert misses | 8,165 | 7,954 |
| Prefetches dispatched / used | 0 / 0 | 10,616 / 211 |

- Median wall time rose by 32.4 s (7.9%). Every on run was slower than every off run.
- All six runs produced the same 256 tokens and the same routing (expert IDs and gate weights at all 10,440 trace records).
- The extra time is in expert loading. GPU time did not move.

Exact values are in `summary-long.json`. Per-run files are in `runs/L*`, and the machine receipts are in `receipts/`.

## Why prefetching did not help here

- **Few prefetches were useful.** 211 of 10,616 dispatched prefetches (2.0%) were used. Each unused one still reads and hashes one expert from disk, and the decoder waits for the reply at the next layer.
- **Most misses cannot be predicted.** The run touched 6,853 distinct (layer, expert) pairs, and each first use is a miss. That leaves 1,312 of the 8,165 off-arm misses (16%) as reloads after eviction. Arboris learns only from experts it has seen routed, so the first uses are out of its reach.
- **Prediction accuracy is not the problem.** Replaying the L1 routing trace through `tests/arboris/online_adapt_bench.om` gives the figures in `replay.txt`:
  - With 6 guesses per layer, 26,400 of 61,074 routed experts were predicted (43.2%). The frequency-only baseline predicted 25,677.
  - With 2 guesses per layer (the decoder's cap), 14,421 of 20,358 guesses were right (70.8%).
  - The harness's own cache simulation (FIFO, 110 slots per layer) gives 51,505 cache hits without prefetch and 51,614 with it. Prefetch adds 109.
- **Correct guesses are mostly already resident.** That is why 43% accuracy turns into about 2% useful prefetches.

The 42 to 44% Arboris "hit" figures in `om/gpu/q36/README.md` are this same prediction accuracy, measured on Qwen 3.6 35B. That decoder only scores predictions (`q36ArbScorePred`). It fetches nothing, and no off-versus-on timing was run there.

## Short workload (32 tokens)

`runs/w1-*`, `runs/w2-*`, `summary-short.json`. Wall times were 148.4 s and 141.2 s off, 142.8 s and 142.4 s on. The prefetcher dispatched nothing in either arm (`pf_dispatched=0`): the run touches 2,990 distinct experts, below the 4,400 resident slots, so every routed expert is still resident and there is nothing to prefetch. This workload cannot show a prefetch effect.

## What was run

- **Source.** omega-mv branch `feat/dsv41-arboris-prefetch-ab`. The prefetcher logic is unchanged from `adb8fa6a8`; the branch adds the off switch.
- **Binary (long runs).** `dsv41-decode` sha256 `b413459b001ca2744f735aed73ac06c9f5e10343c160a72ef093572eb3dcf1a3`, built at `95ac8bdf3` by `check-prefetch-mutants.sh` with `seed/out/omc` sha256 `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`. Each run records the binary hash and a `pfcheck` preflight line.
- **Binary (short runs).** Built at `bfabe5f44` (sha256 `cf7a0506...` in that head's build log). The short runs did not record the binary hash per run.
- **Model.** DeepSeek-V4.1-Flash revision `314113f8`, 48 shards, 510,310,614,966 bytes on disk. Index and sidecar hashes are in `inputs.sha256`. The decoder verifies each expert's digest when it loads it.
- **Workload.** `gen`, prompt token IDs `0 671 6102 294 8760 344`, greedy, 256 generated tokens (32 for the short runs).
- **Machine.** NVIDIA GB10, driver 580.173.02, kernel 7.0.0-1019-nvidia, 4 KiB pages (`host.txt`).

## Method

- One run per `spark-window` with the chip lock and the quiet lock both exclusive (the short runs had two runs per window).
- Before each run, `tools/pagecache.py` drops all 48 shards from the page cache and checks residency with `mincore`. Every run started with 0 of 124,584,171 pages cached (`runs/*/cache-before`).
- Arms alternated: on, off, off, on, on, off.
- Wall time is the decoder process only, from `tools/run-one.sh`. The receipt's `seconds` also covers the cache drop, the preflight and a 10 s settle.
- `tools/summarize.py` checks every run: exit 0, cold start, arm label matches `pf_enabled`, off arm dispatched nothing, on arm dispatched something, one binary, identical tokens and routing. All checks passed for the long runs.
- Host qualification of the switch and its eight negative controls: `host-qualification-95ac8bdf3.log`. That log ends in FAIL because the driver's expectation for mutant G assumed the wrong exit code; the mutant itself was rejected. The driver was corrected in the next commit.

## Limits and disclosures

- **Machine load.** The 1-minute load average at run start was between 5.0 and 9.7 (`receipts/`). Other lanes' CPU jobs were running. The quiet lock keeps builds out but does not idle the machine.
- **Driver log lines.** Runs L3, L4 and L6 each logged one new NVRM line (`nvrm_errors_delta: 1`). The one inspected (L3, 15:38:28Z) was an `NV_ERR_NO_MEMORY` allocation retry during startup. All three runs exited 0 with outputs identical to the others.
- **Cold cache only.** Every run starts with nothing cached, so every expert load is a real disk read. A warm page cache was not measured.
- **One prompt, one length.** Routing, and so the share of predictable misses, depends on the text. A longer or more repetitive workload has more reloads after eviction and could behave differently.
- **Energy.** The receipts' wall power is the whole UPS output at 1% resolution. No energy claim is made.
- **Trace files are not stored here** (835 KB each). Their hashes are in `runs/*/outputs.sha256`. The full trace hash differs between runs because records carry timestamps; `routing_sha256` in the summaries excludes them.

## Reproduce

```sh
# Build and qualify (host only), from a clean tree at the branch head:
bash om/gpu/dsv41/decoder/check-prefetch-mutants.sh "$out/pf" "$out/tensors.bin" "$sidecars" "$checkpoint"
# One timed run per window; tools/ab-long.sh drives six of them:
DSV41_BIN="$out/pf/dsv41-decode" NGEN=256 tools/ab-window.sh NAME 1:L1-on
python3 -I tools/summarize.py runs L1-on L2-off L3-off L4-on L5-on L6-off
```

The tools assume the Spark's paths (`~/work/dsv41-pf-ab-out`, `~/models/deepseek-v4.1-flash-314113f8`).
