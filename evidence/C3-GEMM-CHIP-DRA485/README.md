# C3 GEMM chip receipt (DRA-485): 208 shapes on the GB10, plus the wrong-transpose negative controls on the chip

Source: omega-mv main 3086ed3ca + branch dra485/c3-gemm-wrong-transpose, code head b291375e (evidence-only commits follow it). Physics at the pin in physics.lock (048e5f5e).
Binary build/gpu_gemm_test sha256 dfcb56cd6c5ef89b3ad737b1073213f0f7aedd52c51453456327cd6d52620342 (aarch64 native, cc -O2 -ffp-contract=off).
Device: NVIDIA GB10, driver 580.173.02, kernel 7.0.0-1019-nvidia, run 2026-11-17T21:31Z.

| File | What | Result |
|---|---|---|
| chip-208-shapes.log, receipt-full.json, window-*.json | `build/gpu_gemm_test` with no flag, exclusive spark-window 20261117T213117Z-3784d7 (verdict "quiet machine", lease 20 min, load1 9.65 at start) | 208 shapes PASS: 26 shape triples x 2 types x 4 layouts, M N K from 1 to 8192, 0 wrong; 104 shapes compared in full (M N K <= 2^27), 104 on a sample (4096 random elements plus the last row and column); every output word written; 14 red checks caught on the chip (mutants 1, 2, 3 and the wrong transposes 4 (A) and 5 (B) in both directions, 4095 of 4095 outputs wrong each); 226 checks PASS; nvrm_errors_delta 0 |
| per-shape.csv | every shape: kernel ms, TFLOPS, fraction of ceiling, fraction with the pack kernels | generated from the log |
| chip-*-first-run-50us-poll.log | first run the same day (window 20261117T211140Z-df8aaf, 50 us sleep-poll marker) | also PASS; superseded, kept as history: its kernel times are quantized to 0.1 ms steps |
| 01-host-only.log, 02-sim.log | host 196 checks, simulator 222 checks | PASS |
| 03-noop-mutants-4-5.patch, 03-sim-mutants-4-5-noop-control.log | control of the control: the patch turns mutants 4 and 5 into no-ops | simulator FAIL 8 of 222 (all eight transpose checks read 0 wrong of 4095) |
| ceiling-fp8-gpu-qmma-from-3c8ce239.txt | the FP8 ceiling's measurement, copied from omega-mv 3c8ce239 (branch doc/machine-ceiling, not on main) evidence/MACHINE-CEILING-20261020/raw/gpu-qmma.txt, sha256 98de215d71a78ed4e42109b226e39396b3c3524fca6582b1f67536be2bac8339 | line 63: QMMA peak 237.52 TFLOPS, 0 wrong values |

## Speed
Speed = 2MNK / info.main_ns, one sample per shape. main_ns is the host-observed time from submit to the second completion marker, with the marker
busy-polled for up to 2000 us (`--spin-us`, default 2000), so it includes the launch/completion latency of the host path (about 8 us at the smallest shapes) and is not a pure device
kernel time; the busy-poll resolves times of a few microseconds. One named measured ceiling per type: BF16 HMMA 115.36 TFLOPS
(evidence OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z, peak.log line 9) and FP8 e4m3 QMMA 237.52 TFLOPS (the file above).
Best shapes: 0.0605 (bf16, 8192x64x8192, A col B col) and 0.0705 (e4m3, 8192x64x8192, A col B row) of the ceiling. 8192^3: 0.0437 to 0.0447 (bf16), 0.0462 to 0.0468 (e4m3).
Median over the 40 shapes of at least 2^30 multiply-adds: 0.0467 (bf16), 0.0456 (e4m3). Small shapes show a fraction near zero because the time is latency, not arithmetic.
This is the general any-shape kernel, not the L403 tuned prefill kernel; the C3 gate is correctness plus the reported fraction, not a speed target.

## Negative controls, wrong transpose
Mutant 4: `omega_gpu_gemm_drive` packs A with the strides of the other layout. Mutant 5: the same for B. Both read inside the M*K / K*N buffers (no out-of-bounds read).
Host, simulator and chip all catch them (above). The original GitHub-only c97e25c (mutant 4, host 166 / sim 188 / control 4 of 188) was not in any local store and
GitHub is not used; this is a re-implementation and extension with the same behaviour.
