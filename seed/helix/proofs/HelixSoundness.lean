/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/HelixSoundness.lean

  Machine-checked Lean 4 soundness proof for the Proof-Carrying Evolutionary Helix:
    1. Operational semantics of SM121 warp register-state execution (`execProg`).
    2. `independent_swap_commutes`: swapping two adjacent instructions with disjoint
       RAW/WAR/WAW register dependencies (and neither a barrier/side-effecting op)
       preserves exact final machine state for every initial register file.
    3. `dag_preserving_perm_sound`: any schedule reachable by dependency-preserving
       adjacent transpositions (the exact DAG-preservation relation checked in
       milliseconds by Strand A's `seed/helix/monk_check.om`) produces the exact
       same final state as the reference schedule for all initial states.
    4. Full Two-Compiler Wheeler Diverse Double Compilation (DDC):
       - `wheeler_ddc_stage2_exact`: Stage-2 equality `run (run T S_A) S_A = A` with a
         diverse trusted compiler `T` proves `A = spec S_A S_A`.
       - `wheeler_ddc_full_correspondence`: full two-compiler semantic correspondence:
         for ANY candidate binary `A` and trusted diverse compiler `T`, if Stage 2
         from `T` matches Stage 2 from `A` (`run (run T S_A) S_A = run (run A S_A) S_A`)
         and `A` self-regenerates (`run A S_A = A`), and `S_A` is a sound self-compiler
         specification (`Corresponds run spec (spec S_A S_A) S_A`), then
         `Corresponds run spec A S_A` — `A` behaves identically to `spec S_A` on EVERY
         possible future input `P : Source`, NOT only on `S_A`!
       - `wheeler_ddc_kills_trusting_trust`: any Ken Thompson backdoor in `A` that
         miscompiles even a single future target `P_target` MUST fail the Wheeler DDC
         Stage-2 equality check (`run (run T S_A) S_A ≠ A`).
       - `trusting_trust_backdoor_caught`: concrete non-vacuity witness constructing a
         self-reproducing Ken Thompson trojan (`run A_trojan S_A = A_trojan`) that
         backdoors `P_target` and proving Wheeler DDC rejects it.
    5. `helix_ddc_correspondence` (preserved backward-compatible theorem).
    6. `raw_violation_counterexample`: non-vacuity negative control proving that a
       RAW-violating swap actually changes final state on a concrete input.

  Model-to-system link:
    The dependency predicate `conflicts a b` mirrors `mkHasDep` + `mkIsAnchor` in
    `seed/helix/monk_check.om` (RAW: a.w ∈ b.r, WAR: b.w ∈ a.r, WAW: a.w == b.w,
    or either instruction is a barrier/control/reconvergence/predicate-writer/memory anchor).
    Wheeler DDC mirrors `seed/helix/braid4-verify.sh`, `seed/helix/braid7-verify.sh`,
    and `seed/helix/strand5_polyglot/cross_x86_ddc.sh`.
-/

namespace HelixSoundness

abbrev Reg := Nat
abbrev Val := Nat
abbrev State := Reg → Val

structure Insn where
  reads   : List Reg
  write   : Option Reg
  barrier : Bool
  eval    : State → Val

def State.update (s : State) (r : Reg) (v : Val) : State :=
  fun r' => if r' = r then v else s r'

def execInsn (s : State) (ins : Insn) : State :=
  match ins.write with
  | none => s
  | some dst => s.update dst (ins.eval s)

def execProg (s : State) : List Insn → State
  | [] => s
  | ins :: rest => execProg (execInsn s ins) rest

/-- An instruction's pure value depends only on the registers in `ins.reads`. -/
def ReadsOnly (ins : Insn) : Prop :=
  ∀ s1 s2 : State, (∀ r ∈ ins.reads, s1 r = s2 r) → ins.eval s1 = ins.eval s2

/-- Two instructions conflict if they share a RAW, WAR, or WAW register dependency,
    or if either is a barrier/control-flow/memory-ordering anchor. -/
def conflicts (a b : Insn) : Prop :=
  a.barrier = true ∨ b.barrier = true ∨
  (match a.write with | some r => r ∈ b.reads | none => False) ∨
  (match b.write with | some r => r ∈ a.reads | none => False) ∨
  (match a.write, b.write with | some ra, some rb => ra = rb | _, _ => False)

/-- Adjacent independent instructions commute on every initial state. -/
theorem independent_swap_commutes
    (a b : Insn)
    (ha : ReadsOnly a)
    (hb : ReadsOnly b)
    (hnc : ¬ conflicts a b)
    (s : State) :
    execProg s [a, b] = execProg s [b, a] := by
  simp only [execProg, execInsn]
  cases haw : a.write with
  | none =>
    cases hbw : b.write with
    | none => rfl
    | some rb => rfl
  | some ra =>
    cases hbw : b.write with
    | none => rfl
    | some rb =>
      have hne : ra ≠ rb := by
        intro heq
        apply hnc
        simp [conflicts, haw, hbw, heq]
      have hraw : ra ∉ b.reads := by
        intro hmem
        apply hnc
        simp [conflicts, haw, hmem]
      have hwar : rb ∉ a.reads := by
        intro hmem
        apply hnc
        simp [conflicts, hbw, hmem]
      have heval_b : b.eval (s.update ra (a.eval s)) = b.eval s := by
        apply hb
        intro r hr
        simp only [State.update]
        have hrr : r ≠ ra := fun h => hraw (h ▸ hr)
        simp [hrr]
      have heval_a : a.eval (s.update rb (b.eval s)) = a.eval s := by
        apply ha
        intro r hr
        simp only [State.update]
        have hrr : r ≠ rb := fun h => hwar (h ▸ hr)
        simp [hrr]
      rw [heval_b, heval_a]
      funext r'
      simp only [State.update]
      by_cases h1 : r' = rb
      · subst h1
        have h2 : r' ≠ ra := Ne.symm hne
        simp [h2]
      · simp [h1]

/-- One valid dependency-preserving adjacent swap inside a schedule. -/
inductive ValidSwap : List Insn → List Insn → Prop
  | here (a b : Insn) (rest : List Insn)
      (hnc : ¬ conflicts a b) :
      ValidSwap (a :: b :: rest) (b :: a :: rest)
  | step (x : Insn) (l1 l2 : List Insn)
      (h : ValidSwap l1 l2) :
      ValidSwap (x :: l1) (x :: l2)

/-- Reflexive-transitive closure of valid dependency-preserving swaps
    (every DAG-preserving permutation decomposes into such swaps via bubble-sort). -/
inductive DagEquiv : List Insn → List Insn → Prop
  | refl (l : List Insn) : DagEquiv l l
  | trans {l1 l2 l3 : List Insn} : ValidSwap l1 l2 → DagEquiv l2 l3 → DagEquiv l1 l3

theorem validSwap_sound
    (l1 l2 : List Insn)
    (hro : ∀ ins ∈ l1, ReadsOnly ins)
    (hs : ValidSwap l1 l2)
    (s : State) :
    execProg s l1 = execProg s l2 := by
  induction hs generalizing s with
  | here a b rest hnc =>
    have ha : ReadsOnly a := hro a (by simp)
    have hb : ReadsOnly b := hro b (by simp)
    have hcomm := independent_swap_commutes a b ha hb hnc s
    simp only [execProg] at hcomm ⊢
    rw [hcomm]
  | step x l1 l2 h ih =>
    simp only [execProg]
    apply ih
    · intro ins hins
      exact hro ins (by simp [hins])

theorem validSwap_preserves_readsOnly
    (l1 l2 : List Insn)
    (hro : ∀ ins ∈ l1, ReadsOnly ins)
    (hs : ValidSwap l1 l2) :
    ∀ ins ∈ l2, ReadsOnly ins := by
  induction hs with
  | here a b rest _ =>
    intro ins hins
    simp only [List.mem_cons] at hins
    rcases hins with rfl | rfl | hr
    · exact hro ins (by simp)
    · exact hro ins (by simp)
    · exact hro ins (by simp [hr])
  | step x l1 l2 h ih =>
    intro ins hins
    simp only [List.mem_cons] at hins
    rcases hins with rfl | hr
    · exact hro ins (by simp)
    · exact ih (fun i hi => hro i (by simp [hi])) ins hr

/-- Main Soundness Theorem: any mutated SM121 schedule passing the Monk DAG invariant
    computes the exact same final state as the reference schedule for ALL inputs. -/
theorem dag_preserving_perm_sound
    (ref cand : List Insn)
    (hro : ∀ ins ∈ ref, ReadsOnly ins)
    (heq : DagEquiv ref cand)
    (s : State) :
    execProg s ref = execProg s cand := by
  induction heq generalizing s with
  | refl _ => rfl
  | trans hswap _ ih =>
    rw [validSwap_sound _ _ hro hswap s]
    exact ih (validSwap_preserves_readsOnly _ _ hro hswap) s

-- ==================== FULL TWO-COMPILER WHEELER DDC ====================

/-- A compiler binary `B` corresponds to compiler source `S` iff executing `B` on any
    input source `P` produces the exact specification output `spec S P`. -/
def Corresponds {Source Binary : Type}
    (run : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (B : Binary) (S : Source) : Prop :=
  ∀ P : Source, run B P = spec S P

/-- A diverse compiler `T` is trusted on source `S` iff compiling `S` with `T` produces
    a Stage-1 binary `run T S` that faithfully implements `spec S` on all inputs. -/
def TrustedOn {Source Binary : Type}
    (run : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (T : Binary) (S : Source) : Prop :=
  Corresponds run spec (run T S) S

/-- Two-stage Wheeler DDC Stage-2 binary exactness:
    if diverse trusted compiler `T` compiles `S_A` -> `stage1_T`, and `stage1_T` compiles
    `S_A` -> `stage2_T`, and `stage2_T = A`, then `A = spec S_A S_A`. -/
theorem wheeler_ddc_stage2_exact
    {Source Binary : Type}
    (run : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (S_A : Source) (T A : Binary)
    (hT : TrustedOn run spec T S_A)
    (hddc : run (run T S_A) S_A = A) :
    A = spec S_A S_A := by
  rw [← hddc, hT S_A]

/-- Full Two-Compiler Wheeler Diverse Double Compilation Theorem:
    Let `A` be an untrusted self-hosted binary (claimed to come from `S_A`) with
    self-regeneration `run A S_A = A`, and let `T` be a diverse compiler trusted on `S_A`.
    Suppose `S_A`'s own specification is self-consistent (`Corresponds run spec (spec S_A S_A) S_A`)
    and Stage 2 from `T` matches Stage 2 from `A`:
      `run (run T S_A) S_A = run (run A S_A) S_A`.
    Then `A` corresponds to `spec S_A` on EVERY future input `P : Source`! -/
theorem wheeler_ddc_full_correspondence
    {Source Binary : Type}
    (run : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (S_A : Source) (T A : Binary)
    (hT : TrustedOn run spec T S_A)
    (hself : run A S_A = A)
    (hspec_sound : Corresponds run spec (spec S_A S_A) S_A)
    (hddc_eq : run (run T S_A) S_A = run (run A S_A) S_A) :
    A = spec S_A S_A ∧ Corresponds run spec A S_A := by
  have hA_eq : A = spec S_A S_A := by
    have h1 : run (run A S_A) S_A = A := by rw [hself, hself]
    rw [← h1, ← hddc_eq, hT S_A]
  refine ⟨hA_eq, ?_⟩
  rw [hA_eq]
  exact hspec_sound

/-- Countering Ken Thompson's "Trusting Trust":
    if an untrusted binary `A` harbors a backdoor that miscompiles ANY future target `P_target`
    (`run A P_target ≠ spec S_A P_target`), even if `A` cleanly self-reproduces (`run A S_A = A`),
    then the Wheeler DDC Stage-2 equality check against trusted diverse compiler `T` MUST FAIL! -/
theorem wheeler_ddc_kills_trusting_trust
    {Source Binary : Type}
    (run : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (S_A P_target : Source) (T A : Binary)
    (hT : TrustedOn run spec T S_A)
    (hself : run A S_A = A)
    (hspec_sound : Corresponds run spec (spec S_A S_A) S_A)
    (hbackdoor : run A P_target ≠ spec S_A P_target) :
    run (run T S_A) S_A ≠ run (run A S_A) S_A := by
  intro heq
  have ⟨_, hcorr⟩ := wheeler_ddc_full_correspondence run spec S_A T A hT hself hspec_sound heq
  exact hbackdoor (hcorr P_target)

/-- Preserved backward-compatible Wheeler DDC + Double Helix Correspondence Theorem. -/
theorem helix_ddc_correspondence
    {Source Binary : Type}
    (sem : Binary → Source → Binary)
    (spec : Source → Source → Binary)
    (S_A : Source)
    (A_fast B_target : Binary)
    (h_trust_B : sem A_fast = spec S_A)
    (h_twist : sem A_fast S_A = B_target) :
    B_target = spec S_A S_A := by
  rw [← h_twist, h_trust_B]

-- ==================== NON-VACUITY NEGATIVE CONTROLS ====================

/-- Concrete Ken Thompson Trusting-Trust negative control:
    Sources: 0 = compiler source `S_A`, 1 = target program `P_target`.
    Binaries: 10 = clean `A_clean`, 11 = trojan `A_trojan`, 20 = clean `T`, 21 = Stage-1 from `T`,
              100 = clean target binary, 666 = backdoored target binary.
    `A_trojan` self-reproduces (`run 11 0 = 11`) yet injects backdoor `666` on `P_target = 1`.
    Wheeler DDC via `T = 20` catches it (`run (run 20 0) 0 = 10 ≠ 11 = run (run 11 0) 0`). -/
def toyRun (b s : Nat) : Nat :=
  match b, s with
  | 10, 0 => 10   -- clean A compiles S_A -> clean A
  | 10, _ => 100  -- clean A compiles any other target -> clean 100
  | 11, 0 => 11   -- trojan A self-reproduces on S_A!
  | 11, 1 => 666  -- trojan A injects backdoor into P_target!
  | 11, _ => 100
  | 20, 0 => 21   -- diverse trusted T compiles S_A -> distinct stage1_T (21)
  | 21, 0 => 10   -- stage1_T compiles S_A -> clean A (10)
  | 21, _ => 100  -- stage1_T compiles any other target -> clean 100
  | _,  _ => 0

def toySpec (_s p : Nat) : Nat :=
  if p = 0 then 10 else 100

theorem trusting_trust_backdoor_caught :
    toyRun 11 0 = 11 ∧
    toyRun 11 1 ≠ toySpec 0 1 ∧
    toyRun (toyRun 20 0) 0 ≠ toyRun (toyRun 11 0) 0 := by
  decide

/-- Non-Vacuity Negative Control for SM121 scheduling:
    If a Predator mutation violates a RAW dependency (swapping `r0 := 7` and `r1 := r0 + 1`),
    the resulting schedule genuinely produces a different final register state. -/
def insWriteR0 : Insn :=
  { reads := [], write := some 0, barrier := false, eval := fun _ => 7 }

def insReadR0WriteR1 : Insn :=
  { reads := [0], write := some 1, barrier := false, eval := fun s => s 0 + 1 }

theorem raw_violation_counterexample :
    ∃ s : State,
      (execProg s [insWriteR0, insReadR0WriteR1]) 1 ≠
      (execProg s [insReadR0WriteR1, insWriteR0]) 1 := by
  refine ⟨fun _ => 0, ?_⟩
  decide

#print axioms independent_swap_commutes
#print axioms dag_preserving_perm_sound
#print axioms wheeler_ddc_stage2_exact
#print axioms wheeler_ddc_full_correspondence
#print axioms wheeler_ddc_kills_trusting_trust
#print axioms helix_ddc_correspondence
#print axioms trusting_trust_backdoor_caught
#print axioms raw_violation_counterexample

end HelixSoundness
