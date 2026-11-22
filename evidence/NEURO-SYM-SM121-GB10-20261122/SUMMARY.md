# Pure Seeded OM-2 Neuro-Symbolic SM121 GB10 Synthesizer Evidence Bundle

- **Date:** 2026-11-22
- **Host / Silicon:** DGX Spark (AArch64 Linux, NVIDIA GB10 SM 12.1, 48 SMs, 24 MiB L2)
- **Compiler:** `seed/out/omc` (`708fdc0f...`, pure seeded OM-2, zero C, zero CUDA, zero Python in engines)
- **Window & Receipt:** `20261122T200159Z-23cbad` (`quiet machine`, `exclusive` chip+quiet lock, `silicon-v3-receipt.json`)

## 1. Live Physical GB10 SM121 Silicon Execution (`om_synth_gb10.om`)

- **Binary:** Static AArch64 ELF built by `seed/helix/ollm_factory/build-synth-gb10.sh` (`106,524` bytes, SHA-256 `13afd5be604f55990cbffa8f1c68887db2da13169d6d3bacca422eea8df8c06f`, `ldd: not a dynamic executable`, zero CUDA / zero `libc`).
- **Offline SASS Verification:** All 10 hand-emitted SM121 binary-op kernels (`op_4` `ADD` through `op_13` `REM`, `6,128`–`9,840` bytes each) disassembled with `0` errors under `/usr/local/cuda-13.0/bin/nvdisasm -b SM121` and passed Antibody `#14` (`stall >= 6`).
- **Live Silicon Result (`spark-receipt om-synth-gb10-silicon-v3`, `exit: 0`, `nvrm_errors_delta: 0`):**
  ```
  OM_SYNTH_GB10 SILICON SELFCHECK PASS c1_03=3278 c1_11=170 d3_cands=594655360 d3_nodes=1048576 d3_pruned=23189831 d3_invalid=125240608 d3_aborts=445176213 d3_occ=131072 gpu_us=32907332 mcands_s=18 inv1_cas=1 inv2_occ70_p32=1 inv3_branchless=1
  ```
  - **INV-1 (Strict BFS Level Barriers + 64-bit `ATOMG.E.CAS.64.STRONG.GPU`):** Synthesized `c1-03` class (`and (shr a 5) 1`, node `3278`) and `c1-11` class (`sub a (rem a 14)`, node `170`) on GB10 silicon and verified both bit-exact on CPU; collapsed `23,189,831` observationally equivalent duplicates on the fly.
  - **INV-2 (`MAX_PROBES = 32` + 70% L2 Occupancy Cutoff):** Real `16 MiB` L2-resident table (`1,048,576 x 16 B`, cleared via GPU slot-10 `STG.E.64` zero kernel); `445,176,213` saturated probe chains aborted cleanly at `MAX_PROBES = 32` with zero probe livelock (`occ = 131,072 <= 734,003`).
  - **INV-3 (Branchless 8-Lane Vector Safety):** `125,240,608` `div/rem`-by-`0` and `shift >= 64` candidates invalidated branchlessly across all 8 `u64` lanes with `0` Xid faults (`nvrm_errors_delta: 0`).
  - **Throughput:** `594,655,360` 8-lane 64-bit candidates evaluated in `32.907 s` (`18.07M` 8-lane programs/s = `144.6M` 64-bit lane evals/s).

## 2. Cache-Resident Operator Prior (`om_prior.om`) & Wake-Sleep Wave-2 (`om_synth.om`)

- **`om_prior.om`:** `< 2 KiB` L1-cache-resident 24-feature I/O behavior policy ranking all 10 OM-2 ops (`OM_PRIOR SELFCHECK PASS tasks=6/6 top4_recall=6/6 features=24 ops=10`, `0.000` nats forgetting).
- **Wake-Sleep Wave-2 Compounding Depth Compression (`om_synth.om`):** Promotes mined verified combinators (`comb_floor`, `comb_bit`, `comb_ceildiv`, `comb_lowbits`) to depth 0 as inline self-contained OM-2 AST nodes; solves synthetic depth-4 task at depth `<= 2` where raw Wave-1 depth-2 fails (`OM_SYNTH SELFCHECK PASS ... wave2_compress=4to2 forgetting=0 mine=5`, `SEENSUM tasks 165 seen 0 functions 5`).

## 3. Standalone Zero-Leakage Benchmark Evaluation (`tools/bench/`, 165 tasks)

- **Pipeline:** Pure seeded OM-2 `om_formalize -> (om_sketch [151 skeletons] | om_synth [Wave-1 + Wave-2])` on Spark CPU (`ZERO` LLM, `ZERO` GPU, `ZERO` `expect.txt` access, `0.000` nats forgetting, `13 s` wall-clock):
  - **Headline:** **`SCORE tasks 165 pass 77 passcut 0 seen 0`** (`12.8x` vs 15.8M autoregressive LLM 7-round plateau of `5-6 / 159`).
  - **Compile rate on synthesized answers:** **`129 / 129 = 100.0%`** (`0` `nocompile`, `0` `noend`, `0` `passcut`, `0` `refused`, `0` `timeout`; `36` fail-closed abstains).
  - **Per-family breakdown (`pass / tasks`):** `arith 12/20`, `branch 14/39`, `loop 6/16`, `bits 11/15`, `digits 6/11`, `fold 9/13`, `select 2/4`, `count 5/8`, `scan 5/7`, `rewrite 7/32`.
  - **Hybrid (`+ loop_r6.ck` fallback on abstain):** `78 / 165` (`+1` on `rewrite`).

## 4. Disclosure

- An initial `om_synth_gb10` silicon attempt (`20261122T195502Z-a0d456`) triggered 1 MMU `Xid 31` (`FAULT_PDE @ 0x50_05171000`) due to unsigned magic-division overestimation (`ri = gid - li*nR` underflowing by 1). Adding exact 3-instruction overestimation correction + `SQ_MAX_NODES` bounds guards eliminated the fault completely (`nvrm_errors_delta: 0` across both `v2` and `v3` receipts).
- External/third-party re-run: `NOT_RUN`.
