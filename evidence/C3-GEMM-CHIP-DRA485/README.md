# C3 GEMM chip receipt (DRA-485): 208 shapes on the GB10, plus the wrong-transpose negative controls on the chip

Final run: omega-mv branch dra485/c3-gemm-wrong-transpose, code head 9b77c7596a50d596fd4ae745cfa4c0bfa86aaf1d (evidence-only commits follow it), main base 3086ed3ca, physics at the pin (048e5f5e).
The log starts with a provenance header written by tools/run_gpu_gemm_chip.sh: git head, dirty=0, binary sha256 8d65acc03032eb239fd3e90b404a7307fa4045447ca0cc7cdb85b7a997cc159c,
kernel 7.0.0-1019-nvidia, driver 580.173.02, aarch64, MemAvailable and buddyinfo. Run 2026-11-17T22:08Z.

| File | What | Result |
|---|---|---|
| chip-20261117T220817Z-c9d0e8.log, receipt-20261117T220817Z-c9d0e8.json, window-20261117T220817Z-c9d0e8-*.json | `tools/run_gpu_gemm_chip.sh` = `build/gpu_gemm_test` with no flag, exclusive spark-window 20261117T220817Z-c9d0e8 (verdict "quiet machine"; load1 13.2 at start, 13.2 at end, see Speed) | 208 shapes PASS: 26 shape triples x 2 types x 4 layouts, M N K from 1 to 8192, 0 wrong; 104 shapes compared in full (M N K <= 2^27), 104 on a sample (4096 random elements plus about 512 evenly spaced elements of the last row and of the last column); every output word written; 14 red checks caught on the chip (mutants 1, 2, 3 and the wrong transposes 4 (A) and 5 (B) in both directions, 4095 of 4095 outputs wrong each); 226 checks PASS; nvrm_errors_delta 0 |
| per-shape.csv | every shape of the final run: kernel ms, TFLOPS, fraction of ceiling, fraction with the pack kernels | generated from the final log |
| history-b291375e/ | the same tier at code head b291375e (window 20261117T213117Z-3784d7, load1 9.65 at start, busy-polled marker): same shapes | also PASS, 226 checks; the code differences to the final head are the sample wording, the --spin-us range check and the runner, not the kernels |
| history-first-run-50us-poll/ | first run the same day (window 20261117T211140Z-df8aaf, 50 us sleep-poll marker) and a value-window quick run | PASS; superseded: kernel times are quantized to 0.1 ms steps |
| 01-host-only.log, 02-sim.log | host 196 checks, simulator 222 checks (final head) | PASS |
| 03-noop-mutants-4-5.patch, 03-sim-mutants-4-5-noop-control.log | control of the control: `git apply 03-noop-mutants-4-5.patch` (src hunks only) turns mutants 4 and 5 into no-ops; then `make test-gpu-gemm` | simulator FAIL 8 of 222 (all eight transpose checks read 0 wrong of 4095), exit 2 |
| ceiling-fp8-gpu-qmma-from-3c8ce239.txt | the FP8 ceiling's measurement, copied from omega-mv 3c8ce239 (branch doc/machine-ceiling, not on main) evidence/MACHINE-CEILING-20261020/raw/gpu-qmma.txt, sha256 98de215d71a78ed4e42109b226e39396b3c3524fca6582b1f67536be2bac8339 | line 63: QMMA peak 237.52 TFLOPS, 0 wrong values |

## Speed
Speed = 2MNK / info.main_ns, one sample per shape per run. main_ns is the host-observed time from submit to the second completion marker, with the marker busy-polled for up to 2000 us
(`--spin-us`, default 2000): it includes the launch/completion latency of the host path (about 8 to 11 us at the smallest shapes) and is not a pure device kernel time.
One named measured ceiling per type: BF16 HMMA 115.36 TFLOPS (evidence OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z, peak.log line 9) and FP8 e4m3 QMMA 237.52 TFLOPS (the file above).
Final run: best shapes 0.0629 (bf16) and 0.0657 (e4m3) of the ceiling, both 8192x64x8192; 8192^3 squares 0.0432 to 0.0444 (bf16) and 0.0452 to 0.0459 (e4m3);
median over the 40 shapes of at least 2^30 multiply-adds 0.0464 (bf16) and 0.0452 (e4m3). Small shapes show a fraction near zero because the time is latency, not arithmetic.
No confidence interval is attached to a shape. The only repeat is the earlier run at b291375e (same kernels, load 9.65): over the 40 large shapes per type the fraction differed by a median of
3% (bf16 3.5%, e4m3 2.8%) and at most 17% (bf16) and 21% (e4m3). The final window ran at load1 13.2 (above the 10 that spark-window's own rule names for a quiet start, but the tool recorded
"quiet machine"); read the fractions as about 0.04 to 0.07 of the ceiling at the large shapes, not to three digits.
This is the general any-shape kernel, not the L403 tuned prefill kernel; the C3 gate is correctness plus the reported fraction, not a speed target.

## Negative controls, wrong transpose
Mutant 4: `omega_gpu_gemm_drive` packs A with the strides of the other layout. Mutant 5: the same for B. Both read inside the M*K / K*N buffers (no out-of-bounds read).
Host, simulator and chip all catch them (above). The original GitHub-only c97e25c (mutant 4, host 166 / sim 188 / control 4 of 188) was not in any local store and
GitHub is not used; this is a re-implementation and extension with the same behaviour. The old C3-GEMM README (evidence/C3-GEMM/README.md, "(next) chip ... waiting for a chip window")
is reviewed evidence and cannot be edited (evidence-immutable gate); this directory supersedes that row, and docs/OMEGA.md now points here.
