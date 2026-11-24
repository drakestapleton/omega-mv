# Arboris prefetch off versus on: DeepSeek-V4.1 decoder on GB10, 2026-11-23

Status: EXERCISED (Series A, co-occurrence prefetcher). Measured on one machine (DGX Spark, GB10) with one workload. Not independently reproduced. Series B and the look-ahead prefetcher GB10 A/B remain `BLOCKED_OPERATOR` / `NOT_RUN` (require an authorized GB10 window and restored checkpoint shards).

All tables and checks below are generated from the stored run files in `RESULTS.md` by `tools/results.py` and verified by `tools/verify.sh`. Each figure is labelled measured (read directly from stored Spark run files) or calculated (computed by `tools/results.py` from measured values).

## Series A result (256 generated tokens)

On a 256-token greedy generation with the co-occurrence prefetcher, turning prefetching on made the run slower.

| | Prefetch off (`DSV41_ARBORIS_PREFETCH=0`) | Prefetch on (`=1`, the default) |
| --- | --- | --- |
| Wall time, three runs each (measured) | 402.8 s, 410.1 s, 415.6 s | 438.0 s, 442.5 s, 453.8 s |
| Wall time, median (calculated) | 410.1 s | 442.5 s |
| Expert load time (`nvme_ns`), median (calculated) | 266.8 s | 307.2 s |
| GPU time (`gpu_ns`), median (calculated) | 66.4 s | 66.3 s |
| Expert lookups (measured) | 62,640 | 62,640 |
| Expert misses (measured) | 8,165 | 7,954 |
| Prefetches dispatched / used (measured) | 0 / 0 | 10,616 / 211 |

- Calculated: median wall time rose by 32.4 s (+7.9%). Every on run (fastest 438.0 s) was slower than every off run (slowest 415.6 s).
- Measured: all six runs produced identical 256 tokens and identical routing (`routing.bin` sha256 `c5dc128195133f97ebcc421343c048ea3e8b2171091ab483133cae57afc84d17`, 10,440 records per run).
- The extra time is in expert loading; GPU time did not move.

Full per-run tables and automated checks are in `RESULTS.md`. Per-run files are in `series-a/runs/L*`, and the machine receipts are in `series-a/receipts/`.

## Why the co-occurrence prefetcher did not help here

- **Few prefetches were useful.** Measured: 211 of 10,616 dispatched prefetches were used (calculated: 2.0%). Each unused prefetch still read and hashed an expert from disk, and the co-occurrence decoder waited for in-flight replies at the next layer.
- **Most misses were first uses.** Measured from the routing records: the run touched 6,853 distinct (layer, expert) pairs, and each first use is a miss. Calculated: off-arm misses 8,165 minus 6,853 distinct pairs leaves 1,312 reloads after eviction (16.1% of misses). The co-occurrence table learns only from experts it has already seen routed, so first uses are out of its reach.
- **Prediction accuracy is not the problem.** Replaying the measured routing (`c5dc128195133f97ebcc421343c048ea3e8b2171091ab483133cae57afc84d17`) through `tests/arboris/online_adapt_bench.om` on CPU (`replay.txt`, simulated, not decoder measurements):
  - With 6 guesses per layer, 26,400 of 61,074 routed experts were predicted (43.2%, calculated); frequency-only baseline 25,677.
  - With 2 guesses per layer (the co-occurrence decoder's cap), 14,421 of 61,074 routed experts were predicted (23.6%, calculated; at most 20,358 guesses, so at least 70.8% of guesses were right); frequency-only baseline 14,344.
  - With the harness's FIFO cache simulation (110 slots per layer): 51,505 cache hits without prefetch, 51,614 with prefetch, 109 prefetch hits.
- **Correct guesses are mostly already resident.** That is why 43.2% prediction accuracy turns into 2.0% useful prefetches.

The 42 to 44% Arboris "hit" figures in `om/gpu/q36/README.md` are this same prediction accuracy on Qwen 3.6 35B. That decoder only scores predictions (`q36ArbScorePred`); it fetches nothing and no off-versus-on timing was run there.

## What was run

- **Source.** Series A used the co-occurrence prefetcher unchanged from `adb8fa6a8` plus the `DSV41_ARBORIS_PREFETCH` off switch.
- **Binary (Series A).** `dsv41-decode` sha256 `b413459b001ca2744f735aed73ac06c9f5e10343c160a72ef093572eb3dcf1a3`, qualified at `afb1de29166acc65b068978257bf45a0b12da3df` (`series-a/qualification.log`, sha256 `aff8d3c771622836305461fbae748376a6a8ac57ad0e1be0076cb29520d69702`, last line `PREFETCH-MUTANTS PASS`, 8 mutants rejected) with `seed/out/omc` sha256 `708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3`. Every run records `binary.sha256` and `preflight`.
- **Model.** DeepSeek-V4.1-Flash revision `314113f8a7dadb388215396ba5fbee2c610a04d6`, 48 shards, 510,310,614,966 bytes on disk. `model.sha256` matches `model-upstream.sha256` on 48 of 48 weight shards (checked by `tools/results.py`). Index and sidecar hashes are in `inputs.sha256`.
- **Workload.** `gen`, prompt token IDs `0 671 6102 294 8760 344`, greedy, 256 generated tokens, 4,400 resident expert slots.
- **Machine.** NVIDIA GB10, driver 580.173.02, kernel 7.0.0-1019-nvidia, 4096-byte pages (`host.txt`).

## Method

- One run per `spark-window` with the chip lock and quiet lock both exclusive.
- Before each run, `tools/pagecache.py` drops all 48 shards from the page cache and checks residency with `mincore`. Measured: every run started with 0 of 124,584,171 pages cached (`series-a/runs/*/cache-before`).
- Arms alternated: on, off, off, on, on, off.
- Wall time is the decoder process only, from `tools/series-a/run-one.sh`. The receipt's `seconds` also covers cache drop, preflight, and a 10 s settle.
- `spark-window run` environment passthrough was verified in window `20261123T164833Z-d968fd` (`envcheck.txt`, binary `9b9bf2e26c9d49f6e0ed0d74bc4b3c38c3c995896e49d42a72bd760a872ffd94` at `981d832eb55860ba9c75d901c8f89846d2f06f6c`): `DSV41_ARBORIS_PREFETCH=0` gave `ARBORIS pf_enabled=0` and `DSV41_ARBORIS_PREFETCH=1` gave `ARBORIS pf_enabled=1`.

## Other modes checked on GB10

- **`layer0` parity.** `layer0-parity.log`: binary `b413459b001ca2744f735aed73ac06c9f5e10343c160a72ef093572eb3dcf1a3` passes `check-layer0.py` (`GATE2_LAYER0_PARITY_PASS`) with the variable unset and with `DSV41_ARBORIS_PREFETCH=1`, and both output files are byte-identical (`a8529380ac7cae8bbc9cc633fc843960399e5db20ac27fc1c85a4cc9c97ecfeb`).
- **`chat` mode was not run.**

## Limits and disclosures

- **Machine load.** Measured `load1_start` at run start ranged from 5.01 to 9.74 (`series-a/receipts/`). Other lanes' CPU jobs were running; the quiet lock keeps builds out but does not idle the machine.
- **Driver log lines.** Measured: runs L3-off, L4-on, and L6-off each logged 1 new NVRM line (`nvrm_errors_delta: 1`). All six runs exited 0 with identical tokens and routing.
- **Cold cache only.** Every run started with 0 cached checkpoint pages. Warm page cache was not measured.
- **One prompt, one length.** Routing and reload share depend on the prompt and generation length.
- **Energy.** Receipt wall power is whole-UPS output at 1% resolution; no energy claim is made.
- **Trace files are not stored here.** Their hashes are in `series-a/runs/*/outputs.sha256`; `routing.bin` strips timestamps so routing identity can be verified directly.
- **Series B and look-ahead prefetcher GB10 A/B.** Not run in this folder (`BLOCKED_OPERATOR` / `NOT_RUN`): Series B was paused mid-run, the DeepSeek-V4.1-Flash weight shards were removed from Spark on operator request, and the look-ahead prefetcher has not yet been run on GB10.

## Reproduce

```sh
# Verify this evidence folder on any machine (CPU only, python3):
sh evidence/DSV41-ARBORIS-PF-AB-20261123/tools/verify.sh
# Replay routing through the Arboris CPU harness (AArch64 Linux, clean tree):
sh evidence/DSV41-ARBORIS-PF-AB-20261123/tools/replay.sh \
    evidence/DSV41-ARBORIS-PF-AB-20261123/series-a/runs/L1-on/routing.bin
```
