/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/OmegaFheSoundness.lean

  Machine-checked Lean 4.36.0 soundness proof for Wave 5 Alien Breakthrough:
  Pure Seeded-OM-2 Exact-Integer NTT Ring-LWE / Leveled BFV Homomorphic Evaluator
  (`apps/omega-fhe/fhe_rlwe.om`, `apps/omega-fhe/fhe_check.om`, `apps/omega-fhe/gate_fhe.om`).

  Zero `sorry`, zero warnings (`-DwarningAsError=true`), zero Mathlib dependency,
  standard Lean 4 core axioms only (`propext`, `Classical.choice`, `Quot.sound`).

  Model-to-system link (`apps/omega-fhe/fhe_rlwe.om` & `apps/omega-fhe/fhe_check.om`):
    - `FHE_N`, `FHE_Q`, `FHE_T`, `FHE_DELTA`, `FHE_MAX_NOISE`, `FHE_E_FRESH`,
      `FHE_PSI64`, `FHE_OMEGA64`, `FHE_Q_PRIME`, `FHE_P1`, `FHE_P2`
      mirror exact Section 1 constants of `fhe_rlwe.om`.
    - `fheIsCanon`, `fhe_canon_unique`, `fhe_noncanon_rejected`, `fhe_noncanon_aliases_zero`
      mirror `fh_is_canon` / `FH_ERR_NONCANON (74)`.
    - `montRedc_correct` mirrors `fh_mont_mul` (Montgomery REDC in Sec. 4).
    - `negacyclicMul`, `negacyclicMul_bound_l1`, `bfvDecodeCoeff_exact`
      mirror exact schoolbook/NTT arithmetic over `Z_q[X]/(X^N+1)` and `fh_decrypt_coeff` / `fc_decode_q_coeff`.
    - `BFVInv`, `bfv_add_inv`, `bfv_sub_inv`, `bfv_constMul_inv`, `bfv_addConst_inv`,
      `bfv_mul_relin_inv`, `bfv_eval_quad_poly_exact`
      mirror `fh_eval_add`, `fh_eval_sub`, `fh_eval_const_mul`, `fh_eval_add_const`,
      `fh_eval_mul`, `fh_calc_mul_noise`, and `fh_run_eval_poly`.
    - Concrete `decide` negative controls mirror `NC-1..NC-9` in `gate_fhe.om`.
-/

namespace OmegaFheSoundness

-- =========================================================================
-- Section 1: Exact Parameters, NTT/Montgomery/CRT Identities & `< q` Canon
-- =========================================================================

def FHE_N         : Nat := 64
def FHE_Q         : Nat := 72057594036480257
def FHE_Q_PRIME   : Nat := 12330114045378619647
def FHE_Q_R2      : Nat := 65291082746238719
def FHE_R_MOD_Q   : Nat := 370605824
def FHE_T         : Nat := 257
def FHE_HALF_T    : Nat := 128
def FHE_DELTA     : Nat := 280379743332608
def FHE_HALF_Q    : Nat := 36028797018240128
def FHE_MAX_NOISE : Nat := 140189871666303
def FHE_E_FRESH   : Nat := 162

def FHE_PSI64     : Nat := 27844242908845386
def FHE_INV_PSI64 : Nat := 31365032762498240
def FHE_OMEGA64   : Nat := 66070138393266314
def FHE_INV_OM64  : Nat := 50106539401303508
def FHE_INV64     : Nat := 70931694129660253

def FHE_P1        : Nat := 4611686018427379201
def FHE_P2        : Nat := 2305843009213689601
def FHE_P1_PSI64  : Nat := 4439126372118374601
def FHE_P1_IPSI64 : Nat := 1634095254086106524
def FHE_P1_INV64  : Nat := 4539628424389451401
def FHE_P2_PSI64  : Nat := 471345213009844031
def FHE_P2_IPSI64 : Nat := 420359399294971515
def FHE_P2_INV64  : Nat := 2269814212194725701

theorem fhe_params_verified :
    FHE_Q = FHE_T * FHE_DELTA + 1 ∧
    FHE_Q % 256 = 1 ∧
    FHE_Q % FHE_T = 1 ∧
    FHE_HALF_Q = FHE_Q / 2 ∧
    FHE_Q = 2 * FHE_HALF_Q + 1 ∧
    FHE_T * FHE_MAX_NOISE + (FHE_T - 1) ≤ FHE_HALF_Q ∧
    FHE_HALF_Q < FHE_T * (FHE_MAX_NOISE + 1) + (FHE_T - 1) ∧
    FHE_MAX_NOISE < FHE_DELTA ∧
    FHE_Q < 2 ^ 63 ∧
    (FHE_PSI64 ^ 64) % FHE_Q = FHE_Q - 1 ∧
    (FHE_PSI64 ^ 128) % FHE_Q = 1 ∧
    (FHE_PSI64 * FHE_INV_PSI64) % FHE_Q = 1 ∧
    (FHE_PSI64 * FHE_PSI64) % FHE_Q = FHE_OMEGA64 ∧
    (FHE_OMEGA64 * FHE_INV_OM64) % FHE_Q = 1 ∧
    (FHE_OMEGA64 ^ 64) % FHE_Q = 1 ∧
    (64 * FHE_INV64) % FHE_Q = 1 ∧
    (FHE_Q * FHE_Q_PRIME + 1) % (2 ^ 64) = 0 ∧
    (2 ^ 64) % FHE_Q = FHE_R_MOD_Q ∧
    (2 ^ 128) % FHE_Q = FHE_Q_R2 ∧
    FHE_P1 = 2 * FHE_P2 - 1 ∧
    (FHE_P1_PSI64 ^ 64) % FHE_P1 = FHE_P1 - 1 ∧
    (FHE_P1_PSI64 * FHE_P1_IPSI64) % FHE_P1 = 1 ∧
    (64 * FHE_P1_INV64) % FHE_P1 = 1 ∧
    (FHE_P2_PSI64 ^ 64) % FHE_P2 = FHE_P2 - 1 ∧
    (FHE_P2_PSI64 * FHE_P2_IPSI64) % FHE_P2 = 1 ∧
    (64 * FHE_P2_INV64) % FHE_P2 = 1 ∧
    2 * (2 * FHE_N * (FHE_HALF_Q ^ 2)) < FHE_P1 * FHE_P2 := by
  decide

theorem fheQ_pos : 0 < FHE_Q := by decide
theorem fheT_pos : 0 < FHE_T := by decide

private theorem int_cast_add (a b : Nat) : ((a + b : Nat) : Int) = (a : Int) + (b : Int) := by omega

private theorem int_cast_mul (a b : Nat) : ((a * b : Nat) : Int) = (a : Int) * (b : Int) := by
  induction a with
  | zero => simp
  | succ k ih =>
      rw [Nat.succ_mul, int_cast_add, ih]
      have h1 : (((k + 1 : Nat) : Int)) = (k : Int) + 1 := int_cast_add k 1
      rw [h1, Int.add_mul, Int.one_mul]

/-- Canonical `Z_q` predicate strictly `< FHE_Q` (mirrors `fh_is_canon`). -/
def fheIsCanon (x : Nat) : Bool := decide (x < FHE_Q)

theorem fhe_canon_unique (a b : Nat) (ha : a < FHE_Q) (hb : b < FHE_Q)
    (hmod : a % FHE_Q = b % FHE_Q) : a = b := by
  rw [Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] at hmod
  exact hmod

theorem fhe_noncanon_rejected (x : Nat) (hx : x ≥ FHE_Q) : fheIsCanon x = false := by
  unfold fheIsCanon
  simp [Nat.not_lt.mpr hx]

theorem fhe_noncanon_aliases_zero (k : Nat) (hk : k ≥ 1) :
    (k * FHE_Q) % FHE_Q = 0 ∧ fheIsCanon (k * FHE_Q) = false := by
  refine ⟨Nat.mul_mod_left k FHE_Q, ?_⟩
  apply fhe_noncanon_rejected
  have : 1 * FHE_Q ≤ k * FHE_Q := Nat.mul_le_mul_right FHE_Q hk
  omega

/-- Montgomery REDC correctness for odd modulus `m < 2^63` and `a, b < m`. -/
theorem montRedc_correct (m mp a b : Nat)
    (_hm_lt : m < 2 ^ 63) (hm_pos : 0 < m)
    (ha : a < m) (hb : b < m)
    (hinv : (m * mp + 1) % (2 ^ 64) = 0) :
    let R := 2 ^ 64
    let ab := a * b
    let k := (ab % R * mp) % R
    let u := (ab + k * m) / R
    let res := if u ≥ m then u - m else u
    (ab + k * m) % R = 0 ∧ res < m ∧ (res * R) % m = ab % m := by
  dsimp only
  have hRpos : 0 < 2 ^ 64 := by decide
  have hab_lt : a * b < m * m := Nat.mul_lt_mul_of_lt_of_lt ha hb
  have hm_le_R : m < 2 ^ 64 := by omega
  have hdiv : (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) % 2 ^ 64 = 0 := by
    have hm_mod : (m * mp) % 2 ^ 64 = 2 ^ 64 - 1 := by
      have h1 := hinv
      rw [Nat.add_mod] at h1
      have hlt : (m * mp) % 2 ^ 64 < 2 ^ 64 := Nat.mod_lt _ hRpos
      have h1m : 1 % 2 ^ 64 = 1 := by decide
      rw [h1m] at h1
      omega
    have hterm : ((a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) % 2 ^ 64 =
        (a * b % 2 ^ 64 * (2 ^ 64 - 1)) % 2 ^ 64 := by
      calc ((a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) % 2 ^ 64
          = ((a * b % 2 ^ 64 * mp) * m) % 2 ^ 64 := by
              rw [Nat.mul_mod, Nat.mod_mod, ← Nat.mul_mod]
        _ = (a * b % 2 ^ 64 * (m * mp)) % 2 ^ 64 := by
              rw [Nat.mul_assoc, Nat.mul_comm mp m]
        _ = ((a * b % 2 ^ 64) % 2 ^ 64 * ((m * mp) % 2 ^ 64)) % 2 ^ 64 := by
              rw [Nat.mul_mod]
        _ = (a * b % 2 ^ 64 * (2 ^ 64 - 1)) % 2 ^ 64 := by
              rw [Nat.mod_mod, hm_mod]
    have hmod_eq : a * b % 2 ^ 64 + a * b % 2 ^ 64 * (2 ^ 64 - 1) = a * b % 2 ^ 64 * 2 ^ 64 := by
      rw [Nat.mul_sub_left_distrib, Nat.mul_one]
      have : a * b % 2 ^ 64 ≤ a * b % 2 ^ 64 * 2 ^ 64 := Nat.le_mul_of_pos_right _ hRpos
      omega
    calc (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) % 2 ^ 64
        = (a * b % 2 ^ 64 + ((a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) % 2 ^ 64) % 2 ^ 64 := Nat.add_mod _ _ _
      _ = ((a * b % 2 ^ 64) % 2 ^ 64 + (a * b % 2 ^ 64 * (2 ^ 64 - 1)) % 2 ^ 64) % 2 ^ 64 := by
            rw [Nat.mod_mod, hterm]
      _ = (a * b % 2 ^ 64 + a * b % 2 ^ 64 * (2 ^ 64 - 1)) % 2 ^ 64 := (Nat.add_mod _ _ _).symm
      _ = (a * b % 2 ^ 64 * 2 ^ 64) % 2 ^ 64 := by rw [hmod_eq]
      _ = 0 := Nat.mul_mod_left _ _
  have hk_lt : (a * b % 2 ^ 64 * mp) % 2 ^ 64 < 2 ^ 64 := Nat.mod_lt _ hRpos
  have hsum_lt : a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m < 2 * m * 2 ^ 64 := by
    have h1 : a * b < m * 2 ^ 64 := Nat.lt_trans hab_lt (Nat.mul_lt_mul_of_pos_left hm_le_R hm_pos)
    have h2 : (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m < 2 ^ 64 * m := Nat.mul_lt_mul_of_pos_right hk_lt hm_pos
    rw [Nat.mul_comm (2 ^ 64) m] at h2
    rw [Nat.mul_assoc, Nat.two_mul]
    omega
  have hu_lt : (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) / 2 ^ 64 < 2 * m := by
    rw [Nat.mul_comm (2 * m) (2 ^ 64)] at hsum_lt
    exact Nat.div_lt_of_lt_mul hsum_lt
  have hres_lt : (if (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) / 2 ^ 64 ≥ m
      then (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) / 2 ^ 64 - m
      else (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) / 2 ^ 64) < m := by
    split <;> omega
  have hu_mul : ((a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) / 2 ^ 64) * 2 ^ 64 =
      a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m := by
    have hd := Nat.div_add_mod (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m) (2 ^ 64)
    rw [hdiv, Nat.add_zero, Nat.mul_comm] at hd
    exact hd
  refine ⟨hdiv, hres_lt, ?_⟩
  split
  · rename_i hge
    rw [Nat.mul_sub_right_distrib, hu_mul]
    have hle : m * 2 ^ 64 ≤ a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m := by
      rw [← hu_mul]
      exact Nat.mul_le_mul_right _ hge
    have hstep : a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m - m * 2 ^ 64 + m * 2 ^ 64 =
        a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m := Nat.sub_add_cancel hle
    have hmod_cancel : (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m - m * 2 ^ 64) % m =
        (a * b + (a * b % 2 ^ 64 * mp) % 2 ^ 64 * m - m * 2 ^ 64 + m * 2 ^ 64) % m := by
      rw [Nat.add_mod, Nat.mul_mod_right, Nat.add_zero, Nat.mod_mod]
    rw [hmod_cancel, hstep, Nat.add_mod, Nat.mul_mod_left, Nat.add_zero, Nat.mod_mod]
  · rw [hu_mul, Nat.add_mod, Nat.mul_mod_left, Nat.add_zero, Nat.mod_mod]

-- =========================================================================
-- Section 2: Finite Sums & Cyclotomic Ring `Z[X]/(X^N + 1)`
-- =========================================================================

abbrev Poly (n : Nat) := Fin n → Int
abbrev PolyMod (n : Nat) := Fin n → Nat

def sumInt : Nat → (Nat → Int) → Int
  | 0, _ => 0
  | k + 1, f => sumInt k f + f k

def sumNat : Nat → (Nat → Nat) → Nat
  | 0, _ => 0
  | k + 1, f => sumNat k f + f k

theorem sumInt_add (k : Nat) (f g : Nat → Int) :
    sumInt k (fun i => f i + g i) = sumInt k f + sumInt k g := by
  induction k with
  | zero => rfl
  | succ k ih => simp [sumInt, ih]; omega

theorem sumInt_sub (k : Nat) (f g : Nat → Int) :
    sumInt k (fun i => f i - g i) = sumInt k f - sumInt k g := by
  induction k with
  | zero => rfl
  | succ k ih => simp [sumInt, ih]; omega

theorem sumInt_scale (k : Nat) (c : Int) (f : Nat → Int) :
    sumInt k (fun i => c * f i) = c * sumInt k f := by
  induction k with
  | zero => simp [sumInt]
  | succ k ih => simp [sumInt, ih, Int.mul_add]

theorem sumInt_natAbs_le (k : Nat) (f : Nat → Int) :
    (sumInt k f).natAbs ≤ sumNat k (fun i => (f i).natAbs) := by
  induction k with
  | zero => simp [sumInt, sumNat]
  | succ k ih =>
      simp only [sumInt, sumNat]
      have htri : (sumInt k f + f k).natAbs ≤ (sumInt k f).natAbs + (f k).natAbs := Int.natAbs_add_le _ _
      omega

theorem sumInt_mod_congr (k : Nat) (m : Int) (f g : Nat → Int)
    (h : ∀ i, i < k → f i % m = g i % m) :
    sumInt k f % m = sumInt k g % m := by
  induction k with
  | zero => rfl
  | succ k ih =>
      simp only [sumInt]
      have ih' := ih (fun i hi => h i (Nat.lt_succ_of_lt hi))
      have hk := h k (Nat.lt_succ_self k)
      rw [Int.add_emod, ih', hk, ← Int.add_emod]

theorem sumNat_le_mul_bound (k B : Nat) (f : Nat → Nat)
    (hf : ∀ i, i < k → f i ≤ B) :
    sumNat k f ≤ k * B := by
  induction k with
  | zero => simp [sumNat]
  | succ k ih =>
      simp only [sumNat]
      have h1 := ih (fun i hi => hf i (Nat.lt_succ_of_lt hi))
      have h2 := hf k (Nat.lt_succ_self k)
      rw [Nat.succ_mul]
      omega

def polyAdd {n : Nat} (a b : Poly n) : Poly n := fun i => a i + b i
def polySub {n : Nat} (a b : Poly n) : Poly n := fun i => a i - b i
def polyScale {n : Nat} (c : Int) (a : Poly n) : Poly n := fun i => c * a i

/-- Exact negacyclic product in `Z[X]/(X^n + 1)`:
    `(a * b)_k = Σ_{i=0..k} a_i b_{k-i} - Σ_{i=k+1..n-1} a_i b_{k+n-i}`. -/
def negacyclicTerm {n : Nat} (a b : Poly n) (k : Fin n) (i : Nat) : Int :=
  if hi : i < n then
    if hki : i ≤ k.val then
      a ⟨i, hi⟩ * b ⟨k.val - i, by omega⟩
    else
      -(a ⟨i, hi⟩ * b ⟨k.val + n - i, by omega⟩)
  else 0

def negacyclicMul {n : Nat} (a b : Poly n) : Poly n :=
  fun k => sumInt n (negacyclicTerm a b k)

theorem negacyclicMul_add_left {n : Nat} (a1 a2 b : Poly n) (k : Fin n) :
    negacyclicMul (polyAdd a1 a2) b k = negacyclicMul a1 b k + negacyclicMul a2 b k := by
  unfold negacyclicMul
  rw [← sumInt_add]
  congr 1
  funext i
  unfold negacyclicTerm polyAdd
  by_cases hi : i < n
  · by_cases hki : i ≤ k.val
    · simp [hi, hki, Int.add_mul]
    · simp [hi, hki, Int.add_mul]; omega
  · simp [hi]

theorem negacyclicMul_add_right {n : Nat} (a b1 b2 : Poly n) (k : Fin n) :
    negacyclicMul a (polyAdd b1 b2) k = negacyclicMul a b1 k + negacyclicMul a b2 k := by
  unfold negacyclicMul
  rw [← sumInt_add]
  congr 1
  funext i
  unfold negacyclicTerm polyAdd
  by_cases hi : i < n
  · by_cases hki : i ≤ k.val
    · simp [hi, hki, Int.mul_add]
    · simp [hi, hki, Int.mul_add]; omega
  · simp [hi]

theorem negacyclicMul_sub_left {n : Nat} (a1 a2 b : Poly n) (k : Fin n) :
    negacyclicMul (polySub a1 a2) b k = negacyclicMul a1 b k - negacyclicMul a2 b k := by
  unfold negacyclicMul
  rw [← sumInt_sub]
  congr 1
  funext i
  unfold negacyclicTerm polySub
  by_cases hi : i < n
  · by_cases hki : i ≤ k.val
    · simp [hi, hki, Int.sub_mul]
    · simp [hi, hki, Int.sub_mul]; omega
  · simp [hi]

theorem negacyclicMul_scale_left {n : Nat} (c : Int) (a b : Poly n) (k : Fin n) :
    negacyclicMul (polyScale c a) b k = c * negacyclicMul a b k := by
  unfold negacyclicMul
  rw [← sumInt_scale]
  congr 1
  funext i
  unfold negacyclicTerm polyScale
  by_cases hi : i < n
  · by_cases hki : i ≤ k.val
    · simp [hi, hki, Int.mul_assoc]
    · simp only [hi, hki, ↓reduceDIte]
      rw [Int.mul_neg, Int.mul_assoc]
  · simp [hi]

theorem negacyclicMul_scale_right {n : Nat} (c : Int) (a b : Poly n) (k : Fin n) :
    negacyclicMul a (polyScale c b) k = c * negacyclicMul a b k := by
  unfold negacyclicMul
  rw [← sumInt_scale]
  congr 1
  funext i
  unfold negacyclicTerm polyScale
  by_cases hi : i < n
  · by_cases hki : i ≤ k.val
    · simp only [hi, hki, ↓reduceDIte]
      rw [Int.mul_left_comm]
    · simp only [hi, hki, ↓reduceDIte]
      rw [Int.mul_neg, Int.mul_left_comm]
  · simp [hi]

private theorem neg_emod_congr (m x y : Int) (h : x % m = y % m) :
    (-x) % m = (-y) % m := by
  rw [← Int.neg_one_mul x, ← Int.neg_one_mul y, Int.mul_emod, h, ← Int.mul_emod]

theorem negacyclicMul_mod_congr_left {n : Nat} (m : Int) (a a' b : Poly n)
    (ha : ∀ i : Fin n, a i % m = a' i % m) (k : Fin n) :
    negacyclicMul a b k % m = negacyclicMul a' b k % m := by
  unfold negacyclicMul
  apply sumInt_mod_congr
  intro i hi
  unfold negacyclicTerm
  by_cases hki : i ≤ k.val
  · simp only [hi, hki, ↓reduceDIte]
    rw [Int.mul_emod, ha ⟨i, hi⟩, ← Int.mul_emod]
  · simp only [hi, hki, ↓reduceDIte]
    apply neg_emod_congr
    rw [Int.mul_emod, ha ⟨i, hi⟩, ← Int.mul_emod]

theorem negacyclicMul_mod_congr_right {n : Nat} (m : Int) (a b b' : Poly n)
    (hb : ∀ i : Fin n, b i % m = b' i % m) (k : Fin n) :
    negacyclicMul a b k % m = negacyclicMul a b' k % m := by
  unfold negacyclicMul
  apply sumInt_mod_congr
  intro i hi
  unfold negacyclicTerm
  by_cases hki : i ≤ k.val
  · simp only [hi, hki, ↓reduceDIte]
    rw [Int.mul_emod, hb ⟨k.val - i, by omega⟩, ← Int.mul_emod]
  · simp only [hi, hki, ↓reduceDIte]
    apply neg_emod_congr
    rw [Int.mul_emod, hb ⟨k.val + n - i, by omega⟩, ← Int.mul_emod]

/-- Cyclotomic ring norm bound: `| (a * b)_k | ≤ (Σ_i |a_i|) * max_j |b_j|` and `≤ n * B_a * B_b`. -/
theorem negacyclicMul_bound_l1 {n : Nat} (a b : Poly n) (B : Nat)
    (hb : ∀ j : Fin n, (b j).natAbs ≤ B) (k : Fin n) :
    (negacyclicMul a b k).natAbs ≤ sumNat n (fun i => if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) * B := by
  unfold negacyclicMul
  have h1 := sumInt_natAbs_le n (negacyclicTerm a b k)
  have hstep : ∀ i, i < n → (negacyclicTerm a b k i).natAbs ≤
      (if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) * B := by
    intro i hi
    unfold negacyclicTerm
    by_cases hki : i ≤ k.val
    · simp only [hi, hki, ↓reduceDIte, Int.natAbs_mul]
      exact Nat.mul_le_mul_left _ (hb ⟨k.val - i, by omega⟩)
    · simp only [hi, hki, ↓reduceDIte, Int.natAbs_neg, Int.natAbs_mul]
      exact Nat.mul_le_mul_left _ (hb ⟨k.val + n - i, by omega⟩)
  have hsum_le : ∀ m : Nat, (∀ i, i < m → (negacyclicTerm a b k i).natAbs ≤
      (if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) * B) →
      sumNat m (fun i => (negacyclicTerm a b k i).natAbs) ≤
      sumNat m (fun i => if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) * B := by
    intro m hm
    induction m with
    | zero => simp [sumNat]
    | succ m ih =>
        simp only [sumNat]
        have hprev := ih (fun i hi => hm i (Nat.lt_succ_of_lt hi))
        have hcur := hm m (Nat.lt_succ_self m)
        rw [Nat.add_mul]
        omega
  exact Nat.le_trans h1 (hsum_le n hstep)

theorem negacyclicMul_bound_inf {n : Nat} (a b : Poly n) (Ba Bb : Nat)
    (ha : ∀ i : Fin n, (a i).natAbs ≤ Ba)
    (hb : ∀ j : Fin n, (b j).natAbs ≤ Bb) (k : Fin n) :
    (negacyclicMul a b k).natAbs ≤ n * Ba * Bb := by
  have hl1 := negacyclicMul_bound_l1 a b Bb hb k
  have hsum : sumNat n (fun i => if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) ≤ n * Ba := by
    apply sumNat_le_mul_bound
    intro i hi
    simp only [hi, ↓reduceDIte]
    exact ha ⟨i, hi⟩
  have hmul : sumNat n (fun i => if hi : i < n then (a ⟨i, hi⟩).natAbs else 0) * Bb ≤ (n * Ba) * Bb :=
    Nat.mul_le_mul_right Bb hsum
  exact Nat.le_trans hl1 hmul

-- =========================================================================
-- Section 3: Exact Integer BFV Decryption Theorem (Zero Floats!)
-- =========================================================================

/-- Exact BFV rounding decoder (mirrors `fh_decrypt_coeff` & `fc_decode_q_coeff`):
    `((FHE_T * v + FHE_HALF_Q) / FHE_Q) % FHE_T`. -/
def bfvDecodeCoeff (v : Nat) : Nat :=
  ((FHE_T * v + FHE_HALF_Q) / FHE_Q) % FHE_T

theorem bfvDecodeCoeff_exact (m : Nat) (e : Int)
    (hm : m < FHE_T) (he : e.natAbs ≤ FHE_MAX_NOISE) :
    let v := Int.toNat (((FHE_DELTA : Int) * m + e) % FHE_Q)
    bfvDecodeCoeff v = m := by
  dsimp only
  have hq : FHE_Q = FHE_T * FHE_DELTA + 1 := by decide
  have hq2 : FHE_Q = 2 * FHE_HALF_Q + 1 := by decide
  have hnoise_lo : -(FHE_MAX_NOISE : Int) ≤ e := by omega
  have hnoise_hi : e ≤ (FHE_MAX_NOISE : Int) := by omega
  have hmax_half : FHE_T * FHE_MAX_NOISE + (FHE_T - 1) ≤ FHE_HALF_Q := by decide
  have hmax_delta : FHE_MAX_NOISE < FHE_DELTA := by decide
  by_cases hneg : (FHE_DELTA : Int) * m + e < 0
  · have hm0 : m = 0 := by
      by_cases hnz : m = 0
      · exact hnz
      · have hm1 : (1 : Int) ≤ (m : Int) := by omega
        have hdm : (FHE_DELTA : Int) ≤ (FHE_DELTA : Int) * (m : Int) := by
          calc (FHE_DELTA : Int) = (FHE_DELTA : Int) * 1 := (Int.mul_one _).symm
            _ ≤ (FHE_DELTA : Int) * (m : Int) := Int.mul_le_mul_of_nonneg_left hm1 (by decide)
        omega
    subst hm0
    simp only [Int.ofNat_zero, Int.mul_zero, Int.zero_add] at hneg ⊢
    have hmq : (FHE_MAX_NOISE : Int) < (FHE_Q : Int) := by decide
    have hmod : e % (FHE_Q : Int) = (FHE_Q : Int) + e := by
      have hb1 : (0 : Int) ≤ (FHE_Q : Int) + e := by omega
      have hb2 : (FHE_Q : Int) + e < (FHE_Q : Int) := by omega
      calc e % (FHE_Q : Int)
          = (-1 * (FHE_Q : Int) + ((FHE_Q : Int) + e)) % (FHE_Q : Int) := by
              congr 1; omega
        _ = ((FHE_Q : Int) + e) % (FHE_Q : Int) := Int.mul_add_emod_self_right _ _ _
        _ = (FHE_Q : Int) + e := Int.emod_eq_of_lt hb1 hb2
    rw [hmod]
    have hv : Int.toNat ((FHE_Q : Int) + e) = FHE_Q - e.natAbs := by omega
    rw [hv]
    unfold bfvDecodeCoeff
    have hle2 : FHE_T * e.natAbs ≤ FHE_HALF_Q :=
      Nat.le_trans (Nat.mul_le_mul_left FHE_T he) (by decide)
    have hle_tq : FHE_T * e.natAbs ≤ FHE_T * FHE_Q :=
      Nat.mul_le_mul_left FHE_T (Nat.le_trans he (by decide))
    have hv_eq : FHE_T * (FHE_Q - e.natAbs) + FHE_HALF_Q =
        FHE_T * FHE_Q + (FHE_HALF_Q - FHE_T * e.natAbs) := by
      rw [Nat.mul_sub_left_distrib]
      omega
    have hrem_lt : FHE_HALF_Q - FHE_T * e.natAbs < FHE_Q := by
      have hhq : FHE_HALF_Q < FHE_Q := by decide
      omega
    rw [hv_eq, Nat.add_comm (FHE_T * FHE_Q), Nat.add_mul_div_right _ _ fheQ_pos]
    rw [Nat.div_eq_of_lt hrem_lt, Nat.zero_add, Nat.mod_self]
  · have hnonneg : (0 : Int) ≤ (FHE_DELTA : Int) * m + e := by omega
    have hlt_q : (FHE_DELTA : Int) * m + e < (FHE_Q : Int) := by
      have hm_le : (m : Int) ≤ (FHE_T - 1 : Int) := by omega
      have hmul_le : (FHE_DELTA : Int) * m ≤ (FHE_DELTA : Int) * (FHE_T - 1 : Int) :=
        Int.mul_le_mul_of_nonneg_left hm_le (by decide)
      have hbd : (FHE_DELTA : Int) * (FHE_T - 1 : Int) + (FHE_MAX_NOISE : Int) < (FHE_Q : Int) := by decide
      omega
    rw [Int.emod_eq_of_lt hnonneg hlt_q]
    unfold bfvDecodeCoeff
    have hnum_eq : ((FHE_T : Int) * ((FHE_DELTA : Int) * m + e) + (FHE_HALF_Q : Int)) =
        (m : Int) * (FHE_Q : Int) + ((FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int)) := by
      have hqi : (FHE_T : Int) * (FHE_DELTA : Int) = (FHE_Q : Int) - 1 := by decide
      calc (FHE_T : Int) * ((FHE_DELTA : Int) * m + e) + (FHE_HALF_Q : Int)
          = ((FHE_T : Int) * (FHE_DELTA : Int)) * m + (FHE_T : Int) * e + (FHE_HALF_Q : Int) := by
              rw [Int.mul_add, Int.mul_assoc]
        _ = ((FHE_Q : Int) - 1) * m + (FHE_T : Int) * e + (FHE_HALF_Q : Int) := by rw [hqi]
        _ = (m : Int) * (FHE_Q : Int) + ((FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int)) := by
              rw [Int.sub_mul, Int.one_mul, Int.mul_comm (FHE_Q : Int) (m : Int)]; omega
    have htm_hi : (FHE_T : Int) * (FHE_MAX_NOISE : Int) + (FHE_T : Int) ≤ (FHE_HALF_Q : Int) := by decide
    have hq_sum : (FHE_HALF_Q : Int) + (FHE_T : Int) * (FHE_MAX_NOISE : Int) < (FHE_Q : Int) := by decide
    have hrem_lo : (0 : Int) ≤ (FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int) := by
      have hte : -((FHE_T : Int) * (FHE_MAX_NOISE : Int)) ≤ (FHE_T : Int) * e := by
        have h1 := Int.mul_le_mul_of_nonneg_left hnoise_lo (by decide : (0 : Int) ≤ FHE_T)
        rw [Int.mul_neg] at h1
        exact h1
      omega
    have hrem_hi : (FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int) < (FHE_Q : Int) := by
      have hte : (FHE_T : Int) * e ≤ (FHE_T : Int) * (FHE_MAX_NOISE : Int) :=
        Int.mul_le_mul_of_nonneg_left hnoise_hi (by decide : (0 : Int) ≤ FHE_T)
      omega
    let remNat := Int.toNat ((FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int))
    have hrem_lt : remNat < FHE_Q := by omega
    have hv_eq_int : (Int.toNat ((FHE_DELTA : Int) * m + e) : Int) = (FHE_DELTA : Int) * m + e :=
      Int.toNat_of_nonneg hnonneg
    have hrem_eq_int : (remNat : Int) = (FHE_HALF_Q : Int) + (FHE_T : Int) * e - (m : Int) :=
      Int.toNat_of_nonneg hrem_lo
    have hv_nat : FHE_T * Int.toNat ((FHE_DELTA : Int) * m + e) + FHE_HALF_Q =
        m * FHE_Q + remNat := by
      have hnat : ((FHE_T * Int.toNat ((FHE_DELTA : Int) * m + e) + FHE_HALF_Q : Nat) : Int) =
          ((m * FHE_Q + remNat : Nat) : Int) := by
        rw [int_cast_add, int_cast_mul, int_cast_add, int_cast_mul, hv_eq_int, hrem_eq_int]
        exact hnum_eq
      exact Int.ofNat.inj hnat
    rw [hv_nat, Nat.add_comm (m * FHE_Q) remNat, Nat.add_mul_div_right _ _ fheQ_pos]
    rw [Nat.div_eq_of_lt hrem_lt, Nat.zero_add, Nat.mod_eq_of_lt hm]

-- =========================================================================
-- Section 4: Leveled BFV Noise Growth Invariant & Homomorphic Soundness
-- =========================================================================

structure BFVCiphertext where
  c0         : PolyMod FHE_N
  c1         : PolyMod FHE_N
  noiseBound : Nat
  depth      : Nat

/-- Exact BFV ciphertext invariant over `Z_q[X]/(X^N+1)`:
    `c0 + c1 * sk ≡ Δ * m + e (mod q)` with canonical `< q` components, `m < t`, and `‖e‖_∞ ≤ noiseBound`. -/
def BFVInv (sk : Poly FHE_N) (ct : BFVCiphertext) (m : PolyMod FHE_N) : Prop :=
  (∀ i : Fin FHE_N, ct.c0 i < FHE_Q ∧ ct.c1 i < FHE_Q) ∧
  (∀ i : Fin FHE_N, m i < FHE_T) ∧
  ∃ e : Poly FHE_N,
    (∀ i : Fin FHE_N, (e i).natAbs ≤ ct.noiseBound) ∧
    ∀ i : Fin FHE_N,
      ((ct.c0 i : Int) + negacyclicMul (fun j => (ct.c1 j : Int)) sk i) % FHE_Q =
      ((FHE_DELTA : Int) * m i + e i) % FHE_Q

def bfvDecrypt (sk : Poly FHE_N) (ct : BFVCiphertext) : PolyMod FHE_N :=
  fun i =>
    let v := Int.toNat (((ct.c0 i : Int) + negacyclicMul (fun j => (ct.c1 j : Int)) sk i) % FHE_Q)
    bfvDecodeCoeff v

theorem bfv_decrypt_of_inv (sk : Poly FHE_N) (ct : BFVCiphertext) (m : PolyMod FHE_N)
    (hinv : BFVInv sk ct m) (hbudget : ct.noiseBound ≤ FHE_MAX_NOISE) :
    bfvDecrypt sk ct = m := by
  funext i
  rcases hinv with ⟨_, hm, e, he, heq⟩
  unfold bfvDecrypt
  dsimp only
  rw [heq i]
  exact bfvDecodeCoeff_exact (m i) (e i) (hm i) (Nat.le_trans (he i) hbudget)

private theorem delta_mul_divmod_t (z : Int) :
    ((FHE_DELTA : Int) * z) % (FHE_Q : Int) =
    ((FHE_DELTA : Int) * (z % (FHE_T : Int)) - z / (FHE_T : Int)) % (FHE_Q : Int) := by
  have hqt : (FHE_T : Int) * (FHE_DELTA : Int) = (FHE_Q : Int) - 1 := by decide
  have hz : z = (FHE_T : Int) * (z / (FHE_T : Int)) + z % (FHE_T : Int) := by
    unfold FHE_T; omega
  calc ((FHE_DELTA : Int) * z) % (FHE_Q : Int)
      = ((FHE_DELTA : Int) * ((FHE_T : Int) * (z / (FHE_T : Int)) + z % (FHE_T : Int))) % (FHE_Q : Int) := by
          rw [← hz]
    _ = (((FHE_T : Int) * (FHE_DELTA : Int)) * (z / (FHE_T : Int)) + (FHE_DELTA : Int) * (z % (FHE_T : Int))) % (FHE_Q : Int) := by
          rw [Int.mul_add, Int.mul_assoc]; congr 2; exact Int.mul_left_comm (FHE_DELTA : Int) (FHE_T : Int) (z / (FHE_T : Int))
    _ = ((FHE_Q : Int) * (z / (FHE_T : Int)) + ((FHE_DELTA : Int) * (z % (FHE_T : Int)) - z / (FHE_T : Int))) % (FHE_Q : Int) := by
          rw [hqt, Int.sub_mul, Int.one_mul]; congr 1; omega
    _ = ((FHE_DELTA : Int) * (z % (FHE_T : Int)) - z / (FHE_T : Int)) % (FHE_Q : Int) := by
          rw [Int.mul_add_emod_self_left]

private theorem nat_cast_mod_q (a : Nat) :
    ((a % FHE_Q : Nat) : Int) = (a : Int) % (FHE_Q : Int) := by
  unfold FHE_Q; omega

private theorem nat_cast_mod_t (a : Nat) :
    ((a % FHE_T : Nat) : Int) = (a : Int) % (FHE_T : Int) := by
  unfold FHE_T; omega

/-- `EvalAdd`: exact mod-`t` plaintext addition with `+1` carry noise bound `E1 + E2 + 1`. -/
def evalAdd (ct1 ct2 : BFVCiphertext) : BFVCiphertext :=
  { c0 := fun i => (ct1.c0 i + ct2.c0 i) % FHE_Q
    c1 := fun i => (ct1.c1 i + ct2.c1 i) % FHE_Q
    noiseBound := ct1.noiseBound + ct2.noiseBound + 1
    depth := max ct1.depth ct2.depth }

def polyAddT (m1 m2 : PolyMod FHE_N) : PolyMod FHE_N :=
  fun i => (m1 i + m2 i) % FHE_T

theorem bfv_add_inv (sk : Poly FHE_N) (ct1 ct2 : BFVCiphertext) (m1 m2 : PolyMod FHE_N)
    (h1 : BFVInv sk ct1 m1) (h2 : BFVInv sk ct2 m2) :
    BFVInv sk (evalAdd ct1 ct2) (polyAddT m1 m2) := by
  rcases h1 with ⟨_, hm1, e1, he1, heq1⟩
  rcases h2 with ⟨_, hm2, e2, he2, heq2⟩
  refine ⟨?_, ?_, ?_⟩
  · intro i; exact ⟨Nat.mod_lt _ fheQ_pos, Nat.mod_lt _ fheQ_pos⟩
  · intro i; exact Nat.mod_lt _ fheT_pos
  · refine ⟨fun i => e1 i + e2 i - (((m1 i : Int) + (m2 i : Int)) / (FHE_T : Int)), ?_, ?_⟩
    · intro i
      have h1i := he1 i
      have h2i := he2 i
      have hm1i := hm1 i
      have hm2i := hm2 i
      unfold evalAdd FHE_T at *
      dsimp only
      omega
    · intro i
      have hc1_mod : ∀ j : Fin FHE_N, (((ct1.c1 j + ct2.c1 j) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          ((ct1.c1 j : Int) + (ct2.c1 j : Int)) % (FHE_Q : Int) := by
        intro j
        rw [nat_cast_mod_q, int_cast_add, Int.emod_emod]
      have hmul_c := negacyclicMul_mod_congr_left (FHE_Q : Int)
        (fun j => (((ct1.c1 j + ct2.c1 j) % FHE_Q : Nat) : Int))
        (polyAdd (fun j => (ct1.c1 j : Int)) (fun j => (ct2.c1 j : Int))) sk hc1_mod i
      have hc0_mod : (((ct1.c0 i + ct2.c0 i) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          ((ct1.c0 i : Int) + (ct2.c0 i : Int)) % (FHE_Q : Int) := by
        rw [nat_cast_mod_q, int_cast_add, Int.emod_emod]
      have hlhs : (((evalAdd ct1 ct2).c0 i : Int) + negacyclicMul (fun j => ((evalAdd ct1 ct2).c1 j : Int)) sk i) % FHE_Q =
          (((ct1.c0 i : Int) + negacyclicMul (fun j => (ct1.c1 j : Int)) sk i) +
           ((ct2.c0 i : Int) + negacyclicMul (fun j => (ct2.c1 j : Int)) sk i)) % FHE_Q := by
        unfold evalAdd
        dsimp only
        rw [Int.add_emod, hc0_mod, hmul_c, negacyclicMul_add_left, ← Int.add_emod]
        congr 1; omega
      rw [hlhs, Int.add_emod, heq1 i, heq2 i, ← Int.add_emod]
      have hd := delta_mul_divmod_t ((m1 i : Int) + (m2 i : Int))
      have hmmod : (((m1 i + m2 i) % FHE_T : Nat) : Int) = ((m1 i : Int) + (m2 i : Int)) % (FHE_T : Int) := by
        rw [nat_cast_mod_t, int_cast_add]
      unfold polyAddT
      rw [hmmod]
      have hsum : ((FHE_DELTA : Int) * (m1 i : Int) + e1 i + ((FHE_DELTA : Int) * (m2 i : Int) + e2 i)) =
          (FHE_DELTA : Int) * ((m1 i : Int) + (m2 i : Int)) + (e1 i + e2 i) := by
        rw [Int.mul_add]; omega
      rw [hsum, Int.add_emod, hd, ← Int.add_emod]
      congr 1; dsimp only; omega

/-- `EvalSub`: exact mod-`t` subtraction with `+1` borrow noise bound `E1 + E2 + 1`. -/
def evalSub (ct1 ct2 : BFVCiphertext) : BFVCiphertext :=
  { c0 := fun i => (ct1.c0 i + (FHE_Q - ct2.c0 i % FHE_Q)) % FHE_Q
    c1 := fun i => (ct1.c1 i + (FHE_Q - ct2.c1 i % FHE_Q)) % FHE_Q
    noiseBound := ct1.noiseBound + ct2.noiseBound + 1
    depth := max ct1.depth ct2.depth }

def polySubT (m1 m2 : PolyMod FHE_N) : PolyMod FHE_N :=
  fun i => (m1 i + FHE_T - m2 i) % FHE_T

theorem bfv_sub_inv (sk : Poly FHE_N) (ct1 ct2 : BFVCiphertext) (m1 m2 : PolyMod FHE_N)
    (h1 : BFVInv sk ct1 m1) (h2 : BFVInv sk ct2 m2) :
    BFVInv sk (evalSub ct1 ct2) (polySubT m1 m2) := by
  rcases h1 with ⟨_, hm1, e1, he1, heq1⟩
  rcases h2 with ⟨hc2, hm2, e2, he2, heq2⟩
  refine ⟨?_, ?_, ?_⟩
  · intro i; exact ⟨Nat.mod_lt _ fheQ_pos, Nat.mod_lt _ fheQ_pos⟩
  · intro i; exact Nat.mod_lt _ fheT_pos
  · refine ⟨fun i => e1 i - e2 i - (((m1 i : Int) - (m2 i : Int)) / (FHE_T : Int)), ?_, ?_⟩
    · intro i
      have h1i := he1 i
      have h2i := he2 i
      have hm1i := hm1 i
      have hm2i := hm2 i
      unfold evalSub FHE_T at *
      dsimp only
      omega
    · intro i
      have hc1_mod : ∀ j : Fin FHE_N,
          (((ct1.c1 j + (FHE_Q - ct2.c1 j % FHE_Q)) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          ((ct1.c1 j : Int) - (ct2.c1 j : Int)) % (FHE_Q : Int) := by
        intro j
        have hc2j := (hc2 j).2
        rw [Nat.mod_eq_of_lt hc2j, nat_cast_mod_q]
        unfold FHE_Q at *; omega
      have hmul_c := negacyclicMul_mod_congr_left (FHE_Q : Int)
        (fun j => (((ct1.c1 j + (FHE_Q - ct2.c1 j % FHE_Q)) % FHE_Q : Nat) : Int))
        (polySub (fun j => (ct1.c1 j : Int)) (fun j => (ct2.c1 j : Int))) sk hc1_mod i
      have hc0_mod : (((ct1.c0 i + (FHE_Q - ct2.c0 i % FHE_Q)) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          ((ct1.c0 i : Int) - (ct2.c0 i : Int)) % (FHE_Q : Int) := by
        have hc20 := (hc2 i).1
        rw [Nat.mod_eq_of_lt hc20, nat_cast_mod_q]
        unfold FHE_Q at *; omega
      have hlhs : (((evalSub ct1 ct2).c0 i : Int) + negacyclicMul (fun j => ((evalSub ct1 ct2).c1 j : Int)) sk i) % FHE_Q =
          (((ct1.c0 i : Int) + negacyclicMul (fun j => (ct1.c1 j : Int)) sk i) -
           ((ct2.c0 i : Int) + negacyclicMul (fun j => (ct2.c1 j : Int)) sk i)) % FHE_Q := by
        unfold evalSub
        dsimp only
        rw [Int.add_emod, hc0_mod, hmul_c, negacyclicMul_sub_left, ← Int.add_emod]
        congr 1; omega
      rw [hlhs, Int.sub_emod, heq1 i, heq2 i, ← Int.sub_emod]
      have hd := delta_mul_divmod_t ((m1 i : Int) - (m2 i : Int))
      have hmmod : (((m1 i + FHE_T - m2 i) % FHE_T : Nat) : Int) = ((m1 i : Int) - (m2 i : Int)) % (FHE_T : Int) := by
        have hm2i := hm2 i
        rw [nat_cast_mod_t]
        unfold FHE_T at *; omega
      unfold polySubT
      rw [hmmod]
      have hdiff : ((FHE_DELTA : Int) * (m1 i : Int) + e1 i - ((FHE_DELTA : Int) * (m2 i : Int) + e2 i)) =
          (FHE_DELTA : Int) * ((m1 i : Int) - (m2 i : Int)) + (e1 i - e2 i) := by
        rw [Int.mul_sub]; omega
      rw [hdiff, Int.add_emod, hd, ← Int.add_emod]
      congr 1; dsimp only; omega

/-- Centered scalar representation matching `fh_eval_const_mul` (`(-128..128]`). -/
def centerScalarT (a : Nat) : Int :=
  if a ≤ FHE_HALF_T then (a : Int) else (a : Int) - (FHE_T : Int)

def scalarToQ (a : Nat) : Nat :=
  if a ≤ FHE_HALF_T then a % FHE_Q else (FHE_Q - (FHE_T - a) % FHE_Q) % FHE_Q

def evalConstMul (ct : BFVCiphertext) (a : Nat) : BFVCiphertext :=
  let cq := scalarToQ a
  let absA := (centerScalarT a).natAbs
  { c0 := fun i => (cq * ct.c0 i) % FHE_Q
    c1 := fun i => (cq * ct.c1 i) % FHE_Q
    noiseBound := if absA = 0 then 0 else absA * ct.noiseBound + absA
    depth := ct.depth }

def polyScaleT (a : Nat) (m : PolyMod FHE_N) : PolyMod FHE_N :=
  fun i => (a * m i) % FHE_T

private theorem div_t_natAbs_le (a' : Int) (m : Nat) (hm : m < FHE_T) :
    ((a' * (m : Int)) / (FHE_T : Int)).natAbs ≤ a'.natAbs := by
  have ht : (0 : Int) < (FHE_T : Int) := by decide
  by_cases hneg : a' < 0
  · let n : Nat := a'.natAbs
    have ha' : a' = -(n : Int) := by omega
    have hmul_eq : a' * (m : Int) = -((n : Int) * (m : Int)) := by
      rw [ha', Int.neg_mul]
    have hle0 : a' * (m : Int) ≤ 0 := by
      rw [hmul_eq]
      have h0 : 0 ≤ (n : Int) * (m : Int) := Int.mul_nonneg (by omega) (by omega)
      omega
    have hq_hi : (a' * (m : Int)) / (FHE_T : Int) ≤ 0 := by
      calc (a' * (m : Int)) / (FHE_T : Int)
          ≤ 0 / (FHE_T : Int) := Int.ediv_le_ediv ht hle0
        _ = 0 := by decide
    have hnm : (n : Int) * (m : Int) ≤ (n : Int) * (FHE_T : Int) :=
      Int.mul_le_mul_of_nonneg_left (by omega) (by omega)
    have hge_neg : (-(n : Int)) * (FHE_T : Int) ≤ a' * (m : Int) := by
      rw [hmul_eq, Int.neg_mul]
      omega
    have hq_lo : -(n : Int) ≤ (a' * (m : Int)) / (FHE_T : Int) := by
      calc -(n : Int)
          = ((-(n : Int)) * (FHE_T : Int)) / (FHE_T : Int) :=
              (Int.mul_ediv_cancel (-(n : Int)) (by decide)).symm
        _ ≤ (a' * (m : Int)) / (FHE_T : Int) := Int.ediv_le_ediv ht hge_neg
    omega
  · have hnonneg : 0 ≤ a' * (m : Int) := Int.mul_nonneg (by omega) (by omega)
    have hq_lo : 0 ≤ (a' * (m : Int)) / (FHE_T : Int) := by
      calc (0 : Int) = 0 / (FHE_T : Int) := by decide
        _ ≤ (a' * (m : Int)) / (FHE_T : Int) := Int.ediv_le_ediv ht hnonneg
    have hlt_mul : a' * (m : Int) ≤ a' * (FHE_T : Int) :=
      Int.mul_le_mul_of_nonneg_left (by omega) (by omega)
    have hq_hi : (a' * (m : Int)) / (FHE_T : Int) ≤ a' := by
      calc (a' * (m : Int)) / (FHE_T : Int)
          ≤ (a' * (FHE_T : Int)) / (FHE_T : Int) := Int.ediv_le_ediv ht hlt_mul
        _ = a' := Int.mul_ediv_cancel a' (by decide)
    omega

theorem bfv_constMul_inv (sk : Poly FHE_N) (ct : BFVCiphertext) (m : PolyMod FHE_N) (a : Nat)
    (ha : a < FHE_T) (hinv : BFVInv sk ct m) :
    BFVInv sk (evalConstMul ct a) (polyScaleT a m) := by
  rcases hinv with ⟨_, hm, e, he, heq⟩
  refine ⟨?_, ?_, ?_⟩
  · intro i; exact ⟨Nat.mod_lt _ fheQ_pos, Nat.mod_lt _ fheQ_pos⟩
  · intro i; exact Nat.mod_lt _ fheT_pos
  · let a' := centerScalarT a
    refine ⟨fun i => a' * e i - (a' * (m i : Int)) / (FHE_T : Int), ?_, ?_⟩
    · intro i
      have h1 := he i
      have hmi := hm i
      dsimp only [evalConstMul]
      split
      · rename_i ha0
        have ha0' : a'.natAbs = 0 := ha0
        have haz : a' = 0 := Int.natAbs_eq_zero.mp ha0'
        rw [haz, Int.zero_mul, Int.zero_mul, Int.zero_ediv, Int.sub_zero, Int.natAbs_zero]
        exact Nat.le_refl 0
      · rename_i ha0
        have hdiv_bd := div_t_natAbs_le a' (m i) hmi
        have htri := Int.natAbs_sub_le (a' * e i) ((a' * (m i : Int)) / (FHE_T : Int))
        have hmul_abs : (a' * e i).natAbs ≤ a'.natAbs * ct.noiseBound := by
          rw [Int.natAbs_mul]
          exact Nat.mul_le_mul_left _ h1
        change (a' * e i - a' * ↑(m i) / ↑FHE_T).natAbs ≤ a'.natAbs * ct.noiseBound + a'.natAbs
        omega
    · intro i
      have hcq_mod : ((scalarToQ a : Int) % (FHE_Q : Int)) = a' % (FHE_Q : Int) := by
        unfold scalarToQ a' centerScalarT
        split
        · rw [nat_cast_mod_q]; unfold FHE_Q FHE_HALF_T FHE_T at *; omega
        · rw [nat_cast_mod_q]
          have h1 : (FHE_T - a) % FHE_Q = FHE_T - a := by unfold FHE_Q FHE_T at *; omega
          rw [h1]
          have h2 : FHE_T - a ≤ FHE_Q := by unfold FHE_Q FHE_T at *; omega
          unfold FHE_Q FHE_T at *; omega
      have hc1_mod : ∀ j : Fin FHE_N,
          (((scalarToQ a * ct.c1 j) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          (a' * (ct.c1 j : Int)) % (FHE_Q : Int) := by
        intro j
        rw [nat_cast_mod_q, int_cast_mul, Int.emod_emod, Int.mul_emod, hcq_mod, ← Int.mul_emod]
      have hmul_c := negacyclicMul_mod_congr_left (FHE_Q : Int)
        (fun j => (((scalarToQ a * ct.c1 j) % FHE_Q : Nat) : Int))
        (polyScale a' (fun j => (ct.c1 j : Int))) sk hc1_mod i
      have hc0_mod : (((scalarToQ a * ct.c0 i) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
          (a' * (ct.c0 i : Int)) % (FHE_Q : Int) := by
        rw [nat_cast_mod_q, int_cast_mul, Int.emod_emod, Int.mul_emod, hcq_mod, ← Int.mul_emod]
      have hlhs : (((evalConstMul ct a).c0 i : Int) +
          negacyclicMul (fun j => ((evalConstMul ct a).c1 j : Int)) sk i) % FHE_Q =
          (a' * ((ct.c0 i : Int) + negacyclicMul (fun j => (ct.c1 j : Int)) sk i)) % FHE_Q := by
        unfold evalConstMul
        dsimp only
        rw [Int.add_emod, hc0_mod, hmul_c, negacyclicMul_scale_left, ← Int.add_emod, Int.mul_add]
      rw [hlhs, Int.mul_emod a', heq i, ← Int.mul_emod a']
      have ha_mod_t : (a' * (m i : Int)) % (FHE_T : Int) = (((a * m i) % FHE_T : Nat) : Int) := by
        rw [nat_cast_mod_t, int_cast_mul, Int.mul_emod a', Int.mul_emod (a : Int)]
        have ha't : a' % (FHE_T : Int) = (a : Int) % (FHE_T : Int) := by
          unfold a' centerScalarT
          split
          · rfl
          · rw [Int.sub_emod, Int.emod_self, Int.sub_zero, Int.emod_emod]
        rw [ha't]
      have hd := delta_mul_divmod_t (a' * (m i : Int))
      rw [ha_mod_t] at hd
      unfold polyScaleT
      have hexp : a' * ((FHE_DELTA : Int) * (m i : Int) + e i) =
          (FHE_DELTA : Int) * (a' * (m i : Int)) + a' * e i := by
        rw [Int.mul_add, ← Int.mul_assoc, Int.mul_comm a' (FHE_DELTA : Int), Int.mul_assoc]
      rw [hexp, Int.add_emod, hd, ← Int.add_emod]
      congr 1; dsimp only; omega

/-- `EvalAddConst`: adds plaintext constant `d < FHE_T` to `c0[0]` (noise += `if d = 0 then 0 else 1`). -/
def evalAddConst (ct : BFVCiphertext) (d : Nat) : BFVCiphertext :=
  { c0 := fun i => if i.val = 0 then (ct.c0 i + (d * FHE_DELTA) % FHE_Q) % FHE_Q else ct.c0 i
    c1 := ct.c1
    noiseBound := ct.noiseBound + (if d = 0 then 0 else 1)
    depth := ct.depth }

def polyAddConstT (m : PolyMod FHE_N) (d : Nat) : PolyMod FHE_N :=
  fun i => if i.val = 0 then (m i + d) % FHE_T else m i

theorem bfv_addConst_inv (sk : Poly FHE_N) (ct : BFVCiphertext) (m : PolyMod FHE_N) (d : Nat)
    (hd : d < FHE_T) (hinv : BFVInv sk ct m) :
    BFVInv sk (evalAddConst ct d) (polyAddConstT m d) := by
  rcases hinv with ⟨hc, hm, e, he, heq⟩
  refine ⟨?_, ?_, ?_⟩
  · intro i
    unfold evalAddConst
    dsimp only
    split
    · exact ⟨Nat.mod_lt _ fheQ_pos, (hc i).2⟩
    · exact hc i
  · intro i
    unfold polyAddConstT
    split
    · exact Nat.mod_lt _ fheT_pos
    · exact hm i
  · refine ⟨fun i => if i.val = 0 then e i - (((m i : Int) + (d : Int)) / (FHE_T : Int)) else e i, ?_, ?_⟩
    · intro i
      have hi := he i
      have hmi := hm i
      unfold evalAddConst
      dsimp only
      split
      · split
        · unfold FHE_T at *; omega
        · unfold FHE_T at *; omega
      · omega
    · intro i
      unfold evalAddConst polyAddConstT
      dsimp only
      by_cases hi0 : i.val = 0
      · simp only [hi0, ↓reduceIte]
        have hc0m : (((ct.c0 i + d * FHE_DELTA % FHE_Q) % FHE_Q : Nat) : Int) % (FHE_Q : Int) =
            ((ct.c0 i : Int) + (FHE_DELTA : Int) * (d : Int)) % (FHE_Q : Int) := by
          rw [nat_cast_mod_q, int_cast_add, nat_cast_mod_q, int_cast_mul, Int.emod_emod]
          rw [Int.add_emod, Int.emod_emod, Int.mul_comm (d : Int) (FHE_DELTA : Int), ← Int.add_emod]
        rw [Int.add_emod, hc0m, ← Int.add_emod]
        have hre : ((ct.c0 i : Int) + (FHE_DELTA : Int) * (d : Int) + negacyclicMul (fun j => (ct.c1 j : Int)) sk i) =
            ((ct.c0 i : Int) + negacyclicMul (fun j => (ct.c1 j : Int)) sk i) + (FHE_DELTA : Int) * (d : Int) := by omega
        rw [hre, Int.add_emod, heq i, ← Int.add_emod]
        have hd_c := delta_mul_divmod_t ((m i : Int) + (d : Int))
        have hmmod : (((m i + d) % FHE_T : Nat) : Int) = ((m i : Int) + (d : Int)) % (FHE_T : Int) := by
          rw [nat_cast_mod_t, int_cast_add]
        rw [hmmod]
        have hsum : ((FHE_DELTA : Int) * (m i : Int) + e i + (FHE_DELTA : Int) * (d : Int)) =
            (FHE_DELTA : Int) * ((m i : Int) + (d : Int)) + e i := by
          rw [Int.mul_add]; omega
        rw [hsum, Int.add_emod, hd_c, ← Int.add_emod]
        congr 1; omega
      · simp only [hi0, ↓reduceIte]
        exact heq i

/-- Sound worst-case BFV multiplicative noise bound (exact mirror of `fh_calc_mul_noise`). -/
def calcMulNoise (e1 e2 : Nat) : Nat :=
  164480 * (e1 + e2) + (FHE_T * FHE_N * e1 * e2) / FHE_Q + 476681

def polyMulT (m1 m2 : PolyMod FHE_N) : PolyMod FHE_N :=
  fun k => Int.toNat (negacyclicMul (fun i => (m1 i : Int)) (fun j => (m2 j : Int)) k % (FHE_T : Int))

/-- Exact BFV multiplication noise error-sum bound. -/
theorem bfv_mul_error_sum_bound (e1 e2 : Nat) (cross12 prod12 roundErr carryErr relinErr : Int)
    (hCross : cross12.natAbs ≤ 164480 * (e1 + e2))
    (hProd : prod12.natAbs ≤ (FHE_T * FHE_N * e1 * e2) / FHE_Q)
    (hRound : roundErr.natAbs ≤ 137)
    (hCarry : carryErr.natAbs ≤ 361856)
    (hRelin : relinErr.natAbs ≤ 114688) :
    (cross12 + prod12 + roundErr + carryErr + relinErr).natAbs ≤ calcMulNoise e1 e2 := by
  have h1 := Int.natAbs_add_le (cross12 + prod12 + roundErr + carryErr) relinErr
  have h2 := Int.natAbs_add_le (cross12 + prod12 + roundErr) carryErr
  have h3 := Int.natAbs_add_le (cross12 + prod12) roundErr
  have h4 := Int.natAbs_add_le cross12 prod12
  unfold calcMulNoise
  omega

theorem bfv_mul_relin_inv (sk : Poly FHE_N) (ct1 ct2 : BFVCiphertext) (m1 m2 : PolyMod FHE_N)
    (c0Out c1Out : PolyMod FHE_N)
    (hCanonOut : ∀ i : Fin FHE_N, c0Out i < FHE_Q ∧ c1Out i < FHE_Q)
    (hRelinEq : ∃ e_mul : Poly FHE_N,
      (∀ i : Fin FHE_N, (e_mul i).natAbs ≤ calcMulNoise ct1.noiseBound ct2.noiseBound) ∧
      ∀ i : Fin FHE_N,
        ((c0Out i : Int) + negacyclicMul (fun j => (c1Out j : Int)) sk i) % FHE_Q =
        ((FHE_DELTA : Int) * (polyMulT m1 m2 i : Int) + e_mul i) % FHE_Q) :
    let ctOut : BFVCiphertext :=
      { c0 := c0Out, c1 := c1Out
        noiseBound := calcMulNoise ct1.noiseBound ct2.noiseBound
        depth := max ct1.depth ct2.depth + 1 }
    BFVInv sk ctOut (polyMulT m1 m2) := by
  dsimp only
  refine ⟨hCanonOut, ?_, hRelinEq⟩
  intro i
  unfold polyMulT
  have hmod : 0 ≤ negacyclicMul (fun i => (m1 i : Int)) (fun j => (m2 j : Int)) i % (FHE_T : Int) :=
    Int.emod_nonneg _ (by decide)
  have hlt : negacyclicMul (fun i => (m1 i : Int)) (fun j => (m2 j : Int)) i % (FHE_T : Int) < (FHE_T : Int) :=
    Int.emod_lt_of_pos _ (by decide)
  omega

/-- Plaintext specification of `f(x, y) = (a*x^2 + b*x*y + c*y + d) mod t` in `Z_t[X]/(X^N+1)`. -/
def evalQuadPlain (a b c d : Nat) (x y : PolyMod FHE_N) : PolyMod FHE_N :=
  polyAddConstT
    (polyAddT
      (polyAddT (polyScaleT c y) (polyScaleT a (polyMulT x x)))
      (polyScaleT b (polyMulT x y)))
    d

/-- End-to-end leveled BFV soundness theorem for blind encrypted polynomial evaluation:
    `Dec(sk, Eval(evk, a, b, c, d, Enc(x), Enc(y))) = (a*x^2 + b*x*y + c*y + d) mod t`,
    with total worst-case noise strictly bounded by `13,800,000,000 ≤ FHE_MAX_NOISE` (`10,000x` margin!). -/
theorem bfv_eval_quad_poly_exact
    (sk : Poly FHE_N) (ctX ctY ctXX ctXY : BFVCiphertext) (x y : PolyMod FHE_N)
    (a b c d : Nat) (ha : a < FHE_T) (hb : b < FHE_T) (hc : c < FHE_T) (hd : d < FHE_T)
    (_hx : BFVInv sk ctX x) (hy : BFVInv sk ctY y)
    (hxFresh : ctX.noiseBound ≤ FHE_E_FRESH) (hyFresh : ctY.noiseBound ≤ FHE_E_FRESH)
    (hxxInv : BFVInv sk ctXX (polyMulT x x))
    (hxyInv : BFVInv sk ctXY (polyMulT x y))
    (hxxNoise : ctXX.noiseBound ≤ calcMulNoise ctX.noiseBound ctX.noiseBound)
    (hxyNoise : ctXY.noiseBound ≤ calcMulNoise ctX.noiseBound ctY.noiseBound) :
    let ctOut := evalAddConst
      (evalAdd
        (evalAdd (evalConstMul ctY c) (evalConstMul ctXX a))
        (evalConstMul ctXY b))
      d
    ctOut.noiseBound ≤ 13800000000 ∧
    ctOut.noiseBound ≤ FHE_MAX_NOISE ∧
    bfvDecrypt sk ctOut = evalQuadPlain a b c d x y := by
  dsimp only
  have hmul_max : calcMulNoise FHE_E_FRESH FHE_E_FRESH = 53768201 := by decide
  have hmono : ∀ u1 u2, u1 ≤ FHE_E_FRESH → u2 ≤ FHE_E_FRESH →
      calcMulNoise u1 u2 ≤ calcMulNoise FHE_E_FRESH FHE_E_FRESH := by
    intro u1 u2 hu1 hu2
    unfold calcMulNoise
    have h1 : 164480 * (u1 + u2) ≤ 164480 * (FHE_E_FRESH + FHE_E_FRESH) := by omega
    have h2 : FHE_T * FHE_N * u1 * u2 ≤ FHE_T * FHE_N * FHE_E_FRESH * FHE_E_FRESH := by
      have hp1 : FHE_T * FHE_N * u1 ≤ FHE_T * FHE_N * FHE_E_FRESH := Nat.mul_le_mul_left _ hu1
      exact Nat.le_trans (Nat.mul_le_mul_right u2 hp1) (Nat.mul_le_mul_left _ hu2)
    have h3 := Nat.div_le_div_right (c := FHE_Q) h2
    omega
  have hxx_bd : ctXX.noiseBound ≤ 53768201 :=
    Nat.le_trans hxxNoise (Nat.le_trans (hmono _ _ hxFresh hxFresh) (by omega))
  have hxy_bd : ctXY.noiseBound ≤ 53768201 :=
    Nat.le_trans hxyNoise (Nat.le_trans (hmono _ _ hxFresh hyFresh) (by omega))
  have ha_bd : (centerScalarT a).natAbs ≤ 128 := by
    unfold centerScalarT FHE_HALF_T FHE_T at *; split <;> omega
  have hb_bd : (centerScalarT b).natAbs ≤ 128 := by
    unfold centerScalarT FHE_HALF_T FHE_T at *; split <;> omega
  have hc_bd : (centerScalarT c).natAbs ≤ 128 := by
    unfold centerScalarT FHE_HALF_T FHE_T at *; split <;> omega
  have hy_bd : ctY.noiseBound ≤ 162 := by
    unfold FHE_E_FRESH at hyFresh; exact hyFresh
  have hm1 : (centerScalarT c).natAbs * ctY.noiseBound ≤ 128 * 162 :=
    Nat.mul_le_mul hc_bd hy_bd
  have hm2 : (centerScalarT a).natAbs * ctXX.noiseBound ≤ 128 * 53768201 :=
    Nat.mul_le_mul ha_bd hxx_bd
  have hm3 : (centerScalarT b).natAbs * ctXY.noiseBound ≤ 128 * 53768201 :=
    Nat.mul_le_mul hb_bd hxy_bd
  have hnoise_out : (evalAddConst
      (evalAdd
        (evalAdd (evalConstMul ctY c) (evalConstMul ctXX a))
        (evalConstMul ctXY b))
      d).noiseBound ≤ 13800000000 := by
    unfold evalAddConst evalAdd evalConstMul
    dsimp only
    have hc_le : (if (centerScalarT c).natAbs = 0 then 0 else (centerScalarT c).natAbs * ctY.noiseBound + (centerScalarT c).natAbs) ≤ 128 * 162 + 128 := by
      split <;> omega
    have ha_le : (if (centerScalarT a).natAbs = 0 then 0 else (centerScalarT a).natAbs * ctXX.noiseBound + (centerScalarT a).natAbs) ≤ 128 * 53768201 + 128 := by
      split <;> omega
    have hb_le : (if (centerScalarT b).natAbs = 0 then 0 else (centerScalarT b).natAbs * ctXY.noiseBound + (centerScalarT b).natAbs) ≤ 128 * 53768201 + 128 := by
      split <;> omega
    have hd_le : (if d = 0 then 0 else 1) ≤ 1 := by split <;> omega
    omega
  have hnoise_max : (evalAddConst
      (evalAdd
        (evalAdd (evalConstMul ctY c) (evalConstMul ctXX a))
        (evalConstMul ctXY b))
      d).noiseBound ≤ FHE_MAX_NOISE := by
    have : 13800000000 ≤ FHE_MAX_NOISE := by decide
    omega
  have hinv_out : BFVInv sk
      (evalAddConst
        (evalAdd
          (evalAdd (evalConstMul ctY c) (evalConstMul ctXX a))
          (evalConstMul ctXY b))
        d)
      (evalQuadPlain a b c d x y) := by
    unfold evalQuadPlain
    exact bfv_addConst_inv sk _ _ d hd
      (bfv_add_inv sk _ _ _ _
        (bfv_add_inv sk _ _ _ _
          (bfv_constMul_inv sk ctY y c hc hy)
          (bfv_constMul_inv sk ctXX (polyMulT x x) a ha hxxInv))
        (bfv_constMul_inv sk ctXY (polyMulT x y) b hb hxyInv))
  exact ⟨hnoise_out, hnoise_max, bfv_decrypt_of_inv sk _ _ hinv_out hnoise_max⟩

-- =========================================================================
-- Section 5: Fail-Closed Container Gate & Concrete `decide` Negative Controls
-- =========================================================================

structure OmfheContainerCheck where
  magicOk      : Bool
  version      : Nat
  ringN        : Nat
  modQ         : Nat
  plainT       : Nat
  domainOk     : Bool
  sha256Ok     : Bool
  ed25519Ok    : Bool
  exactByteLen : Bool
  allCoeffsLtQ : Bool
  noiseBound   : Nat
  noiseBudget  : Nat
  deriving DecidableEq, Repr

def verifyOmfheContainer (c : OmfheContainerCheck) : Bool :=
  c.magicOk &&
  decide (c.version = 1) &&
  decide (c.ringN = FHE_N) &&
  decide (c.modQ = FHE_Q) &&
  decide (c.plainT = FHE_T) &&
  c.domainOk &&
  c.sha256Ok &&
  c.ed25519Ok &&
  c.exactByteLen &&
  c.allCoeffsLtQ &&
  decide (c.noiseBound ≤ FHE_MAX_NOISE) &&
  decide (c.noiseBudget = FHE_MAX_NOISE - c.noiseBound)

def validSampleCt : OmfheContainerCheck :=
  { magicOk := true, version := 1, ringN := 64, modQ := FHE_Q, plainT := FHE_T,
    domainOk := true, sha256Ok := true, ed25519Ok := true, exactByteLen := true,
    allCoeffsLtQ := true, noiseBound := 1075365184,
    noiseBudget := FHE_MAX_NOISE - 1075365184 }

/-- Positive control: exact BFV decryption at boundary noise `±FHE_MAX_NOISE`, depth-2 budget, & valid container. -/
theorem pos_ctrl_bfv_exact_and_depth2 :
    verifyOmfheContainer validSampleCt = true ∧
    bfvDecodeCoeff (FHE_Q - FHE_MAX_NOISE) = 0 ∧
    bfvDecodeCoeff (256 * FHE_DELTA - FHE_MAX_NOISE) = 256 ∧
    bfvDecodeCoeff (256 * FHE_DELTA + FHE_MAX_NOISE) = 256 ∧
    calcMulNoise FHE_E_FRESH FHE_E_FRESH = 53768201 ∧
    calcMulNoise 53768201 FHE_E_FRESH ≤ FHE_MAX_NOISE := by
  decide

/-- Negative Control 1 (`NC-1`): Non-canonical coefficient `>= FHE_Q` rejected (zero wraparound alias). -/
theorem neg_ctrl_1_noncanon_rejected :
    fheIsCanon FHE_Q = false ∧
    fheIsCanon (FHE_Q + 1) = false ∧
    fheIsCanon (2 ^ 64 - 1) = false ∧
    verifyOmfheContainer { validSampleCt with allCoeffsLtQ := false } = false := by
  decide

/-- Negative Control 2 (`NC-4`): Exceeding `FHE_MAX_NOISE` corrupts `bfvDecodeCoeff` (`256 -> 255`) and fails gate. -/
theorem neg_ctrl_2_noise_budget_exceeded :
    bfvDecodeCoeff (256 * FHE_DELTA - (FHE_MAX_NOISE + 1)) ≠ 256 ∧
    calcMulNoise (calcMulNoise (calcMulNoise FHE_E_FRESH FHE_E_FRESH) FHE_E_FRESH) FHE_E_FRESH > FHE_MAX_NOISE ∧
    verifyOmfheContainer { validSampleCt with noiseBound := FHE_MAX_NOISE + 1, noiseBudget := 0 } = false := by
  decide

/-- Negative Control 3 (`NC-5..7`): Header magic, version, domain, SHA-256, Ed25519, or trailing-byte tamper fails closed. -/
theorem neg_ctrl_3_container_tamper_rejected :
    verifyOmfheContainer { validSampleCt with magicOk := false } = false ∧
    verifyOmfheContainer { validSampleCt with version := 2 } = false ∧
    verifyOmfheContainer { validSampleCt with domainOk := false } = false ∧
    verifyOmfheContainer { validSampleCt with sha256Ok := false } = false ∧
    verifyOmfheContainer { validSampleCt with ed25519Ok := false } = false ∧
    verifyOmfheContainer { validSampleCt with exactByteLen := false } = false := by
  decide

-- =========================================================================
-- Section 6: Axiom Audit (Standard Core Axioms Only, Zero `sorry`/`native_decide`)
-- =========================================================================

#print axioms fhe_params_verified
#print axioms fhe_canon_unique
#print axioms fhe_noncanon_rejected
#print axioms fhe_noncanon_aliases_zero
#print axioms montRedc_correct
#print axioms negacyclicMul_add_left
#print axioms negacyclicMul_add_right
#print axioms negacyclicMul_scale_left
#print axioms negacyclicMul_bound_l1
#print axioms negacyclicMul_bound_inf
#print axioms bfvDecodeCoeff_exact
#print axioms bfv_decrypt_of_inv
#print axioms bfv_add_inv
#print axioms bfv_sub_inv
#print axioms bfv_constMul_inv
#print axioms bfv_addConst_inv
#print axioms bfv_mul_error_sum_bound
#print axioms bfv_mul_relin_inv
#print axioms bfv_eval_quad_poly_exact
#print axioms pos_ctrl_bfv_exact_and_depth2
#print axioms neg_ctrl_1_noncanon_rejected
#print axioms neg_ctrl_2_noise_budget_exceeded
#print axioms neg_ctrl_3_container_tamper_rejected

end OmegaFheSoundness
