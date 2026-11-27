/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/HiveShield.lean

  Machine-checked Lean 4.36.0 proofs for the Multi-Strand Hive Shield
  (Strands 6..9: Sentinel, Warden, Notary, Arbiter), complementing Strand 5 (Om3MemorySafety.lean)
  and Compiler BFT Strands 0..4 (HelixBFT.lean).

  Model-to-system link:
    - `sentinelDecide` mirrors `seed/helix/hive_shield/strand6_sentinel.om`.
    - `wardenDecide`   mirrors `seed/helix/hive_shield/strand7_warden.om`.
    - `hiveDecide`     mirrors `seed/helix/hive_shield/strand8_notary.om` (Dual-Law Consensus:
                       1-of-K Defense Safety Veto + N >= 3f+1 Compiler BFT Quorum).
    - `arbiterDecide`  mirrors `seed/helix/hive_shield/strand9_arbiter.om`.

  ZERO sorry, ZERO extra axioms (standard Lean 4 axioms only).
-/

namespace HiveShield

-- ==================== STRAND 6 (SENTINEL): PURITY & KMOD QUARANTINE ====================

inductive SentinelVerdict where
  | pass
  | refuseRogueKmod
  | refuseCContam
  | refuseUefiSpi
  | refuseImpureOm
  deriving DecidableEq, Repr

def sentinelDecide (liveKo cFiles maxC uefiTouch impureOm : Nat) : SentinelVerdict :=
  if liveKo > 0 then .refuseRogueKmod
  else if cFiles > maxC then .refuseCContam
  else if uefiTouch > 0 then .refuseUefiSpi
  else if impureOm > 0 then .refuseImpureOm
  else .pass

theorem sentinel_pass_implies_clean (liveKo cFiles maxC uefiTouch impureOm : Nat)
    (h : sentinelDecide liveKo cFiles maxC uefiTouch impureOm = .pass) :
    liveKo = 0 ∧ cFiles ≤ maxC ∧ uefiTouch = 0 ∧ impureOm = 0 := by
  unfold sentinelDecide at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · contradiction
      · split at h
        · contradiction
        · refine ⟨?_, ?_, ?_, ?_⟩ <;> omega

theorem sentinel_always_blocks_live_ko (liveKo cFiles maxC uefiTouch impureOm : Nat)
    (h : liveKo > 0) :
    sentinelDecide liveKo cFiles maxC uefiTouch impureOm = .refuseRogueKmod := by
  unfold sentinelDecide
  simp [h]

-- ==================== STRAND 7 (WARDEN): MULTI-NODE HIVE CBF ====================

inductive HiveNode where
  | sparkGb10
  | pi5
  | macbookAir
  deriving DecidableEq, Repr

structure NodeLimits where
  maxTempMc  : Nat
  maxPowerMw : Nat
  minRamMib  : Nat
  minDiskMib : Nat
  maxLeaseS  : Nat
  deriving DecidableEq, Repr

def nodeLimits : HiveNode → NodeLimits
  | .sparkGb10  => { maxTempMc := 82000, maxPowerMw := 170000, minRamMib := 8192, minDiskMib := 16384, maxLeaseS := 1200 }
  | .pi5        => { maxTempMc := 75000, maxPowerMw := 25000,  minRamMib := 1024, minDiskMib := 4096,  maxLeaseS := 0 }
  | .macbookAir => { maxTempMc := 80000, maxPowerMw := 35000,  minRamMib := 512,  minDiskMib := 10240, maxLeaseS := 0 }

structure Telemetry where
  tempMc    : Nat
  powerMw   : Nat
  ramMib    : Nat
  diskMib   : Nat
  leaseS    : Nat
  proofMask : Nat
  rogueKmod : Nat
  deriving DecidableEq, Repr

inductive WardenVerdict where
  | pass
  | refuseKmod
  | refuseProof
  | refuseThermal
  | refusePower
  | refuseRam
  | refuseDisk
  | refuseLease
  deriving DecidableEq, Repr

def wardenDecide (n : HiveNode) (t : Telemetry) : WardenVerdict :=
  let lim := nodeLimits n
  if t.rogueKmod ≠ 0 then .refuseKmod
  else if t.proofMask ≠ 7 then .refuseProof
  else if t.tempMc > lim.maxTempMc then .refuseThermal
  else if t.powerMw > lim.maxPowerMw then .refusePower
  else if t.ramMib < lim.minRamMib then .refuseRam
  else if t.diskMib < lim.minDiskMib then .refuseDisk
  else if t.leaseS > lim.maxLeaseS then .refuseLease
  else .pass

theorem warden_pass_guarantees_cbf_envelope (n : HiveNode) (t : Telemetry)
    (h : wardenDecide n t = .pass) :
    t.rogueKmod = 0 ∧
    t.proofMask = 7 ∧
    t.tempMc ≤ (nodeLimits n).maxTempMc ∧
    t.powerMw ≤ (nodeLimits n).maxPowerMw ∧
    t.ramMib ≥ (nodeLimits n).minRamMib ∧
    t.diskMib ≥ (nodeLimits n).minDiskMib ∧
    t.leaseS ≤ (nodeLimits n).maxLeaseS := by
  unfold wardenDecide at h
  dsimp only at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · contradiction
      · split at h
        · contradiction
        · split at h
          · contradiction
          · split at h
            · contradiction
            · split at h
              · contradiction
              · refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> omega

theorem warden_blocks_rogue_kmod_even_when_cool :
    wardenDecide .sparkGb10
      { tempMc := 48000, powerMw := 30000, ramMib := 110000, diskMib := 500000,
        leaseS := 60, proofMask := 7, rogueKmod := 1 } = .refuseKmod := by
  decide

-- ==================== STRAND 8 (NOTARY): DUAL-LAW HIVE CONSENSUS ====================

inductive HiveConsensus where
  | admit
  | haltSafetyVeto
  | haltNoQuorum
  deriving DecidableEq, Repr

/-- Dual-Law Consensus:
    1. 1-of-K Defense Veto Law: ANY safety strand veto (`vetoMask ≠ 0`) halts unconditionally.
    2. Compiler BFT Quorum Law: `nComp ≥ 3 * fMax + 1` and `nComp - fMax ≤ cOk ≤ nComp`. -/
def hiveDecide (nComp fMax cOk vetoMask : Nat) : HiveConsensus :=
  if vetoMask ≠ 0 then .haltSafetyVeto
  else if nComp < 3 * fMax + 1 || cOk > nComp || cOk < nComp - fMax then .haltNoQuorum
  else .admit

/-- Even 100% unanimous compiler agreement CANNOT override a single defense strand veto! -/
theorem safety_veto_overrides_unanimous_compilers (nComp fMax vetoMask : Nat)
    (hv : vetoMask ≠ 0) :
    hiveDecide nComp fMax nComp vetoMask = .haltSafetyVeto := by
  unfold hiveDecide
  simp [hv]

/-- Admission proves zero safety vetoes AND valid N >= 3f+1 BFT compiler quorum. -/
theorem hive_admit_sound (nComp fMax cOk vetoMask : Nat)
    (h : hiveDecide nComp fMax cOk vetoMask = .admit) :
    vetoMask = 0 ∧ nComp ≥ 3 * fMax + 1 ∧ cOk ≥ nComp - fMax ∧ cOk ≤ nComp := by
  unfold hiveDecide at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · rename_i hnv hnq
      simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, Nat.not_lt] at hnq
      refine ⟨by omega, hnq.1.1, hnq.2, hnq.1.2⟩

/-- Concrete 7-strand BFT + 5-defense-strand admission check (N=7, f=2, 5/7 ok, veto=0 -> admit). -/
theorem hive_7_2_quorum_admit : hiveDecide 7 2 5 0 = .admit := by decide

/-- Concrete f=3 simultaneous faults on N=7 -> fail-closed haltNoQuorum. -/
theorem hive_7_2_triple_fault_halt : hiveDecide 7 2 4 0 = .haltNoQuorum := by decide

-- ==================== STRAND 9 (ARBITER): ZERO-TRUST MESH GUARD ====================

inductive EndpointClass where
  | wildcard
  | loopback
  | ownedLan
  | ownedTailscale
  | localL2
  | externalPublic
  deriving DecidableEq, Repr

inductive ArbiterVerdict where
  | pass
  | refuseWildcard
  | refuseUnowned
  | refuseUnsafeCmd
  | refuseSshStorm
  | refuseUnsigned
  deriving DecidableEq, Repr

def arbiterBindDecide (ep : EndpointClass) : ArbiterVerdict :=
  match ep with
  | .wildcard => .refuseWildcard
  | .externalPublic => .refuseUnowned
  | _ => .pass

def arbiterCmdDecide (unsafeCmd : Bool) (sshConc : Nat) (signedCap : Bool) : ArbiterVerdict :=
  if sshConc > 4 then .refuseSshStorm
  else if !signedCap then .refuseUnsigned
  else if unsafeCmd then .refuseUnsafeCmd
  else .pass

theorem arbiter_never_allows_wildcard : arbiterBindDecide .wildcard = .refuseWildcard := rfl
theorem arbiter_never_allows_external : arbiterBindDecide .externalPublic = .refuseUnowned := rfl

theorem arbiter_cmd_pass_sound (u : Bool) (c : Nat) (s : Bool)
    (h : arbiterCmdDecide u c s = .pass) :
    u = false ∧ c ≤ 4 ∧ s = true := by
  unfold arbiterCmdDecide at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · contradiction
      · rename_i h1 h2 h3
        refine ⟨?_, ?_, ?_⟩
        · cases u <;> simp at h3 ⊢
        · omega
        · cases s <;> simp at h2 ⊢

end HiveShield

#print axioms HiveShield.sentinel_pass_implies_clean
#print axioms HiveShield.warden_pass_guarantees_cbf_envelope
#print axioms HiveShield.safety_veto_overrides_unanimous_compilers
#print axioms HiveShield.hive_admit_sound
#print axioms HiveShield.arbiter_cmd_pass_sound
