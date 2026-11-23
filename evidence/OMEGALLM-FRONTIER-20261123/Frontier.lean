import Std

namespace SynthFrontier

-- Both loops in syExpandLevel use an offset into a frozen half-open interval.
def visits (first stop : Nat) : List Nat :=
  (List.range (stop - first)).map (fun offset => first + offset)

theorem visits_exactly (first stop i : Nat) :
    i ∈ visits first stop ↔ first ≤ i ∧ i < stop := by
  simp only [visits, List.mem_map, List.mem_range]
  constructor
  · rintro ⟨offset, bound, rfl⟩
    omega
  · rintro ⟨lo, hi⟩
    exact ⟨i - first, by omega, by omega⟩

-- In phase B, an earlier right operand has no later outer-loop turn.
-- A same-level pair has exactly one commutative orientation, including the diagonal.
def emitsCommutative (first i j : Nat) : Prop := ¬ (j ≥ first ∧ i > j)

theorem earlier_order (first i j : Nat) (prior : j < first) :
    emitsCommutative first i j := by unfold emitsCommutative; omega

theorem same_level_order (first i j : Nat) (right : first ≤ j) :
    emitsCommutative first i j ↔ i ≤ j := by unfold emitsCommutative; omega

-- syAdmit requires both counters below their existing limits; neither decreases during expansion.
theorem capacity_stays_closed (nodes occupied nodeLimit occupancyLimit nextNodes nextOccupied : Nat)
    (full : nodes ≥ nodeLimit ∨ occupied ≥ occupancyLimit)
    (monotoneNodes : nodes ≤ nextNodes) (monotoneOccupancy : occupied ≤ nextOccupied) :
    ¬ (nextNodes < nodeLimit ∧ nextOccupied < occupancyLimit) := by omega

end SynthFrontier

#print axioms SynthFrontier.visits_exactly
#print axioms SynthFrontier.earlier_order
#print axioms SynthFrontier.same_level_order
#print axioms SynthFrontier.capacity_stays_closed
