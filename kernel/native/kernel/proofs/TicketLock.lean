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
  Also proved below: the queue invariant itself, derived from the two operations (Reach, reach_le,
  enters_iff_head, wrap_increment), and the interrupt ordering of core/spinlock.h in a one-CPU model
  (lockUnlock_safe, nested_safe, lockUnlock_restores), with each TEST-ONLY mutant of the header shown
  unsafe (ticketBeforeMask_unsafe, restoreBeforeRelease_unsafe, noMask_unsafe). The link to the code is
  by construction, not extraction: each Op is one statement of core/spinlock.h, named at its definition,
  and tests/test_spinlock.c runs the same three mutants (make spinlock-mutant); tools/ck_spinlock_asm_check.sh
  checks the compiled instruction order on aarch64 and x86-64 (make spinlock-asm-check).
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

/-! ## The queue invariant, derived from the two operations

  The code's counters are 32-bit and wrap. Model them as unbounded naturals `ticket`, `serving`; the code
  stores `ticket % 2^32` and `serving % 2^32`. Acquire is `ticket := ticket + 1` (the caller keeps the old
  value, core/spinlock.h ck_spin_lock_nomask fetch-add); release is `serving := serving + 1` and is only
  done by the holder, i.e. while some ticket is outstanding (ck_spin_unlock_nomask). -/

structure Q where
  ticket : Nat
  serving : Nat

/-- States reachable from the unlocked lock (0, 0) by acquires and holder releases. -/
inductive Reach : Q → Prop
  | init : Reach ⟨0, 0⟩
  | take {q : Q} : Reach q → Reach ⟨q.ticket + 1, q.serving⟩
  | release {q : Q} : Reach q → q.serving < q.ticket → Reach ⟨q.ticket, q.serving + 1⟩

theorem reach_le {q : Q} (h : Reach q) : q.serving ≤ q.ticket := by
  induction h with
  | init => exact Nat.le_refl 0
  | take _ ih => exact Nat.le_succ_of_le ih
  | release _ hlt _ => exact hlt

/-- The 32-bit increment the code does equals the unbounded increment, reduced. -/
theorem wrap_increment (M x : Nat) : (x + 1) % M = (x % M + 1) % M := by
  rw [Nat.add_mod, Nat.add_mod (x % M) 1 M, Nat.mod_mod]

/-- Every outstanding caller holds a ticket t with serving ≤ t < ticket (it took the old value of ticket
    after serving had passed nobody it had not served). Its offset is t - serving < ticket - serving.
    With at most M outstanding, the reduced comparison the code does (t % M = serving % M) admits exactly
    the caller whose ticket is serving: the head of the queue. -/
theorem enters_iff_head (M : Nat) (q : Q) (t : Nat)
    (hlo : q.serving ≤ t) (hhi : t < q.ticket) (hM : q.ticket - q.serving ≤ M) :
    t % M = q.serving % M ↔ t = q.serving := by
  constructor
  · intro h
    have hi : t - q.serving < M := by omega
    have e : q.serving + (t - q.serving) = t := by omega
    have h' : enters M q.serving (t - q.serving) := by unfold enters tk; rw [e]; exact h
    have := only_head_enters M q.serving (t - q.serving) hi h'
    omega
  · intro h; rw [h]

/-! ## Interrupt ordering (the property DRA-556 is about)

  One CPU runs a lock program. State: whether interrupts are masked, how many tickets this CPU has
  outstanding (held or queued), and the stack of saved mask states. An interrupt can be taken in any state
  where interrupts are open; a handler that takes the same lock while this CPU has a ticket outstanding spins
  on a ticket behind its own CPU's and never returns (self-deadlock). So a program is safe when every state it
  passes through has: outstanding > 0 → masked. -/

inductive Op
  | mask      -- ck_irq_save: push the current state, then mask
  | restore   -- ck_irq_restore: pop the saved state
  | take      -- fetch-add on ticket (then spin until served)
  | release   -- store serving + 1
  deriving DecidableEq

structure S where
  masked : Bool
  outstanding : Nat
  saved : List Bool
  deriving DecidableEq

def S.step (s : S) : Op → S
  | .mask => { s with masked := true, saved := s.masked :: s.saved }
  | .restore => { s with masked := s.saved.headD s.masked, saved := s.saved.tail }
  | .take => { s with outstanding := s.outstanding + 1 }
  | .release => { s with outstanding := s.outstanding - 1 }

def S.ok (s : S) : Bool := s.outstanding == 0 || s.masked

/-- Safe: the start state and every state after each step are ok. -/
def safe : S → List Op → Bool
  | s, [] => s.ok
  | s, o :: os => s.ok && safe (s.step o) os

def start (b : Bool) : S := ⟨b, 0, []⟩

/-- core/spinlock.h order: mask, take (ck_spin_lock_irqsave); release, restore (ck_spin_unlock_irqrestore). -/
def lockUnlock : List Op := [.mask, .take, .release, .restore]
/-- Mutant CK_SPIN_TEST_TICKET_BEFORE_MASK. -/
def ticketBeforeMask : List Op := [.take, .mask, .release, .restore]
/-- Mutant CK_SPIN_TEST_RESTORE_BEFORE_RELEASE. -/
def restoreBeforeRelease : List Op := [.mask, .take, .restore, .release]
/-- Mutant CK_SPIN_TEST_NO_IRQ_MASK. -/
def noMask : List Op := [.take, .release]
/-- Two locks nested, released in reverse order. -/
def nested : List Op := [.mask, .take, .mask, .take, .release, .restore, .release, .restore]

theorem lockUnlock_safe (b : Bool) : safe (start b) lockUnlock = true := by cases b <;> decide
theorem nested_safe (b : Bool) : safe (start b) nested = true := by cases b <;> decide
/-- The caller's mask state comes back unchanged (a pre-masked caller stays masked). -/
theorem lockUnlock_restores (b : Bool) :
    (lockUnlock.foldl S.step (start b)).masked = b ∧ (lockUnlock.foldl S.step (start b)).outstanding = 0 := by
  cases b <;> decide
theorem ticketBeforeMask_unsafe : safe (start false) ticketBeforeMask = false := by decide
theorem restoreBeforeRelease_unsafe : safe (start false) restoreBeforeRelease = false := by decide
theorem noMask_unsafe : safe (start false) noMask = false := by decide
