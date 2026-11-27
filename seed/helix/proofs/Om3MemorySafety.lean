/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/Om3MemorySafety.lean

  Machine-checked Lean 4.36.0 soundness proofs for Strand 5 (The Aegis) & OM-3
  Zero-Pointer CFG-Sound Linear Silicon Capability and 4-Step Hardware DMA-Fence Profile.

  Exact 1:1 model of `seed/helix/strand5_aegis/om3_aegis.om` and `spec/omegese-om3.md` §2.
  Born from RCCA `evidence/RCCA-SPARK-DMA-UAF-20261126/` (legacy C `aien_gpu.ko` DMA UAF
  that overwrote Linux VFS `inode_cache` slab memory with raw f32 tensor data).

  Proves BOTH local step inversions AND full global multi-step trace preservation
  (`step_preserves_wellFormed`, `runTrace_preserves_wellFormed`, `trace_guarantees_kernel_slab_isolation`).

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

theorem intervalsDisjoint_symm {a0 al b0 bl : Nat}
    (h : intervalsDisjoint a0 al b0 bl) : intervalsDisjoint b0 bl a0 al := by
  unfold intervalsDisjoint at h ⊢
  rcases h with h1 | h2 | h3 | h4
  · exact Or.inr (Or.inl h1)
  · exact Or.inl h2
  · exact Or.inr (Or.inr (Or.inr h3))
  · exact Or.inr (Or.inr (Or.inl h4))

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
      if r.lstate != .live || r.dom == .cpuKernelSlab || r.mstate == .pteCleared || r.mstate == .tlbFlushed then none
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
      else if r.mstate == .mapped && off + alen > r.gvlen then none
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

/-- Every region has bounded non-zero size, bounded GPU VA, kernel-slab isolation, and DMA integrity. -/
def RegionSafe (r : Region) : Prop :=
  r.psize > 0 ∧
  r.pbase + r.psize < U64_LIMIT ∧
  r.gvlen ≤ r.psize ∧
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

/-- Uniqueness of region IDs in state list. -/
def UniqueIds (s : State) : Prop :=
  ∀ r1 ∈ s, ∀ r2 ∈ s, r1.rid = r2.rid → r1 = r2

def WellFormed (s : State) : Prop :=
  UniqueIds s ∧
  (∀ r ∈ s, RegionSafe r) ∧
  (∀ r1 ∈ s, ∀ r2 ∈ s, PairSafe r1 r2)

theorem empty_wellFormed : WellFormed [] := by
  refine ⟨?_, ?_, ?_⟩ <;> simp [UniqueIds]

private theorem findReg_mem {s : State} {rid : Nat} {r : Region}
    (h : findReg s rid = some r) : r ∈ s ∧ r.rid = rid := by
  unfold findReg at h
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  exact ⟨hm, beq_iff_eq.mp hp⟩

private theorem findReg_none_forall {s : State} {rid : Nat}
    (h : findReg s rid = none) : ∀ r ∈ s, r.rid ≠ rid := by
  unfold findReg at h
  intro r hr heq
  have hp := List.find?_eq_none.mp h r hr
  simp [heq] at hp

private theorem uniqueIds_updateReg {s : State} {rid : Nat} {f : Region → Region}
    (hu : UniqueIds s) (hkeep : ∀ x, (f x).rid = x.rid) :
    UniqueIds (updateReg s rid f) := by
  intro a ha b hb heq
  unfold updateReg at ha hb
  rw [List.mem_map] at ha hb
  rcases ha with ⟨x, hx, rfl⟩
  rcases hb with ⟨y, hy, rfl⟩
  have hrx : (if x.rid == rid then f x else x).rid = x.rid := by
    split <;> simp [hkeep]
  have hry : (if y.rid == rid then f y else y).rid = y.rid := by
    split <;> simp [hkeep]
  rw [hrx, hry] at heq
  have hxy := hu x hx y hy heq
  subst hxy
  rfl

-- ==================== GLOBAL INDUCTIVE PRESERVATION THEOREM ====================

/-- Global Inductive Safety Theorem: EVERY accepted OM-3 transition preserves `WellFormed`:
    unique IDs, non-wrapping physical bounds, GPU VA bounds, strict `cpuKernelSlab` isolation,
    reclaimed-DMA fence integrity, and pairwise physical + GPU VA disjointness across all live regions. -/
theorem step_preserves_wellFormed (s s' : State) (a : Action)
    (hwf : WellFormed s) (h : step s a = some s') :
    WellFormed s' := by
  rcases hwf with ⟨huniq, hreg, hpair⟩
  cases a with
  | allocRegion rid dom pbase psize =>
    simp only [step] at h
    split at h
    · contradiction
    · rename_i hsz
      split at h
      · contradiction
      · rename_i hnf
        split at h
        · contradiction
        · rename_i hnoov
          injection h with hs'
          subst hs'
          simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or] at hsz
          have hfn : findReg s rid = none := by
            cases hfr : findReg s rid
            · rfl
            · simp [hfr] at hnf
          have hfresh := findReg_none_forall hfn
          have hdisj_all : ∀ r ∈ s, r.lstate = .live → intervalsDisjoint pbase psize r.pbase r.psize := by
            intro r hr hlive
            have hfalse : s.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize) = false := by
              cases hb : s.any (fun x => x.lstate == .live && intervalsOverlap pbase psize x.pbase x.psize)
              · rfl
              · exact absurd hb hnoov
            have hm := List.any_eq_false.mp hfalse r hr
            simp only [hlive, beq_self_eq_true, Bool.true_and] at hm
            have hovf : intervalsOverlap pbase psize r.pbase r.psize = false := by
              cases hov : intervalsOverlap pbase psize r.pbase r.psize
              · rfl
              · simp [hov] at hm
            exact (overlap_false_iff_disjoint pbase psize r.pbase r.psize).mp hovf
          refine ⟨?_, ?_, ?_⟩
          · intro r1 hr1 r2 hr2 heq
            rcases List.mem_cons.mp hr1 with rfl | hr1' <;> rcases List.mem_cons.mp hr2 with rfl | hr2'
            · rfl
            · exact absurd heq.symm (hfresh r2 hr2')
            · exact absurd heq (hfresh r1 hr1')
            · exact huniq r1 hr1' r2 hr2' heq
          · intro r hr
            rcases List.mem_cons.mp hr with rfl | hr'
            · dsimp only [RegionSafe]
              refine ⟨by omega, by omega, by omega, ?_, ?_⟩
              · intro _; exact ⟨rfl, rfl, rfl, rfl⟩
              · intro hrec; cases hrec
            · exact hreg r hr'
          · intro r1 hr1 r2 hr2 hne hl1 hl2
            rcases List.mem_cons.mp hr1 with rfl | hr1' <;> rcases List.mem_cons.mp hr2 with rfl | hr2'
            · exact absurd rfl hne
            · refine ⟨hdisj_all r2 hr2' hl2, ?_⟩
              intro hgv; dsimp only at hgv; omega
            · refine ⟨intervalsDisjoint_symm (hdisj_all r1 hr1' hl1), ?_⟩
              intro _ hgv; dsimp only at hgv; omega
            · exact hpair r1 hr1' r2 hr2' hne hl1 hl2

  | gpuMap rid va vlen =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hlive
        split at h
        · contradiction
        · rename_i hnotk
          split at h
          · contradiction
          · rename_i hunm
            split at h
            · contradiction
            · rename_i hvbnd
              split at h
              · contradiction
              · rename_i hnoov
                injection h with hs'
                subst hs'
                have ⟨hrmem, hrid⟩ := findReg_mem hf
                simp only [Bool.or_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, decide_eq_true_eq, not_or] at hlive hnotk hunm hvbnd
                have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
                have hdisj_va : ∀ o ∈ s, o.lstate = .live → o.gvlen > 0 → intervalsDisjoint va vlen o.gva o.gvlen := by
                  intro o ho hol hog
                  have hfalse : s.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen) = false := by
                    cases hb : s.any (fun x => x.lstate == .live && x.gvlen > 0 && intervalsOverlap va vlen x.gva x.gvlen)
                    · rfl
                    · exact absurd hb hnoov
                  have hm := List.any_eq_false.mp hfalse o ho
                  simp only [hol, beq_self_eq_true, Bool.true_and, decide_eq_true hog] at hm
                  have hovf : intervalsOverlap va vlen o.gva o.gvlen = false := by
                    cases hov : intervalsOverlap va vlen o.gva o.gvlen
                    · rfl
                    · simp [hov] at hm
                  exact (overlap_false_iff_disjoint va vlen o.gva o.gvlen).mp hovf
                refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
                · intro x hx
                  unfold updateReg at hx
                  rw [List.mem_map] at hx
                  rcases hx with ⟨y, hy, rfl⟩
                  by_cases hyr : y.rid == rid
                  · simp only [hyr, ↓reduceIte]
                    have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
                    subst hyeq
                    have hys := hreg y hy
                    dsimp only [RegionSafe]
                    refine ⟨hys.1, hys.2.1, by omega, ?_, ?_⟩
                    · intro hdom; exact absurd hdom hnotk
                    · intro hrec; rw [hrlive] at hrec; cases hrec
                  · simp only [hyr, Bool.false_eq_true, ↓reduceIte]
                    exact hreg y hy
                · intro a ha b hb hne hla hlb
                  unfold updateReg at ha hb
                  rw [List.mem_map] at ha hb
                  rcases ha with ⟨x, hx, rfl⟩
                  rcases hb with ⟨y, hy, rfl⟩
                  by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid
                  · simp only [hxr, hyr, ↓reduceIte] at hne
                    have hxe : x.rid = rid := beq_iff_eq.mp hxr
                    have hye : y.rid = rid := beq_iff_eq.mp hyr
                    exact absurd (by rw [hxe, hye]) hne
                  · simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
                    have hpx := hpair x hx y hy hne hla hlb
                    exact ⟨hpx.1, fun _ hygv => hdisj_va y hy hlb hygv⟩
                  · simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
                    have hpx := hpair x hx y hy hne hla hlb
                    exact ⟨hpx.1, fun hxgv _ => intervalsDisjoint_symm (hdisj_va x hx hla hxgv)⟩
                  · simp only [hxr, hyr, Bool.false_eq_true, ↓reduceIte] at hne hla hlb ⊢
                    exact hpair x hx y hy hne hla hlb

  | vmaPin rid =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom; exact absurd hdom hok.1.1.2
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | gpuSubmit rid ep =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, decide_eq_true_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom; exact absurd hdom hok.1.1.2
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | staticAccess rid off alen =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · split at h
        · contradiction
        · split at h
          · contradiction
          · split at h
            · contradiction
            · injection h with hs'; subst hs'; exact ⟨huniq, hreg, hpair⟩

  | gpuUnmap rid =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        have hrmap : r.mstate = .mapped := by cases hm : r.mstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom
              have hku := (hys.2.2.2.1 hdom).1
              rw [hrmap] at hku; cases hku
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | tlbInval rid =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        have hrclr : r.mstate = .pteCleared := by cases hm : r.mstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom
              have hku := (hys.2.2.2.1 hdom).1
              rw [hrclr] at hku; cases hku
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | fenceDrain rid ep =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, decide_eq_true_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        have hrtlb : r.mstate = .tlbFlushed := by cases hm : r.mstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom
              have hku := (hys.2.2.2.1 hdom).1
              rw [hrtlb] at hku; cases hku
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | vmaRevoke rid =>
    simp only [step] at h
    cases hf : findReg s rid with
    | none => simp [hf] at h
    | some r =>
      simp only [hf] at h
      split at h
      · contradiction
      · rename_i hok
        injection h with hs'
        subst hs'
        have ⟨hrmem, hrid⟩ := findReg_mem hf
        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or] at hok
        have hrlive : r.lstate = .live := by cases hl : r.lstate <;> simp_all
        refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
        · intro x hx
          unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
          by_cases hyr : y.rid == rid
          · simp only [hyr, ↓reduceIte]
            have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
            subst hyeq; have hys := hreg y hy
            refine ⟨hys.1, hys.2.1, hys.2.2.1, ?_, ?_⟩
            · intro hdom
              have hkv := (hys.2.2.2.1 hdom).2.2.2
              exact absurd hkv hok.2
            · intro hrec; rw [hrlive] at hrec; cases hrec
          · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
        · intro a ha b hb hne hla hlb
          unfold updateReg at ha hb; rw [List.mem_map] at ha hb
          rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
          by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
            simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
          all_goals exact hpair x hx y hy hne hla hlb

  | reclaim rid =>
    simp only [step] at h
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
              injection h with hs'
              subst hs'
              have ⟨hrmem, hrid⟩ := findReg_mem hf
              simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, not_or, Nat.not_lt] at hlive hmap hdma hvma
              refine ⟨uniqueIds_updateReg huniq (fun _ => rfl), ?_, ?_⟩
              · intro x hx
                unfold updateReg at hx; rw [List.mem_map] at hx; rcases hx with ⟨y, hy, rfl⟩
                by_cases hyr : y.rid == rid
                · simp only [hyr, ↓reduceIte]
                  have hyeq : y = r := huniq y hy r hrmem (by rw [beq_iff_eq.mp hyr, hrid])
                  subst hyeq; have hys := hreg y hy
                  dsimp only [RegionSafe]
                  refine ⟨hys.1, hys.2.1, by omega, ?_, ?_⟩
                  · intro hdom
                    have hk := hys.2.2.2.1 hdom
                    exact ⟨hk.1, rfl, hk.2.2.1, hk.2.2.2⟩
                  · intro _; exact ⟨hmap.1, hmap.2, hdma, by omega, rfl⟩
                · simp only [hyr, Bool.false_eq_true, ↓reduceIte]; exact hreg y hy
              · intro a ha b hb hne hla hlb
                unfold updateReg at ha hb; rw [List.mem_map] at ha hb
                rcases ha with ⟨x, hx, rfl⟩; rcases hb with ⟨y, hy, rfl⟩
                by_cases hxr : x.rid == rid <;> by_cases hyr : y.rid == rid <;>
                  simp only [hxr, hyr, ↓reduceIte, Bool.false_eq_true] at hne hla hlb ⊢
                · cases hla
                · cases hla
                · cases hlb
                · exact hpair x hx y hy hne hla hlb

/-- Multi-step Trace Preservation Theorem: ANY OM-3 trace of ANY length accepted from the empty state
    yields a globally `WellFormed` hardware memory state. -/
theorem runTrace_preserves_wellFormed (acts : List Action) (s s' : State)
    (hwf : WellFormed s) (h : runTrace s acts = some s') :
    WellFormed s' := by
  induction acts generalizing s with
  | nil =>
    simp [runTrace] at h
    subst h
    exact hwf
  | cons a rest ih =>
    simp only [runTrace] at h
    cases hs : step s a with
    | none => simp [hs] at h
    | some s1 =>
      simp only [hs] at h
      exact ih s1 (step_preserves_wellFormed s s1 a hwf hs) h

/-- Corollary (Global Kernel-Slab Non-Interference Across Arbitrary Traces):
    In ANY state reachable by an accepted OM-3 trace of ANY length, NO `cpuKernelSlab` region
    can EVER be GPU-mapped, hold a non-zero GPU VA, have active GPU DMA epochs, have VMA pins,
    or physically overlap any other live region. -/
theorem trace_guarantees_kernel_slab_isolation (acts : List Action) (s' : State)
    (h : runTrace [] acts = some s') :
    ∀ r ∈ s', r.dom = .cpuKernelSlab →
      r.mstate = .unmapped ∧ r.gvlen = 0 ∧ r.epoch = 0 ∧ r.vmaPins = 0 ∧
      (r.lstate = .live → ∀ o ∈ s', o.rid ≠ r.rid → o.lstate = .live →
        intervalsDisjoint r.pbase r.psize o.pbase o.psize) := by
  have hwf := runTrace_preserves_wellFormed acts [] s' empty_wellFormed h
  rcases hwf with ⟨_, hreg, hpair⟩
  intro r hr hdom
  have hk := (hreg r hr).2.2.2.1 hdom
  refine ⟨hk.1, hk.2.1, hk.2.2.1, hk.2.2.2, ?_⟩
  intro hlive o ho hne hol
  exact (hpair r hr o ho hne.symm hlive hol).1

-- ==================== LOCAL STEP SECURITY THEOREMS ====================

/-- Theorem 1 (4-Step Linear Fence Necessity). -/
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

/-- Theorem 2 (Zero-Runtime-Overhead Static Bounds Soundness — BOTH Physical AND Mapped GPU VA Bounds). -/
theorem static_access_in_bounds (s s' : State) (rid off alen : Nat)
    (h : step s (.staticAccess rid off alen) = some s') :
    ∃ r, findReg s rid = some r ∧
      r.lstate = .live ∧
      alen > 0 ∧
      off + alen < U64_LIMIT ∧
      off + alen ≤ r.psize ∧
      (r.mstate = .mapped → off + alen ≤ r.gvlen) := by
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
          split at h
          · contradiction
          · rename_i hgv
            simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, not_or, not_and, bne_iff_ne, ne_eq] at hlive hbnd hgv
            refine ⟨r, rfl, ?_, by omega, by omega, by omega, ?_⟩
            · cases hl : r.lstate
              · rfl
              · exfalso; exact hlive (by simp [hl])
            · intro hmp
              have hle := hgv hmp
              omega

-- ==================== CONSTRUCTIVE POSITIVE & NEGATIVE CONTROLS ====================

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

theorem pos_safe_gpu_lifecycle_accepted : (runTrace [] safeGpuTrace).isSome = true := by decide

theorem cex_aien_gpu_unfenced_reclaim_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .reclaim 2
    ] = none := by decide

theorem cex_aien_gpu_missing_tlb_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .gpuUnmap 2,
      .reclaim 2
    ] = none := by decide

theorem cex_aien_gpu_missing_fence_drain_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuSubmit 2 1,
      .gpuUnmap 2,
      .tlbInval 2,
      .reclaim 2
    ] = none := by decide

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
    ] = none := by decide

theorem cex_aien_gpu_va_aliasing_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .allocRegion 3 .gpuDeviceDma 0x30000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuMap 3 0x200200000 0x200000
    ] = none := by decide

theorem cex_aien_gpu_uaf_after_reclaim_refused :
    runTrace [] (safeGpuTrace ++ [.staticAccess 2 0 64]) = none := by decide

theorem cex_kernel_slab_gpu_map_refused :
    runTrace [] [
      .allocRegion 1 .cpuKernelSlab 0x10000000 0x100000,
      .gpuMap 1 0x200000000 0x100000
    ] = none := by decide

/-- Negative Control 8 (RCCA v2 audit finding S5-4): GPU access past mapped `gvlen` (< `psize`) -> REFUSED. -/
theorem cex_gpu_access_past_vlen_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x1000,
      .staticAccess 2 0x2000 0x1000
    ] = none := by decide

/-- Negative Control 9: VMA pin after PTE unmap -> REFUSED. -/
theorem cex_vma_pin_after_unmap_refused :
    runTrace [] [
      .allocRegion 2 .gpuDeviceDma 0x20000000 0x400000,
      .gpuMap 2 0x200000000 0x400000,
      .gpuUnmap 2,
      .vmaPin 2
    ] = none := by decide

end Om3MemorySafety

#print axioms Om3MemorySafety.step_preserves_wellFormed
#print axioms Om3MemorySafety.runTrace_preserves_wellFormed
#print axioms Om3MemorySafety.trace_guarantees_kernel_slab_isolation
#print axioms Om3MemorySafety.reclaim_requires_full_4step_fence
#print axioms Om3MemorySafety.static_access_in_bounds
#print axioms Om3MemorySafety.pos_safe_gpu_lifecycle_accepted
#print axioms Om3MemorySafety.cex_gpu_access_past_vlen_refused
#print axioms Om3MemorySafety.cex_vma_pin_after_unmap_refused
