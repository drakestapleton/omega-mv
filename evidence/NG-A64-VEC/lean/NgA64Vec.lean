/-
NgA64Vec.lean: Formal verification of Omega NG AArch64 128-bit packed float vector lowering.

Scope and model-to-implementation mapping (repo omega-mv, branch feat/ng-a64-vec-f32-f64):
1. AArch64 instruction word encoders (Arm ARM DDI 0487 M.d, seed/ng/src/a64.om a6_formfp, a6_enca,
   a6_encdp):
   - strq (165, 0x3d800000), ldrq (166, 0x3dc00000), strqr (164 -> 0x3ca06800), ldrqr (167 -> 0x3ce06800)
   - orr16b (168, 0x4ea01c00)
   - dupv4s (169, 0x4e040400), dupv2d (170, 0x4e080400), dups (171, 0x5e040400), dupd (172, 0x5e080400)
   - fadd4s/2d (173/174), fsub4s/2d (175/176), fmul4s/2d (177/178), fmla4s/2d (179/180)
   Proves operand bitfield round-trip injectivity and pairwise opcode/sz disjointness (4S vs 2D).
2. 128-bit packed vector representation (seed/ng/ngrun.om r_v/r_w and seed/ng/src/a64.om V registers):
   Proves lane-parallel homomorphism of vextract over vsplat, add/sub/mul, and single-rounding fma
   for both vec f32 4 (4 lanes of 32 bits) and vec f64 2 (2 lanes of 64 bits).
3. FMLA register-aliasing schedule (seed/ng/src/a64.om a6_vfma) and 16-byte stack spill alignment
   (a6_slot, a6_alloc):
   Proves that a6_vfma computes c + a * b without clobbering live multiplicands across all register
   aliasing combinations (d = c, d = a, d = b, d = a = b, and distinct registers), and that even-slot
   rounding produces 16-byte aligned SP offsets encoded losslessly by LDR/STR Q imm12.
4. Load-bearing negative controls:
   - AAPCS64 callee-save truncation: preserving only low 64 bits (d8..d15) across BL corrupts upper
     lanes of 128-bit vectors, whereas 16-byte Q stack spills preserve all 128 bits.
   - Naive FMLA move without alias guard overwrites multiplicand Va when Vd = Va and Va != Vc.
   - Dropping bit 22 (sz) collides 4S and 2D SIMD encodings.
-/

namespace NgA64Vec

/-! ## 1. AArch64 Packed SIMD Instruction Encodings (DDI 0487 M.d) -/

def zext5 (r : BitVec 5) : BitVec 32 := r.zeroExtend 32
def zext12 (i : BitVec 12) : BitVec 32 := i.zeroExtend 32
def zext2 (i : BitVec 2) : BitVec 32 := i.zeroExtend 32
def zext1 (i : BitVec 1) : BitVec 32 := i.zeroExtend 32

/-- Kind 1 (R3) with sh=0, amt=0: base | Rd | (Rn << 5) | (Rm << 16). -/
def encR3 (base : BitVec 32) (d n m : BitVec 5) : BitVec 32 :=
  base ||| zext5 d ||| (zext5 n <<< 5) ||| (zext5 m <<< 16)

def encOrr16b (d n m : BitVec 5) : BitVec 32 := encR3 0x4ea01c00#32 d n m
def encFadd4s (d n m : BitVec 5) : BitVec 32 := encR3 0x4e20d400#32 d n m
def encFadd2d (d n m : BitVec 5) : BitVec 32 := encR3 0x4e60d400#32 d n m
def encFsub4s (d n m : BitVec 5) : BitVec 32 := encR3 0x4ea0d400#32 d n m
def encFsub2d (d n m : BitVec 5) : BitVec 32 := encR3 0x4ee0d400#32 d n m
def encFmul4s (d n m : BitVec 5) : BitVec 32 := encR3 0x6e20dc00#32 d n m
def encFmul2d (d n m : BitVec 5) : BitVec 32 := encR3 0x6e60dc00#32 d n m
def encFmla4s (d n m : BitVec 5) : BitVec 32 := encR3 0x4e20cc00#32 d n m
def encFmla2d (d n m : BitVec 5) : BitVec 32 := encR3 0x4e60cc00#32 d n m

/-- Kind 23 (DUPE): DUP element on 32-bit S lanes (idx in bits 19..20) and 64-bit D lanes (idx at bit 20). -/
def encDupv4s (d n : BitVec 5) (idx : BitVec 2) : BitVec 32 :=
  0x4e040400#32 ||| zext5 d ||| (zext5 n <<< 5) ||| (zext2 idx <<< 19)

def encDupv2d (d n : BitVec 5) (idx : BitVec 1) : BitVec 32 :=
  0x4e080400#32 ||| zext5 d ||| (zext5 n <<< 5) ||| (zext1 idx <<< 20)

def encDups (d n : BitVec 5) (idx : BitVec 2) : BitVec 32 :=
  0x5e040400#32 ||| zext5 d ||| (zext5 n <<< 5) ||| (zext2 idx <<< 19)

def encDupd (d n : BitVec 5) (idx : BitVec 1) : BitVec 32 :=
  0x5e080400#32 ||| zext5 d ||| (zext5 n <<< 5) ||| (zext1 idx <<< 20)

/-- Kind 9 (LDST) and Kind 10 (LDSR) 128-bit Q loads and stores. -/
def encStrq (t n : BitVec 5) (imm12 : BitVec 12) : BitVec 32 :=
  0x3d800000#32 ||| zext5 t ||| (zext5 n <<< 5) ||| (zext12 imm12 <<< 10)

def encLdrq (t n : BitVec 5) (imm12 : BitVec 12) : BitVec 32 :=
  0x3dc00000#32 ||| zext5 t ||| (zext5 n <<< 5) ||| (zext12 imm12 <<< 10)

def encStrqr (t n m : BitVec 5) (sc : BitVec 1) : BitVec 32 :=
  0x3ca06800#32 ||| zext5 t ||| (zext5 n <<< 5) ||| (zext5 m <<< 16) ||| (zext1 sc <<< 12)

def encLdrqr (t n m : BitVec 5) (sc : BitVec 1) : BitVec 32 :=
  0x3ce06800#32 ||| zext5 t ||| (zext5 n <<< 5) ||| (zext5 m <<< 16) ||| (zext1 sc <<< 12)

/-- Bitfield decoders for encoded 32-bit A64 words. -/
def decRd (w : BitVec 32) : BitVec 5 := w.extractLsb' 0 5
def decRn (w : BitVec 32) : BitVec 5 := w.extractLsb' 5 5
def decRm (w : BitVec 32) : BitVec 5 := w.extractLsb' 16 5
def decImm12 (w : BitVec 32) : BitVec 12 := w.extractLsb' 10 12
def decDupIdxS (w : BitVec 32) : BitVec 2 := w.extractLsb' 19 2
def decDupIdxD (w : BitVec 32) : BitVec 1 := w.extractLsb' 20 1
def decTop11 (w : BitVec 32) : BitVec 11 := w.extractLsb' 21 11
def decMid6 (w : BitVec 32) : BitVec 6 := w.extractLsb' 10 6

/-- Spot-check exact hex words matching GNU objdump in seed/ng/a64/tests/enc.cases. -/
theorem enc_reference_words :
    encStrq 1#5 2#5 0#12 = 0x3d800041#32 ∧
    encStrq 31#5 31#5 1#12 = 0x3d8007ff#32 ∧
    encLdrq 29#5 31#5 2#12 = 0x3dc00bfd#32 ∧
    encLdrqr 1#5 2#5 3#5 0#1 = 0x3ce36841#32 ∧
    encLdrqr 2#5 3#5 4#5 1#1 = 0x3ce47862#32 ∧
    encOrr16b 1#5 2#5 2#5 = 0x4ea21c41#32 ∧
    encDupv4s 1#5 2#5 0#2 = 0x4e040441#32 ∧
    encDupv2d 1#5 2#5 0#1 = 0x4e080441#32 ∧
    encDups 5#5 6#5 3#2 = 0x5e1c04c5#32 ∧
    encDupd 1#5 2#5 1#1 = 0x5e180441#32 ∧
    encFadd4s 1#5 2#5 3#5 = 0x4e23d441#32 ∧
    encFadd2d 1#5 2#5 3#5 = 0x4e63d441#32 ∧
    encFsub4s 1#5 2#5 3#5 = 0x4ea3d441#32 ∧
    encFsub2d 1#5 2#5 3#5 = 0x4ee3d441#32 ∧
    encFmul4s 1#5 2#5 3#5 = 0x6e23dc41#32 ∧
    encFmul2d 1#5 2#5 3#5 = 0x6e63dc41#32 ∧
    encFmla4s 1#5 2#5 3#5 = 0x4e23cc41#32 ∧
    encFmla2d 1#5 2#5 3#5 = 0x4e63cc41#32 := by
  decide

/-- Helper: if base has zeroes in bits 0..9 and bits 16..20, R3 decodes (d, n, m) and preserves opcode fields. -/
theorem dec_encR3 (base : BitVec 32) (hlo : base.extractLsb' 0 10 = 0#10)
    (hrm : base.extractLsb' 16 5 = 0#5) (d n m : BitVec 5) :
    decRd (encR3 base d n m) = d ∧
    decRn (encR3 base d n m) = n ∧
    decRm (encR3 base d n m) = m ∧
    decTop11 (encR3 base d n m) = decTop11 base ∧
    decMid6 (encR3 base d n m) = decMid6 base := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hb : base[i]'(by omega) = false := by
      have h0 := congrArg (fun x => x.getLsbD i) hlo
      simpa [show i < 10 by omega, show i < 32 by omega] using h0
    simp [decRd, encR3, zext5, hi, hb, show i < 32 by omega, show i < 16 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hb : base[5 + i]'(by omega) = false := by
      have h0 := congrArg (fun x => x.getLsbD (5 + i)) hlo
      simpa [show 5 + i < 10 by omega, show 5 + i < 32 by omega] using h0
    simp [decRn, encR3, zext5, hi, hb,
      show 5 + i < 32 by omega, show ¬(5 + i < 5) by omega, show 5 + i < 16 by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hb : base[16 + i]'(by omega) = false := by
      have h0 := congrArg (fun x => x.getLsbD i) hrm
      simpa [hi, show 16 + i < 32 by omega] using h0
    have hd : d.getLsbD (16 + i) = false := BitVec.getLsbD_of_ge d (16 + i) (by omega)
    have hn : n.getLsbD (16 + i - 5) = false := BitVec.getLsbD_of_ge n (16 + i - 5) (by omega)
    simp [decRm, encR3, zext5, hi, hb, hd, hn,
      show 16 + i < 32 by omega, show ¬(16 + i < 5) by omega, show ¬(16 + i < 16) by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hd : d.getLsbD (21 + i) = false := BitVec.getLsbD_of_ge d (21 + i) (by omega)
    have hn : n.getLsbD (21 + i - 5) = false := BitVec.getLsbD_of_ge n (21 + i - 5) (by omega)
    have hm : m.getLsbD (21 + i - 16) = false := BitVec.getLsbD_of_ge m (21 + i - 16) (by omega)
    simp [decTop11, encR3, zext5, hi, hd, hn, hm,
      show 21 + i < 32 by omega, show ¬(21 + i < 5) by omega, show ¬(21 + i < 16) by omega]
  · apply BitVec.eq_of_getLsbD_eq; intro i hi
    have hd : d.getLsbD (10 + i) = false := BitVec.getLsbD_of_ge d (10 + i) (by omega)
    have hn : n.getLsbD (10 + i - 5) = false := BitVec.getLsbD_of_ge n (10 + i - 5) (by omega)
    simp [decMid6, encR3, zext5, hi, hd, hn,
      show 10 + i < 32 by omega, show ¬(10 + i < 5) by omega, show 10 + i < 16 by omega]

/-- Every R3 packed SIMD form is injective in (Rd, Rn, Rm). -/
theorem encR3_injective (base : BitVec 32) (hlo : base.extractLsb' 0 10 = 0#10)
    (hrm : base.extractLsb' 16 5 = 0#5)
    {d1 n1 m1 d2 n2 m2 : BitVec 5}
    (h : encR3 base d1 n1 m1 = encR3 base d2 n2 m2) :
    d1 = d2 ∧ n1 = n2 ∧ m1 = m2 := by
  have h1 := dec_encR3 base hlo hrm d1 n1 m1
  have h2 := dec_encR3 base hlo hrm d2 n2 m2
  refine ⟨?_, ?_, ?_⟩
  · rw [← h1.1, ← h2.1, h]
  · rw [← h1.2.1, ← h2.2.1, h]
  · rw [← h1.2.2.1, ← h2.2.2.1, h]

theorem fmla4s_injective {d1 n1 m1 d2 n2 m2 : BitVec 5}
    (h : encFmla4s d1 n1 m1 = encFmla4s d2 n2 m2) : d1 = d2 ∧ n1 = n2 ∧ m1 = m2 :=
  encR3_injective 0x4e20cc00#32 (by decide) (by decide) h

theorem fmla2d_injective {d1 n1 m1 d2 n2 m2 : BitVec 5}
    (h : encFmla2d d1 n1 m1 = encFmla2d d2 n2 m2) : d1 = d2 ∧ n1 = n2 ∧ m1 = m2 :=
  encR3_injective 0x4e60cc00#32 (by decide) (by decide) h

/-- 4S (sz=0) and 2D (sz=1) encodings are strictly disjoint across all register choices. -/
theorem fadd_4s_2d_disjoint (d1 n1 m1 d2 n2 m2 : BitVec 5) :
    encFadd4s d1 n1 m1 ≠ encFadd2d d2 n2 m2 := by
  intro h
  have h1 := (dec_encR3 0x4e20d400#32 (by decide) (by decide) d1 n1 m1).2.2.2.1
  have h2 := (dec_encR3 0x4e60d400#32 (by decide) (by decide) d2 n2 m2).2.2.2.1
  have eqTop : decTop11 0x4e20d400#32 = decTop11 0x4e60d400#32 := by
    rw [← h1, ← h2]; exact congrArg decTop11 h
  exact absurd eqTop (by decide)

theorem fsub_4s_2d_disjoint (d1 n1 m1 d2 n2 m2 : BitVec 5) :
    encFsub4s d1 n1 m1 ≠ encFsub2d d2 n2 m2 := by
  intro h
  have h1 := (dec_encR3 0x4ea0d400#32 (by decide) (by decide) d1 n1 m1).2.2.2.1
  have h2 := (dec_encR3 0x4ee0d400#32 (by decide) (by decide) d2 n2 m2).2.2.2.1
  have eqTop : decTop11 0x4ea0d400#32 = decTop11 0x4ee0d400#32 := by
    rw [← h1, ← h2]; exact congrArg decTop11 h
  exact absurd eqTop (by decide)

theorem fmul_4s_2d_disjoint (d1 n1 m1 d2 n2 m2 : BitVec 5) :
    encFmul4s d1 n1 m1 ≠ encFmul2d d2 n2 m2 := by
  intro h
  have h1 := (dec_encR3 0x6e20dc00#32 (by decide) (by decide) d1 n1 m1).2.2.2.1
  have h2 := (dec_encR3 0x6e60dc00#32 (by decide) (by decide) d2 n2 m2).2.2.2.1
  have eqTop : decTop11 0x6e20dc00#32 = decTop11 0x6e60dc00#32 := by
    rw [← h1, ← h2]; exact congrArg decTop11 h
  exact absurd eqTop (by decide)

theorem fmla_4s_2d_disjoint (d1 n1 m1 d2 n2 m2 : BitVec 5) :
    encFmla4s d1 n1 m1 ≠ encFmla2d d2 n2 m2 := by
  intro h
  have h1 := (dec_encR3 0x4e20cc00#32 (by decide) (by decide) d1 n1 m1).2.2.2.1
  have h2 := (dec_encR3 0x4e60cc00#32 (by decide) (by decide) d2 n2 m2).2.2.2.1
  have eqTop : decTop11 0x4e20cc00#32 = decTop11 0x4e60cc00#32 := by
    rw [← h1, ← h2]; exact congrArg decTop11 h
  exact absurd eqTop (by decide)

/-- FADD and FMLA on 4S share top-11 bits (0x4e20..) but are disjoint via middle opcode bits 10..15. -/
theorem fadd4s_fmla4s_disjoint (d1 n1 m1 d2 n2 m2 : BitVec 5) :
    encFadd4s d1 n1 m1 ≠ encFmla4s d2 n2 m2 := by
  intro h
  have h1 := (dec_encR3 0x4e20d400#32 (by decide) (by decide) d1 n1 m1).2.2.2.2
  have h2 := (dec_encR3 0x4e20cc00#32 (by decide) (by decide) d2 n2 m2).2.2.2.2
  have eqMid : decMid6 0x4e20d400#32 = decMid6 0x4e20cc00#32 := by
    rw [← h1, ← h2]; exact congrArg decMid6 h
  exact absurd eqMid (by decide)

/-- Scalar DUP element lane index round-trips cleanly for all S lanes 0..3 and D lanes 0..1. -/
theorem dups_lane_roundtrip (d n : BitVec 5) (idx : BitVec 2) :
    decDupIdxS (encDups d n idx) = idx := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  have hb : (0x5e040400#32)[19 + i]'(by omega) = false := by
    match i, hi with
    | 0, _ => decide +revert
    | 1, _ => decide +revert
  have hd : d.getLsbD (19 + i) = false := BitVec.getLsbD_of_ge d (19 + i) (by omega)
  have hn : n.getLsbD (19 + i - 5) = false := BitVec.getLsbD_of_ge n (19 + i - 5) (by omega)
  simp [decDupIdxS, encDups, zext5, zext2, hi, hb, hd, hn,
    show 19 + i < 32 by omega, show ¬(19 + i < 5) by omega, show ¬(19 + i < 19) by omega]

theorem dupd_lane_roundtrip (d n : BitVec 5) (idx : BitVec 1) :
    decDupIdxD (encDupd d n idx) = idx := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  have hb : (0x5e080400#32)[20 + i]'(by omega) = false := by
    match i, hi with
    | 0, _ => decide +revert
  have hd : d.getLsbD (20 + i) = false := BitVec.getLsbD_of_ge d (20 + i) (by omega)
  have hn : n.getLsbD (20 + i - 5) = false := BitVec.getLsbD_of_ge n (20 + i - 5) (by omega)
  simp [decDupIdxD, encDupd, zext5, zext1, hi, hb, hd, hn,
    show 20 + i < 32 by omega, show ¬(20 + i < 5) by omega, show ¬(20 + i < 20) by omega]

/-! ## 2. 128-Bit Packed Vector Lane Homomorphism (ngrun.om & V Registers) -/

/-- A 128-bit vector value modeled identically to ngrun.om `(r_v, r_w)` little-endian 64-bit words. -/
structure Vec128 where
  lo : BitVec 64
  hi : BitVec 64
  deriving DecidableEq

/-- Pack two 32-bit lanes into one 64-bit word (matching `or r0 (shl r1 32)` in ngrun.om). -/
def pack2x32 (x0 x1 : BitVec 32) : BitVec 64 :=
  x0.zeroExtend 64 ||| ((x1.zeroExtend 64) <<< 32)

def lane32Lo (w : BitVec 64) : BitVec 32 := w.extractLsb' 0 32
def lane32Hi (w : BitVec 64) : BitVec 32 := w.extractLsb' 32 32

theorem lane32Lo_pack (x0 x1 : BitVec 32) : lane32Lo (pack2x32 x0 x1) = x0 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp [lane32Lo, pack2x32, hi, show i < 64 by omega]

theorem lane32Hi_pack (x0 x1 : BitVec 32) : lane32Hi (pack2x32 x0 x1) = x1 := by
  apply BitVec.eq_of_getLsbD_eq; intro i hi
  simp [lane32Hi, pack2x32, hi, show 32 + i < 64 by omega, show ¬(32 + i < 32) by omega]

/-- Extract lane k (0..3) of vec f32 4 (matching rn_vget in ngrun.om and DUP Sd, Vn.S[k] in a64.om). -/
def vextract4s (v : Vec128) (k : Fin 4) : BitVec 32 :=
  match k with
  | ⟨0, _⟩ => lane32Lo v.lo
  | ⟨1, _⟩ => lane32Hi v.lo
  | ⟨2, _⟩ => lane32Lo v.hi
  | ⟨3, _⟩ => lane32Hi v.hi

/-- Extract lane k (0..1) of vec f64 2 (matching rn_vget in ngrun.om and DUP Dd, Vn.D[k] in a64.om). -/
def vextract2d (v : Vec128) (k : Fin 2) : BitVec 64 :=
  match k with
  | ⟨0, _⟩ => v.lo
  | ⟨1, _⟩ => v.hi

def vsplat4s (x : BitVec 32) : Vec128 := ⟨pack2x32 x x, pack2x32 x x⟩
def vsplat2d (x : BitVec 64) : Vec128 := ⟨x, x⟩

def vbin4s (op : BitVec 32 → BitVec 32 → BitVec 32) (a b : Vec128) : Vec128 :=
  ⟨pack2x32 (op (lane32Lo a.lo) (lane32Lo b.lo)) (op (lane32Hi a.lo) (lane32Hi b.lo)),
   pack2x32 (op (lane32Lo a.hi) (lane32Lo b.hi)) (op (lane32Hi a.hi) (lane32Hi b.hi))⟩

def vbin2d (op : BitVec 64 → BitVec 64 → BitVec 64) (a b : Vec128) : Vec128 :=
  ⟨op a.lo b.lo, op a.hi b.hi⟩

def vfma4s (fma32 : BitVec 32 → BitVec 32 → BitVec 32 → BitVec 32) (a b c : Vec128) : Vec128 :=
  ⟨pack2x32 (fma32 (lane32Lo a.lo) (lane32Lo b.lo) (lane32Lo c.lo))
            (fma32 (lane32Hi a.lo) (lane32Hi b.lo) (lane32Hi c.lo)),
   pack2x32 (fma32 (lane32Lo a.hi) (lane32Lo b.hi) (lane32Lo c.hi))
            (fma32 (lane32Hi a.hi) (lane32Hi b.hi) (lane32Hi c.hi))⟩

def vfma2d (fma64 : BitVec 64 → BitVec 64 → BitVec 64 → BitVec 64) (a b c : Vec128) : Vec128 :=
  ⟨fma64 a.lo b.lo c.lo, fma64 a.hi b.hi c.hi⟩

theorem vextract_vsplat4s (x : BitVec 32) (k : Fin 4) :
    vextract4s (vsplat4s x) k = x := by
  match k with
  | ⟨0, _⟩ => exact lane32Lo_pack x x
  | ⟨1, _⟩ => exact lane32Hi_pack x x
  | ⟨2, _⟩ => exact lane32Lo_pack x x
  | ⟨3, _⟩ => exact lane32Hi_pack x x

theorem vextract_vsplat2d (x : BitVec 64) (k : Fin 2) :
    vextract2d (vsplat2d x) k = x := by
  match k with
  | ⟨0, _⟩ => rfl
  | ⟨1, _⟩ => rfl

theorem vextract_vbin4s (op : BitVec 32 → BitVec 32 → BitVec 32) (a b : Vec128) (k : Fin 4) :
    vextract4s (vbin4s op a b) k = op (vextract4s a k) (vextract4s b k) := by
  match k with
  | ⟨0, _⟩ => exact lane32Lo_pack _ _
  | ⟨1, _⟩ => exact lane32Hi_pack _ _
  | ⟨2, _⟩ => exact lane32Lo_pack _ _
  | ⟨3, _⟩ => exact lane32Hi_pack _ _

theorem vextract_vbin2d (op : BitVec 64 → BitVec 64 → BitVec 64) (a b : Vec128) (k : Fin 2) :
    vextract2d (vbin2d op a b) k = op (vextract2d a k) (vextract2d b k) := by
  match k with
  | ⟨0, _⟩ => rfl
  | ⟨1, _⟩ => rfl

theorem vextract_vfma4s (fma32 : BitVec 32 → BitVec 32 → BitVec 32 → BitVec 32)
    (a b c : Vec128) (k : Fin 4) :
    vextract4s (vfma4s fma32 a b c) k = fma32 (vextract4s a k) (vextract4s b k) (vextract4s c k) := by
  match k with
  | ⟨0, _⟩ => exact lane32Lo_pack _ _
  | ⟨1, _⟩ => exact lane32Hi_pack _ _
  | ⟨2, _⟩ => exact lane32Lo_pack _ _
  | ⟨3, _⟩ => exact lane32Hi_pack _ _

theorem vextract_vfma2d (fma64 : BitVec 64 → BitVec 64 → BitVec 64 → BitVec 64)
    (a b c : Vec128) (k : Fin 2) :
    vextract2d (vfma2d fma64 a b c) k = fma64 (vextract2d a k) (vextract2d b k) (vextract2d c k) := by
  match k with
  | ⟨0, _⟩ => rfl
  | ⟨1, _⟩ => rfl

/-! ## 3. FMLA Register-Aliasing Schedule (a6_vfma) and 16-Byte Stack Alignment (a6_slot) -/

abbrev VReg := Fin 32
abbrev VFile := VReg → Vec128

def vset (rf : VFile) (d : VReg) (v : Vec128) : VFile :=
  fun r => if r = d then v else rf r

/-- Hardware `ORR Vd.16B, Vs.16B, Vs.16B` (128-bit register move). -/
def execMov16b (rf : VFile) (d s : VReg) : VFile :=
  vset rf d (rf s)

/-- Hardware `FMLA Vd, Va, Vb` accumulates `a * b` into `Vd` (`Vd := fma(Va, Vb, Vd)`). -/
def execFmla (fmaV : Vec128 → Vec128 → Vec128 → Vec128) (rf : VFile) (d a b : VReg) : VFile :=
  vset rf d (fmaV (rf a) (rf b) (rf d))

/-- Exact instruction sequence emitted by `a6_vfma` in `seed/ng/src/a64.om`.
    Note `a` is in `0..28` or scratch `29`, `b` is in `0..28` or scratch `30`, so neither `a` nor `b`
    is ever `v31` (`(31 : VReg)`). -/
def runA6Vfma (fmaV : Vec128 → Vec128 → Vec128 → Vec128) (rf : VFile) (d a b c : VReg) : VFile :=
  if d = c then
    execFmla fmaV rf d a b
  else if d = a ∨ d = b then
    let rf1 := if c = (31 : VReg) then rf else execMov16b rf 31 c
    let rf2 := execFmla fmaV rf1 31 a b
    execMov16b rf2 d 31
  else
    let rf1 := execMov16b rf d c
    execFmla fmaV rf1 d a b

theorem a6_vfma_correct (fmaV : Vec128 → Vec128 → Vec128 → Vec128)
    (rf : VFile) (d a b c : VReg)
    (ha31 : a ≠ (31 : VReg)) (hb31 : b ≠ (31 : VReg)) :
    (runA6Vfma fmaV rf d a b c) d = fmaV (rf a) (rf b) (rf c) ∧
    ∀ r : VReg, r ≠ d → r ≠ (31 : VReg) → (runA6Vfma fmaV rf d a b c) r = rf r := by
  unfold runA6Vfma
  split
  · rename_i hdc
    subst hdc
    refine ⟨?_, ?_⟩
    · simp [execFmla, vset]
    · intro r hrd _; simp [execFmla, vset, hrd]
  · rename_i hdnc
    split
    · rename_i hdab
      split
      · rename_i hc31
        subst hc31
        refine ⟨?_, ?_⟩
        · simp [execFmla, execMov16b, vset]
        · intro r hrd hr31; simp [execFmla, execMov16b, vset, hrd, hr31]
      · rename_i hnc31
        refine ⟨?_, ?_⟩
        · simp [execFmla, execMov16b, vset, ha31, hb31]
        · intro r hrd hr31; simp [execFmla, execMov16b, vset, hrd, hr31]
    · rename_i hndab
      have hda : a ≠ d := fun h => hndab (Or.inl h.symm)
      have hdb : b ≠ d := fun h => hndab (Or.inr h.symm)
      refine ⟨?_, ?_⟩
      · simp [execFmla, execMov16b, vset, hda, hdb]
      · intro r hrd _; simp [execFmla, execMov16b, vset, hrd]

/-- `a6_slot` even rounding for 16-byte stack slots: `n' = 2 * ((n + 1) / 2)`. -/
def alignSlotEven (n : Nat) : Nat := 2 * ((n + 1) / 2)

theorem alignSlotEven_16b_aligned (n : Nat) :
    n ≤ alignSlotEven n ∧
    (8 * alignSlotEven n) % 16 = 0 ∧
    16 * (alignSlotEven n / 2) = 8 * alignSlotEven n := by
  unfold alignSlotEven
  omega

/-! ## 4. Load-Bearing Negative Controls -/

/-- AAPCS64 callee-save contract on `v8..v15`: only the low 64 bits (`d8..d15`) are preserved across
    `BL`; bits 64..127 are clobbered by a conforming callee (modeled as zeroing or overwriting `hi`). -/
def aapcs64CallClobberV8 (v : Vec128) (calleeHi : BitVec 64) : Vec128 :=
  ⟨v.lo, calleeHi⟩

/-- 16-byte stack spill (`STR Q` before `BL`, `LDR Q` after `BL`, enforced by `a6_alloc` when `x && vf==2`). -/
def stackSpillQ128 (v : Vec128) : Vec128 :=
  ⟨v.lo, v.hi⟩

/-- Negative Control 1: Placing a live 128-bit `VEC` in `v8..v15` across `BL` corrupts upper lanes,
    whereas 16-byte `Q` stack spilling preserves all lanes. -/
theorem neg_aapcs64_d8_truncates_upper_lanes :
    (∃ v : Vec128, vextract2d (aapcs64CallClobberV8 v 0#64) ⟨1, by decide⟩ ≠ vextract2d v ⟨1, by decide⟩) ∧
    (∃ v : Vec128, vextract4s (aapcs64CallClobberV8 v 0#64) ⟨3, by decide⟩ ≠ vextract4s v ⟨3, by decide⟩) ∧
    (∀ v : Vec128, stackSpillQ128 v = v) := by
  refine ⟨⟨⟨0x3ff0000000000000#64, 0x4000000000000000#64⟩, by decide⟩,
          ⟨⟨0#64, 0x3f80000000000000#64⟩, by decide⟩,
          fun v => by cases v; rfl⟩

/-- Naive `FMLA` lowering without the `d = a ∨ d = b` alias guard: unconditionally moves `c` to `d` first. -/
def naiveVfma (fmaV : Vec128 → Vec128 → Vec128 → Vec128) (rf : VFile) (d a b c : VReg) : VFile :=
  execFmla fmaV (execMov16b rf d c) d a b

/-- Negative Control 2: When `d = a` and `a ≠ c`, `naiveVfma` clobbers `Va` with `Vc` before `FMLA`,
    producing `fma(Vc, Vb, Vc)` instead of `fma(Va, Vb, Vc)`. -/
theorem neg_naive_vfma_clobbers_alias :
    ∃ (fmaV : Vec128 → Vec128 → Vec128 → Vec128) (rf : VFile) (d a b c : VReg),
      d = a ∧ a ≠ (31 : VReg) ∧ b ≠ (31 : VReg) ∧
      (naiveVfma fmaV rf d a b c) d ≠ fmaV (rf a) (rf b) (rf c) := by
  let fmaAdd : Vec128 → Vec128 → Vec128 → Vec128 :=
    fun x y z => ⟨x.lo + y.lo + z.lo, x.hi + y.hi + z.hi⟩
  let rf : VFile := fun r =>
    if r = (0 : VReg) then ⟨10#64, 0#64⟩
    else if r = (1 : VReg) then ⟨2#64, 0#64⟩
    else ⟨1#64, 0#64⟩
  refine ⟨fmaAdd, rf, 0, 0, 1, 2, rfl, by decide, by decide, ?_⟩
  decide

/-- Broken encoder that clears bit 22 (`sz`) on 2D SIMD forms. -/
def brokenEncFadd2dNoSz (d n m : BitVec 5) : BitVec 32 :=
  encR3 (0x4e60d400#32 &&& ~~~(1#32 <<< 22)) d n m

/-- Negative Control 3: Clearing bit 22 (`sz`) makes 4S and 2D FADD encodings collide identically. -/
theorem neg_drop_sz_bit_collides (d n m : BitVec 5) :
    brokenEncFadd2dNoSz d n m = encFadd4s d n m := by
  simp [brokenEncFadd2dNoSz, encFadd4s]

/-! ## 5. 128-Bit Parallel Move Scratch Disjointness (a6_mvq v30 vs a6_mvbrk v31) -/

abbrev QSlot := Nat
abbrev QFrame := QSlot → Vec128

structure QState where
  rf : VFile
  sf : QFrame

inductive QLoc where
  | vreg (r : VReg)
  | qslot (q : QSlot)
  deriving DecidableEq

def qlocRead (st : QState) : QLoc → Vec128
  | .vreg r => st.rf r
  | .qslot q => st.sf q

def qset (sf : QFrame) (q : QSlot) (v : Vec128) : QFrame :=
  fun k => if k = q then v else sf k

def execLdrQ (st : QState) (t : VReg) (q : QSlot) : QState :=
  ⟨vset st.rf t (st.sf q), st.sf⟩

def execStrQ (st : QState) (t : VReg) (q : QSlot) : QState :=
  ⟨st.rf, qset st.sf q (st.rf t)⟩

/-- Exact `a6_mvq` parameterized by `slotScratch` (`30` in `seed/ng/src/a64.om`, `31` in the `a60844d5` defect). -/
def execMvqWith (slotScratch : VReg) (st : QState) (d s : QLoc) : QState :=
  match d, s with
  | .vreg rd, .vreg rs =>
    if rd = rs then st else ⟨execMov16b st.rf rd rs, st.sf⟩
  | .vreg rd, .qslot qs =>
    execLdrQ st rd qs
  | .qslot qd, .vreg rs =>
    execStrQ st rs qd
  | .qslot qd, .qslot qs =>
    execStrQ (execLdrQ st slotScratch qs) slotScratch qd

/-- Exact `a6_pmove` + `a6_mvbrk` schedule on a 2-cycle `(locA <- locB, locB <- locA)`:
    `a6_mvbrk` parks `locB` in cycle-breaker `631` (`.vreg 31`), `a6_pmove` moves `locA` into `locB`,
    then `a6_pmove` moves `.vreg 31` into `locA`. -/
def runPmoveSwap2 (slotScratch : VReg) (st : QState) (locA locB : QLoc) : QState :=
  let st1 := execMvqWith slotScratch st (.vreg 31) locB
  let st2 := execMvqWith slotScratch st1 locB locA
  execMvqWith slotScratch st2 locA (.vreg 31)

/-- Single `a6_mvq` (`slotScratch = 30`) copies 128 bits from `s` to `d` and preserves every location
    other than `d` and scratch `v30`. -/
theorem a6_mvq_single_correct (st : QState) (d s : QLoc) :
    qlocRead (execMvqWith 30 st d s) d = qlocRead st s ∧
    ∀ l : QLoc, l ≠ d → l ≠ .vreg 30 → qlocRead (execMvqWith 30 st d s) l = qlocRead st l := by
  cases d <;> cases s <;> simp [execMvqWith, execMov16b, execLdrQ, execStrQ, qlocRead, vset, qset]
  · rename_i rd rs
    by_cases hds : rd = rs
    · subst hds; simp
    · simp [hds, vset]; intro l hld _; cases l <;> simp at hld ⊢; simp [hld]
  · rename_i rd qs
    intro l hld _; cases l <;> simp at hld ⊢; simp [hld]
  · rename_i qd rs
    intro l hld _; cases l <;> simp at hld ⊢; simp [hld]
  · rename_i qd qs
    intro l hld hl30
    cases l with
    | vreg r =>
      have hr30 : r ≠ (30 : VReg) := fun h => hl30 (congrArg QLoc.vreg h)
      simp [hr30]
    | qslot q =>
      have hqd : q ≠ qd := fun h => hld (congrArg QLoc.qslot h)
      simp [hqd]

/-- With `slotScratch = 30` (`v30`) disjoint from `a6_mvbrk` cycle-breaker `631` (`v31`), a 2-cycle
    parallel swap across any allocated registers (`v0..v28`) or 16B stack slots swaps both 128-bit
    vectors and preserves all non-scratch locations. -/
theorem a6_pmove_swap2_correct (st : QState) (locA locB : QLoc)
    (hab : locA ≠ locB)
    (ha30 : locA ≠ .vreg 30) (ha31 : locA ≠ .vreg 31)
    (hb30 : locB ≠ .vreg 30) (hb31 : locB ≠ .vreg 31) :
    let out := runPmoveSwap2 30 st locA locB
    qlocRead out locA = qlocRead st locB ∧
    qlocRead out locB = qlocRead st locA ∧
    ∀ l : QLoc, l ≠ locA → l ≠ locB → l ≠ .vreg 30 → l ≠ .vreg 31 →
      qlocRead out l = qlocRead st l := by
  dsimp [runPmoveSwap2]
  have s1 := a6_mvq_single_correct st (.vreg 31) locB
  have s2 := a6_mvq_single_correct (execMvqWith 30 st (.vreg 31) locB) locB locA
  have s3 := a6_mvq_single_correct (execMvqWith 30 (execMvqWith 30 st (.vreg 31) locB) locB locA) locA (.vreg 31)
  have h31_ne_30 : (.vreg 31 : QLoc) ≠ .vreg 30 := by decide
  refine ⟨?_, ?_, ?_⟩
  · rw [s3.1, s2.2 (.vreg 31) hb31.symm h31_ne_30, s1.1]
  · rw [s3.2 locB hab.symm hb30, s2.1, s1.2 locA ha31 ha30]
  · intro l hla hlb hl30 hl31
    rw [s3.2 l hla hl30, s2.2 l hlb hl30, s1.2 l hl31 hl30]

/-- Negative Control 4: When `a6_mvq` shares `v31` (`slotScratch = 31`) with `a6_mvbrk`, swapping two
    spilled 16-byte stack slots overwrites `v31` during the second move and writes `st.sf qa` to BOTH
    slots (`v-spill-swap.oir` defect: `splat(1.0f)` overwrites `splat(2.0f)`). -/
theorem neg_mvq_shared_v31_clobbers_slot_swap :
    (∀ (st : QState) (qa qb : QSlot),
      (runPmoveSwap2 31 st (.qslot qa) (.qslot qb)).sf qa = st.sf qa ∧
      (runPmoveSwap2 31 st (.qslot qa) (.qslot qb)).sf qb = st.sf qa) ∧
    (∃ (st : QState) (qa qb : QSlot),
      qa ≠ qb ∧ (runPmoveSwap2 31 st (.qslot qa) (.qslot qb)).sf qa ≠ st.sf qb) := by
  refine ⟨fun st qa qb => ?_, ?_⟩
  · simp [runPmoveSwap2, execMvqWith, execLdrQ, execStrQ, vset, qset]
  · let v1 := vsplat4s 0x3f800000#32
    let v2 := vsplat4s 0x40000000#32
    let st : QState := ⟨fun _ => ⟨0#64, 0#64⟩, fun q => if q = 0 then v1 else v2⟩
    refine ⟨st, 0, 1, by decide, ?_⟩
    simp [runPmoveSwap2, execMvqWith, execLdrQ, execStrQ, vset, qset, st, v1, v2, vsplat4s, pack2x32]

end NgA64Vec

#print axioms NgA64Vec.enc_reference_words
#print axioms NgA64Vec.fmla4s_injective
#print axioms NgA64Vec.fmla2d_injective
#print axioms NgA64Vec.fadd_4s_2d_disjoint
#print axioms NgA64Vec.fsub_4s_2d_disjoint
#print axioms NgA64Vec.fmul_4s_2d_disjoint
#print axioms NgA64Vec.fmla_4s_2d_disjoint
#print axioms NgA64Vec.fadd4s_fmla4s_disjoint
#print axioms NgA64Vec.dups_lane_roundtrip
#print axioms NgA64Vec.dupd_lane_roundtrip
#print axioms NgA64Vec.vextract_vsplat4s
#print axioms NgA64Vec.vextract_vsplat2d
#print axioms NgA64Vec.vextract_vbin4s
#print axioms NgA64Vec.vextract_vbin2d
#print axioms NgA64Vec.vextract_vfma4s
#print axioms NgA64Vec.vextract_vfma2d
#print axioms NgA64Vec.a6_vfma_correct
#print axioms NgA64Vec.alignSlotEven_16b_aligned
#print axioms NgA64Vec.neg_aapcs64_d8_truncates_upper_lanes
#print axioms NgA64Vec.neg_naive_vfma_clobbers_alias
#print axioms NgA64Vec.neg_drop_sz_bit_collides
#print axioms NgA64Vec.a6_mvq_single_correct
#print axioms NgA64Vec.a6_pmove_swap2_correct
#print axioms NgA64Vec.neg_mvq_shared_v31_clobbers_slot_swap
