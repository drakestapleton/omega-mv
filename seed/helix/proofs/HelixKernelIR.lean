/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/HelixKernelIR.lean

  Phase 2 Formal Kernel IR & Verified Equality-Saturation Soundness in Lean 4:
    1. Compact inductive kernel DSL (`KExpr`) modeling hot SM121 GPU & host inner loops
       (register loads, constants, 32-bit wrapping arithmetic, fused multiply-add `fma`,
       bit-shifts, masks, bitwise ops, warp butterfly shuffle `shflXor`, memory tile load).
    2. Explicit denotational semantics (`eval : Env → KExpr → UInt32`).
    3. 12 machine-checked algebraic & SM121 fusion rewrite theorems
       (`∀ env, eval env lhs = eval env rhs`):
         - `rw_fma_fuse`       : add (mul a b) c  = fma a b c
         - `rw_fma_fuse_comm`  : add c (mul a b)  = fma a b c
         - `rw_add_zero`       : add x 0          = x
         - `rw_zero_add`       : add 0 x          = x
         - `rw_mul_one`        : mul x 1          = x
         - `rw_mul_zero`       : mul x 0          = 0
         - `rw_add_comm`       : add x y          = add y x
         - `rw_mul_comm`       : mul x y          = mul y x
         - `rw_add_assoc`      : add (add x y) z  = add x (add y z)
         - `rw_mul_assoc`      : mul (mul x y) z  = mul x (mul y z)
         - `rw_and_self`       : band x x         = x
         - `rw_fma_zero_add`   : fma a b 0        = mul a b
    4. Verified equality-saturation step & multi-step soundness (`EGraphStep`, `EGraphEquiv`),
       proving that any e-graph saturation + GB10 cost-model extraction preserves exact
       denotational semantics for ALL input environments (`egraph_extract_sound`).
    5. Non-vacuity negative control (`unsound_rewrite_counterexample`): proves that an
       unsound rewrite (`add a b -> mul a b`) genuinely fails on a concrete environment.

  Model-to-system link:
    Rule IDs 1..12 mirror the exact rule table in `seed/helix/egraph_opt.om` and
    `seed/helix/dual_checker.om`.
-/

namespace HelixKernelIR

abbrev RegId := Nat

structure Env where
  reg    : RegId → UInt32
  shfl   : UInt32 → UInt32 → UInt32
  tileLd : UInt32 → UInt32

inductive KExpr where
  | kconst (v : UInt32)
  | kreg   (r : RegId)
  | kadd   (a b : KExpr)
  | ksub   (a b : KExpr)
  | kmul   (a b : KExpr)
  | kfma   (a b c : KExpr)
  | kshl   (a s : KExpr)
  | kshr   (a s : KExpr)
  | kband  (a b : KExpr)
  | kbor   (a b : KExpr)
  | kshfl  (val laneMask : KExpr)
  | ktile  (addr : KExpr)
  deriving DecidableEq, Repr

/-- Explicit denotational semantics of the SM121/host kernel IR. -/
def eval (env : Env) : KExpr → UInt32
  | .kconst v      => v
  | .kreg r        => env.reg r
  | .kadd a b      => eval env a + eval env b
  | .ksub a b      => eval env a - eval env b
  | .kmul a b      => eval env a * eval env b
  | .kfma a b c    => (eval env a * eval env b) + eval env c
  | .kshl a s      => eval env a <<< eval env s
  | .kshr a s      => eval env a >>> eval env s
  | .kband a b     => eval env a &&& eval env b
  | .kbor a b      => eval env a ||| eval env b
  | .kshfl v m     => env.shfl (eval env v) (eval env m)
  | .ktile addr    => env.tileLd (eval env addr)

/-- GB10 SM121 instruction cost model (cycles / issue slots). -/
def gb10Cost : KExpr → Nat
  | .kconst _   => 0
  | .kreg _     => 0
  | .kadd a b   => 2 + gb10Cost a + gb10Cost b
  | .ksub a b   => 2 + gb10Cost a + gb10Cost b
  | .kmul a b   => 3 + gb10Cost a + gb10Cost b
  | .kfma a b c => 2 + gb10Cost a + gb10Cost b + gb10Cost c  -- 1 fused IMAD/FFMA beats MUL(3)+ADD(2)=5!
  | .kshl a s   => 1 + gb10Cost a + gb10Cost s
  | .kshr a s   => 1 + gb10Cost a + gb10Cost s
  | .kband a b  => 1 + gb10Cost a + gb10Cost b
  | .kbor a b   => 1 + gb10Cost a + gb10Cost b
  | .kshfl v m  => 4 + gb10Cost v + gb10Cost m
  | .ktile addr => 6 + gb10Cost addr

/-- Semantic equivalence of two kernel IR expressions across all environments. -/
def SemEq (lhs rhs : KExpr) : Prop :=
  ∀ env : Env, eval env lhs = eval env rhs

-- ==================== 12 VERIFIED REWRITE THEOREMS ====================

theorem rw_fma_fuse (a b c : KExpr) :
    SemEq (.kadd (.kmul a b) c) (.kfma a b c) := by
  intro env; rfl

theorem rw_fma_fuse_comm (a b c : KExpr) :
    SemEq (.kadd c (.kmul a b)) (.kfma a b c) := by
  intro env; simp [eval, UInt32.add_comm]

theorem rw_add_zero (x : KExpr) :
    SemEq (.kadd x (.kconst 0)) x := by
  intro env; simp [eval]

theorem rw_zero_add (x : KExpr) :
    SemEq (.kadd (.kconst 0) x) x := by
  intro env; simp [eval]

theorem rw_mul_one (x : KExpr) :
    SemEq (.kmul x (.kconst 1)) x := by
  intro env; simp [eval]

theorem rw_mul_zero (x : KExpr) :
    SemEq (.kmul x (.kconst 0)) (.kconst 0) := by
  intro env; simp [eval]

theorem rw_add_comm (x y : KExpr) :
    SemEq (.kadd x y) (.kadd y x) := by
  intro env; simp [eval, UInt32.add_comm]

theorem rw_mul_comm (x y : KExpr) :
    SemEq (.kmul x y) (.kmul y x) := by
  intro env; simp [eval, UInt32.mul_comm]

theorem rw_add_assoc (x y z : KExpr) :
    SemEq (.kadd (.kadd x y) z) (.kadd x (.kadd y z)) := by
  intro env; simp [eval, UInt32.add_assoc]

theorem rw_mul_assoc (x y z : KExpr) :
    SemEq (.kmul (.kmul x y) z) (.kmul x (.kmul y z)) := by
  intro env; simp [eval, UInt32.mul_assoc]

theorem rw_and_self (x : KExpr) :
    SemEq (.kband x x) x := by
  intro env
  simp only [eval]
  apply UInt32.eq_of_toBitVec_eq
  simp

theorem rw_fma_zero_add (a b : KExpr) :
    SemEq (.kfma a b (.kconst 0)) (.kmul a b) := by
  intro env; simp [eval]

/-- Verified single equality-saturation rewrite step (including congruence inside subexpressions). -/
inductive EGraphStep : KExpr → KExpr → Prop
  | fma_fuse (a b c : KExpr)      : EGraphStep (.kadd (.kmul a b) c) (.kfma a b c)
  | fma_fuse_comm (a b c : KExpr) : EGraphStep (.kadd c (.kmul a b)) (.kfma a b c)
  | add_zero (x : KExpr)          : EGraphStep (.kadd x (.kconst 0)) x
  | zero_add (x : KExpr)          : EGraphStep (.kadd (.kconst 0) x) x
  | mul_one (x : KExpr)           : EGraphStep (.kmul x (.kconst 1)) x
  | mul_zero (x : KExpr)          : EGraphStep (.kmul x (.kconst 0)) (.kconst 0)
  | add_comm (x y : KExpr)        : EGraphStep (.kadd x y) (.kadd y x)
  | mul_comm (x y : KExpr)        : EGraphStep (.kmul x y) (.kmul y x)
  | add_assoc (x y z : KExpr)     : EGraphStep (.kadd (.kadd x y) z) (.kadd x (.kadd y z))
  | mul_assoc (x y z : KExpr)     : EGraphStep (.kmul (.kmul x y) z) (.kmul x (.kmul y z))
  | and_self (x : KExpr)          : EGraphStep (.kband x x) x
  | fma_zero_add (a b : KExpr)    : EGraphStep (.kfma a b (.kconst 0)) (.kmul a b)
  | cong_add_l {a a' b}           : EGraphStep a a' → EGraphStep (.kadd a b) (.kadd a' b)
  | cong_add_r {a b b'}           : EGraphStep b b' → EGraphStep (.kadd a b) (.kadd a b')
  | cong_mul_l {a a' b}           : EGraphStep a a' → EGraphStep (.kmul a b) (.kmul a' b)
  | cong_mul_r {a b b'}           : EGraphStep b b' → EGraphStep (.kmul a b) (.kmul a b')
  | cong_fma_a {a a' b c}         : EGraphStep a a' → EGraphStep (.kfma a b c) (.kfma a' b c)
  | cong_fma_b {a b b' c}         : EGraphStep b b' → EGraphStep (.kfma a b c) (.kfma a b' c)
  | cong_fma_c {a b c c'}         : EGraphStep c c' → EGraphStep (.kfma a b c) (.kfma a b c')
  | cong_shfl_v {v v' m}          : EGraphStep v v' → EGraphStep (.kshfl v m) (.kshfl v' m)
  | cong_tile {a a'}              : EGraphStep a a' → EGraphStep (.ktile a) (.ktile a')

/-- Equivalence closure in the saturated e-graph. -/
inductive EGraphEquiv : KExpr → KExpr → Prop
  | refl (e : KExpr) : EGraphEquiv e e
  | step {a b c} : EGraphStep a b → EGraphEquiv b c → EGraphEquiv a c
  | symm {a b} : EGraphEquiv a b → EGraphEquiv b a

theorem egraph_step_sound {a b : KExpr} (h : EGraphStep a b) : SemEq a b := by
  induction h with
  | fma_fuse a b c      => exact rw_fma_fuse a b c
  | fma_fuse_comm a b c => exact rw_fma_fuse_comm a b c
  | add_zero x          => exact rw_add_zero x
  | zero_add x          => exact rw_zero_add x
  | mul_one x           => exact rw_mul_one x
  | mul_zero x          => exact rw_mul_zero x
  | add_comm x y        => exact rw_add_comm x y
  | mul_comm x y        => exact rw_mul_comm x y
  | add_assoc x y z     => exact rw_add_assoc x y z
  | mul_assoc x y z     => exact rw_mul_assoc x y z
  | and_self x          => exact rw_and_self x
  | fma_zero_add a b    => exact rw_fma_zero_add a b
  | cong_add_l _ ih     => intro env; simp [eval, ih env]
  | cong_add_r _ ih     => intro env; simp [eval, ih env]
  | cong_mul_l _ ih     => intro env; simp [eval, ih env]
  | cong_mul_r _ ih     => intro env; simp [eval, ih env]
  | cong_fma_a _ ih     => intro env; simp [eval, ih env]
  | cong_fma_b _ ih     => intro env; simp [eval, ih env]
  | cong_fma_c _ ih     => intro env; simp [eval, ih env]
  | cong_shfl_v _ ih    => intro env; simp [eval, ih env]
  | cong_tile _ ih      => intro env; simp [eval, ih env]

/-- Main E-Graph Soundness Theorem: ANY expression extracted from a saturated e-graph
    (including the minimum GB10-cost schedule) has the EXACT same semantics on every input. -/
theorem egraph_extract_sound {orig opt : KExpr} (h : EGraphEquiv orig opt) : SemEq orig opt := by
  induction h with
  | refl _ => intro env; rfl
  | step hs _ ih =>
    intro env
    rw [egraph_step_sound hs env, ih env]
  | symm _ ih =>
    intro env
    exact (ih env).symm

/-- Concrete Cost-Reduction Proof: fusing `add (mul (kreg 0) (kreg 1)) (add (kreg 2) 0)`
    into `fma (kreg 0) (kreg 1) (kreg 2)` is semantically identical AND strictly lowers GB10 cost (7 -> 2). -/
def exOrig : KExpr := .kadd (.kmul (.kreg 0) (.kreg 1)) (.kadd (.kreg 2) (.kconst 0))
def exOpt  : KExpr := .kfma (.kreg 0) (.kreg 1) (.kreg 2)

theorem ex_gemv_mac_equiv : SemEq exOrig exOpt := by
  apply egraph_extract_sound
  apply EGraphEquiv.step (EGraphStep.cong_add_r (EGraphStep.add_zero (.kreg 2)))
  apply EGraphEquiv.step (EGraphStep.fma_fuse (.kreg 0) (.kreg 1) (.kreg 2))
  exact EGraphEquiv.refl _

theorem ex_gemv_mac_strictly_faster : gb10Cost exOpt < gb10Cost exOrig := by
  decide

/-- Non-Vacuity Negative Control: an unsound rewrite (`add -> mul`) is refuted. -/
theorem unsound_rewrite_counterexample :
    ¬ SemEq (.kadd (.kreg 0) (.kreg 1)) (.kmul (.kreg 0) (.kreg 1)) := by
  intro h
  have h0 := h { reg := fun i => if i = 0 then 2 else 3, shfl := fun v _ => v, tileLd := fun a => a }
  simp [eval] at h0

#print axioms rw_fma_fuse
#print axioms rw_and_self
#print axioms egraph_extract_sound
#print axioms ex_gemv_mac_equiv
#print axioms ex_gemv_mac_strictly_faster
#print axioms unsound_rewrite_counterexample

end HelixKernelIR
