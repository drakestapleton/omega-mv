# Omegese profile OM-3: additions after the OM-2 freeze

Status: PROPOSED (draft omega-mv#1008, 2026-10-31). Not frozen, not reviewed by the #599
language-evolution coordinator. `spec/omegese-om2.md` is frozen and says "A change after freeze needs
`omegese-om3.md`"; this file is where such changes are written. It is additive to
`spec/omegese-om2.md`, its errata and `docs/one_layer/OMEGESE.md`, which stay normative for everything
not stated here.

## 0. Opt-in and compatibility

- Each addition below names the units it applies to. Section 1 applies to units whose first line that
  is not a `note` is `om2`; this draft adds no `om3` line. Whether later additions need their own
  opt-in line is open.
- **C1 and C2 of OM-2 still hold.** Every OM-1 unit keeps its meaning, error code and line, and the
  frozen C2 manifest compiles byte-identically. An addition may only turn an OM-2 refusal into an
  accepted unit; it never changes the output of a unit that compiles today.
- **C3 still holds.** The compiler source stays inside om4's language and om4's function limit.

## 1. Host words in function mode (#1008)

- An OM-2 function unit (first line `om2`, no `fn main`) may use the host words `fopen`, `fclose`,
  `fstat`, `stat`, `lstat`, `getuid`, `geteuid`, `getgid` and `getegid` (OMEGESE.md section 10) on
  AArch64, with their program-mode meaning and machine code.
- The same units may use the clocks `monons`, `realns` and `sleepns` and the device words `devctl`,
  `mapnew`, `mapdrop`, `mapread`, `mapwrite`, `devcall`, `uvmctl`, `mapaddr`, `mapget`,
  `mapset`, `maphold` and `mapbind` (`seed/host/MAPPING.md`). Function-mode entry31
  is a data pointer to a32-byte capacity/generation header followed by1..4098
  32-byte owned slots; handles have13 low slot bits. The bridge supplies an
  explicit context with disjoint generation ranges and serializes its calls.
  Fixed bind can replace only the whole owned PROT_NONE reservation; failure
  unmaps/retires the token if cleanup succeeds. Cleanup failure traps3 with a
  quarantined owner: bind/read/write refuse; mapaddr/drop remain available,
  and destroy stays busy until drop succeeds. Neither outcome promises to
  preserve a reservation. An absent table pointer may fault, not status34.
- **Context ABI revision is DRAFT and requires Drake approval before merge.**
  It supersedes the unmerged#1040 raw128-slot function-mode format, not an
  accepted frozen OM-2 feature. The bridge must reject incompatible mapping
  compiler/runtime fingerprints. Program-mode raw128 slots/eight slot bits,
  frozen C2 manifest, pure and file/identity units stay unchanged.
- Every other host word in function mode, any host word in an OM-1 function unit, and any host word for
  another target is error 9.
- These words do not form a sandbox: a caller that embeds such a unit grants it the file and identity
  view (and, for the device words, the ioctl and mapping view) of its own process, so the omega-bridge refuses a unit that names one unless the caller opts in.
- Gate: `seed/omc/om2/fnhost/fnhost.cases` with the mutants in `seed/omc/om2/fnhost/mutants.cases`,
  run by `seed/host/check.sh`.

## 2. Zero-Pointer Linear Silicon Capability & Hardware-Fence Profile (`om3`, Strand 5 Aegis)

Added 2026-11-26 in response to RCCA `evidence/RCCA-SPARK-DMA-UAF-20261126/` (unified-memory GB10
GPU DMA use-after-free in legacy C `aien_gpu.ko` that overwrote Linux VFS `inode_cache` slab memory
with raw IEEE-754 `f32` tensor data).

- **Opt-in header:** A unit whose first line is `om3` opts into the Zero-Pointer Linear Silicon
  Capability & Hardware-Fence profile. `seed/out/omc` (`om2`, SHA-256
  `85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`) stays byte-for-bit frozen and
  untouched; Strand 5 (`seed/helix/strand5_aegis/om3_aegis.om`, built on `@ng` + `ΩIR v2` +
  `OMEGA-MEMO`) verifies every `om3` unit statically, memoizes the cryptographic proof certificate
  in `OMEGA-MEMO` (`OMEM` v1), and erases all capability directives into zero-runtime-overhead `om2`
  for `@ng front-ir -> @ng opt -> @ng a64` or `seed/out/omc` compilation.
- **Four Compile-Time Silicon Safety Laws (0 runtime instructions on hot paths):**
  1. `NO_RAW_PTR` (`OM3_ERR_RAW_PTR = 101`): Raw pointer casts, untyped address arithmetic, and
     raw load/store escape hatches (`fwld`, `fwst`, `rawptr`, `unsafe_ptr`, `ptr_cast`, `dma_addr`)
     are statically refused.
  2. `DISJOINT_DOMAINS` (`OM3_ERR_VA_OVERLAP = 102`, `OM3_ERR_DOMAIN_ALIEN = 110`): Every `@region`
     belongs to a single exclusive hardware domain (`1=CPU_HOST`, `2=CPU_KERNEL_SLAB`,
     `3=GPU_DEVICE_DMA`, `4=GPU_PT_GMMU`, `5=MMIO_BAR0`, `6=SHARED_UNCACHED`). Physical ranges
     across distinct domains and GPU virtual-address mappings across ALL user and kernel buffers
     (`@map`) MUST be pairwise disjoint; `DOM_CPU_KERNEL_SLAB` can never be GPU-mapped or targeted
     by GPU DMA.
  3. `DMA_FENCE_LINEAR` (`OM3_ERR_MISSING_UNMAP = 104`, `OM3_ERR_MISSING_TLB = 105`,
     `OM3_ERR_UNFENCED_DMA = 106`, `OM3_ERR_VMA_LEAK = 107`, `OM3_ERR_USE_AFTER_RECLAIM = 108`,
     `OM3_ERR_DOUBLE_RECLAIM = 109`): Reclaiming a GPU-mapped region back to host memory (`@reclaim`)
     statically requires the complete linear hardware transition sequence:
     `@unmap` (PTEs cleared) -> `@tlbinval` (GMMU TLB invalidated) -> `@fence_drain EPOCH` (in-flight
     GPU compute/copy epoch drained) -> `@vma_revoke` (userspace VMA pins == 0) -> `@reclaim`.
     Skipping any step is a compile-time refusal.
  4. `SPEED_LIMIT_ZERO_RT` (`OM3_ERR_OOB_STATIC = 103`): Every `@access NAME OFF LEN` proves
     `LEN > 0`, `OFF + LEN` non-wrapping, and `OFF + LEN <= SIZE` at compile time, then erases all
     metadata before codegen so the emitted AArch64 / SM121 machine code runs at 100% hardware speed
     with zero runtime capability tags, reference counts, or bounds branches.
- **Machine-checked soundness:** `seed/helix/proofs/Om3MemorySafety.lean` (Lean 4.36.0, 0 `sorry`,
  standard axioms only) proves global domain disjointness, GPU/kernel VA non-overlap, full 4-step
  fence necessity, and explicit negative-control counterexamples reproducing the 2026-11-26 Spark
  `aien_gpu.ko` crash bug.
- **Gate:** `sh seed/helix/strand5_aegis/strand5_verify.sh` and `sh seed/helix/hive_shield/hive_shield_gate.sh`.
