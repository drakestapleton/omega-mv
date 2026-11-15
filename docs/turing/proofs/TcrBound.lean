/-
SPDX-License-Identifier: Apache-2.0
Copyright 2026 Drake Stapleton (AIEN / aien-dev)

docs/turing/proofs/TcrBound.lean: the length bound of the TCR1 range coder (L111).

Model (transcribed from calibration/docs/CODER_SPEC.md section 5 and src/turing/tc_range.om
`encs`, which is byte-identical to src/turing/tc_range.c on every gate unit):
  r = R >> 16;  R' = (last ? R - r*cum : r*q);  while R' < 2^24: R' <<= 8, shifts += 1
with R in [2^24, 2^32) between symbols, R0 = 2^32 - 1, q >= 1, cum + q <= 65536 and
cum + q = 65536 for the last symbol of the row (rows sum to 65536).

Main result `encode_bound`: for every valid symbol list of length n with realised entries q_t,
  R0 * (prod q_t) * 16711681^n * 256^S < 2^32 * (2^40)^n
where S is the total number of renormalisation shifts and 16711681 = 2^24 - 65535.
Taking log2 (docs/turing/TURING_YIELD_RANGE_CODER_OM.md):
  8 S < sum_t (16 - log2 q_t) + n * (24 - log2 16711681) + (32 - log2 R0)
      = ideal_exact_bits + n * eps + 3.36e-10,   eps = -log2(1 - 65535/2^24).
Natural numbers only; no Mathlib, no sorry, no extra axioms.
-/
namespace TcrBound

def TOP : Nat := 16777216          -- 2^24
def MQ : Nat := 65536              -- 2^16, the row total
def C : Nat := 16711681            -- 2^24 - 65535

/-- One coding step before renormalisation (CODER_SPEC s.5). -/
def step (R q cum : Nat) (last : Bool) : Nat :=
  if last then R - (R / MQ) * cum else (R / MQ) * q

/-- Renormalisation: at most two byte shifts are needed once R' >= 256 (lemma `step_ge`). -/
def renorm (R : Nat) : Nat × Nat :=
  if R < TOP then (if R * 256 < TOP then (R * 65536, 2) else (R * 256, 1)) else (R, 0)

structure Sym where
  q : Nat
  cum : Nat
  last : Bool

def Sym.valid (s : Sym) : Prop :=
  1 ≤ s.q ∧ s.cum + s.q ≤ MQ ∧ (s.last = true → s.cum + s.q = MQ)

/-- Encoder range and shift count after a list of symbols. -/
def run : Nat → List Sym → Nat × Nat
  | R, [] => (R, 0)
  | R, s :: rest =>
      let p := renorm (step R s.q s.cum s.last)
      let t := run p.1 rest
      (t.1, p.2 + t.2)

def prodq : List Sym → Nat
  | [] => 1
  | s :: rest => s.q * prodq rest

theorem div_facts (R : Nat) : MQ * (R / MQ) ≤ R ∧ R < MQ * (R / MQ) + MQ := by
  have h1 := Nat.div_add_mod R MQ
  have h2 : R % MQ < MQ := Nat.mod_lt R (by decide)
  constructor <;> omega

/-- The per-step inequality: the coded interval keeps at least (1 - 65535/2^24) of p * R. -/
theorem step_lb (R : Nat) (s : Sym) (hR : TOP ≤ R) (hv : s.valid) :
    R * s.q * C ≤ step R s.q s.cum s.last * (MQ * TOP) := by
  obtain ⟨hq, hc, hl⟩ := hv
  obtain ⟨d1, d2⟩ := div_facts R
  unfold step
  cases hlast : s.last
  · -- r * q: 2^40 * r >= 16711681 * R, times q
    simp only [Bool.false_eq_true, ↓reduceIte]
    have key : R * C ≤ (R / MQ) * (MQ * TOP) := by
      unfold C MQ TOP at *; omega
    calc R * s.q * C = (R * C) * s.q := by rw [Nat.mul_right_comm]
      _ ≤ ((R / MQ) * (MQ * TOP)) * s.q := Nat.mul_le_mul_right _ key
      _ = (R / MQ) * s.q * (MQ * TOP) := by rw [Nat.mul_right_comm]
  · -- R - r * cum, with cum + q = 2^16
    simp only [↓reduceIte]
    have hsum := hl hlast
    have a1 : MQ * ((R / MQ) * s.cum) ≤ R * s.cum := by
      rw [← Nat.mul_assoc]; exact Nat.mul_le_mul_right _ d1
    have a2 : R * s.cum + R * s.q = R * MQ := by rw [← Nat.mul_add, hsum]
    have a3 : (R / MQ) * s.cum ≤ R := by
      have : (R / MQ) * s.cum ≤ (R / MQ) * MQ := Nat.mul_le_mul_left _ (by omega)
      rw [Nat.mul_comm (R / MQ) MQ] at this; omega
    have a4 : R * s.q ≤ (R - (R / MQ) * s.cum) * MQ := by
      rw [Nat.sub_mul]; rw [Nat.mul_comm ((R / MQ) * s.cum) MQ]; omega
    have a5 : R * s.q * C ≤ R * s.q * TOP := Nat.mul_le_mul_left _ (by unfold C TOP; omega)
    calc R * s.q * C ≤ R * s.q * TOP := a5
      _ ≤ ((R - (R / MQ) * s.cum) * MQ) * TOP := Nat.mul_le_mul_right _ a4
      _ = (R - (R / MQ) * s.cum) * (MQ * TOP) := by rw [Nat.mul_assoc]

/-- R' >= 256 and R' <= R: renormalisation needs at most two shifts and never overflows. -/
theorem step_ge (R : Nat) (s : Sym) (hR : TOP ≤ R) (hv : s.valid) :
    256 ≤ step R s.q s.cum s.last ∧ step R s.q s.cum s.last ≤ R := by
  obtain ⟨hq, hc, hl⟩ := hv
  obtain ⟨d1, d2⟩ := div_facts R
  have hr : 256 ≤ R / MQ := by unfold TOP MQ at *; omega
  unfold step
  cases hlast : s.last
  · simp only [Bool.false_eq_true, ↓reduceIte]
    have u1 : (R / MQ) * 1 ≤ (R / MQ) * s.q := Nat.mul_le_mul_left _ hq
    have u2 : (R / MQ) * s.q ≤ (R / MQ) * MQ := Nat.mul_le_mul_left _ (by omega)
    rw [Nat.mul_comm (R / MQ) MQ] at u2
    omega
  · simp only [↓reduceIte]
    have u2 : (R / MQ) * s.cum ≤ (R / MQ) * (MQ - 1) := Nat.mul_le_mul_left _ (by omega)
    have u3 : (R / MQ) * (MQ - 1) + (R / MQ) = MQ * (R / MQ) := by
      unfold MQ; rw [Nat.mul_comm 65536]; omega
    omega

def W : Nat := 4294967296          -- 2^32

theorem renorm_spec (x : Nat) (h1 : 256 ≤ x) (h2 : x < W) :
    (renorm x).1 = x * 256 ^ (renorm x).2 ∧ TOP ≤ (renorm x).1 ∧ (renorm x).1 < W := by
  unfold renorm
  by_cases a : x < TOP
  · by_cases b : x * 256 < TOP
    · simp only [a, b, ↓reduceIte]
      have hb : x < 65536 := by unfold TOP at b; omega
      have c1 : x * 65536 < 65536 * 65536 := Nat.mul_lt_mul_of_pos_right hb (by decide)
      have c2 : 256 * 65536 ≤ x * 65536 := Nat.mul_le_mul_right _ h1
      refine ⟨?_, ?_, ?_⟩
      · trivial
      · show 16777216 ≤ x * 65536
        exact c2
      · show x * 65536 < 4294967296
        exact c1
    · simp only [a, b, ↓reduceIte]
      have c1 : x * 256 < 65536 * 65536 := by unfold TOP at a; omega
      refine ⟨?_, ?_, ?_⟩
      · trivial
      · show 16777216 ≤ x * 256
        unfold TOP at b; omega
      · show x * 256 < 4294967296
        exact c1
  · simp only [a, ↓reduceIte]
    refine ⟨?_, ?_, h2⟩
    · show x = x * 256 ^ 0
      rw [Nat.pow_zero, Nat.mul_one]
    · unfold TOP at *; omega

theorem run_cons (R : Nat) (s : Sym) (rest : List Sym) :
    run R (s :: rest) =
      ((run (renorm (step R s.q s.cum s.last)).1 rest).1,
       (renorm (step R s.q s.cum s.last)).2 + (run (renorm (step R s.q s.cum s.last)).1 rest).2) := rfl

/-- Telescoped bound from any start range in [2^24, 2^32). -/
theorem run_bound (l : List Sym) (hv : ∀ s ∈ l, s.valid) :
    ∀ R, TOP ≤ R → R < W →
      R * prodq l * C ^ l.length * 256 ^ (run R l).2 ≤ (run R l).1 * (MQ * TOP) ^ l.length ∧
      TOP ≤ (run R l).1 ∧ (run R l).1 < W := by
  induction l with
  | nil => intro R h1 h2; simp [run, prodq]; exact ⟨h1, h2⟩
  | cons s rest ih =>
    intro R h1 h2
    have hs : s.valid := hv s (by simp)
    have hrest : ∀ x ∈ rest, x.valid := fun x hx => hv x (by simp [hx])
    obtain ⟨g1, g2⟩ := step_ge R s h1 hs
    have lb := step_lb R s h1 hs
    rw [run_cons]
    simp only [prodq, List.length_cons]
    generalize step R s.q s.cum s.last = x at g1 g2 lb ⊢
    obtain ⟨e1, e2, e3⟩ := renorm_spec x g1 (by omega)
    generalize renorm x = p at e1 e2 e3 ⊢
    obtain ⟨R2, k⟩ := p
    simp only at e1 e2 e3 ⊢
    obtain ⟨i1, i2, i3⟩ := ih hrest R2 e2 e3
    refine ⟨?_, i2, i3⟩
    have lb2 : R * s.q * C * 256 ^ k ≤ R2 * (MQ * TOP) := by
      rw [e1]
      calc R * s.q * C * 256 ^ k ≤ x * (MQ * TOP) * 256 ^ k := Nat.mul_le_mul_right _ lb
        _ = x * 256 ^ k * (MQ * TOP) := by rw [Nat.mul_right_comm]
    calc R * (s.q * prodq rest) * C ^ (rest.length + 1) * 256 ^ (k + (run R2 rest).2)
        = (R * s.q * C * 256 ^ k) * (prodq rest * C ^ rest.length * 256 ^ (run R2 rest).2) := by
          rw [Nat.pow_succ, Nat.pow_add]; ac_rfl
      _ ≤ (R2 * (MQ * TOP)) * (prodq rest * C ^ rest.length * 256 ^ (run R2 rest).2) :=
          Nat.mul_le_mul_right _ lb2
      _ = (R2 * prodq rest * C ^ rest.length * 256 ^ (run R2 rest).2) * (MQ * TOP) := by ac_rfl
      _ ≤ ((run R2 rest).1 * (MQ * TOP) ^ rest.length) * (MQ * TOP) := Nat.mul_le_mul_right _ i1
      _ = (run R2 rest).1 * (MQ * TOP) ^ (rest.length + 1) := by rw [Nat.pow_succ]; ac_rfl

/-- The coder's start range 2^32 - 1: the result used for the length bound
(W = 2^32, MQ * TOP = 2^40). -/
theorem encode_bound (l : List Sym) (hv : ∀ s ∈ l, s.valid) :
    (W - 1) * prodq l * C ^ l.length * 256 ^ (run (W - 1) l).2 < W * (MQ * TOP) ^ l.length := by
  obtain ⟨b1, _, b3⟩ := run_bound l hv (W - 1) (by unfold TOP W; omega) (by unfold W; omega)
  have hpos : 0 < (MQ * TOP) ^ l.length := Nat.pow_pos (by unfold MQ TOP; omega)
  calc _ ≤ (run (W - 1) l).1 * (MQ * TOP) ^ l.length := b1
    _ < W * (MQ * TOP) ^ l.length := Nat.mul_lt_mul_of_pos_right b3 hpos

theorem constants : W = 2 ^ 32 ∧ MQ * TOP = 2 ^ 40 ∧ C = 2 ^ 24 - 65535 ∧ TOP = 2 ^ 24 ∧ MQ = 2 ^ 16 := by
  unfold W MQ TOP C; decide

/-! Negative control: a coder that drops the last-symbol slack rule and uses r = R >> 17
violates the per-step inequality on a concrete valid symbol, so `step_lb` is not vacuous. -/
def badStep (R q : Nat) : Nat := (R / 131072) * q

theorem bad_step_violates :
    ¬ (16777216 * 1 * C ≤ badStep 16777216 1 * (MQ * TOP)) := by
  unfold badStep C MQ TOP; decide

/-- Second control: the loss factor C < 2^24 is needed. With no loss (C replaced by 2^24) the
per-step inequality fails at R = 2^24 + 65535, q = 1, cum = 0, where r = R >> 16 = 256 throws
away 65535 of the range: the per-symbol eps of the bound is a real cost, not slack. -/
theorem tight_without_loss :
    ¬ ((16777216 + 65535) * 1 * 16777216 ≤ step (16777216 + 65535) 1 0 false * (MQ * TOP)) := by
  unfold step MQ TOP; decide

end TcrBound

#print axioms TcrBound.step_lb
#print axioms TcrBound.run_bound
#print axioms TcrBound.encode_bound
#print axioms TcrBound.constants
#print axioms TcrBound.tight_without_loss
#print axioms TcrBound.bad_step_violates
