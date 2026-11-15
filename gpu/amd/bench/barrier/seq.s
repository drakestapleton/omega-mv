// gfx942 barrier encodings for the persistent-kernel micro-benchmark.
// Data, not a kernel. The Omega gate feeds this file to:
//   llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding
// and requires the bytes to match seq.enc.
//
// Sequences are the GFX942 rows of the table "AMDHSA Memory Model Code Sequences
// GFX940, GFX941, GFX942" in LLVM AMDGPUUsage at llvmorg-20.1.0
// (llvm/docs/AMDGPUUsage.rst, section "Memory Model GFX942").
// Release puts buffer_wbl2 first, then s_waitcnt, then the atomic.
// Acquire puts the atomic, then s_waitcnt vmcnt(0), then buffer_inv.
//
// The agent-release step 3 in that table is "buffer/global/flat_atomic sc1=1"
// with no sc0. CDNA3 ISA 9.1.10.2 says SC0=1 returns the previous value and
// SC1=0 is device scope. A sense-reversing barrier needs the ticket, so the
// ticket lines below set sc0 and are not the LLVM step-3 spelling. Both are
// assembled here. Do not copy the branch offsets at the bottom as a spin loop.

.text

// atomicrmw release, agent, global. LLVM steps 1, 2, 3.
buffer_wbl2 sc1
s_waitcnt vmcnt(0) lgkmcnt(0)
buffer_atomic_add v0, off, s[0:3], 0 sc1

// atomicrmw release, system, global. LLVM steps 1, 2, 3.
buffer_wbl2 sc0 sc1
s_waitcnt vmcnt(0) lgkmcnt(0)
buffer_atomic_add v0, off, s[0:3], 0 sc0 sc1

// atomicrmw acquire, agent, global. LLVM steps 1, 2, 3.
buffer_atomic_add v0, off, s[0:3], 0
s_waitcnt vmcnt(0)
buffer_inv sc1

// atomicrmw acquire, system, global. LLVM steps 1, 2, 3.
buffer_atomic_add v0, off, s[0:3], 0 sc1
s_waitcnt vmcnt(0)
buffer_inv sc0 sc1

// Ticket atomics. ISA SC0 returns the pre-op value. SC1=0 device, SC1=1 system.
// NT=1 is "no Allocate" in the last-level cache (MALL). NT=0 allocates.
buffer_atomic_add v0, off, s[0:3], 0 sc0
buffer_atomic_add v0, off, s[0:3], 0 sc0 nt
buffer_atomic_add v0, off, s[0:3], 0 sc0 sc1
buffer_atomic_add v0, off, s[0:3], 0 sc0 nt sc1

// CDNA3 ISA 8.2.5 S_MEMREALTIME. Fixed 100 MHz, not the core clock.
s_memrealtime s[0:1]
s_memrealtime s[2:3]
s_waitcnt lgkmcnt(0)

// 64-bit unsigned compare pieces (now in s[2:3], deadline in s[4:5]).
// Offsets below reach the two s_endpgm labels in THIS fragment only.
// A device spin branches back to s_memrealtime instead of the second s_endpgm.
s_cmp_lt_u32 s3, s5
s_cbranch_scc1 5
s_cmp_eq_u32 s3, s5
s_cbranch_scc0 2
s_cmp_lt_u32 s2, s4
s_cbranch_scc1 1
s_endpgm
s_endpgm
