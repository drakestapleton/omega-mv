# Persistent-kernel barrier, gfx942

Host-side micro-benchmark for one question: what does a grid-wide barrier inside a persistent kernel cost on an MI300X, compared with the AQL dispatch barrier it would replace.

Decode currently issues about 1,126 barrier-ordered AQL dispatches per token, measured at about 1.54 µs each. Those two figures are the reason this bench exists. This tree did not remeasure them. A persistent megakernel would replace the dispatches with in-kernel grid barriers. Eighteen kernels are not worth porting until that barrier's cost is known on a warm L2 and after the L2 has been flushed.

This directory does not submit work to a GPU. Every timing it prints is `source=model` or `NOT_RUN`.

## The two arms

Same math, same shapes. The fixture is four workgroups, each with a vector of four binary32 values, an FP8 E4M3FNUZ matrix of 4×4, and four scales. Production RMSNorm5120 is the motivation, not the fixture. N = 1000.

Arm A is the dispatch arm. Each iteration is an RMSNorm packet then an FP8 GEMV packet, both with the HSA barrier bit set. That is 2,000 packets. The header word is the one `gpu/amd/kfd/aql.om` documents: type 2, barrier at bit 8, acquire fence scope at bits 9..10, release fence scope at bits 11..12 (NONE 0, AGENT 1, SYSTEM 2). The gate adds the header of all 2,000 packets and checks the sum. Agent scope sums to 5636000. System scope sums to 10756000. Arm B is one packet, not 2,000. Its grid is the device's CU count, read at run time. The number 304 does not appear in the launch path.

Arm B is the persistent arm. One launch. The grid is one workgroup per CU. The body is N iterations of RMSNorm, grid barrier, FP8 GEMV, grid barrier.

The numeric check does not execute either kernel. Arm A and arm B are the same phased schedule in this program: every group finishes RMSNorm, then every group runs GEMV. That is the happens-before of a correct barrier, AQL or in-kernel. Both match a third run of the same functions, bit for bit, after 1,000 iterations. The GEMV reduction is `fpfma` from `gpu/amd/gfx942/exec/fma.om` (exact binary32 FMA, ascending k, accumulator starts at +0). RMSNorm is ascending k, sum of squares starts at +0, mean is that sum divided by 4, then `1/sqrt(mean)` with the host `fsqrt` and `div`. Epsilon is 0. The fixture values are 1 and 4 and 0.25, which are exact in binary32, so the host sqrt is not being asked to round. This is not a claim about `v_sqrt_f32` on gfx942.

A mutant runs GEMV in the same group immediately after that group's RMSNorm, with the other groups' rows still the canonical qNaN `0x7fc00000`. `fpfma` returns that NaN. The mutant must not match. It does not.

## The barrier

Sense-reversing counter. Each group carries a local sense. On arrival it flips that sense, atomically adds 1, and the last arriver (ticket = groups−1) stores 0 back to the counter and publishes the new sense. Everyone else spins until the published sense matches. The next barrier uses the opposite sense, so a group cannot observe the previous generation.

The release and acquire instructions are the GFX942 rows of the table "AMDHSA Memory Model Code Sequences GFX940, GFX941, GFX942" in LLVM's AMDGPUUsage at tag llvmorg-20.1.0 (`llvm/docs/AMDGPUUsage.rst`, section "Memory Model GFX942"):

https://github.com/llvm/llvm-project/blob/llvmorg-20.1.0/llvm/docs/AMDGPUUsage.rst

Release, agent, global, in the table's order:

1. `buffer_wbl2 sc1`
2. `s_waitcnt vmcnt(0) lgkmcnt(0)` (the table says to drop `lgkmcnt(0)` for TgSplit and for OpenCL; this fragment keeps it)
3. `buffer_atomic_add` with `sc1` and no `sc0`

Release, system, is the same with `sc0 sc1` on both the writeback and the atomic. Acquire, agent, is a bare atomic, then `s_waitcnt vmcnt(0)`, then `buffer_inv sc1`. Acquire, system, sets `sc1` on the atomic and `sc0 sc1` on `buffer_inv`.

`seq.s` is that text. `seq.enc` is the byte pin. The gate runs

```
llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding gpu/amd/bench/barrier/seq.s
```

and requires every encoding to match `seq.enc`. The pin was taken from Ubuntu's llvm-mc 18.1.3, the same LLVM the `.isa` comments name. A missing `llvm-mc-18` fails the gate. It is not skipped.

The table's agent-release step 3 is `sc1` with no `sc0`. CDNA3 ISA 9.1.10.2 says SC0 = 1 returns the previous value and SC1 = 0 is device scope (SC1 = 1 is system). A ticket needs the previous value, so the barrier's atomic is `buffer_atomic_add ... sc0` for device scope, not the table's step 3. Both spellings are in `seq.s`. The gate checks that they differ by two bits (SC0 set, SC1 clear). `buffer_wbl2` and `buffer_inv` stay on the table's bits: one bit, SC0, between the agent and system forms.

From the bytes llvm-mc emitted, SC0 is bit 14 of the first dword, SC1 is bit 15, and NT is bit 17. The ISA's Table 40 lists those fields as one bit each and does not give the positions. The positions above are the assembler's, checked by the one-bit differences, not a reading of the field table.

## Scope and MALL

Two scopes, chosen together on the AQL fences and on `buffer_wbl2` / `buffer_inv` / the atomic:

| | agent (device) | system |
| --- | --- | --- |
| AQL acquire / release | 1 | 2 |
| `buffer_wbl2` / `buffer_inv` | `sc1` | `sc0 sc1` |
| ticket atomic | `sc0` | `sc0 sc1` |

MALL is the 256 MB AMD Infinity Cache on the MI300X IODs. The CDNA3 white paper ("AMD CDNA 3 Architecture", AMD, the MI300 series paper) says each XCD's 38 CUs share a 4 MB L2, a processor has up to 8 XCDs, and the Infinity Cache is 256 MB (8 HBM stacks × 16 channels × 2 MB). It is a memory-side cache, holds no dirty lines, and is not in the coherency protocol. The ISA's NT bit on an atomic is "no Allocate" in the last-level cache. `sc0 nt` versus `sc0` is that bit and nothing else (the gate checks a one-bit difference). Whether NT keeps the atomic out of the Infinity Cache is the measurement this bench is for. It was not measured here.

## Stamps

CDNA3 ISA, 5 August 2025, section 8.2.5 `S_MEMREALTIME`:

> The time value is from a constant 100MHz clock (not affected by power modes or core clock frequency changes).

https://www.amd.com/content/dam/amd/en/documents/instinct-tech-docs/instruction-set-architectures/amd-instinct-mi300-cdna3-instruction-set-architecture.pdf

Not the 25 MHz clock in the CDNA2 manual, and not a core clock. One tick is 10 ns when the counter is that clock. `s_memrealtime s[0:1]` assembles to `00 00 94 c0 00 00 00 00`. On gfx942 this is an 8-byte scalar-memory encoding. The ISA section is the one that states the frequency.

The gate's samples are not those ticks. Each modeled barrier writes one cost per group: group `g` of 4 pays `3-g` model ticks (the first arriver waits for the other three), and the cold pass adds 1000. The 1000 is a label so the cold distribution cannot be confused with the warm one. It is not a flush latency. The stats line says `source=model`. Median of an even count is the truncating average of the two central samples. p99 is nearest-rank: `rank = (n*99+99)/100`, index `rank-1`. For the 8,000 model samples that is index 7919.

Cold, when a device is actually programmed, means the kernel loads and stores a device buffer between iterations so the per-XCD L2 and the Infinity Cache are evicted. The size is `2 * (num_xcc * 4 MiB + 256 MiB)`, with `num_xcc` from KFD and the two cache sizes from the white paper above. It is computed only when `gfx_target_version` is 90402 and `num_xcc` was read. Otherwise `cold_bytes=NOT_RUN`. The formula check for 8 XCDs is 603979776 bytes (576 MiB). The flush itself is `flush=NOT_RUN` in every run this program can do, because nothing is submitted.

## Occupancy, and what would wedge the machine

AMD compute does not preempt a wave that is spinning on a device-scope atomic. If the grid has more workgroups than the device can hold at once, the late groups never start, the resident groups wait at the barrier, and the device stays that way until something resets it. That is the hang.

The counter uses the LLVM 18.1.3 rules in `llvm/lib/Target/AMDGPU/Utils/AMDGPUBaseInfo.cpp` for gfx942 (it is GFX9.4, and `isGFX90A` is true, so the GFX9 "10 waves" path is not the one that applies):

- `getMaxWavesPerEU` = 8
- `getEUsPerCU` = 4
- VGPR file 512, alloc granule 8
- SGPR file 800, addressable 102, alloc granule 16
- LDS 65536
- 16 barriers per CU, and a one-wave workgroup does not take a barrier slot
- waves per workgroup = ceil(workgroup size / 64)

Waves per EU is the minimum of the VGPR limit, the SGPR limit, and `max_waves_per_simd` from KFD, and that last number is itself capped at 8 because that is the architectural file. Groups per CU is waves per CU divided by waves per group, then cut by the barrier cap and by LDS. Resident groups = groups per CU times CU count. CU count is `simd_count / simd_per_cu`. A remainder is refused. A zero query is refused. 304 is not filled in.

The plan's kernel budget is 32 VGPRs, 32 SGPRs, no LDS, workgroup 64. That budget is declared here. It is not the resource usage of a compiled kernel, because this program does not compile one. If a real kernel needs more, the check has to be rerun with those counts. The gate checks the function: 32/32/0/64 on one CU with 4 SIMDs and 8 waves gives 32 resident groups; a grid of 33 aborts; 512 VGPRs gives 4; 32,768 bytes of LDS gives 2; 103 SGPRs gives 0; a 128-thread group gives 16.

The device path sets the persistent grid to the CU count it just computed and aborts when that grid is larger than the resident capacity. Abort means it prints `fit=abort` and does not describe a launch. It still does not submit.

The watchdog, for a kernel that does get submitted later: the spin reads `s_memrealtime` and leaves if the counter has passed a deadline carried in the kernarg. Two seconds is 200,000,000 ticks of the 100 MHz clock. The host should also stop waiting on the completion signal (five seconds is the allowance suggested here) and print `TIMEOUT`. This program does not call `amdgpu` gpu_recover. A hang in the command processor, before any wave reaches the compare, will not notice the deadline. That one still belongs to an operator.

`seq.s` contains the compare and two `s_endpgm`s so the branch offsets have somewhere to land. Those offsets are for that fragment. A real spin branches back to `s_memrealtime`, and the timeout path stores a flag before it ends. Copying the fragment in as the spin would end the wave on the first compare.

## What a run prints

From the repo root, on this x86 VM and on an x86 host in front of an MI300X:

```
{ printf 'target x86linux\nom2\n'; cat gpu/amd/gfx942/exec/fma.om gpu/amd/bench/barrier/gate.om; } | qemu-aarch64-static seed/out/omc > /tmp/barrier-gate && chmod +x /tmp/barrier-gate && /tmp/barrier-gate
```

`seed/out/omc` is the aarch64 compiler from the 408-byte seed. On an aarch64 host, drop `qemu-aarch64-static`. The gate is an x86 binary either way, so `llvm-mc-18` has to be on that host. An optional argument replaces `/sys/class/kfd/kfd/topology/nodes/` and must end with a slash. It exists so the parser can be fed a fixture. It does not make a run into a hardware run.

The summary line is `OMEGA-GPU-AMD-BARRIER PASS llvm-mc=PASS hardware=NOT_RUN`. `hardware=NOT_RUN` stays on a machine that has a card. KFD properties are read and printed (CU count, `num_xcc`, `fw_version`, `max_engine_clk_fcompute`). Current clocks are `NOT_RUN`: the render minor is not a card index, and guessing `card0` would be a guess. ROCm is the first line of `/opt/rocm/.info/version` or `version-dev`, else `NOT_RUN`. The kernel string is `/proc/sys/kernel/osrelease`.

`tests/gates/run.sh` was not given a step. That script is on the operator list in `AGENTS.md`. The program above is the run.
