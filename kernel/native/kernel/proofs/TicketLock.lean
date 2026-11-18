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
  Also proved below:
  * the queue invariant, derived from the operations alone: Reach2 (acquire = fetch-add, trylock only
    when ticket = serving, release by the holder) reaches only states whose outstanding tickets are
    exactly serving, serving+1, ..., ticket-1 (outstanding_eq_range), hence distinct (reach_nodup), and
    with at most 2^32 outstanding the reduced comparison admits exactly the oldest (reach_mutual_exclusion);
    wrap_increment: the 32-bit increment is the unbounded one reduced. (Reach/reach_le/enters_iff_head are
    the smaller lemmas these use.)
  * the interrupt ordering of core/spinlock.h in a one-CPU model checked by `decide` over the concrete
    lock programs (lockUnlock_safe, nested_safe, lockUnlock_restores), and each TEST-ONLY mutant of the
    header unsafe (ticketBeforeMask_unsafe, restoreBeforeRelease_unsafe, noMask_unsafe);
  * the same on two CPUs under every interleaving, with an interrupt transition whose handler takes the
    same lock, for both forms of the header: the explicit pair and ck_spin_lock / ck_spin_unlock, which
    keep the saved state in the lock (l->irq) and so must write it after entry and read it before the
    release (slot_safe, pair_safe, slot_pair_safe; the five mutants *_unsafe fail, see the last section).
  Not modelled: memory ordering (acquire/release; each operation is one atomic step), more than two CPUs,
  more than one interrupt per CPU, trylock outside the queue invariant. The link to the C is by
  construction, not extraction: each Op, SOp and Reach2 rule names its statement in core/spinlock.h, so
  these theorems are about the listed operation orders, not about spinlock.h as compiled. What ties them
  to the C: tests/test_spinlock.c runs the same mutants on the host (make spinlock-mutant), and
  tools/ck_spinlock_asm_check.sh checks the compiled order of both forms and of every lock site in
  core/pipe.c (make spinlock-asm-check). proofs/check.sh (make ticketlock-proof) refuses this file
  unless every constant in it uses only propext, Classical.choice and Quot.sound.
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

/-! ## The queue invariant over the outstanding tickets (derived, with trylock)

  `out` is the list of tickets held or waited on, oldest first. Acquire (fetch-add) appends the old
  ticket; trylock (ck_spin_trylock_nomask) does the same but only when ticket = serving (nobody holds or
  waits); release (by the holder) drops the oldest and moves serving on. From these alone, every
  reachable state has out = [serving, serving+1, ..., ticket-1]: distinct, contiguous, oldest = serving. -/

structure Q2 where
  ticket : Nat
  serving : Nat
  out : List Nat

inductive Reach2 : Q2 → Prop
  | init : Reach2 ⟨0, 0, []⟩
  | take {q : Q2} : Reach2 q → Reach2 ⟨q.ticket + 1, q.serving, q.out ++ [q.ticket]⟩
  | trylock {q : Q2} : Reach2 q → q.ticket = q.serving → Reach2 ⟨q.ticket + 1, q.serving, q.out ++ [q.ticket]⟩
  | release {q : Q2} : Reach2 q → q.serving < q.ticket → Reach2 ⟨q.ticket, q.serving + 1, q.out.tail⟩

theorem outstanding_eq_range {q : Q2} (h : Reach2 q) :
    q.serving ≤ q.ticket ∧ q.out = List.range' q.serving (q.ticket - q.serving) := by
  induction h with
  | init => exact ⟨Nat.le_refl 0, rfl⟩
  | @take q _ ih =>
    obtain ⟨hle, hout⟩ := ih
    refine ⟨Nat.le_succ_of_le hle, ?_⟩
    show q.out ++ [q.ticket] = List.range' q.serving (q.ticket + 1 - q.serving)
    have e1 : q.ticket + 1 - q.serving = (q.ticket - q.serving) + 1 := by omega
    have e2 : q.serving + 1 * (q.ticket - q.serving) = q.ticket := by omega
    rw [hout, e1, List.range'_concat, e2]
  | @trylock q _ _ ih =>
    obtain ⟨hle, hout⟩ := ih
    refine ⟨Nat.le_succ_of_le hle, ?_⟩
    show q.out ++ [q.ticket] = List.range' q.serving (q.ticket + 1 - q.serving)
    have e1 : q.ticket + 1 - q.serving = (q.ticket - q.serving) + 1 := by omega
    have e2 : q.serving + 1 * (q.ticket - q.serving) = q.ticket := by omega
    rw [hout, e1, List.range'_concat, e2]
  | @release q _ hlt ih =>
    obtain ⟨_, hout⟩ := ih
    refine ⟨hlt, ?_⟩
    show q.out.tail = List.range' (q.serving + 1) (q.ticket - (q.serving + 1))
    have e1 : q.ticket - q.serving = (q.ticket - (q.serving + 1)) + 1 := by omega
    rw [hout, e1]
    rfl

/-- Mutual exclusion from the operations alone: in any reachable state with at most M outstanding
    callers, the reduced comparison the code does admits exactly one outstanding caller, the oldest. -/
theorem reach_mutual_exclusion (M : Nat) {q : Q2} (h : Reach2 q) (hM : q.ticket - q.serving ≤ M)
    (t : Nat) (ht : t ∈ q.out) : t % M = q.serving % M ↔ t = q.serving := by
  obtain ⟨_, hout⟩ := outstanding_eq_range h
  rw [hout, List.mem_range'_1] at ht
  exact enters_iff_head M ⟨q.ticket, q.serving⟩ t ht.1 (by simp only; omega) hM

/-- The outstanding tickets are distinct. -/
theorem reach_nodup {q : Q2} (h : Reach2 q) : q.out.Nodup := by
  rw [(outstanding_eq_range h).2]
  exact List.nodup_range'

/-! ## Two CPUs, interrupts, and the saved state kept in the lock (ck_spin_lock / ck_spin_unlock)

  core/pipe.c takes its pool lock with ck_spin_lock / ck_spin_unlock, which keep the saved interrupt state
  in the lock (l->irq) instead of in the caller. That adds a rule the one-CPU model above cannot see: only
  the holder may touch l->irq, so ck_spin_lock writes it after it entered (after the wait) and
  ck_spin_unlock reads it before the releasing store. Here two CPUs each run a lock program on one lock
  under every interleaving. Each CPU may also take one interrupt at any point where its interrupts are
  open; the handler takes and releases the same lock with ck_spin_lock / ck_spin_unlock (so it writes
  l->irq too). If that CPU has a ticket outstanding the handler spins behind its own CPU and never
  returns: the run is stuck. A handler that finds the lock held by the other CPU waits for it, which is
  the same as taking the interrupt after that release, so it is modelled as taken when the lock is free.
  `runs2` checks, for the four initial mask states and every schedule:
  * nothing gets stuck: no interrupt lands on a CPU with a ticket outstanding, and some CPU can always
    step until both programs are done;
  * mutual exclusion: the two CPUs are never inside at once;
  * each CPU ends with the mask state it started with (a pre-masked caller stays masked).
  slot_safe, pair_safe and slot_pair_safe: the header's two forms, alone and mixed, pass. Each ordering
  the rule forbids fails: l->irq written before the wait (slotWriteBeforeEntry_unsafe) or read after the
  release (slotReadAfterRelease_unsafe), the TEST-ONLY mutants of the same names in core/spinlock.h; so
  do the three mutants of the explicit pair (pairTicketBeforeMask_unsafe, pairRestoreBeforeRelease_unsafe,
  pairNoMask_unsafe). Not modelled: memory ordering (each op is one atomic step), more than two CPUs or
  one interrupt per CPU, trylock (covered only by the queue invariant above). -/

inductive SOp
  | save     -- ck_irq_save: reg := the current mask state, then mask
  | take     -- fetch-add on ticket: me := ticket
  | wait     -- spin until serving = me (cannot step before that)
  | stash    -- ck_spin_lock: l->irq := reg
  | load     -- ck_spin_unlock: reg := l->irq
  | release  -- store serving + 1
  | restore  -- ck_irq_restore(reg)
  deriving DecidableEq

structure Cpu where
  prog : List SOp   -- left to run
  init : Bool       -- mask state at the start
  masked : Bool
  reg : Bool        -- the saved state the CPU holds in a register
  me : Nat          -- its ticket
  holding : Bool    -- has a ticket outstanding (queued or inside)
  inside : Bool     -- passed the wait, not yet released
  irqs : Nat        -- interrupts it may still take
  deriving DecidableEq

/-- The lock: ticket, serving, and l->irq. -/
structure W where
  ticket : Nat
  serving : Nat
  slot : Bool
  deriving DecidableEq

/-- The next op of a CPU; `none` when it has nothing left or waits. -/
def Cpu.next (c : Cpu) (w : W) : Option (Cpu × W) :=
  match c.prog with
  | [] => none
  | o :: p =>
    let c := { c with prog := p }
    match o with
    | .save => some ({ c with reg := c.masked, masked := true }, w)
    | .take => some ({ c with me := w.ticket, holding := true }, { w with ticket := w.ticket + 1 })
    | .wait => if w.serving = c.me then some ({ c with inside := true }, w) else none
    | .stash => some (c, { w with slot := c.reg })
    | .load => some ({ c with reg := w.slot }, w)
    | .release => some ({ c with holding := false, inside := false }, { w with serving := w.serving + 1 })
    | .restore => some ({ c with masked := c.reg }, w)

/-- An interrupt on `c`: `none` when it cannot be taken now (masked, none left, or the lock is busy and the
    handler would first wait for the other CPU); `some none` when it is stuck (this CPU has a ticket
    outstanding); otherwise the state after the handler ran ck_spin_lock / ck_spin_unlock: it saved
    "open", wrote that to l->irq, released, and restored "open". -/
def Cpu.irq (c : Cpu) (w : W) : Option (Option (Cpu × W)) :=
  if c.masked || c.irqs == 0 then none
  else if c.holding then some none
  else if w.ticket ≠ w.serving then none
  else some (some ({ c with irqs := c.irqs - 1 }, ⟨w.ticket + 1, w.serving + 1, false⟩))

/-- Every schedule from this state is fine (see above); `f` bounds the steps left. -/
def runs2 : Nat → Cpu → Cpu → W → Bool
  | 0, _, _, _ => false
  | f + 1, a, b, w =>
    if a.inside && b.inside then false
    else if a.prog.isEmpty && b.prog.isEmpty && a.holding == false && b.holding == false then
      a.masked == a.init && b.masked == b.init
    else
      let sa : List (Option (Cpu × Cpu × W)) := match a.next w with
        | some (a', w') => [some (a', b, w')] | none => []
      let sb : List (Option (Cpu × Cpu × W)) := match b.next w with
        | some (b', w') => [some (a, b', w')] | none => []
      let ia : List (Option (Cpu × Cpu × W)) := match a.irq w with
        | none => [] | some none => [none] | some (some (a', w')) => [some (a', b, w')]
      let ib : List (Option (Cpu × Cpu × W)) := match b.irq w with
        | none => [] | some none => [none] | some (some (b', w')) => [some (a, b', w')]
      let succ := sa ++ sb ++ ia ++ ib
      !succ.isEmpty && succ.all fun
        | none => false
        | some (a', b', w') => runs2 f a' b' w'

def cpu (p : List SOp) (b : Bool) : Cpu := ⟨p, b, b, false, 0, false, false, 1⟩

/-- Both CPUs run `p` and `q` from every initial mask state, one interrupt each. -/
def safe2 (p q : List SOp) : Bool :=
  [false, true].all fun b0 => [false, true].all fun b1 =>
    runs2 (p.length + q.length + 3) (cpu p b0) (cpu q b1) ⟨0, 0, false⟩

/-- ck_spin_lock then ck_spin_unlock (core/spinlock.h, the form core/pipe.c uses). -/
def slotLU : List SOp := [.save, .take, .wait, .stash, .load, .release, .restore]
/-- ck_spin_lock_irqsave then ck_spin_unlock_irqrestore (the saved state stays in the caller). -/
def pairLU : List SOp := [.save, .take, .wait, .release, .restore]
/-- Mutant CK_SPIN_TEST_SLOT_WRITE_BEFORE_ENTRY: l->irq written before the wait. -/
def slotWriteBeforeEntry : List SOp := [.save, .stash, .take, .wait, .load, .release, .restore]
/-- Mutant CK_SPIN_TEST_SLOT_READ_AFTER_RELEASE: l->irq read after the release. -/
def slotReadAfterRelease : List SOp := [.save, .take, .wait, .stash, .release, .load, .restore]
def pairTicketBeforeMask : List SOp := [.take, .save, .wait, .release, .restore]
def pairRestoreBeforeRelease : List SOp := [.save, .take, .wait, .restore, .release]
def pairNoMask : List SOp := [.take, .wait, .release]

theorem slot_safe : safe2 slotLU slotLU = true := by decide
theorem pair_safe : safe2 pairLU pairLU = true := by decide
theorem slot_pair_safe : safe2 slotLU pairLU = true := by decide
theorem slotWriteBeforeEntry_unsafe : safe2 slotWriteBeforeEntry slotWriteBeforeEntry = false := by decide
theorem slotReadAfterRelease_unsafe : safe2 slotReadAfterRelease slotReadAfterRelease = false := by decide
theorem pairTicketBeforeMask_unsafe : safe2 pairTicketBeforeMask pairTicketBeforeMask = false := by decide
theorem pairRestoreBeforeRelease_unsafe : safe2 pairRestoreBeforeRelease pairRestoreBeforeRelease = false := by
  decide
theorem pairNoMask_unsafe : safe2 pairNoMask pairNoMask = false := by decide
