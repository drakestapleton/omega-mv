-- SPDX-License-Identifier: Apache-2.0
-- Machine-checked Lean 4 specification for hologram:gpu/omega-om2@1 (UOR-GPU-1).
-- Core Lean 4 only (no Mathlib), zero `sorry`, zero `native_decide`, standard axioms only.
--
-- Model-to-system link (repo omega-mv):
--   * protocol/uor-gpu/canonical.om   — 384-byte UOR-GPU-1 header, u32 LE codec, SHA-256 + BLAKE3 seal,
--                                       reason codes 0..20.
--   * protocol/uor-gpu/payload_vm.om  — 896-byte SM121 payload (512B SASS + 384B QMD v05.00),
--                                       SKEDCHECK05 checks, SM121 SASS decoder, canary-guarded replay.
--   * protocol/uor-gpu/verify.om      — UORTRST1 local trust anchors (104B + 32*k keys, auth != signer),
--                                       P0..P3 policy order, honest policy level & signature rules.
--   * protocol/uor-gpu/gate.om        — Pre-dispatch admission gate (P2 + authority-signed live grant).
--   * om/gpu/bw_vecadd.om             — 512B Blackwell SM121 u32 vecadd machine code.
--   * om/gpu/bw_qmd.om                — 96-word (384B) QMD v05.00 packer, smem_cfg_for, bw_qmd_verify.
--
-- Theorem family alignment:
--   * Recent AIEN Lean 4 proofs (AienGpuGb20b, AienReceipt, AienCap, NgA64Vec, CodebookProof,
--     TicketLock, interplane-forge Ledger, BtWaveProofs): wire-layout contiguity/disjointness,
--     BitVec round-trip/injectivity/opcode-disjointness, multi-thread loop + canary preservation,
--     collision-resistant hash tamper evidence, trust separation + check-order equivalence +
--     monotonicity, inductive lifecycle reachability, and load-bearing negative controls.
--   * UOR Foundation / Prism group (uor-framework, LexLean, PrismPM, uor-comms, mnist):
--     Z/(2^32)Z ring critical identity & involutions, contract-satisfaction theorem,
--     domain-separated framed content IDs, refusal-reason soundness/completeness, and
--     PrismPM Foundation.Proof.V1.Statement axiom-policy & replay verdict enforcement.
--
-- Honest scope boundary:
--   Proves the explicit model below. Does NOT prove hardware equivalence on physical GB10 silicon
--   (hardware status: NOT_RUN).

namespace UorGpuWorld

/-! ## 1. Wire-Layout Contiguity, Disjointness, and Exact Tiling -/

/-- Interval `[lo, hi)` disjointness check (matches AienGpuGb20b / AienReceipt). -/
def ivDisjoint (a b : Nat × Nat) : Bool :=
  a.2 ≤ b.1 || b.2 ≤ a.1

def allPairwiseDisjoint : List (Nat × Nat) → Bool
  | [] => true
  | x :: xs => xs.all (ivDisjoint x) && allPairwiseDisjoint xs

def allValidIn (bound : Nat) (fs : List (Nat × Nat)) : Bool :=
  fs.all (fun p => p.1 < p.2 && p.2 ≤ bound)

/-- Contiguous `(offset, width)` tiling checker from starting offset `n`. -/
def contiguousFrom : Nat → List (Nat × Nat) → Option Nat
  | n, [] => some n
  | n, (o, w) :: rest => if o == n && 0 < w then contiguousFrom (n + w) rest else none

def toIntervals (ow : List (Nat × Nat)) : List (Nat × Nat) :=
  ow.map (fun p => (p.1, p.1 + p.2))

/-- Canonical 384-byte UOR-GPU-1 header fields (canonical.om + README.md). -/
def uorHdrLayout : List (Nat × Nat) :=
  [ (0, 8),    -- magic "UORGPU1\0"
    (8, 4),    -- version (1)
    (12, 4),   -- isa (1=SM121, 2=SPIRV)
    (16, 4),   -- math (1=RN, 2=FTZ)
    (20, 4),   -- claimed level (0..3)
    (24, 4),   -- payload_len
    (28, 4),   -- block_x (1..1024)
    (32, 32),  -- omc_sha256
    (64, 32),  -- source_sha256
    (96, 32),  -- payload_sha256
    (128, 32), -- lean_proof_sha256
    (160, 32), -- replay_sha256
    (192, 32), -- mlbom_sha256
    (224, 32), -- uor_id_sha256  = SHA-256(hdr[0..224))
    (256, 32), -- holo_blake3    = BLAKE3(hdr[0..256) || payload)
    (288, 32), -- signer_pubkey
    (320, 64)  -- attest_sig     = Ed25519(hdr[224..288))
  ]

/-- Local trust anchors UORTRST1 fixed prefix (104 bytes before 1..16 x 32B signer keys). -/
def uorTrstBaseLayout : List (Nat × Nat) :=
  [ (0, 8),   -- magic "UORTRST1"
    (8, 32),  -- omc_sha256 pin
    (40, 32), -- lean_proof_sha256 pin
    (72, 32)  -- authority_pubkey
  ]

/-- Authority-signed capability grant wire layout (128 bytes: 8 x u64 LE + 64B Ed25519 sig). -/
def uorGrantLayout : List (Nat × Nat) :=
  [ (0, 8), (8, 8), (16, 8), (24, 8), (32, 8), (40, 8), (48, 8), (56, 8), (64, 64) ]

/-- SM121 payload layout: 512B SASS machine code + 384B (96 x u32) QMD v05.00 = 896 bytes. -/
def sm121PayloadLayout : List (Nat × Nat) :=
  [ (0, 512), (512, 384) ]

theorem uorHdrLayout_tiles_384 :
    contiguousFrom 0 uorHdrLayout = some 384 ∧
    allPairwiseDisjoint (toIntervals uorHdrLayout) = true ∧
    allValidIn 384 (toIntervals uorHdrLayout) = true := by
  decide

theorem uorTrstBaseLayout_tiles_104 :
    contiguousFrom 0 uorTrstBaseLayout = some 104 ∧
    allPairwiseDisjoint (toIntervals uorTrstBaseLayout) = true ∧
    allValidIn 104 (toIntervals uorTrstBaseLayout) = true := by
  decide

theorem uorTrst_size_bounds (k : Nat) (h1 : 1 ≤ k) (h16 : k ≤ 16) :
    136 ≤ 104 + 32 * k ∧ 104 + 32 * k ≤ 616 ∧ (104 + 32 * k - 104) % 32 = 0 := by
  omega

theorem uorGrantLayout_tiles_128 :
    contiguousFrom 0 uorGrantLayout = some 128 ∧
    allPairwiseDisjoint (toIntervals uorGrantLayout) = true ∧
    allValidIn 128 (toIntervals uorGrantLayout) = true := by
  decide

theorem sm121PayloadLayout_tiles_896 :
    contiguousFrom 0 sm121PayloadLayout = some 896 ∧
    allPairwiseDisjoint (toIntervals sm121PayloadLayout) = true ∧
    allValidIn 896 (toIntervals sm121PayloadLayout) = true := by
  decide

/-- Negative control: overlapping header fields are caught by `allPairwiseDisjoint` and `contiguousFrom`. -/
def brokenOverlapLayout : List (Nat × Nat) := [(0, 8), (6, 4), (10, 4)]

theorem neg_overlapping_layout_detected :
    allPairwiseDisjoint (toIntervals brokenOverlapLayout) = false ∧
    contiguousFrom 0 brokenOverlapLayout = none := by
  decide

/-! ## 2. Bit-Exact `BitVec` Encodings, Round-Trips, Injectivity & Opcode Disjointness -/

/-- Little-endian 32-bit pack/unpack (matches `uor_put_u32` / `uor_get_u32` in canonical.om). -/
def le32Pack (b0 b1 b2 b3 : BitVec 8) : BitVec 32 :=
  b0.zeroExtend 32 ||| (b1.zeroExtend 32 <<< 8) ||| (b2.zeroExtend 32 <<< 16) ||| (b3.zeroExtend 32 <<< 24)

def le32Byte (w : BitVec 32) (i : Fin 4) : BitVec 8 :=
  match i with
  | ⟨0, _⟩ => w.extractLsb' 0 8
  | ⟨1, _⟩ => w.extractLsb' 8 8
  | ⟨2, _⟩ => w.extractLsb' 16 8
  | ⟨3, _⟩ => w.extractLsb' 24 8

theorem le32_byte_roundtrip (b0 b1 b2 b3 : BitVec 8) :
    le32Byte (le32Pack b0 b1 b2 b3) ⟨0, by decide⟩ = b0 ∧
    le32Byte (le32Pack b0 b1 b2 b3) ⟨1, by decide⟩ = b1 ∧
    le32Byte (le32Pack b0 b1 b2 b3) ⟨2, by decide⟩ = b2 ∧
    le32Byte (le32Pack b0 b1 b2 b3) ⟨3, by decide⟩ = b3 := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [le32Byte, le32Pack, hi, show i < 32 by omega,
          show i < 16 by omega, show i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [le32Byte, le32Pack, hi, show 8 + i < 32 by omega,
          show ¬(8 + i < 8) by omega, show 8 + i < 16 by omega, show 8 + i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have h0 : b0.getLsbD (16 + i) = false := BitVec.getLsbD_of_ge b0 (16 + i) (by omega)
    have h1 : b1.getLsbD (16 + i - 8) = false := BitVec.getLsbD_of_ge b1 (16 + i - 8) (by omega)
    simp [le32Byte, le32Pack, hi, h0, h1, show 16 + i < 32 by omega,
          show ¬(16 + i < 8) by omega, show ¬(16 + i < 16) by omega, show 16 + i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have h0 : b0.getLsbD (24 + i) = false := BitVec.getLsbD_of_ge b0 (24 + i) (by omega)
    have h1 : b1.getLsbD (24 + i - 8) = false := BitVec.getLsbD_of_ge b1 (24 + i - 8) (by omega)
    have h2 : b2.getLsbD (24 + i - 16) = false := BitVec.getLsbD_of_ge b2 (24 + i - 16) (by omega)
    simp [le32Byte, le32Pack, hi, h0, h1, h2, show 24 + i < 32 by omega,
          show ¬(24 + i < 8) by omega, show ¬(24 + i < 16) by omega, show ¬(24 + i < 24) by omega]

theorem le32Pack_injective {a0 a1 a2 a3 b0 b1 b2 b3 : BitVec 8}
    (h : le32Pack a0 a1 a2 a3 = le32Pack b0 b1 b2 b3) :
    a0 = b0 ∧ a1 = b1 ∧ a2 = b2 ∧ a3 = b3 := by
  have ha := le32_byte_roundtrip a0 a1 a2 a3
  have hb := le32_byte_roundtrip b0 b1 b2 b3
  refine ⟨?_, ?_, ?_, ?_⟩
  · rw [← ha.1, ← hb.1, h]
  · rw [← ha.2.1, ← hb.2.1, h]
  · rw [← ha.2.2.1, ← hb.2.2.1, h]
  · rw [← ha.2.2.2, ← hb.2.2.2, h]

/-- Blackwell QMD v5 Word 34 (`threads_x | (threads_y << 16)`, matches om/gpu/bw_qmd.om:122). -/
def packQmdW34 (tx ty : BitVec 16) : BitVec 32 :=
  tx.zeroExtend 32 ||| (ty.zeroExtend 32 <<< 16)

def decQmdTx (w34 : BitVec 32) : BitVec 16 := w34.extractLsb' 0 16
def decQmdTy (w34 : BitVec 32) : BitVec 16 := w34.extractLsb' 16 16

theorem dec_packQmdW34 (tx ty : BitVec 16) :
    decQmdTx (packQmdW34 tx ty) = tx ∧ decQmdTy (packQmdW34 tx ty) = ty := by
  constructor
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [decQmdTx, packQmdW34, hi, show i < 32 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [decQmdTy, packQmdW34, hi, show 16 + i < 32 by omega, show ¬(16 + i < 16) by omega]

theorem packQmdW34_injective {tx1 ty1 tx2 ty2 : BitVec 16}
    (h : packQmdW34 tx1 ty1 = packQmdW34 tx2 ty2) : tx1 = tx2 ∧ ty1 = ty2 := by
  have h1 := dec_packQmdW34 tx1 ty1
  have h2 := dec_packQmdW34 tx2 ty2
  exact ⟨by rw [← h1.1, ← h2.1, h], by rw [← h1.2, ← h2.2, h]⟩

/-- Blackwell QMD v5 Word 35 (`1 | (gpr << 8) | (1 << 17)`, matches om/gpu/bw_qmd.om:123). -/
def packQmdW35 (gpr : BitVec 9) : BitVec 32 :=
  1#32 ||| (gpr.zeroExtend 32 <<< 8) ||| (1#32 <<< 17)

def decQmdGpr (w35 : BitVec 32) : BitVec 9 := w35.extractLsb' 8 9

theorem dec_packQmdW35 (gpr : BitVec 9) : decQmdGpr (packQmdW35 gpr) = gpr := by
  have h17all : ∀ j : Fin 9, (131072#32).getLsbD (8 + j.val) = false := by decide
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  have h17 : (131072#32)[8 + i] = false := h17all ⟨i, hi⟩
  simp [decQmdGpr, packQmdW35, hi, h17, show 8 + i < 32 by omega, show ¬(8 + i < 8) by omega]

/-- Blackwell QMD v5 Word 36 SMEM config (`(sc<<23) | (26<<17) | (sc<<11) | s7`, om/gpu/bw_qmd.om:143). -/
def packQmdW36 (sc : BitVec 5) (s7 : BitVec 11) : BitVec 32 :=
  (sc.zeroExtend 32 <<< 23) ||| (26#32 <<< 17) ||| (sc.zeroExtend 32 <<< 11) ||| s7.zeroExtend 32

def smemCfgFor (sb : Nat) : Nat :=
  if sb ≤ 32768 then 9 else if sb ≤ 65536 then 17 else 26

theorem smemCfgFor_bounds (sb : Nat) :
    (sb ≤ 32768 → smemCfgFor sb = 9) ∧
    (32768 < sb ∧ sb ≤ 65536 → smemCfgFor sb = 17) ∧
    (65536 < sb → smemCfgFor sb = 26) ∧
    smemCfgFor sb ≤ 26 := by
  by_cases h1 : sb ≤ 32768 <;> by_cases h2 : sb ≤ 65536 <;>
    simp [smemCfgFor, h1, h2] <;> omega

/-- Exact Blackwell QMD v05.00 hardware constants verified against om/gpu/bw_qmd.om. -/
theorem qmd_reference_words :
    ((0x2f5003a4#32).extractLsb' 20 4 = 5#4) ∧       -- word 14: VERSION_MAJOR == 5
    ((0x013f0000#32).extractLsb' 23 3 = 2#3) ∧       -- word 4:  QMD_TYPE == 2 (GRID_CTA)
    ((0x10300011#32).extractLsb' 0 1 = 1#1) ∧        -- word 58: CB0 valid bit
    (packQmdW36 9#5 8#11 = 0x04b44808#32) ∧          -- word 36 for shared_bytes = 0 (bw_qmd.om:6)
    (packQmdW34 256#16 1#16 = 0x00010100#32) ∧       -- word 34 for block_x = 256, ty = 1
    (packQmdW35 16#9 = 0x00021001#32) := by          -- word 35 for gpr_count = 16
  decide

/-- SM121 SASS word 0 bitfield layout: `[11:0]=op12, [15:12]=pred, [23:16]=rd, [31:24]=ra`. -/
def packSassW0 (op12 : BitVec 12) (pred : BitVec 4) (rd ra : BitVec 8) : BitVec 32 :=
  op12.zeroExtend 32 ||| (pred.zeroExtend 32 <<< 12) |||
  (rd.zeroExtend 32 <<< 16) ||| (ra.zeroExtend 32 <<< 24)

def decSassOp12 (w0 : BitVec 32) : BitVec 12 := w0.extractLsb' 0 12
def decSassPred (w0 : BitVec 32) : BitVec 4  := w0.extractLsb' 12 4
def decSassRd   (w0 : BitVec 32) : BitVec 8  := w0.extractLsb' 16 8
def decSassRa   (w0 : BitVec 32) : BitVec 8  := w0.extractLsb' 24 8

theorem dec_packSassW0 (op12 : BitVec 12) (pred : BitVec 4) (rd ra : BitVec 8) :
    decSassOp12 (packSassW0 op12 pred rd ra) = op12 ∧
    decSassPred (packSassW0 op12 pred rd ra) = pred ∧
    decSassRd   (packSassW0 op12 pred rd ra) = rd ∧
    decSassRa   (packSassW0 op12 pred rd ra) = ra := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [decSassOp12, packSassW0, hi, show i < 32 by omega,
          show i < 16 by omega, show i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    simp [decSassPred, packSassW0, hi, show 12 + i < 32 by omega,
          show ¬(12 + i < 12) by omega, show 12 + i < 16 by omega, show 12 + i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hop : op12.getLsbD (16 + i) = false := BitVec.getLsbD_of_ge op12 (16 + i) (by omega)
    have hpr : pred.getLsbD (16 + i - 12) = false := BitVec.getLsbD_of_ge pred (16 + i - 12) (by omega)
    simp [decSassRd, packSassW0, hi, hop, hpr, show 16 + i < 32 by omega,
          show ¬(16 + i < 12) by omega, show ¬(16 + i < 16) by omega, show 16 + i < 24 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hop : op12.getLsbD (24 + i) = false := BitVec.getLsbD_of_ge op12 (24 + i) (by omega)
    have hpr : pred.getLsbD (24 + i - 12) = false := BitVec.getLsbD_of_ge pred (24 + i - 12) (by omega)
    have hrd : rd.getLsbD (24 + i - 16) = false := BitVec.getLsbD_of_ge rd (24 + i - 16) (by omega)
    simp [decSassRa, packSassW0, hi, hop, hpr, hrd, show 24 + i < 32 by omega,
          show ¬(24 + i < 12) by omega, show ¬(24 + i < 16) by omega, show ¬(24 + i < 24) by omega]

theorem packSassW0_injective {o1 o2 : BitVec 12} {p1 p2 : BitVec 4} {d1 d2 a1 a2 : BitVec 8}
    (h : packSassW0 o1 p1 d1 a1 = packSassW0 o2 p2 d2 a2) :
    o1 = o2 ∧ p1 = p2 ∧ d1 = d2 ∧ a1 = a2 := by
  have h1 := dec_packSassW0 o1 p1 d1 a1
  have h2 := dec_packSassW0 o2 p2 d2 a2
  exact ⟨by rw [← h1.1, ← h2.1, h], by rw [← h1.2.1, ← h2.2.1, h],
         by rw [← h1.2.2.1, ← h2.2.2.1, h], by rw [← h1.2.2.2, ← h2.2.2.2, h]⟩

/-- Spot-check exact `w0` encodings emitted by `om/gpu/bw_vecadd.om` and decoded by `payload_vm.om`. -/
theorem sass_vecadd_reference_w0 :
    packSassW0 0xb82#12 7#4 1#8 0xff#8 = 0xff017b82#32 ∧  -- LDC R1, c[0x0][0x37c]
    packSassW0 0x919#12 7#4 9#8 0#8    = 0x00097919#32 ∧  -- S2R R9, SR_CTAID.X
    packSassW0 0x7ac#12 7#4 4#8 0xff#8 = 0xff0477ac#32 ∧  -- LDCU UR4, c[0x0][0x360]
    packSassW0 0x919#12 7#4 0#8 0#8    = 0x00007919#32 ∧  -- S2R R0, SR_TID.X
    packSassW0 0xc24#12 7#4 9#8 9#8    = 0x09097c24#32 ∧  -- IMAD R9, R9, UR4, R0
    packSassW0 0xc0c#12 7#4 0#8 9#8    = 0x09007c0c#32 ∧  -- ISETP.GE.U32 P0, PT, R9, UR5, PT
    packSassW0 0x94d#12 0#4 0#8 0#8    = 0x0000094d#32 ∧  -- @P0 EXIT
    packSassW0 0x825#12 7#4 2#8 9#8    = 0x09027825#32 ∧  -- IMAD.WIDE.U32 R2, R9, 0x4, R2
    packSassW0 0x981#12 7#4 2#8 2#8    = 0x02027981#32 ∧  -- LDG.E R2, desc[UR4][R2.64]
    packSassW0 0x210#12 7#4 9#8 2#8    = 0x02097210#32 ∧  -- IADD3 R9, PT, PT, R2, R5, RZ
    packSassW0 0x986#12 7#4 0#8 6#8    = 0x06007986#32 ∧  -- STG.E desc[UR4][R6.64], R9
    packSassW0 0x94d#12 7#4 0#8 0#8    = 0x0000794d#32 ∧  -- EXIT
    packSassW0 0x918#12 7#4 0#8 0#8    = 0x00007918#32 := by -- NOP
  decide

/-- All 13 SM121 opcodes dispatched by `payload_vm.om` are pairwise distinct. -/
def sm121Opcodes : List (BitVec 12) :=
  [0x918#12, 0x94d#12, 0x947#12, 0x919#12, 0xb82#12, 0x7ac#12,
   0x981#12, 0x986#12, 0xc24#12, 0x825#12, 0xc0c#12, 0x210#12, 0x221#12]

def allDistinctBv12 : List (BitVec 12) → Bool
  | [] => true
  | x :: xs => xs.all (fun y => x != y) && allDistinctBv12 xs

theorem sm121_opcodes_pairwise_disjoint : allDistinctBv12 sm121Opcodes = true := by
  decide

/-- Negative control: unmasked 32-bit `tx` in QMD word 34 overflows into `ty` bits [31:16]. -/
def brokenPackQmdW34 (tx ty : BitVec 32) : BitVec 32 := tx ||| (ty <<< 16)

theorem neg_unmasked_qmd_w34_corrupts_ty :
    ∃ tx ty : BitVec 32, decQmdTy (brokenPackQmdW34 tx ty) ≠ ty.extractLsb' 0 16 := by
  exact ⟨0x00010100#32, 0#32, by decide⟩

/-! ## 3. Multi-Thread Bounded GPU Kernel Model & Canary Preservation -/

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

/-- Multi-thread CTA launch executing threads `0, 1, ..., k - 1` (models `UOR_REPLAY_THREADS = 12`
    over `UOR_REPLAY_N = 8` elements + 4 OOB threads). -/
def runVecadd (n : Nat) : Nat → (Nat → Nat) → (Nat → Nat) → (Nat → Nat) → (Nat → Nat)
  | 0, _, _, init => init
  | k + 1, a, b, init => vecaddStep n k a b (runVecadd n k a b init)

theorem runVecadd_result (n k : Nat) (a b init : Nat → Nat) (i : Nat) :
    runVecadd n k a b init i = if i < k ∧ i < n then a i + b i else init i := by
  induction k with
  | zero => simp [runVecadd]
  | succ k ih =>
    unfold runVecadd vecaddStep
    by_cases hkn : k < n
    · simp only [hkn, ↓reduceIte]
      by_cases hik : i = k
      · subst hik; simp [hkn]
      · simp only [hik, ↓reduceIte, ih]
        have hiff : (i < k ∧ i < n) ↔ (i < k + 1 ∧ i < n) := by omega
        simp [hiff]
    · simp only [hkn, ↓reduceIte, ih]
      have hiff : (i < k ∧ i < n) ↔ (i < k + 1 ∧ i < n) := by omega
      simp [hiff]

/-- Every in-bounds output slot holds `a[i] + b[i]` once `k ≥ n` threads run. -/
theorem runVecadd_in_bounds (n k : Nat) (a b init : Nat → Nat) (i : Nat)
    (hi : i < n) (hk : n ≤ k) :
    runVecadd n k a b init i = a i + b i := by
  rw [runVecadd_result]
  have : i < k ∧ i < n := ⟨by omega, hi⟩
  simp [this]

/-- Every OOB guard canary slot (`i ≥ n`) stays untouched regardless of how many OOB threads run. -/
theorem runVecadd_preserves_canaries (n k : Nat) (a b init : Nat → Nat) (i : Nat) (hoob : n ≤ i) :
    runVecadd n k a b init i = init i := by
  rw [runVecadd_result]
  have : ¬ (i < k ∧ i < n) := by omega
  simp [this]

/-- Negative control: an unguarded kernel writes out-of-bounds and clobbers canary slot `tid = n`. -/
def brokenVecaddStep (tid : Nat) (a b out : Nat → Nat) : Nat → Nat :=
  fun i => if i = tid then a tid + b tid else out i

theorem broken_vecadd_violates_oob :
    ∃ n tid a b out, ¬ tid < n ∧ brokenVecaddStep tid a b out tid ≠ out tid := by
  refine ⟨4, 4, (fun _ => 1), (fun _ => 1), (fun _ => 0), by decide, by decide⟩

theorem neg_unguarded_clobbers_canary :
    ∃ a b, brokenVecaddStep 8 a b (fun _ => 0xdeadbeef) 8 ≠ 0xdeadbeef := by
  refine ⟨fun _ => 10, fun _ => 20, by decide⟩

/-! ## 4. Two-Stage Hash-Commitment Tamper Evidence (canonical.om `uor_hdr_seal`) -/

/-- Abstract bundle commitment matching `uor_hdr_seal`:
    `uorId = hSha (meta, hShaPay pay)` and `holo = hB3 (meta, uorId, pay)`.
    Collision resistance of SHA-256 and BLAKE3 is stated explicitly as a hypothesis (Ledger.lean style). -/
structure SealedBundle (M P D : Type) where
  metaFields : M   -- header[0..96) + header[128..224): meta, omc_pin, source, lean, replay, mlbom
  payload    : P   -- emitted SM121 SASS+QMD v5 or SPIR-V bytes
  payHash    : D   -- header[96..128)
  uorId      : D   -- header[224..256)
  holoSeal   : D   -- header[256..288)

def ValidSeal {M P D : Type} (hPay : P → D) (hUor : M → D → D) (hHolo : M → D → P → D)
    (b : SealedBundle M P D) : Prop :=
  b.payHash = hPay b.payload ∧
  b.uorId = hUor b.metaFields b.payHash ∧
  b.holoSeal = hHolo b.metaFields b.uorId b.payload

/-- Equal `uor_id_sha256` fixes both all canonical metadata fields and the exact payload bytes. -/
theorem uor_id_tamper_evident {M P D : Type}
    (hPay : P → D) (hUor : M → D → D) (hHolo : M → D → P → D)
    (hPayInj : ∀ p1 p2, hPay p1 = hPay p2 → p1 = p2)
    (hUorInj : ∀ m1 d1 m2 d2, hUor m1 d1 = hUor m2 d2 → m1 = m2 ∧ d1 = d2)
    (b1 b2 : SealedBundle M P D)
    (v1 : ValidSeal hPay hUor hHolo b1) (v2 : ValidSeal hPay hUor hHolo b2)
    (heq : b1.uorId = b2.uorId) :
    b1.metaFields = b2.metaFields ∧ b1.payload = b2.payload := by
  rw [v1.2.1, v2.2.1] at heq
  obtain ⟨hm, hd⟩ := hUorInj _ _ _ _ heq
  rw [v1.1, v2.1] at hd
  exact ⟨hm, hPayInj _ _ hd⟩

/-- Equal `.holo` BLAKE3 seal fixes metadata, `uor_id_sha256`, and payload bytes simultaneously. -/
theorem holo_seal_tamper_evident {M P D : Type}
    (hPay : P → D) (hUor : M → D → D) (hHolo : M → D → P → D)
    (hHoloInj : ∀ m1 u1 p1 m2 u2 p2, hHolo m1 u1 p1 = hHolo m2 u2 p2 → m1 = m2 ∧ u1 = u2 ∧ p1 = p2)
    (b1 b2 : SealedBundle M P D)
    (v1 : ValidSeal hPay hUor hHolo b1) (v2 : ValidSeal hPay hUor hHolo b2)
    (heq : b1.holoSeal = b2.holoSeal) :
    b1.metaFields = b2.metaFields ∧ b1.uorId = b2.uorId ∧ b1.payload = b2.payload := by
  rw [v1.2.2, v2.2.2] at heq
  exact hHoloInj _ _ _ _ _ _ heq

/-! ## 5. Blackwell QMD v5 SKEDCHECK05, Trust-Anchor Separation & Reason-Coded Admission -/

structure QmdV5 where
  versionMajor : Nat      -- (q[14] >> 20) & 0xf == 5
  qmdType : Nat           -- (q[4] >> 23) & 0x7 == 2 (GRID_CTA)
  word37 : Nat            -- q[37] == 0
  semEnable : Nat         -- q[17] != 0
  prefetchTag : Nat       -- (q[33] >> 21) & 0x1ff == 0xa
  cb0Valid : Bool         -- (q[58] & 1) != 0
  threadsX : Nat          -- q[34] & 0xffff == hdr.block_x
  threadsY : Nat          -- (q[34] >> 16) & 0xffff >= 1
  gridX : Nat             -- q[39] >= 1
  gridY : Nat             -- q[40] >= 1
  gridZ : Nat             -- q[41] >= 1
  gprCount : Nat          -- (q[35] >> 8) & 0x1ff >= 16
  codeVaNonZero : Bool    -- q[32] != 0
  cbankVaNonZero : Bool   -- q[42] != 0
  deriving DecidableEq

def qmdV5Valid (hdrBlockX : Nat) (q : QmdV5) : Bool :=
  decide (q.versionMajor = 5) &&
  decide (q.qmdType = 2) &&
  decide (q.word37 = 0) &&
  decide (q.semEnable ≠ 0) &&
  decide (q.prefetchTag = 10) &&
  q.cb0Valid &&
  decide (q.threadsX = hdrBlockX) &&
  decide (q.threadsY ≥ 1) &&
  decide (q.gridX ≥ 1) &&
  decide (q.gridY ≥ 1) &&
  decide (q.gridZ ≥ 1) &&
  decide (q.gprCount ≥ 16) &&
  q.codeVaNonZero &&
  q.cbankVaNonZero

theorem qmd_valid_enforces_skedcheck05 (bx : Nat) (q : QmdV5)
    (h : qmdV5Valid bx q = true) :
    q.versionMajor = 5 ∧ q.qmdType = 2 ∧ q.word37 = 0 ∧
    q.prefetchTag = 10 ∧ q.cb0Valid = true ∧ q.threadsX = bx ∧ q.gprCount ≥ 16 := by
  unfold qmdV5Valid at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1.1.1.1.1.1.1.1.1.1.1.1.1, h.1.1.1.1.1.1.1.1.1.1.1.1.2,
         h.1.1.1.1.1.1.1.1.1.1.1.2, h.1.1.1.1.1.1.1.1.1.2,
         h.1.1.1.1.1.1.1.1.2, h.1.1.1.1.1.1.1.2, h.1.1.2⟩

theorem qmd_wrong_version_refused (bx : Nat) (q : QmdV5) (hv : q.versionMajor ≠ 5) :
    qmdV5Valid bx q = false := by
  simp [qmdV5Valid, hv]

theorem qmd_blockx_mismatch_refused (bx : Nat) (q : QmdV5) (hm : q.threadsX ≠ bx) :
    qmdV5Valid bx q = false := by
  simp [qmdV5Valid, hm]

/-- Local trust anchors model (verify.om `uor_anchors_nkeys`): non-zero pins, 1..16 non-zero signer
    keys, and strict separation of privilege (`authorityKey ≠ signerKey` for every trusted signer). -/
structure TrustAnchors where
  omcPin       : Nat
  leanPin      : Nat
  authorityKey : Nat
  signerKeys   : List Nat
  deriving DecidableEq

def anchorsWellFormed (a : TrustAnchors) : Bool :=
  decide (a.omcPin ≠ 0) &&
  decide (a.leanPin ≠ 0) &&
  decide (1 ≤ a.signerKeys.length) &&
  decide (a.signerKeys.length ≤ 16) &&
  a.signerKeys.all (fun k => decide (k ≠ 0) && decide (k ≠ a.authorityKey))

/-- Separation of privilege: a bundle signer key in valid trust anchors can never equal the
    capability authority key (so a bundle signer can never mint its own capability grant). -/
theorem anchors_separate_authority_and_signer (a : TrustAnchors) (k : Nat)
    (hwf : anchorsWellFormed a = true) (hmem : k ∈ a.signerKeys) :
    k ≠ 0 ∧ k ≠ a.authorityKey := by
  unfold anchorsWellFormed at hwf
  simp only [Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at hwf
  exact hwf.2 k hmem

/-- Negative control: anchors where the authority key appears as a bundle signer are refused. -/
theorem neg_shared_auth_signer_refused :
    anchorsWellFormed ⟨1, 2, 42, [42]⟩ = false := by
  decide

/-- Exact reason codes matching `protocol/uor-gpu/canonical.om` constants 0..20. -/
inductive ReasonCode where
  | pass            -- 0
  | badMagic        -- 1
  | badTarget       -- 2
  | payloadTamper   -- 3
  | uorIdTamper     -- 4
  | holoTamper      -- 5
  | omcPin          -- 6
  | levelLow        -- 7
  | noLeanProof     -- 8
  | noReplay        -- 9
  | capDenied       -- 10
  | badSig          -- 11
  | replayMismatch  -- 12
  | untrustedSigner -- 13
  | leanUnpinned    -- 14
  | badAnchors      -- 15
  | badGrant        -- 16
  | unsignedLevel   -- 17
  | badQmd          -- 18
  | badSpirv        -- 19
  | replayFault     -- 20
  deriving DecidableEq, Repr

def ReasonCode.code : ReasonCode → Nat
  | .pass            => 0
  | .badMagic        => 1
  | .badTarget       => 2
  | .payloadTamper   => 3
  | .uorIdTamper     => 4
  | .holoTamper      => 5
  | .omcPin          => 6
  | .levelLow        => 7
  | .noLeanProof     => 8
  | .noReplay        => 9
  | .capDenied       => 10
  | .badSig          => 11
  | .replayMismatch  => 12
  | .untrustedSigner => 13
  | .leanUnpinned    => 14
  | .badAnchors      => 15
  | .badGrant        => 16
  | .unsignedLevel   => 17
  | .badQmd          => 18
  | .badSpirv        => 19
  | .replayFault     => 20

structure BundleVerdict where
  anchorsValid : Bool
  payloadNonEmpty : Bool
  blockXValid : Bool
  payloadStructOk : Bool
  payloadOk : Bool
  uorIdOk : Bool
  holoBlake3Ok : Bool
  omcPinOk : Bool
  level : Nat
  hasLeanProof : Bool
  leanProofPinned : Bool
  hasReplay : Bool
  replayExecOk : Bool
  replayMatch : Bool
  hasSig : Bool
  sigSlotZero : Bool
  signerTrusted : Bool
  sigValid : Bool
  deriving DecidableEq

structure CapGrant where
  grantSigValid : Bool
  live : Bool
  genNonZero : Bool
  genMatch : Bool
  epochMatch : Bool
  leaseNonZero : Bool
  notExpired : Bool
  subjectMatch : Bool
  resourceMatch : Bool
  hasEffectRight : Bool
  deriving DecidableEq

/-- Exact check-order evaluator matching `verify.om` (`uor_verify_policy` + `uor_verify_replay_real`). -/
def evalPolicy (minLevel : Nat) (v : BundleVerdict) : ReasonCode :=
  if !v.anchorsValid then .badAnchors
  else if !v.payloadNonEmpty then .payloadTamper
  else if !v.blockXValid then .badTarget
  else if !v.payloadOk then .payloadTamper
  else if !v.uorIdOk then .uorIdTamper
  else if !v.holoBlake3Ok then .holoTamper
  else if !v.payloadStructOk then .badQmd
  else if !v.omcPinOk then .omcPin
  else if !(v.level ≤ 3) then .badTarget
  else if !(minLevel ≤ v.level) then .levelLow
  else if minLevel ≥ 2 ∧ !v.hasLeanProof then .noLeanProof
  else if minLevel ≥ 2 ∧ !v.leanProofPinned then .leanUnpinned
  else if minLevel ≥ 3 ∧ !v.hasReplay then .noReplay
  else if !v.hasSig then
    if minLevel ≥ 1 then .badSig
    else if v.level ≠ 0 then .unsignedLevel
    else if !v.sigSlotZero then .badSig
    else .pass
  else if !v.signerTrusted then .untrustedSigner
  else if !v.sigValid then .badSig
  else if minLevel ≥ 3 ∧ !v.replayExecOk then .replayFault
  else if minLevel ≥ 3 ∧ !v.replayMatch then .replayMismatch
  else .pass

def verifyPolicy (minLevel : Nat) (v : BundleVerdict) : Bool :=
  v.anchorsValid &&
  v.payloadNonEmpty && v.blockXValid && v.payloadStructOk &&
  v.payloadOk && v.uorIdOk && v.holoBlake3Ok && v.omcPinOk &&
  decide (v.level ≤ 3) &&
  decide (minLevel ≤ v.level) &&
  (if minLevel ≥ 2 then v.hasLeanProof && v.leanProofPinned else true) &&
  (if minLevel ≥ 3 then v.hasReplay && v.replayExecOk && v.replayMatch else true) &&
  (if v.hasSig then
      v.signerTrusted && v.sigValid
   else
      decide (minLevel = 0) && decide (v.level = 0) && v.sigSlotZero)

def capAdmit (g : CapGrant) : Bool :=
  g.grantSigValid && g.live && g.genNonZero && g.genMatch && g.epochMatch &&
  g.leaseNonZero && g.notExpired && g.subjectMatch && g.resourceMatch && g.hasEffectRight

def evalAdmit (v : BundleVerdict) (g : CapGrant) : ReasonCode :=
  match evalPolicy 2 v with
  | .pass =>
    if !g.grantSigValid then .badGrant
    else if !capAdmit g then .capDenied
    else .pass
  | rc => rc

def gpuAdmitDefault (v : BundleVerdict) (g : CapGrant) : Bool :=
  verifyPolicy 2 v && capAdmit g

/-- Exact equivalence between the reason-coded evaluator and the boolean policy predicate. -/
theorem evalPolicy_pass_iff (minLevel : Nat) (v : BundleVerdict) :
    evalPolicy minLevel v = .pass ↔ verifyPolicy minLevel v = true := by
  cases ha : v.anchorsValid
  · simp [evalPolicy, verifyPolicy, ha]
  cases hne : v.payloadNonEmpty
  · simp [evalPolicy, verifyPolicy, ha, hne]
  cases hbx : v.blockXValid
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx]
  cases hp : v.payloadOk
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp]
  cases hu : v.uorIdOk
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu]
  cases hb : v.holoBlake3Ok
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb]
  cases hst : v.payloadStructOk
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst]
  cases ho : v.omcPinOk
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho]
  by_cases hl3 : v.level ≤ 3
  · by_cases hml : minLevel ≤ v.level
    · by_cases hm2 : minLevel ≥ 2
      · cases hlp : v.hasLeanProof
        · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp]
        cases hlpin : v.leanProofPinned
        · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin]
        by_cases hm3 : minLevel ≥ 3
        · cases hr : v.hasReplay
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr]
          cases hs : v.hasSig
          · have hm1 : minLevel ≥ 1 := by omega
            have hm0 : minLevel ≠ 0 := by omega
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr, hs, hm1, hm0]
          cases htr : v.signerTrusted
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr, hs, htr]
          cases hsv : v.sigValid
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr, hs, htr, hsv]
          cases hre : v.replayExecOk
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr, hs, htr, hsv, hre]
          cases hrm : v.replayMatch <;>
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hr, hs, htr, hsv, hre, hrm]
        · cases hs : v.hasSig
          · have hm1 : minLevel ≥ 1 := by omega
            have hm0 : minLevel ≠ 0 := by omega
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hs, hm1, hm0]
          cases htr : v.signerTrusted
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hs, htr]
          cases hsv : v.sigValid <;>
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hlp, hlpin, hm3, hs, htr, hsv]
      · have hm3 : ¬(minLevel ≥ 3) := by omega
        cases hs : v.hasSig
        · by_cases hm1 : minLevel ≥ 1
          · have hm0 : minLevel ≠ 0 := by omega
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hm3, hs, hm1, hm0]
          · have hm0 : minLevel = 0 := by omega
            by_cases hl0 : v.level = 0
            · cases hsz : v.sigSlotZero <;>
                simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hs, hm0, hl0, hsz]
            · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hs, hm0, hl0]
        · cases htr : v.signerTrusted
          · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hm3, hs, htr]
          cases hsv : v.sigValid <;>
            simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml, hm2, hm3, hs, htr, hsv]
    · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3, hml]
  · simp [evalPolicy, verifyPolicy, ha, hne, hbx, hp, hu, hb, hst, ho, hl3]

theorem evalAdmit_pass_iff (v : BundleVerdict) (g : CapGrant) :
    evalAdmit v g = .pass ↔ gpuAdmitDefault v g = true := by
  unfold evalAdmit gpuAdmitDefault
  have hp := evalPolicy_pass_iff 2 v
  cases h : evalPolicy 2 v with
  | pass =>
    have hv : verifyPolicy 2 v = true := hp.mp h
    cases hgs : g.grantSigValid <;> cases hc : capAdmit g <;>
    simp_all [capAdmit]
  | _ =>
    have hv : verifyPolicy 2 v = false := by
      cases hv' : verifyPolicy 2 v
      · rfl
      · exfalso; have := hp.mpr hv'; rw [h] at this; cases this
    simp [hv]

/-- Policy-level monotonicity: passing a higher minimum level implies passing every lower level. -/
theorem verifyPolicy_monotone {m1 m2 : Nat} {v : BundleVerdict}
    (hle : m1 ≤ m2) (h : verifyPolicy m2 v = true) :
    verifyPolicy m1 v = true := by
  unfold verifyPolicy at h ⊢
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h ⊢
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨ha, hne⟩, hbx⟩, hst⟩, hp⟩, hu⟩, hb⟩, ho⟩, hl3⟩, hm2⟩, hlp⟩, hrep⟩, hsig⟩ := h
  refine ⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨ha, hne⟩, hbx⟩, hst⟩, hp⟩, hu⟩, hb⟩, ho⟩, hl3⟩, by omega⟩, ?_⟩, ?_⟩, ?_⟩
  · split
    · rename_i hm1_2
      have hm2_2 : m2 ≥ 2 := by omega
      simp only [hm2_2, ↓reduceIte] at hlp
      exact hlp
    · rfl
  · split
    · rename_i hm1_3
      have hm2_3 : m2 ≥ 3 := by omega
      simp only [hm2_3, ↓reduceIte] at hrep
      exact hrep
    · rfl
  · cases hsf : v.hasSig
    · simp only [hsf, Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true, decide_eq_true_eq] at hsig ⊢
      exact ⟨⟨by omega, hsig.1.2⟩, hsig.2⟩
    · simp only [hsf, ↓reduceIte] at hsig ⊢
      exact hsig

/-- "Nothing raises a level except signing": an unsigned bundle can NEVER pass any level >= P1. -/
theorem unsigned_never_above_p0 (minLevel : Nat) (v : BundleVerdict)
    (hm : 1 ≤ minLevel) (hu : v.hasSig = false) :
    verifyPolicy minLevel v = false := by
  unfold verifyPolicy
  have hne : minLevel ≠ 0 := by omega
  simp [hu, hne]

theorem admit_requires_pinned_lean_proof (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.hasLeanProof = true ∧ v.leanProofPinned = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hlp : v.hasLeanProof <;> cases hpin : v.leanProofPinned <;> simp [hlp, hpin] at h
  exact ⟨rfl, rfl⟩

theorem admit_requires_intact_digests_and_struct (v : BundleVerdict) (g : CapGrant)
    (h : gpuAdmitDefault v g = true) :
    v.payloadNonEmpty = true ∧ v.blockXValid = true ∧ v.payloadStructOk = true ∧
    v.payloadOk = true ∧ v.uorIdOk = true ∧ v.holoBlake3Ok = true ∧ v.omcPinOk = true := by
  unfold gpuAdmitDefault verifyPolicy at h
  cases hne : v.payloadNonEmpty <;> cases hbx : v.blockXValid <;>
    cases hst : v.payloadStructOk <;> cases hp : v.payloadOk <;>
    cases hu : v.uorIdOk <;> cases hb : v.holoBlake3Ok <;> cases ho : v.omcPinOk <;>
    simp [hne, hbx, hst, hp, hu, hb, ho] at h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

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

theorem invalid_payload_struct_refused (v : BundleVerdict) (g : CapGrant)
    (hbad : v.payloadStructOk = false) : gpuAdmitDefault v g = false := by
  simp [gpuAdmitDefault, verifyPolicy, hbad]

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

theorem p3_replay_fault_refused (v : BundleVerdict)
    (hf : v.replayExecOk = false) : verifyPolicy 3 v = false := by
  simp [verifyPolicy, hf]

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

/-! ## 6. Inductive Pre-Dispatch Lifecycle State Machine (AienGpuGb20b / TicketLock Style) -/

inductive Phase where
  | init | compiled | verifiedP2 | replayedP3 | admitted | dispatched | failed
  deriving DecidableEq

structure TraceState where
  phase       : Phase
  omcPinned   : Bool
  p2Passed    : Bool
  p3Replayed  : Bool
  capVerified : Bool
  gpuTouched  : Bool
  deriving DecidableEq

def initTrace : TraceState :=
  { phase := .init, omcPinned := false, p2Passed := false,
    p3Replayed := false, capVerified := false, gpuTouched := false }

inductive Step : TraceState → TraceState → Prop
  | compile_ok {s} (hp : s.phase = .init) :
      Step s { s with phase := .compiled, omcPinned := true }
  | verify_p2_ok {s} (v : BundleVerdict) (hp : s.phase = .compiled)
      (hok : verifyPolicy 2 v = true) :
      Step s { s with phase := .verifiedP2, p2Passed := true }
  | replay_p3_ok {s} (v : BundleVerdict) (hp : s.phase = .verifiedP2)
      (hok : verifyPolicy 3 v = true) :
      Step s { s with phase := .replayedP3, p3Replayed := true }
  | admit_from_p2 {s} (v : BundleVerdict) (g : CapGrant) (hp : s.phase = .verifiedP2)
      (hok : gpuAdmitDefault v g = true) :
      Step s { s with phase := .admitted, capVerified := true }
  | admit_from_p3 {s} (v : BundleVerdict) (g : CapGrant) (hp : s.phase = .replayedP3)
      (hok : gpuAdmitDefault v g = true) :
      Step s { s with phase := .admitted, capVerified := true }
  | dispatch_gpu {s} (hp : s.phase = .admitted) :
      Step s { s with phase := .dispatched, gpuTouched := true }
  | fail_closed {s} :
      Step s { s with phase := .failed }

inductive Reachable : TraceState → Prop
  | init : Reachable initTrace
  | step {s s'} : Reachable s → Step s s' → Reachable s'

/-- Fail-closed lifecycle invariant: GPU dispatch is reachable ONLY after pinned compilation,
    P2 policy verification (pinned Lean 4 proof + QMD v5/SPIR-V + trusted Ed25519 signature),
    and authority-signed live capability admission. -/
def SafeInv (s : TraceState) : Prop :=
  (s.phase = .init → s.gpuTouched = false) ∧
  (s.phase = .compiled → s.omcPinned = true ∧ s.gpuTouched = false) ∧
  (s.phase = .verifiedP2 → s.omcPinned = true ∧ s.p2Passed = true ∧ s.gpuTouched = false) ∧
  (s.phase = .replayedP3 → s.omcPinned = true ∧ s.p2Passed = true ∧ s.p3Replayed = true ∧ s.gpuTouched = false) ∧
  (s.phase = .admitted → s.omcPinned = true ∧ s.p2Passed = true ∧ s.capVerified = true) ∧
  (s.gpuTouched = true → s.omcPinned = true ∧ s.p2Passed = true ∧ s.capVerified = true)

theorem safeInv_init : SafeInv initTrace := by
  simp [SafeInv, initTrace]

theorem safeInv_step {s s'} (hinv : SafeInv s) (hst : Step s s') : SafeInv s' := by
  rcases hinv with ⟨h0, h1, h2, h3, h4, h5⟩
  cases hst with
  | compile_ok hp =>
    have hg := h0 hp
    refine ⟨by simp, by simp [hg], by simp, by simp, by simp, by simp [hg]⟩
  | verify_p2_ok _ hp _ =>
    have hc := h1 hp
    refine ⟨by simp, by simp, by simp [hc.1, hc.2], by simp, by simp, by simp [hc.2]⟩
  | replay_p3_ok _ hp _ =>
    have hv := h2 hp
    refine ⟨by simp, by simp, by simp, by simp [hv.1, hv.2.1, hv.2.2], by simp, by simp [hv.2.2]⟩
  | admit_from_p2 _ _ hp _ =>
    have hv := h2 hp
    refine ⟨by simp, by simp, by simp, by simp, by simp [hv.1, hv.2.1], by simp [hv.2.2]⟩
  | admit_from_p3 _ _ hp _ =>
    have hr := h3 hp
    refine ⟨by simp, by simp, by simp, by simp, by simp [hr.1, hr.2.1], by simp [hr.2.2.2]⟩
  | dispatch_gpu hp =>
    have ha := h4 hp
    refine ⟨by simp, by simp, by simp, by simp, by simp, by intro _; exact ha⟩
  | fail_closed =>
    refine ⟨by simp, by simp, by simp, by simp, by simp, h5⟩

theorem safeInv_reachable {s : TraceState} (hr : Reachable s) : SafeInv s := by
  induction hr with
  | init => exact safeInv_init
  | step _ hst ih => exact safeInv_step ih hst

/-- Corollary: no reachable execution can ever touch the GPU without passing all three gates. -/
theorem no_unverified_gpu_touch {s : TraceState} (hr : Reachable s) (ht : s.gpuTouched = true) :
    s.omcPinned = true ∧ s.p2Passed = true ∧ s.capVerified = true :=
  (safeInv_reachable hr).2.2.2.2.2 ht

/-- Negative control: a shortcut dispatching straight from `compiled` without P2/cap admission violates `SafeInv`. -/
theorem neg_shortcut_dispatch_violates_safeInv :
    let bad : TraceState := { initTrace with phase := .dispatched, omcPinned := true, gpuTouched := true }
    ¬ SafeInv bad := by
  intro bad h
  have := h.2.2.2.2.2 rfl
  simp [bad, initTrace] at this

/-! ## 7. Prism Group Alignment (`uor-framework`, `LexLean`, `PrismPM`, `uor-comms`, `mnist`) -/

/-! ### 7a. UOR Ring `Z/(2^32)Z` Critical Identity & Word Arithmetic (`uor-framework`) -/

/-- Foundational UOR ring identity over `BitVec 32` (`Z/(2^32)Z`), matching 32-bit GPU words
    in `om/gpu/bw_vecadd.om` (`IADD3`) and `protocol/uor-gpu/canonical.om`: `neg (bnot x) = succ x`. -/
theorem uor_ring_critical_identity (x : BitVec 32) :
    -~~~x = x + 1#32 := by
  apply BitVec.eq_of_toNat_eq
  have hx := x.isLt
  simp [BitVec.toNat_neg, BitVec.toNat_not, BitVec.toNat_add]
  omega

theorem uor_ring_neg_involution (x : BitVec 32) :
    -(-x) = x := by
  bv_omega

theorem uor_ring_bnot_involution (x : BitVec 32) :
    ~~~(~~~x) = x :=
  BitVec.not_not

theorem uor_u32_add_comm_assoc (x y z : BitVec 32) :
    x + y = y + x ∧ (x + y) + z = x + (y + z) :=
  ⟨BitVec.add_comm x y, BitVec.add_assoc x y z⟩

/-! ### 7b. Contract Satisfaction (`UOR-Foundation/mnist` `satisfies_contract` pattern) -/

/-- Precondition / postcondition boundary contract for bounded GPU vecadd launch. -/
def VecaddPrecond (n k : Nat) : Prop := n ≤ k

def VecaddPostcond (n : Nat) (a b init out : Nat → Nat) : Prop :=
  (∀ i, i < n → out i = a i + b i) ∧ (∀ i, n ≤ i → out i = init i)

/-- Universal contract theorem: every launch satisfying `VecaddPrecond` satisfies `VecaddPostcond`
    (discharging the postcondition by proof, matching `Mnist.Model.satisfies_contract`). -/
theorem vecadd_satisfies_contract (n k : Nat) (a b init : Nat → Nat)
    (hpre : VecaddPrecond n k) :
    VecaddPostcond n a b init (runVecadd n k a b init) :=
  ⟨fun i hi => runVecadd_in_bounds n k a b init i hi hpre,
   fun i hoob => runVecadd_preserves_canaries n k a b init i hoob⟩

/-! ### 7c. Domain-Separated Framed Content IDs (`LexLeanBoot.ContentId` pattern) -/

/-- Domain-separated framed input `(domain, body)` matching `LexLeanBoot.ContentId.framedHash`
    and `uor-gpu`'s distinct domain tags (`UORGPU1\0`, `mlbom:v2:...`, `UORTRST1`). -/
structure FramedInput (D B : Type) where
  domain : D
  body   : B
  deriving DecidableEq

/-- Under an injective hash over `(domain, body)`, distinct domains can never collide. -/
theorem framed_domain_disjoint {D B H : Type}
    (hHash : FramedInput D B → H)
    (hInj : ∀ x y, hHash x = hHash y → x = y)
    (d1 d2 : D) (b1 b2 : B) (hd : d1 ≠ d2) :
    hHash ⟨d1, b1⟩ ≠ hHash ⟨d2, b2⟩ := by
  intro heq
  have h := hInj _ _ heq
  cases h
  exact hd rfl

/-- Negative control: unframed concatenation allows cross-domain ambiguity (`"ab" ++ "c" = "a" ++ "bc"`). -/
theorem neg_unframed_concat_ambiguity :
    ∃ d1 b1 d2 b2 : String, d1 ≠ d2 ∧ d1 ++ b1 = d2 ++ b2 := by
  exact ⟨"ab", "c", "a", "bc", by decide, by decide⟩

/-! ### 7d. Exact Refusal-Reason Soundness & Completeness (`uor-comms` `ReasonProofs` pattern) -/

private theorem ite_ne {α : Type} {c : Prop} [Decidable c] {a b t : α}
    (ha : a ≠ t) (hb : b ≠ t) : (if c then a else b) ≠ t := by
  by_cases hc : c <;> simp [hc, ha, hb]

/-- Forward & converse characterization: `.badAnchors` is returned iff `anchorsValid = false`. -/
theorem reason_badAnchors_iff (minLevel : Nat) (v : BundleVerdict) :
    evalPolicy minLevel v = .badAnchors ↔ v.anchorsValid = false := by
  cases ha : v.anchorsValid
  · simp [evalPolicy, ha]
  · simp only [Bool.true_eq_false, iff_false]
    change evalPolicy minLevel v ≠ .badAnchors
    unfold evalPolicy
    simp only [ha, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
    repeat (first | decide | apply ite_ne)

/-- Every refused verdict carries a non-zero reason code in `1..20` (`everyRefusalHasAName`). -/
theorem every_refusal_has_nonzero_code (rc : ReasonCode) (hne : rc ≠ .pass) :
    1 ≤ rc.code ∧ rc.code ≤ 20 := by
  cases rc <;> simp [ReasonCode.code] at hne ⊢

theorem evalPolicy_ne_badGrant (minLevel : Nat) (v : BundleVerdict) :
    evalPolicy minLevel v ≠ .badGrant := by
  unfold evalPolicy
  repeat (first | decide | apply ite_ne)

/-- Forward & converse for `evalAdmit`: `.badGrant` is returned iff policy passed and `grantSigValid = false`. -/
theorem reason_badGrant_iff (v : BundleVerdict) (g : CapGrant) :
    evalAdmit v g = .badGrant ↔ (verifyPolicy 2 v = true ∧ g.grantSigValid = false) := by
  unfold evalAdmit
  have hp := evalPolicy_pass_iff 2 v
  cases h : evalPolicy 2 v with
  | pass =>
    have hv : verifyPolicy 2 v = true := hp.mp h
    cases hgs : g.grantSigValid
    · simp [hv]
    · cases hc : capAdmit g <;> simp [hv]
  | badGrant =>
    exact absurd h (evalPolicy_ne_badGrant 2 v)
  | _ =>
    have hv : verifyPolicy 2 v = false := by
      cases hv' : verifyPolicy 2 v
      · rfl
      · exfalso; have := hp.mpr hv'; rw [h] at this; cases this
    simp [hv]

/-! ### 7e. PrismPM Proof-Statement Axiom Policy & Replay Gate (`Foundation.Proof.V1.Statement`) -/

inductive AxiomPolicyKind where
  | none | allow | exact
  deriving DecidableEq

def allIn (xs ys : List String) : Bool :=
  xs.all (fun x => ys.contains x)

/-- Exact mirror of `Foundation.Proof.V1.Statement.withinPolicy` in `UOR-Foundation/prismpm`. -/
def withinAxiomPolicy (kind : AxiomPolicyKind) (allowed observed : List String) : Bool :=
  match kind with
  | .none  => observed.isEmpty
  | .allow => allIn observed allowed
  | .exact => allIn observed allowed && allIn allowed observed

structure ProofTheoremRec where
  resultOk     : Bool
  policyKind   : AxiomPolicyKind
  policyAxioms : List String
  observed     : List String
  deriving DecidableEq

def theoremPassed (t : ProofTheoremRec) : Bool :=
  t.resultOk && withinAxiomPolicy t.policyKind t.policyAxioms t.observed

def allTheoremsPassed (ts : List ProofTheoremRec) : Bool :=
  ts.all theoremPassed

def replaysClean (exits : List Nat) : Bool :=
  exits.all (fun c => c == 0)

def prismStatementPassed (ts : List ProofTheoremRec) (exits : List Nat) : Bool :=
  allTheoremsPassed ts && replaysClean exits

def standardLeanAxioms : List String :=
  ["propext", "Classical.choice", "Quot.sound"]

theorem withinAxiomPolicy_none_iff_empty (allowed observed : List String) :
    withinAxiomPolicy .none allowed observed = true ↔ observed = [] := by
  cases observed <;> simp [withinAxiomPolicy]

theorem allIn_contains_false {x : String} {xs ys : List String}
    (hmem : x ∈ xs) (hnot : ys.contains x = false) :
    allIn xs ys = false := by
  unfold allIn
  cases h : xs.all (fun y => ys.contains y)
  · rfl
  · exfalso
    rw [List.all_eq_true] at h
    have hx := h x hmem
    rw [hnot] at hx
    cases hx

/-- Any theorem depending on `sorryAx` is ALWAYS rejected under PrismPM's standard axiom policy. -/
theorem withinAxiomPolicy_standard_rejects_sorry (kind : AxiomPolicyKind) (observed : List String)
    (hsorry : "sorryAx" ∈ observed) :
    withinAxiomPolicy kind standardLeanAxioms observed = false := by
  have hnot : standardLeanAxioms.contains "sorryAx" = false := by decide
  have hall : allIn observed standardLeanAxioms = false := allIn_contains_false hsorry hnot
  cases kind with
  | none =>
    cases observed with
    | nil => cases hsorry
    | cons _ _ => rfl
  | allow => exact hall
  | exact => simp [withinAxiomPolicy, hall]

theorem replaysClean_iff_all_zero (exits : List Nat) :
    replaysClean exits = true ↔ ∀ c ∈ exits, c = 0 := by
  simp [replaysClean, List.all_eq_true]

/-- Negative control: a proof statement containing a theorem with `sorryAx` or a non-zero replay exit
    is refused by `prismStatementPassed`. -/
theorem neg_sorryAx_or_replay_fail_refused_by_prism_statement :
    prismStatementPassed
      [⟨true, .allow, standardLeanAxioms, ["propext", "sorryAx"]⟩] [0] = false ∧
    prismStatementPassed
      [⟨true, .allow, standardLeanAxioms, ["propext"]⟩] [0, 1] = false := by
  decide

/-! ## 8. Axiom Audit (must be empty or subset of `[propext, Classical.choice, Quot.sound]`) -/

#print axioms uorHdrLayout_tiles_384
#print axioms uorTrstBaseLayout_tiles_104
#print axioms uorGrantLayout_tiles_128
#print axioms sm121PayloadLayout_tiles_896
#print axioms neg_overlapping_layout_detected
#print axioms le32Pack_injective
#print axioms packQmdW34_injective
#print axioms dec_packQmdW35
#print axioms smemCfgFor_bounds
#print axioms qmd_reference_words
#print axioms packSassW0_injective
#print axioms sass_vecadd_reference_w0
#print axioms sm121_opcodes_pairwise_disjoint
#print axioms neg_unmasked_qmd_w34_corrupts_ty
#print axioms runVecadd_in_bounds
#print axioms runVecadd_preserves_canaries
#print axioms neg_unguarded_clobbers_canary
#print axioms uor_id_tamper_evident
#print axioms holo_seal_tamper_evident
#print axioms qmd_valid_enforces_skedcheck05
#print axioms anchors_separate_authority_and_signer
#print axioms neg_shared_auth_signer_refused
#print axioms evalPolicy_pass_iff
#print axioms evalAdmit_pass_iff
#print axioms verifyPolicy_monotone
#print axioms unsigned_never_above_p0
#print axioms safeInv_reachable
#print axioms no_unverified_gpu_touch
#print axioms neg_shortcut_dispatch_violates_safeInv
#print axioms uor_ring_critical_identity
#print axioms uor_ring_neg_involution
#print axioms uor_ring_bnot_involution
#print axioms uor_u32_add_comm_assoc
#print axioms vecadd_satisfies_contract
#print axioms framed_domain_disjoint
#print axioms neg_unframed_concat_ambiguity
#print axioms reason_badAnchors_iff
#print axioms every_refusal_has_nonzero_code
#print axioms reason_badGrant_iff
#print axioms withinAxiomPolicy_none_iff_empty
#print axioms withinAxiomPolicy_standard_rejects_sorry
#print axioms replaysClean_iff_all_zero
#print axioms neg_sorryAx_or_replay_fail_refused_by_prism_statement

end UorGpuWorld
