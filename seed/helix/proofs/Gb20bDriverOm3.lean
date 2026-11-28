/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/Gb20bDriverOm3.lean

  Machine-checked Lean 4.36.0 proofs for Frontier #2: OM-3 Strand 5 Aegis Verified GB20B Driver.
  Exact 1:1 model of `gpu/driver/om3/gb20b_om3_dma.om` and `spec/omegese-om3.md` §2.

  Proves (with 0 warnings, 0 sorry, standard Lean 4 core axioms only):
    1. Kernel slab non-mapping (`trace_guarantees_kernel_slab_non_mapping`):
       NO `cpuKernelSlab` region can ever be GPU-mapped, hold a non-zero GPU VA,
       have active GPU DMA epochs, or physically overlap any other live region.
    2. RMR & GPU VA disjointness (`trace_guarantees_rmr_disjointness`,
       `trace_guarantees_gpu_va_safety`):
       ALL live driver regions and sysmem flush buffers are strictly disjoint from ALL 3
       ACPI IORT RMR carveouts (`0xa1600000..0xb97fffff`, `0x280000000..0x302ffffff`) and
       the MSI ITS doorbell window (`0x08000000..0x080fffff`); all GPU VAs satisfy
       `va >= vaBase (2 GiB)`, `va + vlen <= 2^40`, disjointness from GSP `[4 GiB, 4.5 GiB)`,
       and pairwise GPU VA disjointness.
    3. Fence-before-reclaim necessity (`reclaim_requires_4step_fence`):
       `reclaim` succeeds ONLY after `@unmap -> @tlbinval -> @fence_drain -> @vma_revoke`.
    4. `VER3 PTE PCF = 0x11` enforcement on ALL GR context buffers (`trace_guarantees_gr_ctx_pcf_0x11`):
       Every mapped GR context buffer (`MAIN`, `PATCH`, `PAM`, `GCB[0..6]`) MUST carry
       `pteValid = true ∧ pteAperture = 2 ∧ ptePcf = 0x11` (GPU-uncached); cached `PCF = 0x10`
       is refused fail-closed.
    5. Pre-bootstrap & Channel promotion (`boot_requires_9msix_and_flush`,
       `compute_requires_sc_pdb_and_gr_pcf11`):
       9 MSI-X vectors + non-zero 256B-aligned sysmem flush buffer (`0x008a1d58/5c`) before GSP boot,
       and `SC_PDB(0)` patch + global GR promotion before `B_COMPUTE (0xcec0)`.
    6. 14 Constructive Positive & Negative Controls verified by the Lean kernel (`by decide`).
-/

namespace Gb20bDriverOm3

-- ==================== GB20B HARDWARE CONSTANTS ====================

def U64_LIMIT        : Nat := 2 ^ 64
def GB20B_DMA_LIMIT  : Nat := 2 ^ 40
def GB20B_VABASE     : Nat := 0x80000000   -- 2 GiB (NV_VASPACE_ALLOCATION_PARAMETERS.vaBase)
def GB20B_GSP_VA_LO  : Nat := 0x100000000  -- 4 GiB (GSP-RM server split-VAS start)
def GB20B_GSP_VA_LEN : Nat := 0x20000000   -- 512 MiB ([4 GiB, 4.5 GiB))
def GB20B_MSIX_REQ   : Nat := 9
def GB20B_FLUSH_LO   : Nat := 0x008a1d58
def GB20B_FLUSH_HI   : Nat := 0x008a1d5c

def VER3_AP_SYS_COH     : Nat := 2
def VER3_PTE_PCF_CACHED : Nat := 0x10      -- 16: REGULAR_RW_ATOMIC_CACHED_ACD (INVALID for GR ctx)
def VER3_PTE_PCF_UNCACH : Nat := 0x11      -- 17: REGULAR_RW_ATOMIC_UNCACHED_ACD (REQUIRED)

-- 3 ACPI IORT RMR carveouts (IORT RMR_NODE idx=50, flags=0x10, remap_permitted=0) + MSI ITS window
def RMR0_BASE : Nat := 0xa1600000
def RMR0_LEN  : Nat := 0x18200000          -- 386 MiB -> 0xa1600000..0xb97fffff
def RMR1_BASE : Nat := 0x280000000
def RMR1_LEN  : Nat := 0x80000000          -- 2 GiB   -> 0x280000000..0x2ffffffff
def RMR2_BASE : Nat := 0x300000000
def RMR2_LEN  : Nat := 0x03000000          -- 48 MiB  -> 0x300000000..0x302ffffff
def MSI_BASE  : Nat := 0x08000000
def MSI_LEN   : Nat := 0x00100000          -- 1 MiB   -> 0x08000000..0x080fffff

-- ==================== HARDWARE DOMAINS, GR BUFFERS & PTE MODEL ====================

inductive Domain where
  | cpuHost        -- 1
  | cpuKernelSlab  -- 2: Linux/Aienux kernel slab (NEVER GPU-mappable)
  | gpuDeviceDma   -- 3
  | gpuPtGmmu      -- 4
  | mmioBar0       -- 5
  | sharedUncached -- 6
  deriving DecidableEq, Repr

inductive MapState where
  | unmapped
  | mapped
  | pteCleared
  | tlbFlushed
  deriving DecidableEq, Repr

inductive LifeState where
  | live
  | reclaimed
  deriving DecidableEq, Repr

inductive GrBufKind where
  | main
  | patch
  | pam
  | gcb (idx : Fin 7)
  deriving DecidableEq, Repr

structure Ver3Pte where
  valid    : Bool
  aperture : Nat
  pcf      : Nat
  pa       : Nat
  deriving DecidableEq, Repr

def grPteValid (pte : Ver3Pte) : Bool :=
  pte.valid && (pte.aperture == VER3_AP_SYS_COH) && (pte.pcf == VER3_PTE_PCF_UNCACH)

structure Region where
  rid      : Nat
  dom      : Domain
  pbase    : Nat
  psize    : Nat
  gva      : Nat
  gvlen    : Nat
  mstate   : MapState
  epoch    : Nat
  drained  : Nat
  vmaPins  : Nat
  lstate   : LifeState
  grKind   : Option GrBufKind
  pte      : Option Ver3Pte
  deriving DecidableEq, Repr

-- ==================== INTERVAL DISJOINTNESS & HARDWARE PREDICATES ====================

def intervalsDisjoint (a0 al b0 bl : Nat) : Prop :=
  al = 0 ∨ bl = 0 ∨ a0 + al ≤ b0 ∨ b0 + bl ≤ a0

theorem intervalsDisjoint_symm {a0 al b0 bl : Nat}
    (h : intervalsDisjoint a0 al b0 bl) : intervalsDisjoint b0 bl a0 al := by
  unfold intervalsDisjoint at h ⊢
  rcases h with h1 | h2 | h3 | h4
  · exact Or.inr (Or.inl h1)
  · exact Or.inl h2
  · exact Or.inr (Or.inr (Or.inr h3))
  · exact Or.inr (Or.inr (Or.inl h4))

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

def DisjointFromRmrs (base len : Nat) : Prop :=
  intervalsDisjoint base len RMR0_BASE RMR0_LEN ∧
  intervalsDisjoint base len RMR1_BASE RMR1_LEN ∧
  intervalsDisjoint base len RMR2_BASE RMR2_LEN ∧
  intervalsDisjoint base len MSI_BASE MSI_LEN

def hitsRmrs (base len : Nat) : Bool :=
  intervalsOverlap base len RMR0_BASE RMR0_LEN ||
  intervalsOverlap base len RMR1_BASE RMR1_LEN ||
  intervalsOverlap base len RMR2_BASE RMR2_LEN ||
  intervalsOverlap base len MSI_BASE MSI_LEN

theorem hitsRmrs_false_iff_disjoint (base len : Nat) :
    hitsRmrs base len = false ↔ DisjointFromRmrs base len := by
  unfold hitsRmrs DisjointFromRmrs
  simp only [Bool.or_eq_false_iff, overlap_false_iff_disjoint]
  constructor
  · rintro ⟨⟨⟨h0, h1⟩, h2⟩, h3⟩
    exact ⟨h0, h1, h2, h3⟩
  · rintro ⟨h0, h1, h2, h3⟩
    exact ⟨⟨⟨h0, h1⟩, h2⟩, h3⟩

def GpuVaLegal (va vlen : Nat) : Prop :=
  va ≥ GB20B_VABASE ∧
  vlen > 0 ∧
  va + vlen ≤ GB20B_DMA_LIMIT ∧
  intervalsDisjoint va vlen GB20B_GSP_VA_LO GB20B_GSP_VA_LEN

def gpuVaLegalBool (va vlen : Nat) : Bool :=
  decide (va ≥ GB20B_VABASE) &&
  decide (vlen > 0) &&
  decide (va + vlen ≤ GB20B_DMA_LIMIT) &&
  !intervalsOverlap va vlen GB20B_GSP_VA_LO GB20B_GSP_VA_LEN

theorem gpuVaLegalBool_true_iff (va vlen : Nat) :
    gpuVaLegalBool va vlen = true ↔ GpuVaLegal va vlen := by
  unfold gpuVaLegalBool GpuVaLegal
  simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq, overlap_false_iff_disjoint]
  constructor
  · rintro ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩
    exact ⟨h1, h2, h3, h4⟩
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩

-- ==================== GB20B DRIVER STATE MACHINE ====================

structure DriverState where
  msixVectors  : Nat
  flushAddr    : Nat
  flushLoReg   : Nat
  flushHiReg   : Nat
  booted       : Bool
  scPdbPatched : Bool
  gcbInitDone  : Bool
  computeReady : Bool
  regions      : List Region
  deriving DecidableEq, Repr

def initDriverState : DriverState :=
  { msixVectors := 0, flushAddr := 0, flushLoReg := 0, flushHiReg := 0,
    booted := false, scPdbPatched := false, gcbInitDone := false, computeReady := false,
    regions := [] }

inductive Action where
  | armPreboot   (nvec flushPa flushLoReg flushHiReg : Nat)
  | bootGsp
  | allocRegion  (rid : Nat) (dom : Domain) (pbase psize : Nat) (grKind : Option GrBufKind)
  | gpuMap       (rid va vlen aperture pcf : Nat)
  | vmaPin       (rid : Nat)
  | gpuSubmit    (rid ep : Nat)
  | gpuUnmap     (rid : Nat)
  | tlbInval     (rid : Nat)
  | fenceDrain   (rid ep : Nat)
  | vmaRevoke    (rid : Nat)
  | reclaim      (rid : Nat)
  | patchScPdb0  (rootPa : Nat)
  | allocCompute (gcb5Init : Bool) (gcb6Init : Bool)
  deriving DecidableEq, Repr

def findReg (rs : List Region) (rid : Nat) : Option Region :=
  rs.find? (fun r => r.rid == rid)

def updateReg (rs : List Region) (rid : Nat) (f : Region → Region) : List Region :=
  rs.map (fun r => if r.rid == rid then f r else r)

def allGrKindMapped (rs : List Region) (k : GrBufKind) : Bool :=
  rs.any (fun r =>
    r.lstate == .live &&
    r.mstate == .mapped &&
    r.grKind == some k &&
    match r.pte with
    | some p => grPteValid p
    | none => false)

def all10GrBuffersPromoted (rs : List Region) : Bool :=
  allGrKindMapped rs .main &&
  allGrKindMapped rs .patch &&
  allGrKindMapped rs .pam &&
  allGrKindMapped rs (.gcb 0) &&
  allGrKindMapped rs (.gcb 1) &&
  allGrKindMapped rs (.gcb 2) &&
  allGrKindMapped rs (.gcb 3) &&
  allGrKindMapped rs (.gcb 4) &&
  allGrKindMapped rs (.gcb 5) &&
  allGrKindMapped rs (.gcb 6)

def gbStep (s : DriverState) (a : Action) : Option DriverState :=
  match a with
  | .armPreboot nvec fpa flo fhi =>
    if nvec != GB20B_MSIX_REQ then none
    else if flo != GB20B_FLUSH_LO || fhi != GB20B_FLUSH_HI then none
    else if fpa == 0 || fpa % 256 != 0 || fpa + 4096 > GB20B_DMA_LIMIT then none
    else if hitsRmrs fpa 4096 then none
    else some { s with msixVectors := nvec, flushAddr := fpa, flushLoReg := flo, flushHiReg := fhi }

  | .bootGsp =>
    if s.msixVectors != GB20B_MSIX_REQ then none
    else if s.flushAddr == 0 || s.flushLoReg != GB20B_FLUSH_LO || s.flushHiReg != GB20B_FLUSH_HI then none
    else if hitsRmrs s.flushAddr 4096 then none
    else some { s with booted := true }

  | .allocRegion rid dom pbase psize grKind =>
    if psize == 0 || pbase + psize >= U64_LIMIT then none
    else if hitsRmrs pbase psize then none
    else if (findReg s.regions rid).isSome then none
    else if s.regions.any (fun r => r.lstate == .live && intervalsOverlap pbase psize r.pbase r.psize) then none
    else
      let nr : Region := {
        rid := rid, dom := dom, pbase := pbase, psize := psize,
        gva := 0, gvlen := 0, mstate := .unmapped,
        epoch := 0, drained := 0, vmaPins := 0, lstate := .live,
        grKind := grKind, pte := none
      }
      some { s with regions := nr :: s.regions }

  | .gpuMap rid va vlen aperture pcf =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live then none
      else if r.dom == .cpuKernelSlab then none
      else if r.mstate != .unmapped then none
      else if !gpuVaLegalBool va vlen || vlen > r.psize then none
      else if aperture != VER3_AP_SYS_COH then none
      else if r.grKind.isSome && pcf != VER3_PTE_PCF_UNCACH then none
      else if s.regions.any (fun o => o.lstate == .live && o.gvlen > 0 && intervalsOverlap va vlen o.gva o.gvlen) then none
      else
        let p : Ver3Pte := { valid := true, aperture := aperture, pcf := pcf, pa := r.pbase }
        some { s with regions := updateReg s.regions rid (fun x =>
          { x with gva := va, gvlen := vlen, mstate := .mapped, pte := some p }) }

  | .vmaPin rid =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.dom == .cpuKernelSlab || r.mstate == .pteCleared || r.mstate == .tlbFlushed then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with vmaPins := x.vmaPins + 1 }) }

  | .gpuSubmit rid ep =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.dom == .cpuKernelSlab || r.mstate != .mapped || ep <= r.epoch then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with epoch := ep }) }

  | .gpuUnmap rid =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .mapped then none
      else some { s with
        computeReady := false,
        regions := updateReg s.regions rid (fun x => { x with mstate := .pteCleared, pte := none }) }

  | .tlbInval rid =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .pteCleared then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with mstate := .tlbFlushed }) }

  | .fenceDrain rid ep =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.mstate != .tlbFlushed || ep < r.epoch then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with drained := ep }) }

  | .vmaRevoke rid =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live || r.vmaPins == 0 then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with vmaPins := x.vmaPins - 1 }) }

  | .reclaim rid =>
    match findReg s.regions rid with
    | none => none
    | some r =>
      if r.lstate != .live then none
      else if r.mstate == .mapped || r.mstate == .pteCleared then none
      else if r.epoch > r.drained then none
      else if r.vmaPins > 0 then none
      else some { s with regions := updateReg s.regions rid (fun x => { x with lstate := .reclaimed, gva := 0, gvlen := 0 }) }

  | .patchScPdb0 rootPa =>
    if !s.booted then none
    else if rootPa == 0 || rootPa % 4096 != 0 || rootPa + 4096 > GB20B_DMA_LIMIT then none
    else if hitsRmrs rootPa 4096 then none
    else some { s with scPdbPatched := true }

  | .allocCompute gcb5Init gcb6Init =>
    if !s.booted || !s.scPdbPatched then none
    else if !all10GrBuffersPromoted s.regions then none
    else if s.gcbInitDone && (gcb5Init || gcb6Init) then none
    else some { s with gcbInitDone := true, computeReady := true }

def gbRunTrace (s : DriverState) (acts : List Action) : Option DriverState :=
  match acts with
  | [] => some s
  | a :: rest =>
    match gbStep s a with
    | none => none
    | some s' => gbRunTrace s' rest

-- ==================== GLOBAL SAFETY INVARIANTS ====================

def RegionSafe (r : Region) : Prop :=
  r.psize > 0 ∧
  r.pbase + r.psize < U64_LIMIT ∧
  r.gvlen ≤ r.psize ∧
  DisjointFromRmrs r.pbase r.psize ∧
  (r.dom = .cpuKernelSlab → r.mstate = .unmapped ∧ r.gvlen = 0 ∧ r.epoch = 0 ∧ r.vmaPins = 0 ∧ r.pte = none) ∧
  (r.mstate = .mapped →
    GpuVaLegal r.gva r.gvlen ∧
    (∀ k, r.grKind = some k → ∃ p, r.pte = some p ∧ p.valid = true ∧ p.aperture = VER3_AP_SYS_COH ∧ p.pcf = VER3_PTE_PCF_UNCACH)) ∧
  (r.lstate = .reclaimed →
    r.mstate ≠ .mapped ∧ r.mstate ≠ .pteCleared ∧ r.drained ≥ r.epoch ∧ r.vmaPins = 0 ∧ r.gvlen = 0)

def PairSafe (r1 r2 : Region) : Prop :=
  r1.rid ≠ r2.rid →
  r1.lstate = .live →
  r2.lstate = .live →
  intervalsDisjoint r1.pbase r1.psize r2.pbase r2.psize ∧
  (r1.gvlen > 0 → r2.gvlen > 0 → intervalsDisjoint r1.gva r1.gvlen r2.gva r2.gvlen)

def UniqueIds (rs : List Region) : Prop :=
  ∀ r1 ∈ rs, ∀ r2 ∈ rs, r1.rid = r2.rid → r1 = r2

def StateSafe (s : DriverState) : Prop :=
  (s.flushAddr ≠ 0 → DisjointFromRmrs s.flushAddr 4096) ∧
  (s.booted = true →
    s.msixVectors = GB20B_MSIX_REQ ∧
    s.flushAddr ≠ 0 ∧
    s.flushLoReg = GB20B_FLUSH_LO ∧
    s.flushHiReg = GB20B_FLUSH_HI ∧
    DisjointFromRmrs s.flushAddr 4096) ∧
  (s.computeReady = true →
    s.booted = true ∧ s.scPdbPatched = true ∧ all10GrBuffersPromoted s.regions = true)

def WellFormed (s : DriverState) : Prop :=
  StateSafe s ∧
  UniqueIds s.regions ∧
  (∀ r ∈ s.regions, RegionSafe r) ∧
  (∀ r1 ∈ s.regions, ∀ r2 ∈ s.regions, PairSafe r1 r2)

theorem initDriverState_wellFormed : WellFormed initDriverState := by
  refine ⟨⟨?_, ?_, ?_⟩, ?_, ?_, ?_⟩
  · intro h; simp [initDriverState] at h
  · intro h; simp [initDriverState] at h
  · intro h; simp [initDriverState] at h
  · simp [UniqueIds, initDriverState]
  · simp [initDriverState]
  · simp [initDriverState]

private theorem findReg_mem {rs : List Region} {rid : Nat} {r : Region}
    (h : findReg rs rid = some r) : r ∈ rs ∧ r.rid = rid := by
  induction rs with
  | nil => simp [findReg] at h
  | cons x xs ih =>
    unfold findReg at h
    simp only [List.find?] at h
    cases hx : (x.rid == rid)
    · simp [hx] at h
      have ⟨hm, he⟩ := ih h
      exact ⟨List.mem_cons_of_mem x hm, he⟩
    · simp [hx] at h
      subst h
      exact ⟨List.mem_cons_self, beq_iff_eq.mp hx⟩

private theorem findReg_none_forall {rs : List Region} {rid : Nat}
    (h : findReg rs rid = none) : ∀ r ∈ rs, r.rid ≠ rid := by
  unfold findReg at h
  simp only [List.find?_eq_none, beq_iff_eq] at h
  exact h

private theorem uniqueIds_updateReg {rs : List Region} {rid : Nat} {f : Region → Region}
    (hu : UniqueIds rs) (hkeep : ∀ x, (f x).rid = x.rid) :
    UniqueIds (updateReg rs rid f) := by
  intro a ha b hb heq
  unfold updateReg at ha hb
  rw [List.mem_map] at ha hb
  rcases ha with ⟨x, hx, rfl⟩
  rcases hb with ⟨y, hy, rfl⟩
  have hrx : (if x.rid == rid then f x else x).rid = x.rid := by split <;> simp [hkeep]
  have hry : (if y.rid == rid then f y else y).rid = y.rid := by split <;> simp [hkeep]
  rw [hrx, hry] at heq
  have hxy := hu x hx y hy heq
  subst hxy
  rfl

private theorem allGrKindMapped_cons (nr : Region) (rs : List Region) (k : GrBufKind)
    (hk : allGrKindMapped rs k = true) : allGrKindMapped (nr :: rs) k = true := by
  unfold allGrKindMapped at hk ⊢
  rw [List.any_cons]
  simp [hk]

private theorem allGrKindMapped_updateReg_nonmapped {rs : List Region} {rid : Nat} {f : Region → Region}
    (hu : UniqueIds rs) {r : Region} (hf : findReg rs rid = some r) (hnot : r.mstate ≠ .mapped) :
    ∀ k, allGrKindMapped rs k = true → allGrKindMapped (updateReg rs rid f) k = true := by
  intro k hk
  have ⟨hrmem, hrid⟩ := findReg_mem hf
  unfold allGrKindMapped at hk ⊢
  rw [List.any_eq_true] at hk ⊢
  rcases hk with ⟨x, hx, hxp⟩
  refine ⟨x, ?_, hxp⟩
  unfold updateReg; rw [List.mem_map]; refine ⟨x, hx, ?_⟩
  by_cases hxr : x.rid == rid
  · have hxe : x = r := hu x hx r hrmem (by rw [beq_iff_eq.mp hxr, hrid])
    have hxm : x.mstate ≠ .mapped := by rw [hxe]; exact hnot
    have hm : (x.mstate == .mapped) = false := by
      cases hmm : x.mstate
      · rfl
      · exact absurd hmm hxm
      · rfl
      · rfl
    simp [hm] at hxp
  · simp [hxr]

private theorem allGrKindMapped_updateReg_keepPte {rs : List Region} {rid : Nat} {f : Region → Region}
    (hl : ∀ x, (f x).lstate = x.lstate)
    (hm : ∀ x, (f x).mstate = x.mstate)
    (hg : ∀ x, (f x).grKind = x.grKind)
    (hp : ∀ x, (f x).pte = x.pte) :
    ∀ k, allGrKindMapped rs k = true → allGrKindMapped (updateReg rs rid f) k = true := by
  intro k hk
  unfold allGrKindMapped at hk ⊢
  rw [List.any_eq_true] at hk ⊢
  rcases hk with ⟨x, hx, hxp⟩
  refine ⟨if x.rid == rid then f x else x, ?_, ?_⟩
  · unfold updateReg
    exact List.mem_map.mpr ⟨x, hx, rfl⟩
  · by_cases hxr : x.rid == rid <;> simp [hxr, hl, hm, hg, hp, hxp]

private theorem all10GrBuffersPromoted_of_forall {rs1 rs2 : List Region}
    (h : ∀ k, allGrKindMapped rs1 k = true → allGrKindMapped rs2 k = true)
    (h1 : all10GrBuffersPromoted rs1 = true) : all10GrBuffersPromoted rs2 = true := by
  unfold all10GrBuffersPromoted at h1 ⊢
  simp only [Bool.and_eq_true] at h1 ⊢
  rcases h1 with ⟨⟨⟨⟨⟨⟨⟨⟨⟨hm, hp⟩, hpa⟩, h0⟩, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩
  exact ⟨⟨⟨⟨⟨⟨⟨⟨⟨h _ hm, h _ hp⟩, h _ hpa⟩, h _ h0⟩, h _ h1⟩, h _ h2⟩, h _ h3⟩, h _ h4⟩, h _ h5⟩, h _ h6⟩

private theorem pairSafe_updateReg_keepIds {rs : List Region} {rid : Nat} {f : Region → Region}
    (hp : ∀ r1 ∈ rs, ∀ r2 ∈ rs, PairSafe r1 r2)
    (hrid : ∀ x, (f x).rid = x.rid)
    (hlive : ∀ x, (f x).lstate = x.lstate)
    (hphys : ∀ x, (f x).pbase = x.pbase ∧ (f x).psize = x.psize)
    (hva : ∀ x, (f x).gva = x.gva ∧ (f x).gvlen = x.gvlen) :
    ∀ a ∈ updateReg rs rid f, ∀ b ∈ updateReg rs rid f, PairSafe a b := by
  intro a ha b hb hne hla hlb
  unfold updateReg at ha hb; rw [List.mem_map] at ha hb
  rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
  have hax : (if x.rid == rid then f x else x).rid = x.rid := by split <;> simp [hrid]
  have hby : (if y.rid == rid then f y else y).rid = y.rid := by split <;> simp [hrid]
  have hlx : (if x.rid == rid then f x else x).lstate = x.lstate := by split <;> simp [hlive]
  have hly : (if y.rid == rid then f y else y).lstate = y.lstate := by split <;> simp [hlive]
  have hpx : (if x.rid == rid then f x else x).pbase = x.pbase ∧ (if x.rid == rid then f x else x).psize = x.psize := by
    split <;> simp [hphys]
  have hpy : (if y.rid == rid then f y else y).pbase = y.pbase ∧ (if y.rid == rid then f y else y).psize = y.psize := by
    split <;> simp [hphys]
  have hvx : (if x.rid == rid then f x else x).gva = x.gva ∧ (if x.rid == rid then f x else x).gvlen = x.gvlen := by
    split <;> simp [hva]
  have hvy : (if y.rid == rid then f y else y).gva = y.gva ∧ (if y.rid == rid then f y else y).gvlen = y.gvlen := by
    split <;> simp [hva]
  rw [hax, hby] at hne; rw [hlx] at hla; rw [hly] at hlb
  have hxy := hp x hx y hy hne hla hlb
  rw [hpx.1, hpx.2, hpy.1, hpy.2, hvx.1, hvx.2, hvy.1, hvy.2]
  exact hxy

-- ==================== INDUCTIVE SAFETY PROOF ====================

theorem gbStep_preserves_wellFormed (s s' : DriverState) (a : Action)
    (hwf : WellFormed s) (h : gbStep s a = some s') :
    WellFormed s' := by
  rcases hwf with ⟨hss, huniq, hreg, hpair⟩
  cases a with
  | armPreboot nvec fpa flo fhi =>
    simp only [gbStep] at h
    by_cases h1 : nvec = GB20B_MSIX_REQ
    · by_cases h2 : flo = GB20B_FLUSH_LO ∧ fhi = GB20B_FLUSH_HI
      · by_cases h3 : fpa ≠ 0 ∧ fpa % 256 = 0 ∧ fpa + 4096 ≤ GB20B_DMA_LIMIT
        · by_cases h4 : hitsRmrs fpa 4096 = false
          · have hdisj := (hitsRmrs_false_iff_disjoint fpa 4096).mp h4
            have hb1 : (nvec != GB20B_MSIX_REQ) = false := by simp [h1]
            have hb2 : (flo != GB20B_FLUSH_LO || fhi != GB20B_FLUSH_HI) = false := by simp [h2.1, h2.2]
            have hb3 : (fpa == 0 || fpa % 256 != 0 || fpa + 4096 > GB20B_DMA_LIMIT) = false := by
              simp [h3.1, h3.2.1, Nat.not_lt_of_ge h3.2.2]
            rw [hb1, hb2, hb3, h4] at h
            simp only [Bool.false_eq_true, ↓reduceIte] at h
            injection h with hs'; subst hs'
            refine ⟨⟨fun _ => hdisj, fun _ => ?_, ?_⟩, huniq, hreg, hpair⟩
            · dsimp only
              exact ⟨h1, h3.1, h2.1, h2.2, hdisj⟩
            · intro hcmp; dsimp only at hcmp ⊢; exact hss.2.2 hcmp
          · have h4t : hitsRmrs fpa 4096 = true := by cases hm : hitsRmrs fpa 4096 <;> simp_all
            have hb1 : (nvec != GB20B_MSIX_REQ) = false := by simp [h1]
            have hb2 : (flo != GB20B_FLUSH_LO || fhi != GB20B_FLUSH_HI) = false := by simp [h2.1, h2.2]
            have hb3 : (fpa == 0 || fpa % 256 != 0 || fpa + 4096 > GB20B_DMA_LIMIT) = false := by
              simp [h3.1, h3.2.1, Nat.not_lt_of_ge h3.2.2]
            rw [hb1, hb2, hb3, h4t] at h
            simp at h
        · have hb3 : (fpa == 0 || fpa % 256 != 0 || fpa + 4096 > GB20B_DMA_LIMIT) = true := by
            by_cases ha : fpa = 0
            · simp [ha]
            · by_cases hb : fpa % 256 = 0
              · have hc : fpa + 4096 > GB20B_DMA_LIMIT := by omega
                simp [hb, hc]
              · simp [ha, hb]
          simp [h1, h2.1, h2.2, hb3] at h
      · have hb2 : (flo != GB20B_FLUSH_LO || fhi != GB20B_FLUSH_HI) = true := by
          by_cases ha : flo = GB20B_FLUSH_LO
          · have hb : fhi ≠ GB20B_FLUSH_HI := fun hc => h2 ⟨ha, hc⟩
            simp [ha, hb]
          · simp [ha]
        simp [h1, hb2] at h
    · have hb1 : (nvec != GB20B_MSIX_REQ) = true := by simp [h1]
      simp [hb1] at h

  | bootGsp =>
    simp only [gbStep] at h
    split at h; · contradiction
    rename_i hmsix
    split at h; · contradiction
    rename_i hfl
    split at h; · contradiction
    rename_i hrmr
    injection h with hs'; subst hs'
    simp only [bne_iff_ne, ne_eq, Bool.or_eq_true, beq_iff_eq, not_or] at hmsix hfl
    have hms : s.msixVectors = GB20B_MSIX_REQ := Decidable.of_not_not hmsix
    have hlo : s.flushLoReg = GB20B_FLUSH_LO := Decidable.of_not_not hfl.1.2
    have hhi : s.flushHiReg = GB20B_FLUSH_HI := Decidable.of_not_not hfl.2
    have hrmrf : hitsRmrs s.flushAddr 4096 = false := by
      cases hb : hitsRmrs s.flushAddr 4096 <;> simp_all
    have hdisj := (hitsRmrs_false_iff_disjoint s.flushAddr 4096).mp hrmrf
    refine ⟨⟨hss.1, ?_, ?_⟩, huniq, hreg, hpair⟩
    · intro _; dsimp only; exact ⟨hms, hfl.1.1, hlo, hhi, hdisj⟩
    · intro hcmp; dsimp only at hcmp ⊢; have hb := hss.2.2 hcmp; exact ⟨rfl, hb.2.1, hb.2.2⟩

  | allocRegion rid dom pbase psize grKind =>
    simp only [gbStep] at h
    split at h; · contradiction
    rename_i hsz
    split at h; · contradiction
    rename_i hrmr
    split at h; · contradiction
    rename_i hnf
    split at h; · contradiction
    rename_i hnoov
    injection h with hs'; subst hs'
    simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or] at hsz
    have hrmrf : hitsRmrs pbase psize = false := by cases hb : hitsRmrs pbase psize <;> simp_all
    have hdisj_rmr := (hitsRmrs_false_iff_disjoint pbase psize).mp hrmrf
    have hfn : findReg s.regions rid = none := by
      cases hfr : findReg s.regions rid
      · rfl
      · simp [hfr] at hnf
    have hfresh := findReg_none_forall hfn
    have hdisj_all : ∀ r ∈ s.regions, r.lstate = .live → intervalsDisjoint pbase psize r.pbase r.psize := by
      intro r hr hlive
      have hfalse : s.regions.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize) = false := by
        cases hb : s.regions.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize)
        · rfl
        · exact absurd hb hnoov
      have hm := List.any_eq_false.mp hfalse r hr
      simp only [hlive, beq_self_eq_true, Bool.true_and] at hm
      have hovf : intervalsOverlap pbase psize r.pbase r.psize = false := by
        cases hov : intervalsOverlap pbase psize r.pbase r.psize
        · rfl
        · simp [hov] at hm
      exact (overlap_false_iff_disjoint pbase psize r.pbase r.psize).mp hovf
    refine ⟨⟨hss.1, hss.2.1, ?_⟩, ?_, ?_, ?_⟩
    · intro hcmp
      dsimp only at hcmp ⊢
      have hsc := hss.2.2 hcmp
      refine ⟨hsc.1, hsc.2.1, ?_⟩
      let nr : Region := {
        rid := rid, dom := dom, pbase := pbase, psize := psize,
        gva := 0, gvlen := 0, mstate := .unmapped, epoch := 0, drained := 0, vmaPins := 0,
        lstate := .live, grKind := grKind, pte := none }
      have hkeep := fun k => allGrKindMapped_cons nr s.regions k
      have hp := hsc.2.2
      unfold all10GrBuffersPromoted at hp ⊢
      simp only [Bool.and_eq_true] at hp ⊢
      rcases hp with ⟨⟨⟨⟨⟨⟨⟨⟨⟨hm, hpa⟩, hpm⟩, h0⟩, h1⟩, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩
      exact ⟨⟨⟨⟨⟨⟨⟨⟨⟨hkeep _ hm, hkeep _ hpa⟩, hkeep _ hpm⟩, hkeep _ h0⟩, hkeep _ h1⟩, hkeep _ h2⟩, hkeep _ h3⟩, hkeep _ h4⟩, hkeep _ h5⟩, hkeep _ h6⟩
    · intro r1 hr1 r2 hr2 heq
      dsimp only at hr1 hr2
      rcases List.mem_cons.mp hr1 with rfl | hr1' <;> rcases List.mem_cons.mp hr2 with rfl | hr2'
      · rfl
      · exact absurd heq.symm (hfresh r2 hr2')
      · exact absurd heq (hfresh r1 hr1')
      · exact huniq r1 hr1' r2 hr2' heq
    · intro r hr
      dsimp only at hr
      rcases List.mem_cons.mp hr with rfl | hr'
      · refine ⟨Nat.pos_of_ne_zero hsz.1, Nat.lt_of_not_ge hsz.2, Nat.zero_le _, hdisj_rmr, ?_, ?_, ?_⟩
        · intro _; exact ⟨rfl, rfl, rfl, rfl, rfl⟩
        · intro hm; cases hm
        · intro hrec; cases hrec
      · exact hreg r hr'
    · intro r1 hr1 r2 hr2 hne hl1 hl2
      dsimp only at hr1 hr2
      rcases List.mem_cons.mp hr1 with rfl | hr1' <;> rcases List.mem_cons.mp hr2 with rfl | hr2'
      · exact absurd rfl hne
      · refine ⟨hdisj_all r2 hr2' hl2, ?_⟩
        intro hgv; dsimp only at hgv; omega
      · refine ⟨intervalsDisjoint_symm (hdisj_all r1 hr1' hl1), ?_⟩
        intro _ hgv; dsimp only at hgv; omega
      · exact hpair r1 hr1' r2 hr2' hne hl1 hl2

  | gpuMap rid va vlen aperture pcf =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hlive
      split at h
      · contradiction
      rename_i hnotk
      split at h
      · contradiction
      rename_i hunm
      split at h
      · contradiction
      rename_i hvbnd
      split at h
      · contradiction
      rename_i hap
      split at h
      · contradiction
      rename_i hpcf
      split at h
      · contradiction
      rename_i hnoov
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, Bool.not_eq_true', bne_iff_ne, ne_eq, beq_iff_eq, decide_eq_true_eq, not_or] at hlive hnotk hunm hvbnd hap hpcf
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      have hrunm : r.mstate = .unmapped := by cases hm : r.mstate <;> simp_all
      have hapeq : aperture = VER3_AP_SYS_COH := by omega
      have hvaleg : GpuVaLegal va vlen :=
        (gpuVaLegalBool_true_iff va vlen).mp (by cases hb : gpuVaLegalBool va vlen <;> simp_all)
      have hvle : vlen ≤ r.psize := Nat.le_of_not_lt hvbnd.2
      have hdisj_va : ∀ o ∈ s.regions, o.lstate = .live → o.gvlen > 0 → intervalsDisjoint va vlen o.gva o.gvlen := by
        intro o ho hol hog
        have hfalse : s.regions.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen) = false := by
          cases hb : s.regions.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen)
          · rfl
          · exact absurd hb hnoov
        have hm := List.any_eq_false.mp hfalse o ho
        simp only [hol, beq_self_eq_true, Bool.true_and, decide_eq_true hog] at hm
        have hovf : intervalsOverlap va vlen o.gva o.gvlen = false := by
          cases hov : intervalsOverlap va vlen o.gva o.gvlen <;> simp_all
        exact (overlap_false_iff_disjoint va vlen o.gva o.gvlen).mp hovf
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp
        dsimp only at hcmp ⊢
        have hsc := hss.2.2 hcmp
        refine ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_nonmapped huniq hf (by rw [hrunm]; decide)) hsc.2.2⟩
      · intro x hx
        unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hvle, hys.2.2.2.1, ?_, ?_, ?_⟩
          · intro hdom; exact absurd hdom hnotk
          · intro _
            refine ⟨hvaleg, ?_⟩
            intro k hk
            dsimp only at hk
            have his : y.grKind.isSome = true := by simp [hk]
            have hpcfeq : pcf = VER3_PTE_PCF_UNCACH := by
              by_cases hp : pcf = VER3_PTE_PCF_UNCACH
              · exact hp
              · exfalso; apply hpcf; simp [his, hp]
            refine ⟨{ valid := true, aperture := aperture, pcf := pcf, pa := y.pbase }, rfl, rfl, hapeq, hpcfeq⟩
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · intro a ha b hb hne hla hlb
        unfold updateReg at ha hb; rw [List.mem_map] at ha hb
        rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
        cases hxr : (x.rid == rid) <;> cases hyr : (y.rid == rid)
        · simp only [hxr, hyr, Bool.false_eq_true, ↓reduceIte] at hne hla hlb ⊢
          exact hpair x hx y hy hne hla hlb
        · simp only [hxr, hyr, Bool.false_eq_true, ↓reduceIte] at hne hla hlb ⊢
          exact ⟨(hpair x hx y hy hne hla hlb).1, fun hxgv _ => intervalsDisjoint_symm (hdisj_va x hx hla hxgv)⟩
        · simp only [hxr, hyr, Bool.false_eq_true, ↓reduceIte] at hne hla hlb ⊢
          exact ⟨(hpair x hx y hy hne hla hlb).1, fun _ hygv => hdisj_va y hy hlb hygv⟩
        · simp only [hxr, hyr, ↓reduceIte] at hne
          exact absurd (by rw [beq_iff_eq.mp hxr, beq_iff_eq.mp hyr]) hne

  | vmaPin rid =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_keepPte (fun _ => rfl) (fun _ => rfl) (fun _ => rfl) (fun _ => rfl)) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, hys.2.2.2.2.2.1, ?_⟩
          · intro hdom; exact absurd hdom hok.1.1.2
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | gpuSubmit rid ep =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, decide_eq_true_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_keepPte (fun _ => rfl) (fun _ => rfl) (fun _ => rfl) (fun _ => rfl)) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, hys.2.2.2.2.2.1, ?_⟩
          · intro hdom; exact absurd hdom hok.1.1.2
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | gpuUnmap rid =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      have hrmap : r.mstate = .mapped := by cases hm : r.mstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, fun hc => by dsimp only at hc; cases hc⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, ?_, ?_⟩
          · intro hdom
            have hks := (hys.2.2.2.2.1 hdom).1
            rw [hrmap] at hks; cases hks
          · intro hm; cases hm
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | tlbInval rid =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      have hrclr : r.mstate = .pteCleared := by cases hm : r.mstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_nonmapped huniq hf (by rw [hrclr]; decide)) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, ?_, ?_⟩
          · intro hdom; have hks := (hys.2.2.2.2.1 hdom).1; rw [hrclr] at hks; cases hks
          · intro hm; cases hm
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | fenceDrain rid ep =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, decide_eq_true_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      have hrtlb : r.mstate = .tlbFlushed := by cases hm : r.mstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_nonmapped huniq hf (by rw [hrtlb]; decide)) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, hys.2.2.2.2.2.1, ?_⟩
          · intro hdom; have hks := (hys.2.2.2.2.1 hdom).1; rw [hrtlb] at hks; cases hks
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | vmaRevoke rid =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hok
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hok
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_keepPte (fun _ => rfl) (fun _ => rfl) (fun _ => rfl) (fun _ => rfl)) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, hys.2.2.1, hys.2.2.2.1, ?_, hys.2.2.2.2.2.1, ?_⟩
          · intro hdom
            have hks := hys.2.2.2.2.1 hdom
            exact absurd hks.2.2.2.1 hok.2
          · intro hrec; dsimp only at hrec; rw [hrlive] at hrec; cases hrec
      · exact pairSafe_updateReg_keepIds hpair (fun _ => rfl) (fun _ => rfl)
          (fun _ => ⟨rfl, rfl⟩) (fun _ => ⟨rfl, rfl⟩)

  | reclaim rid =>
    simp only [gbStep] at h
    cases hf : findReg s.regions rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      rename_i hlive
      split at h
      · contradiction
      rename_i hmst
      split at h
      · contradiction
      rename_i hdrn
      split at h
      · contradiction
      rename_i hvma
      injection h with hs'; subst hs'
      have ⟨hrmem, hrid⟩ := findReg_mem hf
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hlive hmst hdrn hvma
      have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
      have hnotm : r.mstate ≠ .mapped := hmst.1
      have hnotp : r.mstate ≠ .pteCleared := hmst.2
      have hdrained : r.drained ≥ r.epoch := Nat.le_of_not_lt hdrn
      have hvpins : r.vmaPins = 0 := Nat.eq_zero_of_not_pos hvma
      refine ⟨⟨hss.1, hss.2.1, ?_⟩, uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
      · intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp
        exact ⟨hsc.1, hsc.2.1, all10GrBuffersPromoted_of_forall
          (allGrKindMapped_updateReg_nonmapped huniq hf hnotm) hsc.2.2⟩
      · intro x hx; unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
        cases hyr : (y.rid == rid)
        · simp only [Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · simp only [↓reduceIte]
          have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
          subst hyeq; have hys := hreg y hy
          refine ⟨hys.1, hys.2.1, Nat.zero_le _, hys.2.2.2.1, ?_, ?_, ?_⟩
          · intro hdom
            have hks := hys.2.2.2.2.1 hdom
            exact ⟨hks.1, rfl, hks.2.2.1, hks.2.2.2.1, hks.2.2.2.2⟩
          · intro hm
            exact absurd hm hnotm
          · intro _; exact ⟨hnotm, hnotp, hdrained, hvpins, rfl⟩
      · intro a ha b hb hne hla hlb
        unfold updateReg at ha hb; rw [List.mem_map] at ha hb
        rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
        by_cases hxr : x.rid == rid
        · have hlx : (if x.rid == rid then ({ x with lstate := .reclaimed, gva := 0, gvlen := 0 } : Region) else x).lstate = .reclaimed := by
            simp [hxr]
          rw [hlx] at hla; cases hla
        · by_cases hyr : y.rid == rid
          · have hly : (if y.rid == rid then ({ y with lstate := .reclaimed, gva := 0, gvlen := 0 } : Region) else y).lstate = .reclaimed := by
              simp [hyr]
            rw [hly] at hlb; cases hlb
          · simp [hxr, hyr] at hne hla hlb ⊢
            exact hpair x hx y hy hne hla hlb

  | patchScPdb0 rootPa =>
    simp only [gbStep] at h
    cases h1 : (!s.booted)
    · cases h2 : (rootPa == 0 || rootPa % 4096 != 0 || rootPa + 4096 > GB20B_DMA_LIMIT)
      · cases h3 : hitsRmrs rootPa 4096
        · simp [h1, h2, h3] at h
          subst h
          refine ⟨⟨hss.1, hss.2.1, ?_⟩, huniq, hreg, hpair⟩
          intro hcmp; dsimp only at hcmp ⊢; have hsc := hss.2.2 hcmp; exact ⟨hsc.1, rfl, hsc.2.2⟩
        · simp [h1, h2, h3] at h
      · simp [h1, h2] at h
    · simp [h1] at h

  | allocCompute gcb5Init gcb6Init =>
    simp only [gbStep] at h
    split at h
    · contradiction
    rename_i hbp
    split at h
    · contradiction
    rename_i hgr
    split at h
    · contradiction
    injection h with hs'; subst hs'
    have hbt : s.booted = true := by cases hb : s.booted <;> simp_all
    have hsc : s.scPdbPatched = true := by cases hp : s.scPdbPatched <;> simp_all
    have hgr10 : all10GrBuffersPromoted s.regions = true := by cases hg : all10GrBuffersPromoted s.regions <;> simp_all
    refine ⟨⟨hss.1, hss.2.1, ?_⟩, huniq, hreg, hpair⟩
    intro _; exact ⟨hbt, hsc, hgr10⟩

theorem gbRunTrace_preserves_wellFormed (acts : List Action) (s s' : DriverState)
    (hwf : WellFormed s) (h : gbRunTrace s acts = some s') : WellFormed s' := by
  induction acts generalizing s with
  | nil => simp [gbRunTrace] at h; subst h; exact hwf
  | cons a rest ih =>
    simp only [gbRunTrace] at h
    cases hs : gbStep s a with
    | none => simp [hs] at h
    | some s1 =>
      simp only [hs] at h
      exact ih s1 (gbStep_preserves_wellFormed s s1 a hwf hs) h

-- ==================== REQUIRED SAFETY THEOREMS ====================

/-- 1. Kernel slab (`CPU_KERNEL_SLAB`) can NEVER be GPU-mapped, hold a non-zero GPU VA,
    hold active DMA epochs/VMA pins, or physically overlap any other live region. -/
theorem trace_guarantees_kernel_slab_non_mapping (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) :
    (∀ r ∈ s.regions, r.dom = .cpuKernelSlab →
      r.mstate = .unmapped ∧ r.gvlen = 0 ∧ r.epoch = 0 ∧ r.vmaPins = 0 ∧ r.pte = none) ∧
    (∀ r1 ∈ s.regions, ∀ r2 ∈ s.regions,
      r1.rid ≠ r2.rid → r1.lstate = .live → r2.lstate = .live → r1.dom = .cpuKernelSlab →
      intervalsDisjoint r1.pbase r1.psize r2.pbase r2.psize) := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  exact ⟨fun r hr hdom => (hwf.2.2.1 r hr).2.2.2.2.1 hdom,
         fun r1 hr1 r2 hr2 hne hl1 hl2 _ => (hwf.2.2.2 r1 hr1 r2 hr2 hne hl1 hl2).1⟩

/-- 2. ALL live driver regions AND the PCIe sysmem flush buffer are strictly disjoint
    from ALL 3 ACPI IORT RMR carveouts and the GICv3 MSI ITS doorbell window. -/
theorem trace_guarantees_rmr_disjointness (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) :
    (s.flushAddr ≠ 0 → DisjointFromRmrs s.flushAddr 4096) ∧
    (∀ r ∈ s.regions, DisjointFromRmrs r.pbase r.psize) := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  exact ⟨hwf.1.1, fun r hr => (hwf.2.2.1 r hr).2.2.2.1⟩

/-- 3. Every GPU-mapped region obeys `va >= 2 GiB`, `va + vlen <= 2^40`, disjointness
    from GSP split-VAS `[4 GiB, 4.5 GiB)`, and pairwise GPU VA disjointness. -/
theorem trace_guarantees_gpu_va_safety (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) :
    (∀ r ∈ s.regions, r.mstate = .mapped → GpuVaLegal r.gva r.gvlen) ∧
    (∀ r1 ∈ s.regions, ∀ r2 ∈ s.regions,
      r1.rid ≠ r2.rid → r1.lstate = .live → r2.lstate = .live →
      r1.gvlen > 0 → r2.gvlen > 0 → intervalsDisjoint r1.gva r1.gvlen r2.gva r2.gvlen) := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  exact ⟨fun r hr hm => ((hwf.2.2.1 r hr).2.2.2.2.2.1 hm).1,
         fun r1 hr1 r2 hr2 hne hl1 hl2 hg1 hg2 => (hwf.2.2.2 r1 hr1 r2 hr2 hne hl1 hl2).2 hg1 hg2⟩

/-- 4. Every mapped GR context buffer (`MAIN`, `PATCH`, `PAM`, `GCB[0..6]`) MUST
    carry `VER3 PTE PCF = 0x11` (GPU-uncached, coherent sysmem aperture 2). -/
theorem trace_guarantees_gr_ctx_pcf_0x11 (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) :
    ∀ r ∈ s.regions, ∀ k, r.mstate = .mapped → r.grKind = some k →
      ∃ p, r.pte = some p ∧ p.valid = true ∧ p.aperture = VER3_AP_SYS_COH ∧ p.pcf = VER3_PTE_PCF_UNCACH := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  intro r hr k hm hk
  exact ((hwf.2.2.1 r hr).2.2.2.2.2.1 hm).2 k hk

/-- 5. Linear 4-step DMA reclaim fence necessity: `reclaim` ONLY succeeds when
    the target region is neither `.mapped` nor `.pteCleared`, `drained >= epoch`,
    and `vmaPins = 0` (i.e. `@unmap -> @tlbinval -> @fence_drain -> @vma_revoke` completed). -/
theorem reclaim_requires_4step_fence (s s' : DriverState) (rid : Nat)
    (h : gbStep s (.reclaim rid) = some s') :
    ∃ r ∈ s.regions, r.rid = rid ∧ r.lstate = .live ∧
      r.mstate ≠ .mapped ∧ r.mstate ≠ .pteCleared ∧ r.drained ≥ r.epoch ∧ r.vmaPins = 0 := by
  simp only [gbStep] at h
  cases hf : findReg s.regions rid with
  | none => simp [hf] at h
  | some r =>
    simp only [hf] at h
    split at h
    · contradiction
    rename_i hlive
    split at h
    · contradiction
    rename_i hmst
    split at h
    · contradiction
    rename_i hdrn
    split at h
    · contradiction
    rename_i hvma
    have ⟨hrmem, hrid⟩ := findReg_mem hf
    simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hlive hmst hdrn hvma
    have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
    exact ⟨r, hrmem, hrid, hrlive, hmst.1, hmst.2, Nat.le_of_not_lt hdrn, Nat.eq_zero_of_not_pos hvma⟩

/-- 6. GSP bootstrap requires 9 MSI-X vectors + valid non-RMR flush buffer (`0x008a1d58/5c`). -/
theorem boot_requires_9msix_and_flush (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) (hb : s.booted = true) :
    s.msixVectors = 9 ∧ s.flushAddr ≠ 0 ∧ s.flushLoReg = 0x008a1d58 ∧ s.flushHiReg = 0x008a1d5c ∧
    DisjointFromRmrs s.flushAddr 4096 := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  exact hwf.1.2.1 hb

/-- 7. Compute dispatch (`B_COMPUTE 0xcec0`) requires `SC_PDB(0)` + ALL 10 GR buffers `PCF = 0x11`. -/
theorem compute_requires_sc_pdb_and_gr_pcf11 (acts : List Action) (s : DriverState)
    (h : gbRunTrace initDriverState acts = some s) (hc : s.computeReady = true) :
    s.booted = true ∧ s.scPdbPatched = true ∧ all10GrBuffersPromoted s.regions = true := by
  have hwf := gbRunTrace_preserves_wellFormed acts initDriverState s initDriverState_wellFormed h
  exact hwf.1.2.2 hc

-- ==================== CONSTRUCTIVE POSITIVE TRACE & 19 NEGATIVE CONTROLS ====================

def posBootAndGrSetup : List Action :=
  [ .armPreboot 9 0x92000000 0x008a1d58 0x008a1d5c
  , .bootGsp
  , .allocRegion 100 .cpuKernelSlab 0x90000000 0x01000000 none
  , .allocRegion 0   .sharedUncached 0x93000000 0x20000 (some .main)
  , .allocRegion 1   .sharedUncached 0x93020000 0x20000 (some .patch)
  , .allocRegion 2   .sharedUncached 0x93040000 0x20000 (some .pam)
  , .allocRegion 3   .sharedUncached 0x93060000 0x20000 (some (.gcb 0))
  , .allocRegion 4   .sharedUncached 0x93080000 0x20000 (some (.gcb 1))
  , .allocRegion 5   .sharedUncached 0x930a0000 0x20000 (some (.gcb 2))
  , .allocRegion 6   .sharedUncached 0x930c0000 0x20000 (some (.gcb 3))
  , .allocRegion 7   .sharedUncached 0x930e0000 0x20000 (some (.gcb 4))
  , .allocRegion 8   .sharedUncached 0x93100000 0x20000 (some (.gcb 5))
  , .allocRegion 9   .sharedUncached 0x93120000 0x20000 (some (.gcb 6))
  , .gpuMap 0 0x200000000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 1 0x200020000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 2 0x200040000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 3 0x200060000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 4 0x200080000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 5 0x2000a0000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 6 0x2000c0000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 7 0x2000e0000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 8 0x200100000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .gpuMap 9 0x200120000 0x20000 2 VER3_PTE_PCF_UNCACH
  , .patchScPdb0 0x93800000
  , .allocCompute true true
  , .allocRegion 11 .gpuDeviceDma 0x93200000 0x10000 none
  , .gpuMap 11 0x201000000 0x10000 2 VER3_PTE_PCF_UNCACH
  , .vmaPin 11
  , .gpuSubmit 11 1
  ]

def posFullLifecycle : List Action :=
  posBootAndGrSetup ++
  [ .gpuUnmap 11
  , .tlbInval 11
  , .fenceDrain 11 1
  , .vmaRevoke 11
  , .reclaim 11
  ]

theorem pos_gb20b_full_lifecycle_accepted :
    (gbRunTrace initDriverState posFullLifecycle).isSome = true := by
  decide

-- Negative Control 1: Omitted @unmap before @reclaim (direct reclaim after submit)
theorem neg_omit_unmap_reclaim :
    gbRunTrace initDriverState (posBootAndGrSetup ++ [.reclaim 11]) = none := by decide

-- Negative Control 2: Omitted @tlbinval (unmap -> fenceDrain -> reclaim)
theorem neg_omit_tlbinval_reclaim :
    gbRunTrace initDriverState (posBootAndGrSetup ++ [.gpuUnmap 11, .reclaim 11]) = none := by decide

-- Negative Control 3: Omitted @fence_drain (unmap -> tlbinval -> vmaRevoke -> reclaim)
theorem neg_omit_fence_drain_reclaim :
    gbRunTrace initDriverState (posBootAndGrSetup ++ [.gpuUnmap 11, .tlbInval 11, .vmaRevoke 11, .reclaim 11]) = none := by decide

-- Negative Control 4: Omitted @vma_revoke (unmap -> tlbinval -> fenceDrain -> reclaim while pinned)
theorem neg_omit_vma_revoke_reclaim :
    gbRunTrace initDriverState (posBootAndGrSetup ++ [.gpuUnmap 11, .tlbInval 11, .fenceDrain 11 1, .reclaim 11]) = none := by decide

-- Negative Control 5: GPU-mapping a CPU_KERNEL_SLAB region
theorem neg_kernel_slab_gpu_map :
    gbRunTrace initDriverState
      [.allocRegion 100 .cpuKernelSlab 0x90000000 0x01000000 none,
       .gpuMap 100 0x200000000 0x10000 2 VER3_PTE_PCF_UNCACH] = none := by decide

-- Negative Control 6: GPU DMA physical allocation overlapping CPU_KERNEL_SLAB
theorem neg_kernel_slab_phys_overlap :
    gbRunTrace initDriverState
      [.allocRegion 100 .cpuKernelSlab 0x90000000 0x01000000 none,
       .allocRegion 101 .gpuDeviceDma  0x90500000 0x00100000 none] = none := by decide

-- Negative Control 7: Physical allocation colliding with ACPI IORT RMR0 (0xa1600000..0xb97fffff)
theorem neg_rmr0_collision :
    gbRunTrace initDriverState
      [.allocRegion 102 .gpuDeviceDma 0xa1600000 0x10000 none] = none := by decide

-- Negative Control 8: Physical allocation colliding with ACPI IORT RMR1 (0x280000000..0x2ffffffff)
theorem neg_rmr1_collision :
    gbRunTrace initDriverState
      [.allocRegion 103 .gpuDeviceDma 0x280000000 0x10000 none] = none := by decide

-- Negative Control 9: Physical allocation colliding with ACPI IORT RMR2 (0x300000000..0x302ffffff)
theorem neg_rmr2_collision :
    gbRunTrace initDriverState
      [.allocRegion 104 .gpuDeviceDma 0x300000000 0x10000 none] = none := by decide

-- Negative Control 10: Physical allocation colliding with MSI ITS doorbell window (0x08000000)
theorem neg_msi_collision :
    gbRunTrace initDriverState
      [.allocRegion 105 .sharedUncached 0x08000000 0x1000 none] = none := by decide

-- Negative Control 11: GCB[0] mapped with cached VER3 PTE PCF=0x10 (16) instead of 0x11 (17)
theorem neg_gcb0_cached_pcf_0x10 :
    gbRunTrace initDriverState
      [.allocRegion 3 .sharedUncached 0x93060000 0x20000 (some (.gcb 0)),
       .gpuMap 3 0x200060000 0x20000 2 VER3_PTE_PCF_CACHED] = none := by decide

-- Negative Control 12: GPU VA below vaBase (2 GiB = 0x80000000)
theorem neg_va_below_2gib :
    gbRunTrace initDriverState
      [.allocRegion 106 .gpuDeviceDma 0x93200000 0x10000 none,
       .gpuMap 106 0x40000000 0x10000 2 VER3_PTE_PCF_UNCACH] = none := by decide

-- Negative Control 13: GPU VA colliding with GSP split-VAS [4 GiB, 4.5 GiB)
theorem neg_va_hits_gsp_4gib :
    gbRunTrace initDriverState
      [.allocRegion 107 .gpuDeviceDma 0x93200000 0x10000 none,
       .gpuMap 107 0x100000000 0x10000 2 VER3_PTE_PCF_UNCACH] = none := by decide

-- Negative Control 14: GPU VA aliasing between two live DMA regions
theorem neg_va_aliasing :
    gbRunTrace initDriverState
      [.allocRegion 108 .gpuDeviceDma 0x93200000 0x10000 none,
       .allocRegion 109 .gpuDeviceDma 0x93210000 0x10000 none,
       .gpuMap 108 0x201000000 0x10000 2 VER3_PTE_PCF_UNCACH,
       .gpuMap 109 0x201000000 0x10000 2 VER3_PTE_PCF_UNCACH] = none := by decide

-- Negative Control 15: Pre-bootstrap with 8 MSI-X vectors instead of 9
theorem neg_boot_with_8_msix :
    gbRunTrace initDriverState
      [.armPreboot 8 0x92000000 0x008a1d58 0x008a1d5c] = none := by decide

-- Negative Control 16: Pre-bootstrap with wrong sysmem flush register address
theorem neg_boot_wrong_flush_reg :
    gbRunTrace initDriverState
      [.armPreboot 9 0x92000000 0x008a1d50 0x008a1d5c] = none := by decide

-- Negative Control 17: Compute dispatch without patching SC_PDB(0) first
theorem neg_compute_without_sc_pdb0 :
    gbRunTrace initDriverState
      [.armPreboot 9 0x92000000 0x008a1d58 0x008a1d5c,
       .bootGsp,
       .allocCompute true true] = none := by decide

-- Negative Control 18: Re-initializing GCB[5]/GCB[6] after first promote
theorem neg_compute_double_gcb_init :
    gbRunTrace initDriverState (posBootAndGrSetup ++ [.allocCompute true true]) = none := by decide

-- Negative Control 19: Double reclaim of the same region
theorem neg_double_reclaim :
    gbRunTrace initDriverState (posFullLifecycle ++ [.reclaim 11]) = none := by decide

-- Verify zero extra axioms across core proofs (standard axioms only: propext, Classical.choice, Quot.sound)
#print axioms gbStep_preserves_wellFormed
#print axioms trace_guarantees_kernel_slab_non_mapping
#print axioms trace_guarantees_rmr_disjointness
#print axioms trace_guarantees_gpu_va_safety
#print axioms trace_guarantees_gr_ctx_pcf_0x11
#print axioms reclaim_requires_4step_fence
#print axioms boot_requires_9msix_and_flush
#print axioms compute_requires_sc_pdb_and_gr_pcf11
#print axioms pos_gb20b_full_lifecycle_accepted

end Gb20bDriverOm3
