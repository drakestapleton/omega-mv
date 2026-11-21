-- SPDX-License-Identifier: Apache-2.0
-- Machine-checked Lean 4 specification for hologram:gpu/omega-om2@1 (UOR-GPU-1).
-- Scope (honest boundary):
--   1. Proves index bounds safety and algebraic commutativity of the `Nat` vecadd kernel
--      model (+ negative control). Does NOT verify binary equivalence of emitted SM121 SASS
--      or SPIR-V machine code.
--   2. Proves fail-closed properties of the UOR-GPU-1 policy and admission state machine
--      matching protocol/uor-gpu/{canonical,verify,gate}.om:
--      local trust anchors, intact digests, non-empty payload, valid launch geometry,
--      pinned Lean 4 proof digest, locally trusted RFC 8032 Ed25519 signer, no unsigned
--      level elevation, no smuggled signature bytes, and authority-signed live capability
--      grants with non-zero generation and non-zero unexpired lease.
-- Zero `sorry`, standard axioms only.

namespace UorGpuWorld

/-- 1. GPU Kernel Model: bounded elementwise vector addition (algebraic Nat model). -/
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

/-- 2. UOR-GPU-1 Bundle & Fail-Closed Admission State Machine (matches verify.om + gate.om). -/
structure BundleVerdict where
  anchorsValid : Bool     -- local UORTRST1 anchors well-formed, signer != authority
  payloadNonEmpty : Bool  -- len pay > 0 and matches header payload_len
  blockXValid : Bool      -- 1 <= block_x <= 1024
  payloadOk : Bool        -- payload SHA-256 matches
  uorIdOk : Bool          -- uor_id SHA-256 matches header[0..224)
  holoBlake3Ok : Bool     -- holo BLAKE3 matches header[0..256) || payload
  omcPinOk : Bool         -- omc_sha256 equals verifier anchor pin
  level : Nat             -- claimed level: 0=P0, 1=P1, 2=P2, 3=P3
  hasLeanProof : Bool     -- lean_proof_sha256 != 0
  leanProofPinned : Bool  -- lean_proof_sha256 equals verifier anchor pin
  hasReplay : Bool        -- replay_sha256 != 0
  replayMatch : Bool      -- golden replay digest equals replay_sha256
  hasSig : Bool           -- signer_pubkey != 0
  sigSlotZero : Bool      -- attest_sig == 0 (required when hasSig = false)
  signerTrusted : Bool    -- signer_pubkey is in local trust anchors
  sigValid : Bool         -- RFC 8032 Ed25519 verification result
  deriving DecidableEq

structure CapGrant where
  grantSigValid : Bool    -- RFC 8032 Ed25519 signature by anchors' non-zero authority key
  live : Bool             -- state == UOR_CAP_LIVE (1)
  genNonZero : Bool       -- generation != 0
  genMatch : Bool         -- generation == expected_gen
  epochMatch : Bool       -- epoch == cur_epoch
  leaseNonZero : Bool     -- lease_expiry != 0 (no immortal offline grants)
  notExpired : Bool       -- cur_clock < lease_expiry
  subjectMatch : Bool     -- subject == req.subject
  resourceMatch : Bool    -- resource == req.resource
  hasEffectRight : Bool   -- (rights & RX_RIGHT_EFFECT) != 0
  deriving DecidableEq

def verifyPolicy (minLevel : Nat) (v : BundleVerdict) : Bool :=
  v.anchorsValid &&
  v.payloadNonEmpty && v.blockXValid &&
  v.payloadOk && v.uorIdOk && v.holoBlake3Ok && v.omcPinOk &&
  decide (v.level ≤ 3) &&
  decide (minLevel ≤ v.level) &&
  (if minLevel ≥ 2 then v.hasLeanProof && v.leanProofPinned else true) &&
  (if minLevel ≥ 3 then v.hasReplay && v.replayMatch else true) &&
  (if v.hasSig then
      v.signerTrusted && v.sigValid
   else
      decide (minLevel = 0) && decide (v.level = 0) && v.sigSlotZero)

def capAdmit (g : CapGrant) : Bool :=
  g.grantSigValid && g.live && g.genNonZero && g.genMatch && g.epochMatch &&
  g.leaseNonZero && g.notExpired && g.subjectMatch && g.resourceMatch && g.hasEffectRight

/-- Default Prism GPU admission enforces minimum level P2 + authority-signed live capability. -/
def gpuAdmitDefault (v : BundleVerdict) (g : CapGrant) : Bool :=
  verifyPolicy 2 v && capAdmit g

theorem admit_requires_pinned_lean_proof (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.hasLeanProof = true ∧ v.leanProofPinned = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hlp : v.hasLeanProof <;> cases hpin : v.leanProofPinned <;> simp [hlp, hpin] at h
  exact ⟨rfl, rfl⟩

theorem admit_requires_intact_digests (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.payloadNonEmpty = true ∧ v.blockXValid = true ∧
    v.payloadOk = true ∧ v.uorIdOk = true ∧ v.holoBlake3Ok = true ∧ v.omcPinOk = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hne : v.payloadNonEmpty <;> cases hbx : v.blockXValid <;>
    cases hp : v.payloadOk <;> cases hu : v.uorIdOk <;>
    cases hb : v.holoBlake3Ok <;> cases ho : v.omcPinOk <;>
    simp [hne, hbx, hp, hu, hb, ho] at h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem admit_requires_trusted_valid_sig (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.anchorsValid = true ∧ v.hasSig = true ∧ v.signerTrusted = true ∧ v.sigValid = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases ha : v.anchorsValid <;> cases hs : v.hasSig <;>
    cases ht : v.signerTrusted <;> cases hv : v.sigValid <;>
    simp [ha, hs, ht, hv] at h
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem admit_requires_authority_live_cap (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    g.grantSigValid = true ∧ g.live = true ∧ g.genNonZero = true ∧
    g.leaseNonZero = true ∧ g.notExpired = true ∧
    g.hasEffectRight = true ∧ g.resourceMatch = true := by
  unfold gpuAdmitDefault capAdmit at h
  cases hgs : g.grantSigValid <;> cases hl : g.live <;> cases hgz : g.genNonZero <;>
    cases hlz : g.leaseNonZero <;> cases hex : g.notExpired <;>
    cases he : g.hasEffectRight <;> cases hr : g.resourceMatch <;>
    simp [hgs, hl, hgz, hlz, hex, he, hr] at h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem unsigned_p2_refused (v : BundleVerdict) (g : CapGrant)
    (hu : v.hasSig = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hu]

theorem unsigned_nonzero_claim_refused (v : BundleVerdict)
    (hu : v.hasSig = false) (hl : v.level ≠ 0) : verifyPolicy 0 v = false := by
  simp [verifyPolicy, hu, hl]

theorem unsigned_smuggled_sig_refused (v : BundleVerdict)
    (hu : v.hasSig = false) (hsm : v.sigSlotZero = false) : verifyPolicy 0 v = false := by
  simp [verifyPolicy, hu, hsm]

theorem untrusted_signer_refused (v : BundleVerdict) (minLevel : Nat)
    (hs : v.hasSig = true) (hut : v.signerTrusted = false) : verifyPolicy minLevel v = false := by
  simp [verifyPolicy, hs, hut]

theorem bad_sig_refused (v : BundleVerdict) (g : CapGrant)
    (hs : v.hasSig = true) (hb : v.sigValid = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hs, hb]

theorem unpinned_lean_proof_refused (v : BundleVerdict) (g : CapGrant)
    (hup : v.leanProofPinned = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hup]

theorem p3_replay_mismatch_refused (v : BundleVerdict)
    (hrm : v.replayMatch = false) : verifyPolicy 3 v = false := by
  simp [verifyPolicy, hrm]

theorem missing_lean_proof_refused (v : BundleVerdict) (g : CapGrant)
    (hno : v.hasLeanProof = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hno]

theorem tampered_payload_refused (v : BundleVerdict) (g : CapGrant)
    (htamp : v.payloadOk = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, htamp]

theorem forged_grant_refused (v : BundleVerdict) (g : CapGrant)
    (hfg : g.grantSigValid = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, capAdmit, hfg]

theorem revoked_cap_refused (v : BundleVerdict) (g : CapGrant)
    (hrev : g.live = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, capAdmit, hrev]

theorem zero_gen_cap_refused (v : BundleVerdict) (g : CapGrant)
    (hzg : g.genNonZero = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, capAdmit, hzg]

theorem zero_lease_cap_refused (v : BundleVerdict) (g : CapGrant)
    (hzl : g.leaseNonZero = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, capAdmit, hzl]

#print axioms vecadd_in_bounds_writes_sum
#print axioms vecadd_preserves_other_indices
#print axioms vecadd_oob_noop
#print axioms vecadd_comm
#print axioms broken_vecadd_violates_oob
#print axioms admit_requires_pinned_lean_proof
#print axioms admit_requires_intact_digests
#print axioms admit_requires_trusted_valid_sig
#print axioms admit_requires_authority_live_cap
#print axioms unsigned_p2_refused
#print axioms unsigned_nonzero_claim_refused
#print axioms unsigned_smuggled_sig_refused
#print axioms untrusted_signer_refused
#print axioms unpinned_lean_proof_refused
#print axioms forged_grant_refused
#print axioms zero_gen_cap_refused
#print axioms zero_lease_cap_refused

end UorGpuWorld
