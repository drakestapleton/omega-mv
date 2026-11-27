/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/Om3MemorySafety.lean

  Machine-checked Lean 4.36.0 soundness proofs for Strand 5 (The Aegis) & OM-3
  Zero-Pointer Linear Silicon Capability and 4-Step Hardware DMA-Fence Profile.

  Exact 1:1 model of `seed/helix/strand5_aegis/om3_aegis.om` and `spec/omegese-om3.md` §2.
  Born from RCCA `evidence/RCCA-SPARK-DMA-UAF-20261126/` (legacy C `aien_gpu.ko` DMA UAF
  that overwrote Linux VFS `inode_cache` slab memory with raw f32 tensor data).

  ZERO sorry, ZERO warnings, ZERO extra axioms (standard Lean 4 core only).
-/

namespace Om3MemorySafety

/-- Exclusive hardware memory domains (mirrors AE_DOM_* in om3_aegis.om). -/
inductive Domain where
  | cpuHost        -- 1: CPU host DRAM
  | cpuKernelSlab  -- 2: Linux/Aienux kernel slab (NEVER GPU-mappable or DMA-targetable)
  | gpuDeviceDma   -- 3: GPU device DMA buffer
  | gpuPtGmmu      -- 4: GPU page table / GMMU
  | mmioBar0       -- 5: MMIO BAR0 register aperture
  | sharedUncached -- 6: Coherent uncached shared buffer
  deriving DecidableEq, Repr

/-- Linear GPU page-table & TLB state (mirrors AE_MAP_* in om3_aegis.om). -/
inductive MapState where
  | unmapped    -- 0: AE_MAP_NONE
  | mapped      -- 1: AE_MAP_MAPPED (PTEs live)
  | pteCleared  -- 2: AE_MAP_PTE_CLEARED (PTEs cleared, TLB still hot)
  | tlbFlushed  -- 3: AE_MAP_TLB_FLUSHED (GMMU TLB invalidated)
  deriving DecidableEq, Repr

/-- Linear region lifetime state (mirrors AE_ST_* in om3_aegis.om). -/
inductive LifeState where
  | live       -- 1: AE_ST_LIVE
  | reclaimed  -- 2: AE_ST_RECLAIMED
  deriving DecidableEq, Repr

/-- A capability-governed memory region (zero raw pointers). -/
structure Region where
  rid     : Nat
  dom     : Domain
  pbase   : Nat
  psize   : Nat
  gva     : Nat
  gvlen   : Nat
  mstate  : MapState
  epoch   : Nat
  drained : Nat
  vmaPins : Nat
  lstate  : LifeState
  deriving DecidableEq, Repr

/-- 64-bit unsigned address space bound (2^64). -/
def U64_LIMIT : Nat := 2 ^ 64

/-- Half-open interval [a0, a0 + al) and [b0, b0 + bl) are disjoint. -/
def intervalsDisjoint (a0 al b0 bl : Nat) : Prop :=
  al = 0 ∨ bl = 0 ∨ a0 + al ≤ b0 ∨ b0 + bl ≤ a0

/-- Decidable overlap predicate (exact mirror of `ae_ovl` in om3_aegis.om). -/
def intervalsOverlap (a0 al b0 bl : Nat) : Bool :=
  if al == 0 || bl == 0 then false
  else decide (a0 < b0 + bl) && decide (b0 < a0 + al)

theorem overlap_false_iff_disjoint (a0 al b0 bl : Nat) :
    intervalsOverlap a0 al b0 bl = false ↔ intervalsDisjoint a0 al b0 bl := by
  unfold intervalsOverlap intervalsDisjoint
  by_cases ha : al = 0
  · simp [ha]
  · by_cases hb : bl = 0
    · simp [ha, hb]
    · by_cases h1 : a0 < b0 + bl
      · by_cases h2 : b0 < a0 + al
        · simp [ha, hb, h1, h2]
        · simp [ha, hb, h1, h2]
          exact Or.inl (Nat.le_of_not_lt h2)
      · simp [ha, hb, h1]
        exact Or.inr (Nat.le_of_not_lt h1)

/-- OM-3 linear silicon capability instructions. -/
inductive Action where
  | allocRegion  (rid : Nat) (dom : Domain) (pbase psize : Nat)
  | gpuMap       (rid : Nat) (va vlen : Nat)
  | vmaPin       (rid : Nat)
  | gpuSubmit    (rid : Nat) (ep : Nat)
  | staticAccess (rid : Nat) (off alen : Nat)
  | gpuUnmap     (rid : Nat)
  | tlbInval     (rid : Nat)
  | fenceDrain   (rid : Nat) (ep : Nat)
  | vmaRevoke    (rid : Nat)
  | reclaim      (rid : Nat)
  deriving DecidableEq, Repr

/-- Machine state: list of regions with unique IDs. -/
abbrev State := List Region

def findReg (s : State) (rid : Nat) : Option Region :=
  s.find? (fun r => r.rid == rid)

def updateReg (s : State) (rid : Nat) (f : Region → Region) : State :=
  s.map (fun r => if r.rid == rid then f r else r)

/-- Single-step fail-closed verifier semantics (1:1 mirror of om3_aegis.om). -/
def step (s : State) (a : Action) : Option State :=
  match a with
  | .allocRegion rid dom pbase psize =>
    if psize == 0 || pbase + psize >= U64_LIMIT then none
    else if (findReg s rid).isSome then none
    else if s.any (fun r => r.lstate == .live && intervalsOverlap pbase psize r.pbase r.psize) then none
    else some ({ rid := rid, dom := dom, pbase := pbase, psize := psize,
                 gva := 0, gvlen := 0, mstate := .unmapped,
                 epoch := 0, drained := 0, vmaPins := 0, lstate := .live } :: s)

  | .gpuMap rid va vlen =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live then none
      else if r.dom == .cpuKernelSlab then none
      else if r.mstate != .unmapped then none
      else if va == 0 || vlen == 0 || va + vlen >= U64_LIMIT || vlen > r.psize then none
      else if s.any (fun o => o.lstate == .live && o.gvlen > 0 && intervalsOverlap va vlen o.gva o.gvlen) then none
      else some (updateReg s rid (fun x => { x with gva := va, gvlen := vlen, mstate := .mapped }))

  | .vmaPin rid =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.dom == .cpuKernelSlab then none
      else some (updateReg s rid (fun x => { x with vmaPins := x.vmaPins + 1 }))

  | .gpuSubmit rid ep =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.dom == .cpuKernelSlab || r.mstate != .mapped || ep <= r.epoch then none
      else some (updateReg s rid (fun x => { x with epoch := ep }))

  | .staticAccess rid off alen =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live then none
      else if (r.dom == .gpuDeviceDma || r.dom == .gpuPtGmmu) && r.mstate != .mapped then none
      else if alen == 0 || off + alen >= U64_LIMIT || off + alen > r.psize then none
      else some s

  | .gpuUnmap rid =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .mapped then none
      else some (updateReg s rid (fun x => { x with mstate := .pteCleared }))

  | .tlbInval rid =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .pteCleared then none
      else some (updateReg s rid (fun x => { x with mstate := .tlbFlushed }))

  | .fenceDrain rid ep =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .tlbFlushed || ep < r.epoch then none
      else some (updateReg s rid (fun x => { x with drained := ep }))

  | .vmaRevoke rid =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.vmaPins == 0 then none
      else some (updateReg s rid (fun x => { x with vmaPins := x.vmaPins - 1 }))

  | .reclaim rid =>
    match findReg s rid with
    | none => none
    | some r =>
      if r.lstate != .live then none
      else if r.mstate == .mapped || r.mstate == .pteCleared then none
      else if r.epoch > r.drained then none
      else if r.vmaPins > 0 then none
      else some (updateReg s rid (fun x => { x with lstate := .reclaimed, gva := 0, gvlen := 0 }))

/-- Multi-step execution of a full OM-3 capability trace. -/
def runTrace (s : State) (acts : List Action) : Option State :=
  match acts with
  | [] => some s
  | a :: rest =>
    match step s a with
    | none => none
    | some s' => runTrace s' rest

-- ==================== GLOBAL SAFETY INVARIANTS ====================

/-- Every region has bounded non-zero size, kernel-slab isolation, and DMA integrity. -/
def RegionSafe (r : Region) : Prop :=
  r.psize > 0 ∧
  r.pbase + r.psize < U64_LIMIT ∧
  (r.dom = .cpuKernelSlab → r.mstate = .unmapped ∧ r.gvlen = 0 ∧ r.epoch = 0 ∧ r.vmaPins = 0) ∧
  (r.lstate = .reclaimed →
    r.mstate ≠ .mapped ∧ r.mstate ≠ .pteCleared ∧ r.drained ≥ r.epoch ∧ r.vmaPins = 0 ∧ r.gvlen = 0)

/-- Pairwise physical & GPU VA disjointness across distinct live regions. -/
def PairSafe (r1 r2 : Region) : Prop :=
  r1.rid ≠ r2.rid →
  r1.lstate = .live →
  r2.lstate = .live →
  intervalsDisjoint r1.pbase r1.psize r2.pbase r2.psize ∧
  (r1.gvlen > 0 → r2.gvlen > 0 → intervalsDisjoint r1.gva r1.gvlen r2.gva r2.gvlen)

def WellFormed (s : State) : Prop :=
  (∀ r ∈ s, RegionSafe r) ∧
  (∀ r1 ∈ s, ∀ r2 ∈ s, PairSafe r1 r2)

theorem empty_wellFormed : WellFormed [] := by
  constructor <;> simp

-- ==================== KEY SECURITY THEOREMS ====================

/-- Theorem 1 (4-Step Linear Fence Necessity):
    Reclaiming a region back to host memory is IMPOSSIBLE unless PTEs are unmapped,
    GMMU TLB is flushed, all in-flight GPU DMA epochs are drained, and all user VMAs are revoked. -/
theorem reclaim_requires_full_4step_fence (s s' : State) (rid : Nat)
    (h : step s (.reclaim rid) = some s') :
    ∃ r, findReg s rid = some r ∧
      r.lstate = .live ∧
      r.mstate ≠ .mapped ∧
      r.mstate ≠ .pteCleared ∧
      r.drained ≥ r.epoch ∧
      r.vmaPins = 0 := by
  unfold step at h
  cases hf : findReg s rid with
  | none => simp [hf] at h
  | some r =>
    simp only [hf] at h
    split at h
    · contradiction
    · rename_i hlive
      split at h
      · contradiction
      · rename_i hmap
        split at h
        · contradiction
        · rename_i hdma
          split at h
          · contradiction
          · rename_i hvma
            simp only [bne_iff_ne, ne_eq, Bool.or_eq_true, beq_iff_eq,
              not_or, Nat.not_lt] at hlive hmap hdma hvma
            refine ⟨r, rfl, ?_, hmap.1, hmap.2, hdma, by omega⟩
            cases hl : r.lstate
            · rfl
            · simp [hl] at hlive

/-- Theorem 2 (Kernel-Slab Non-Interference on GPU Map & Global VA Disjointness):
    A `cpuKernelSlab` region (e.g. Linux VFS `inode_cache`) can NEVER be mapped into GPU VA space,
    and no newly mapped GPU VA can overlap any existing live region's GPU VA. -/
theorem kernel_slab_never_gpu_mapped (s s' : State) (rid va vlen : Nat)
    (h : step s (.gpuMap rid va vlen) = some s') :
    ∃ r, findReg s rid = some r ∧
      r.dom ≠ .cpuKernelSlab ∧
      ∀ o ∈ s, o.lstate = .live → o.gvlen > 0 → intervalsDisjoint va vlen o.gva o.gvlen := by
  unfold step at h
  cases hf : findReg s rid with
  | none => simp [hf] at h
  | some r =>
    simp only [hf] at h
    split at h
    · contradiction
    · split at h
      · contradiction
      · rename_i hnotk
        split at h
        · contradiction
        · split at h
          · contradiction
          · split at h
            · contradiction
            · rename_i hnoov
              refine ⟨r, rfl, ?_, ?_⟩
              · intro heq; simp [heq] at hnotk
              · intro o ho hlive hgv
                have hfalse : s.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen) = false := by
                  cases hb : s.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen)
                  · rfl
                  · exact absurd hb hnoov
                have hmem := List.any_eq_false.mp hfalse o ho
                simp only [hlive, beq_self_eq_true, Bool.true_and, decide_eq_true hgv] at hmem
                have hovf : intervalsOverlap va vlen o.gva o.gvlen = false := by
                  cases hov : intervalsOverlap va vlen o.gva o.gvlen
                  · rfl
                  · simp [hov] at hmem
                exact (overlap_false_iff_disjoint va vlen o.gva o.gvlen).mp hovf

/-- Theorem 3 (Kernel-Slab Non-Interference on GPU Submit):
    GPU compute/copy DMA can NEVER be submitted against a `cpuKernelSlab` or unmapped region. -/
theorem kernel_slab_never_dma_targeted (s s' : State) (rid ep : Nat)
    (h : step s (.gpuSubmit rid ep) = some s') :
    ∃ r, findReg s rid = some r ∧ r.lstate = .live ∧ r.dom ≠ .cpuKernelSlab ∧ r.mstate = .mapped := by
  unfold step at h
  cases hf : findReg s rid with
  | none => simp [hf] at h
  | some r =>
    simp only [hf] at h
    split at h
    · contradiction
    · rename_i hok
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, decide_eq_true_eq, not_or] at hok
      refine ⟨r, rfl, ?_, hok.1.1.2, ?_⟩
      · cases hl : r.lstate
        · rfl
        · exfalso; exact hok.1.1.1 (by simp [hl])
      · cases hm : r.mstate
        · exfalso; exact hok.1.2 (by simp [hm])
        · rfl
        · exfalso; exact hok.1.2 (by simp [hm])
        · exfalso; exact hok.1.2 (by simp [hm])

/-- Theorem 4 (Zero-Runtime-Overhead Static Bounds Soundness):
    Every statically accepted `@access` is provably in-bounds without 64-bit wraparound,
    justifying complete erasure of capability/bounds checks prior to AArch64/SM121 codegen. -/
theorem static_access_in_bounds (s s' : State) (rid off alen : Nat)
    (h : step s (.staticAccess rid off alen) = some s') :
    ∃ r, findReg s rid = some r ∧ r.lstate = .live ∧ alen > 0 ∧ off + alen < U64_LIMIT ∧ off + alen ≤ r.psize := by
  unfold step at h
  cases hf : findReg s rid with
  | none => simp [hf] at h
  | some r =>
    simp only [hf] at h
    split at h
    · contradiction
    · rename_i hlive
      split at h
      · contradiction
      · split at h
        · contradiction
        · rename_i hbnd
          simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or, bne_iff_ne, ne_eq] at hlive hbnd
          refine ⟨r, rfl, ?_, by omega, by omega, by omega⟩
          cases hl : r.lstate
          · rfl
          · exfalso; exact hlive (by simp [hl])

/-- Theorem 5 (Physical Domain Disjointness on Alloc):
    No newly allocated region can overlap the physical address range of any existing live region
    (across ANY domain — e.g. GPU DMA buffer can never overlap Linux VFS `cpuKernelSlab`). -/
theorem alloc_phys_disjoint (s s' : State) (rid : Nat) (dom : Domain) (pbase psize : Nat)
    (h : step s (.allocRegion rid dom pbase psize) = some s') :
    psize > 0 ∧ pbase + psize < U64_LIMIT ∧
    ∀ r ∈ s, r.lstate = .live → intervalsDisjoint pbase psize r.pbase r.psize := by
  simp only [step] at h
  split at h
  · contradiction
  · rename_i hsz
    split at h
    · contradiction
    · split at h
      · contradiction
      · rename_i hnoov
        simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or] at hsz
        refine ⟨by omega, by omega, ?_⟩
        intro r hr hlive
        have hfalse : s.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize) = false := by
          cases hb : s.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize)
          · rfl
          · exact absurd hb hnoov
        have hmem := List.any_eq_false.mp hfalse r hr
        simp only [hlive, beq_self_eq_true, Bool.true_and] at hmem
        have hovf : intervalsOverlap pbase psize r.pbase r.psize = false := by
          cases hov : intervalsOverlap pbase psize r.pbase r.psize
          · rfl
          · simp [hov] at hmem
        exact (overlap_false_iff_disjoint pbase psize r.pbase r.psize).mp hovf

-- ==================== CONSTRUCTIVE POSITIVE & NEGATIVE CONTROLS ====================
-- Reproduces the exact 2026-11-26 Spark `aien_gpu.ko` unified-memory crash bugs!

/-- Canonical safe GPU DMA lifecycle (all 4 linear fence steps before reclaim): ACCEPTED. -/
def safeGpuTrace : List Action := [
  .allocRegion 1 .cpuKernelSlab 0x10000000 0x100000,
  .allocRegion 2 .gpuDeviceDma  0x20000000 0x400000,
  .gpuMap      2 0x200000000 0x400000,
  .vmaPin      2,
  .gpuSubmit   2 1,
  .staticAccess 2 0 4096,
  .gpuUnmap    2,
  .tlbInval    2,
  .fenceDrain  2 1,
  .vmaRevoke   2,
  .reclaim     2
]

theorem pos_safe_gpu_lifecycle_accepted : (runTrace [] safeGpuTrace).isSome = true := by
  decide

/-- Negative Control 1 (2026-11-26 Spark crash bug): reclaim without unmap -> REFUSED. -/
theorem cex_aien_gpu_unfenced_reclaim_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .reclaim 2
    ] = none := by
  decide

/-- Negative Control 2: reclaim after unmap without GMMU TLB invalidation -> REFUSED. -/
theorem cex_aien_gpu_missing_tlb_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .gpuUnmap 2,
      .reclaim 2
    ] = none := by
  decide

/-- Negative Control 3: reclaim after TLB flush without draining GPU DMA epoch -> REFUSED. -/
theorem cex_aien_gpu_missing_fence_drain_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .gpuUnmap 2,
      .tlbInval 2,
      .reclaim 2
    ] = none := by
  decide

/-- Negative Control 4 (vm_insert_pages leak): reclaim with active user VMA pin -> REFUSED. -/
theorem cex_aien_gpu_vma_pin_leak_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .vmaPin 2,
      .gpuSubmit 2 1,
      .gpuUnmap 2,
      .tlbInval 2,
      .fenceDrain 2 1,
      .reclaim 2
    ] = none := by
  decide

/-- Negative Control 5 (agpu_vas_map_kbuf bug): user VA overlapping kernel GPU VA -> REFUSED. -/
theorem cex_aien_gpu_va_aliasing_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .allocRegion 3 .gpuDeviceDma 0x30000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuMap 3 0x200200000 0x200000
    ] = none := by
  decide

/-- Negative Control 6: use-after-reclaim (UAF access after reclaim) -> REFUSED. -/
theorem cex_aien_gpu_uaf_after_reclaim_refused :
    runTrace [] (safeGpuTrace ++ [.staticAccess 2 0 64]) = none := by
  decide

/-- Negative Control 7: GPU attempting to map Linux VFS `cpuKernelSlab` -> REFUSED. -/
theorem cex_kernel_slab_gpu_map_refused :
    runTrace [] [
      .allocRegion 1 .cpuKernelSlab 0x10000000 0x100000,
      .gpuMap 1 0x200000000 0x100000
    ] = none := by
  decide

end Om3MemorySafety

#print axioms Om3MemorySafety.reclaim_requires_full_4step_fence
#print axioms Om3MemorySafety.kernel_slab_never_gpu_mapped
#print axioms Om3MemorySafety.kernel_slab_never_dma_targeted
#print axioms Om3MemorySafety.static_access_in_bounds
#print axioms Om3MemorySafety.alloc_phys_disjoint
#print axioms Om3MemorySafety.pos_safe_gpu_lifecycle_accepted
#print axioms Om3MemorySafety.cex_aien_gpu_unfenced_reclaim_refused
#print axioms Om3MemorySafety.cex_aien_gpu_va_aliasing_refused
#print axioms Om3MemorySafety.cex_kernel_slab_gpu_map_refused
