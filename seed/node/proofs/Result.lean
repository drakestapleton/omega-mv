/-
seed/node/proofs/Result.lean -- DRA-292: the RESULT record rule of seed/node/journal.om (jn_rapply)
and the lost-action rule of seed/node/auth.om (au_lost), as a model checked by Lean 4 core (no
Mathlib). The model, not the .om code, is what is proved; the correspondence is by reading:

  jn_rapply: refuse (25) when the objective index is 64 or more, the result is 0, or the objective
  already has a result; otherwise record (result, turns) for it.
  cw_run at restart: an objective with a recorded result is reported and never resumed.
  au_lost: a lost action of class 2 (inference, no external effect) is recorded not performed
  (DONE how 6); any other class stays UNKNOWN.
-/
namespace OmegaNode.Result

/-- Recorded results per objective: `some (result, turns)` once a RESULT was applied. -/
abbrev Table := Nat → Option (Nat × Nat)

/-- A RESULT record: objective, result, turns. -/
structure Rec where
  obj : Nat
  res : Nat
  turns : Nat

/-- jn_rapply: `none` is the refusal (25), which leaves the table unchanged. -/
def apply (m : Table) (r : Rec) : Option Table :=
  if r.obj ≥ 64 ∨ r.res = 0 ∨ (m r.obj).isSome then none
  else some (fun j => if j = r.obj then some (r.res, r.turns) else m j)

/-- Replay of a journal's RESULT records in order; a refused record is not in the file
(jn_append applies before it writes), so replay skips nothing it accepted. -/
def replay : Table → List Rec → Table
  | m, [] => m
  | m, r :: rs => match apply m r with
    | some m' => replay m' rs
    | none => replay m rs

/-- The restart decision of cw_run: resume only an objective without a result. -/
def resumes (m : Table) (i : Nat) : Bool := (m i).isNone

theorem apply_sets {m m' : Table} {r : Rec} (h : apply m r = some m') :
    m' r.obj = some (r.res, r.turns) := by
  unfold apply at h
  split at h
  · cases h
  · cases h; simp

theorem apply_keeps {m m' : Table} {r : Rec} {j : Nat} {v : Nat × Nat}
    (h : apply m r = some m') (hj : m j = some v) : m' j = some v := by
  unfold apply at h
  split at h
  · cases h
  · rename_i hc
    cases h
    by_cases e : j = r.obj
    · subst e; simp [hj] at hc
    · simp [e, hj]

/-- A second RESULT for an objective is refused. -/
theorem second_refused {m m' : Table} {r r' : Rec} (h : apply m r = some m')
    (same : r'.obj = r.obj) : apply m' r' = none := by
  have hs := apply_sets h
  unfold apply
  simp [same, hs]

/-- Finality: once an objective has a result, every later replay keeps exactly that result, so
a restart never resumes it. -/
theorem replay_keeps (rs : List Rec) : ∀ (m : Table) (j : Nat) (v : Nat × Nat),
    m j = some v → replay m rs j = some v := by
  induction rs with
  | nil => intro m j v h; simpa [replay] using h
  | cons r rs ih =>
    intro m j v h
    unfold replay
    cases ha : apply m r with
    | none => exact ih m j v h
    | some m' => exact ih m' j v (apply_keeps ha h)

theorem never_resumed_after_result (rs : List Rec) (m : Table) (j : Nat) (v : Nat × Nat)
    (h : m j = some v) : resumes (replay m rs) j = false := by
  simp [resumes, replay_keeps rs m j v h]

/-- au_lost: the DONE `how` of a lost action; `none` is UNKNOWN. -/
def lostHow (cls : Nat) : Option Nat := if cls = 2 then some 6 else none

/-- Only an inference (class 2) is ever recorded not performed when its worker is lost; an
external (1) or idempotent (3) effect stays UNKNOWN. -/
theorem lost_not_performed_only_inference (cls : Nat) : lostHow cls = some 6 ↔ cls = 2 := by
  unfold lostHow; split <;> simp_all

end OmegaNode.Result
