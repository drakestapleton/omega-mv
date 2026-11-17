# C3 GEMM chip receipt (DRA-485): 208 shapes on the GB10, plus the wrong-transpose negative control on the chip

Source: omega-mv main 3086ed3ca + branch dra485/c3-gemm-wrong-transpose (mutant 4, `--part`). Physics at the pin in physics.lock (048e5f5e).
Binary build/gpu_gemm_test sha256 b8b739b497f0309ef0576f8ba0248533c794555198f7d72a22d977ef85372f63 (aarch64 native, cc -O2 -ffp-contract=off).
Device: NVIDIA GB10, driver 580.173.02, kernel 7.0.0-1019-nvidia, run 2026-11-17T21:11Z.

| File | What | Result |
|---|---|---|
| chip-208-shapes.log | `build/gpu_gemm_test` with no flag, exclusive spark-window 20261117T211140Z-df8aaf (verdict: quiet machine, held 73 s, lease 20 min) | 208 shapes PASS (26 shape triples x 2 types x 4 layouts, M N K 1..8192), 0 wrong; 4 mutants x both types caught on the chip; 222 checks PASS |
| per-shape.csv | every shape: kernel ms, TFLOPS, fraction of ceiling, fraction with the pack kernels | generated from the log |
| receipt-full.json, window-*.json | spark-receipt and window open/close records | nvrm_errors_delta 0 |
| chip-part0.log, receipt-part0.json | `--part 0` (bf16, A row B row) in its own window 20261117T211043Z-457dac | PASS, 26 shapes |
| chip-quick-value-check.log | `--quick` in a --quiet none value window (not a speed) | PASS, 38 checks |

Speed = 2MNK / device-kernel time (`info.main_ns`), as a fraction of ONE named measured ceiling per type: BF16 HMMA 115.36 TFLOPS
(evidence OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z), FP8 e4m3 QMMA 237.52 TFLOPS (L151 as quoted in evidence/L403-roof-20261022).
Best shapes reach 0.0672 (bf16) and 0.0710 (e4m3) of the ceiling (8192x64x8192); the 8192^3 squares reach 0.043 to 0.046 (bf16) and
0.044 to 0.048 (e4m3). Median over shapes of at least 2^30 multiply-adds: 0.047 for both types. Small shapes sit at the ~0.103 ms
launch floor (fraction below 0.001). This is the general any-shape kernel, not the L403 tuned prefill kernel; correctness, not speed, is the C3 gate.
Compared in full when M N K <= 2^27, else on 4096 random elements plus the last row and column (known limit, stated in the test header).

## Negative control, wrong transpose (mutant 4)
`omega_gpu_gemm_drive` packs A with the strides of the other layout. Host 166 PASS, simulator 188 PASS (01, 02 logs), mutant-4-as-no-op
control: simulator FAIL 4 of 188 (03 log). Chip: caught in both directions (A row and A col layouts), both types, 4095 of 4095 outputs wrong
(chip-208-shapes.log, "chip red check ... mutant 4"). The original c97e25c (GitHub only) was not in any local store and GitHub is not
reachable by rule; this is a re-implementation with the same behaviour described in the issue (host 166, sim 188, control 4 of 188).
