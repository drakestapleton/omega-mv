# What Omega cannot say yet, and the closest program that still checks

The bench needs four things the language and the gfx942 executor do not have. This file is the proposal. `gate.om` is the closest program that can be run today. It does not pretend the missing operations happened.

## 1. `s_memrealtime`

No Omega word reads the fixed 100 MHz real-time counter. The executor in `gpu/amd/gfx942/exec/main.om` has no scalar-memory realtime opcode; an unrecognised encoding exits 66.

Closest: `seq.s` contains `s_memrealtime s[0:1]` and `s_memrealtime s[2:3]`, and the gate checks both encodings against `llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding`. The samples the stats line reduces are a host counter, printed `source=model`. A device run has to keep that label off the model numbers and print `timestamps=NOT_RUN` until a wave actually stores the counter.

Proposal: one word, `tickdst`, that lowers to `s_memrealtime` plus `s_waitcnt lgkmcnt(0)` and returns the pair as a ulong. The frequency is the ISA's 100 MHz, not a value the compiler invents and not a value the program measures.

## 2. Scoped atomics, `buffer_wbl2`, `buffer_inv`

No Omega word emits a MUBUF atomic with SC0, SC1 and NT, and none emits `buffer_wbl2` or `buffer_inv`. The executor does not execute atomics. A barrier written as a loop of ordinary loads will not order work across XCDs, and the executor runs one wave to `s_endpgm`, so it cannot host the other waves a grid barrier waits for.

Closest: the memory-model sequences and the ticket atomics live in `seq.s`. The gate checks the bytes, and checks that agent versus system is one bit on the writeback and the invalidate, that NT is one other bit, and that the ticket form differs from the LLVM agent step 3 by two bits. The ordering check is a host model of the sense-reversing counter: last arriver publishes the sense, an incomplete set of arrivals hits a deadline instead of spinning. The mutant that skips the phase produces NaNs. None of that is a device barrier.

Proposal: a barrier statement whose arguments are the scope (`agent` or `system`), the NT bit, the group count, and a deadline in counter ticks. Lowering is fixed:

- release: `buffer_wbl2` with the table's bits, then `s_waitcnt vmcnt(0) lgkmcnt(0)`, then `buffer_atomic_add` with SC0 set so the ticket comes back, SC1 clear for agent and set for system, NT as requested
- spin on the sense flag until it matches or `s_memrealtime` passes the deadline
- acquire: `s_waitcnt vmcnt(0)`, then `buffer_inv` with the table's bits

The LLVM table's agent step 3 does not return the old value. The statement must not lower to that spelling and then read a destination the instruction did not write. The encodings stay pinned by the same llvm-mc check.

## 3. Occupancy

No Omega word returns the resident workgroup capacity of a kernel. KFD's sysfs is readable with `fopen` and `read`, which is what `gpu/amd/kfd/launch/device.om` already does, and what this gate does.

Closest: `groups` in `gate.om` applies the LLVM 18.1.3 gfx942 limits (8 waves per EU, 4 SIMDs per CU, 512 VGPRs granule 8, 102 addressable SGPRs granule 16, 64 KiB LDS, 16 barriers, one-wave groups free of the barrier cap). CU count is `simd_count / simd_per_cu` from the topology file. A remainder, a missing file, or a grid larger than resident capacity aborts. The number 304 is not a fallback.

Proposal: the launch word takes the kernel's VGPR, SGPR, LDS and workgroup size, reads the same topology keys, and refuses the ioctl when the grid does not fit. The refusal is a return, before any packet is written. The limits that are architectural constants stay cited; the limits KFD reports (`simd_count`, `simd_per_cu`, `max_waves_per_simd`, `num_xcc`) stay reads.

## 4. Submitting the persistent grid

The KFD launcher under `gpu/amd/kfd/launch/` submits ordinary AQL dispatches. This bench does not call it. A persistent kernel with a grid barrier is one packet plus code the executor cannot run. Submitting an untested spin is how the hang in the README happens: non-preemptible waves, a counter that never reaches the group count, a device that waits until reset.

Closest: the gate builds the one packet and the 2,000-packet checksum, prints `hardware=NOT_RUN reason=no-submit`, and returns. Reading topology is not a submit. Printing `kfd_fw_version` and `kfd_max_engine_clk_fcompute` is not a clock measurement. `current_clock` stays `NOT_RUN`.

Proposal: the launch word from item 3, plus a completion-signal wait with its own deadline, plus an explicit result of `TIMEOUT` when the signal does not arrive. The word does not reset the GPU. A command-processor hang that never enters the wave is still an operator's `gpu_recover`, and the program should say so rather than issue it.

Until those four exist, a run of `gate.om` is the check: the math, the packet headers, the occupancy abort, the model of the sense-reversing counter, the deadline, and the bytes of the sequences. It is not the measurement.
