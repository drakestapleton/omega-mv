/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/ProofDnaSoundness.lean

  Machine-checked Lean 4.36.0 soundness proofs for Wave 2 Breakthrough #4:
  Self-Healing Adversarial Proof-DNA Immune Evolution (`OMDNA1`).

  Model-to-system link:
    - `Surface`, `AntibodyRecord`, `CorpusState`, `admitAntibody`, `ratchetValid`,
      and `startupReplayPass` mirror `seed/helix/proof_dna/proof_dna.om` (`OMDNA1`
      64B header + 256B Ed25519-signed antibody records + 64B trailer seal).
    - `bftQuorumSafe` and `MAX_BFT_F` mirror `HiveShield.hiveDecide` /
      `HiveShield.hive_bft_overflow_guard_sound` (`seed/helix/proofs/HiveShield.lean`)
      and `HelixBFT` (`N >= 3f + 1` with `N = 4, f = 1` across Monk | Predator |
      Trickster | Ascetic, plus `1-of-K` Safety Veto non-bypassability).
    - `Surface` invariants match the 5 security/correctness surfaces:
        1. `om3`     (`seed/helix/strand5_aegis/om3_aegis.om`, `Om3MemorySafety.lean`)
        2. `sm121`   (`seed/helix/monk_check.om`, `HelixAntibodies.lean`, `Antibody17.lean`)
        3. `egp3`    (`seed/ng/verify/egp3_checker.om`, `NgEGraphIR.lean`)
        4. `wattcbf` (`apps/omega-wattd/watt_cbf.om`, `WattCBF.lean`)
        5. `omsh`    (`apps/omega-mesh/{mesh_route,mesh_verify}.om`, `strand9_arbiter.om`)

  Proves (0 warnings, 0 sorry, standard Lean 4 axioms only):
    (a) Monotonic antibody set retention (previously verified antibodies are never
        weakened or evicted across evolution rounds; prefix and membership invariant).
    (b) BFT `N >= 3f + 1` (`4 >= 3(1) + 1`, threshold `>= 3`) + `1-of-K` Safety Veto
        non-bypassability + overflow-safe `u64` arithmetic matching `HiveShield`.
    (c) Ed25519 + SHA-256 signature & digest binding integrity required prior to admission.
    (d) Regression-blocking guarantee + concrete `decide` negative controls for all
        7 adversarial bypass/tamper classes.
-/

namespace ProofDnaSoundness

/-- Five hardware/protocol verification surfaces guarded by Proof-DNA (`OMDNA1`). -/
inductive Surface where
  | om3     -- 1: OM-3 linear DMA fence & NO_RAW_PTR
  | sm121   -- 2: SM121 SASS scoreboard & rawFloor >= 6 hazards
  | egp3    -- 3: EGP3 e-graph rewrite soundness
  | wattcbf -- 4: WattCBF < 80 W thermal & overflow boundaries
  | omsh    -- 5: OMSH / OMRC0001 wire framing & IPv4/command validation
  deriving DecidableEq, Repr

/-- Exact overflow ceiling matching `HiveShield.lean` / `strand8_notary.om`:
    guarantees `3 * f + 1 < 2 ^ 64` for every `f <= MAX_BFT_F`. -/
def MAX_BFT_F : Nat := 6148914691236517204

def U64_LIMIT : Nat := 2 ^ 64

/-- Explicit OMDNA1 header / frame bounds validation model. -/
structure OmdnaHeader where
  magicOk     : Bool  -- "OMDNA1"
  version     : Nat   -- must equal 1
  recSize     : Nat   -- must equal 256
  count       : Nat   -- 1 <= count <= 240
  epoch       : Nat   -- >= 1
  ratchetFlr  : Nat   -- >= count
  actualBytes : Nat   -- exact file size == 64 + count * 256 + 64
  deriving DecidableEq, Repr

def headerValid (h : OmdnaHeader) : Bool :=
  h.magicOk &&
  decide (h.version = 1) &&
  decide (h.recSize = 256) &&
  decide (1 ≤ h.count) &&
  decide (h.count ≤ 240) &&
  decide (1 ≤ h.epoch) &&
  decide (h.ratchetFlr ≥ h.count) &&
  decide (h.actualBytes = 64 + h.count * 256 + 64)

/-- Permanent Ed25519-signed OMDNA1 Antibody record. -/
structure AntibodyRecord where
  antibodyId   : Nat
  surface      : Surface
  attackClass  : Nat
  ruleId       : Nat
  bftVotes     : Nat
  bftMask      : Nat
  vetoMask     : Nat
  attackDigest : Nat   -- SHA-256 commitment to canonical attack vector
  chainDigest  : Nat   -- Merkle chain commitment from prior record
  reproBreach  : Bool  -- baseline unhardened surface allows attack
  reproKilled  : Bool  -- synthesized rule kills attack
  nonVacuous   : Bool  -- positive valid surface witness still passes
  sha256Ok     : Bool  -- FIPS 180-4 SHA-256 verification status
  ed25519Ok    : Bool  -- RFC 8032 Ed25519 strict verification status
  deriving DecidableEq, Repr

/-- Corpus state across evolution rounds. -/
structure CorpusState where
  epoch        : Nat
  ratchetFloor : Nat
  records      : List AntibodyRecord
  deriving DecidableEq, Repr

-- ==================== (b) BFT N >= 3f+1 + 1-OF-K SAFETY VETO ====================

/-- Dual-Law Proof-DNA Consensus (exact mirror of `HiveShield.hiveDecide` & `proof_dna.om`):
    1. 1-of-K Safety Veto Law: ANY safety veto (`vetoMask != 0`) halts admission unconditionally.
    2. Overflow-safe BFT Quorum Law: `fMax <= MAX_BFT_F`, `nComp >= 3*fMax + 1`,
       `nComp - fMax <= votes <= nComp`. -/
def bftQuorumSafe (nComp fMax votes vetoMask : Nat) : Bool :=
  decide (vetoMask = 0) &&
  decide (fMax ≤ MAX_BFT_F) &&
  decide (nComp ≥ 3 * fMax + 1) &&
  decide (votes ≥ nComp - fMax) &&
  decide (votes ≤ nComp)

/-- BFT arithmetic overflow safety: no admitted quorum ever overflows `u64` (`2^64`). -/
theorem bft_quorum_overflow_safe (nComp fMax votes vetoMask : Nat)
    (h : bftQuorumSafe nComp fMax votes vetoMask = true) :
    3 * fMax + 1 < U64_LIMIT := by
  unfold bftQuorumSafe MAX_BFT_F U64_LIMIT at *
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  omega

/-- Safety Veto non-bypassability: even unanimous `nComp`-of-`nComp` strand votes
    CANNOT override any non-zero `1-of-K` safety veto! -/
theorem safety_veto_non_bypassable (nComp fMax vetoMask : Nat) (hv : vetoMask ≠ 0) :
    bftQuorumSafe nComp fMax nComp vetoMask = false := by
  unfold bftQuorumSafe
  simp [hv]

/-- For N = 4 strands (`Monk | Predator | Trickster | Ascetic`), `f = 1` gives `4 >= 3(1) + 1`
    and requires `>= 3` agreeing strands. -/
theorem bft_4_1_threshold_sound (votes vetoMask : Nat)
    (h : bftQuorumSafe 4 1 votes vetoMask = true) :
    vetoMask = 0 ∧ 3 ≤ votes ∧ votes ≤ 4 := by
  unfold bftQuorumSafe at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  omega

/-- BFT 4-strand quorum uniqueness: no two distinct verdicts can BOTH achieve `>= 3` out of 4 votes. -/
theorem bft_4_strand_quorum_unique (votesA votesB : Nat)
    (hsum : votesA + votesB ≤ 4) (ha : votesA ≥ 3) (hb : votesB ≥ 3) : False := by
  omega

-- ==================== (c) ED25519 + SHA-256 SIGNATURE BINDING INTEGRITY ====================

/-- Deterministic counterexample replay check before admission. -/
def replayPrecheckOk (ab : AntibodyRecord) : Bool :=
  ab.reproBreach && ab.reproKilled && ab.nonVacuous

/-- Cryptographic signature + digest binding integrity check before admission. -/
def sigBindingValid (ab : AntibodyRecord) (computedSha : Nat) (edStrictOk : Bool) : Bool :=
  decide (ab.attackDigest = computedSha) &&
  ab.sha256Ok &&
  ab.ed25519Ok &&
  edStrictOk

theorem sigBinding_requires_both (ab : AntibodyRecord) (computedSha : Nat) (edStrictOk : Bool)
    (h : sigBindingValid ab computedSha edStrictOk = true) :
    ab.attackDigest = computedSha ∧ ab.sha256Ok = true ∧ ab.ed25519Ok = true ∧ edStrictOk = true := by
  unfold sigBindingValid at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1.1.1, h.1.1.2, h.1.2, h.2⟩

/-- Full fail-closed antibody admission gate (`OMDNA1`):
    requires 3-of-4 BFT consensus, 0 safety vetoes, reproducible counterexample replay,
    valid SHA-256 + strict RFC 8032 Ed25519 binding, and sequential antibody ID. -/
def admitAntibody (s : CorpusState) (ab : AntibodyRecord)
    (computedSha : Nat) (edStrictOk : Bool) : Option CorpusState :=
  if bftQuorumSafe 4 1 ab.bftVotes ab.vetoMask &&
     replayPrecheckOk ab &&
     sigBindingValid ab computedSha edStrictOk &&
     decide (ab.antibodyId = s.records.length + 1) then
    some {
      epoch := s.epoch + 1
      ratchetFloor := max s.ratchetFloor (s.records.length + 1)
      records := s.records ++ [ab]
    }
  else
    none

theorem admit_requires_crypto_bft_veto_replay
    (s s' : CorpusState) (ab : AntibodyRecord) (computedSha : Nat) (edStrictOk : Bool)
    (h : admitAntibody s ab computedSha edStrictOk = some s') :
    ab.vetoMask = 0 ∧
    3 ≤ ab.bftVotes ∧ ab.bftVotes ≤ 4 ∧
    ab.reproBreach = true ∧ ab.reproKilled = true ∧ ab.nonVacuous = true ∧
    ab.attackDigest = computedSha ∧ ab.sha256Ok = true ∧ ab.ed25519Ok = true ∧ edStrictOk = true := by
  unfold admitAntibody at h
  split at h
  · rename_i hcond
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hcond
    have hbft := bft_4_1_threshold_sound ab.bftVotes ab.vetoMask hcond.1.1.1
    have hrep := hcond.1.1.2
    unfold replayPrecheckOk at hrep
    simp only [Bool.and_eq_true] at hrep
    have hsig := sigBinding_requires_both ab computedSha edStrictOk hcond.1.2
    exact ⟨hbft.1, hbft.2.1, hbft.2.2, hrep.1.1, hrep.1.2, hrep.2,
           hsig.1, hsig.2.1, hsig.2.2.1, hsig.2.2.2⟩
  · contradiction

-- ==================== (a) MONOTONIC ANTIBODY SET RETENTION ====================

/-- Monotonic ratchet predicate between prior corpus `prev` and successor corpus `next`:
    epoch and ratchet floor never decrease, count never shrinks, and EVERY prior
    antibody at index `0..prev.records.length-1` is retained verbatim. -/
def ratchetValid (prev next : CorpusState) : Bool :=
  decide (prev.epoch ≤ next.epoch) &&
  decide (prev.ratchetFloor ≤ next.ratchetFloor) &&
  decide (prev.records.length ≤ next.records.length) &&
  decide (next.records.take prev.records.length = prev.records)

private theorem list_take_append_self {α : Type} (xs ys : List α) :
    (xs ++ ys).take xs.length = xs := by
  induction xs with
  | nil => simp
  | cons x xs ih => simp [ih]

/-- Every admitted evolution step strictly preserves the entire prior antibody corpus
    and passes the monotonic ratchet check. -/
theorem admitAntibody_preserves_ratchet
    (s s' : CorpusState) (ab : AntibodyRecord) (computedSha : Nat) (edStrictOk : Bool)
    (h : admitAntibody s ab computedSha edStrictOk = some s') :
    ratchetValid s s' = true ∧
    s'.records.length = s.records.length + 1 ∧
    (∀ x, x ∈ s.records → x ∈ s'.records) ∧
    (∀ i, i < s.records.length → s'.records[i]? = s.records[i]?) := by
  unfold admitAntibody at h
  split at h
  · injection h with hs
    subst hs
    refine ⟨?_, ?_, ?_, ?_⟩
    · unfold ratchetValid
      simp only [Bool.and_eq_true, decide_eq_true_eq, List.length_append, List.length_singleton]
      refine ⟨⟨⟨by omega, by omega⟩, by omega⟩, list_take_append_self s.records [ab]⟩
    · simp
    · intro x hx
      exact List.mem_append_left [ab] hx
    · intro i hi
      exact List.getElem?_append_left hi
  · contradiction

/-- Multi-round evolution trace preserves all antibodies from initial state `s0`. -/
def evolveStep (s : CorpusState) (cand : AntibodyRecord × Nat × Bool) : CorpusState :=
  match admitAntibody s cand.1 cand.2.1 cand.2.2 with
  | some s' => s'
  | none    => s

def evolveTrace (s0 : CorpusState) (cands : List (AntibodyRecord × Nat × Bool)) : CorpusState :=
  cands.foldl evolveStep s0

theorem evolveStep_preserves_ratchet (s : CorpusState) (cand : AntibodyRecord × Nat × Bool) :
    ratchetValid s (evolveStep s cand) = true ∧
    (∀ x, x ∈ s.records → x ∈ (evolveStep s cand).records) := by
  unfold evolveStep
  cases h : admitAntibody s cand.1 cand.2.1 cand.2.2 with
  | none =>
    refine ⟨?_, fun _ hx => hx⟩
    unfold ratchetValid
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    refine ⟨⟨⟨Nat.le_refl _, Nat.le_refl _⟩, Nat.le_refl _⟩, by simp⟩
  | some s' =>
    have hp := admitAntibody_preserves_ratchet s s' cand.1 cand.2.1 cand.2.2 h
    exact ⟨hp.1, hp.2.2.1⟩

private theorem ratchetValid_trans (a b c : CorpusState)
    (hab : ratchetValid a b = true) (hbc : ratchetValid b c = true) :
    ratchetValid a c = true := by
  unfold ratchetValid at *
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hab hbc ⊢
  refine ⟨⟨⟨by omega, by omega⟩, by omega⟩, ?_⟩
  have htake : (c.records.take b.records.length).take a.records.length = c.records.take a.records.length := by
    rw [List.take_take]
    congr 1
    exact Nat.min_eq_left hab.1.2
  rw [← htake, hbc.2, hab.2]

/-- Multi-round Proof-DNA evolution is globally monotonic across arbitrary round counts:
    every previously verified antibody remains present and unaltered in the final corpus. -/
theorem evolveTrace_monotonic (cands : List (AntibodyRecord × Nat × Bool)) (s0 : CorpusState) :
    ratchetValid s0 (evolveTrace s0 cands) = true ∧
    (∀ x, x ∈ s0.records → x ∈ (evolveTrace s0 cands).records) := by
  induction cands generalizing s0 with
  | nil =>
    refine ⟨?_, fun _ hx => hx⟩
    unfold ratchetValid
    simp only [Bool.and_eq_true, decide_eq_true_eq]
    exact ⟨⟨⟨Nat.le_refl _, Nat.le_refl _⟩, Nat.le_refl _⟩, List.take_length⟩
  | cons c rest ih =>
    unfold evolveTrace
    simp only [List.foldl_cons]
    have hstep := evolveStep_preserves_ratchet s0 c
    have hrest := ih (evolveStep s0 c)
    refine ⟨ratchetValid_trans s0 (evolveStep s0 c) (evolveTrace (evolveStep s0 c) rest) hstep.1 hrest.1, ?_⟩
    intro x hx
    exact hrest.2 x (hstep.2 x hx)

-- ==================== (d) STARTUP REPLAY & REGRESSION-BLOCKING GUARANTEE ====================

/-- Abstract candidate verifier guard: `guard ruleId = true` means a bug/attack of `ruleId`
    SLIPS THROUGH (regression!), `false` means the attack is KILLED. -/
def startupReplayPass (corpus : List AntibodyRecord) (attackPassesGuard : Nat → Bool) : Bool :=
  corpus.all (fun ab => !(attackPassesGuard ab.ruleId))

/-- Regression-blocking guarantee: if startup replay passes on `corpus`, NO antibody's
    attack class can slip through the active verifier (`attackPassesGuard ab.ruleId = false`). -/
theorem regression_blocker_sound (corpus : List AntibodyRecord) (attackPassesGuard : Nat → Bool)
    (hpass : startupReplayPass corpus attackPassesGuard = true)
    (ab : AntibodyRecord) (hmem : ab ∈ corpus) :
    attackPassesGuard ab.ruleId = false := by
  unfold startupReplayPass at hpass
  rw [List.all_eq_true] at hpass
  have hspec := hpass ab hmem
  simpa using hspec

/-- Weakened mutant detector: any mutant that lets ANY antibody `ab ∈ corpus` slip through
    MUST fail `startupReplayPass`. -/
theorem weakened_mutant_detected (corpus : List AntibodyRecord) (attackPassesGuard : Nat → Bool)
    (ab : AntibodyRecord) (hmem : ab ∈ corpus) (hslip : attackPassesGuard ab.ruleId = true) :
    startupReplayPass corpus attackPassesGuard = false := by
  cases h : startupReplayPass corpus attackPassesGuard with
  | false => rfl
  | true =>
    have hblk := regression_blocker_sound corpus attackPassesGuard h ab hmem
    rw [hblk] at hslip
    cases hslip

-- ==================== CONCRETE NON-VACUITY WITNESSES & 7 NEGATIVE CONTROLS ====================

def seedAb1 : AntibodyRecord :=
  { antibodyId := 1, surface := .om3, attackClass := 1, ruleId := 1,
    bftVotes := 4, bftMask := 15, vetoMask := 0, attackDigest := 1001, chainDigest := 2001,
    reproBreach := true, reproKilled := true, nonVacuous := true,
    sha256Ok := true, ed25519Ok := true }

def candAb2 : AntibodyRecord :=
  { antibodyId := 2, surface := .wattcbf, attackClass := 2, ruleId := 32,
    bftVotes := 3, bftMask := 14, vetoMask := 0, attackDigest := 1002, chainDigest := 2002,
    reproBreach := true, reproKilled := true, nonVacuous := true,
    sha256Ok := true, ed25519Ok := true }

def seedCorpus : CorpusState :=
  { epoch := 1, ratchetFloor := 1, records := [seedAb1] }

/-- Positive non-vacuity witness: valid 3-of-4 BFT, 0 veto, valid Ed25519+SHA256,
    and valid replay admits `candAb2`, ratchets epoch/floor, and passes startup replay. -/
theorem pos_witness_admission_and_replay :
    ∃ s', admitAntibody seedCorpus candAb2 1002 true = some s' ∧
      ratchetValid seedCorpus s' = true ∧
      startupReplayPass s'.records (fun _ => false) = true := by
  refine ⟨{ epoch := 2, ratchetFloor := 2, records := [seedAb1, candAb2] }, ?_, ?_, ?_⟩
  · decide
  · decide
  · decide

/-- Negative Control 1: 1-bit Ed25519 signature tamper (`ed25519Ok = false` or `edStrictOk = false`)
    ALWAYS blocks antibody admission. -/
theorem neg_control_1bit_ed25519_tamper :
    admitAntibody seedCorpus { candAb2 with ed25519Ok := false } 1002 true = none ∧
    admitAntibody seedCorpus candAb2 1002 false = none := by
  decide

/-- Negative Control 2: 2-of-4 insufficient BFT quorum (`votes = 2 < 3`) is ALWAYS refused. -/
theorem neg_control_2of4_bft_insufficient :
    bftQuorumSafe 4 1 2 0 = false ∧
    admitAntibody seedCorpus { candAb2 with bftVotes := 2, bftMask := 3 } 1002 true = none := by
  decide

/-- Negative Control 3: 1-of-K Safety Veto overrides even 4-of-4 unanimous strands! -/
theorem neg_control_safety_veto_override :
    bftQuorumSafe 4 1 4 1 = false ∧
    admitAntibody seedCorpus { candAb2 with bftVotes := 4, bftMask := 15, vetoMask := 1 } 1002 true = none := by
  decide

/-- Negative Control 4: Deleting or dropping an existing antibody violates the monotonic ratchet. -/
theorem neg_control_ratchet_deletion :
    let evolved : CorpusState := { epoch := 2, ratchetFloor := 2, records := [seedAb1, candAb2] }
    let deleted : CorpusState := { epoch := 3, ratchetFloor := 2, records := [candAb2] }
    ratchetValid evolved deleted = false := by
  decide

/-- Negative Control 5: Non-reproducible / bogus antibody injection (`reproBreach = false`
    or `reproKilled = false` or `nonVacuous = false`) is ALWAYS refused. -/
theorem neg_control_bogus_nonrepro_injection :
    admitAntibody seedCorpus { candAb2 with reproBreach := false } 1002 true = none ∧
    admitAntibody seedCorpus { candAb2 with reproKilled := false } 1002 true = none ∧
    admitAntibody seedCorpus { candAb2 with nonVacuous := false } 1002 true = none := by
  decide

/-- Negative Control 6: A weakened verifier mutant letting `ruleId = 32` (< 80 W boundary)
    slip through is IMMEDIATELY caught by `startupReplayPass`. -/
theorem neg_control_weakened_mutant_caught :
    let corpus := [seedAb1, candAb2]
    let weakenedGuard := fun r => r == 32
    startupReplayPass corpus weakenedGuard = false := by
  decide

/-- Negative Control 7: Malformed `OMDNA1` magic / truncated / trailing byte / OOB count fails `headerValid`. -/
theorem neg_control_malformed_omdna_header :
    headerValid { magicOk := false, version := 1, recSize := 256, count := 1,
                  epoch := 1, ratchetFlr := 1, actualBytes := 384 } = false ∧
    headerValid { magicOk := true, version := 2, recSize := 256, count := 1,
                  epoch := 1, ratchetFlr := 1, actualBytes := 384 } = false ∧
    headerValid { magicOk := true, version := 1, recSize := 256, count := 1,
                  epoch := 1, ratchetFlr := 1, actualBytes := 385 } = false ∧
    headerValid { magicOk := true, version := 1, recSize := 256, count := 0,
                  epoch := 1, ratchetFlr := 1, actualBytes := 128 } = false := by
  decide

end ProofDnaSoundness

#print axioms ProofDnaSoundness.bft_quorum_overflow_safe
#print axioms ProofDnaSoundness.safety_veto_non_bypassable
#print axioms ProofDnaSoundness.bft_4_1_threshold_sound
#print axioms ProofDnaSoundness.bft_4_strand_quorum_unique
#print axioms ProofDnaSoundness.sigBinding_requires_both
#print axioms ProofDnaSoundness.admit_requires_crypto_bft_veto_replay
#print axioms ProofDnaSoundness.admitAntibody_preserves_ratchet
#print axioms ProofDnaSoundness.evolveTrace_monotonic
#print axioms ProofDnaSoundness.regression_blocker_sound
#print axioms ProofDnaSoundness.weakened_mutant_detected
#print axioms ProofDnaSoundness.pos_witness_admission_and_replay
#print axioms ProofDnaSoundness.neg_control_1bit_ed25519_tamper
#print axioms ProofDnaSoundness.neg_control_2of4_bft_insufficient
#print axioms ProofDnaSoundness.neg_control_safety_veto_override
#print axioms ProofDnaSoundness.neg_control_ratchet_deletion
#print axioms ProofDnaSoundness.neg_control_bogus_nonrepro_injection
#print axioms ProofDnaSoundness.neg_control_weakened_mutant_caught
#print axioms ProofDnaSoundness.neg_control_malformed_omdna_header
