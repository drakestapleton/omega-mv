/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/HelixBFT.lean

  Machine-checked Lean 4 proofs for the Generalized N = 3f + 1 Byzantine Self-Healing
  Compiler Braid (instantiated at N = 4, f = 1 and N = 7, f = 2), Quorum Election +
  Cold-Regrowth Composition, Compiler Mitosis, and Arboris Predator <-> Ascetic Hot-Swap.

  Model-to-system link:
    - `BraidN`, `countMatchesN`, `hasQuorumN`, `electQuorumN`, `healBraidOpt` mirror
      `seed/helix/bft_healer.om` (`bfDoQuorumN` with threshold `n - f = 2f + 1` for
      `n = 3f + 1`, quarantine bitmask `100 + mask` for `1..f` faults, fail-closed
      exit `20` for `> f` faults) and `seed/helix/braid4-verify.sh` / `braid7-verify.sh`.
    - `mitosisStep` mirrors `bfMitosisStep` in `seed/helix/bft_healer.om`.
    - `runWorkload` / `ascetic_predator_hotswap_sound` mirror `bfArbMode` + Monk-verified
      SM121 schedules in `seed/helix/bft_healer.om` and `seed/helix/monk_check.om`.

  Theorems proved (ZERO sorry, ZERO extra axioms):
    1. Generalized `BraidN (n : Nat) (D : Type)` for any `n ≥ 3*f + 1`:
       - `bftN_quorum_unique`: at most one digest can hold `≥ n - f` votes (for `n = 3f + 1`, `2f + 1`).
       - `bftN_survives_f_faults`: with `≤ f` Byzantine faults, `canon` always holds a quorum
         and no distinct corrupted digest can ever hold one.
       - `electQuorumN_recovers_canon`: the computable quorum election algorithm
         `electQuorumN f b` ALWAYS returns `some canon` whenever `faultCountN b canon ≤ f`
         (genuinely uses `hf` — fixes the former `have _ := hf` modeling gap!).
       - `bftN_elect_and_heal_restores_unanimity`: directly composes `electQuorumN` with
         `healBraidOpt` to prove `healBraidOpt b (electQuorumN f b) = some (unanimousN n canon)`,
         yielding `countMatchesN = n` and `faultCountN = 0`.
       - `bftN_3f1_threshold_eq`: for `n = 3*f + 1`, `n - f = 2*f + 1`.
    2. Concrete instantiations & tight negative controls:
       - `braid4_bft_spec` (N = 4, f = 1, quorum ≥ 3) + `bft_double_fault_counterexample` (f = 2 halts `none`).
       - `braid7_bft_spec` (N = 7, f = 2, quorum ≥ 5) + `bft7_triple_fault_counterexample` (f = 3 halts `none`).
       - Backward-compatible `Braid4` API with real `electQuorum` + `electQuorum_recovers_canon`
         composed with `healBraid`.
    3. `ascetic_predator_hotswap_sound` and `mitosis_monotonic_and_safe`.
-/

namespace HelixBFT

-- ==================== GENERALIZED N = 3f + 1 BYZANTINE BRAID ====================

/-- Generalized N-strand braid of canonical compiler or kernel digests. -/
structure BraidN (n : Nat) (D : Type) where
  strands : List D
  hlen    : strands.length = n

/-- Count occurrences of digest `x` in a list of strand outputs. -/
def countList {D : Type} [DecidableEq D] (xs : List D) (x : D) : Nat :=
  match xs with
  | [] => 0
  | y :: ys => (if y = x then 1 else 0) + countList ys x

/-- Count strands in `xs` disagreeing with canonical truth `canon`. -/
def faultList {D : Type} [DecidableEq D] (xs : List D) (canon : D) : Nat :=
  match xs with
  | [] => 0
  | y :: ys => (if y = canon then 0 else 1) + faultList ys canon

def countMatchesN {D : Type} [DecidableEq D] {n : Nat} (b : BraidN n D) (x : D) : Nat :=
  countList b.strands x

def faultCountN {D : Type} [DecidableEq D] {n : Nat} (b : BraidN n D) (canon : D) : Nat :=
  faultList b.strands canon

/-- Quorum threshold for `n ≥ 3*f + 1`: requires `≥ n - f` agreeing strands
    (which equals `2*f + 1` when `n = 3*f + 1`, i.e., 3/4 for N=4 and 5/7 for N=7). -/
def hasQuorumN {D : Type} [DecidableEq D] {n : Nat} (f : Nat) (b : BraidN n D) (x : D) : Prop :=
  countMatchesN b x ≥ n - f

theorem bftN_3f1_threshold_eq (f : Nat) : (3 * f + 1) - f = 2 * f + 1 := by
  omega

private theorem countList_add_faultList {D : Type} [DecidableEq D] (xs : List D) (x : D) :
    countList xs x + faultList xs x = xs.length := by
  induction xs with
  | nil => rfl
  | cons y ys ih =>
    simp only [countList, faultList, List.length_cons]
    by_cases h : y = x
    · simp only [h, ↓reduceIte]; omega
    · simp only [h, ↓reduceIte]; omega

private theorem countList_disjoint_sum {D : Type} [DecidableEq D] (xs : List D) (x y : D)
    (hne : x ≠ y) :
    countList xs x + countList xs y ≤ xs.length := by
  induction xs with
  | nil => simp [countList]
  | cons z zs ih =>
    simp only [countList, List.length_cons]
    by_cases h1 : z = x
    · subst h1
      simp only [↓reduceIte, hne]
      omega
    · by_cases h2 : z = y
      · subst h2
        simp only [h1, ↓reduceIte]
        omega
      · simp only [h1, h2, ↓reduceIte]
        omega

private theorem mem_of_countList_pos {D : Type} [DecidableEq D] (xs : List D) (x : D)
    (h : countList xs x > 0) : x ∈ xs := by
  induction xs with
  | nil => simp [countList] at h
  | cons y ys ih =>
    simp only [countList] at h
    by_cases hyx : y = x
    · subst hyx; exact List.Mem.head ys
    · simp only [hyx, ↓reduceIte, Nat.zero_add] at h
      exact List.Mem.tail y (ih h)

/-- Generalized BFT Quorum Uniqueness: whenever `n ≥ 3*f + 1`, at most one digest
    can hold a Byzantine quorum (`≥ n - f` votes). -/
theorem bftN_quorum_unique {D : Type} [DecidableEq D] {n f : Nat}
    (hn : n ≥ 3 * f + 1) (b : BraidN n D) (x y : D)
    (hx : hasQuorumN f b x) (hy : hasQuorumN f b y) : x = y := by
  by_cases hxy : x = y
  · exact hxy
  · exfalso
    unfold hasQuorumN countMatchesN at hx hy
    have hsum := countList_disjoint_sum b.strands x y hxy
    rw [b.hlen] at hsum
    omega

/-- Generalized BFT Survival Theorem: with `≤ f` Byzantine faults on `n ≥ 3*f + 1` strands,
    the canonical truth ALWAYS holds a quorum and no corrupted digest can outvote it. -/
theorem bftN_survives_f_faults {D : Type} [DecidableEq D] {n f : Nat}
    (hn : n ≥ 3 * f + 1) (b : BraidN n D) (canon bad : D)
    (hf : faultCountN b canon ≤ f) (hbad : bad ≠ canon) :
    hasQuorumN f b canon ∧ ¬ hasQuorumN f b bad := by
  have hq : hasQuorumN f b canon := by
    unfold hasQuorumN countMatchesN
    unfold faultCountN at hf
    have htot := countList_add_faultList b.strands canon
    rw [b.hlen] at htot
    omega
  refine ⟨hq, ?_⟩
  intro hqb
  exact hbad (bftN_quorum_unique hn b bad canon hqb hq)

-- ==================== COMPUTABLE QUORUM ELECTION & HEALING COMPOSITION ====================

/-- Computable quorum election over candidate list `cands` against full strand list `all`. -/
def findQuorumAux {D : Type} [DecidableEq D] (thresh : Nat) (all : List D) : List D → Option D
  | [] => none
  | x :: rest =>
    if countList all x ≥ thresh then some x
    else findQuorumAux thresh all rest

/-- Elect the unique Byzantine quorum digest (returns `none` fail-closed if no quorum exists). -/
def electQuorumN {D : Type} [DecidableEq D] {n : Nat} (f : Nat) (b : BraidN n D) : Option D :=
  findQuorumAux (n - f) b.strands b.strands

private theorem findQuorumAux_sound {D : Type} [DecidableEq D] (thresh : Nat)
    (all cands : List D) (q : D) (h : findQuorumAux thresh all cands = some q) :
    countList all q ≥ thresh := by
  induction cands with
  | nil => simp [findQuorumAux] at h
  | cons x rest ih =>
    unfold findQuorumAux at h
    split at h
    · rename_i hge
      injection h with hxq
      subst hxq
      exact hge
    · exact ih h

private theorem findQuorumAux_complete {D : Type} [DecidableEq D] (thresh : Nat)
    (all cands : List D) (x : D) (hmem : x ∈ cands) (hge : countList all x ≥ thresh) :
    ∃ q, findQuorumAux thresh all cands = some q := by
  induction cands with
  | nil => cases hmem
  | cons y rest ih =>
    unfold findQuorumAux
    split
    · exact ⟨y, rfl⟩
    · rename_i hnot
      cases hmem with
      | head => exact absurd hge hnot
      | tail _ hmem' => exact ih hmem'

/-- Core Election Recovery Theorem: for any `n ≥ 3*f + 1`, if at most `f` strands are
    Byzantine-faulty (`faultCountN b canon ≤ f`), then `electQuorumN f b` ALWAYS returns
    `some canon`. (No unused hypothesis: `hf` is required to guarantee `canon` reaches
    threshold `n - f` and uniquely dominates every other candidate.) -/
theorem electQuorumN_recovers_canon {D : Type} [DecidableEq D] {n f : Nat}
    (hn : n ≥ 3 * f + 1) (b : BraidN n D) (canon : D)
    (hf : faultCountN b canon ≤ f) :
    electQuorumN f b = some canon := by
  have hcanon_q : countList b.strands canon ≥ n - f := by
    have htot := countList_add_faultList b.strands canon
    unfold faultCountN at hf
    rw [b.hlen] at htot
    omega
  have hpos : countList b.strands canon > 0 := by omega
  have hmem : canon ∈ b.strands := mem_of_countList_pos b.strands canon hpos
  obtain ⟨q, hq⟩ := findQuorumAux_complete (n - f) b.strands b.strands canon hmem hcanon_q
  have hq_ge : countList b.strands q ≥ n - f :=
    findQuorumAux_sound (n - f) b.strands b.strands q hq
  have hq_eq : q = canon :=
    bftN_quorum_unique hn b q canon hq_ge hcanon_q
  subst hq_eq
  exact hq

/-- Canonical unanimous N-strand braid where every strand holds digest `x`. -/
def unanimousN (n : Nat) {D : Type} (x : D) : BraidN n D :=
  { strands := List.replicate n x
    hlen    := List.length_replicate }

/-- Quarantine + Cold Regrowth operator for a generalized N-strand braid:
    every strand disagreeing with elected quorum `q` is regrown from its clean seed, yielding `q`. -/
def healList {D : Type} [DecidableEq D] (xs : List D) (q : D) : List D :=
  xs.map (fun s => if s = q then s else q)

def healBraidN {D : Type} [DecidableEq D] {n : Nat} (b : BraidN n D) (q : D) : BraidN n D :=
  { strands := healList b.strands q
    hlen    := by simp [healList, b.hlen] }

/-- Fail-closed optional healing: halts (`none`) if no quorum was elected,
    otherwise quarantines faulty strands and regrows them to `q`. -/
def healBraidOpt {D : Type} [DecidableEq D] {n : Nat} (b : BraidN n D) :
    Option D → Option (BraidN n D)
  | none   => none
  | some q => some (healBraidN b q)

private theorem healList_eq_replicate {D : Type} [DecidableEq D] (xs : List D) (q : D) :
    healList xs q = List.replicate xs.length q := by
  induction xs with
  | nil => rfl
  | cons y ys ih =>
    simp only [healList, List.map_cons, List.length_cons, List.replicate_succ]
    have hhead : (if y = q then y else q) = q := by
      by_cases h : y = q <;> simp [h]
    rw [hhead]
    congr 1

private theorem countList_replicate {D : Type} [DecidableEq D] (n : Nat) (x : D) :
    countList (List.replicate n x) x = n := by
  induction n with
  | zero => rfl
  | succ k ih => simp [List.replicate_succ, countList, ih]; omega

private theorem faultList_replicate {D : Type} [DecidableEq D] (n : Nat) (x : D) :
    faultList (List.replicate n x) x = 0 := by
  induction n with
  | zero => rfl
  | succ k ih => simp [List.replicate_succ, faultList, ih]

/-- Composed End-to-End BFT Healing Theorem:
    Running computable quorum election `electQuorumN f b` followed by quarantine +
    cold regrowth `healBraidOpt` ALWAYS recovers the exact unanimous canonical braid
    whenever `n ≥ 3*f + 1` and `faultCountN b canon ≤ f`. -/
theorem bftN_elect_and_heal_restores_unanimity {D : Type} [DecidableEq D] {n f : Nat}
    (hn : n ≥ 3 * f + 1) (b : BraidN n D) (canon : D)
    (hf : faultCountN b canon ≤ f) :
    healBraidOpt b (electQuorumN f b) = some (unanimousN n canon) := by
  rw [electQuorumN_recovers_canon hn b canon hf]
  simp only [healBraidOpt, healBraidN, unanimousN]
  congr 1
  cases b with
  | mk strands hlen =>
    simp only [BraidN.mk.injEq]
    rw [healList_eq_replicate, hlen]

theorem unanimousN_counts {D : Type} [DecidableEq D] (n : Nat) (canon : D) :
    countMatchesN (unanimousN n canon) canon = n ∧
    faultCountN (unanimousN n canon) canon = 0 := by
  exact ⟨countList_replicate n canon, faultList_replicate n canon⟩

-- ==================== INSTANTIATIONS: N = 4 (f = 1) AND N = 7 (f = 2) ====================

/-- Instantiation for N = 4, f = 1 (threshold = 3/4). -/
theorem braid4_bft_spec {D : Type} [DecidableEq D] (b : BraidN 4 D) (canon : D)
    (hf : faultCountN b canon ≤ 1) :
    electQuorumN 1 b = some canon ∧
    healBraidOpt b (electQuorumN 1 b) = some (unanimousN 4 canon) := by
  have hn : 4 ≥ 3 * 1 + 1 := by omega
  exact ⟨electQuorumN_recovers_canon hn b canon hf,
         bftN_elect_and_heal_restores_unanimity hn b canon hf⟩

/-- Instantiation for N = 7, f = 2 (threshold = 5/7, surviving ANY 2 simultaneous Byzantine faults). -/
theorem braid7_bft_spec {D : Type} [DecidableEq D] (b : BraidN 7 D) (canon : D)
    (hf : faultCountN b canon ≤ 2) :
    electQuorumN 2 b = some canon ∧
    healBraidOpt b (electQuorumN 2 b) = some (unanimousN 7 canon) := by
  have hn : 7 ≥ 3 * 2 + 1 := by omega
  exact ⟨electQuorumN_recovers_canon hn b canon hf,
         bftN_elect_and_heal_restores_unanimity hn b canon hf⟩

/-- Non-Vacuity Negative Control for N = 7, f = 2:
    with 3 simultaneous Byzantine faults (`f + 1 = 3`), NO digest reaches 5/7 quorum
    and `electQuorumN 2` halts fail-closed (`none`), proving `N = 3f + 1 = 7` is tight! -/
theorem bft7_triple_fault_counterexample :
    let b : BraidN 7 Nat := ⟨[1, 1, 1, 1, 2, 2, 3], rfl⟩
    ¬ hasQuorumN 2 b 1 ∧ ¬ hasQuorumN 2 b 2 ∧ electQuorumN 2 b = none := by
  dsimp [hasQuorumN, countMatchesN, electQuorumN, findQuorumAux, countList]
  decide

-- ==================== LEGACY Braid4 STRUCT + DIRECT electQuorum COMPOSITION ====================

/-- 4-strand braid of canonical compiler or kernel digests. -/
structure Braid4 (D : Type) where
  monk      : D
  predator  : D
  trickster : D
  ascetic   : D
  deriving DecidableEq

def Braid4.toBraidN {D : Type} (b : Braid4 D) : BraidN 4 D :=
  ⟨[b.monk, b.predator, b.trickster, b.ascetic], rfl⟩

def unanimous {D : Type} (x : D) : Braid4 D :=
  { monk := x, predator := x, trickster := x, ascetic := x }

def countMatches {D : Type} [DecidableEq D] (b : Braid4 D) (x : D) : Nat :=
  (if b.monk = x then 1 else 0) +
  (if b.predator = x then 1 else 0) +
  (if b.trickster = x then 1 else 0) +
  (if b.ascetic = x then 1 else 0)

/-- Byzantine quorum predicate for N = 4, f = 1 (requires >= 2f + 1 = 3 agreeing strands). -/
def hasQuorum {D : Type} [DecidableEq D] (b : Braid4 D) (x : D) : Prop :=
  countMatches b x ≥ 3

/-- Number of strands disagreeing with the canonical truth `canon`. -/
def faultCount {D : Type} [DecidableEq D] (b : Braid4 D) (canon : D) : Nat :=
  (if b.monk = canon then 0 else 1) +
  (if b.predator = canon then 0 else 1) +
  (if b.trickster = canon then 0 else 1) +
  (if b.ascetic = canon then 0 else 1)

private theorem braid4_count_eq {D : Type} [DecidableEq D] (b : Braid4 D) (x : D) :
    countMatches b x = countMatchesN b.toBraidN x := by
  simp [countMatches, countMatchesN, Braid4.toBraidN, countList]
  omega

private theorem braid4_fault_eq {D : Type} [DecidableEq D] (b : Braid4 D) (canon : D) :
    faultCount b canon = faultCountN b.toBraidN canon := by
  simp [faultCount, faultCountN, Braid4.toBraidN, faultList]
  omega

/-- At most one digest can hold a 3/4 Byzantine quorum. -/
theorem bft_quorum_unique {D : Type} [DecidableEq D] (b : Braid4 D) (x y : D)
    (hx : hasQuorum b x) (hy : hasQuorum b y) : x = y := by
  have hx' : hasQuorumN 1 b.toBraidN x := by
    unfold hasQuorumN; rw [← braid4_count_eq]; exact hx
  have hy' : hasQuorumN 1 b.toBraidN y := by
    unfold hasQuorumN; rw [← braid4_count_eq]; exact hy
  exact bftN_quorum_unique (by omega) b.toBraidN x y hx' hy'

/-- BFT Survival Theorem for N = 4, f = 1. -/
theorem bft_survives_single_fault {D : Type} [DecidableEq D] (b : Braid4 D) (canon bad : D)
    (hf : faultCount b canon ≤ 1) (hbad : bad ≠ canon) :
    hasQuorum b canon ∧ ¬ hasQuorum b bad := by
  rw [braid4_fault_eq] at hf
  have h := bftN_survives_f_faults (by omega) b.toBraidN canon bad hf hbad
  unfold hasQuorum hasQuorumN at *
  rw [braid4_count_eq, braid4_count_eq]
  exact h

/-- Computable 4-strand quorum election (returns `some q` iff `countMatches b q ≥ 3`). -/
def electQuorum {D : Type} [DecidableEq D] (b : Braid4 D) : Option D :=
  electQuorumN 1 b.toBraidN

/-- Quarantine + Cold Regrowth operator driven by elected `Option D`. -/
def healBraid {D : Type} [DecidableEq D] (b : Braid4 D) (q : D) : Braid4 D :=
  { monk      := if b.monk = q then b.monk else q
    predator  := if b.predator = q then b.predator else q
    trickster := if b.trickster = q then b.trickster else q
    ascetic   := if b.ascetic = q then b.ascetic else q }

def healBraid4Opt {D : Type} [DecidableEq D] (b : Braid4 D) : Option D → Option (Braid4 D)
  | none   => none
  | some q => some (healBraid b q)

/-- `electQuorum` recovers `some canon` for any single-strand fault (genuinely uses `hf`). -/
theorem electQuorum_recovers_canon {D : Type} [DecidableEq D] (b : Braid4 D) (canon : D)
    (hf : faultCount b canon ≤ 1) :
    electQuorum b = some canon := by
  rw [braid4_fault_eq] at hf
  exact electQuorumN_recovers_canon (by omega) b.toBraidN canon hf

/-- Direct composition: `healBraid4Opt b (electQuorum b) = some (unanimous canon)` and
    exact 4/4 unanimity is restored without any vacuous `have _ := hf`. -/
theorem bft_quarantine_regrow_restores_unanimity {D : Type} [DecidableEq D]
    (b : Braid4 D) (canon : D) (hf : faultCount b canon ≤ 1) :
    healBraid4Opt b (electQuorum b) = some (unanimous canon) ∧
    (∀ q, electQuorum b = some q →
      healBraid b q = unanimous canon ∧
      countMatches (healBraid b q) canon = 4 ∧
      faultCount (healBraid b q) canon = 0) := by
  have helec : electQuorum b = some canon := electQuorum_recovers_canon b canon hf
  have hheal : healBraid b canon = unanimous canon := by
    unfold healBraid unanimous
    by_cases hm : b.monk = canon <;>
    by_cases hp : b.predator = canon <;>
    by_cases ht : b.trickster = canon <;>
    by_cases ha : b.ascetic = canon <;>
    simp [hm, hp, ht, ha]
  refine ⟨?_, ?_⟩
  · simp [helec, healBraid4Opt, hheal]
  · intro q hq
    rw [helec] at hq
    injection hq with hqc
    subst hqc
    refine ⟨hheal, ?_, ?_⟩
    · rw [hheal]; simp [unanimous, countMatches]
    · rw [hheal]; simp [unanimous, faultCount]

-- ==================== ARBORIS PREDATOR <-> ASCETIC HOT-SWAP SOUNDNESS ====================

inductive PowerMode where
  | predator  -- wall power / cool: maximize tokens/sec
  | ascetic   -- thermal throttle / battery / edge: minimize joules/token
  deriving DecidableEq, Repr

/-- Hot-swapping mid-workload between Predator and Ascetic kernels preserves exact semantics
    across any sequence of power-mode switches, provided both kernels are Monk-proved equivalent
    to the reference transition function `refStep`. -/
def runWorkload {S : Type} (predStep ascStep : S → S) : List PowerMode → S → S
  | [], s => s
  | .predator :: rest, s => runWorkload predStep ascStep rest (predStep s)
  | .ascetic  :: rest, s => runWorkload predStep ascStep rest (ascStep s)

def runRef {S : Type} (refStep : S → S) : Nat → S → S
  | 0, s => s
  | n + 1, s => runRef refStep n (refStep s)

theorem ascetic_predator_hotswap_sound
    {S : Type} (refStep predStep ascStep : S → S)
    (hpred : ∀ s, predStep s = refStep s)
    (hasc  : ∀ s, ascStep s  = refStep s)
    (modes : List PowerMode) (s0 : S) :
    runWorkload predStep ascStep modes s0 = runRef refStep modes.length s0 := by
  induction modes generalizing s0 with
  | nil => rfl
  | cons m rest ih =>
    cases m with
    | predator =>
      simp only [runWorkload, List.length_cons, runRef, hpred]
      exact ih (refStep s0)
    | ascetic =>
      simp only [runWorkload, List.length_cons, runRef, hasc]
      exact ih (refStep s0)

-- ==================== COMPILER MITOSIS MONOTONICITY & SAFETY ====================

structure CandidateStrand where
  monkProved     : Bool
  tricksterClean : Bool
  metricCost     : Nat   -- lower is better (e.g., us/tok or mJ/tok)

structure BraidChampion where
  safe       : Bool
  metricCost : Nat

/-- Mitosis admission gate: a freshly spawned child strand earns its place in the braid
    IFF it passes Monk's proof gate AND Trickster's chaos test AND strictly beats incumbent cost;
    otherwise it is retired and the incumbent stays untouched. -/
def mitosisStep (inc : BraidChampion) (child : CandidateStrand) : BraidChampion :=
  if child.monkProved && child.tricksterClean && decide (child.metricCost < inc.metricCost) then
    { safe := true, metricCost := child.metricCost }
  else
    inc

theorem mitosis_monotonic_and_safe (inc : BraidChampion) (child : CandidateStrand)
    (hinc : inc.safe = true) :
    (mitosisStep inc child).safe = true ∧
    (mitosisStep inc child).metricCost ≤ inc.metricCost := by
  unfold mitosisStep
  split
  · rename_i hcond
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hcond
    exact ⟨rfl, Nat.le_of_lt hcond.2⟩
  · exact ⟨hinc, Nat.le_refl _⟩

/-- Non-Vacuity Negative Control for N = 4, f = 1:
    with f = 2 simultaneous Byzantine faults on N = 4 strands, NO digest holds a 3/4 quorum
    and `electQuorum` halts fail-closed (`none`). -/
theorem bft_double_fault_counterexample :
    let b : Braid4 Nat := { monk := 1, predator := 1, trickster := 2, ascetic := 2 }
    ¬ hasQuorum b 1 ∧ ¬ hasQuorum b 2 ∧ electQuorum b = none := by
  dsimp [hasQuorum, countMatches, electQuorum, electQuorumN, Braid4.toBraidN, findQuorumAux, countList]
  decide

#print axioms bftN_quorum_unique
#print axioms bftN_survives_f_faults
#print axioms electQuorumN_recovers_canon
#print axioms bftN_elect_and_heal_restores_unanimity
#print axioms braid4_bft_spec
#print axioms braid7_bft_spec
#print axioms bft7_triple_fault_counterexample
#print axioms bft_quorum_unique
#print axioms bft_survives_single_fault
#print axioms electQuorum_recovers_canon
#print axioms bft_quarantine_regrow_restores_unanimity
#print axioms ascetic_predator_hotswap_sound
#print axioms mitosis_monotonic_and_safe
#print axioms bft_double_fault_counterexample

end HelixBFT
