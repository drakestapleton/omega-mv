import Std

-- measure.query admits a previously unused input exactly when fewer than eight
-- answers have been recorded. A fallback and a regeneration use that same gate.
def charge (used : Nat) (fresh : Bool) : Nat :=
  if fresh && decide (used < 8) then used + 1 else used

theorem charge_bounded (used : Nat) (fresh : Bool) (h : used ≤ 8) :
    charge used fresh ≤ 8 := by
  unfold charge
  split <;> simp_all <;> omega

theorem sequence_bounded (attempts : List Bool) (used : Nat) (h : used ≤ 8) :
    attempts.foldl charge used ≤ 8 := by
  induction attempts generalizing used with
  | nil => exact h
  | cons fresh rest ih => exact ih _ (charge_bounded used fresh h)

theorem starting_with_four (attempts : List Bool) :
    attempts.foldl charge 4 ≤ 8 := sequence_bounded attempts 4 (by decide)

#print axioms starting_with_four
