# C3 GEMM chip receipt (DRA-485): any-shape GEMM in BF16 and FP8 on the GB10, with wrong-transpose controls on the chip

<!-- generated: tools/c3_gemm_evidence.sh summary chip-20261117T222059Z-0d5b0d.log history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log history/b291375e-26-triples-load9.65/chip-208-shapes.log -->
- provenance: window 20261117T222059Z-0d5b0d
- provenance: git head a5e29deb5f92d43139b5eb2b79aab45e6544c6c0 dirty=0 files
- provenance: binary 04464f078ff321a1ac62360f979023da8939a82569e26adefed18f7124f0bf80
- provenance: kernel 7.0.0-1019-nvidia driver 580.173.02 arch aarch64
- provenance: exit 0
- cases: 1648 = 206 distinct (M, N, K) shapes x 2 types x 4 layouts; every shape in every type/layout cell exactly once: yes
- dimensions: smallest 1, largest 8192; wrong outputs in all cases: 0; compared in full (checked = M*N): 1288 cases, on a sample: 360 cases
- DRA-485 acceptance, read literally (at least 200 shapes, each a distinct (M, N, K), dimensions 1 to 8192, BF16 and FP8, both layouts of A and B, every shape correct against a host reference): PARTIAL: 0 wrong, but 161 shapes were compared in full in every cell and 45 shapes only on a sample in at least one cell
- speed bf16: best 0.0552 (8192x8192x826 A col B col); 8192^3 0.0379 to 0.0433; over the 108 cases of at least 2^30 multiply-adds median 0.0400, lowest 0.0062 (8192x8192x42 A row B col), 19 below 0.03
- speed e4m3: best 0.0595 (8192x64x8192 A row B row); 8192^3 0.0426 to 0.0453; over the 108 cases of at least 2^30 multiply-adds median 0.0383, lowest 0.0029 (8192x8192x42 A col B row), 30 below 0.03
- repeat vs history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log, bf16: 40 common cases of at least 2^30 multiply-adds, |final - earlier| / earlier median 7.8%, max 34.2%
- repeat vs history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log, e4m3: 40 common cases of at least 2^30 multiply-adds, |final - earlier| / earlier median 5.0%, max 20.0%
- repeat vs history/b291375e-26-triples-load9.65/chip-208-shapes.log, bf16: 40 common cases of at least 2^30 multiply-adds, |final - earlier| / earlier median 8.5%, max 25.5%
- repeat vs history/b291375e-26-triples-load9.65/chip-208-shapes.log, e4m3: 40 common cases of at least 2^30 multiply-adds, |final - earlier| / earlier median 6.9%, max 20.4%
- chip red checks caught: 14
- wrong-transpose controls caught on the chip: bf16 mutant 4 (A row B row); bf16 mutant 4 (A col B row); bf16 mutant 5 (A row B row); bf16 mutant 5 (A row B col); e4m3 mutant 4 (A row B row); e4m3 mutant 4 (A col B row); e4m3 mutant 5 (A row B row); e4m3 mutant 5 (A row B col)
- last line: C3 gemm chip: PASS (1666 checks)
<!-- end generated -->

## Files

Command lines run in this directory unless they say otherwise; `../../tools/` is the repository's `tools/`.

- `chip-20261117T222059Z-0d5b0d.log`: the final run, `tools/run_gpu_gemm_chip.sh` running `build/gpu_gemm_test` with no flag in an exclusive spark-window. Its `provenance:` lines name the window, git head, dirty flag, binary sha256, kernel and driver.
- `receipt-20261117T222059Z-0d5b0d.json`, `window-20261117T222059Z-0d5b0d-open.json`, `window-20261117T222059Z-0d5b0d-close.json`: the receipt and window files of that run (load1 and power are in them).
- `per-shape.csv`: every case of the final run, a line per case:
  `sh ../../tools/c3_gemm_evidence.sh csv chip-20261117T222059Z-0d5b0d.log > per-shape.csv`
- `history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log`, `history/9b77c759-26-triples/receipt-20261117T220817Z-c9d0e8.json`, `history/9b77c759-26-triples/window-20261117T220817Z-c9d0e8-open.json`, `history/9b77c759-26-triples/window-20261117T220817Z-c9d0e8-close.json`: an earlier run at commit 9b77c759 of a shorter shape list whose shapes are all in the final run; history, not the acceptance run. `history/9b77c759-26-triples/per-shape.csv` is its case table:
  `sh ../../tools/c3_gemm_evidence.sh csv history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log > history/9b77c759-26-triples/per-shape.csv`
- `history/b291375e-26-triples-load9.65/chip-208-shapes.log`, `history/b291375e-26-triples-load9.65/receipt-full.json`, `history/b291375e-26-triples-load9.65/window-open.json`, `history/b291375e-26-triples-load9.65/window-close.json`: the same shorter list at commit b291375e, run while other work loaded the machine (load1 in `history/b291375e-26-triples-load9.65/receipt-full.json`); history.
- `history/first-run-50us-poll/chip-quick-value-check-first-run.log`, `history/first-run-50us-poll/chip-part0-first-run-50us-poll.log`, `history/first-run-50us-poll/chip-208-shapes-first-run-50us-poll.log`: the first runs, with the completion marker sleep-polled instead of busy-polled, so their kernel times are quantized to the poll step; history.
- `01-host-only.log`: `build/gpu_gemm_test --host-only` (refusals and code generation, no device).
- `02-sim.log`: `make test-gpu-gemm` (the warp simulator tier).
- `03-noop-mutants-4-5.patch`, `03-sim-mutants-4-5-noop-control.log`: the control of the control. In the repository root,
  `git apply evidence/C3-GEMM-CHIP-DRA485/03-noop-mutants-4-5.patch && make test-gpu-gemm`
  turns the wrong-transpose mutants into no-ops, so the simulator tier must exit nonzero on the transpose checks; the log is that run.
- `ceiling-fp8-gpu-qmma-from-3c8ce239.txt`: the FP8 QMMA ceiling measurement, a byte copy of `evidence/MACHINE-CEILING-20261020/raw/gpu-qmma.txt` at omega-mv commit 3c8ce239 (branch doc/machine-ceiling, not on main):
  `git show 3c8ce239:evidence/MACHINE-CEILING-20261020/raw/gpu-qmma.txt | cmp - ceiling-fp8-gpu-qmma-from-3c8ce239.txt`
- `README.md`: this file.
- `SHA256SUMS`: the sha256 of every other file in this directory:
  `find . ! -type d ! -path ./SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | xargs sha256sum > SHA256SUMS`
  `sha256sum -c SHA256SUMS`

## Method notes

- The block between the generated markers is the output of the command in the opening marker, run in this directory with the generator `tools/c3_gemm_evidence.sh`; every count, range, median and acceptance word of this receipt is in that block and nowhere else in this file. `tools/c3_gemm_evidence.sh check`, run by `tests/gates/run.sh c3-gemm-evidence`, reruns that command and the csv command of each `per-shape.csv` and checks `SHA256SUMS`. The chip logs are as the runs wrote them.
- A SHAPE is a distinct (M, N, K) triple. Each shape runs in BF16 and in FP8 e4m3, with A and B each row or column major. The acceptance line of the block reads the DRA-485 clause literally.
- Correctness: each compared element must equal, bit for bit, a host model of the same tensor-core steps (`ref_elem` in `tests/gpu_gemm_test.c`, on the chip-measured HMMA and QMMA models of `tests/bw_hmma_model.h` and `tests/bw_qmma_model.h`), and every output word must be written (the POISON scan in `src/omega_gpu_gemm.c`). Which cases are compared in full and which elements a sampled case compares is defined by `chip_tier` and its compare routine in `tests/gpu_gemm_test.c`; the `checked` column of `per-shape.csv` is the number of elements compared in each case, and the block counts the cases compared in full and on a sample.
- Speed: twice M·N·K divided by `main_ns`, the multiply kernel's launch-to-completion time as the host observes it (`src/omega_gpu_gemm.c`), with the completion marker busy-polled for `--spin-us` (default in `tests/gpu_gemm_test.c`). It includes the host path's launch and completion latency, so it is not a pure device kernel time. The fraction is of the per-type ceiling constants in `tests/gpu_gemm_test.c`, whose header comment cites the BF16 HMMA peak measurement OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z and the FP8 QMMA measurement copied here as `ceiling-fp8-gpu-qmma-from-3c8ce239.txt`. No confidence interval is attached to a case; the repeat lines of the block compare the cases common to the final run and each named history run, relative to the earlier run.
- This is the general any-shape kernel, not the tuned prefill kernel; the C3 bar asks for correctness plus the reported fraction, not a speed target.
- Negative controls: the wrong-transpose mutant hooks in `src/omega_gpu_gemm.c` pack A, or B, with the strides of the other layout; both read inside the buffers. The host, simulator and chip tiers of `tests/gpu_gemm_test.c` run them, and the block lists the chip cases caught.
