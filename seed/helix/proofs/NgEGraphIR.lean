/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/NgEGraphIR.lean

  Formal EGP3 Omega-NG E-Graph IR Soundness Proof in Lean 4:
    1. Parameterized inductive integer IR (`Expr w`) over arbitrary bit-width `w : Nat`
       (explicitly instantiated for both `w = 32` and `w = 64`), covering all 11 EGP3 opcodes:
         1=CONST, 2=SSA_VAL, 3=ADD, 4=SUB, 5=MUL, 6=FMA, 7=SHL, 8=SHR, 9=AND, 10=OR, 11=XOR.
    2. Explicit denotational semantics (`eval : Env w → Expr w → BitVec w`) with wrapping
       two's-complement arithmetic and hardware/ΩIR-aligned masked shift counts (`s.toNat % w`).
    3. All 18 machine-checked algebraic, bitwise, fusion, and strength-reduction rewrite theorems
       (`∀ env, eval env lhs = eval env rhs`) for arbitrary `w : Nat`, plus explicit
       `w = 32` and `w = 64` instantiations:
         1  `rw_fma_fuse`       : add(mul(a, b), c)   = fma(a, b, c)
         2  `rw_fma_fuse_comm`  : add(c, mul(a, b))   = fma(a, b, c)
         3  `rw_add_zero`       : add(x, 0)           = x
         4  `rw_zero_add`       : add(0, x)           = x
         5  `rw_mul_one`        : mul(x, 1)           = x
         6  `rw_mul_zero`       : mul(x, 0)           = 0
         7  `rw_add_comm`       : add(x, y)           = add(y, x)
         8  `rw_mul_comm`       : mul(x, y)           = mul(y, x)
         9  `rw_add_assoc`      : add(add(x, y), z)   = add(x, add(y, z))
         10 `rw_mul_assoc`      : mul(mul(x, y), z)   = mul(x, mul(y, z))
         11 `rw_and_self`       : and(x, x)           = x
         12 `rw_fma_zero_add`   : fma(a, b, 0)        = mul(a, b)
         13 `rw_sub_zero`       : sub(x, 0)           = x
         14 `rw_sub_self`       : sub(x, x)           = 0
         15 `rw_xor_self`       : xor(x, x)           = 0
         16 `rw_or_zero`        : or(x, 0)            = x
         17 `rw_shl_zero`       : shl(x, 0)           = x
         18 `rw_mul_pow2_shl`   : mul(x, 1 <<< k)     = shl(x, k)   (for k < w)
    4. Full congruence & multi-step e-graph equivalence closure (`EGraphStep`, `EGraphEquiv`)
       and extraction soundness (`egraph_extract_sound`, `egraph_extract_sound_32`,
       `egraph_extract_sound_64`).
    5. Non-vacuity negative controls:
         - `unsound_add_to_mul_counterexample` (32-bit and 64-bit)
         - `unsound_shl_oob_counterexample` (`mul(x, 1 <<< w) ≠ shl(x, w)` for `w = 32` and `w = 64`)
         - `unsound_mul_nonpow2_counterexample` (`mul(x, 3) ≠ shl(x, 1)`)

  Model-to-system link:
    Opcodes 1..11, bit-widths 32 & 64, and Rule IDs 1..18 mirror the exact structural
    verification kernel in `seed/ng/verify/egp3_checker.om` and its gate
    `seed/ng/verify/gate_egp3.om` (standalone pure-Omega checker, zero shared code with
    `seed/ng/egraph/` or `seed/ng/src/ir.om`).
-/

namespace NgEGraphIR

abbrev SsaId := Nat

/-- Concrete valuation of SSA values at bit-width `w`. -/
abbrev Env (w : Nat) := SsaId → BitVec w

/-- EGP3 integer expression AST parameterized by bit-width `w` (opcodes 1..11). -/
inductive Expr (w : Nat) where
  | const (v : BitVec w)              -- opcode 1:  CONST
  | ssa   (id : SsaId)                -- opcode 2:  SSA_VAL
  | add   (a b : Expr w)              -- opcode 3:  ADD
  | sub   (a b : Expr w)              -- opcode 4:  SUB
  | mul   (a b : Expr w)              -- opcode 5:  MUL
  | fma   (a b c : Expr w)            -- opcode 6:  FMA
  | shl   (a s : Expr w)              -- opcode 7:  SHL
  | shr   (a s : Expr w)              -- opcode 8:  SHR
  | band  (a b : Expr w)              -- opcode 9:  AND
  | bor   (a b : Expr w)              -- opcode 10: OR
  | bxor  (a b : Expr w)              -- opcode 11: XOR
  deriving DecidableEq, Repr

/-- Denotational semantics of EGP3 expressions over `BitVec w`.
    Shift counts are reduced modulo `w`, matching AArch64 `LSL`/`LSR` (W/X),
    Lean `UInt32`/`UInt64` shifts, and `seed/ng/verify/egp3_checker.om`. -/
def eval {w : Nat} (env : Env w) : Expr w → BitVec w
  | .const v    => v
  | .ssa id     => env id
  | .add a b    => eval env a + eval env b
  | .sub a b    => eval env a - eval env b
  | .mul a b    => eval env a * eval env b
  | .fma a b c  => (eval env a * eval env b) + eval env c
  | .shl a s    => eval env a <<< ((eval env s).toNat % w)
  | .shr a s    => eval env a >>> ((eval env s).toNat % w)
  | .band a b   => eval env a &&& eval env b
  | .bor a b    => eval env a ||| eval env b
  | .bxor a b   => eval env a ^^^ eval env b

/-- Semantic equivalence across all concrete SSA environments at width `w`. -/
def SemEq {w : Nat} (lhs rhs : Expr w) : Prop :=
  ∀ env : Env w, eval env lhs = eval env rhs

private theorem nat_lt_two_pow : ∀ n : Nat, n < 2 ^ n
  | 0 => by decide
  | n + 1 => by
    have ih := nat_lt_two_pow n
    have hpow : 2 ^ (n + 1) = 2 ^ n + 2 ^ n := by
      rw [Nat.pow_succ]
      omega
    omega

-- ==================== ALL 18 VERIFIED REWRITE THEOREMS ====================

/-- Rule 1: `add(mul(a, b), c) = fma(a, b, c)` -/
theorem rw_fma_fuse {w : Nat} (a b c : Expr w) :
    SemEq (.add (.mul a b) c) (.fma a b c) := by
  intro env; rfl

/-- Rule 2: `add(c, mul(a, b)) = fma(a, b, c)` -/
theorem rw_fma_fuse_comm {w : Nat} (a b c : Expr w) :
    SemEq (.add c (.mul a b)) (.fma a b c) := by
  intro env; simp [eval, BitVec.add_comm]

/-- Rule 3: `add(x, 0) = x` -/
theorem rw_add_zero {w : Nat} (x : Expr w) :
    SemEq (.add x (.const (0#w))) x := by
  intro env; simp [eval]

/-- Rule 4: `add(0, x) = x` -/
theorem rw_zero_add {w : Nat} (x : Expr w) :
    SemEq (.add (.const (0#w)) x) x := by
  intro env; simp [eval]

/-- Rule 5: `mul(x, 1) = x` -/
theorem rw_mul_one {w : Nat} (x : Expr w) :
    SemEq (.mul x (.const (1#w))) x := by
  intro env; simp [eval]

/-- Rule 6: `mul(x, 0) = 0` -/
theorem rw_mul_zero {w : Nat} (x : Expr w) :
    SemEq (.mul x (.const (0#w))) (.const (0#w)) := by
  intro env; simp [eval]

/-- Rule 7: `add(x, y) = add(y, x)` -/
theorem rw_add_comm {w : Nat} (x y : Expr w) :
    SemEq (.add x y) (.add y x) := by
  intro env; simp [eval, BitVec.add_comm]

/-- Rule 8: `mul(x, y) = mul(y, x)` -/
theorem rw_mul_comm {w : Nat} (x y : Expr w) :
    SemEq (.mul x y) (.mul y x) := by
  intro env; simp [eval, BitVec.mul_comm]

/-- Rule 9: `add(add(x, y), z) = add(x, add(y, z))` -/
theorem rw_add_assoc {w : Nat} (x y z : Expr w) :
    SemEq (.add (.add x y) z) (.add x (.add y z)) := by
  intro env; simp [eval, BitVec.add_assoc]

/-- Rule 10: `mul(mul(x, y), z) = mul(x, mul(y, z))` -/
theorem rw_mul_assoc {w : Nat} (x y z : Expr w) :
    SemEq (.mul (.mul x y) z) (.mul x (.mul y z)) := by
  intro env; simp [eval, BitVec.mul_assoc]

/-- Rule 11: `and(x, x) = x` -/
theorem rw_and_self {w : Nat} (x : Expr w) :
    SemEq (.band x x) x := by
  intro env; simp [eval]

/-- Rule 12: `fma(a, b, 0) = mul(a, b)` -/
theorem rw_fma_zero_add {w : Nat} (a b : Expr w) :
    SemEq (.fma a b (.const (0#w))) (.mul a b) := by
  intro env; simp [eval]

/-- Rule 13: `sub(x, 0) = x` -/
theorem rw_sub_zero {w : Nat} (x : Expr w) :
    SemEq (.sub x (.const (0#w))) x := by
  intro env; simp [eval]

/-- Rule 14: `sub(x, x) = 0` -/
theorem rw_sub_self {w : Nat} (x : Expr w) :
    SemEq (.sub x x) (.const (0#w)) := by
  intro env; simp [eval]

/-- Rule 15: `xor(x, x) = 0` -/
theorem rw_xor_self {w : Nat} (x : Expr w) :
    SemEq (.bxor x x) (.const (0#w)) := by
  intro env; simp [eval]

/-- Rule 16: `or(x, 0) = x` -/
theorem rw_or_zero {w : Nat} (x : Expr w) :
    SemEq (.bor x (.const (0#w))) x := by
  intro env; simp [eval]

/-- Rule 17: `shl(x, 0) = x` -/
theorem rw_shl_zero {w : Nat} (x : Expr w) :
    SemEq (.shl x (.const (0#w))) x := by
  intro env; simp [eval]

/-- Rule 18: `mul(x, 1 <<< k) = shl(x, k)` for every `k < w`. -/
theorem rw_mul_pow2_shl {w : Nat} (x : Expr w) (k : Nat) (hk : k < w) :
    SemEq (.mul x (.const ((1#w) <<< k))) (.shl x (.const (BitVec.ofNat w k))) := by
  intro env
  have hk_pow : k < 2 ^ w := Nat.lt_trans hk (nat_lt_two_pow w)
  have hw_pos : 0 < w := Nat.lt_of_le_of_lt (Nat.zero_le k) hk
  have h1_lt : 1 < 2 ^ w := by
    have hpow := nat_lt_two_pow w
    omega
  apply BitVec.eq_of_toNat_eq
  simp only [eval, BitVec.toNat_mul, BitVec.toNat_shiftLeft, BitVec.toNat_ofNat,
    Nat.shiftLeft_eq]
  rw [Nat.mod_eq_of_lt hk_pow, Nat.mod_eq_of_lt hk, Nat.mod_eq_of_lt h1_lt, Nat.one_mul]
  rw [Nat.mul_mod, Nat.mod_mod, ← Nat.mul_mod]

-- ==================== E-GRAPH SINGLE-STEP & MULTI-STEP CLOSURE ====================

/-- Single verified EGP3 rewrite step (Rules 1..18 + congruence for every operator operand). -/
inductive EGraphStep {w : Nat} : Expr w → Expr w → Prop
  | fma_fuse (a b c : Expr w)                  : EGraphStep (.add (.mul a b) c) (.fma a b c)
  | fma_fuse_comm (a b c : Expr w)             : EGraphStep (.add c (.mul a b)) (.fma a b c)
  | add_zero (x : Expr w)                      : EGraphStep (.add x (.const (0#w))) x
  | zero_add (x : Expr w)                      : EGraphStep (.add (.const (0#w)) x) x
  | mul_one (x : Expr w)                       : EGraphStep (.mul x (.const (1#w))) x
  | mul_zero (x : Expr w)                      : EGraphStep (.mul x (.const (0#w))) (.const (0#w))
  | add_comm (x y : Expr w)                    : EGraphStep (.add x y) (.add y x)
  | mul_comm (x y : Expr w)                    : EGraphStep (.mul x y) (.mul y x)
  | add_assoc (x y z : Expr w)                 : EGraphStep (.add (.add x y) z) (.add x (.add y z))
  | mul_assoc (x y z : Expr w)                 : EGraphStep (.mul (.mul x y) z) (.mul x (.mul y z))
  | and_self (x : Expr w)                      : EGraphStep (.band x x) x
  | fma_zero_add (a b : Expr w)                : EGraphStep (.fma a b (.const (0#w))) (.mul a b)
  | sub_zero (x : Expr w)                      : EGraphStep (.sub x (.const (0#w))) x
  | sub_self (x : Expr w)                      : EGraphStep (.sub x x) (.const (0#w))
  | xor_self (x : Expr w)                      : EGraphStep (.bxor x x) (.const (0#w))
  | or_zero (x : Expr w)                       : EGraphStep (.bor x (.const (0#w))) x
  | shl_zero (x : Expr w)                      : EGraphStep (.shl x (.const (0#w))) x
  | mul_pow2_shl (x : Expr w) (k : Nat) (hk : k < w) :
      EGraphStep (.mul x (.const ((1#w) <<< k))) (.shl x (.const (BitVec.ofNat w k)))
  | cong_add_l {a a' b}     : EGraphStep a a' → EGraphStep (.add a b) (.add a' b)
  | cong_add_r {a b b'}     : EGraphStep b b' → EGraphStep (.add a b) (.add a b')
  | cong_sub_l {a a' b}     : EGraphStep a a' → EGraphStep (.sub a b) (.sub a' b)
  | cong_sub_r {a b b'}     : EGraphStep b b' → EGraphStep (.sub a b) (.sub a b')
  | cong_mul_l {a a' b}     : EGraphStep a a' → EGraphStep (.mul a b) (.mul a' b)
  | cong_mul_r {a b b'}     : EGraphStep b b' → EGraphStep (.mul a b) (.mul a b')
  | cong_fma_a {a a' b c}   : EGraphStep a a' → EGraphStep (.fma a b c) (.fma a' b c)
  | cong_fma_b {a b b' c}   : EGraphStep b b' → EGraphStep (.fma a b c) (.fma a b' c)
  | cong_fma_c {a b c c'}   : EGraphStep c c' → EGraphStep (.fma a b c) (.fma a b c')
  | cong_shl_l {a a' s}     : EGraphStep a a' → EGraphStep (.shl a s) (.shl a' s)
  | cong_shl_r {a s s'}     : EGraphStep s s' → EGraphStep (.shl a s) (.shl a s')
  | cong_shr_l {a a' s}     : EGraphStep a a' → EGraphStep (.shr a s) (.shr a' s)
  | cong_shr_r {a s s'}     : EGraphStep s s' → EGraphStep (.shr a s) (.shr a s')
  | cong_band_l {a a' b}    : EGraphStep a a' → EGraphStep (.band a b) (.band a' b)
  | cong_band_r {a b b'}    : EGraphStep b b' → EGraphStep (.band a b) (.band a b')
  | cong_bor_l {a a' b}     : EGraphStep a a' → EGraphStep (.bor a b) (.bor a' b)
  | cong_bor_r {a b b'}     : EGraphStep b b' → EGraphStep (.bor a b) (.bor a b')
  | cong_bxor_l {a a' b}    : EGraphStep a a' → EGraphStep (.bxor a b) (.bxor a' b)
  | cong_bxor_r {a b b'}    : EGraphStep b b' → EGraphStep (.bxor a b) (.bxor a b')

/-- Multi-step reflexive-symmetric-transitive equivalence closure in the saturated e-graph. -/
inductive EGraphEquiv {w : Nat} : Expr w → Expr w → Prop
  | refl (e : Expr w)         : EGraphEquiv e e
  | step {a b c : Expr w}     : EGraphStep a b → EGraphEquiv b c → EGraphEquiv a c
  | symm {a b : Expr w}       : EGraphEquiv a b → EGraphEquiv b a
  | trans {a b c : Expr w}    : EGraphEquiv a b → EGraphEquiv b c → EGraphEquiv a c

theorem egraph_step_sound {w : Nat} {a b : Expr w} (h : EGraphStep a b) : SemEq a b := by
  induction h with
  | fma_fuse a b c           => exact rw_fma_fuse a b c
  | fma_fuse_comm a b c      => exact rw_fma_fuse_comm a b c
  | add_zero x               => exact rw_add_zero x
  | zero_add x               => exact rw_zero_add x
  | mul_one x                => exact rw_mul_one x
  | mul_zero x               => exact rw_mul_zero x
  | add_comm x y             => exact rw_add_comm x y
  | mul_comm x y             => exact rw_mul_comm x y
  | add_assoc x y z          => exact rw_add_assoc x y z
  | mul_assoc x y z          => exact rw_mul_assoc x y z
  | and_self x               => exact rw_and_self x
  | fma_zero_add a b         => exact rw_fma_zero_add a b
  | sub_zero x               => exact rw_sub_zero x
  | sub_self x               => exact rw_sub_self x
  | xor_self x               => exact rw_xor_self x
  | or_zero x                => exact rw_or_zero x
  | shl_zero x               => exact rw_shl_zero x
  | mul_pow2_shl x k hk      => exact rw_mul_pow2_shl x k hk
  | cong_add_l _ ih          => intro env; simp [eval, ih env]
  | cong_add_r _ ih          => intro env; simp [eval, ih env]
  | cong_sub_l _ ih          => intro env; simp [eval, ih env]
  | cong_sub_r _ ih          => intro env; simp [eval, ih env]
  | cong_mul_l _ ih          => intro env; simp [eval, ih env]
  | cong_mul_r _ ih          => intro env; simp [eval, ih env]
  | cong_fma_a _ ih          => intro env; simp [eval, ih env]
  | cong_fma_b _ ih          => intro env; simp [eval, ih env]
  | cong_fma_c _ ih          => intro env; simp [eval, ih env]
  | cong_shl_l _ ih          => intro env; simp [eval, ih env]
  | cong_shl_r _ ih          => intro env; simp [eval, ih env]
  | cong_shr_l _ ih          => intro env; simp [eval, ih env]
  | cong_shr_r _ ih          => intro env; simp [eval, ih env]
  | cong_band_l _ ih         => intro env; simp [eval, ih env]
  | cong_band_r _ ih         => intro env; simp [eval, ih env]
  | cong_bor_l _ ih          => intro env; simp [eval, ih env]
  | cong_bor_r _ ih          => intro env; simp [eval, ih env]
  | cong_bxor_l _ ih         => intro env; simp [eval, ih env]
  | cong_bxor_r _ ih         => intro env; simp [eval, ih env]

/-- Main E-Graph Soundness Theorem: ANY expression extracted from an EGP3-verified
    e-graph equivalence class has bit-identical semantics to the original expression
    on EVERY input environment at ANY bit-width `w`. -/
theorem egraph_extract_sound {w : Nat} {orig opt : Expr w} (h : EGraphEquiv orig opt) :
    SemEq orig opt := by
  induction h with
  | refl _ => intro env; rfl
  | step hs _ ih =>
    intro env
    rw [egraph_step_sound hs env, ih env]
  | symm _ ih =>
    intro env
    exact (ih env).symm
  | trans _ _ ih1 ih2 =>
    intro env
    rw [ih1 env, ih2 env]

-- ==================== EXPLICIT 32-BIT AND 64-BIT INSTANTIATIONS ====================

/-- 32-bit EGP3 extraction soundness (`BitVec 32`). -/
theorem egraph_extract_sound_32 {orig opt : Expr 32} (h : EGraphEquiv orig opt) :
    SemEq orig opt :=
  egraph_extract_sound h

/-- 64-bit EGP3 extraction soundness (`BitVec 64`). -/
theorem egraph_extract_sound_64 {orig opt : Expr 64} (h : EGraphEquiv orig opt) :
    SemEq orig opt :=
  egraph_extract_sound h

/-- 32-bit Rule 18 instantiation (`k < 32`). -/
theorem rw_mul_pow2_shl_32 (x : Expr 32) (k : Nat) (hk : k < 32) :
    SemEq (.mul x (.const ((1#32) <<< k))) (.shl x (.const (BitVec.ofNat 32 k))) :=
  rw_mul_pow2_shl x k hk

/-- 64-bit Rule 18 instantiation (`k < 64`). -/
theorem rw_mul_pow2_shl_64 (x : Expr 64) (k : Nat) (hk : k < 64) :
    SemEq (.mul x (.const ((1#64) <<< k))) (.shl x (.const (BitVec.ofNat 64 k))) :=
  rw_mul_pow2_shl x k hk

/-- Concrete 32-bit multi-step derivation:
    `add(mul(ssa 0, 1 <<< 5), sub(ssa 1, ssa 1))` ~> `shl(ssa 0, 5)`. -/
theorem ex_32bit_strength_reduce :
    SemEq (w := 32)
      (.add (.mul (.ssa 0) (.const ((1#32) <<< 5))) (.sub (.ssa 1) (.ssa 1)))
      (.shl (.ssa 0) (.const (BitVec.ofNat 32 5))) := by
  apply egraph_extract_sound_32
  apply EGraphEquiv.step (EGraphStep.cong_add_r (EGraphStep.sub_self (.ssa 1)))
  apply EGraphEquiv.step (EGraphStep.add_zero (.mul (.ssa 0) (.const ((1#32) <<< 5))))
  apply EGraphEquiv.step (EGraphStep.mul_pow2_shl (.ssa 0) 5 (by decide))
  exact EGraphEquiv.refl _

/-- Concrete 64-bit multi-step derivation:
    `or(shl(mul(ssa 0, 1 <<< 63), xor(ssa 1, ssa 1)), 0)` ~> `shl(ssa 0, 63)`. -/
theorem ex_64bit_strength_reduce :
    SemEq (w := 64)
      (.bor (.shl (.mul (.ssa 0) (.const ((1#64) <<< 63))) (.bxor (.ssa 1) (.ssa 1))) (.const (0#64)))
      (.shl (.ssa 0) (.const (BitVec.ofNat 64 63))) := by
  apply egraph_extract_sound_64
  apply EGraphEquiv.step (EGraphStep.or_zero _)
  apply EGraphEquiv.step (EGraphStep.cong_shl_r (EGraphStep.xor_self (.ssa 1)))
  apply EGraphEquiv.step (EGraphStep.shl_zero _)
  apply EGraphEquiv.step (EGraphStep.mul_pow2_shl (.ssa 0) 63 (by decide))
  exact EGraphEquiv.refl _

-- ==================== NON-VACUITY NEGATIVE CONTROLS ====================

/-- Negative Control 1 (32-bit): unsound rewrite `add(x, y) -> mul(x, y)` is refuted. -/
theorem unsound_add_to_mul_counterexample :
    ¬ SemEq (w := 32) (.add (.ssa 0) (.ssa 1)) (.mul (.ssa 0) (.ssa 1)) := by
  intro h
  have h0 := h (fun i => if i = 0 then 2#32 else 3#32)
  simp [eval] at h0

/-- Negative Control 1b (64-bit): unsound rewrite `add(x, y) -> mul(x, y)` is refuted. -/
theorem unsound_add_to_mul_counterexample_64 :
    ¬ SemEq (w := 64) (.add (.ssa 0) (.ssa 1)) (.mul (.ssa 0) (.ssa 1)) := by
  intro h
  have h0 := h (fun i => if i = 0 then 2#64 else 3#64)
  simp [eval] at h0

/-- Negative Control 2 (32-bit out-of-width shift): `mul(x, 1 <<< 32) ≠ shl(x, 32)`.
    Demonstrates why the side condition `k < w` in Rule 18 is strictly necessary. -/
theorem unsound_shl_oob_counterexample :
    ¬ SemEq (w := 32)
        (.mul (.ssa 0) (.const ((1#32) <<< 32)))
        (.shl (.ssa 0) (.const (BitVec.ofNat 32 32))) := by
  intro h
  have h0 := h (fun _ => 1#32)
  simp [eval] at h0

/-- Negative Control 2b (64-bit out-of-width shift): `mul(x, 1 <<< 64) ≠ shl(x, 64)`. -/
theorem unsound_shl_oob_counterexample_64 :
    ¬ SemEq (w := 64)
        (.mul (.ssa 0) (.const ((1#64) <<< 64)))
        (.shl (.ssa 0) (.const (BitVec.ofNat 64 64))) := by
  intro h
  have h0 := h (fun _ => 1#64)
  simp [eval] at h0

/-- Negative Control 3 (non-power-of-two spoof): `mul(x, 3) ≠ shl(x, 1)`. -/
theorem unsound_mul_nonpow2_counterexample :
    ¬ SemEq (w := 32)
        (.mul (.ssa 0) (.const (BitVec.ofNat 32 3)))
        (.shl (.ssa 0) (.const (BitVec.ofNat 32 1))) := by
  intro h
  have h0 := h (fun _ => 1#32)
  simp [eval] at h0

-- ==================== AXIOM AUDIT (STANDARD AXIOMS ONLY) ====================

#print axioms rw_fma_fuse
#print axioms rw_fma_fuse_comm
#print axioms rw_add_zero
#print axioms rw_zero_add
#print axioms rw_mul_one
#print axioms rw_mul_zero
#print axioms rw_add_comm
#print axioms rw_mul_comm
#print axioms rw_add_assoc
#print axioms rw_mul_assoc
#print axioms rw_and_self
#print axioms rw_fma_zero_add
#print axioms rw_sub_zero
#print axioms rw_sub_self
#print axioms rw_xor_self
#print axioms rw_or_zero
#print axioms rw_shl_zero
#print axioms rw_mul_pow2_shl
#print axioms egraph_extract_sound
#print axioms egraph_extract_sound_32
#print axioms egraph_extract_sound_64
#print axioms ex_32bit_strength_reduce
#print axioms ex_64bit_strength_reduce
#print axioms unsound_add_to_mul_counterexample
#print axioms unsound_add_to_mul_counterexample_64
#print axioms unsound_shl_oob_counterexample
#print axioms unsound_shl_oob_counterexample_64
#print axioms unsound_mul_nonpow2_counterexample

end NgEGraphIR
