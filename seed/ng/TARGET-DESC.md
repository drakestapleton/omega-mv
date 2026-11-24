# Unified `TargetDesc` & Universal `ng` Backend Architecture

```text
Document:   seed/ng/TARGET-DESC.md
Status:     IMPLEMENTED (Step 1 foundation in seed/ng/target/, verified HOST_TESTED on Spark AArch64)
Scope:      Unified CPU + GPU + NPU + Multi-Spark realization contract for Omega NG (ΩIR)
```

## 1. Purpose

Traditional compilers split CPUs, GPUs, NPUs, and multi-node clusters into incompatible toolchains (`gcc`/`llvm` vs `nvcc`/`ptxas` vs vendor NPU SDKs vs `MPI`/`NCCL`), and distribute lowest-common-denominator binaries (`x86-64-v1`, `armv8.0-a`, `rv64gc`) that leave 50–80% of modern silicon idle.

Omega unifies **multi-CPU Compile-on-Arrive** with **heterogeneous GPU/APU/Neural realization**:

1. **Ship Meaning (`ΩIR`), Realize Locally:** Canonical SHA-256-addressed `ΩIR` (`seed/ng/IR.md`) is the distribution unit. `ng` probes the exact local silicon and caches native realizations keyed by `(SEMANTIC_ID, TARGET_ID, FEATURES_MASK, SHAPE_SIG)`.
2. **One Unified `TargetDesc` Across All Silicon:** Every execution unit—`Cortex-X925`, `Cortex-A725`, `x86-64 (AVX2/AVX-512)`, `RV64GC/RVV`, `Cortex-M55`, `GB10 SM121`, `Ethos-U55/U85`, and `Multi-Spark Ring`—is a row in one uniform 24-field descriptor derived from `gpu/hw/manifest.tsv`.
3. **Compile-Time Physical Contracts:** `ΩIR` states what a kernel *requires* (`SHARED` bytes, register budget, `subgroup` width, `FRAG` MMA shape, `@exact(E1)` vs `@tol` error envelope). `TargetDesc` states what the chip *offers*. Any violation (e.g., `req_smem = 16384 > smem_bytes = 8192`) is refused *before* emitting a single instruction or QMD.
4. **Shared Backend Engine + Tiny Declarative ISA Tables:** One shared IPRA + live-range register allocator (`regalloc.om`) and one cost-guided pattern selector (`isel.om`) serve AArch64, x86-64, RV64GC, and SM121 via small declarative ISA tables.
5. **Live Realization Cache ↔ `QDI_WTBL`:** The on-device realization cache projects directly into CPU indirect dispatch tables and GPU `QDI_WTBL`, allowing proof-gated hot-swap (checked by `ngcheck` + `ngrun` + `immune.om` antibodies) with zero downtime.

## 2. Unified `TargetDesc` Schema (24 Fields)

| Index | Field | Meaning |
|---|---|---|
| 0 | `isa_id` | `1=AArch64`, `2=x86-64`, `3=RV64GC`, `4=Thumb2`, `16=SM121`, `17=Ethos-U` |
| 1 | `exec_model` | `0=SCALAR_SIMD`, `1=SIMT_WARP`, `2=SYSTOLIC_CMD` |
| 2 | `endian` | `0=little`, `1=big` |
| 3 | `ptr_bits` | `32` or `64` |
| 4 | `ngpr` | Allocatable GPRs (`30` A64/RV64, `15` x86-64, `12` Thumb2, `64` SM121) |
| 5 | `nvec` | Vector / FP registers (`32` A64/RV64/AVX-512, `16` AVX2, `64` SM121) |
| 6 | `npred` | Predicate registers (`16` SVE, `8` AVX-512, `7` SM121, `0` scalar) |
| 7 | `vec_bits` | Native vector width in bits (`128`, `256`, `512`, `1024`) |
| 8 | `scalable_vec` | `1` for SVE/RVV VLA, `0` fixed-width |
| 9 | `two_addr` | `1` for destructive 2-address ISAs (`x86-64`), `0` for 3-address RISC/SASS |
| 10 | `subgroup_w` | `1` scalar, `4/8/16` SIMD lanes, `32` SM121 warp, `64` wavefront |
| 11 | `l1d_kb` | L1 data cache KiB per core/SM |
| 12 | `l2_kb` | L2 cache KiB per core/cluster |
| 13 | `cache_line` | Cache line size in bytes (`64` or `128`) |
| 14 | `smem_bytes` | On-chip scratchpad / shared memory bytes (`0` CPU, `101376` SM121, `16384` restricted test) |
| 15 | `ooo_width` | Issue width (`10` X925, `5` A725, `6` Zen/Xeon, `4` SM121 warp schedulers) |
| 16 | `mul_lat` | Integer/FP multiply latency (cycles) |
| 17 | `div_lat` | Divide latency (cycles) |
| 18 | `branch_cost` | Mispredict / divergence penalty (cycles) |
| 19 | `features_mask` | Bitmask: `FMA(1)`, `DOTPROD(2)`, `I8MM(4)`, `BF16(8)`, `AVX2(16)`, `AVX512(32)`, `RVV(64)`, `SHA(128)`, `AES(256)`, `BMI2(512)`, `FP8(1024)`, `HMMA16816(2048)` |
| 20 | `mma_mask` | Supported `FRAG` tile shapes: `1=M16N8K16_BF16`, `2=M16N8K32_FP8`, `4=M8N8K8_I8MM`, `8=M16N16K16_AMX` |
| 21 | `mem_domain` | `0=HOST_LPDDR`, `1=UVM_C2C_COHERENT`, `2=DEVICE_LOCAL`, `3=SPARK_RING_REMOTE` |
| 22 | `coherence_cost` | Cross-domain sync cost in nanoseconds (`0` local, `80` NVLink-C2C, `4500` Spark Ring) |
| 23 | `caller_save_mask` | Bitmask of caller-saved GPRs for external ABI boundaries (internal calls use IPRA) |

## 3. Units in `seed/ng/target/`

- `target_desc.om`: Unified 24-field `TargetDesc` registry (10 silicon profiles), compile-time physical contract checker (`tdCheckKernelContract`), cache/tile planner (`tdDeriveTilePlan`), and proof-gated Realization Cache (`tdCacheLookup` / `tdCacheInstall`).
- `regalloc.om`: Target-parameterized live-range register allocator + whole-program IPRA clobber propagation + graph-coloring invariant verifier.
- `isel.om`: Cost-guided declarative ISA pattern selector + real machine-code emitters for **AArch64**, **register-allocated x86-64**, **RV64GC**, and **SM121** descriptors.
- `sm121_pe.om`: Runtime shape partial evaluator (`peSpecializeW4Gemm` across `M=1`, `2..8`, `>8`), embedded Antibody `#14` (`stall >= 6`) SASS verifier, and orthogonal ELF64 static executable emitter (`EM_AARCH64=183`, `EM_X86_64=62`, `EM_RISCV=243`).
- `fabric.om`: Live Realization Cache ↔ `QDI_WTBL` dispatch fabric (`fabWtbl`), heterogeneous `apu-gb10` scheduler (`X925` / `A725` / `SM121` / `Spark Ring`), and Arboris-driven A725 metabolic re-specialization.
- `crystallize.om`: `ΩIR v2` `SLAB` protection (`SLAB_IMMUTABLE`, `SLAB_MUTABLE_ALARMED` with rollback, `SLAB_SHARDED`), `ORACLE` dual-path execution with out-of-domain alarm fallback, and bottom-up observational-equivalence neural crystallizer compiling discovered skills directly to native AArch64 and register-allocated x86-64 ELFs.
- `gate.om`: Pure seeded OM-2 verification gate (`NG-TARGET-GATE PASS checks=73 controls=10`, plus live `ca64` / `cx64` crystallized ELF emission).

## 4. Roadmap Status (All 4 Steps Implemented & Verified)

1. **Step 1 (DONE — `b2ac40d55`):** Unified `TargetDesc`, shared IPRA/RegAlloc, 4-ISA table-driven ISel & encoders, proof-gated realization cache.
2. **Step 2 (DONE — `0d590048e`):** SM121 runtime shape partial evaluation (`M=1 / 4 / 512`), Antibody `#14` verification, and orthogonal AArch64/x86-64/RV64 ELF64 container emitter.
3. **Step 3 (DONE):** Live Realization Cache ↔ `QDI_WTBL` dispatch fabric (`fabric.om`) + `apu-gb10` heterogeneous routing + Arboris-triggered A725 background specialization.
4. **Step 4 (DONE):** `ΩIR v2` `SLAB` + `ORACLE` neural crystallization loop (`crystallize.om`), verified live on Spark (`CRYST_A64_NATIVE_EXIT=36`, `CRYST_X64_QEMU_EXIT=36`).
