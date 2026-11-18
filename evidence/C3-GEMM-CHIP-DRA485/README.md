# C3 GEMM chip receipt (DRA-485): any-shape GEMM in BF16 and FP8, both layouts, on the GB10, with wrong-transpose negative controls on the chip

Every count, range, median and the acceptance word below is generated from the chip log by `tools/c3_gemm_evidence.sh` and
checked by the always-run gate `tests/gates/run.sh evidence-generated`; the prose around it states methods and sources only.
A SHAPE is a distinct (M, N, K) triple. Each one is run in BF16 and in FP8 e4m3, and in all four layouts of A and B (row or column major each).

## Summary of the final run (generated)
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
<!-- generated-file: per-shape.csv tools/c3_gemm_evidence.sh csv chip-20261117T222059Z-0d5b0d.log -->
<!-- generated-file: history/9b77c759-26-triples/per-shape.csv tools/c3_gemm_evidence.sh csv history/9b77c759-26-triples/chip-20261117T220817Z-c9d0e8.log -->

## Files

| File | What |
|---|---|
| chip-20261117T222059Z-0d5b0d.log, receipt-20261117T222059Z-0d5b0d.json, window-20261117T222059Z-0d5b0d-*.json | the final run: `tools/run_gpu_gemm_chip.sh` = `build/gpu_gemm_test` with no flag, in one exclusive spark-window, provenance header at the top of the log (git head, dirty flag, binary sha256, kernel, driver, MemAvailable, buddyinfo); load1 is in the receipt and window files |
| per-shape.csv | every case of the final run (generated from the log, see the marker above): checked elements, wrong elements, kernel ms, TFLOPS, fraction of the ceiling, the same with the pack kernels |
| history/ | earlier chip runs of the first 26 hand-picked shapes only (not the acceptance run): first run 20261117T211140Z-df8aaf (50 us sleep-poll), b291375e run 20261117T213117Z-3784d7, 9b77c759 run 20261117T220817Z-c9d0e8; kept as history and as the repeat data in the summary |
| 01-host-only.log, 02-sim.log | `build/gpu_gemm_test --host-only` and `make test-gpu-gemm` (simulator) at the final code head |
| 03-noop-mutants-4-5.patch, 03-sim-mutants-4-5-noop-control.log | control of the control: `git apply evidence/C3-GEMM-CHIP-DRA485/03-noop-mutants-4-5.patch` (src hunks only) turns mutants 4 and 5 into no-ops; `make test-gpu-gemm` must then fail on exactly the transpose checks (the log is that run) |
| ceiling-fp8-gpu-qmma-from-3c8ce239.txt | the FP8 ceiling's measurement, copied from omega-mv 3c8ce239 (branch doc/machine-ceiling, not on main) evidence/MACHINE-CEILING-20261020/raw/gpu-qmma.txt, sha256 98de215d71a78ed4e42109b226e39396b3c3524fca6582b1f67536be2bac8339; QMMA peak on line 63 |

## Correctness method
Each case is compared bit for bit with a host model of the same tensor-core steps (chip-measured HMMA and QMMA accumulation
models, `tests/gpu_gemm_test.c` ref_elem), and every output word must be written (POISON scan). Cases of at most 2^27
multiply-adds, and 1000x999x1001, are compared in full; larger ones on 4096 random elements, every max(1, floor(N/512))-th element of
the last row and every max(1, floor(M/512))-th element of the last column (the whole row when N <= 1023, the whole column when M <= 1023). The summary counts which cases were compared in full (checked = M*N) and which on a sample.

## Speed method
Speed = 2MNK / info.main_ns, one sample per case. main_ns is the host-observed time from submit to the second completion marker,
with the marker busy-polled for up to 2000 us (`--spin-us`, default 2000): it includes the host path's launch and completion latency
and is not a pure device kernel time. One named measured ceiling per type: BF16 HMMA
115.36 TFLOPS (evidence OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z, peak.log line 9, printed by our own tensor-core peak test;
what fa_ops.cu in that directory is used for was not traced) and FP8 e4m3 QMMA 237.52 TFLOPS (the copied file above, line 63).
No confidence interval is attached to a case. The repeat lines of the summary compare the shapes common to the history runs
(denominator: the earlier run). The load1 of every window is in its receipt and window files, not restated here: spark-window admits a window while load1 is at most nproc (20, its code); its header
comment still says 10, a stale comment outside this repository. This is the general any-shape kernel, not the L403 tuned prefill
kernel; the C3 gate is correctness plus the reported fraction, not a speed target.

## Negative controls, wrong transpose
Mutant 4: `omega_gpu_gemm_drive` packs A with the strides of the other layout. Mutant 5: the same for B. Both read inside the
M*K / K*N buffers (no out-of-bounds read). Host, simulator and chip run them on one non-square shape, 65x63x100, per type and
direction; the chip results are in the summary. The original GitHub-only c97e25c (mutant 4) was not in any local store and GitHub is
not used; this is a re-implementation and extension with the same behaviour. The old C3-GEMM README (evidence/C3-GEMM/README.md,
"(next) chip ... waiting for a chip window") is reviewed evidence and cannot be edited (evidence-immutable gate); this directory
supersedes that row, and docs/OMEGA.md points here.

## Not in this receipt
DRA-485's November 17 plan (small-row FP8 weight reuse, a tile or weight-reuse variant, prefetch tested separately, win/loss matrix
under DRA-191's rule) is not part of this receipt; its record is in CUDApp evidence/DRA-485-SMALLROW/ (CUDApp branch dra485/fp8-smallrow, not on CUDApp main).
