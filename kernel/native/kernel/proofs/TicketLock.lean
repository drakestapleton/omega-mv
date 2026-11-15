/-
  TicketLock.lean -- the arithmetic behind core/spinlock.h (DRA-556).

  The lock holds two 32-bit counters, ticket and serving, compared only for equality and
  wrapping mod 2^32. While n callers hold tickets (the holder plus waiters), those tickets are
  serving + 0, serving + 1, ..., serving + (n-1) (mod 2^32), because each caller took the next
  value of ticket with a fetch-add and the holder releases by serving := serving + 1.

  Proved here, for any modulus M > 0 (the code uses M = 2^32) and n <= M:
  * mutual exclusion: the caller with offset i may enter (its ticket equals serving) iff i = 0;
  * FIFO: after a release, the caller at offset i + 1 is at offset i, so callers enter in the
    order they took tickets.
  No Mathlib; core Lean 4 only.
-/

/-- Ticket of the caller at queue offset `i`, mod `M`. -/
def tk (M s i : Nat) : Nat := (s + i) % M

/-- A caller enters when its ticket equals the serving counter. -/
def enters (M s i : Nat) : Prop := tk M s i = s % M

theorem offset_zero_enters (M s : Nat) : enters M s 0 := by
  simp [enters, tk]

/-- Mutual exclusion: with fewer than M callers, only offset 0 can enter. -/
theorem only_head_enters (M s i : Nat) (hi : i < M) (h : enters M s i) : i = 0 := by
  unfold enters tk at h
  -- (s + i) % M = s % M  ->  i % M = 0  (since (s + i) % M = (s % M + i % M) % M)
  have hM : 0 < M := Nat.lt_of_le_of_lt (Nat.zero_le i) hi
  have h1 : (s % M + i) % M = s % M := by rw [Nat.add_mod, Nat.mod_mod, ← Nat.add_mod] at *; simpa [Nat.add_mod] using h
  have hlt : s % M < M := Nat.mod_lt _ hM
  rcases Nat.eq_zero_or_pos i with h0 | hpos
  · exact h0
  -- s % M + i lies in (s % M, s % M + M), so its residue differs from s % M
  by_cases hc : s % M + i < M
  · rw [Nat.mod_eq_of_lt hc] at h1
    omega
  · have hge : M ≤ s % M + i := Nat.le_of_not_lt hc
    have hlt2 : s % M + i - M < M := by omega
    have : (s % M + i) % M = s % M + i - M := by
      rw [Nat.mod_eq_sub_mod hge, Nat.mod_eq_of_lt hlt2]
    rw [this] at h1
    omega

/-- Two callers with offsets below M never both enter. -/
theorem mutual_exclusion (M s i j : Nat) (hi : i < M) (hj : j < M)
    (h1 : enters M s i) (h2 : enters M s j) : i = j := by
  rw [only_head_enters M s i hi h1, only_head_enters M s j hj h2]

/-- Release moves serving to s + 1: the caller at offset i + 1 now has offset i (FIFO). -/
theorem release_shifts (M s i : Nat) : tk M s (i + 1) = tk M (s + 1) i := by
  unfold tk
  rw [Nat.add_assoc, Nat.add_comm 1 i]

/-- FIFO: the caller at offset k enters after exactly k releases, and not before. -/
theorem enters_after_k_releases (M s k : Nat) (hk : k < M) :
    enters M (s + k) 0 ∧ ∀ r, r < k → ¬ enters M (s + r) (k - r) := by
  refine ⟨offset_zero_enters M (s + k), ?_⟩
  intro r hr h
  have := only_head_enters M (s + r) (k - r) (by omega) h
  omega

/-- Counters wrap: equality mod M is all the code compares, and the tickets above stay
    consistent across 2^32 (instance used by core/spinlock.h). -/
theorem wrap_instance : enters (2^32) (2^32 - 1) 0 ∧ ¬ enters (2^32) (2^32 - 1) 1 := by
  refine ⟨offset_zero_enters _ _, ?_⟩
  intro h
  have := only_head_enters (2^32) (2^32 - 1) 1 (by decide) h
  omega
