/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/CaReversibleSoundness.lean

  Machine-checked Lean 4.36.0 soundness proof for Wave 4 Breakthrough:
  Lean-4-Proven Strictly Bit-Reversible Lossless Cellular Automaton (`OMCA01`)
  (`apps/omega-ca/ca_engine.om`, `apps/omega-ca/emit_ca_ir.om`, `apps/omega-ca/gate_ca.om`).

  Zero `sorry`, zero warnings (`-DwarningAsError=true`), zero Mathlib dependency,
  standard Lean 4 core axioms only (`propext`, `Classical.choice`, `Quot.sound`).

  Model-to-System Link:
    1. 4-bit block rule `fwdBlock` / `invBlock` (`Fin 16`) mirrors `bbm_fwd_block` in
       `apps/omega-ca/ca_engine.om` (cell-by-cell OM-2 scalar oracle).
    2. Branchless 4-bit SWAR formula `swarBlock` mirrors the exact 64-bit word-parallel
       boolean ops (`pop1`, `diag`, `pad`, `pbc`, `a'`, `b'`, `c'`, `d'`) emitted into
       binary ΩIR by `apps/omega-ca/emit_ca_ir.om` (`ca_worker`).
       `swarBlock_eq_fwdBlock` proves both implementations compute the identical bijection
       across all 16 neighborhood configurations.
    3. Arbitrary `(2*wx) × (2*hy)` toroidal 2D grid evolution (`stepEvenWith`, `stepOddWith`,
       `evolveFrom`, `reverseFrom`) with alternating `(0,0)` / `(1,1)` Margolus partitions
       proves exact multi-step reversibility (`reverseFrom_evolveFrom`) and exact per-step
       particle energy conservation (`evolveFrom_conserves_pop`, `reverseFrom_conserves_pop`).
    4. Row-radius causal light-cone lemma (`stepFwd_light_cone`, `evolveFrom_halo_sound`)
       proves that a worker owning `[lo, hi)` with `steps` halo rows above and below
       computes bit-exact rows `[lo, hi)` across `steps` consecutive generations.
    5. Concrete `decide` checks verify an asymmetric 6×6 colliding glider evolution
       (`T = 6` steps forward and reverse, head-on collision at step 1) plus negative controls
       matching `gate_ca.om`.
-/

namespace CaReversibleSoundness

-- =========================================================================
-- Section 1: 4-Bit Margolus BBM Block Rule & SWAR Equivalence
-- =========================================================================

def bitAt (n k : Nat) : Nat :=
  (n >>> k) &&& 1

def pop4 (x : Fin 16) : Nat :=
  bitAt x.val 0 + bitAt x.val 1 + bitAt x.val 2 + bitAt x.val 3

/-- Margolus Billiard-Ball Model (BBM) 2x2 neighborhood transition on `Fin 16`:
    bits: 0=top-left(a), 1=top-right(b), 2=bottom-left(c), 3=bottom-right(d).
    - Single particle bounces diagonally: 1 <-> 8, 2 <-> 4.
    - Head-on 2-particle diagonal collision rotates 90 deg: 6 <-> 9.
    - All other states (0, 3, 5, 7, 10, 11, 12, 13, 14, 15) stay fixed. -/
def fwdBlock (x : Fin 16) : Fin 16 :=
  match x.val with
  | 1 => ⟨8, by decide⟩
  | 8 => ⟨1, by decide⟩
  | 2 => ⟨4, by decide⟩
  | 4 => ⟨2, by decide⟩
  | 6 => ⟨9, by decide⟩
  | 9 => ⟨6, by decide⟩
  | _ => x

/-- Explicit inverse rule for Margolus BBM (involutive). -/
def invBlock (x : Fin 16) : Fin 16 :=
  match x.val with
  | 8 => ⟨1, by decide⟩
  | 1 => ⟨8, by decide⟩
  | 4 => ⟨2, by decide⟩
  | 2 => ⟨4, by decide⟩
  | 9 => ⟨6, by decide⟩
  | 6 => ⟨9, by decide⟩
  | _ => x

/-- Branchless bitwise SWAR formulation emitted by `apps/omega-ca/emit_ca_ir.om`.
    Operates simultaneously on 32 blocks per `u64` row-pair using pure bitwise ops. -/
def swarBlock (x : Fin 16) : Fin 16 :=
  let a := bitAt x.val 0
  let b := bitAt x.val 1
  let c := bitAt x.val 2
  let d := bitAt x.val 3
  let pop1 := (((a ^^^ b) &&& (1 - c) &&& (1 - d)) ||| ((c ^^^ d) &&& (1 - a) &&& (1 - b))) &&& 1
  let diag := ((a ^^^ b) &&& (1 - (a ^^^ d)) &&& (1 - (b ^^^ c))) &&& 1
  let pad := pop1 &&& (a ^^^ d)
  let pbc := pop1 &&& (b ^^^ c)
  let a' := (a ^^^ pad) ^^^ diag
  let b' := (b ^^^ pbc) ^^^ diag
  let c' := (c ^^^ pbc) ^^^ diag
  let d' := (d ^^^ pad) ^^^ diag
  ⟨(a' + 2 * b' + 4 * c' + 8 * d') % 16, Nat.mod_lt _ (by decide)⟩

theorem fwdBlock_involutive : ∀ x : Fin 16, fwdBlock (fwdBlock x) = x := by
  decide

theorem invBlock_fwdBlock : ∀ x : Fin 16, invBlock (fwdBlock x) = x := by
  decide

theorem fwdBlock_invBlock : ∀ x : Fin 16, fwdBlock (invBlock x) = x := by
  decide

theorem fwdBlock_injective : ∀ x y : Fin 16, fwdBlock x = fwdBlock y → x = y := by
  decide

theorem fwdBlock_surjective : ∀ y : Fin 16, ∃ x : Fin 16, fwdBlock x = y := by
  decide

theorem fwdBlock_conserves_pop : ∀ x : Fin 16, pop4 (fwdBlock x) = pop4 x := by
  decide

theorem invBlock_conserves_pop : ∀ x : Fin 16, pop4 (invBlock x) = pop4 x := by
  decide

theorem swarBlock_eq_fwdBlock : ∀ x : Fin 16, swarBlock x = fwdBlock x := by
  decide

-- =========================================================================
-- Section 2: List-Level Block-Grid Induction Theorems
-- =========================================================================

def mapFwd (bs : List (Fin 16)) : List (Fin 16) :=
  bs.map fwdBlock

def mapInv (bs : List (Fin 16)) : List (Fin 16) :=
  bs.map invBlock

def popSum : List (Fin 16) → Nat
  | [] => 0
  | b :: rest => pop4 b + popSum rest

theorem mapInv_mapFwd (bs : List (Fin 16)) : mapInv (mapFwd bs) = bs := by
  induction bs with
  | nil => rfl
  | cons b rest ih =>
    simp only [mapInv, mapFwd, List.map_cons, invBlock_fwdBlock]
    exact congrArg (b :: ·) ih

theorem mapFwd_mapInv (bs : List (Fin 16)) : mapFwd (mapInv bs) = bs := by
  induction bs with
  | nil => rfl
  | cons b rest ih =>
    simp only [mapFwd, mapInv, List.map_cons, fwdBlock_invBlock]
    exact congrArg (b :: ·) ih

theorem mapFwd_conserves_pop (bs : List (Fin 16)) : popSum (mapFwd bs) = popSum bs := by
  induction bs with
  | nil => rfl
  | cons b rest ih =>
    simp only [mapFwd, List.map_cons, popSum, fwdBlock_conserves_pop]
    exact congrArg (pop4 b + ·) ih

theorem mapInv_conserves_pop (bs : List (Fin 16)) : popSum (mapInv bs) = popSum bs := by
  induction bs with
  | nil => rfl
  | cons b rest ih =>
    simp only [mapInv, List.map_cons, popSum, invBlock_conserves_pop]
    exact congrArg (pop4 b + ·) ih

-- =========================================================================
-- Section 3: Arbitrary (2*wx) × (2*hy) Toroidal Grid Model & Multi-Step Proofs
-- =========================================================================

abbrev Grid (wx hy : Nat) := Fin (2 * wx) → Fin (2 * hy) → Bool

def boolBit (b : Bool) : Nat :=
  if b then 1 else 0

private theorem bitAt_pack4 (b0 b1 b2 b3 : Bool) :
    bitAt (boolBit b0 + 2 * boolBit b1 + 4 * boolBit b2 + 8 * boolBit b3) 0 = boolBit b0 ∧
    bitAt (boolBit b0 + 2 * boolBit b1 + 4 * boolBit b2 + 8 * boolBit b3) 1 = boolBit b1 ∧
    bitAt (boolBit b0 + 2 * boolBit b1 + 4 * boolBit b2 + 8 * boolBit b3) 2 = boolBit b2 ∧
    bitAt (boolBit b0 + 2 * boolBit b1 + 4 * boolBit b2 + 8 * boolBit b3) 3 = boolBit b3 := by
  cases b0 <;> cases b1 <;> cases b2 <;> cases b3 <;> decide

private theorem pack4_lt16 (b0 b1 b2 b3 : Bool) :
    boolBit b0 + 2 * boolBit b1 + 4 * boolBit b2 + 8 * boolBit b3 < 16 := by
  cases b0 <;> cases b1 <;> cases b2 <;> cases b3 <;> decide

private theorem pack4_reconstruct (n : Fin 16) :
    bitAt n.val 0 + 2 * bitAt n.val 1 + 4 * bitAt n.val 2 + 8 * bitAt n.val 3 = n.val := by
  revert n
  decide

def readBlock {wx hy : Nat} (g : Grid wx hy) (bx : Fin wx) (by_ : Fin hy) : Fin 16 :=
  let x0 : Fin (2 * wx) := ⟨2 * bx.val, by omega⟩
  let x1 : Fin (2 * wx) := ⟨2 * bx.val + 1, by omega⟩
  let y0 : Fin (2 * hy) := ⟨2 * by_.val, by omega⟩
  let y1 : Fin (2 * hy) := ⟨2 * by_.val + 1, by omega⟩
  ⟨boolBit (g x0 y0) + 2 * boolBit (g x1 y0) + 4 * boolBit (g x0 y1) + 8 * boolBit (g x1 y1),
    pack4_lt16 (g x0 y0) (g x1 y0) (g x0 y1) (g x1 y1)⟩

def stepEvenWith {wx hy : Nat} (rule : Fin 16 → Fin 16) (g : Grid wx hy) : Grid wx hy :=
  fun x y =>
    let bx : Fin wx := ⟨x.val / 2, by omega⟩
    let by_ : Fin hy := ⟨y.val / 2, by omega⟩
    let blk := rule (readBlock g bx by_)
    let k := 2 * (y.val % 2) + (x.val % 2)
    bitAt blk.val k == 1

private theorem stepEvenWith_eval {wx hy : Nat}
    (rule : Fin 16 → Fin 16) (g : Grid wx hy) (x : Fin (2 * wx)) (y : Fin (2 * hy)) :
    stepEvenWith rule g x y =
      (bitAt (rule (readBlock g ⟨x.val / 2, by omega⟩ ⟨y.val / 2, by omega⟩)).val
        (2 * (y.val % 2) + (x.val % 2)) == 1) :=
  rfl

private theorem boolBit_beq_bitAt (v : Fin 16) (k : Fin 4) :
    boolBit (bitAt v.val k.val == 1) = bitAt v.val k.val := by
  revert v k
  decide

private theorem readBlock_stepEvenWith {wx hy : Nat}
    (rule : Fin 16 → Fin 16) (g : Grid wx hy) (bx : Fin wx) (by_ : Fin hy) :
    readBlock (stepEvenWith rule g) bx by_ = rule (readBlock g bx by_) := by
  apply Fin.ext
  unfold readBlock stepEvenWith
  have hx0 : (2 * bx.val) / 2 = bx.val := by omega
  have hx1 : (2 * bx.val + 1) / 2 = bx.val := by omega
  have hy0 : (2 * by_.val) / 2 = by_.val := by omega
  have hy1 : (2 * by_.val + 1) / 2 = by_.val := by omega
  have mx0 : (2 * bx.val) % 2 = 0 := by omega
  have mx1 : (2 * bx.val + 1) % 2 = 1 := by omega
  have my0 : (2 * by_.val) % 2 = 0 := by omega
  have my1 : (2 * by_.val + 1) % 2 = 1 := by omega
  simp only [hx0, hx1, hy0, hy1, mx0, mx1, my0, my1, Fin.eta]
  have hb0 := boolBit_beq_bitAt (rule (readBlock g bx by_)) ⟨0, by decide⟩
  have hb1 := boolBit_beq_bitAt (rule (readBlock g bx by_)) ⟨1, by decide⟩
  have hb2 := boolBit_beq_bitAt (rule (readBlock g bx by_)) ⟨2, by decide⟩
  have hb3 := boolBit_beq_bitAt (rule (readBlock g bx by_)) ⟨3, by decide⟩
  simp only at hb0 hb1 hb2 hb3
  rw [hb0, hb1, hb2, hb3]
  exact pack4_reconstruct (rule (readBlock g bx by_))

private theorem stepEvenWith_compose_id {wx hy : Nat}
    (r1 r2 : Fin 16 → Fin 16) (hinv : ∀ z : Fin 16, r2 (r1 z) = z)
    (g : Grid wx hy) :
    stepEvenWith r2 (stepEvenWith r1 g) = g := by
  funext x y
  rw [stepEvenWith_eval r2 (stepEvenWith r1 g) x y]
  rw [readBlock_stepEvenWith r1 g ⟨x.val / 2, by omega⟩ ⟨y.val / 2, by omega⟩]
  rw [hinv]
  have hbits := bitAt_pack4
    (g ⟨2 * (x.val / 2), by omega⟩ ⟨2 * (y.val / 2), by omega⟩)
    (g ⟨2 * (x.val / 2) + 1, by omega⟩ ⟨2 * (y.val / 2), by omega⟩)
    (g ⟨2 * (x.val / 2), by omega⟩ ⟨2 * (y.val / 2) + 1, by omega⟩)
    (g ⟨2 * (x.val / 2) + 1, by omega⟩ ⟨2 * (y.val / 2) + 1, by omega⟩)
  unfold readBlock
  dsimp only
  rcases Nat.mod_two_eq_zero_or_one x.val with hxm | hxm <;>
    rcases Nat.mod_two_eq_zero_or_one y.val with hym | hym
  · simp only [hxm, hym]
    rw [hbits.1]
    have hx' : (⟨2 * (x.val / 2), by omega⟩ : Fin (2 * wx)) = x := Fin.ext (by dsimp only; omega)
    have hy' : (⟨2 * (y.val / 2), by omega⟩ : Fin (2 * hy)) = y := Fin.ext (by dsimp only; omega)
    rw [hx', hy']
    cases g x y <;> rfl
  · simp only [hxm, hym]
    rw [hbits.2.2.1]
    have hx' : (⟨2 * (x.val / 2), by omega⟩ : Fin (2 * wx)) = x := Fin.ext (by dsimp only; omega)
    have hy' : (⟨2 * (y.val / 2) + 1, by omega⟩ : Fin (2 * hy)) = y := Fin.ext (by dsimp only; omega)
    rw [hx', hy']
    cases g x y <;> rfl
  · simp only [hxm, hym]
    rw [hbits.2.1]
    have hx' : (⟨2 * (x.val / 2) + 1, by omega⟩ : Fin (2 * wx)) = x := Fin.ext (by dsimp only; omega)
    have hy' : (⟨2 * (y.val / 2), by omega⟩ : Fin (2 * hy)) = y := Fin.ext (by dsimp only; omega)
    rw [hx', hy']
    cases g x y <;> rfl
  · simp only [hxm, hym]
    rw [hbits.2.2.2]
    have hx' : (⟨2 * (x.val / 2) + 1, by omega⟩ : Fin (2 * wx)) = x := Fin.ext (by dsimp only; omega)
    have hy' : (⟨2 * (y.val / 2) + 1, by omega⟩ : Fin (2 * hy)) = y := Fin.ext (by dsimp only; omega)
    rw [hx', hy']
    cases g x y <;> rfl

def shiftIdx (m : Nat) (hm : 0 < m) (i : Fin m) : Fin m :=
  ⟨(i.val + 1) % m, Nat.mod_lt _ hm⟩

def unshiftIdx (m : Nat) (hm : 0 < m) (i : Fin m) : Fin m :=
  ⟨(i.val + (m - 1)) % m, Nat.mod_lt _ hm⟩

theorem unshiftIdx_shiftIdx (m : Nat) (hm : 0 < m) (i : Fin m) :
    unshiftIdx m hm (shiftIdx m hm i) = i := by
  apply Fin.ext
  unfold unshiftIdx shiftIdx
  dsimp only
  have h1 : ((i.val + 1) % m + (m - 1)) % m = (i.val + 1 + (m - 1)) % m := by
    rw [Nat.add_mod, Nat.mod_mod_of_dvd _ (Nat.dvd_refl m), ← Nat.add_mod]
  rw [h1]
  have h2 : i.val + 1 + (m - 1) = i.val + m := by omega
  rw [h2, Nat.add_mod_right, Nat.mod_eq_of_lt i.isLt]

theorem shiftIdx_unshiftIdx (m : Nat) (hm : 0 < m) (i : Fin m) :
    shiftIdx m hm (unshiftIdx m hm i) = i := by
  apply Fin.ext
  unfold shiftIdx unshiftIdx
  dsimp only
  have h1 : ((i.val + (m - 1)) % m + 1) % m = (i.val + (m - 1) + 1) % m := by
    rw [Nat.add_mod, Nat.mod_mod_of_dvd _ (Nat.dvd_refl m), ← Nat.add_mod]
  rw [h1]
  have h2 : i.val + (m - 1) + 1 = i.val + m := by omega
  rw [h2, Nat.add_mod_right, Nat.mod_eq_of_lt i.isLt]

def shiftGrid {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) : Grid wx hy :=
  fun x y => g (shiftIdx (2 * wx) (by omega) x) (shiftIdx (2 * hy) (by omega) y)

def unshiftGrid {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) : Grid wx hy :=
  fun x y => g (unshiftIdx (2 * wx) (by omega) x) (unshiftIdx (2 * hy) (by omega) y)

theorem unshift_shift_grid {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) :
    unshiftGrid hw hh (shiftGrid hw hh g) = g := by
  funext x y
  unfold unshiftGrid shiftGrid
  rw [shiftIdx_unshiftIdx, shiftIdx_unshiftIdx]

theorem shift_unshift_grid {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) :
    shiftGrid hw hh (unshiftGrid hw hh g) = g := by
  funext x y
  unfold shiftGrid unshiftGrid
  rw [unshiftIdx_shiftIdx, unshiftIdx_shiftIdx]

def stepOddWith {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (rule : Fin 16 → Fin 16) (g : Grid wx hy) : Grid wx hy :=
  unshiftGrid hw hh (stepEvenWith rule (shiftGrid hw hh g))

private theorem stepOddWith_compose_id {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (r1 r2 : Fin 16 → Fin 16) (hinv : ∀ z : Fin 16, r2 (r1 z) = z)
    (g : Grid wx hy) :
    stepOddWith hw hh r2 (stepOddWith hw hh r1 g) = g := by
  unfold stepOddWith
  rw [shift_unshift_grid hw hh]
  rw [stepEvenWith_compose_id r1 r2 hinv]
  exact unshift_shift_grid hw hh g

def stepFwd {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (t : Nat) (g : Grid wx hy) : Grid wx hy :=
  if t % 2 = 0 then stepEvenWith fwdBlock g else stepOddWith hw hh fwdBlock g

def stepRev {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (t : Nat) (g : Grid wx hy) : Grid wx hy :=
  if t % 2 = 0 then stepEvenWith invBlock g else stepOddWith hw hh invBlock g

theorem stepRev_stepFwd {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (t : Nat) (g : Grid wx hy) :
    stepRev hw hh t (stepFwd hw hh t g) = g := by
  unfold stepRev stepFwd
  by_cases hp : t % 2 = 0
  · simp only [hp, ↓reduceIte]
    exact stepEvenWith_compose_id fwdBlock invBlock invBlock_fwdBlock g
  · simp only [hp, ↓reduceIte]
    exact stepOddWith_compose_id hw hh fwdBlock invBlock invBlock_fwdBlock g

theorem stepFwd_stepRev {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (t : Nat) (g : Grid wx hy) :
    stepFwd hw hh t (stepRev hw hh t g) = g := by
  unfold stepFwd stepRev
  by_cases hp : t % 2 = 0
  · simp only [hp, ↓reduceIte]
    exact stepEvenWith_compose_id invBlock fwdBlock fwdBlock_invBlock g
  · simp only [hp, ↓reduceIte]
    exact stepOddWith_compose_id hw hh invBlock fwdBlock fwdBlock_invBlock g

def evolveFrom {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (start : Nat) : Nat → Grid wx hy → Grid wx hy
  | 0, g => g
  | n + 1, g => evolveFrom hw hh (start + 1) n (stepFwd hw hh start g)

def reverseFrom {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (stop : Nat) : Nat → Grid wx hy → Grid wx hy
  | 0, g => g
  | n + 1, g => reverseFrom hw hh (stop - 1) n (stepRev hw hh (stop - 1) g)

private theorem evolveFrom_step_last {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (start n : Nat) (g : Grid wx hy) :
    evolveFrom hw hh start (n + 1) g =
      stepFwd hw hh (start + n) (evolveFrom hw hh start n g) := by
  induction n generalizing start g with
  | zero => simp [evolveFrom]
  | succ k ih =>
    unfold evolveFrom
    have ih' := ih (start + 1) (stepFwd hw hh start g)
    have hidx : start + 1 + k = start + (k + 1) := by omega
    rw [hidx] at ih'
    exact ih'

private theorem reverseFrom_step_add {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (stop n : Nat) (g : Grid wx hy) :
    reverseFrom hw hh (stop + 1) (n + 1) g =
      reverseFrom hw hh stop n (stepRev hw hh stop g) := by
  conv => lhs; unfold reverseFrom
  have hsub : stop + 1 - 1 = stop := by omega
  rw [hsub]

theorem reverseFrom_evolveFrom {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (start steps : Nat) (g : Grid wx hy) :
    reverseFrom hw hh (start + steps) steps (evolveFrom hw hh start steps g) = g := by
  induction steps generalizing start g with
  | zero => rfl
  | succ k ih =>
    rw [evolveFrom_step_last hw hh start k g]
    have hsum : start + (k + 1) = (start + k) + 1 := by omega
    rw [hsum, reverseFrom_step_add hw hh (start + k) k]
    rw [stepRev_stepFwd hw hh (start + k)]
    exact ih start g

-- =========================================================================
-- Section 4: Strict Per-Step Total Particle Conservation (`gridPop`)
-- =========================================================================

def sumIdx : Nat → (Nat → Nat) → Nat
  | 0, _ => 0
  | n + 1, f => sumIdx n f + f n

theorem sumIdx_congr (n : Nat) (f h : Nat → Nat) (heq : ∀ i, i < n → f i = h i) :
    sumIdx n f = sumIdx n h := by
  induction n with
  | zero => rfl
  | succ k ih =>
    unfold sumIdx
    rw [ih (fun i hi => heq i (by omega)), heq k (by omega)]

theorem sumIdx_pair (n : Nat) (f : Nat → Nat) :
    sumIdx (2 * n) f = sumIdx n (fun i => f (2 * i) + f (2 * i + 1)) := by
  induction n with
  | zero => rfl
  | succ k ih =>
    have h2 : 2 * (k + 1) = (2 * k + 1) + 1 := by omega
    rw [h2]
    conv => lhs; unfold sumIdx; unfold sumIdx
    conv => rhs; unfold sumIdx
    dsimp only
    rw [ih]
    omega

private theorem sumIdx_split (k n : Nat) (f : Nat → Nat) (hk : k ≤ n) :
    sumIdx n f = sumIdx k f + sumIdx (n - k) (fun i => f (k + i)) := by
  induction hdiff : n - k generalizing n with
  | zero =>
    have hkn : n = k := by omega
    subst hkn
    simp [sumIdx]
  | succ d ih =>
    cases n with
    | zero => omega
    | succ m =>
      have hm : k ≤ m := by omega
      have hmd : m - k = d := by omega
      conv => lhs; unfold sumIdx
      conv => rhs; arg 2; unfold sumIdx
      rw [ih m hm hmd]
      have hidx : k + d = m := by omega
      dsimp only
      rw [hidx]
      omega

theorem sumIdx_shift (m : Nat) (hm : 0 < m) (f : Nat → Nat) :
    sumIdx m (fun i => f ((i + 1) % m)) = sumIdx m f := by
  cases m with
  | zero => omega
  | succ k =>
    have h1 : sumIdx (k + 1) f = f 0 + sumIdx k (fun i => f (1 + i)) := by
      have hs := sumIdx_split 1 (k + 1) f (by omega)
      simp only [sumIdx, Nat.zero_add, Nat.add_sub_cancel] at hs
      exact hs
    rw [h1]
    have h2 : sumIdx (k + 1) (fun i => f ((i + 1) % (k + 1))) =
        sumIdx k (fun i => f ((i + 1) % (k + 1))) + f ((k + 1) % (k + 1)) := rfl
    rw [h2, Nat.mod_self]
    have h3 : sumIdx k (fun i => f ((i + 1) % (k + 1))) = sumIdx k (fun i => f (1 + i)) := by
      apply sumIdx_congr
      intro i hi
      have hmod : (i + 1) % (k + 1) = 1 + i := by
        rw [Nat.mod_eq_of_lt (by omega)]
        omega
      rw [hmod]
    rw [h3]
    omega

def gridPop {wx hy : Nat} (g : Grid wx hy) : Nat :=
  sumIdx (2 * wx) (fun x =>
    sumIdx (2 * hy) (fun y =>
      if h : x < 2 * wx ∧ y < 2 * hy then
        boolBit (g ⟨x, h.1⟩ ⟨y, h.2⟩)
      else 0))

private theorem gridPop_eq_blocks {wx hy : Nat} (g : Grid wx hy) :
    gridPop g = sumIdx wx (fun bx =>
      sumIdx hy (fun by_ =>
        if h : bx < wx ∧ by_ < hy then
          pop4 (readBlock g ⟨bx, h.1⟩ ⟨by_, h.2⟩)
        else 0)) := by
  unfold gridPop
  rw [sumIdx_pair wx]
  apply sumIdx_congr
  intro bx hbx
  rw [sumIdx_pair hy, sumIdx_pair hy]
  have hind : ∀ k, k ≤ hy →
      sumIdx k (fun by_ =>
        (if h : 2 * bx < 2 * wx ∧ 2 * by_ < 2 * hy then boolBit (g ⟨2 * bx, h.1⟩ ⟨2 * by_, h.2⟩) else 0) +
        (if h : 2 * bx < 2 * wx ∧ 2 * by_ + 1 < 2 * hy then boolBit (g ⟨2 * bx, h.1⟩ ⟨2 * by_ + 1, h.2⟩) else 0)) +
      sumIdx k (fun by_ =>
        (if h : 2 * bx + 1 < 2 * wx ∧ 2 * by_ < 2 * hy then boolBit (g ⟨2 * bx + 1, h.1⟩ ⟨2 * by_, h.2⟩) else 0) +
        (if h : 2 * bx + 1 < 2 * wx ∧ 2 * by_ + 1 < 2 * hy then boolBit (g ⟨2 * bx + 1, h.1⟩ ⟨2 * by_ + 1, h.2⟩) else 0)) =
      sumIdx k (fun by_ =>
        if h : bx < wx ∧ by_ < hy then
          pop4 (readBlock g ⟨bx, h.1⟩ ⟨by_, h.2⟩)
        else 0) := by
    intro k hk
    induction k with
    | zero => rfl
    | succ m ihm =>
      conv => lhs; arg 1; unfold sumIdx
      conv => lhs; arg 2; unfold sumIdx
      conv => rhs; unfold sumIdx
      have hsub := ihm (by omega)
      have hm1 : bx < wx ∧ m < hy := ⟨hbx, by omega⟩
      have h00 : 2 * bx < 2 * wx ∧ 2 * m < 2 * hy := ⟨by omega, by omega⟩
      have h01 : 2 * bx < 2 * wx ∧ 2 * m + 1 < 2 * hy := ⟨by omega, by omega⟩
      have h10 : 2 * bx + 1 < 2 * wx ∧ 2 * m < 2 * hy := ⟨by omega, by omega⟩
      have h11 : 2 * bx + 1 < 2 * wx ∧ 2 * m + 1 < 2 * hy := ⟨by omega, by omega⟩
      dsimp only
      rw [dite_eq_left_of_eq_true (eq_true hm1), dite_eq_left_of_eq_true (eq_true h00),
          dite_eq_left_of_eq_true (eq_true h01), dite_eq_left_of_eq_true (eq_true h10),
          dite_eq_left_of_eq_true (eq_true h11)]
      have hpop : pop4 (readBlock g ⟨bx, hbx⟩ ⟨m, by omega⟩) =
          boolBit (g ⟨2 * bx, by omega⟩ ⟨2 * m, by omega⟩) +
          boolBit (g ⟨2 * bx + 1, by omega⟩ ⟨2 * m, by omega⟩) +
          boolBit (g ⟨2 * bx, by omega⟩ ⟨2 * m + 1, by omega⟩) +
          boolBit (g ⟨2 * bx + 1, by omega⟩ ⟨2 * m + 1, by omega⟩) := by
        unfold pop4 readBlock
        have hbt := bitAt_pack4
          (g ⟨2 * bx, by omega⟩ ⟨2 * m, by omega⟩)
          (g ⟨2 * bx + 1, by omega⟩ ⟨2 * m, by omega⟩)
          (g ⟨2 * bx, by omega⟩ ⟨2 * m + 1, by omega⟩)
          (g ⟨2 * bx + 1, by omega⟩ ⟨2 * m + 1, by omega⟩)
        dsimp only
        rw [hbt.1, hbt.2.1, hbt.2.2.1, hbt.2.2.2]
      rw [hpop]
      omega
  exact hind hy (Nat.le_refl hy)

theorem stepEvenWith_conserves_pop {wx hy : Nat}
    (rule : Fin 16 → Fin 16) (hcons : ∀ b : Fin 16, pop4 (rule b) = pop4 b)
    (g : Grid wx hy) :
    gridPop (stepEvenWith rule g) = gridPop g := by
  rw [gridPop_eq_blocks (stepEvenWith rule g), gridPop_eq_blocks g]
  apply sumIdx_congr
  intro bx hbx
  apply sumIdx_congr
  intro by_ hby
  have hcond : bx < wx ∧ by_ < hy := ⟨hbx, hby⟩
  rw [dite_eq_left_of_eq_true (eq_true hcond), dite_eq_left_of_eq_true (eq_true hcond)]
  rw [readBlock_stepEvenWith rule g ⟨bx, hbx⟩ ⟨by_, hby⟩]
  exact hcons _

theorem shiftGrid_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) :
    gridPop (shiftGrid hw hh g) = gridPop g := by
  unfold gridPop shiftGrid
  have hx : ∀ x, x < 2 * wx →
      sumIdx (2 * hy) (fun y =>
        if h : x < 2 * wx ∧ y < 2 * hy then
          boolBit (g (shiftIdx (2 * wx) (by omega) ⟨x, h.1⟩) (shiftIdx (2 * hy) (by omega) ⟨y, h.2⟩))
        else 0) =
      sumIdx (2 * hy) (fun y =>
        if h : (x + 1) % (2 * wx) < 2 * wx ∧ y < 2 * hy then
          boolBit (g ⟨(x + 1) % (2 * wx), h.1⟩ ⟨y, h.2⟩)
        else 0) := by
    intro x hx
    have hshift := sumIdx_shift (2 * hy) (by omega) (fun y =>
      if hy_lt : y < 2 * hy then
        boolBit (g ⟨(x + 1) % (2 * wx), Nat.mod_lt _ (by omega)⟩ ⟨y, hy_lt⟩)
      else 0)
    have hlhs : sumIdx (2 * hy) (fun y =>
        if h : x < 2 * wx ∧ y < 2 * hy then
          boolBit (g (shiftIdx (2 * wx) (by omega) ⟨x, h.1⟩) (shiftIdx (2 * hy) (by omega) ⟨y, h.2⟩))
        else 0) =
      sumIdx (2 * hy) (fun y =>
        if hy_lt : (y + 1) % (2 * hy) < 2 * hy then
          boolBit (g ⟨(x + 1) % (2 * wx), Nat.mod_lt _ (by omega)⟩ ⟨(y + 1) % (2 * hy), hy_lt⟩)
        else 0) := by
      apply sumIdx_congr
      intro y hy_lt
      have hcond : x < 2 * wx ∧ y < 2 * hy := ⟨hx, hy_lt⟩
      have hmod : (y + 1) % (2 * hy) < 2 * hy := Nat.mod_lt _ (by omega)
      rw [dite_eq_left_of_eq_true (eq_true hcond), dite_eq_left_of_eq_true (eq_true hmod)]
      rfl
    have hrhs : sumIdx (2 * hy) (fun y =>
        if hy_lt : y < 2 * hy then
          boolBit (g ⟨(x + 1) % (2 * wx), Nat.mod_lt _ (by omega)⟩ ⟨y, hy_lt⟩)
        else 0) =
      sumIdx (2 * hy) (fun y =>
        if h : (x + 1) % (2 * wx) < 2 * wx ∧ y < 2 * hy then
          boolBit (g ⟨(x + 1) % (2 * wx), h.1⟩ ⟨y, h.2⟩)
        else 0) := by
      apply sumIdx_congr
      intro y hy_lt
      have hcond2 : (x + 1) % (2 * wx) < 2 * wx ∧ y < 2 * hy := ⟨Nat.mod_lt _ (by omega), hy_lt⟩
      rw [dite_eq_left_of_eq_true (eq_true hy_lt), dite_eq_left_of_eq_true (eq_true hcond2)]
    rw [hlhs, hshift, hrhs]
  rw [sumIdx_congr (2 * wx) _ _ hx]
  exact sumIdx_shift (2 * wx) (by omega) (fun x =>
    sumIdx (2 * hy) (fun y =>
      if h : x < 2 * wx ∧ y < 2 * hy then
        boolBit (g ⟨x, h.1⟩ ⟨y, h.2⟩)
      else 0))

theorem unshiftGrid_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy) (g : Grid wx hy) :
    gridPop (unshiftGrid hw hh g) = gridPop g := by
  have heq : g = shiftGrid hw hh (unshiftGrid hw hh g) := (shift_unshift_grid hw hh g).symm
  conv => rhs; rw [heq]
  exact (shiftGrid_conserves_pop hw hh (unshiftGrid hw hh g)).symm

theorem stepOddWith_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (rule : Fin 16 → Fin 16) (hcons : ∀ b : Fin 16, pop4 (rule b) = pop4 b)
    (g : Grid wx hy) :
    gridPop (stepOddWith hw hh rule g) = gridPop g := by
  unfold stepOddWith
  rw [unshiftGrid_conserves_pop hw hh]
  rw [stepEvenWith_conserves_pop rule hcons]
  exact shiftGrid_conserves_pop hw hh g

theorem stepFwd_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (t : Nat) (g : Grid wx hy) :
    gridPop (stepFwd hw hh t g) = gridPop g := by
  unfold stepFwd
  by_cases hp : t % 2 = 0
  · simp only [hp, ↓reduceIte]
    exact stepEvenWith_conserves_pop fwdBlock fwdBlock_conserves_pop g
  · simp only [hp, ↓reduceIte]
    exact stepOddWith_conserves_pop hw hh fwdBlock fwdBlock_conserves_pop g

theorem stepRev_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (t : Nat) (g : Grid wx hy) :
    gridPop (stepRev hw hh t g) = gridPop g := by
  unfold stepRev
  by_cases hp : t % 2 = 0
  · simp only [hp, ↓reduceIte]
    exact stepEvenWith_conserves_pop invBlock invBlock_conserves_pop g
  · simp only [hp, ↓reduceIte]
    exact stepOddWith_conserves_pop hw hh invBlock invBlock_conserves_pop g

theorem evolveFrom_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (start steps : Nat) (g : Grid wx hy) :
    gridPop (evolveFrom hw hh start steps g) = gridPop g := by
  induction steps generalizing start g with
  | zero => rfl
  | succ k ih =>
    unfold evolveFrom
    rw [ih (start + 1) (stepFwd hw hh start g)]
    exact stepFwd_conserves_pop hw hh start g

theorem reverseFrom_conserves_pop {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (stop steps : Nat) (g : Grid wx hy) :
    gridPop (reverseFrom hw hh stop steps g) = gridPop g := by
  induction steps generalizing stop g with
  | zero => rfl
  | succ k ih =>
    unfold reverseFrom
    rw [ih (stop - 1) (stepRev hw hh (stop - 1) g)]
    exact stepRev_conserves_pop hw hh (stop - 1) g

-- =========================================================================
-- Section 5: Parallel Strip Halo Causal Light-Cone Soundness
-- =========================================================================

/-- Two grids agree on all rows `y` in `[lo, hi)` (where `lo ≤ hi ≤ 2 * hy`). -/
def RowsAgree {wx hy : Nat} (lo hi : Nat) (g1 g2 : Grid wx hy) : Prop :=
  ∀ (x : Fin (2 * wx)) (y : Fin (2 * hy)), lo ≤ y.val → y.val < hi → g1 x y = g2 x y

private theorem readBlock_congr {wx hy : Nat} (g1 g2 : Grid wx hy) (bx : Fin wx) (by_ : Fin hy)
    (h : ∀ (x : Fin (2 * wx)) (y : Fin (2 * hy)),
      y.val = 2 * by_.val ∨ y.val = 2 * by_.val + 1 → g1 x y = g2 x y) :
    readBlock g1 bx by_ = readBlock g2 bx by_ := by
  apply Fin.ext
  unfold readBlock
  dsimp only
  have h00 := h ⟨2 * bx.val, by omega⟩ ⟨2 * by_.val, by omega⟩ (Or.inl rfl)
  have h10 := h ⟨2 * bx.val + 1, by omega⟩ ⟨2 * by_.val, by omega⟩ (Or.inl rfl)
  have h01 := h ⟨2 * bx.val, by omega⟩ ⟨2 * by_.val + 1, by omega⟩ (Or.inr rfl)
  have h11 := h ⟨2 * bx.val + 1, by omega⟩ ⟨2 * by_.val + 1, by omega⟩ (Or.inr rfl)
  rw [h00, h10, h01, h11]

theorem stepEven_preserves_even_strip {wx hy : Nat}
    (rule : Fin 16 → Fin 16) (lo hi : Nat)
    (hlo : lo % 2 = 0) (hhi : hi % 2 = 0)
    (g1 g2 : Grid wx hy) (hagree : RowsAgree lo hi g1 g2) :
    RowsAgree lo hi (stepEvenWith rule g1) (stepEvenWith rule g2) := by
  intro x y hyl hyu
  unfold stepEvenWith
  dsimp only
  have hblk := readBlock_congr g1 g2 ⟨x.val / 2, by omega⟩ ⟨y.val / 2, by omega⟩ (by
    intro xx yy hy_eq
    dsimp only at hy_eq
    rcases hy_eq with hy0 | hy1
    · exact hagree xx yy (by omega) (by omega)
    · exact hagree xx yy (by omega) (by omega))
  rw [hblk]

theorem stepFwd_light_cone {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (t lo hi : Nat) (hlo : lo + 1 ≤ hi) (hhi : hi ≤ 2 * hy)
    (g1 g2 : Grid wx hy) (hagree : RowsAgree lo hi g1 g2) :
    RowsAgree (lo + 1) (hi - 1) (stepFwd hw hh t g1) (stepFwd hw hh t g2) := by
  intro x y hyl hyu
  unfold stepFwd
  by_cases hp : t % 2 = 0
  · simp only [hp, ↓reduceIte]
    unfold stepEvenWith
    dsimp only
    have hblk := readBlock_congr g1 g2 ⟨x.val / 2, by omega⟩ ⟨y.val / 2, by omega⟩ (by
      intro xx yy hy_eq
      dsimp only at hy_eq
      rcases hy_eq with hy0 | hy1
      · exact hagree xx yy (by omega) (by omega)
      · exact hagree xx yy (by omega) (by omega))
    rw [hblk]
  · simp only [hp, ↓reduceIte]
    unfold stepOddWith unshiftGrid stepEvenWith shiftGrid
    dsimp only
    have hy_pos : y.val ≥ 1 := by omega
    have hy_lt : y.val < 2 * hy - 1 := by omega
    have hus : (unshiftIdx (2 * hy) (by omega) y).val = y.val - 1 := by
      unfold unshiftIdx
      dsimp only
      have heq : y.val + (2 * hy - 1) = (y.val - 1) + 2 * hy := by omega
      rw [heq, Nat.add_mod_right, Nat.mod_eq_of_lt (by omega)]
    have hblk := readBlock_congr
      (fun x y => g1 (shiftIdx (2 * wx) (by omega) x) (shiftIdx (2 * hy) (by omega) y))
      (fun x y => g2 (shiftIdx (2 * wx) (by omega) x) (shiftIdx (2 * hy) (by omega) y))
      ⟨(unshiftIdx (2 * wx) (by omega) x).val / 2, by omega⟩
      ⟨(unshiftIdx (2 * hy) (by omega) y).val / 2, by omega⟩
      (by
        intro xx yy hy_eq
        dsimp only [shiftIdx] at hy_eq ⊢
        rcases hy_eq with hy0 | hy1
        · have hyval : yy.val = 2 * ((y.val - 1) / 2) := by rw [hy0, hus]
          have hmod : (yy.val + 1) % (2 * hy) = yy.val + 1 := Nat.mod_eq_of_lt (by omega)
          have hlo' : lo ≤ (⟨(yy.val + 1) % (2 * hy), Nat.mod_lt _ (by omega)⟩ : Fin (2 * hy)).val := by
            dsimp only; rw [hmod, hyval]; omega
          have hhi' : (⟨(yy.val + 1) % (2 * hy), Nat.mod_lt _ (by omega)⟩ : Fin (2 * hy)).val < hi := by
            dsimp only; rw [hmod, hyval]; omega
          exact hagree _ _ hlo' hhi'
        · have hyval : yy.val = 2 * ((y.val - 1) / 2) + 1 := by rw [hy1, hus]
          have hmod : (yy.val + 1) % (2 * hy) = yy.val + 1 := Nat.mod_eq_of_lt (by omega)
          have hlo' : lo ≤ (⟨(yy.val + 1) % (2 * hy), Nat.mod_lt _ (by omega)⟩ : Fin (2 * hy)).val := by
            dsimp only; rw [hmod, hyval]; omega
          have hhi' : (⟨(yy.val + 1) % (2 * hy), Nat.mod_lt _ (by omega)⟩ : Fin (2 * hy)).val < hi := by
            dsimp only; rw [hmod, hyval]; omega
          exact hagree _ _ hlo' hhi')
    rw [hblk]

/-- Multi-step halo-strip soundness: `steps` generations of parallel execution on a strip
    with `steps` top and `steps` bottom halo rows (`[lo - steps, hi + steps)`) produces
    the EXACT same bits on `[lo, hi)` as evolving the full global torus. -/
theorem evolveFrom_halo_sound {wx hy : Nat} (hw : 0 < wx) (hh : 0 < hy)
    (start steps lo hi : Nat) (hlo_ge : steps ≤ lo) (hhi_le : hi + steps ≤ 2 * hy)
    (hnonempty : lo ≤ hi)
    (g1 g2 : Grid wx hy) (hagree : RowsAgree (lo - steps) (hi + steps) g1 g2) :
    RowsAgree lo hi (evolveFrom hw hh start steps g1) (evolveFrom hw hh start steps g2) := by
  induction steps generalizing start lo hi g1 g2 with
  | zero =>
    simp only [Nat.sub_zero, Nat.add_zero] at hagree
    exact hagree
  | succ k ih =>
    unfold evolveFrom
    have hstep : RowsAgree (lo - (k + 1) + 1) (hi + (k + 1) - 1)
        (stepFwd hw hh start g1) (stepFwd hw hh start g2) :=
      stepFwd_light_cone hw hh start (lo - (k + 1)) (hi + (k + 1))
        (by omega) (by omega) g1 g2 hagree
    have h1 : lo - (k + 1) + 1 = lo - k := by omega
    have h2 : hi + (k + 1) - 1 = hi + k := by omega
    rw [h1, h2] at hstep
    exact ih (start + 1) lo hi (by omega) (by omega) hnonempty _ _ hstep

-- =========================================================================
-- Section 6: OMCA01 Container Invariants & Concrete `decide` Controls
-- =========================================================================

def validDims (w h : Nat) : Bool :=
  (w ≥ 2) && (h ≥ 2) && (w % 2 == 0) && (h % 2 == 0)

structure OmcaHeader where
  magicTag  : Nat
  version   : Nat
  ruleId    : Nat
  width     : Nat
  height    : Nat
  step      : Nat
  popcount  : Nat
  actualPop : Nat
  shaOk     : Bool
  fileBytes : Nat
  deriving DecidableEq, Repr

def OMCA01_MAGIC_TAG : Nat := 0x4F4D43413031
def RULE_BBM         : Nat := 1

def validateContainer (hdr : OmcaHeader) : Bool :=
  let rowBytes := (hdr.width + 7) / 8
  let expectedPayload := hdr.height * rowBytes
  (hdr.magicTag == OMCA01_MAGIC_TAG) &&
  (hdr.version == 1) &&
  (hdr.ruleId == RULE_BBM) &&
  validDims hdr.width hdr.height &&
  (hdr.popcount == hdr.actualPop) &&
  hdr.shaOk &&
  (hdr.fileBytes == 72 + expectedPayload)

-- Concrete 6×6 toroidal grid (`List Bool` of length 36) for fast kernel `decide`
abbrev Grid6 := List Bool

def g6Idx (x y : Nat) : Nat :=
  (y % 6) * 6 + (x % 6)

def g6Get (g : Grid6) (x y : Nat) : Bool :=
  match g.drop (g6Idx x y) with
  | b :: _ => b
  | [] => false

def g6Pop : Grid6 → Nat
  | [] => 0
  | b :: bs => (if b then 1 else 0) + g6Pop bs

def g6Block (g : Grid6) (x0 y0 : Nat) : Fin 16 :=
  let a := boolBit (g6Get g x0 y0)
  let b := boolBit (g6Get g (x0 + 1) y0)
  let c := boolBit (g6Get g x0 (y0 + 1))
  let d := boolBit (g6Get g (x0 + 1) (y0 + 1))
  ⟨(a + 2 * b + 4 * c + 8 * d) % 16, Nat.mod_lt _ (by decide)⟩

def g6StepWith (rule : Fin 16 → Fin 16) (phase : Nat) (g : Grid6) : Grid6 :=
  let off := phase % 2
  (List.range 36).map fun idx =>
    let x := idx % 6
    let y := idx / 6
    let sx := (x + 6 - off) % 6
    let sy := (y + 6 - off) % 6
    let bx := ((sx / 2) * 2 + off) % 6
    let by_ := ((sy / 2) * 2 + off) % 6
    let blk := rule (g6Block g bx by_)
    let k := 2 * (sy % 2) + (sx % 2)
    bitAt blk.val k == 1

def g6Evolve (rule : Fin 16 → Fin 16) (start : Nat) : Nat → Grid6 → Grid6
  | 0, g => g
  | n + 1, g => g6Evolve rule (start + 1) n (g6StepWith rule start g)

def g6Reverse (rule : Fin 16 → Fin 16) (stop : Nat) : Nat → Grid6 → Grid6
  | 0, g => g
  | n + 1, g => g6Reverse rule (stop - 1) n (g6StepWith rule (stop - 1) g)

/-- Asymmetric colliding 6×6 initial lattice:
    - SE glider at (0,0), NW glider at (3,3) -> head-on collision in odd block [1..2,1..2]!
    - Stationary 2-cell reflector at (4,1)-(5,1) and NE glider at (0,4). -/
def collider6x6 : Grid6 :=
  (List.range 36).map fun idx =>
    let x := idx % 6
    let y := idx / 6
    (x == 0 && y == 0) ||
    (x == 3 && y == 3) ||
    (x == 4 && y == 1) || (x == 5 && y == 1) ||
    (x == 0 && y == 4)

/-- Negative control broken rule: annihilates head-on collision (9 -> 0) and is irreversible. -/
def brokenRule (x : Fin 16) : Fin 16 :=
  if x.val == 9 then ⟨0, by decide⟩ else fwdBlock x

/-- Positive control: 6×6 collider evolves non-trivially over T=6 steps, conserves
    exact particle count = 5 at step 1, 3, 6, and reverses back to exact T0 bits! -/
theorem pos_ctrl_6x6_collider_roundtrip :
    let s1 := g6Evolve fwdBlock 0 1 collider6x6
    let s3 := g6Evolve fwdBlock 0 3 collider6x6
    let s6 := g6Evolve fwdBlock 0 6 collider6x6
    let r6 := g6Reverse invBlock 6 6 s6
    (s6 ≠ collider6x6) ∧
    (g6Pop collider6x6 == 5) ∧
    (g6Pop s1 == 5) ∧
    (g6Pop s3 == 5) ∧
    (g6Pop s6 == 5) ∧
    (r6 == collider6x6) := by
  decide

/-- Negative control 1: Irreversible rule mutation (`9 -> 0`) breaks both reversibility
    and particle conservation (`pop 5 -> 3`). -/
theorem neg_ctrl_broken_rule_fails :
    let s6 := g6Evolve brokenRule 0 6 collider6x6
    let r6 := g6Reverse brokenRule 6 6 s6
    (pop4 (brokenRule ⟨9, by decide⟩) ≠ pop4 ⟨9, by decide⟩) ∧
    (g6Pop s6 ≠ g6Pop collider6x6) ∧
    (r6 ≠ collider6x6) := by
  decide

/-- Negative control 2: Odd lattice dimensions (`63x64` or `64x63`) fail `validDims`. -/
theorem neg_ctrl_odd_dims_refused :
    validDims 64 64 = true ∧
    validDims 63 64 = false ∧
    validDims 64 63 = false ∧
    validDims 0 64 = false := by
  decide

/-- Negative control 3..5: Tampered SHA-256, particle popcount delta, bad magic, and
    truncated `OMCA01` container are all refused fail-closed by `validateContainer`. -/
def validHdr : OmcaHeader :=
  { magicTag := OMCA01_MAGIC_TAG, version := 1, ruleId := RULE_BBM,
    width := 64, height := 64, step := 0, popcount := 42, actualPop := 42,
    shaOk := true, fileBytes := 72 + 64 * 8 }

theorem neg_ctrl_container_tampers_refused :
    validateContainer validHdr = true ∧
    validateContainer { validHdr with shaOk := false } = false ∧
    validateContainer { validHdr with popcount := 43 } = false ∧
    validateContainer { validHdr with magicTag := 0x424144434131 } = false ∧
    validateContainer { validHdr with fileBytes := 583 } = false ∧
    validateContainer { validHdr with width := 63 } = false := by
  decide

-- =========================================================================
-- Section 7: Axiom Audit (Standard Core Axioms Only, Zero sorry/native_decide)
-- =========================================================================

#print axioms fwdBlock_involutive
#print axioms invBlock_fwdBlock
#print axioms fwdBlock_invBlock
#print axioms fwdBlock_injective
#print axioms fwdBlock_surjective
#print axioms fwdBlock_conserves_pop
#print axioms invBlock_conserves_pop
#print axioms swarBlock_eq_fwdBlock
#print axioms mapInv_mapFwd
#print axioms mapFwd_mapInv
#print axioms mapFwd_conserves_pop
#print axioms mapInv_conserves_pop
#print axioms unshift_shift_grid
#print axioms shift_unshift_grid
#print axioms stepRev_stepFwd
#print axioms stepFwd_stepRev
#print axioms reverseFrom_evolveFrom
#print axioms stepEvenWith_conserves_pop
#print axioms stepOddWith_conserves_pop
#print axioms stepFwd_conserves_pop
#print axioms stepRev_conserves_pop
#print axioms evolveFrom_conserves_pop
#print axioms reverseFrom_conserves_pop
#print axioms stepEven_preserves_even_strip
#print axioms stepFwd_light_cone
#print axioms evolveFrom_halo_sound
#print axioms pos_ctrl_6x6_collider_roundtrip
#print axioms neg_ctrl_broken_rule_fails
#print axioms neg_ctrl_odd_dims_refused
#print axioms neg_ctrl_container_tampers_refused

end CaReversibleSoundness
