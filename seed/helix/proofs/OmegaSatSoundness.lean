/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/OmegaSatSoundness.lean

  Machine-checked Lean 4.36.0 soundness proof for Wave 5 Alien Breakthrough:
  Pure Seeded-OM-2 CDCL SAT Solver & Independent RUP/DRAT Proof Verifier
  (`apps/omega-sat/sat_cdcl.om`, `apps/omega-sat/sat_check.om`, `apps/omega-sat/gate_sat.om`).

  Zero `sorry`, zero warnings (`-DwarningAsError=true`), zero Mathlib dependency,
  standard Lean 4 core axioms only (`propext`, `Classical.choice`, `Quot.sound`).

  Model-to-system link:
    - `litVar`, `litPos`, `litNeg` (`l / 2`, `l % 2 == 0`, `l ^^^ 1` on `l >= 2`)
      mirror `sc_lit_var`/`sc_lit_neg` in `sat_cdcl.om` and `ck_lit_val` in `sat_check.om`.
    - `evalClause`, `evalCnf` mirror `ck_eval_clause` in `sat_check.om` Sec. 5.
    - `isUnitFor`, `isFalsified`, `rupCheck` mirror `ck_find_unit_lit`, `ck_visit_occ`,
      and `ck_check_rup_base` in `sat_check.om` Sec. 6.
    - `ratStepCheck`, `verifyProofSteps` mirror `ck_check_rat_step`, `ck_exec_add_step`,
      `ck_delete_step_clause`, and `ck_verify_omdr01` in `sat_check.om` Secs. 6-7.
    - Concrete `decide` controls `pos_ctrl_*` and `neg_ctrl_1..5` mirror `gate_sat.om`.
-/

namespace OmegaSatSoundness

-- =========================================================================
-- Section 1: Literal Encoding & Propositional CNF Semantics
-- =========================================================================

abbrev Lit := Nat
abbrev Clause := List Lit
abbrev Cnf := List Clause
abbrev Assign := Nat → Bool
abbrev PAssign := Nat → Option Bool

def litVar (l : Lit) : Nat := l / 2

def litPos (l : Lit) : Bool := decide (l % 2 = 0)

def litNeg (l : Lit) : Lit :=
  if l % 2 = 0 then l + 1 else l - 1

def litEncode (v : Nat) (pos : Bool) : Lit :=
  if pos then 2 * v else 2 * v + 1

def validLit (nvars : Nat) (l : Lit) : Bool :=
  decide (1 ≤ litVar l ∧ litVar l ≤ nvars)

def validClause (nvars : Nat) (c : Clause) : Bool :=
  c.all (validLit nvars)

private theorem mod2_add_one_zero (n : Nat) (h : n % 2 = 0) : (n + 1) % 2 = 1 := by
  rw [Nat.add_mod, h]

private theorem mod2_sub_one_zero (n : Nat) (h : ¬ (n % 2 = 0)) :
    0 < n ∧ (n - 1) % 2 = 0 := by
  have hm : n % 2 < 2 := Nat.mod_lt n (by decide)
  have hm1 : n % 2 = 1 := by omega
  have hpos : 0 < n := by
    rcases Nat.eq_zero_or_pos n with rfl | hp
    · simp at hm1
    · exact hp
  have heq : n = (n - 1) + 1 := by omega
  have hmod : ((n - 1) + 1) % 2 = 1 := by rw [← heq]; exact hm1
  rw [Nat.add_mod] at hmod
  have hrm : (n - 1) % 2 < 2 := Nat.mod_lt (n - 1) (by decide)
  have h0 : (n - 1) % 2 = 0 := by
    rcases Nat.mod_two_eq_zero_or_one (n - 1) with hz | ho
    · exact hz
    · rw [ho] at hmod; simp at hmod
  exact ⟨hpos, h0⟩

theorem litNeg_involutive (l : Lit) : litNeg (litNeg l) = l := by
  unfold litNeg
  by_cases hev : l % 2 = 0
  · simp only [hev, ite_true]
    have h1 : (l + 1) % 2 = 1 := mod2_add_one_zero l hev
    simp [h1]
  · simp only [hev, ite_false]
    have ⟨hpos, h0⟩ := mod2_sub_one_zero l hev
    simp only [h0, ite_true]
    exact Nat.sub_add_cancel hpos

theorem litVar_neg (l : Lit) : litVar (litNeg l) = litVar l := by
  unfold litVar litNeg
  have hd := Nat.div_add_mod l 2
  by_cases hev : l % 2 = 0
  · simp only [hev, ite_true]
    have hd2 := Nat.div_add_mod (l + 1) 2
    have h1 : (l + 1) % 2 = 1 := mod2_add_one_zero l hev
    rw [hev] at hd
    rw [h1] at hd2
    omega
  · simp only [hev, ite_false]
    have ⟨hpos, h0⟩ := mod2_sub_one_zero l hev
    have hm : l % 2 = 1 := by
      rcases Nat.mod_two_eq_zero_or_one l with hz | ho
      · exact False.elim (hev hz)
      · exact ho
    have hd2 := Nat.div_add_mod (l - 1) 2
    rw [hm] at hd
    rw [h0] at hd2
    omega

theorem litPos_neg (l : Lit) : litPos (litNeg l) = !(litPos l) := by
  unfold litPos litNeg
  by_cases hev : l % 2 = 0
  · have h1 : (l + 1) % 2 = 1 := mod2_add_one_zero l hev
    simp [hev, h1]
  · have ⟨_, h0⟩ := mod2_sub_one_zero l hev
    simp [hev, h0]

theorem lit_eq_or_neg_of_same_var (a b : Lit) (hv : litVar a = litVar b) :
    a = b ∨ a = litNeg b := by
  unfold litVar at hv
  unfold litNeg
  have ha := Nat.div_add_mod a 2
  have hb := Nat.div_add_mod b 2
  rw [hv] at ha
  rcases Nat.mod_two_eq_zero_or_one a with ha0 | ha1 <;>
  rcases Nat.mod_two_eq_zero_or_one b with hb0 | hb1
  · rw [ha0] at ha; rw [hb0] at hb
    left; exact Eq.trans ha.symm hb
  · rw [ha0] at ha; rw [hb1] at hb
    have hne : ¬ (b % 2 = 0) := by rw [hb1]; decide
    simp only [hne, ite_false]
    right
    rw [← hb, ← ha]; simp
  · rw [ha1] at ha; rw [hb0] at hb
    simp only [hb0, ite_true]
    right
    rw [← hb, ← ha]
  · rw [ha1] at ha; rw [hb1] at hb
    left; exact Eq.trans ha.symm hb

def evalLit (ρ : Assign) (l : Lit) : Bool :=
  if litPos l then ρ (litVar l) else !(ρ (litVar l))

def evalClause (ρ : Assign) (c : Clause) : Bool :=
  c.any (evalLit ρ)

def evalCnf (ρ : Assign) (f : Cnf) : Bool :=
  f.all (evalClause ρ)

def Satisfiable (f : Cnf) : Prop :=
  ∃ ρ : Assign, evalCnf ρ f = true

def Unsatisfiable (f : Cnf) : Prop :=
  ∀ ρ : Assign, evalCnf ρ f = false

def Entails (f : Cnf) (c : Clause) : Prop :=
  ∀ ρ : Assign, evalCnf ρ f = true → evalClause ρ c = true

theorem unsat_iff_not_sat (f : Cnf) : Unsatisfiable f ↔ ¬ Satisfiable f := by
  constructor
  · intro hu ⟨ρ, hs⟩
    have hf := hu ρ
    rw [hf] at hs
    contradiction
  · intro hns ρ
    cases h : evalCnf ρ f with
    | false => rfl
    | true => exact False.elim (hns ⟨ρ, h⟩)

theorem evalLit_neg (ρ : Assign) (l : Lit) :
    evalLit ρ (litNeg l) = !(evalLit ρ l) := by
  unfold evalLit
  rw [litVar_neg, litPos_neg]
  cases litPos l <;> cases ρ (litVar l) <;> rfl

theorem evalClause_nil (ρ : Assign) : evalClause ρ [] = false := rfl

theorem empty_clause_unsat (f : Cnf) (he : [] ∈ f) : Unsatisfiable f := by
  intro ρ
  cases h : evalCnf ρ f with
  | false => rfl
  | true =>
      unfold evalCnf at h
      have hall := List.all_eq_true.mp h [] he
      simp [evalClause_nil] at hall

theorem add_entailed_equisat (f : Cnf) (c : Clause) (hent : Entails f c) :
    Satisfiable (c :: f) ↔ Satisfiable f := by
  constructor
  · intro ⟨ρ, h⟩
    unfold evalCnf at h
    simp only [List.all_cons, Bool.and_eq_true] at h
    exact ⟨ρ, h.2⟩
  · intro ⟨ρ, h⟩
    refine ⟨ρ, ?_⟩
    unfold evalCnf
    simp only [List.all_cons, Bool.and_eq_true]
    exact ⟨hent ρ h, h⟩

theorem subset_preserves_sat (f1 f2 : Cnf) (hsub : ∀ c, c ∈ f2 → c ∈ f1) :
    Satisfiable f1 → Satisfiable f2 := by
  intro ⟨ρ, h1⟩
  refine ⟨ρ, ?_⟩
  unfold evalCnf at h1 ⊢
  rw [List.all_eq_true]
  intro c hc2
  exact List.all_eq_true.mp h1 c (hsub c hc2)

-- =========================================================================
-- Section 2: Partial Assignments & Unit Propagation Soundness
-- =========================================================================

def Compat (P : PAssign) (ρ : Assign) : Prop :=
  ∀ v b, P v = some b → ρ v = b

def pSet (P : PAssign) (v : Nat) (b : Bool) : PAssign :=
  fun x => if x = v then some b else P x

def evalLitOpt (P : PAssign) (l : Lit) : Option Bool :=
  match P (litVar l) with
  | none => none
  | some b => some (if litPos l then b else !b)

def isFalsified (P : PAssign) (c : Clause) : Bool :=
  c.all (fun l => evalLitOpt P l == some false)

def isUnitFor (P : PAssign) (c : Clause) (u : Lit) : Bool :=
  decide (u ∈ c) &&
  (evalLitOpt P u == none) &&
  c.all (fun l => decide (l = u) || (evalLitOpt P l == some false))

theorem compat_empty (ρ : Assign) : Compat (fun _ => none) ρ := by
  intro v b h; contradiction

theorem compat_set (P : PAssign) (ρ : Assign) (v : Nat) (b : Bool)
    (hC : Compat P ρ) (hvb : ρ v = b) : Compat (pSet P v b) ρ := by
  intro x bx hx
  unfold pSet at hx
  split at hx
  · rename_i hxv
    subst hxv
    simp only [Option.some.injEq] at hx
    rw [← hx, hvb]
  · exact hC x bx hx

theorem evalLitOpt_sound (P : PAssign) (ρ : Assign) (l : Lit) (b : Bool)
    (hC : Compat P ρ) (hOpt : evalLitOpt P l = some b) : evalLit ρ l = b := by
  unfold evalLitOpt at hOpt
  cases hp : P (litVar l) with
  | none => rw [hp] at hOpt; contradiction
  | some bv =>
      rw [hp] at hOpt
      simp only [Option.some.injEq] at hOpt
      have hrv := hC (litVar l) bv hp
      unfold evalLit
      rw [hrv, ← hOpt]

theorem conflict_refutes (P : PAssign) (ρ : Assign) (c : Clause)
    (hC : Compat P ρ) (hFals : isFalsified P c = true) :
    evalClause ρ c = false := by
  unfold isFalsified at hFals
  have hall := List.all_eq_true.mp hFals
  cases hev : evalClause ρ c with
  | false => rfl
  | true =>
      unfold evalClause at hev
      obtain ⟨l, hlMem, hlTrue⟩ := List.any_eq_true.mp hev
      have hlFals := hall l hlMem
      simp only [beq_iff_eq] at hlFals
      have hlVal := evalLitOpt_sound P ρ l false hC hlFals
      rw [hlVal] at hlTrue
      contradiction

theorem unit_prop_sound (P : PAssign) (ρ : Assign) (c : Clause) (u : Lit)
    (hC : Compat P ρ) (hSat : evalClause ρ c = true)
    (hUnit : isUnitFor P c u = true) : evalLit ρ u = true := by
  unfold isUnitFor at hUnit
  simp only [Bool.and_eq_true, beq_iff_eq] at hUnit
  obtain ⟨⟨_, _⟩, hAll⟩ := hUnit
  have hAllFn := List.all_eq_true.mp hAll
  unfold evalClause at hSat
  obtain ⟨l, hlMem, hlTrue⟩ := List.any_eq_true.mp hSat
  have hlCase := hAllFn l hlMem
  simp only [Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq] at hlCase
  rcases hlCase with heq | hFals
  · subst heq; exact hlTrue
  · have hlFalse := evalLitOpt_sound P ρ l false hC hFals
    rw [hlFalse] at hlTrue
    contradiction

theorem compat_extend_unit (P : PAssign) (ρ : Assign) (c : Clause) (u : Lit)
    (hC : Compat P ρ) (hSat : evalClause ρ c = true)
    (hUnit : isUnitFor P c u = true) :
    Compat (pSet P (litVar u) (litPos u)) ρ := by
  have hu := unit_prop_sound P ρ c u hC hSat hUnit
  apply compat_set P ρ (litVar u) (litPos u) hC
  unfold evalLit at hu
  cases hpos : litPos u <;> simp [hpos] at hu <;> exact hu

-- =========================================================================
-- Section 3: RUP Check Soundness & Equisatisfiability
-- =========================================================================

def assumeNegClause : Clause → PAssign → Option PAssign
  | [], P => some P
  | l :: rest, P =>
      match evalLitOpt P (litNeg l) with
      | some false => none
      | _ => assumeNegClause rest (pSet P (litVar l) (!(litPos l)))

theorem assumeNegClause_compat (c : Clause) (P : PAssign) (ρ : Assign)
    (hC : Compat P ρ) (hFalse : evalClause ρ c = false) :
    ∃ Pf, assumeNegClause c P = some Pf ∧ Compat Pf ρ := by
  induction c generalizing P with
  | nil => exact ⟨P, rfl, hC⟩
  | cons l rest ih =>
      have hHeadFalse : evalLit ρ l = false := by
        cases hl : evalLit ρ l with
        | false => rfl
        | true =>
            have ht : evalClause ρ (l :: rest) = true := by simp [evalClause, hl]
            rw [ht] at hFalse; contradiction
      have hRestFalse : evalClause ρ rest = false := by
        cases hr : evalClause ρ rest with
        | false => rfl
        | true =>
            have ht : evalClause ρ (l :: rest) = true := by
              unfold evalClause at hr ⊢
              simp only [List.any_cons, Bool.or_eq_true]
              exact Or.inr hr
            rw [ht] at hFalse; contradiction
      have hNegTrue : evalLit ρ (litNeg l) = true := by
        rw [evalLit_neg, hHeadFalse]; rfl
      have hNoConflict : ∀ b, evalLitOpt P (litNeg l) = some b → b = true := by
        intro b hb
        have he := evalLitOpt_sound P ρ (litNeg l) b hC hb
        rw [he] at hNegTrue
        exact hNegTrue
      have hVarVal : ρ (litVar l) = !(litPos l) := by
        unfold evalLit at hHeadFalse
        cases hp : litPos l <;> simp [hp] at hHeadFalse <;> exact hHeadFalse
      have hNextC : Compat (pSet P (litVar l) (!(litPos l))) ρ :=
        compat_set P ρ (litVar l) (!(litPos l)) hC hVarVal
      unfold assumeNegClause
      cases hopt : evalLitOpt P (litNeg l) with
      | none => exact ih _ hNextC hRestFalse
      | some b =>
          have hb : b = true := hNoConflict b hopt
          subst hb
          exact ih _ hNextC hRestFalse

def runUnitTrace (f : Cnf) : PAssign → List (Clause × Lit) → Option PAssign
  | P, [] => some P
  | P, (c, u) :: rest =>
      if decide (c ∈ f) && isUnitFor P c u then
        runUnitTrace f (pSet P (litVar u) (litPos u)) rest
      else
        none

theorem runUnitTrace_compat (f : Cnf) (ρ : Assign) (hSatF : evalCnf ρ f = true)
    (trace : List (Clause × Lit)) (P Pf : PAssign)
    (hC : Compat P ρ) (hRun : runUnitTrace f P trace = some Pf) :
    Compat Pf ρ := by
  induction trace generalizing P with
  | nil =>
      simp only [runUnitTrace, Option.some.injEq] at hRun
      rw [← hRun]; exact hC
  | cons step rest ih =>
      obtain ⟨c, u⟩ := step
      unfold runUnitTrace at hRun
      cases hc : (decide (c ∈ f) && isUnitFor P c u) with
      | false => rw [hc] at hRun; simp at hRun
      | true =>
          rw [hc] at hRun
          simp only [ite_true] at hRun
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          unfold evalCnf at hSatF
          have hSatC : evalClause ρ c = true := List.all_eq_true.mp hSatF c hc.1
          have hC' := compat_extend_unit P ρ c u hC hSatC hc.2
          exact ih _ hC' hRun

def rupCheck (f : Cnf) (c : Clause) (trace : List (Clause × Lit)) (confl : Clause) : Bool :=
  match assumeNegClause c (fun _ => none) with
  | none => true
  | some P0 =>
      match runUnitTrace f P0 trace with
      | none => false
      | some Pf => decide (confl ∈ f) && isFalsified Pf confl

theorem rup_sound (f : Cnf) (c : Clause) (trace : List (Clause × Lit)) (confl : Clause)
    (hRup : rupCheck f c trace confl = true) : Entails f c := by
  intro ρ hSatF
  cases hc : evalClause ρ c with
  | true => rfl
  | false =>
      have ⟨P0, hP0, hC0⟩ := assumeNegClause_compat c (fun _ => none) ρ (compat_empty ρ) hc
      unfold rupCheck at hRup
      rw [hP0] at hRup
      dsimp only at hRup
      cases hRun : runUnitTrace f P0 trace with
      | none => rw [hRun] at hRup; contradiction
      | some Pf =>
          rw [hRun] at hRup
          dsimp only at hRup
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hRup
          have hCf := runUnitTrace_compat f ρ hSatF trace P0 Pf hC0 hRun
          have hFals := conflict_refutes Pf ρ confl hCf hRup.2
          unfold evalCnf at hSatF
          have hTrue : evalClause ρ confl = true := List.all_eq_true.mp hSatF confl hRup.1
          rw [hTrue] at hFals
          contradiction

theorem rup_preserves_equisat (f : Cnf) (c : Clause) (trace : List (Clause × Lit)) (confl : Clause)
    (hRup : rupCheck f c trace confl = true) :
    Satisfiable (c :: f) ↔ Satisfiable f :=
  add_entailed_equisat f c (rup_sound f c trace confl hRup)

-- =========================================================================
-- Section 4: RAT (Resolution Asymmetric Tautology) & Full DRAT Proof Soundness
-- =========================================================================

def resolventClause (c : Clause) (p : Lit) (d : Clause) : Clause :=
  c.filter (fun l => !(decide (l = p))) ++ d.filter (fun l => !(decide (l = litNeg p)))

private def flipVarAssign (ρ : Assign) (v : Nat) (b : Bool) : Assign :=
  fun x => if x = v then b else ρ x

private theorem evalLit_flip_same_or_diff (ρ : Assign) (p l : Lit)
    (hlNeg : l ≠ litNeg p) :
    evalLit (flipVarAssign ρ (litVar p) (litPos p)) l = true ∨
    (litVar l ≠ litVar p ∧ evalLit ρ l = evalLit (flipVarAssign ρ (litVar p) (litPos p)) l) := by
  by_cases hv : litVar l = litVar p
  · left
    rcases lit_eq_or_neg_of_same_var l p hv with rfl | hneg
    · unfold evalLit flipVarAssign
      simp only [ite_true]
      cases litPos l <;> rfl
    · exact False.elim (hlNeg hneg)
  · right
    refine ⟨hv, ?_⟩
    unfold evalLit flipVarAssign
    simp [hv]

theorem rat_entailed_resolvents_equisat (f : Cnf) (c : Clause) (p : Lit)
    (hpMem : p ∈ c)
    (hRes : ∀ d, d ∈ f → litNeg p ∈ d → Entails f (resolventClause c p d)) :
    Satisfiable (c :: f) ↔ Satisfiable f := by
  constructor
  · intro ⟨ρ, h⟩
    unfold evalCnf at h
    simp only [List.all_cons, Bool.and_eq_true] at h
    exact ⟨ρ, h.2⟩
  · intro ⟨ρ, hSatF⟩
    cases hc : evalClause ρ c with
    | true =>
        refine ⟨ρ, ?_⟩
        unfold evalCnf
        simp only [List.all_cons, Bool.and_eq_true]
        exact ⟨hc, hSatF⟩
    | false =>
        let ρ' := flipVarAssign ρ (litVar p) (litPos p)
        have hpTrue' : evalLit ρ' p = true := by
          dsimp only [ρ']
          unfold evalLit flipVarAssign
          simp only [ite_true]
          cases litPos p <;> rfl
        have hcTrue' : evalClause ρ' c = true := by
          unfold evalClause
          exact List.any_eq_true.mpr ⟨p, hpMem, hpTrue'⟩
        have hfTrue' : evalCnf ρ' f = true := by
          unfold evalCnf
          rw [List.all_eq_true]
          intro d hdMem
          by_cases hnegMem : litNeg p ∈ d
          · have hEnt := hRes d hdMem hnegMem ρ hSatF
            unfold evalClause resolventClause at hEnt
            obtain ⟨l, hlMem, hlTrue⟩ := List.any_eq_true.mp hEnt
            rw [List.mem_append] at hlMem
            rcases hlMem with hlC | hlD
            · rw [List.mem_filter] at hlC
              have hCFalse : evalClause ρ c = false := hc
              have hlInC : evalLit ρ l = false := by
                cases he : evalLit ρ l with
                | false => rfl
                | true =>
                    have ht : evalClause ρ c = true := List.any_eq_true.mpr ⟨l, hlC.1, he⟩
                    rw [ht] at hCFalse; contradiction
              rw [hlInC] at hlTrue; contradiction
            · rw [List.mem_filter] at hlD
              have hNotNeg : l ≠ litNeg p := by
                have h2 := hlD.2
                simp only [Bool.not_eq_true', decide_eq_false_iff_not] at h2
                exact h2
              rcases evalLit_flip_same_or_diff ρ p l hNotNeg with h1 | ⟨_, heq⟩
              · exact List.any_eq_true.mpr ⟨l, hlD.1, h1⟩
              · rw [heq] at hlTrue
                exact List.any_eq_true.mpr ⟨l, hlD.1, hlTrue⟩
          · unfold evalCnf at hSatF
            have hdTrue : evalClause ρ d = true := List.all_eq_true.mp hSatF d hdMem
            obtain ⟨l, hlMem, hlTrue⟩ := List.any_eq_true.mp hdTrue
            have hNotNeg : l ≠ litNeg p := by
              intro heq; subst heq; exact hnegMem hlMem
            rcases evalLit_flip_same_or_diff ρ p l hNotNeg with h1 | ⟨_, heq⟩
            · exact List.any_eq_true.mpr ⟨l, hlMem, h1⟩
            · rw [heq] at hlTrue
              exact List.any_eq_true.mpr ⟨l, hlMem, hlTrue⟩
        refine ⟨ρ', ?_⟩
        unfold evalCnf
        simp only [List.all_cons, Bool.and_eq_true]
        exact ⟨hcTrue', hfTrue'⟩

structure RatWitness where
  dClause : Clause
  trace   : List (Clause × Lit)
  confl   : Clause
  deriving DecidableEq, Repr

inductive ProofStep where
  | addRup (c : Clause) (trace : List (Clause × Lit)) (confl : Clause)
  | addRat (c : Clause) (p : Lit) (resWits : List RatWitness)
  | delClause (c : Clause)
  deriving DecidableEq, Repr

def ratStepCheck (f : Cnf) (c : Clause) (p : Lit) (wits : List RatWitness) : Bool :=
  decide (p ∈ c) &&
  f.all (fun d =>
    if decide (litNeg p ∈ d) then
      wits.any (fun w => decide (w.dClause = d) && rupCheck f (resolventClause c p d) w.trace w.confl)
    else
      true)

theorem ratStepCheck_sound (f : Cnf) (c : Clause) (p : Lit) (wits : List RatWitness)
    (hRat : ratStepCheck f c p wits = true) :
    Satisfiable (c :: f) ↔ Satisfiable f := by
  unfold ratStepCheck at hRat
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hRat
  apply rat_entailed_resolvents_equisat f c p hRat.1
  intro d hdMem hNegMem
  have hall := List.all_eq_true.mp hRat.2 d hdMem
  simp only [hNegMem, ite_true] at hall
  obtain ⟨w, _, hw⟩ := List.any_eq_true.mp hall
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hw
  exact rup_sound f (resolventClause c p d) w.trace w.confl hw.2

def eraseOneClause (c : Clause) : Cnf → Cnf
  | [] => []
  | x :: xs => if x = c then xs else x :: eraseOneClause c xs

theorem eraseOneClause_mem (c x : Clause) (f : Cnf) (hx : x ∈ eraseOneClause c f) : x ∈ f := by
  induction f with
  | nil => simp [eraseOneClause] at hx
  | cons y ys ih =>
      unfold eraseOneClause at hx
      split at hx
      · exact List.mem_cons_of_mem y hx
      · simp only [List.mem_cons] at hx
        rcases hx with rfl | hy
        · exact List.mem_cons_self
        · exact List.mem_cons_of_mem y (ih hy)

def verifyProofSteps (f : Cnf) : List ProofStep → Bool
  | [] => decide ([] ∈ f)
  | ProofStep.addRup c tr cf :: rest =>
      rupCheck f c tr cf && verifyProofSteps (c :: f) rest
  | ProofStep.addRat c p wits :: rest =>
      ratStepCheck f c p wits && verifyProofSteps (c :: f) rest
  | ProofStep.delClause c :: rest =>
      verifyProofSteps (eraseOneClause c f) rest

theorem proof_chain_sound (f : Cnf) (steps : List ProofStep)
    (hOk : verifyProofSteps f steps = true) : Unsatisfiable f := by
  rw [unsat_iff_not_sat]
  induction steps generalizing f with
  | nil =>
      simp only [verifyProofSteps, decide_eq_true_eq] at hOk
      exact (unsat_iff_not_sat f).mp (empty_clause_unsat f hOk)
  | cons st rest ih =>
      cases st with
      | addRup c tr cf =>
          unfold verifyProofSteps at hOk
          simp only [Bool.and_eq_true] at hOk
          intro hSat
          have hSat' := (rup_preserves_equisat f c tr cf hOk.1).mpr hSat
          exact ih (c :: f) hOk.2 hSat'
      | addRat c p wits =>
          unfold verifyProofSteps at hOk
          simp only [Bool.and_eq_true] at hOk
          intro hSat
          have hSat' := (ratStepCheck_sound f c p wits hOk.1).mpr hSat
          exact ih (c :: f) hOk.2 hSat'
      | delClause c =>
          unfold verifyProofSteps at hOk
          intro hSat
          have hSat' := subset_preserves_sat f (eraseOneClause c f) (fun x hx => eraseOneClause_mem c x f hx) hSat
          exact ih (eraseOneClause c f) hOk hSat'

-- =========================================================================
-- Section 5: Concrete Decidable Positive & Negative Witnesses (`decide`)
-- =========================================================================

-- Literal codes: +v = 2*v, -v = 2*v + 1
-- Mirror of PHP(3,2) in `sat_cdcl.om` (`sc_st_php32`) and `sat_check.om` (`ck_st_php32`)
def php32Cnf : Cnf :=
  [ [2, 4], [6, 8], [10, 12],
    [3, 7], [3, 11], [7, 11],
    [5, 9], [5, 13], [9, 13] ]

def php32Proof : List ProofStep :=
  [ ProofStep.addRup [3] [([3, 7], 7), ([3, 11], 11), ([6, 8], 8), ([10, 12], 12)] [9, 13],
    ProofStep.addRup [7] [([7, 11], 11), ([10, 12], 12), ([3], 3), ([2, 4], 4)] [5, 13],
    ProofStep.addRup [11] [([3], 3), ([7], 7), ([2, 4], 4), ([6, 8], 8)] [5, 9],
    ProofStep.addRup [] [([3], 3), ([7], 7), ([2, 4], 4), ([6, 8], 8)] [5, 9] ]

def php32DroppedClause : Cnf :=
  [ [2, 4], [6, 8], [10, 12],
    [3, 7], [3, 11], [7, 11],
    [5, 9], [5, 13] ]

def satToyCnf : Cnf :=
  [ [2, 4], [3, 6], [5, 6] ]

def satToyAssign : Assign
  | 1 => false
  | 2 => true
  | 3 => true
  | _ => false

def satToyFlipped : Assign
  | 1 => false
  | 2 => true
  | 3 => false
  | _ => false

def php32DroppedAssign : Assign
  | 1 => true
  | 2 => false
  | 3 => false
  | 4 => true
  | 5 => false
  | 6 => true
  | _ => false

def ratToyCnf : Cnf :=
  php32Cnf ++ [ [14, 16], [15, 17], [19, 15, 16] ]

def ratToyProof : List ProofStep :=
  [ ProofStep.addRat [18, 14, 17] 18
      [ { dClause := [19, 15, 16], trace := [], confl := [] } ],
    ProofStep.addRup [3] [([3, 7], 7), ([3, 11], 11), ([6, 8], 8), ([10, 12], 12)] [9, 13],
    ProofStep.addRup [7] [([7, 11], 11), ([10, 12], 12), ([3], 3), ([2, 4], 4)] [5, 13],
    ProofStep.addRup [11] [([3], 3), ([7], 7), ([2, 4], 4), ([6, 8], 8)] [5, 9],
    ProofStep.addRup [] [([3], 3), ([7], 7), ([2, 4], 4), ([6, 8], 8)] [5, 9] ]

def negBadRupCnf : Cnf :=
  [ [3, 4], [3, 5] ]

/-- Positive Control 1: Valid SAT witness satisfies every clause of `satToyCnf`. -/
theorem pos_ctrl_sat_witness :
    evalCnf satToyAssign satToyCnf = true := by
  decide

/-- Positive Control 2: Full RUP proof for `PHP(3,2)` checks out via kernel `decide`. -/
theorem pos_ctrl_php32_rup_valid :
    verifyProofSteps php32Cnf php32Proof = true := by
  decide

theorem pos_ctrl_php32_unsat : Unsatisfiable php32Cnf :=
  proof_chain_sound php32Cnf php32Proof pos_ctrl_php32_rup_valid

/-- Positive Control 3: Non-RUP DRAT proof (`addRat` + `addRup` + `[]`) verifies by `decide`. -/
theorem pos_ctrl_rat_proof_valid :
    verifyProofSteps ratToyCnf ratToyProof = true := by
  decide

theorem pos_ctrl_rat_unsat : Unsatisfiable ratToyCnf :=
  proof_chain_sound ratToyCnf ratToyProof pos_ctrl_rat_proof_valid

/-- Negative Control 1 (M1): Flipped SAT literal witness rejected (`evalCnf = false`). -/
theorem neg_ctrl_1_flipped_sat_rejected :
    evalCnf satToyFlipped satToyCnf = false := by
  decide

/-- Negative Control 2 (M2): Forged non-RUP, non-RAT clause `[2]` rejected (`= false`). -/
theorem neg_ctrl_2_forged_rup_rejected :
    rupCheck negBadRupCnf [2] [] [3, 4] = false ∧
    ratStepCheck negBadRupCnf [2] 2 [] = false := by
  decide

/-- Negative Control 3 (M3): Dropping the last clause of `PHP(3,2)` leaves it satisfiable! -/
theorem neg_ctrl_3_dropped_clause_sat :
    evalCnf php32DroppedAssign php32DroppedClause = true := by
  decide

/-- Negative Control 4 (M4): Omitting final empty clause `[]` rejected (`= false`). -/
theorem neg_ctrl_4_missing_empty_rejected :
    verifyProofSteps php32Cnf (php32Proof.take 3) = false := by
  decide

/-- Negative Control 5 (Lit bounds): Zero literal (`lit < 2`) or out-of-range variable rejected. -/
theorem neg_ctrl_5_invalid_lit_rejected :
    validLit 6 0 = false ∧
    validLit 6 1 = false ∧
    validClause 6 [2, 14] = false := by
  decide

-- =========================================================================
-- Section 6: Axiom Audit (Standard Core Axioms Only, Zero sorry/native_decide)
-- =========================================================================

#print axioms litNeg_involutive
#print axioms litVar_neg
#print axioms litPos_neg
#print axioms lit_eq_or_neg_of_same_var
#print axioms unsat_iff_not_sat
#print axioms evalLit_neg
#print axioms empty_clause_unsat
#print axioms add_entailed_equisat
#print axioms subset_preserves_sat
#print axioms compat_empty
#print axioms compat_set
#print axioms evalLitOpt_sound
#print axioms conflict_refutes
#print axioms unit_prop_sound
#print axioms compat_extend_unit
#print axioms assumeNegClause_compat
#print axioms runUnitTrace_compat
#print axioms rup_sound
#print axioms rup_preserves_equisat
#print axioms rat_entailed_resolvents_equisat
#print axioms ratStepCheck_sound
#print axioms eraseOneClause_mem
#print axioms proof_chain_sound
#print axioms pos_ctrl_sat_witness
#print axioms pos_ctrl_php32_rup_valid
#print axioms pos_ctrl_php32_unsat
#print axioms pos_ctrl_rat_proof_valid
#print axioms pos_ctrl_rat_unsat
#print axioms neg_ctrl_1_flipped_sat_rejected
#print axioms neg_ctrl_2_forged_rup_rejected
#print axioms neg_ctrl_3_dropped_clause_sat
#print axioms neg_ctrl_4_missing_empty_rejected
#print axioms neg_ctrl_5_invalid_lit_rejected

end OmegaSatSoundness
