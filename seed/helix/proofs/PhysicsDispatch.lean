/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/PhysicsDispatch.lean

  Standalone machine-checked Lean 4 safety proof for Sovereign Intelligence 2.0 Stage 3
  (Pillar 3: Physics-Typed Computing — `seed/ng/physics/phys_solver.om` <-> `watt_cbf.om`
  <-> `fabHotSwap`).

  Zero `sorry`, zero warnings, zero Mathlib dependency, standard Lean 4 axioms only.

  Proved properties (exact 1:1 fixed-point mirror of `phys_solver.om` and `watt_cbf.om`):
    1. Inviolable Hardware `WattCBF` Power & Thermal Safety (`admitted_respects_wattcbf`):
       Every realization dispatched by `solveDispatch` is proof-verified (`proofMask = 7`),
       admitted un-clamped by `cbfFilter` (`failClosed = false`), respects the Trap-14 80 W
       GPU hard ceiling (`pGpu <= min 80000 pol.pGpuBudget`), whole-unit Watt conservation
       (`pGpu + pCpu + pUnc <= min pol.pBudget 140000`), discrete CBF barrier invariance
       (`barrierH >= 0` and next-step `tDie' <= tCeil`), and the ΩIR v2 `@power` ceiling.
    2. Inviolable Declared `@err` Accuracy Bound (`admitted_respects_err_bound`):
       Every dispatched realization satisfies `0 <= r.errBound <= contract.errBound`, and
       whenever `contract.precisionTier = 1` (`@exact`), `r.errBound = 0` strictly.
    3. Hard vs. Soft Deadline Semantics & Optimality (`hard_deadline_fail_closed`,
       `soft_deadline_slip_never_silent`, `admitted_is_min_latency_among_safe`,
       `unproved_never_admitted`):
       - When `@hard_deadline = true` and no safe realization meets `@deadline`, the solver
         fails closed (`refuse`) and NEVER dispatches an unsafe or late realization.
       - When `@hard_deadline = false` and no safe realization meets `@deadline`, the solver
         selects the minimum-latency safe realization inside (1) & (2) AND emits an explicit
         structured `DispatchAlarm.deadlineSlip` (never silent).
       - No realization with `proofMask != 7` is ever dispatched.
    4. Composed Multi-Stage Chain Error Soundness (`chain_error_composition_sound`,
       `chain_overflow_refused`):
       For any sequential call chain of proof-bounded stages whose per-stage error bounds
       sum to `<= outerErr`, the composed end-to-end deviation is bounded by `outerErr`;
       any chain exceeding `outerErr` is refused.
    5. Non-Vacuity Negative-Control Witnesses (axiom-free via `decide`):
       - `neg_control_trap14_90w_refused`: 90 W Trap-14 GPU spike refused by solver.
       - `neg_control_err_violation_refused`: loosened-precision `@err` violation refused.
       - `neg_control_hard_deadline_fail_closed`: tight `@hard_deadline` at 84 C fails closed.
       - `neg_control_soft_deadline_alarm`: same 84 C state with soft deadline emits explicit
         `deadlineSlip 5400` alarm.
       - `neg_control_unproved_mask_refused`: missing proof bit (`proofMask = 5`) refused.
       - `neg_control_chain_err_overflow_refused`: 3-stage error overflow `[40, 35, 30] > 100`
         refused while `[40, 35, 25] <= 100` is admitted.
-/

namespace PhysicsDispatch

-- =========================================================================
-- Section 0: Exact Fixed-Point Mirror of WattCBF (`apps/omega-wattd/watt_cbf.om`)
-- =========================================================================

def P_GPU_HARD_MAX_MW   : Int := 80000
def P_TOTAL_HARD_MAX_MW : Int := 140000
def P_UNC_HARD_MAX_MW   : Int := 25000
def T_CEIL_ABS_MAX_MC   : Int := 90000
def FAN_MIN_PCT         : Int := 20
def FAN_MAX_PCT         : Int := 100

def THERMAL_SCALE : Int := 1000
def K_GPU_HEAT    : Int := 25
def K_CPU_HEAT    : Int := 5
def K_DS_COND     : Int := 100

def PROOF_REQUIRED : Int := 7
def TIER_UNSPEC    : Int := 0
def TIER_EXACT     : Int := 1
def TIER_TOL       : Int := 2

structure ThermalState where
  tDie  : Int
  tSink : Int
  tAmb  : Int
  deriving Repr, DecidableEq

structure WattPolicy where
  pBudget    : Int
  pGpuBudget : Int
  tCeil      : Int
  tau        : Int
  deriving Repr, DecidableEq

structure PowerProposal where
  pGpu   : Int
  pCpu   : Int
  pUnc   : Int
  fanPct : Int
  deriving Repr, DecidableEq

structure SafeCommand where
  pGpu       : Int
  pCpu       : Int
  pUnc       : Int
  fanPct     : Int
  failClosed : Bool
  clamped    : Bool
  deriving Repr, DecidableEq

structure RailTriple where
  pUnc : Int
  pCpu : Int
  pGpu : Int
  deriving Repr, DecidableEq

def ceilDiv (a b : Int) : Int :=
  if a ≥ 0 then (a + b - 1) / b else -((-a) / b)

theorem ceilDiv_le_iff (a b k : Int) (hb : b > 0) :
    ceilDiv a b ≤ k ↔ a ≤ b * k := by
  unfold ceilDiv
  split
  · constructor
    · intro h
      have h1 : (a + b - 1) / b * b ≤ k * b := Int.mul_le_mul_of_nonneg_right h (by omega)
      have h2 := Int.ediv_mul_add_emod (a + b - 1) b
      have hmod := Int.emod_lt_of_pos (a + b - 1) hb
      have hcomm : k * b = b * k := Int.mul_comm k b
      omega
    · intro h
      have hcomm : b * k = k * b := Int.mul_comm b k
      have hle : a + b - 1 ≤ k * b + (b - 1) := by omega
      have h3 : (k * b + (b - 1)) / b ≤ k := by
        have hk : k * b + (b - 1) < (k + 1) * b := by
          have := Int.add_mul k 1 b
          omega
        have heq := Int.ediv_mul_add_emod (k * b + (b - 1)) b
        have hnn := Int.emod_nonneg (k * b + (b - 1)) (by omega : b ≠ 0)
        by_cases hgt : (k * b + (b - 1)) / b ≤ k
        · exact hgt
        · have hge : k + 1 ≤ (k * b + (b - 1)) / b := by omega
          have hm := Int.mul_le_mul_of_nonneg_right hge (by omega : 0 ≤ b)
          omega
      have hmono := Int.ediv_le_ediv hb hle
      omega
  · constructor
    · intro h
      have hneg : -k ≤ (-a) / b := by omega
      have h1 : (-k) * b ≤ ((-a) / b) * b := Int.mul_le_mul_of_nonneg_right hneg (by omega)
      have h2 := Int.ediv_mul_add_emod (-a) b
      have hnn := Int.emod_nonneg (-a) (by omega : b ≠ 0)
      have hcomm : k * b = b * k := Int.mul_comm k b
      have hng : (-k) * b = -(k * b) := Int.neg_mul k b
      omega
    · intro h
      have hng : (-k) * b = -(b * k) := by
        have hcomm : k * b = b * k := Int.mul_comm k b
        have hn : (-k) * b = -(k * b) := Int.neg_mul k b
        omega
      have hle : (-k) * b ≤ -a := by omega
      have hdiv := Int.le_ediv_of_mul_le hb hle
      omega

def barrierH (tCeil tDie tau dT : Int) : Int :=
  tCeil - tDie - tau * dT

def dieHeat (pGpu pCpu pUnc : Int) : Int :=
  K_GPU_HEAT * pGpu + K_CPU_HEAT * (pCpu + pUnc)

def dieCoolDs (st : ThermalState) : Int :=
  K_DS_COND * (st.tDie - st.tSink)

def nextDieDelta (st : ThermalState) (pGpu pCpu pUnc : Int) : Int :=
  ceilDiv (dieHeat pGpu pCpu pUnc - dieCoolDs st) THERMAL_SCALE

def clampNonNeg (x hi : Int) : Int :=
  if hi ≤ 0 then 0
  else if x ≤ 0 then 0
  else if x ≥ hi then hi
  else x

def policyValid (pol : WattPolicy) : Bool :=
  decide (pol.pBudget > 0 ∧ pol.pGpuBudget ≥ 0 ∧ pol.tCeil > 0 ∧
          pol.tCeil ≤ T_CEIL_ABS_MAX_MC ∧ pol.tau ≥ 0)

def rawHeatBudget (st : ThermalState) (pol : WattPolicy) : Int :=
  if pol.tau < 0 then 0
  else THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st

def maxHeatSafe (st : ThermalState) (pol : WattPolicy) : Int :=
  if st.tDie ≥ pol.tCeil ∨ st.tSink ≥ pol.tCeil ∨ pol.tau < 0 then 0
  else max 0 (rawHeatBudget st pol)

def mustFailClosed (st : ThermalState) (pol : WattPolicy) : Bool :=
  !policyValid pol ||
  decide (st.tDie ≥ pol.tCeil) ||
  decide (st.tSink ≥ pol.tCeil) ||
  decide (rawHeatBudget st pol < 0)

def safeFanFloor (headroom : Int) (thermalClamped : Bool) : Int :=
  if thermalClamped || decide (headroom ≤ 5000) then FAN_MAX_PCT
  else if decide (headroom ≤ 10000) then 85
  else if decide (headroom ≤ 18000) then 65
  else if decide (headroom ≤ 28000) then 45
  else FAN_MIN_PCT

def powerClampUnc (pol : WattPolicy) (prop : PowerProposal) : Int :=
  clampNonNeg prop.pUnc (min P_UNC_HARD_MAX_MW (min pol.pBudget P_TOTAL_HARD_MAX_MW))

def powerClampCpu (pol : WattPolicy) (prop : PowerProposal) : Int :=
  clampNonNeg prop.pCpu (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop)

def powerClampGpu (pol : WattPolicy) (prop : PowerProposal) : Int :=
  clampNonNeg prop.pGpu
    (min (min P_GPU_HARD_MAX_MW (min pol.pGpuBudget (min pol.pBudget P_TOTAL_HARD_MAX_MW)))
         (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop - powerClampCpu pol prop))

def powerClamp (pol : WattPolicy) (prop : PowerProposal) : RailTriple :=
  { pUnc := powerClampUnc pol prop
    pCpu := powerClampCpu pol prop
    pGpu := powerClampGpu pol prop }

def thermalHeatUnc (r : RailTriple) (maxHeat : Int) : Int :=
  min (K_CPU_HEAT * r.pUnc) maxHeat

def thermalHeatCpu (r : RailTriple) (maxHeat : Int) : Int :=
  min (K_CPU_HEAT * r.pCpu) (maxHeat - thermalHeatUnc r maxHeat)

def thermalHeatGpu (r : RailTriple) (maxHeat : Int) : Int :=
  min (K_GPU_HEAT * r.pGpu) (maxHeat - thermalHeatUnc r maxHeat - thermalHeatCpu r maxHeat)

def thermalClamp (r : RailTriple) (maxHeat : Int) : RailTriple :=
  { pUnc := thermalHeatUnc r maxHeat / K_CPU_HEAT
    pCpu := thermalHeatCpu r maxHeat / K_CPU_HEAT
    pGpu := thermalHeatGpu r maxHeat / K_GPU_HEAT }

def cbfFilter (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal) : SafeCommand :=
  if mustFailClosed st pol then
    { pGpu       := 0
      pCpu       := 0
      pUnc       := 0
      fanPct     := FAN_MAX_PCT
      failClosed := true
      clamped    := true }
  else
    let r1         := powerClamp pol prop
    let r2         := thermalClamp r1 (maxHeatSafe st pol)
    let headroom   := pol.tCeil - st.tDie
    let thermClamp := decide (r2.pUnc < r1.pUnc ∨ r2.pCpu < r1.pCpu ∨ r2.pGpu < r1.pGpu)
    let fanFloor   := safeFanFloor headroom thermClamp
    let fanOut     := min FAN_MAX_PCT (max fanFloor (max FAN_MIN_PCT prop.fanPct))
    let clamped    := decide (r2.pGpu ≠ prop.pGpu ∨ r2.pCpu ≠ prop.pCpu ∨
                              r2.pUnc ≠ prop.pUnc ∨ fanOut ≠ prop.fanPct)
    { pGpu       := r2.pGpu
      pCpu       := r2.pCpu
      pUnc       := r2.pUnc
      fanPct     := fanOut
      failClosed := false
      clamped    := clamped }

-- =========================================================================
-- Section 1: WattCBF Core Safety Lemmas (Self-Contained)
-- =========================================================================

private theorem mul_ediv_bounds (x k : Int) (hk : k > 0) (hx : 0 ≤ x) :
    0 ≤ x / k ∧ k * (x / k) ≤ x := by
  have h1 : 0 ≤ x / k := Int.ediv_nonneg hx (by omega)
  have h2 := Int.mul_ediv_add_emod x k
  have hmod := Int.emod_nonneg x (by omega : k ≠ 0)
  omega

private theorem min_mul_ediv_le (y m k : Int) (hk : k > 0) :
    min (k * y) m / k ≤ y := by
  have hle : min (k * y) m ≤ y * k := by
    have hcomm : k * y = y * k := Int.mul_comm k y
    have hm : min (k * y) m ≤ k * y := Int.min_le_left _ _
    omega
  exact Int.ediv_le_of_le_mul hk hle

private theorem clampNonNeg_bounds (x hi : Int) :
    0 ≤ clampNonNeg x hi ∧ (0 ≤ hi → clampNonNeg x hi ≤ hi) ∧
    (0 ≤ x → clampNonNeg x hi ≤ x) := by
  unfold clampNonNeg
  by_cases h1 : hi ≤ 0
  · simp [h1]
  · by_cases h2 : x ≤ 0
    · simp [h1, h2]
    · by_cases h3 : x ≥ hi
      · simp [h1, h2, h3]; omega
      · simp [h1, h2, h3]; omega

private theorem maxHeatSafe_nonneg (st : ThermalState) (pol : WattPolicy) :
    0 ≤ maxHeatSafe st pol := by
  unfold maxHeatSafe
  split <;> omega

private theorem powerClamp_bounds (pol : WattPolicy) (prop : PowerProposal)
    (hb : 0 ≤ pol.pBudget) (hgb : 0 ≤ pol.pGpuBudget) :
    let r := powerClamp pol prop
    0 ≤ r.pUnc ∧ 0 ≤ r.pCpu ∧ 0 ≤ r.pGpu ∧
    r.pUnc ≤ P_UNC_HARD_MAX_MW ∧
    r.pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget ∧
    r.pGpu + r.pCpu + r.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW := by
  dsimp only [powerClamp]
  have hu : 0 ≤ powerClampUnc pol prop ∧
      (0 ≤ min P_UNC_HARD_MAX_MW (min pol.pBudget P_TOTAL_HARD_MAX_MW) →
        powerClampUnc pol prop ≤ min P_UNC_HARD_MAX_MW (min pol.pBudget P_TOTAL_HARD_MAX_MW)) := by
    unfold powerClampUnc
    have h := clampNonNeg_bounds prop.pUnc (min P_UNC_HARD_MAX_MW (min pol.pBudget P_TOTAL_HARD_MAX_MW))
    exact ⟨h.1, h.2.1⟩
  have hc : 0 ≤ powerClampCpu pol prop ∧
      (0 ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop →
        powerClampCpu pol prop ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop) := by
    unfold powerClampCpu
    have h := clampNonNeg_bounds prop.pCpu (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop)
    exact ⟨h.1, h.2.1⟩
  have hg : 0 ≤ powerClampGpu pol prop ∧
      (0 ≤ min (min P_GPU_HARD_MAX_MW (min pol.pGpuBudget (min pol.pBudget P_TOTAL_HARD_MAX_MW)))
               (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop - powerClampCpu pol prop) →
        powerClampGpu pol prop ≤
          min (min P_GPU_HARD_MAX_MW (min pol.pGpuBudget (min pol.pBudget P_TOTAL_HARD_MAX_MW)))
              (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop - powerClampCpu pol prop)) := by
    unfold powerClampGpu
    have h := clampNonNeg_bounds prop.pGpu
      (min (min P_GPU_HARD_MAX_MW (min pol.pGpuBudget (min pol.pBudget P_TOTAL_HARD_MAX_MW)))
           (min pol.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol prop - powerClampCpu pol prop))
    exact ⟨h.1, h.2.1⟩
  unfold P_GPU_HARD_MAX_MW P_TOTAL_HARD_MAX_MW P_UNC_HARD_MAX_MW at *
  omega

private theorem thermalClamp_le_input (r : RailTriple) (maxHeat : Int) :
    let t := thermalClamp r maxHeat
    t.pUnc ≤ r.pUnc ∧ t.pCpu ≤ r.pCpu ∧ t.pGpu ≤ r.pGpu := by
  dsimp only [thermalClamp, thermalHeatUnc, thermalHeatCpu, thermalHeatGpu]
  exact ⟨min_mul_ediv_le r.pUnc maxHeat K_CPU_HEAT (by decide),
         min_mul_ediv_le r.pCpu _ K_CPU_HEAT (by decide),
         min_mul_ediv_le r.pGpu _ K_GPU_HEAT (by decide)⟩

private theorem thermalClamp_nonneg_and_heat (r : RailTriple) (maxHeat : Int)
    (hu : 0 ≤ r.pUnc) (hc : 0 ≤ r.pCpu) (hg : 0 ≤ r.pGpu) (hm : 0 ≤ maxHeat) :
    let t := thermalClamp r maxHeat
    0 ≤ t.pUnc ∧ 0 ≤ t.pCpu ∧ 0 ≤ t.pGpu ∧
    dieHeat t.pGpu t.pCpu t.pUnc ≤ maxHeat := by
  dsimp only [thermalClamp]
  have hhu : 0 ≤ thermalHeatUnc r maxHeat := by unfold thermalHeatUnc K_CPU_HEAT; omega
  have hhc : 0 ≤ thermalHeatCpu r maxHeat := by
    unfold thermalHeatCpu thermalHeatUnc K_CPU_HEAT; omega
  have hhg : 0 ≤ thermalHeatGpu r maxHeat := by
    unfold thermalHeatGpu thermalHeatCpu thermalHeatUnc K_GPU_HEAT K_CPU_HEAT; omega
  have bu := mul_ediv_bounds (thermalHeatUnc r maxHeat) K_CPU_HEAT (by decide) hhu
  have bc := mul_ediv_bounds (thermalHeatCpu r maxHeat) K_CPU_HEAT (by decide) hhc
  have bg := mul_ediv_bounds (thermalHeatGpu r maxHeat) K_GPU_HEAT (by decide) hhg
  have hsum : thermalHeatUnc r maxHeat + thermalHeatCpu r maxHeat + thermalHeatGpu r maxHeat ≤ maxHeat := by
    unfold thermalHeatGpu thermalHeatCpu thermalHeatUnc; omega
  unfold dieHeat K_GPU_HEAT K_CPU_HEAT at *
  omega

private theorem policyValid_of_not_guard (st : ThermalState) (pol : WattPolicy)
    (h : ¬ (mustFailClosed st pol = true)) :
    pol.pBudget > 0 ∧ pol.pGpuBudget ≥ 0 ∧ pol.tCeil > 0 ∧
    pol.tCeil ≤ T_CEIL_ABS_MAX_MC ∧ pol.tau ≥ 0 ∧
    st.tDie < pol.tCeil ∧ st.tSink < pol.tCeil ∧
    0 ≤ rawHeatBudget st pol := by
  unfold mustFailClosed at h
  have hv : policyValid pol = true := by
    cases hpv : policyValid pol <;> simp [hpv] at h ⊢
  have hdie : ¬ (st.tDie ≥ pol.tCeil) := by intro hge; simp [hge] at h
  have hsink : ¬ (st.tSink ≥ pol.tCeil) := by intro hge; simp [hge] at h
  have hraw : ¬ (rawHeatBudget st pol < 0) := by intro hlt; simp [hlt] at h
  unfold policyValid at hv
  simp only [decide_eq_true_eq] at hv
  omega

theorem cbf_admitted_safe
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hadmit : (cbfFilter st pol prop).failClosed = false) :
    let out := cbfFilter st pol prop
    let dT  := nextDieDelta st out.pGpu out.pCpu out.pUnc
    out.pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget ∧
    out.pGpu + out.pCpu + out.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW ∧
    barrierH pol.tCeil st.tDie pol.tau dT ≥ 0 ∧
    st.tDie + dT ≤ pol.tCeil := by
  dsimp only
  have hng : ¬ (mustFailClosed st pol = true) := by
    intro hfc; unfold cbfFilter at hadmit; simp [hfc] at hadmit
  have hp := policyValid_of_not_guard st pol hng
  have hok : (cbfFilter st pol prop).pGpu = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu ∧
             (cbfFilter st pol prop).pCpu = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu ∧
             (cbfFilter st pol prop).pUnc = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc := by
    unfold cbfFilter; rw [ite_eq_right hng]; exact ⟨rfl, rfl, rfl⟩
  have pb := powerClamp_bounds pol prop (by omega) (by omega)
  have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
  have th := thermalClamp_nonneg_and_heat (powerClamp pol prop) (maxHeatSafe st pol)
    pb.1 pb.2.1 pb.2.2.1 (maxHeatSafe_nonneg st pol)
  have hheat : dieHeat (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
      (cbfFilter st pol prop).pUnc ≤ maxHeatSafe st pol := by
    rw [hok.1, hok.2.1, hok.2.2]; exact th.2.2.2
  have hraw : 0 ≤ THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st := by
    have h1 := hp.2.2.2.2.2.2.2
    unfold rawHeatBudget at h1
    have hnt : ¬ (pol.tau < 0) := by omega
    simp only [hnt, ↓reduceIte] at h1
    exact h1
  have hmh_le : maxHeatSafe st pol ≤
      THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st := by
    unfold maxHeatSafe rawHeatBudget
    have hntau : ¬ (pol.tau < 0) := by omega
    simp only [hntau, ↓reduceIte]
    split <;> omega
  have hdTle : nextDieDelta st (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
      (cbfFilter st pol prop).pUnc ≤ (pol.tCeil - st.tDie) / (pol.tau + 1) := by
    unfold nextDieDelta
    rw [ceilDiv_le_iff _ THERMAL_SCALE _ (by decide)]
    omega
  have hdiv := mul_ediv_bounds (pol.tCeil - st.tDie) (pol.tau + 1) (by omega) (by omega)
  have htau1 : (pol.tau + 1) * nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ pol.tCeil - st.tDie := by
    have hmul := Int.mul_le_mul_of_nonneg_left hdTle (by omega : 0 ≤ pol.tau + 1)
    omega
  have hdist : (pol.tau + 1) * nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc =
      pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc +
      nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc := by
    have := Int.add_mul pol.tau 1 (nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc)
    omega
  have hdT_bound : nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ pol.tCeil - st.tDie := by
    by_cases hpos : 0 ≤ nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc
    · have : 0 ≤ pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
          (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc := Int.mul_nonneg (by omega) hpos
      omega
    · omega
  have htau_bound : pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ pol.tCeil - st.tDie := by
    by_cases hpos : 0 ≤ nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc
    · omega
    · have : pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
          (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ 0 :=
        Int.mul_nonpos_of_nonneg_of_nonpos (by omega) (by omega)
      omega
  unfold barrierH
  refine ⟨by omega, by omega, by omega, by omega⟩

-- =========================================================================
-- Section 2: Physics-Typed Dispatch Model (`pareto_bank.om` + `phys_solver.om`)
-- =========================================================================

structure Realization where
  semId        : Int
  targetTid    : Int
  isGpuTarget  : Bool
  precisionId  : Int
  estPowerMw   : Int
  estLatencyUs : Int
  estJoulesUj  : Int
  errBound     : Int
  proofMask    : Int
  deriving Repr, DecidableEq

structure Contract where
  purityFlag    : Int   -- 0 or 1
  precisionTier : Int   -- 0=unspec, 1=exact, 2=tol
  hardDeadline  : Bool  -- false=soft/none, true=@hard_deadline
  errBound      : Int   -- >= 0; 0 unless precisionTier == 2
  deadlineUs    : Int   -- >= 0; > 0 when hardDeadline == true
  powerMw       : Int   -- >= 0 (0 = none)
  deriving Repr, DecidableEq

structure BaselineLoad where
  baseCpuMw : Int
  baseUncMw : Int
  fanReqPct : Int
  deriving Repr, DecidableEq

inductive DispatchAlarm where
  | none
  | deadlineSlip (slipUs : Int)
  deriving Repr, DecidableEq

inductive RefusalReason where
  | badContract
  | badBaseline
  | wattCbfFailClosed
  | noSafeRealization
  | hardDeadlineMiss
  deriving Repr, DecidableEq

inductive DispatchResult where
  | dispatch (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
  | refuse (reason : RefusalReason)
  deriving Repr, DecidableEq

/-- Canonical ΩIR v2 contract validation (exact mirror of `ps_contract_valid` & `IR.md` §16.1). -/
def contractValid (c : Contract) : Bool :=
  decide (0 ≤ c.purityFlag ∧ c.purityFlag ≤ 1 ∧
          0 ≤ c.precisionTier ∧ c.precisionTier ≤ 2 ∧
          0 ≤ c.errBound ∧ 0 ≤ c.deadlineUs ∧ 0 ≤ c.powerMw ∧
          (c.precisionTier ≠ TIER_TOL → c.errBound = 0) ∧
          (c.hardDeadline = true → c.deadlineUs > 0))

/-- Map realization onto physical WattCBF rails (GPU vs CPU + baseline loads). -/
def realizationProposal (base : BaselineLoad) (r : Realization) : PowerProposal :=
  if r.isGpuTarget then
    { pGpu := r.estPowerMw, pCpu := base.baseCpuMw, pUnc := base.baseUncMw, fanPct := base.fanReqPct }
  else
    { pGpu := 0, pCpu := base.baseCpuMw + r.estPowerMw, pUnc := base.baseUncMw, fanPct := base.fanReqPct }

/-- Proof gate: exact `proofMask == 7` (`Contract | EGP3 | Antibody`) plus valid physical metrics. -/
def isProofVerified (r : Realization) : Bool :=
  decide (r.proofMask = PROOF_REQUIRED ∧ r.estPowerMw ≥ 0 ∧ r.estLatencyUs > 0 ∧
          r.estJoulesUj ≥ 0 ∧ r.errBound ≥ 0)

/-- Priority 1 (INVIOLABLE): `WattCBF` admits realization un-clamped AND `@power` cap holds. -/
def isWattCbfSafe (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (r : Realization) : Bool :=
  let prop := realizationProposal base r
  let cmd  := cbfFilter st pol prop
  !cmd.failClosed &&
  decide (cmd.pGpu = prop.pGpu ∧ cmd.pCpu = prop.pCpu ∧ cmd.pUnc = prop.pUnc) &&
  decide (c.powerMw = 0 ∨ r.estPowerMw ≤ c.powerMw)

/-- Priority 2 (INVIOLABLE): proven realization error bound never exceeds contract `@err`. -/
def isErrSafe (c : Contract) (r : Realization) : Bool :=
  decide (r.errBound ≤ c.errBound)

/-- Full safety admission predicate inside Priorities (1) & (2). -/
def isSafeCandidate (semId : Int) (st : ThermalState) (pol : WattPolicy)
    (base : BaselineLoad) (c : Contract) (r : Realization) : Bool :=
  decide (r.semId = semId) &&
  isProofVerified r &&
  isWattCbfSafe st pol base c r &&
  isErrSafe c r

/-- Strict deterministic preference order inside `(1) & (2)`:
    minimize latency, tie-breaking by lower error, lower energy (uJ), lower power (mW). -/
def betterCandidate (a b : Realization) : Bool :=
  if a.estLatencyUs < b.estLatencyUs then true
  else if a.estLatencyUs > b.estLatencyUs then false
  else if a.errBound < b.errBound then true
  else if a.errBound > b.errBound then false
  else if a.estJoulesUj < b.estJoulesUj then true
  else if a.estJoulesUj > b.estJoulesUj then false
  else decide (a.estPowerMw < b.estPowerMw)

/-- Fold over Pareto bank to pick the minimum-latency safe candidate inside `(1) & (2)`. -/
def selectFastestLoop (semId : Int) (st : ThermalState) (pol : WattPolicy)
    (base : BaselineLoad) (c : Contract) (acc : Option Realization) :
    List Realization → Option Realization
  | [] => acc
  | r :: rest =>
    if isSafeCandidate semId st pol base c r then
      let acc' := match acc with
        | none => some r
        | some cur => if betterCandidate r cur then some r else some cur
      selectFastestLoop semId st pol base c acc' rest
    else
      selectFastestLoop semId st pol base c acc rest

def selectFastestSafe (semId : Int) (st : ThermalState) (pol : WattPolicy)
    (base : BaselineLoad) (c : Contract) (bank : List Realization) : Option Realization :=
  selectFastestLoop semId st pol base c none bank

/-- Real-Time Physics Dispatch Solver (exact mirror of `ps_dispatch` in `phys_solver.om`). -/
def solveDispatch (semId : Int) (st : ThermalState) (pol : WattPolicy)
    (base : BaselineLoad) (c : Contract) (bank : List Realization) : DispatchResult :=
  if !contractValid c then
    .refuse .badContract
  else if decide (base.baseCpuMw < 0 ∨ base.baseUncMw < 0) then
    .refuse .badBaseline
  else if mustFailClosed st pol then
    .refuse .wattCbfFailClosed
  else
    match selectFastestSafe semId st pol base c bank with
    | none => .refuse .noSafeRealization
    | some best =>
      let cmd := cbfFilter st pol (realizationProposal base best)
      if decide (c.deadlineUs = 0 ∨ best.estLatencyUs ≤ c.deadlineUs) then
        .dispatch best cmd .none
      else if c.hardDeadline then
        .refuse .hardDeadlineMiss
      else
        .dispatch best cmd (.deadlineSlip (best.estLatencyUs - c.deadlineUs))

-- =========================================================================
-- Section 3: Selection Helper Lemmas
-- =========================================================================

private theorem betterCandidate_lat_le (a b : Realization) (h : betterCandidate a b = true) :
    a.estLatencyUs ≤ b.estLatencyUs := by
  unfold betterCandidate at h
  by_cases h1 : a.estLatencyUs < b.estLatencyUs
  · omega
  · simp only [h1, ↓reduceIte] at h
    by_cases h2 : a.estLatencyUs > b.estLatencyUs
    · simp [h2] at h
    · omega

private theorem selectFastestLoop_props
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad) (c : Contract)
    (bank : List Realization) (acc : Option Realization)
    (hacc : ∀ a, acc = some a → isSafeCandidate semId st pol base c a = true) :
    ∀ res, selectFastestLoop semId st pol base c acc bank = some res →
      isSafeCandidate semId st pol base c res = true ∧
      (∀ a, acc = some a → res.estLatencyUs ≤ a.estLatencyUs) ∧
      (∀ x, x ∈ bank → isSafeCandidate semId st pol base c x = true →
            res.estLatencyUs ≤ x.estLatencyUs) := by
  induction bank generalizing acc with
  | nil =>
    intro res hres
    unfold selectFastestLoop at hres
    refine ⟨hacc res hres, ?_, ?_⟩
    · intro a ha; rw [ha] at hres; cases hres; exact Int.le_refl _
    · intro x hx; cases hx
  | cons r rest ih =>
    intro res hres
    unfold selectFastestLoop at hres
    by_cases hsafe : isSafeCandidate semId st pol base c r = true
    · simp only [hsafe, ↓reduceIte] at hres
      cases acc with
      | none =>
        dsimp only at hres
        have hih := ih (some r) (by intro a ha; cases ha; exact hsafe) res hres
        refine ⟨hih.1, ?_, ?_⟩
        · intro a ha; cases ha
        · intro x hx hxs
          cases hx with
          | head => exact hih.2.1 r rfl
          | tail _ hmem => exact hih.2.2 x hmem hxs
      | some cur =>
        dsimp only at hres
        by_cases hbet : betterCandidate r cur = true
        · simp only [hbet, ↓reduceIte] at hres
          have hlat_rc : r.estLatencyUs ≤ cur.estLatencyUs := betterCandidate_lat_le r cur hbet
          have hih := ih (some r) (by intro a ha; cases ha; exact hsafe) res hres
          have hres_r : res.estLatencyUs ≤ r.estLatencyUs := hih.2.1 r rfl
          refine ⟨hih.1, ?_, ?_⟩
          · intro a ha; cases ha; omega
          · intro x hx hxs
            cases hx with
            | head => exact hres_r
            | tail _ hmem => exact hih.2.2 x hmem hxs
        · simp only [hbet, Bool.false_eq_true, ↓reduceIte] at hres
          have hlat_cr : cur.estLatencyUs ≤ r.estLatencyUs := by
            unfold betterCandidate at hbet
            by_cases hlt : r.estLatencyUs < cur.estLatencyUs
            · simp [hlt] at hbet
            · omega
          have hih := ih (some cur) hacc res hres
          have hres_c : res.estLatencyUs ≤ cur.estLatencyUs := hih.2.1 cur rfl
          refine ⟨hih.1, ?_, ?_⟩
          · intro a ha; cases ha; exact hres_c
          · intro x hx hxs
            cases hx with
            | head => omega
            | tail _ hmem => exact hih.2.2 x hmem hxs
    · simp only [hsafe, Bool.false_eq_true, ↓reduceIte] at hres
      have hih := ih acc hacc res hres
      refine ⟨hih.1, hih.2.1, ?_⟩
      · intro x hx hxs
        cases hx with
        | head => rw [hxs] at hsafe; exact absurd rfl hsafe
        | tail _ hmem => exact hih.2.2 x hmem hxs

private theorem selectFastestLoop_mem_some
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad) (c : Contract)
    (bank : List Realization) (acc : Option Realization)
    (hacc_some : acc.isSome = true) :
    (selectFastestLoop semId st pol base c acc bank).isSome = true := by
  induction bank generalizing acc with
  | nil => exact hacc_some
  | cons r rest ih =>
    unfold selectFastestLoop
    by_cases hsafe : isSafeCandidate semId st pol base c r = true
    · simp only [hsafe, ↓reduceIte]
      apply ih
      cases acc <;> simp
      split <;> rfl
    · simp only [hsafe, Bool.false_eq_true, ↓reduceIte]
      exact ih acc hacc_some

private theorem selectFastestSafe_sound
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization) (res : Realization)
    (h : selectFastestSafe semId st pol base c bank = some res) :
    isSafeCandidate semId st pol base c res = true ∧
    (∀ x, x ∈ bank → isSafeCandidate semId st pol base c x = true →
          res.estLatencyUs ≤ x.estLatencyUs) := by
  have hp := selectFastestLoop_props semId st pol base c bank none (by intro a ha; cases ha) res h
  exact ⟨hp.1, hp.2.2⟩

private theorem solveDispatch_extract
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm) :
    contractValid c = true ∧
    0 ≤ base.baseCpuMw ∧ 0 ≤ base.baseUncMw ∧
    mustFailClosed st pol = false ∧
    selectFastestSafe semId st pol base c bank = some r ∧
    cmd = cbfFilter st pol (realizationProposal base r) ∧
    ((c.deadlineUs = 0 ∨ r.estLatencyUs ≤ c.deadlineUs) ∧ alarm = .none ∨
     (c.deadlineUs ≠ 0 ∧ r.estLatencyUs > c.deadlineUs ∧ c.hardDeadline = false ∧
      alarm = .deadlineSlip (r.estLatencyUs - c.deadlineUs))) := by
  unfold solveDispatch at h
  by_cases hcv : contractValid c = true
  · simp only [hcv, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
    by_cases hbb : (base.baseCpuMw < 0 ∨ base.baseUncMw < 0)
    · simp [hbb] at h
    · simp only [hbb, decide_false, Bool.false_eq_true, ↓reduceIte] at h
      by_cases hfc : mustFailClosed st pol = true
      · simp [hfc] at h
      · have hfcF : mustFailClosed st pol = false := by
          cases hm : mustFailClosed st pol
          · rfl
          · exact absurd hm hfc
        simp only [hfcF, Bool.false_eq_true, ↓reduceIte] at h
        cases hsel : selectFastestSafe semId st pol base c bank with
        | none => simp [hsel] at h
        | some best =>
          simp only [hsel] at h
          by_cases hdl : (c.deadlineUs = 0 ∨ best.estLatencyUs ≤ c.deadlineUs)
          · simp only [hdl, decide_true, ↓reduceIte] at h
            cases h
            refine ⟨hcv, by omega, by omega, hfcF, rfl, rfl, Or.inl ⟨hdl, rfl⟩⟩
          · simp only [hdl, decide_false, Bool.false_eq_true, ↓reduceIte] at h
            by_cases hhd : c.hardDeadline = true
            · simp [hhd] at h
            · have hhdF : c.hardDeadline = false := by
                cases hh : c.hardDeadline
                · rfl
                · exact absurd hh hhd
              simp only [hhdF, Bool.false_eq_true, ↓reduceIte] at h
              cases h
              refine ⟨hcv, by omega, by omega, hfcF, rfl, rfl,
                      Or.inr ⟨by omega, by omega, hhdF, rfl⟩⟩
  · have hcvF : contractValid c = false := by
      cases hc : contractValid c
      · rfl
      · exact absurd hc hcv
    simp [hcvF] at h

-- =========================================================================
-- Section 4: Main Stage 3 Safety Theorems
-- =========================================================================

/-- Theorem 1 (Inviolable Hardware WattCBF Safety):
    Every realization dispatched by `solveDispatch` is proof-verified (`proofMask = 7`),
    admitted un-clamped by `cbfFilter` (`failClosed = false`), obeys the Trap-14 80 W
    GPU ceiling, total package Watt conservation (`<= min(P_budget, 140 W)`), discrete
    thermal CBF barrier `h >= 0`, next-step thermal safety `T_die' <= T_ceil`, and
    the ΩIR v2 `@power` ceiling. -/
theorem admitted_respects_wattcbf
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm) :
    let prop := realizationProposal base r
    let dT   := nextDieDelta st prop.pGpu prop.pCpu prop.pUnc
    r.proofMask = PROOF_REQUIRED ∧
    cmd.failClosed = false ∧
    cmd.pGpu = prop.pGpu ∧ cmd.pCpu = prop.pCpu ∧ cmd.pUnc = prop.pUnc ∧
    prop.pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget ∧
    prop.pGpu + prop.pCpu + prop.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW ∧
    barrierH pol.tCeil st.tDie pol.tau dT ≥ 0 ∧
    st.tDie + dT ≤ pol.tCeil ∧
    (c.powerMw = 0 ∨ r.estPowerMw ≤ c.powerMw) := by
  dsimp only
  have hex := solveDispatch_extract semId st pol base c bank r cmd alarm h
  have hsel := selectFastestSafe_sound semId st pol base c bank r hex.2.2.2.2.1
  have hcand := hsel.1
  unfold isSafeCandidate at hcand
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hcand
  have hproof := hcand.1.1.2
  unfold isProofVerified at hproof
  simp only [decide_eq_true_eq] at hproof
  have hwc := hcand.1.2
  unfold isWattCbfSafe at hwc
  simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hwc
  have hcmd_eq : cmd = cbfFilter st pol (realizationProposal base r) := hex.2.2.2.2.2.1
  have hsafe := cbf_admitted_safe st pol (realizationProposal base r) hwc.1.1
  dsimp only at hsafe
  rw [hcmd_eq]
  rw [hwc.1.2.1, hwc.1.2.2.1, hwc.1.2.2.2] at hsafe
  exact ⟨hproof.1, hwc.1.1, hwc.1.2.1, hwc.1.2.2.1, hwc.1.2.2.2,
         hsafe.1, hsafe.2.1, hsafe.2.2.1, hsafe.2.2.2, hwc.2⟩

/-- Theorem 2 (Inviolable Declared `@err` Accuracy Bound):
    Every dispatched realization satisfies `0 <= r.errBound <= contract.errBound`, and
    under `@exact` (`precisionTier = 1`), `r.errBound = 0` strictly. -/
theorem admitted_respects_err_bound
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm) :
    0 ≤ r.errBound ∧ r.errBound ≤ c.errBound ∧
    (c.precisionTier = TIER_EXACT → r.errBound = 0) := by
  have hex := solveDispatch_extract semId st pol base c bank r cmd alarm h
  have hcv := hex.1
  unfold contractValid at hcv
  simp only [decide_eq_true_eq] at hcv
  have hsel := selectFastestSafe_sound semId st pol base c bank r hex.2.2.2.2.1
  have hcand := hsel.1
  unfold isSafeCandidate at hcand
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hcand
  have hproof := hcand.1.1.2
  unfold isProofVerified at hproof
  simp only [decide_eq_true_eq] at hproof
  have herr := hcand.2
  unfold isErrSafe at herr
  simp only [decide_eq_true_eq] at herr
  refine ⟨by omega, herr, ?_⟩
  intro hexact
  have hzero : c.errBound = 0 := hcv.2.2.2.2.2.2.2.1 (by unfold TIER_EXACT TIER_TOL at *; omega)
  omega

/-- Theorem 3 (Hard Deadline Fail-Closed):
    When `contract.hardDeadline = true` and NO safe realization in the bank meets
    `contract.deadlineUs`, `solveDispatch` ALWAYS returns `.refuse reason` (never dispatches!).
    Specifically, when contract/baseline/thermal state are valid and safe realizations exist
    (all missing the deadline), it returns `.refuse .hardDeadlineMiss`. -/
theorem hard_deadline_fail_closed
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (hhard : c.hardDeadline = true)
    (hnone : ∀ r, r ∈ bank → isSafeCandidate semId st pol base c r = true →
                  r.estLatencyUs > c.deadlineUs) :
    ∃ reason, solveDispatch semId st pol base c bank = .refuse reason := by
  unfold solveDispatch
  by_cases hcv : contractValid c = true
  · simp only [hcv, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
    by_cases hbb : (base.baseCpuMw < 0 ∨ base.baseUncMw < 0)
    · exact ⟨.badBaseline, by simp [hbb]⟩
    · simp only [hbb, decide_false, Bool.false_eq_true, ↓reduceIte]
      by_cases hfc : mustFailClosed st pol = true
      · exact ⟨.wattCbfFailClosed, by simp [hfc]⟩
      · have hfcF : mustFailClosed st pol = false := by
          cases hm : mustFailClosed st pol
          · rfl
          · exact absurd hm hfc
        simp only [hfcF, Bool.false_eq_true, ↓reduceIte]
        cases hsel : selectFastestSafe semId st pol base c bank with
        | none => exact ⟨.noSafeRealization, rfl⟩
        | some best =>
          have hmem : best ∈ bank := by
            -- Prove membership directly from selectFastestLoop
            have hmem_aux : ∀ (xs : List Realization) (acc : Option Realization),
                (∀ a, acc = some a → a ∈ bank) →
                (∀ x, x ∈ xs → x ∈ bank) →
                ∀ res, selectFastestLoop semId st pol base c acc xs = some res → res ∈ bank := by
              intro xs
              induction xs with
              | nil =>
                intro acc hacc _ res hres
                exact hacc res hres
              | cons y ys ih =>
                intro acc hacc hsub res hres
                unfold selectFastestLoop at hres
                by_cases hs : isSafeCandidate semId st pol base c y = true
                · simp only [hs, ↓reduceIte] at hres
                  apply ih _ _ (fun z hz => hsub z (List.mem_cons_of_mem y hz)) res hres
                  intro a ha
                  cases acc with
                  | none => cases ha; exact hsub y (List.mem_cons_self)
                  | some cur =>
                    dsimp only at ha
                    by_cases hb : betterCandidate y cur = true
                    · simp only [hb, ↓reduceIte] at ha; cases ha; exact hsub y List.mem_cons_self
                    · simp only [hb, Bool.false_eq_true, ↓reduceIte] at ha; exact hacc a ha
                · simp only [hs, Bool.false_eq_true, ↓reduceIte] at hres
                  exact ih acc hacc (fun z hz => hsub z (List.mem_cons_of_mem y hz)) res hres
            exact hmem_aux bank none (by intro a ha; cases ha) (fun x hx => hx) best hsel
          have hsafe := (selectFastestSafe_sound semId st pol base c bank best hsel).1
          have hlate := hnone best hmem hsafe
          unfold contractValid at hcv
          simp only [decide_eq_true_eq] at hcv
          have hdl_pos : c.deadlineUs > 0 := hcv.2.2.2.2.2.2.2.2 hhard
          have hcond : ¬ (c.deadlineUs = 0 ∨ best.estLatencyUs ≤ c.deadlineUs) := by omega
          exact ⟨.hardDeadlineMiss, by simp [hcond, hhard]⟩
  · have hcvF : contractValid c = false := by
      cases hc : contractValid c
      · rfl
      · exact absurd hc hcv
    exact ⟨.badContract, by simp [hcvF]⟩

private theorem selectFastestLoop_exists_some
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad) (c : Contract)
    (bank : List Realization) (acc : Option Realization) (r0 : Realization)
    (hmem : r0 ∈ bank) (hsafe0 : isSafeCandidate semId st pol base c r0 = true) :
    (selectFastestLoop semId st pol base c acc bank).isSome = true := by
  induction bank generalizing acc with
  | nil => cases hmem
  | cons r rest ih =>
    unfold selectFastestLoop
    cases hmem with
    | head =>
      simp only [hsafe0, ↓reduceIte]
      apply selectFastestLoop_mem_some
      cases acc <;> simp
      split <;> rfl
    | tail _ htail =>
      by_cases hs : isSafeCandidate semId st pol base c r = true
      · simp only [hs, ↓reduceIte]; exact ih _ htail
      · simp only [hs, Bool.false_eq_true, ↓reduceIte]; exact ih acc htail

/-- Theorem 3b (Exact Hard-Deadline Refusal Code):
    Under valid contract, baseline, and WattCBF state, if at least one safe realization exists
    and EVERY safe realization misses `contract.deadlineUs` with `contract.hardDeadline = true`,
    `solveDispatch` returns `.refuse .hardDeadlineMiss` specifically. -/
theorem hard_deadline_miss_exact
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (hcv : contractValid c = true)
    (hbc : 0 ≤ base.baseCpuMw) (hbu : 0 ≤ base.baseUncMw)
    (hfc : mustFailClosed st pol = false)
    (hhard : c.hardDeadline = true)
    (hex : ∃ r0, r0 ∈ bank ∧ isSafeCandidate semId st pol base c r0 = true)
    (hnone : ∀ r, r ∈ bank → isSafeCandidate semId st pol base c r = true →
                  r.estLatencyUs > c.deadlineUs) :
    solveDispatch semId st pol base c bank = .refuse .hardDeadlineMiss := by
  have ⟨r0, hmem0, hsafe0⟩ := hex
  have hsome : (selectFastestSafe semId st pol base c bank).isSome = true :=
    selectFastestLoop_exists_some semId st pol base c bank none r0 hmem0 hsafe0
  unfold solveDispatch
  have hbb : ¬ (base.baseCpuMw < 0 ∨ base.baseUncMw < 0) := by omega
  simp only [hcv, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hbb, decide_false, hfc]
  cases hsel : selectFastestSafe semId st pol base c bank with
  | none => rw [hsel] at hsome; simp at hsome
  | some best =>
    have hmem : best ∈ bank := by
      have hmem_aux : ∀ (xs : List Realization) (acc : Option Realization),
          (∀ a, acc = some a → a ∈ bank) →
          (∀ x, x ∈ xs → x ∈ bank) →
          ∀ res, selectFastestLoop semId st pol base c acc xs = some res → res ∈ bank := by
        intro xs
        induction xs with
        | nil => intro acc hacc _ res hres; exact hacc res hres
        | cons y ys ih =>
          intro acc hacc hsub res hres
          unfold selectFastestLoop at hres
          by_cases hs : isSafeCandidate semId st pol base c y = true
          · simp only [hs, ↓reduceIte] at hres
            apply ih _ _ (fun z hz => hsub z (List.mem_cons_of_mem y hz)) res hres
            intro a ha
            cases acc with
            | none => cases ha; exact hsub y List.mem_cons_self
            | some cur =>
              dsimp only at ha
              by_cases hb : betterCandidate y cur = true
              · simp only [hb, ↓reduceIte] at ha; cases ha; exact hsub y List.mem_cons_self
              · simp only [hb, Bool.false_eq_true, ↓reduceIte] at ha; exact hacc a ha
          · simp only [hs, Bool.false_eq_true, ↓reduceIte] at hres
            exact ih acc hacc (fun z hz => hsub z (List.mem_cons_of_mem y hz)) res hres
      exact hmem_aux bank none (by intro a ha; cases ha) (fun x hx => hx) best hsel
    have hsafe := (selectFastestSafe_sound semId st pol base c bank best hsel).1
    have hlate := hnone best hmem hsafe
    unfold contractValid at hcv
    simp only [decide_eq_true_eq] at hcv
    have hdl_pos : c.deadlineUs > 0 := hcv.2.2.2.2.2.2.2.2 hhard
    have hcond : ¬ (c.deadlineUs = 0 ∨ best.estLatencyUs ≤ c.deadlineUs) := by omega
    simp [hcond, hhard]

/-- Theorem 4 (Soft Deadline Slip Is Never Silent):
    Whenever a dispatched realization exceeds `contract.deadlineUs > 0`, `contract.hardDeadline`
    MUST be `false` and the solver MUST emit `DispatchAlarm.deadlineSlip (r.estLatencyUs - c.deadlineUs)`. -/
theorem soft_deadline_slip_never_silent
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm)
    (hdl : c.deadlineUs > 0) (hslip : r.estLatencyUs > c.deadlineUs) :
    c.hardDeadline = false ∧ alarm = .deadlineSlip (r.estLatencyUs - c.deadlineUs) := by
  have hex := solveDispatch_extract semId st pol base c bank r cmd alarm h
  cases hex.2.2.2.2.2.2 with
  | inl hok => omega
  | inr hsl => exact ⟨hsl.2.2.1, hsl.2.2.2⟩

/-- Theorem 5 (Minimum-Latency Optimality Inside Priorities 1 & 2):
    Every dispatched realization achieves the minimum latency among all proof-verified,
    WattCBF-safe, `@err`-safe candidates in the bank. -/
theorem admitted_is_min_latency_among_safe
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm)
    (x : Realization) (hx : x ∈ bank) (hxs : isSafeCandidate semId st pol base c x = true) :
    r.estLatencyUs ≤ x.estLatencyUs := by
  have hex := solveDispatch_extract semId st pol base c bank r cmd alarm h
  exact (selectFastestSafe_sound semId st pol base c bank r hex.2.2.2.2.1).2 x hx hxs

/-- Theorem 6 (Proof Gate Non-Bypassability):
    No unproved realization (`proofMask != 7`) can ever be dispatched. -/
theorem unproved_never_admitted
    (semId : Int) (st : ThermalState) (pol : WattPolicy) (base : BaselineLoad)
    (c : Contract) (bank : List Realization)
    (r : Realization) (cmd : SafeCommand) (alarm : DispatchAlarm)
    (h : solveDispatch semId st pol base c bank = .dispatch r cmd alarm) :
    r.proofMask = PROOF_REQUIRED :=
  (admitted_respects_wattcbf semId st pol base c bank r cmd alarm h).1

-- =========================================================================
-- Section 5: Sequential Call-Chain Error-Composition Soundness
-- =========================================================================

/-- Sum of per-stage proven error bounds across a sequential call chain. -/
def chainErrSum : List Int → Int
  | [] => 0
  | e :: rest => e + chainErrSum rest

/-- Every stage error bound in the chain is non-negative. -/
def chainAllNonNeg : List Int → Bool
  | [] => true
  | e :: rest => decide (0 ≤ e) && chainAllNonNeg rest

/-- Chain admission predicate (exact mirror of `ps_chain_add_stage` / `ps_chain_commit`). -/
def chainAdmit (stages : List Int) (outerErr : Int) : Bool :=
  decide (0 ≤ outerErr) && chainAllNonNeg stages && decide (chainErrSum stages ≤ outerErr)

/-- Inductive additive/interval error propagation along a sequential call chain:
    if input deviation is bounded by `errIn`, then after stage with proven error `e`,
    intermediate deviation is bounded by `errIn + e`. -/
inductive ChainPropagates : List Int → Int → Int → Int → Int → Prop where
  | nil (ex ap : Int) :
      ChainPropagates [] ex ap ex ap
  | cons (e : Int) (rest : List Int) (ex0 ap0 ex1 ap1 exN apN : Int)
      (hstep : ∀ d : Int, -d ≤ ap0 - ex0 → ap0 - ex0 ≤ d →
               -(d + e) ≤ ap1 - ex1 ∧ ap1 - ex1 ≤ d + e)
      (htail : ChainPropagates rest ex1 ap1 exN apN) :
      ChainPropagates (e :: rest) ex0 ap0 exN apN

private theorem chainPropagates_bound
    (stages : List Int) (ex0 ap0 exN apN d0 : Int)
    (hprop : ChainPropagates stages ex0 ap0 exN apN)
    (hinit : -d0 ≤ ap0 - ex0 ∧ ap0 - ex0 ≤ d0) :
    -(d0 + chainErrSum stages) ≤ apN - exN ∧ apN - exN ≤ d0 + chainErrSum stages := by
  induction hprop generalizing d0 with
  | nil ex ap =>
    unfold chainErrSum
    omega
  | cons e rest ex0 ap0 ex1 ap1 exN apN hstep _ ih =>
    have h1 := hstep d0 hinit.1 hinit.2
    have h2 := ih (d0 + e) h1
    unfold chainErrSum
    omega

/-- Theorem 7 (Chain Error-Composition Soundness):
    If every stage in a sequential call chain has non-negative proven error bound and
    the sum of stage errors is `<= outerErr` (`chainAdmit stages outerErr = true`), then
    starting from exact inputs (`ap0 = ex0`), the end-to-end composed output error is
    guaranteed to remain within `[-outerErr, +outerErr]`. -/
theorem chain_error_composition_sound
    (stages : List Int) (outerErr ex0 ap0 exN apN : Int)
    (hadmit : chainAdmit stages outerErr = true)
    (hexact_in : ap0 = ex0)
    (hprop : ChainPropagates stages ex0 ap0 exN apN) :
    chainErrSum stages ≤ outerErr ∧
    -outerErr ≤ apN - exN ∧ apN - exN ≤ outerErr := by
  unfold chainAdmit at hadmit
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hadmit
  have hsum : chainErrSum stages ≤ outerErr := hadmit.2
  have hb := chainPropagates_bound stages ex0 ap0 exN apN 0 hprop (by omega)
  exact ⟨hsum, by omega, by omega⟩

/-- Theorem 8 (Chain Overflow Refusal):
    Whenever the composed chain error sum strictly exceeds `outerErr`, `chainAdmit` returns `false`. -/
theorem chain_overflow_refused (stages : List Int) (outerErr : Int)
    (hovf : chainErrSum stages > outerErr) :
    chainAdmit stages outerErr = false := by
  unfold chainAdmit
  have hle : ¬ (chainErrSum stages ≤ outerErr) := by omega
  simp [hle]

-- =========================================================================
-- Section 6: Non-Vacuity Negative-Control Witnesses (Concrete `decide` Proofs)
-- =========================================================================

/-- Negative Control 1 (Trap-14 90 W Spike Refused):
    A 90 W (`90,000 mW`) GPU realization (even with `proofMask = 7`, `err = 0`, `lat = 500 us`)
    is REFUSED by `solveDispatch` on its own, and bypassed in favor of a safe 50 W realization
    when both are in the bank. -/
theorem neg_control_trap14_90w_refused :
    let st   : ThermalState := { tDie := 76000, tSink := 66000, tAmb := 25000 }
    let pol  : WattPolicy   := { pBudget := 110000, pGpuBudget := 80000, tCeil := 78000, tau := 2 }
    let base : BaselineLoad := { baseCpuMw := 15000, baseUncMw := 5000, fanReqPct := 40 }
    let ctr  : Contract     := { purityFlag := 1, precisionTier := 1, hardDeadline := false,
                                 errBound := 0, deadlineUs := 16600, powerMw := 0 }
    let r90w : Realization  := { semId := 9001, targetTid := 6, isGpuTarget := true,
                                 precisionId := 8, estPowerMw := 90000, estLatencyUs := 500,
                                 estJoulesUj := 45000, errBound := 0, proofMask := 7 }
    let r50w : Realization  := { semId := 9001, targetTid := 6, isGpuTarget := true,
                                 precisionId := 4, estPowerMw := 50000, estLatencyUs := 3000,
                                 estJoulesUj := 150000, errBound := 0, proofMask := 7 }
    solveDispatch 9001 st pol base ctr [r90w] = .refuse .noSafeRealization ∧
    (match solveDispatch 9001 st pol base ctr [r90w, r50w] with
     | .dispatch chosen _ .none => chosen = r50w
     | _ => false) = true := by
  decide

/-- Negative Control 2 (Loosened-Precision `@err` Violation Refused):
    A fast, cool, low-power NVFP4 realization (`err = 100`) is REFUSED under `@tol 10`
    (`@err` is NEVER silently broken to meet latency or power). -/
theorem neg_control_err_violation_refused :
    let st    : ThermalState := { tDie := 60000, tSink := 54000, tAmb := 25000 }
    let pol   : WattPolicy   := { pBudget := 110000, pGpuBudget := 80000, tCeil := 85000, tau := 5 }
    let base  : BaselineLoad := { baseCpuMw := 15000, baseUncMw := 5000, fanReqPct := 40 }
    let ctr   : Contract     := { purityFlag := 1, precisionTier := 2, hardDeadline := false,
                                  errBound := 10, deadlineUs := 16600, powerMw := 0 }
    let rNv4  : Realization  := { semId := 9002, targetTid := 6, isGpuTarget := true,
                                  precisionId := 5, estPowerMw := 26000, estLatencyUs := 1200,
                                  estJoulesUj := 31200, errBound := 100, proofMask := 7 }
    solveDispatch 9002 st pol base ctr [rNv4] = .refuse .noSafeRealization := by
  decide

/-- Negative Control 3 (Tight `@hard_deadline` Fail-Closed Witness at 84 C):
    At `84.0 C` (`T_ceil = 85.0 C`, `tau = 5 s`), GPU kernels & `CPU_X925` exceed WattCBF
    headroom; only `CPU_A725` (`5 W`, `22,000 us > 16,600 us`) is safe. With `hardDeadline = true`,
    `solveDispatch` MUST fail closed with `.refuse .hardDeadlineMiss`. -/
theorem neg_control_hard_deadline_fail_closed :
    let st    : ThermalState := { tDie := 84000, tSink := 84000, tAmb := 25000 }
    let pol   : WattPolicy   := { pBudget := 110000, pGpuBudget := 80000, tCeil := 85000, tau := 5 }
    let base  : BaselineLoad := { baseCpuMw := 15000, baseUncMw := 5000, fanReqPct := 40 }
    let ctrH  : Contract     := { purityFlag := 1, precisionTier := 2, hardDeadline := true,
                                  errBound := 100, deadlineUs := 16600, powerMw := 0 }
    let rGpu  : Realization  := { semId := 9003, targetTid := 6, isGpuTarget := true,
                                  precisionId := 5, estPowerMw := 26000, estLatencyUs := 6500,
                                  estJoulesUj := 169000, errBound := 100, proofMask := 7 }
    let rX925 : Realization  := { semId := 9003, targetTid := 0, isGpuTarget := false,
                                  precisionId := 6, estPowerMw := 18000, estLatencyUs := 13000,
                                  estJoulesUj := 234000, errBound := 0, proofMask := 7 }
    let rA725 : Realization  := { semId := 9003, targetTid := 1, isGpuTarget := false,
                                  precisionId := 7, estPowerMw := 5000, estLatencyUs := 22000,
                                  estJoulesUj := 110000, errBound := 0, proofMask := 7 }
    solveDispatch 9003 st pol base ctrH [rGpu, rX925, rA725] = .refuse .hardDeadlineMiss := by
  decide

/-- Negative Control 4 (Soft Deadline Explicit `ALARM_DEADLINE_SLIP` Witness at 84 C):
    Under the exact same `84.0 C` thermal ceiling with `hardDeadline = false`, `solveDispatch`
    selects safe `CPU_A725` AND emits explicit `.deadlineSlip 5400` (never silent). -/
theorem neg_control_soft_deadline_alarm :
    let st    : ThermalState := { tDie := 84000, tSink := 84000, tAmb := 25000 }
    let pol   : WattPolicy   := { pBudget := 110000, pGpuBudget := 80000, tCeil := 85000, tau := 5 }
    let base  : BaselineLoad := { baseCpuMw := 15000, baseUncMw := 5000, fanReqPct := 40 }
    let ctrS  : Contract     := { purityFlag := 1, precisionTier := 2, hardDeadline := false,
                                  errBound := 100, deadlineUs := 16600, powerMw := 0 }
    let rGpu  : Realization  := { semId := 9003, targetTid := 6, isGpuTarget := true,
                                  precisionId := 5, estPowerMw := 26000, estLatencyUs := 6500,
                                  estJoulesUj := 169000, errBound := 100, proofMask := 7 }
    let rX925 : Realization  := { semId := 9003, targetTid := 0, isGpuTarget := false,
                                  precisionId := 6, estPowerMw := 18000, estLatencyUs := 13000,
                                  estJoulesUj := 234000, errBound := 0, proofMask := 7 }
    let rA725 : Realization  := { semId := 9003, targetTid := 1, isGpuTarget := false,
                                  precisionId := 7, estPowerMw := 5000, estLatencyUs := 22000,
                                  estJoulesUj := 110000, errBound := 0, proofMask := 7 }
    (match solveDispatch 9003 st pol base ctrS [rGpu, rX925, rA725] with
     | .dispatch chosen _ (.deadlineSlip slip) => chosen = rA725 ∧ slip = 5400
     | _ => false) = true := by
  decide

/-- Negative Control 5 (Unproved Realization `proofMask != 7` Refused):
    A realization missing the EGP3 proof bit (`proofMask = 5`) is refused even with ideal metrics. -/
theorem neg_control_unproved_mask_refused :
    let st    : ThermalState := { tDie := 60000, tSink := 54000, tAmb := 25000 }
    let pol   : WattPolicy   := { pBudget := 110000, pGpuBudget := 80000, tCeil := 85000, tau := 5 }
    let base  : BaselineLoad := { baseCpuMw := 15000, baseUncMw := 5000, fanReqPct := 40 }
    let ctr   : Contract     := { purityFlag := 1, precisionTier := 1, hardDeadline := false,
                                  errBound := 0, deadlineUs := 16600, powerMw := 0 }
    let rBad  : Realization  := { semId := 9004, targetTid := 0, isGpuTarget := false,
                                  precisionId := 6, estPowerMw := 10000, estLatencyUs := 1000,
                                  estJoulesUj := 10000, errBound := 0, proofMask := 5 }
    solveDispatch 9004 st pol base ctr [rBad] = .refuse .noSafeRealization := by
  decide

/-- Negative Control 6 (Composed Chain Error Overflow Refused vs Exact Budget Admitted):
    Stages `[40, 35, 30]` (sum `105 > 100`) are refused while `[40, 35, 25]` (sum `100 <= 100`) pass. -/
theorem neg_control_chain_err_overflow_refused :
    chainAdmit [40, 35, 30] 100 = false ∧
    chainAdmit [40, 35, 25] 100 = true := by
  decide

#print axioms cbf_admitted_safe
#print axioms admitted_respects_wattcbf
#print axioms admitted_respects_err_bound
#print axioms hard_deadline_fail_closed
#print axioms hard_deadline_miss_exact
#print axioms soft_deadline_slip_never_silent
#print axioms admitted_is_min_latency_among_safe
#print axioms unproved_never_admitted
#print axioms chain_error_composition_sound
#print axioms chain_overflow_refused
#print axioms neg_control_trap14_90w_refused
#print axioms neg_control_err_violation_refused
#print axioms neg_control_hard_deadline_fail_closed
#print axioms neg_control_soft_deadline_alarm
#print axioms neg_control_unproved_mask_refused
#print axioms neg_control_chain_err_overflow_refused

end PhysicsDispatch
