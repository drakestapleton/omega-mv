/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/HelixAntibodies.lean

  Permanent Lean 4 Antibody Theorems for the Proof-Carrying Evolutionary Helix
  Immune System (`seed/helix/immune.om` <-> `seed/helix/monk_check.om`).

  Every attack class probed by the automated adversarial red-teamer is crystallized
  into a permanent theorem proving that the Monk's gate predicate (`monkAccept`)
  mathematically rejects the entire attack class — the stack can never catch the
  same bug twice.

  Antibodies formalized and proved (ZERO sorry, ZERO extra axioms):
    1. `antibody_digest_spoof`: any candidate whose SHA-256 differs from the
       certificate binding is rejected.
    2. `antibody_non_bijection`: any permutation map that drops or duplicates an
       instruction index is rejected.
    3. `antibody_opcode_smuggle`: any candidate that alters a functional SM121
       instruction word (outside the 17-bit scheduling control word w3[9..25]) is rejected.
    4. `antibody_anchor_escape`: any mutation that moves a barrier/control-flow/reconvergence/
       predicate-writer anchor (`BAR.SYNC`, `MEMBAR`, `BSSY`, `BSYNC`, `BRA`, `EXIT`, `ISETP`, `FSETP`) is rejected.
    5. `antibody_dep_inversion`: any mutation that inverts a RAW, WAR, or WAW
       dependency edge `(u < v)` is rejected.
    6. `antibody_hazard_smuggle`: any candidate with nonzero Blackwell SM121
       scoreboard hazards (`hzCount > 0`) is rejected.
    7. `antibody_length_mismatch`: any certificate with mismatched instruction
       count or out-of-range permutation index is rejected.
    8. `antibody_valid_rung_admitted`: positive witness proving `monkAccept` is
       non-vacuous (the identity rung with 0 hazards is accepted).
-/

namespace HelixAntibodies

structure Cert where
  n          : Nat
  refLen     : Nat
  candLen    : Nat
  refHashOk  : Bool
  candHashOk : Bool
  perm       : List Nat          -- cand pc i -> ref pc perm[i]
  funcEq     : Nat → Nat → Bool  -- functional 128-bit mask equality (excluding 17-bit w3[9..25] ctrl)
  isAnchor   : Nat → Bool        -- ref pc is BRA/EXIT/BAR/MEMBAR/BSSY/BSYNC/ISETP/FSETP/mem/pred
  depends    : Nat → Nat → Bool  -- true if ref pc u < v share RAW/WAR/WAW or memory edge
  hzCount    : Nat               -- CFG scoreboard & fixed-latency RAW hazard count in monk_check.om

def allInRange (n : Nat) (l : List Nat) : Bool :=
  l.all (fun x => decide (x < n))

def noDup (l : List Nat) : Bool :=
  l.Nodup

def idxOf (l : List Nat) (target : Nat) : Option Nat :=
  let rec go : List Nat → Nat → Option Nat
    | [], _ => none
    | x :: xs, i => if x == target then some i else go xs (i + 1)
  go l 0

def funcAllOk (c : Cert) : Bool :=
  (List.range c.n).all (fun i =>
    match c.perm[i]? with
    | some r => c.funcEq i r
    | none => false)

def anchorsFixed (c : Cert) : Bool :=
  (List.range c.n).all (fun i =>
    if c.isAnchor i then
      match c.perm[i]? with
      | some r => r == i
      | none => false
    else true)

def depsPreserved (c : Cert) : Bool :=
  (List.range c.n).all (fun u =>
    (List.range c.n).all (fun v =>
      if decide (u < v) && c.depends u v then
        match idxOf c.perm u, idxOf c.perm v with
        | some pu, some pv => decide (pu < pv)
        | _, _ => false
      else true))

/-- Exact decision model of `seed/helix/monk_check.om`. -/
def monkAccept (c : Cert) : Prop :=
  c.refLen = c.n ∧
  c.candLen = c.n ∧
  c.perm.length = c.n ∧
  c.refHashOk = true ∧
  c.candHashOk = true ∧
  allInRange c.n c.perm = true ∧
  c.perm.Nodup ∧
  funcAllOk c = true ∧
  anchorsFixed c = true ∧
  depsPreserved c = true ∧
  c.hzCount = 0

/-- Antibody 1: Spoofed reference or candidate SHA-256 digest is always rejected. -/
theorem antibody_digest_spoof (c : Cert)
    (h : c.refHashOk = false ∨ c.candHashOk = false) :
    ¬ monkAccept c := by
  intro ha
  rcases h with hr | hc
  · rw [ha.2.2.2.1] at hr; cases hr
  · rw [ha.2.2.2.2.1] at hc; cases hc

/-- Antibody 2: Duplicate or non-bijective permutation map is always rejected. -/
theorem antibody_non_bijection (c : Cert) (h : ¬ c.perm.Nodup) :
    ¬ monkAccept c := by
  intro ha
  exact h ha.2.2.2.2.2.2.1

/-- Antibody 3: Functional SM121 opcode/operand smuggling at any PC `i < n` is rejected. -/
theorem antibody_opcode_smuggle (c : Cert) (i r : Nat)
    (hi : i < c.n) (hp : c.perm[i]? = some r) (hbad : c.funcEq i r = false) :
    ¬ monkAccept c := by
  intro ha
  have hfa := ha.2.2.2.2.2.2.2.1
  unfold funcAllOk at hfa
  rw [List.all_eq_true] at hfa
  have hmem : i ∈ List.range c.n := List.mem_range.mpr hi
  have hspec := hfa i hmem
  simp [hp, hbad] at hspec

/-- Antibody 4: Moving any control-flow/barrier anchor `i < n` is rejected. -/
theorem antibody_anchor_escape (c : Cert) (i r : Nat)
    (hi : i < c.n) (hanc : c.isAnchor i = true)
    (hp : c.perm[i]? = some r) (hne : r ≠ i) :
    ¬ monkAccept c := by
  intro ha
  have haf := ha.2.2.2.2.2.2.2.2.1
  unfold anchorsFixed at haf
  rw [List.all_eq_true] at haf
  have hspec := haf i (List.mem_range.mpr hi)
  simp [hanc, hp, hne] at hspec

/-- Antibody 5: Inverting any RAW/WAR/WAW dependency edge `(u < v)` is rejected. -/
theorem antibody_dep_inversion (c : Cert) (u v pu pv : Nat)
    (hu : u < c.n) (hv : v < c.n) (huv : u < v)
    (hdep : c.depends u v = true)
    (hpu : idxOf c.perm u = some pu)
    (hpv : idxOf c.perm v = some pv)
    (hinv : ¬ (pu < pv)) :
    ¬ monkAccept c := by
  intro ha
  have hdp := ha.2.2.2.2.2.2.2.2.2.1
  unfold depsPreserved at hdp
  rw [List.all_eq_true] at hdp
  have hu_spec := hdp u (List.mem_range.mpr hu)
  rw [List.all_eq_true] at hu_spec
  have hv_spec := hu_spec v (List.mem_range.mpr hv)
  simp [huv, hdep, hpu, hpv, hinv] at hv_spec

/-- Antibody 6: Any nonzero SM121 scoreboard hazard (`bw_hazard.om`) is rejected. -/
theorem antibody_hazard_smuggle (c : Cert) (h : c.hzCount > 0) :
    ¬ monkAccept c := by
  intro ha
  have hz := ha.2.2.2.2.2.2.2.2.2.2
  omega

/-- Antibody 7: Any instruction-count truncation/extension or OOB perm index is rejected. -/
theorem antibody_length_mismatch (c : Cert)
    (h : c.refLen ≠ c.n ∨ c.candLen ≠ c.n ∨ c.perm.length ≠ c.n) :
    ¬ monkAccept c := by
  intro ha
  rcases h with h1 | h2 | h3
  · exact h1 ha.1
  · exact h2 ha.2.1
  · exact h3 ha.2.2.1

/-- Positive non-vacuity witness: a clean 2-instruction independent swap passes `monkAccept`. -/
def validSwapCert : Cert :=
  { n := 2, refLen := 2, candLen := 2,
    refHashOk := true, candHashOk := true,
    perm := [1, 0],
    funcEq := fun _ _ => true,
    isAnchor := fun _ => false,
    depends := fun _ _ => false,
    hzCount := 0 }

theorem antibody_valid_rung_admitted : monkAccept validSwapCert := by
  refine ⟨rfl, rfl, rfl, rfl, rfl, rfl, ?_, rfl, rfl, rfl, rfl⟩
  decide

-- ==================== PHASE 2 UOR-GPU AUTHORITY & LAUNCH-GATE ANTIBODIES ====================
-- Formalizes the manual uor-gpu pass-1/pass-2 audit checks into permanent Lean 4 antibodies
-- mirrored in `seed/helix/dual_checker.om` and attacked by `seed/helix/immune.om`.

structure LaunchGateEnvelope where
  sigCanonical  : Bool  -- RFC 8032 canonical S < L and P0 non-smuggled signature check
  declaredLen   : Nat   -- declared bundle/envelope byte length
  actualLen     : Nat   -- actual observed byte length (catches trailing-byte smuggling)
  qmdAddr       : Nat   -- Blackwell QMD v05.00 GPU VA (must be 256-byte aligned)
  qmdBytes      : Nat   -- QMD v05.00 descriptor size (must be 384 bytes)
  capGeneration : Nat   -- capability handle generation (must be > 0; zero-gen caps forbidden)

def launchGateAccept (e : LaunchGateEnvelope) : Prop :=
  e.sigCanonical = true ∧
  e.actualLen = e.declaredLen ∧
  e.qmdAddr % 256 = 0 ∧
  e.qmdBytes = 384 ∧
  e.capGeneration > 0

/-- Antibody 8: Smuggled P0 / non-canonical signature bytes are always rejected. -/
theorem antibody_p0_sig_smuggle (e : LaunchGateEnvelope) (h : e.sigCanonical = false) :
    ¬ launchGateAccept e := by
  intro ha; rw [ha.1] at h; cases h

/-- Antibody 9: Trailing-byte payloads past declared envelope length are always rejected. -/
theorem antibody_trailing_bytes (e : LaunchGateEnvelope) (h : e.actualLen > e.declaredLen) :
    ¬ launchGateAccept e := by
  intro ha; have := ha.2.1; omega

/-- Antibody 10: Misaligned Blackwell QMD v05.00 (addr % 256 ≠ 0 or size ≠ 384) is always rejected. -/
theorem antibody_misaligned_qmd (e : LaunchGateEnvelope)
    (h : e.qmdAddr % 256 ≠ 0 ∨ e.qmdBytes ≠ 384) :
    ¬ launchGateAccept e := by
  intro ha
  rcases h with h1 | h2
  · exact h1 ha.2.2.1
  · exact h2 ha.2.2.2.1

/-- Antibody 11: Zero-generation capability tokens (`gen = 0`) are always rejected. -/
theorem antibody_zero_gen_cap (e : LaunchGateEnvelope) (h : e.capGeneration = 0) :
    ¬ launchGateAccept e := by
  intro ha; have := ha.2.2.2.2; omega

/-- Positive non-vacuity witness for `launchGateAccept`. -/
def validLaunchEnv : LaunchGateEnvelope :=
  { sigCanonical := true, declaredLen := 512, actualLen := 512,
    qmdAddr := 4096, qmdBytes := 384, capGeneration := 1 }

theorem antibody_valid_launch_admitted : launchGateAccept validLaunchEnv := by
  refine ⟨rfl, rfl, rfl, rfl, ?_⟩
  decide

-- ==================== SILICON-VERIFIED SM121 SCHEDULING ANTIBODIES #13-#16 ====================
-- Formalizes the 4 SM121 microarchitectural & boundary laws enforced in lockstep across
-- `seed/helix/helix_jit.om`, `seed/helix/monk_check.om`, `seed/helix/arboris_predator.om`,
-- and probed by attacks 9..12 of `seed/helix/immune.om`:
--   13. `antibody_bb_leader_escape`: basic-block leaders (pc=0, BRA targets, BRA fall-throughs) are pinned.
--   14. `antibody_raw_floor_6`: fixed-latency ALU RAW spans (distance <= 16) enforce rawFloor = 6.
--   15. `antibody_i2fp_stall_shave`: I2FP/I2F (op 581, nm=29) stalls are never shaved below min(ref, 6).
--   16. `antibody_anchor_consumer_raw`: fixed-latency RAW spans terminating at an anchor consumer
--       (LDG/STG/LDS/STS/ISETP/FSETP/BRA/EXIT) cannot violate the 6-cycle RAW floor.

structure Sm121Schedule where
  n           : Nat
  perm        : List Nat
  isBBLeader  : Nat → Bool      -- pc=0, BRA target, or BRA fall-through
  isAnchor    : Nat → Bool      -- all non-swappable anchors (includes all BB leaders)
  isI2fp      : Nat → Bool      -- true iff instruction is I2FP/I2F (op 581, nm == 29)
  refStall    : Nat → Nat       -- reference stall cycles at ref pc
  candStall   : Nat → Nat       -- candidate stall cycles at inv[ref pc]
  rawSpan     : Nat → Nat → Bool -- fixed-latency RAW consumer or block boundary within distance 16
  refSpanCyc  : Nat → Nat → Nat -- cumulative ref stall cycles across [u, v) or [u, v+1)
  candSpanCyc : Nat → Nat → Nat -- cumulative cand stall cycles across mapped span

def sm121Accept (s : Sm121Schedule) : Prop :=
  (∀ i, i < s.n → s.isBBLeader i = true → s.isAnchor i = true) ∧
  (∀ i, i < s.n → s.isAnchor i = true → s.perm[i]? = some i) ∧
  (∀ u v, u < s.n → v < s.n → u < v → v - u ≤ 16 → s.rawSpan u v = true →
    s.candSpanCyc u v ≥ min (s.refSpanCyc u v) 6) ∧
  (∀ u, u < s.n → s.isI2fp u = true → s.candStall u ≥ min (s.refStall u) 6)

/-- Antibody 13: Moving any basic-block leader (pc=0, BRA target, BRA fall-through) is always rejected. -/
theorem antibody_bb_leader_escape (s : Sm121Schedule) (i r : Nat)
    (hi : i < s.n) (hbb : s.isBBLeader i = true)
    (hp : s.perm[i]? = some r) (hne : r ≠ i) :
    ¬ sm121Accept s := by
  intro ha
  have hanc : s.isAnchor i = true := ha.1 i hi hbb
  have hfix : s.perm[i]? = some i := ha.2.1 i hi hanc
  rw [hp] at hfix
  exact hne (Option.some.inj hfix)

/-- Antibody 14: Shaving any fixed-latency RAW span within distance 16 below rawFloor=6 is always rejected. -/
theorem antibody_raw_floor_6 (s : Sm121Schedule) (u v : Nat)
    (hu : u < s.n) (hv : v < s.n) (huv : u < v) (hdist : v - u ≤ 16)
    (hraw : s.rawSpan u v = true)
    (hshave : s.candSpanCyc u v < min (s.refSpanCyc u v) 6) :
    ¬ sm121Accept s := by
  intro ha
  have hge := ha.2.2.1 u v hu hv huv hdist hraw
  omega

/-- Antibody 15: Shaving any I2FP/I2F (op 581, nm=29) stall below min(ref_stall, 6) is always rejected. -/
theorem antibody_i2fp_stall_shave (s : Sm121Schedule) (u : Nat)
    (hu : u < s.n) (hi2f : s.isI2fp u = true)
    (hshave : s.candStall u < min (s.refStall u) 6) :
    ¬ sm121Accept s := by
  intro ha
  have hge := ha.2.2.2 u hu hi2f
  omega

/-- Antibody 16: Violating a fixed-latency RAW span into an anchor consumer (LDG/STG/ISETP/BRA/EXIT) is rejected. -/
theorem antibody_anchor_consumer_raw (s : Sm121Schedule) (u v : Nat)
    (hu : u < s.n) (hv : v < s.n) (huv : u < v) (hdist : v - u ≤ 16)
    (_hanc : s.isAnchor v = true) (hraw : s.rawSpan u v = true)
    (hshave : s.candSpanCyc u v < min (s.refSpanCyc u v) 6) :
    ¬ sm121Accept s := by
  intro ha
  have hge := ha.2.2.1 u v hu hv huv hdist hraw
  omega

/-- Positive non-vacuity witness for Antibodies #13-#16 (`sm121Accept`). -/
def validSm121Sched : Sm121Schedule :=
  { n := 2,
    perm := [0, 1],
    isBBLeader := fun i => i == 0,
    isAnchor := fun _ => true,
    isI2fp := fun i => i == 0,
    refStall := fun _ => 4,
    candStall := fun _ => 4,
    rawSpan := fun u v => u == 0 && v == 1,
    refSpanCyc := fun _ _ => 6,
    candSpanCyc := fun _ _ => 6 }

theorem antibody_sm121_valid_admitted : sm121Accept validSm121Sched := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro i _ _; rfl
  · intro i hi _
    match i, hi with
    | 0, _ => rfl
    | 1, _ => rfl
  · intro u v _ _ _ _ _; dsimp [validSm121Sched]; omega
  · intro u _ _; dsimp [validSm121Sched]; omega

#print axioms antibody_digest_spoof
#print axioms antibody_non_bijection
#print axioms antibody_opcode_smuggle
#print axioms antibody_anchor_escape
#print axioms antibody_dep_inversion
#print axioms antibody_hazard_smuggle
#print axioms antibody_length_mismatch
#print axioms antibody_valid_rung_admitted
#print axioms antibody_p0_sig_smuggle
#print axioms antibody_trailing_bytes
#print axioms antibody_misaligned_qmd
#print axioms antibody_zero_gen_cap
#print axioms antibody_valid_launch_admitted
#print axioms antibody_bb_leader_escape
#print axioms antibody_raw_floor_6
#print axioms antibody_i2fp_stall_shave
#print axioms antibody_anchor_consumer_raw
#print axioms antibody_sm121_valid_admitted

end HelixAntibodies
