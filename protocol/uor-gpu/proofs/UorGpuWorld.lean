-- SPDX-License-Identifier: Apache-2.0
-- Machine-checked Lean 4 specification for hologram:gpu/omega-om2@1 (UOR-GPU-1).
-- Proves:
--   1. GPU vecadd kernel index bounds safety and algebraic commutativity (+ negative control).
--   2. UOR-GPU fail-closed admission: mandatory Lean 4 P2 proof, exact digest match,
--      and live capability right (+ negative controls).
-- Zero `sorry`, standard axioms only.

namespace UorGpuWorld

/-- 1. GPU Kernel Model: bounded elementwise vector addition (SM121 / SPIR-V). -/
def vecaddStep (n tid : Nat) (a b out : Nat → Nat) : Nat → Nat :=
  if tid < n then
    fun i => if i = tid then a tid + b tid else out i
  else
    out

theorem vecadd_in_bounds_writes_sum (n tid : Nat) (a b out : Nat → Nat) (h : tid < n) :
    vecaddStep n tid a b out tid = a tid + b tid := by
  simp [vecaddStep, h]

theorem vecadd_preserves_other_indices (n tid i : Nat) (a b out : Nat → Nat) (hne : i ≠ tid) :
    vecaddStep n tid a b out i = out i := by
  unfold vecaddStep
  split
  · simp [hne]
  · rfl

theorem vecadd_oob_noop (n tid i : Nat) (a b out : Nat → Nat) (hoob : ¬ tid < n) :
    vecaddStep n tid a b out i = out i := by
  simp [vecaddStep, hoob]

theorem vecadd_comm (n tid i : Nat) (a b out : Nat → Nat) :
    vecaddStep n tid a b out i = vecaddStep n tid b a out i := by
  unfold vecaddStep
  split
  · dsimp
    split
    · exact Nat.add_comm (a tid) (b tid)
    · rfl
  · rfl

/-- Negative control: an unguarded kernel writes out-of-bounds at tid = n. -/
def brokenVecaddStep (tid : Nat) (a b out : Nat → Nat) : Nat → Nat :=
  fun i => if i = tid then a tid + b tid else out i

theorem broken_vecadd_violates_oob :
    ∃ n tid a b out, ¬ tid < n ∧ brokenVecaddStep tid a b out tid ≠ out tid := by
  refine ⟨4, 4, (fun _ => 1), (fun _ => 1), (fun _ => 0), by decide, by decide⟩

/-- 2. UOR-GPU-1 Bundle & Mandatory Lean 4 P2 Admission State Machine. -/
structure BundleVerdict where
  payloadOk : Bool
  uorIdOk : Bool
  holoBlake3Ok : Bool
  omcPinOk : Bool
  level : Nat           -- 0=P0, 1=P1, 2=P2, 3=P3
  hasLeanProof : Bool   -- mandatory for P2/P3
  hasReplay : Bool      -- mandatory for P3
  replayMatch : Bool    -- golden CPU/silicon oracle matches replay_sha256
  hasSig : Bool         -- Ed25519 attestation present
  sigValid : Bool       -- RFC 8032 Ed25519 verification result
  deriving DecidableEq

structure CapGrant where
  live : Bool
  epochMatch : Bool
  notExpired : Bool
  subjectMatch : Bool
  resourceMatch : Bool
  hasEffectRight : Bool
  deriving DecidableEq

def verifyPolicy (minLevel : Nat) (v : BundleVerdict) : Bool :=
  v.payloadOk && v.uorIdOk && v.holoBlake3Ok && v.omcPinOk &&
  decide (minLevel ≤ v.level) &&
  (if minLevel ≥ 2 then v.hasLeanProof else true) &&
  (if minLevel ≥ 3 then v.hasReplay && v.replayMatch else true) &&
  (if v.hasSig then v.sigValid else true)

def capAdmit (g : CapGrant) : Bool :=
  g.live && g.epochMatch && g.notExpired && g.subjectMatch && g.resourceMatch && g.hasEffectRight

/-- Default Prism GPU admission enforces minimum level P2 (mandatory Lean 4 proof). -/
def gpuAdmitDefault (v : BundleVerdict) (g : CapGrant) : Bool :=
  verifyPolicy 2 v && capAdmit g

theorem admit_requires_lean_proof (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) : v.hasLeanProof = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hlp : v.hasLeanProof
  · simp [hlp] at h
  · rfl

theorem admit_requires_intact_digests (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.payloadOk = true ∧ v.uorIdOk = true ∧ v.holoBlake3Ok = true ∧ v.omcPinOk = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hp : v.payloadOk <;> cases hu : v.uorIdOk <;> cases hb : v.holoBlake3Ok <;> cases ho : v.omcPinOk <;>
    simp [hp, hu, hb, ho] at h
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem admit_requires_live_effect_cap (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    g.live = true ∧ g.hasEffectRight = true ∧ g.resourceMatch = true := by
  unfold gpuAdmitDefault capAdmit at h
  cases hl : g.live <;> cases he : g.hasEffectRight <;> cases hr : g.resourceMatch <;>
    simp [hl, he, hr] at h
  exact ⟨rfl, rfl, rfl⟩

theorem admit_requires_valid_sig_when_signed (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) (hs : v.hasSig = true) : v.sigValid = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hv : v.sigValid
  · simp [hs, hv] at h
  · rfl

theorem bad_sig_refused (v : BundleVerdict) (g : CapGrant)
    (hs : v.hasSig = true) (hb : v.sigValid = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hs, hb]

theorem p3_replay_mismatch_refused (v : BundleVerdict)
    (hrm : v.replayMatch = false) : verifyPolicy 3 v = false := by
  simp [verifyPolicy, hrm]

theorem missing_lean_proof_refused (v : BundleVerdict) (g : CapGrant)
    (hno : v.hasLeanProof = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hno]

theorem tampered_payload_refused (v : BundleVerdict) (g : CapGrant)
    (htamp : v.payloadOk = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, htamp]

theorem revoked_cap_refused (v : BundleVerdict) (g : CapGrant)
    (hrev : g.live = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, capAdmit, hrev]

#print axioms vecadd_in_bounds_writes_sum
#print axioms vecadd_preserves_other_indices
#print axioms vecadd_oob_noop
#print axioms vecadd_comm
#print axioms broken_vecadd_violates_oob
#print axioms admit_requires_lean_proof
#print axioms admit_requires_intact_digests
#print axioms admit_requires_live_effect_cap
#print axioms admit_requires_valid_sig_when_signed
#print axioms bad_sig_refused
#print axioms p3_replay_mismatch_refused
#print axioms missing_lean_proof_refused
#print axioms tampered_payload_refused
#print axioms revoked_cap_refused

end UorGpuWorld
