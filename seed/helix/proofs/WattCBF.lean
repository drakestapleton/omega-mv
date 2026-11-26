/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/WattCBF.lean

  Machine-checked Lean 4 safety proof for the `omega-wattd` whole-unit thermal & power
  Control Barrier Function (CBF) controller on DGX Spark GB10 (GB20B + 20-core Grace).

  Proved properties (0 sorry, standard Lean 4 axioms only, zero Mathlib dependency):
    1. Trap-14 Hardware Power Ceiling (`cbf_gpu_hard_cap`, `cbf_gpu_budget_cap`):
       For EVERY thermal state, policy, and arbitrary (even adversarial) power proposal,
       `pGpu <= 80,000 mW` (margin below Trap 14's 85-92 W hard power-off cliff) and
       `pGpu <= min 80000 pGpuBudget`.
    2. Total Package Watt Conservation (`cbf_total_budget`, `cbf_nonneg_and_fan_bounds`):
       `pGpu + pCpu + pUnc <= min pBudget 140000`, all rails non-negative, and fan duty
       strictly inside `[20%, 100%]`.
    3. Fail-Closed Non-Amplification & Invalid-Input/Fault Guards (`cbf_never_amplifies`,
       `cbf_fail_closed_overtemp`, `cbf_fail_closed_sink_overtemp`,
       `cbf_fail_closed_infeasible_barrier`, `cbf_fail_closed_bad_budget`,
       `cbf_fail_closed_bad_ceil`, `cbf_fail_closed_bad_tau`):
       The shield never increases any requested power rail, and forces `(0, 0, 0, fan=100%)`
       on over-temperature (`tDie >= tCeil` or `tSink >= tCeil`), infeasible reverse-conduction
       barrier (`rawHeatBudget < 0`, where even 0 W violates `h >= 0`), or invalid policy
       (`pBudget <= 0`, `pGpuBudget < 0`, `tau < 0`, `tCeil <= 0`, `tCeil > 90,000 mC`).
    4. Discrete 2-Node Thermal CBF Barrier Preservation & Inductive Invariance
       (`cbf_thermal_barrier_preserved`, `cbf_thermal_barrier_normal_regime`,
       `cbf_admitted_barrier_safe`, `cbf_step_box_safe`, `cbf_multistep_temp_safe`):
       With `h(T_ceil, T_die, tau, dT) = T_ceil - T_die - tau * dT`, EVERY admitted command
       (`failClosed = false`) unconditionally satisfies `h >= 0`, `T_die' <= T_ceil`, and
       next-step `h' >= 0`; by induction over arbitrary N-step sequences of arbitrary
       adversarial proposals, both Node 1 (`T_die`) and Node 2 (`T_sink`) remain inside
       `[T_amb, T_ceil]` forever.
    5. Unconditional Clamping Monotonicity, Anticipatory Pre-Cooling & Full Idempotence
       (`powerClamp_mono_pBudget`, `cbf_mono_pBudget_rails`, `cbf_mono_pGpuBudget`,
       `cbf_mono_gpu_req`, `cbf_mono_tCeil`, `cbf_mono_tSink`, `cbf_mono_tau`,
       `cbf_mono_tDie_whole_unit`, `precool_fan_mono_sink`, `cbf_idempotent`):
       Tighter budgets (unconditionally for ALL proposals), lower ceilings, hotter heatsink,
       longer lookahead `tau`, or whole-unit temperature rise monotonically reduce (or
       preserve) allowed power; higher fan duty monotonically cools Node 2 (`T_sink`),
       which monotonically increases sustainable heat headroom at burst onset; filtering an
       already-filtered command is fully idempotent across power rails, fan duty, and
       `failClosed`.
    6. Non-Vacuity Negative Controls (`neg_control_trap14_90w`, `neg_control_over_budget`,
       `neg_control_hot_die_spike`, `neg_control_invalid_budget_fail_closed`,
       `neg_control_hot_sink_infeasible`):
       Concrete counterexamples proving an unclamped 90 W GPU spike violates both Trap 14
       (`90000 > 80000`) and the thermal CBF barrier (`h = -700 < 0`), whereas `cbfFilter`
       clamps it into the safe invariant set (`pGpu = 62640 <= 80000`, `h = +668 >= 0`,
       `fanPct = 100`), and proving reverse-conduction / overheated-sink states violate
       `h >= 0` even at 0 W while `cbfFilter` fails closed with `fanPct = 100`.

  Model-to-system link:
    Constants, `ceilDiv`, `barrierH`, `stepThermal`, and `cbfFilter` mirror 1:1 the exact
    fixed-point integer implementation in `apps/omega-wattd/watt_cbf.om` (milliwatts `mW`,
    millidegrees Celsius `mC` matching Linux `/sys/class/thermal/thermal_zone{0..6}/temp`,
    seconds `s`, percent `%`). This proof verifies the mathematical safety shield model;
    live sensor reads and runtime behavior are separately verified on DGX Spark by
    `apps/omega-wattd/gate_wattd.om`.
-/

namespace WattCBF

-- Exact fixed-point hardware & thermal constants (identical to apps/omega-wattd/watt_cbf.om)
def P_GPU_HARD_MAX_MW   : Int := 80000   -- 80.000 W hard cap below Trap-14 85-92 W cliff
def P_TOTAL_HARD_MAX_MW : Int := 140000  -- 140.000 W whole-unit envelope ceiling
def P_UNC_HARD_MAX_MW   : Int := 25000   -- 25.000 W uncore/C2C/LPDDR5X rail cap
def T_CRIT_MC           : Int := 104800  -- 104.8 C Spark ACPI crit trip (thermal_zone0..6)
def T_CEIL_DEFAULT_MC   : Int := 85000   -- 85.0 C default operating die ceiling
def T_CEIL_TRAIN_MC     : Int := 78000   -- 78.0 C default training die ceiling
def T_CEIL_ABS_MAX_MC   : Int := 90000   -- 90.0 C absolute configurable ceiling
def FAN_MIN_PCT         : Int := 20      -- 20% minimum blower floor
def FAN_MAX_PCT         : Int := 100     -- 100% emergency / full blower duty

-- Discrete 2-node RC thermal constants (dt = 1 s)
def THERMAL_SCALE : Int := 1000
def K_GPU_HEAT    : Int := 25     -- 25 mC/s per W GPU self-heating (C_die = 40 J/C)
def K_CPU_HEAT    : Int := 5      -- 5 mC/s per W CPU+Uncore cross-die coupling
def K_DS_COND     : Int := 100    -- 0.10 /s die-to-sink conductance (tau_die = 10 s)
def K_SINK_IN     : Int := 10     -- 0.01 /s die-to-sink heat into vapor chamber
def K_FAN_BASE    : Int := 2      -- 0.002 /s base sink-to-ambient conductance
def K_FAN_SLOPE   : Int := 8      -- +0.008 /s at 100% fan (0.010 /s total)
def SINK_SCALE    : Int := 100000 -- THERMAL_SCALE * 100 for exact integer fan slope

structure ThermalState where
  tDie  : Int  -- Node 1: silicon die temperature in mC (TGPU / max(TGPU, TSOC))
  tSink : Int  -- Node 2: vapor-chamber / heatsink temperature in mC
  tAmb  : Int  -- Ambient intake temperature in mC
  deriving Repr, DecidableEq

structure WattPolicy where
  pBudget    : Int  -- Total package power budget in mW
  pGpuBudget : Int  -- Mode/policy GPU power cap in mW
  tCeil      : Int  -- Die temperature ceiling in mC (<= T_CEIL_ABS_MAX_MC)
  tau        : Int  -- CBF lookahead horizon in s (>= 0)
  deriving Repr, DecidableEq

structure PowerProposal where
  pGpu   : Int  -- Requested GPU power in mW
  pCpu   : Int  -- Requested Grace 20-core CPU power in mW
  pUnc   : Int  -- Requested Uncore/C2C power in mW
  fanPct : Int  -- Requested blower duty in %
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

/-- Exact ceiling division for `b > 0`, matching AArch64 signed `div` in `watt_cbf.om`:
    rounds toward +infinity so heating rates are never underestimated. -/
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

theorem ceilDiv_mono (a1 a2 b : Int) (hb : b > 0) (h : a1 ≤ a2) :
    ceilDiv a1 b ≤ ceilDiv a2 b := by
  rw [ceilDiv_le_iff a1 b (ceilDiv a2 b) hb]
  have h2 : a2 ≤ b * ceilDiv a2 b := (ceilDiv_le_iff a2 b (ceilDiv a2 b) hb).mp (Int.le_refl _)
  omega

/-- Control Barrier Function: `h = T_ceil - T_die - tau * dT`. -/
def barrierH (tCeil tDie tau dT : Int) : Int :=
  tCeil - tDie - tau * dT

/-- Die thermal power input in scaled units (`kGpu * pGpu + kCpu * (pCpu + pUnc)`). -/
def dieHeat (pGpu pCpu pUnc : Int) : Int :=
  K_GPU_HEAT * pGpu + K_CPU_HEAT * (pCpu + pUnc)

/-- Die-to-sink passive cooling term in scaled units (`kDs * (tDie - tSink)`). -/
def dieCoolDs (st : ThermalState) : Int :=
  K_DS_COND * (st.tDie - st.tSink)

/-- Conservative one-step Node 1 (`T_die`) temperature change in mC. -/
def nextDieDelta (st : ThermalState) (pGpu pCpu pUnc : Int) : Int :=
  ceilDiv (dieHeat pGpu pCpu pUnc - dieCoolDs st) THERMAL_SCALE

/-- Conservative one-step Node 2 (`T_sink`) temperature change in mC. -/
def nextSinkDelta (st : ThermalState) (fanPct : Int) : Int :=
  ceilDiv
    (K_SINK_IN * 100 * (st.tDie - st.tSink) -
     (K_FAN_BASE * 100 + K_FAN_SLOPE * fanPct) * (st.tSink - st.tAmb))
    SINK_SCALE

/-- Discrete 2-node thermal state transition (`dt = 1 s`). -/
def stepThermal (st : ThermalState) (pGpu pCpu pUnc fanPct : Int) : ThermalState :=
  { tDie  := st.tDie + nextDieDelta st pGpu pCpu pUnc
    tSink := st.tSink + nextSinkDelta st fanPct
    tAmb  := st.tAmb }

/-- Clamp integer `x` into `[0, max(0, hi)]`. -/
def clampNonNeg (x hi : Int) : Int :=
  if hi ≤ 0 then 0
  else if x ≤ 0 then 0
  else if x ≥ hi then hi
  else x

/-- Policy validity predicate. -/
def policyValid (pol : WattPolicy) : Bool :=
  decide (pol.pBudget > 0 ∧ pol.pGpuBudget ≥ 0 ∧ pol.tCeil > 0 ∧
          pol.tCeil ≤ T_CEIL_ABS_MAX_MC ∧ pol.tau ≥ 0)

/-- Raw signed thermal heat budget before clamping to 0: negative means even 0 W
    cannot satisfy `barrierH >= 0` due to reverse conduction from a hotter sink. -/
def rawHeatBudget (st : ThermalState) (pol : WattPolicy) : Int :=
  if pol.tau < 0 then 0
  else THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st

/-- Maximum thermally-safe scaled die heat for `(st, pol)`. -/
def maxHeatSafe (st : ThermalState) (pol : WattPolicy) : Int :=
  if st.tDie ≥ pol.tCeil ∨ st.tSink ≥ pol.tCeil ∨ pol.tau < 0 then 0
  else max 0 (rawHeatBudget st pol)

/-- Fail-closed predicate: invalid policy, Node 1 or Node 2 at/above ceiling,
    or infeasible zero-power thermal barrier (`rawHeatBudget < 0`). -/
def mustFailClosed (st : ThermalState) (pol : WattPolicy) : Bool :=
  !policyValid pol ||
  decide (st.tDie ≥ pol.tCeil) ||
  decide (st.tSink ≥ pol.tCeil) ||
  decide (rawHeatBudget st pol < 0)

/-- Monotonic safety fan floor from thermal headroom and clamp engagement. -/
def safeFanFloor (headroom : Int) (thermalClamped : Bool) : Int :=
  if thermalClamped || decide (headroom ≤ 5000) then FAN_MAX_PCT
  else if decide (headroom ≤ 10000) then 85
  else if decide (headroom ≤ 18000) then 65
  else if decide (headroom ≤ 28000) then 45
  else FAN_MIN_PCT

/-- Stage A: Power-budget and Trap-14 hard ceiling clamp (`Uncore -> CPU -> GPU`). -/
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

/-- Stage B: Discrete thermal CBF water-fill clamp (`dieHeat <= maxHeat`). -/
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

/-- Fail-closed Discrete Thermal & Power CBF Safety Filter (exact mirror of `watt_cbf.om`). -/
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
-- Core Arithmetic & Stage Helpers
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

private theorem clampNonNeg_eq_self (x hi : Int) (hx0 : 0 ≤ x) (hxhi : x ≤ hi) :
    clampNonNeg x hi = x := by
  unfold clampNonNeg
  by_cases h1 : hi ≤ 0
  · simp [h1]; omega
  · by_cases h2 : x ≤ 0
    · simp [h1, h2]; omega
    · by_cases h3 : x ≥ hi
      · simp [h1, h2, h3]; omega
      · simp [h1, h2, h3]

private theorem clampNonNeg_mono_hi (x hi1 hi2 : Int) (h : hi1 ≤ hi2) :
    clampNonNeg x hi1 ≤ clampNonNeg x hi2 := by
  unfold clampNonNeg
  by_cases a1 : hi1 ≤ 0 <;> by_cases a2 : hi2 ≤ 0 <;>
  by_cases bx : x ≤ 0 <;> by_cases c1 : x ≥ hi1 <;> by_cases c2 : x ≥ hi2 <;>
  simp [a1, a2, bx, c1, c2] <;> omega

private theorem clampNonNeg_mono_x (x1 x2 hi : Int) (h : x1 ≤ x2) :
    clampNonNeg x1 hi ≤ clampNonNeg x2 hi := by
  unfold clampNonNeg
  by_cases ah : hi ≤ 0 <;> by_cases b1 : x1 ≤ 0 <;> by_cases b2 : x2 ≤ 0 <;>
  by_cases c1 : x1 ≥ hi <;> by_cases c2 : x2 ≥ hi <;>
  simp [ah, b1, b2, c1, c2] <;> omega

private theorem clampNonNeg_rem_mono (x hi1 hi2 : Int) (h : hi1 ≤ hi2) (h1 : 0 ≤ hi1) :
    hi1 - clampNonNeg x hi1 ≤ hi2 - clampNonNeg x hi2 := by
  unfold clampNonNeg
  by_cases a1 : hi1 ≤ 0 <;> by_cases a2 : hi2 ≤ 0 <;>
  by_cases bx : x ≤ 0 <;> by_cases c1 : x ≥ hi1 <;> by_cases c2 : x ≥ hi2 <;>
  simp [a1, a2, bx, c1, c2] <;> omega

private theorem maxHeatSafe_nonneg (st : ThermalState) (pol : WattPolicy) :
    0 ≤ maxHeatSafe st pol := by
  unfold maxHeatSafe
  split <;> omega

private theorem safeFanFloor_bounds (headroom : Int) (tc : Bool) :
    FAN_MIN_PCT ≤ safeFanFloor headroom tc ∧ safeFanFloor headroom tc ≤ FAN_MAX_PCT := by
  unfold safeFanFloor FAN_MIN_PCT FAN_MAX_PCT
  by_cases h1 : (tc || decide (headroom ≤ 5000)) = true
  · simp [h1]
  · simp only [h1, Bool.false_eq_true, ↓reduceIte]
    by_cases h2 : headroom ≤ 10000
    · simp [h2]
    · by_cases h3 : headroom ≤ 18000
      · simp [h2, h3]
      · by_cases h4 : headroom ≤ 28000
        · simp [h2, h3, h4]
        · simp [h2, h3, h4]

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

private theorem powerClamp_le_prop (pol : WattPolicy) (prop : PowerProposal)
    (hg : 0 ≤ prop.pGpu) (hc : 0 ≤ prop.pCpu) (hu : 0 ≤ prop.pUnc) :
    let r := powerClamp pol prop
    r.pUnc ≤ prop.pUnc ∧ r.pCpu ≤ prop.pCpu ∧ r.pGpu ≤ prop.pGpu := by
  dsimp only [powerClamp, powerClampUnc, powerClampCpu, powerClampGpu]
  exact ⟨(clampNonNeg_bounds _ _).2.2 hu,
         (clampNonNeg_bounds _ _).2.2 hc,
         (clampNonNeg_bounds _ _).2.2 hg⟩

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

/-- Monotonicity of `thermalClamp` in `maxHeat` for fixed power-clamped rails `r`. -/
private theorem thermalClamp_mono_heat (r : RailTriple) (m1 m2 : Int) (hm : m1 ≤ m2) :
    let t1 := thermalClamp r m1
    let t2 := thermalClamp r m2
    t1.pUnc ≤ t2.pUnc ∧ t1.pCpu ≤ t2.pCpu ∧ t1.pGpu ≤ t2.pGpu := by
  dsimp only [thermalClamp]
  have hhu : thermalHeatUnc r m1 ≤ thermalHeatUnc r m2 := by
    unfold thermalHeatUnc; omega
  have hr1 : m1 - thermalHeatUnc r m1 ≤ m2 - thermalHeatUnc r m2 := by
    unfold thermalHeatUnc; omega
  have hhc : thermalHeatCpu r m1 ≤ thermalHeatCpu r m2 := by
    unfold thermalHeatCpu; omega
  have hr2 : (m1 - thermalHeatUnc r m1) - thermalHeatCpu r m1 ≤
             (m2 - thermalHeatUnc r m2) - thermalHeatCpu r m2 := by
    unfold thermalHeatCpu; omega
  have hhg : thermalHeatGpu r m1 ≤ thermalHeatGpu r m2 := by
    unfold thermalHeatGpu; omega
  exact ⟨Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hhu,
         Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hhc,
         Int.ediv_le_ediv (by decide : (0 : Int) < K_GPU_HEAT) hhg⟩

/-- Monotonicity of `thermalClamp` in `r.pGpu` when `pUnc` and `pCpu` match. -/
private theorem thermalClamp_mono_gpu (r1 r2 : RailTriple) (m1 m2 : Int)
    (hu : r1.pUnc = r2.pUnc) (hc : r1.pCpu = r2.pCpu) (hg : r1.pGpu ≤ r2.pGpu) (hm : m1 ≤ m2) :
    let t1 := thermalClamp r1 m1
    let t2 := thermalClamp r2 m2
    t1.pUnc ≤ t2.pUnc ∧ t1.pCpu ≤ t2.pCpu ∧ t1.pGpu ≤ t2.pGpu := by
  dsimp only [thermalClamp]
  have hhu : thermalHeatUnc r1 m1 ≤ thermalHeatUnc r2 m2 := by
    unfold thermalHeatUnc; rw [hu]; omega
  have hr1 : m1 - thermalHeatUnc r1 m1 ≤ m2 - thermalHeatUnc r2 m2 := by
    unfold thermalHeatUnc; rw [hu]; omega
  have hhc : thermalHeatCpu r1 m1 ≤ thermalHeatCpu r2 m2 := by
    unfold thermalHeatCpu; rw [hc]; omega
  have hr2 : (m1 - thermalHeatUnc r1 m1) - thermalHeatCpu r1 m1 ≤
             (m2 - thermalHeatUnc r2 m2) - thermalHeatCpu r2 m2 := by
    unfold thermalHeatCpu; rw [hc]; omega
  have hhg : thermalHeatGpu r1 m1 ≤ thermalHeatGpu r2 m2 := by
    unfold thermalHeatGpu K_GPU_HEAT; omega
  exact ⟨Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hhu,
         Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hhc,
         Int.ediv_le_ediv (by decide : (0 : Int) < K_GPU_HEAT) hhg⟩

private theorem safeFanFloor_mono_tc (headroom : Int) (tc : Bool) :
    safeFanFloor headroom false ≤ safeFanFloor headroom tc := by
  cases tc
  · exact Int.le_refl _
  · unfold safeFanFloor FAN_MIN_PCT FAN_MAX_PCT
    by_cases h1 : headroom ≤ 5000
    · simp [h1]
    · by_cases h2 : headroom ≤ 10000
      · simp [h1, h2]
      · by_cases h3 : headroom ≤ 18000
        · simp [h1, h2, h3]
        · by_cases h4 : headroom ≤ 28000
          · simp [h1, h2, h3, h4]
          · simp [h1, h2, h3, h4]

private theorem policyValid_of_not_guard (st : ThermalState) (pol : WattPolicy)
    (h : ¬ (mustFailClosed st pol = true)) :
    pol.pBudget > 0 ∧ pol.pGpuBudget ≥ 0 ∧ pol.tCeil > 0 ∧
    pol.tCeil ≤ T_CEIL_ABS_MAX_MC ∧ pol.tau ≥ 0 ∧
    st.tDie < pol.tCeil ∧ st.tSink < pol.tCeil ∧
    0 ≤ rawHeatBudget st pol := by
  unfold mustFailClosed at h
  have hv : policyValid pol = true := by
    cases hpv : policyValid pol <;> simp [hpv] at h ⊢
  have hdie : ¬ (st.tDie ≥ pol.tCeil) := by
    intro hge; simp [hge] at h
  have hsink : ¬ (st.tSink ≥ pol.tCeil) := by
    intro hge; simp [hge] at h
  have hraw : ¬ (rawHeatBudget st pol < 0) := by
    intro hlt; simp [hlt] at h
  unfold policyValid at hv
  simp only [decide_eq_true_eq] at hv
  omega

private theorem not_mustFailClosed_of_ok (st : ThermalState) (pol : WattPolicy)
    (hbud : pol.pBudget > 0) (hgb : pol.pGpuBudget ≥ 0)
    (hce0 : pol.tCeil > 0) (hceM : pol.tCeil ≤ T_CEIL_ABS_MAX_MC)
    (htau : pol.tau ≥ 0) (hdie : st.tDie < pol.tCeil)
    (hsink : st.tSink < pol.tCeil) (hraw : 0 ≤ rawHeatBudget st pol) :
    ¬ (mustFailClosed st pol = true) := by
  unfold mustFailClosed
  have hv : policyValid pol = true := by
    unfold policyValid; simp only [decide_eq_true_eq]; omega
  have g1 : ¬ (st.tDie ≥ pol.tCeil) := by omega
  have g2 : ¬ (st.tSink ≥ pol.tCeil) := by omega
  have g3 : ¬ (rawHeatBudget st pol < 0) := by omega
  simp [hv, g1, g2, g3]

private theorem cbf_ok_rails (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (h : ¬ (mustFailClosed st pol = true)) :
    (cbfFilter st pol prop).pGpu = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu ∧
    (cbfFilter st pol prop).pCpu = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu ∧
    (cbfFilter st pol prop).pUnc = (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc := by
  unfold cbfFilter
  rw [ite_eq_right h]
  exact ⟨rfl, rfl, rfl⟩

-- =========================================================================
-- Section 1: Power Ceiling, Budget Conservation, and Non-Negativity
-- =========================================================================

/-- Trap-14 Hardware Ceiling: filtered GPU power NEVER exceeds 80,000 mW (80 W). -/
theorem cbf_gpu_hard_cap (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal) :
    (cbfFilter st pol prop).pGpu ≤ P_GPU_HARD_MAX_MW := by
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h, P_GPU_HARD_MAX_MW]
  · have hok := cbf_ok_rails st pol prop h
    have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop (by omega) (by omega)
    have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
    omega

/-- Policy + Trap-14 GPU Ceiling: `pGpu <= min 80000 pol.pGpuBudget` whenever `pol.pGpuBudget >= 0`. -/
theorem cbf_gpu_budget_cap (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hgb : 0 ≤ pol.pGpuBudget) :
    (cbfFilter st pol prop).pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget := by
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h, P_GPU_HARD_MAX_MW]; omega
  · have hok := cbf_ok_rails st pol prop h
    have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop (by omega) hgb
    have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
    omega

/-- Total Package Watt Budget Conservation: `pGpu + pCpu + pUnc <= min pBudget 140000`. -/
theorem cbf_total_budget (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hb : 0 ≤ pol.pBudget) :
    let out := cbfFilter st pol prop
    out.pGpu + out.pCpu + out.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW := by
  dsimp only
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h, P_TOTAL_HARD_MAX_MW]; omega
  · have hok := cbf_ok_rails st pol prop h
    have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop hb (by omega)
    have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
    omega

/-- All output power rails are non-negative and fan duty stays within `[20%, 100%]`. -/
theorem cbf_nonneg_and_fan_bounds (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal) :
    let out := cbfFilter st pol prop
    0 ≤ out.pGpu ∧ 0 ≤ out.pCpu ∧ 0 ≤ out.pUnc ∧
    FAN_MIN_PCT ≤ out.fanPct ∧ out.fanPct ≤ FAN_MAX_PCT := by
  dsimp only
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h, FAN_MIN_PCT, FAN_MAX_PCT]
  · have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop (by omega) (by omega)
    have th := thermalClamp_nonneg_and_heat (powerClamp pol prop) (maxHeatSafe st pol)
      pb.1 pb.2.1 pb.2.2.1 (maxHeatSafe_nonneg st pol)
    unfold cbfFilter
    rw [ite_eq_right h]
    dsimp only
    have hf := safeFanFloor_bounds (pol.tCeil - st.tDie)
      (decide ((thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc < (powerClamp pol prop).pUnc ∨
               (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu < (powerClamp pol prop).pCpu ∨
               (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu < (powerClamp pol prop).pGpu))
    unfold FAN_MIN_PCT FAN_MAX_PCT at *
    refine ⟨th.2.2.1, th.2.1, th.1, by omega, by omega⟩

/-- Fail-Closed Non-Amplification: the shield NEVER increases any non-negative power request. -/
theorem cbf_never_amplifies (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hg : 0 ≤ prop.pGpu) (hc : 0 ≤ prop.pCpu) (hu : 0 ≤ prop.pUnc) :
    let out := cbfFilter st pol prop
    out.pGpu ≤ prop.pGpu ∧ out.pCpu ≤ prop.pCpu ∧ out.pUnc ≤ prop.pUnc := by
  dsimp only
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h]; omega
  · have hok := cbf_ok_rails st pol prop h
    have pl := powerClamp_le_prop pol prop hg hc hu
    have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
    omega

-- =========================================================================
-- Section 2: Fail-Closed Guards
-- =========================================================================

theorem cbf_fail_closed_overtemp (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hot : st.tDie ≥ pol.tCeil) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have h : (!policyValid pol || decide (st.tDie ≥ pol.tCeil) ||
            decide (st.tSink ≥ pol.tCeil) || decide (rawHeatBudget st pol < 0)) = true := by
    simp [hot]
  simp [h]

theorem cbf_fail_closed_sink_overtemp (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hot : st.tSink ≥ pol.tCeil) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have h : (!policyValid pol || decide (st.tDie ≥ pol.tCeil) ||
            decide (st.tSink ≥ pol.tCeil) || decide (rawHeatBudget st pol < 0)) = true := by
    simp [hot]
  simp [h]

theorem cbf_fail_closed_infeasible_barrier (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hinfeas : rawHeatBudget st pol < 0) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have h : (!policyValid pol || decide (st.tDie ≥ pol.tCeil) ||
            decide (st.tSink ≥ pol.tCeil) || decide (rawHeatBudget st pol < 0)) = true := by
    simp [hinfeas]
  simp [h]

theorem cbf_fail_closed_bad_budget (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hbad : pol.pBudget ≤ 0) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have hv : policyValid pol = false := by
    unfold policyValid; simp [decide_eq_false_iff_not]; omega
  simp [hv]

theorem cbf_fail_closed_bad_ceil (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hbad : pol.tCeil > T_CEIL_ABS_MAX_MC) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have hv : policyValid pol = false := by
    unfold policyValid; simp [decide_eq_false_iff_not]; omega
  simp [hv]

theorem cbf_fail_closed_bad_tau (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hbad : pol.tau < 0) :
    let out := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  dsimp only
  unfold cbfFilter mustFailClosed
  have hv : policyValid pol = false := by
    unfold policyValid; simp [decide_eq_false_iff_not]; omega
  simp [hv]

-- =========================================================================
-- Section 3: Discrete 2-Node Thermal CBF Barrier Preservation & Induction
-- =========================================================================

/-- Core heat bound: every filtered command produces `dieHeat <= maxHeatSafe st pol`. -/
theorem cbf_die_heat_le_maxHeat (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal) :
    let out := cbfFilter st pol prop
    dieHeat out.pGpu out.pCpu out.pUnc ≤ maxHeatSafe st pol := by
  dsimp only
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h, dieHeat]
    exact maxHeatSafe_nonneg st pol
  · have hok := cbf_ok_rails st pol prop h
    have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop (by omega) (by omega)
    have th := thermalClamp_nonneg_and_heat (powerClamp pol prop) (maxHeatSafe st pol)
      pb.1 pb.2.1 pb.2.2.1 (maxHeatSafe_nonneg st pol)
    rw [hok.1, hok.2.1, hok.2.2]
    exact th.2.2.2

/-- Main Thermal CBF Barrier Theorem:
    Whenever `T_die <= T_ceil`, `tau >= 0`, and passive die-sink conduction does not
    exceed the ceiling margin (in particular whenever `T_sink <= T_die`), the filtered
    command satisfies:
      1. `barrierH T_ceil T_die tau dT >= 0` (`T_ceil - T_die - tau * dT >= 0`),
      2. `(stepThermal st out).tDie <= T_ceil`, and
      3. `barrierH T_ceil (stepThermal st out).tDie tau dT >= 0` (strong forward invariance). -/
theorem cbf_thermal_barrier_preserved
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (htau : 0 ≤ pol.tau)
    (hle  : st.tDie ≤ pol.tCeil)
    (hpassive : 0 ≤ THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st) :
    let out := cbfFilter st pol prop
    let dT  := nextDieDelta st out.pGpu out.pCpu out.pUnc
    let st' := stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct
    barrierH pol.tCeil st.tDie pol.tau dT ≥ 0 ∧
    st'.tDie ≤ pol.tCeil ∧
    barrierH pol.tCeil st'.tDie pol.tau dT ≥ 0 := by
  dsimp only
  have hheat := cbf_die_heat_le_maxHeat st pol prop
  by_cases hlt : st.tDie < pol.tCeil
  · have hmh_le : maxHeatSafe st pol ≤
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
            (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc := Int.mul_nonneg htau hpos
        omega
      · omega
    have htau_bound : pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ pol.tCeil - st.tDie := by
      by_cases hpos : 0 ≤ nextDieDelta st (cbfFilter st pol prop).pGpu
          (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc
      · omega
      · have : pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
            (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ 0 :=
          Int.mul_nonpos_of_nonneg_of_nonpos htau (by omega)
        omega
    unfold barrierH stepThermal
    dsimp only
    exact ⟨by omega, by omega, by omega⟩
  · have heq : st.tDie = pol.tCeil := by omega
    have hfc := cbf_fail_closed_overtemp st pol prop (by omega)
    have hd0 : dieHeat (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
        (cbfFilter st pol prop).pUnc = 0 := by
      unfold dieHeat; rw [hfc.1, hfc.2.1, hfc.2.2.1]; decide
    have hcool : 0 ≤ dieCoolDs st := by
      have : pol.tCeil - st.tDie = 0 := by omega
      rw [this] at hpassive
      simp only [Int.zero_ediv, Int.mul_zero, Int.zero_add] at hpassive
      exact hpassive
    have hdT0 : nextDieDelta st (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
        (cbfFilter st pol prop).pUnc ≤ 0 := by
      unfold nextDieDelta
      rw [ceilDiv_le_iff _ THERMAL_SCALE 0 (by decide)]
      omega
    have hmul0 : pol.tau * nextDieDelta st (cbfFilter st pol prop).pGpu
        (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ 0 :=
      Int.mul_nonpos_of_nonneg_of_nonpos htau hdT0
    unfold barrierH stepThermal
    dsimp only
    exact ⟨by omega, by omega, by omega⟩

/-- Unconditional Admitted-Command Safety Theorem:
    For ANY `(st, pol, prop)` whatsoever (zero extra assumptions on `tSink`, `tDie`, or `pol`),
    whenever `cbfFilter` does NOT fail closed (`failClosed = false`), ALL safety invariants
    hold simultaneously: Trap-14 GPU cap, total Watt budget, `barrierH >= 0`, `tDie' <= tCeil`,
    and next-step `barrierH' >= 0`. -/
theorem cbf_admitted_barrier_safe
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hadmit : (cbfFilter st pol prop).failClosed = false) :
    let out := cbfFilter st pol prop
    let dT  := nextDieDelta st out.pGpu out.pCpu out.pUnc
    let st' := stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct
    out.pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget ∧
    out.pGpu + out.pCpu + out.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW ∧
    barrierH pol.tCeil st.tDie pol.tau dT ≥ 0 ∧
    st'.tDie ≤ pol.tCeil ∧
    barrierH pol.tCeil st'.tDie pol.tau dT ≥ 0 := by
  dsimp only
  have hng : ¬ (mustFailClosed st pol = true) := by
    intro hfc
    unfold cbfFilter at hadmit
    simp [hfc] at hadmit
  have hp := policyValid_of_not_guard st pol hng
  have hraw : 0 ≤ THERMAL_SCALE * ((pol.tCeil - st.tDie) / (pol.tau + 1)) + dieCoolDs st := by
    have h1 := hp.2.2.2.2.2.2.2
    unfold rawHeatBudget at h1
    have hnt : ¬ (pol.tau < 0) := by omega
    simp only [hnt, ↓reduceIte] at h1
    exact h1
  have hbar := cbf_thermal_barrier_preserved st pol prop (by omega) (by omega) hraw
  have hg := cbf_gpu_budget_cap st pol prop (by omega)
  have ht := cbf_total_budget st pol prop (by omega)
  exact ⟨hg, ht, hbar.1, hbar.2.1, hbar.2.2⟩

/-- Corollary: In the normal heated-die regime (`tSink <= tDie <= tCeil`), `h >= 0` holds
    without any extra passive-conduction hypothesis. -/
theorem cbf_thermal_barrier_normal_regime
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (htau : 0 ≤ pol.tau) (hle : st.tDie ≤ pol.tCeil) (hsink : st.tSink ≤ st.tDie) :
    let out := cbfFilter st pol prop
    let dT  := nextDieDelta st out.pGpu out.pCpu out.pUnc
    let st' := stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct
    barrierH pol.tCeil st.tDie pol.tau dT ≥ 0 ∧
    st'.tDie ≤ pol.tCeil ∧
    barrierH pol.tCeil st'.tDie pol.tau dT ≥ 0 := by
  apply cbf_thermal_barrier_preserved st pol prop htau hle
  have h1 : 0 ≤ (pol.tCeil - st.tDie) / (pol.tau + 1) :=
    Int.ediv_nonneg (by omega) (by omega)
  have h2 : 0 ≤ dieCoolDs st := by unfold dieCoolDs K_DS_COND; omega
  unfold THERMAL_SCALE
  omega

/-- Safe 2-node thermal box invariant: both nodes stay within `[tAmb, tCeil]`. -/
def thermalBoxSafe (st : ThermalState) (pol : WattPolicy) : Prop :=
  st.tAmb ≤ st.tDie ∧ st.tDie ≤ pol.tCeil ∧
  st.tAmb ≤ st.tSink ∧ st.tSink ≤ pol.tCeil

private theorem ceilDiv_neg_mul_self (b x : Int) (hb : b > 0) :
    ceilDiv (-(b * x)) b = -x := by
  have hle : ceilDiv (-(b * x)) b ≤ -x := by
    rw [ceilDiv_le_iff _ b _ hb]
    have : b * (-x) = -(b * x) := Int.mul_neg b x
    omega
  have hge : ¬ (ceilDiv (-(b * x)) b ≤ -x - 1) := by
    rw [ceilDiv_le_iff _ b _ hb]
    have h1 : b * (-x - 1) = -(b * x) - b := by
      have hsub : b * (-x - 1) = b * (-x) - b * 1 := Int.mul_sub b (-x) 1
      have hneg : b * (-x) = -(b * x) := Int.mul_neg b x
      omega
    omega
  omega

/-- One-step unconditional invariance of the 2-node thermal box `[tAmb, tCeil]`. -/
theorem cbf_step_box_safe
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (htau : 0 ≤ pol.tau)
    (hbox : thermalBoxSafe st pol) :
    let out := cbfFilter st pol prop
    thermalBoxSafe (stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct) pol := by
  dsimp only
  have ⟨hambD, hDceil, hambS, hSceil⟩ := hbox
  have hbounds := cbf_nonneg_and_fan_bounds st pol prop
  have hheat_nn : 0 ≤ dieHeat (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
      (cbfFilter st pol prop).pUnc := by
    unfold dieHeat K_GPU_HEAT K_CPU_HEAT; omega
  have hheat_le := cbf_die_heat_le_maxHeat st pol prop
  have htDie_le : st.tDie + nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc ≤ pol.tCeil := by
    have hdT : nextDieDelta st (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
        (cbfFilter st pol prop).pUnc ≤ pol.tCeil - st.tDie := by
      unfold nextDieDelta
      rw [ceilDiv_le_iff _ THERMAL_SCALE _ (by decide)]
      by_cases hlt : st.tDie < pol.tCeil
      · unfold maxHeatSafe rawHeatBudget at hheat_le
        have hntau : ¬ (pol.tau < 0) := by omega
        simp only [hntau, ↓reduceIte] at hheat_le
        have hdiv := mul_ediv_bounds (pol.tCeil - st.tDie) (pol.tau + 1) (by omega) (by omega)
        have hqle : (pol.tCeil - st.tDie) / (pol.tau + 1) ≤ pol.tCeil - st.tDie := by
          have h1 : 1 * ((pol.tCeil - st.tDie) / (pol.tau + 1)) ≤
              (pol.tau + 1) * ((pol.tCeil - st.tDie) / (pol.tau + 1)) :=
            Int.mul_le_mul_of_nonneg_right (by omega) hdiv.1
          omega
        split at hheat_le <;> (unfold dieCoolDs K_DS_COND THERMAL_SCALE at *; omega)
      · have hfc := cbf_fail_closed_overtemp st pol prop (by omega)
        have hd0 : dieHeat (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
            (cbfFilter st pol prop).pUnc = 0 := by
          unfold dieHeat; rw [hfc.1, hfc.2.1, hfc.2.2.1]; decide
        unfold dieCoolDs K_DS_COND THERMAL_SCALE at *; omega
    omega
  have htDie_ge : st.tAmb ≤ st.tDie + nextDieDelta st (cbfFilter st pol prop).pGpu
      (cbfFilter st pol prop).pCpu (cbfFilter st pol prop).pUnc := by
    have hnum : -(THERMAL_SCALE * (st.tDie - st.tAmb)) ≤
        dieHeat (cbfFilter st pol prop).pGpu (cbfFilter st pol prop).pCpu
          (cbfFilter st pol prop).pUnc - dieCoolDs st := by
      unfold dieCoolDs K_DS_COND THERMAL_SCALE; omega
    have hmono := ceilDiv_mono _ _ THERMAL_SCALE (by decide) hnum
    rw [ceilDiv_neg_mul_self THERMAL_SCALE (st.tDie - st.tAmb) (by decide)] at hmono
    unfold nextDieDelta; omega
  have htSink_le : st.tSink + nextSinkDelta st (cbfFilter st pol prop).fanPct ≤ pol.tCeil := by
    have hdS : nextSinkDelta st (cbfFilter st pol prop).fanPct ≤ pol.tCeil - st.tSink := by
      unfold nextSinkDelta
      rw [ceilDiv_le_iff _ SINK_SCALE _ (by decide)]
      have hfan : 0 ≤ (K_FAN_BASE * 100 + K_FAN_SLOPE * (cbfFilter st pol prop).fanPct) *
          (st.tSink - st.tAmb) := by
        apply Int.mul_nonneg
        · unfold K_FAN_BASE K_FAN_SLOPE FAN_MIN_PCT at *; omega
        · omega
      unfold K_SINK_IN SINK_SCALE; omega
    omega
  have htSink_ge : st.tAmb ≤ st.tSink + nextSinkDelta st (cbfFilter st pol prop).fanPct := by
    have hfan_ub : (K_FAN_BASE * 100 + K_FAN_SLOPE * (cbfFilter st pol prop).fanPct) *
        (st.tSink - st.tAmb) ≤ 1000 * (st.tSink - st.tAmb) := by
      apply Int.mul_le_mul_of_nonneg_right
      · unfold K_FAN_BASE K_FAN_SLOPE FAN_MAX_PCT at *; omega
      · omega
    have hnum : -(SINK_SCALE * (st.tSink - st.tAmb)) ≤
        K_SINK_IN * 100 * (st.tDie - st.tSink) -
        (K_FAN_BASE * 100 + K_FAN_SLOPE * (cbfFilter st pol prop).fanPct) *
          (st.tSink - st.tAmb) := by
      unfold K_SINK_IN SINK_SCALE; omega
    have hmono := ceilDiv_mono _ _ SINK_SCALE (by decide) hnum
    rw [ceilDiv_neg_mul_self SINK_SCALE (st.tSink - st.tAmb) (by decide)] at hmono
    unfold nextSinkDelta; omega
  unfold thermalBoxSafe stepThermal
  exact ⟨htDie_ge, htDie_le, htSink_ge, htSink_le⟩

/-- Run an arbitrary sequence of proposals through the closed-loop CBF controller. -/
def runClosedLoop (st : ThermalState) (pol : WattPolicy) : List PowerProposal → ThermalState
  | [] => st
  | prop :: rest =>
    let out := cbfFilter st pol prop
    runClosedLoop (stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct) pol rest

/-- Inductive N-step closed-loop safety: for ANY finite horizon and ANY sequence of
    arbitrary proposals, both `T_die` and `T_sink` remain inside `[T_amb, T_ceil]`. -/
theorem cbf_multistep_temp_safe
    (props : List PowerProposal) (st : ThermalState) (pol : WattPolicy)
    (htau : 0 ≤ pol.tau) (hbox : thermalBoxSafe st pol) :
    thermalBoxSafe (runClosedLoop st pol props) pol := by
  induction props generalizing st with
  | nil => exact hbox
  | cons prop rest ih =>
    unfold runClosedLoop
    exact ih _ (cbf_step_box_safe st pol prop htau hbox)

-- =========================================================================
-- Section 4: Clamping Monotonicity, Pre-Cooling & Idempotence
-- =========================================================================

/-- Stage-A power-clamp monotonicity: raising `pBudget` never decreases any rail
    in `powerClamp`. -/
theorem powerClamp_mono_pBudget
    (pol1 pol2 : WattPolicy) (prop : PowerProposal)
    (hb0  : 0 ≤ pol1.pBudget)
    (hbud : pol1.pBudget ≤ pol2.pBudget)
    (hgb  : pol1.pGpuBudget = pol2.pGpuBudget) :
    let r1 := powerClamp pol1 prop
    let r2 := powerClamp pol2 prop
    r1.pUnc ≤ r2.pUnc ∧ r1.pCpu ≤ r2.pCpu ∧ r1.pGpu ≤ r2.pGpu := by
  dsimp only [powerClamp]
  have hu : powerClampUnc pol1 prop ≤ powerClampUnc pol2 prop := by
    unfold powerClampUnc; exact clampNonNeg_mono_hi prop.pUnc _ _ (by omega)
  have hru : min pol1.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol1 prop ≤
             min pol2.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol2 prop := by
    unfold powerClampUnc clampNonNeg P_UNC_HARD_MAX_MW P_TOTAL_HARD_MAX_MW
    by_cases a1 : min 25000 (min pol1.pBudget 140000) ≤ 0 <;>
    by_cases a2 : min 25000 (min pol2.pBudget 140000) ≤ 0 <;>
    by_cases bx : prop.pUnc ≤ 0 <;>
    by_cases c1 : prop.pUnc ≥ min 25000 (min pol1.pBudget 140000) <;>
    by_cases c2 : prop.pUnc ≥ min 25000 (min pol2.pBudget 140000) <;>
    simp [a1, a2, bx, c1, c2] <;> omega
  have hc : powerClampCpu pol1 prop ≤ powerClampCpu pol2 prop := by
    unfold powerClampCpu; exact clampNonNeg_mono_hi prop.pCpu _ _ hru
  have hru1_nn : 0 ≤ min pol1.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol1 prop := by
    have := clampNonNeg_bounds prop.pUnc (min P_UNC_HARD_MAX_MW (min pol1.pBudget P_TOTAL_HARD_MAX_MW))
    unfold powerClampUnc P_UNC_HARD_MAX_MW P_TOTAL_HARD_MAX_MW at *; omega
  have hrc : (min pol1.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol1 prop) - powerClampCpu pol1 prop ≤
             (min pol2.pBudget P_TOTAL_HARD_MAX_MW - powerClampUnc pol2 prop) - powerClampCpu pol2 prop := by
    unfold powerClampCpu
    exact clampNonNeg_rem_mono prop.pCpu _ _ hru hru1_nn
  have hg : powerClampGpu pol1 prop ≤ powerClampGpu pol2 prop := by
    unfold powerClampGpu
    exact clampNonNeg_mono_hi prop.pGpu _ _ (by omega)
  exact ⟨hu, hc, hg⟩

/-- Unconditional Full CBF Budget Monotonicity: for EVERY thermal state and EVERY
    arbitrary proposal (even adversarial `pUnc + pCpu > pBudget`), raising `pBudget`
    monotonically raises (or preserves) every admitted rail `(pUnc, pCpu, pGpu)`. -/
theorem cbf_mono_pBudget_rails
    (st : ThermalState) (pol1 pol2 : WattPolicy) (prop : PowerProposal)
    (hbud : pol1.pBudget ≤ pol2.pBudget)
    (hgb  : pol1.pGpuBudget = pol2.pGpuBudget)
    (hce  : pol1.tCeil = pol2.tCeil)
    (htau : pol1.tau = pol2.tau) :
    let o1 := cbfFilter st pol1 prop
    let o2 := cbfFilter st pol2 prop
    o1.pUnc ≤ o2.pUnc ∧ o1.pCpu ≤ o2.pCpu ∧ o1.pGpu ≤ o2.pGpu := by
  dsimp only
  by_cases h1 : mustFailClosed st pol1 = true
  · have hnn := cbf_nonneg_and_fan_bounds st pol2 prop
    unfold cbfFilter; simp only [h1, ↓reduceIte]
    exact ⟨hnn.2.2.1, hnn.2.1, hnn.1⟩
  · have hp1 := policyValid_of_not_guard st pol1 h1
    have hrawEq : rawHeatBudget st pol1 = rawHeatBudget st pol2 := by
      unfold rawHeatBudget; rw [hce, htau]
    have h2 : ¬ (mustFailClosed st pol2 = true) :=
      not_mustFailClosed_of_ok st pol2 (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by rw [← hrawEq]; exact hp1.2.2.2.2.2.2.2)
    have hok1 := cbf_ok_rails st pol1 prop h1
    have hok2 := cbf_ok_rails st pol2 prop h2
    rw [hok1.1, hok1.2.1, hok1.2.2, hok2.1, hok2.2.1, hok2.2.2]
    have hmEq : maxHeatSafe st pol1 = maxHeatSafe st pol2 := by
      unfold maxHeatSafe rawHeatBudget; rw [hce, htau]
    rw [hmEq]
    have hpm := powerClamp_mono_pBudget pol1 pol2 prop (by omega) hbud hgb
    have hpb2 := powerClamp_bounds pol2 prop (by omega) (by omega)
    have hth2 := thermalClamp_nonneg_and_heat (powerClamp pol2 prop) (maxHeatSafe st pol2)
      hpb2.1 hpb2.2.1 hpb2.2.2.1 (maxHeatSafe_nonneg st pol2)
    by_cases huEq : (powerClamp pol1 prop).pUnc = (powerClamp pol2 prop).pUnc
    · by_cases hcEq : (powerClamp pol1 prop).pCpu = (powerClamp pol2 prop).pCpu
      · exact thermalClamp_mono_gpu _ _ _ _ huEq hcEq hpm.2.2 (Int.le_refl _)
      · have hcpu_sat : (powerClamp pol1 prop).pCpu =
            min pol1.pBudget P_TOTAL_HARD_MAX_MW - (powerClamp pol1 prop).pUnc := by
          dsimp only [powerClamp] at huEq hcEq hpm ⊢
          have hru1_nn : 0 ≤ min pol1.pBudget 140000 - powerClampUnc pol1 prop := by
            have hb1 := clampNonNeg_bounds prop.pUnc (min P_UNC_HARD_MAX_MW (min pol1.pBudget P_TOTAL_HARD_MAX_MW))
            unfold powerClampUnc P_UNC_HARD_MAX_MW P_TOTAL_HARD_MAX_MW at *; omega
          unfold powerClampCpu clampNonNeg P_TOTAL_HARD_MAX_MW at hcEq ⊢
          rw [← huEq] at hcEq
          by_cases a1 : min pol1.pBudget 140000 - powerClampUnc pol1 prop ≤ 0 <;>
          by_cases a2 : min pol2.pBudget 140000 - powerClampUnc pol1 prop ≤ 0 <;>
          by_cases bx : prop.pCpu ≤ 0 <;>
          by_cases c1 : prop.pCpu ≥ min pol1.pBudget 140000 - powerClampUnc pol1 prop <;>
          by_cases c2 : prop.pCpu ≥ min pol2.pBudget 140000 - powerClampUnc pol1 prop <;>
          simp [a1, a2, bx, c1, c2] at hcEq ⊢ <;> omega
        have hg1_zero : (powerClamp pol1 prop).pGpu = 0 := by
          have hpb1 := powerClamp_bounds pol1 prop (by omega) (by omega)
          omega
        have hthu_eq : thermalHeatUnc (powerClamp pol1 prop) (maxHeatSafe st pol2) =
            thermalHeatUnc (powerClamp pol2 prop) (maxHeatSafe st pol2) := by
          unfold thermalHeatUnc; rw [huEq]
        have hthc_le : thermalHeatCpu (powerClamp pol1 prop) (maxHeatSafe st pol2) ≤
            thermalHeatCpu (powerClamp pol2 prop) (maxHeatSafe st pol2) := by
          unfold thermalHeatCpu; rw [hthu_eq]; unfold K_CPU_HEAT; omega
        have htg1_zero : (thermalClamp (powerClamp pol1 prop) (maxHeatSafe st pol2)).pGpu = 0 := by
          have hpb1 := powerClamp_bounds pol1 prop (by omega) (by omega)
          have hth1 := thermalClamp_nonneg_and_heat (powerClamp pol1 prop) (maxHeatSafe st pol2)
            hpb1.1 hpb1.2.1 hpb1.2.2.1 (maxHeatSafe_nonneg st pol2)
          have hle1 := thermalClamp_le_input (powerClamp pol1 prop) (maxHeatSafe st pol2)
          omega
        refine ⟨by unfold thermalClamp; rw [hthu_eq]; exact Int.le_refl _,
                by unfold thermalClamp; exact Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hthc_le,
                by omega⟩
    · have hunc_sat : (powerClamp pol1 prop).pUnc = min pol1.pBudget P_TOTAL_HARD_MAX_MW := by
        dsimp only [powerClamp] at huEq ⊢
        unfold powerClampUnc clampNonNeg P_UNC_HARD_MAX_MW P_TOTAL_HARD_MAX_MW at huEq ⊢
        by_cases a1 : min 25000 (min pol1.pBudget 140000) ≤ 0 <;>
        by_cases a2 : min 25000 (min pol2.pBudget 140000) ≤ 0 <;>
        by_cases bx : prop.pUnc ≤ 0 <;>
        by_cases c1 : prop.pUnc ≥ min 25000 (min pol1.pBudget 140000) <;>
        by_cases c2 : prop.pUnc ≥ min 25000 (min pol2.pBudget 140000) <;>
        simp [a1, a2, bx, c1, c2] at huEq ⊢ <;> omega
      have hpb1 := powerClamp_bounds pol1 prop (by omega) (by omega)
      have hc1_zero : (powerClamp pol1 prop).pCpu = 0 := by omega
      have hg1_zero : (powerClamp pol1 prop).pGpu = 0 := by omega
      have hth1 := thermalClamp_nonneg_and_heat (powerClamp pol1 prop) (maxHeatSafe st pol2)
        hpb1.1 hpb1.2.1 hpb1.2.2.1 (maxHeatSafe_nonneg st pol2)
      have hle1 := thermalClamp_le_input (powerClamp pol1 prop) (maxHeatSafe st pol2)
      have hthu_le : thermalHeatUnc (powerClamp pol1 prop) (maxHeatSafe st pol2) ≤
          thermalHeatUnc (powerClamp pol2 prop) (maxHeatSafe st pol2) := by
        unfold thermalHeatUnc K_CPU_HEAT; omega
      refine ⟨by unfold thermalClamp; exact Int.ediv_le_ediv (by decide : (0 : Int) < K_CPU_HEAT) hthu_le,
              by omega, by omega⟩

/-- Policy GPU-budget monotonicity: raising `pGpuBudget` never decreases filtered `pGpu`. -/
theorem cbf_mono_pGpuBudget
    (st : ThermalState) (pol1 pol2 : WattPolicy) (prop : PowerProposal)
    (hbud : pol1.pBudget = pol2.pBudget)
    (hgb  : pol1.pGpuBudget ≤ pol2.pGpuBudget)
    (hce  : pol1.tCeil = pol2.tCeil)
    (htau : pol1.tau = pol2.tau) :
    (cbfFilter st pol1 prop).pGpu ≤ (cbfFilter st pol2 prop).pGpu := by
  by_cases h1 : mustFailClosed st pol1 = true
  · have hnn := cbf_nonneg_and_fan_bounds st pol2 prop
    unfold cbfFilter; simp only [h1, ↓reduceIte]; exact hnn.1
  · have hp1 := policyValid_of_not_guard st pol1 h1
    have hrawEq : rawHeatBudget st pol1 = rawHeatBudget st pol2 := by
      unfold rawHeatBudget; rw [hce, htau]
    have h2 : ¬ (mustFailClosed st pol2 = true) :=
      not_mustFailClosed_of_ok st pol2 (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by rw [← hrawEq]; exact hp1.2.2.2.2.2.2.2)
    have hok1 := cbf_ok_rails st pol1 prop h1
    have hok2 := cbf_ok_rails st pol2 prop h2
    rw [hok1.1, hok2.1]
    have hmEq : maxHeatSafe st pol1 = maxHeatSafe st pol2 := by
      unfold maxHeatSafe rawHeatBudget; rw [hce, htau]
    have hu : (powerClamp pol1 prop).pUnc = (powerClamp pol2 prop).pUnc := by
      unfold powerClamp powerClampUnc; rw [hbud]
    have hc : (powerClamp pol1 prop).pCpu = (powerClamp pol2 prop).pCpu := by
      unfold powerClamp powerClampCpu powerClampUnc; rw [hbud]
    have hg : (powerClamp pol1 prop).pGpu ≤ (powerClamp pol2 prop).pGpu := by
      unfold powerClamp powerClampGpu powerClampCpu powerClampUnc; rw [hbud]
      exact clampNonNeg_mono_hi prop.pGpu _ _ (by omega)
    exact (thermalClamp_mono_gpu _ _ _ _ hu hc hg (by rw [hmEq]; exact Int.le_refl _)).2.2

/-- Monotonicity in GPU power request: raising `prop.pGpu` never decreases filtered `pGpu`. -/
theorem cbf_mono_gpu_req
    (st : ThermalState) (pol : WattPolicy) (p1 p2 : PowerProposal)
    (hg : p1.pGpu ≤ p2.pGpu) (hc : p1.pCpu = p2.pCpu) (hu : p1.pUnc = p2.pUnc) :
    (cbfFilter st pol p1).pGpu ≤ (cbfFilter st pol p2).pGpu := by
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h]
  · have hok1 := cbf_ok_rails st pol p1 h
    have hok2 := cbf_ok_rails st pol p2 h
    rw [hok1.1, hok2.1]
    have hpu : (powerClamp pol p1).pUnc = (powerClamp pol p2).pUnc := by
      unfold powerClamp powerClampUnc; rw [hu]
    have hpc : (powerClamp pol p1).pCpu = (powerClamp pol p2).pCpu := by
      unfold powerClamp powerClampCpu powerClampUnc; rw [hu, hc]
    have hpg : (powerClamp pol p1).pGpu ≤ (powerClamp pol p2).pGpu := by
      unfold powerClamp powerClampGpu powerClampCpu powerClampUnc; rw [hu, hc]
      exact clampNonNeg_mono_x p1.pGpu p2.pGpu _ hg
    exact (thermalClamp_mono_gpu _ _ _ _ hpu hpc hpg (Int.le_refl _)).2.2

/-- Monotonicity in die ceiling `tCeil`: raising `tCeil` (up to `T_CEIL_ABS_MAX_MC`)
    never decreases admitted power on any rail. -/
theorem cbf_mono_tCeil
    (st : ThermalState) (pol1 pol2 : WattPolicy) (prop : PowerProposal)
    (hbud : pol1.pBudget = pol2.pBudget) (hgb : pol1.pGpuBudget = pol2.pGpuBudget)
    (htau : pol1.tau = pol2.tau)
    (hce  : pol1.tCeil ≤ pol2.tCeil) (hmax : pol2.tCeil ≤ T_CEIL_ABS_MAX_MC) :
    let o1 := cbfFilter st pol1 prop
    let o2 := cbfFilter st pol2 prop
    o1.pUnc ≤ o2.pUnc ∧ o1.pCpu ≤ o2.pCpu ∧ o1.pGpu ≤ o2.pGpu := by
  dsimp only
  by_cases h1 : mustFailClosed st pol1 = true
  · have hnn := cbf_nonneg_and_fan_bounds st pol2 prop
    unfold cbfFilter; simp only [h1, ↓reduceIte]
    exact ⟨hnn.2.2.1, hnn.2.1, hnn.1⟩
  · have hp1 := policyValid_of_not_guard st pol1 h1
    have hraw_le : rawHeatBudget st pol1 ≤ rawHeatBudget st pol2 := by
      unfold rawHeatBudget
      have nt1 : ¬ (pol1.tau < 0) := by omega
      have nt2 : ¬ (pol2.tau < 0) := by omega
      simp only [nt1, nt2, ↓reduceIte]
      rw [htau]
      have hd := Int.ediv_le_ediv (by omega : 0 < pol2.tau + 1) (by omega : pol1.tCeil - st.tDie ≤ pol2.tCeil - st.tDie)
      unfold THERMAL_SCALE; omega
    have h2 : ¬ (mustFailClosed st pol2 = true) :=
      not_mustFailClosed_of_ok st pol2 (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by omega)
    have hok1 := cbf_ok_rails st pol1 prop h1
    have hok2 := cbf_ok_rails st pol2 prop h2
    rw [hok1.1, hok1.2.1, hok1.2.2, hok2.1, hok2.2.1, hok2.2.2]
    have hpcEq : powerClamp pol1 prop = powerClamp pol2 prop := by
      unfold powerClamp powerClampGpu powerClampCpu powerClampUnc; rw [hbud, hgb]
    have hm : maxHeatSafe st pol1 ≤ maxHeatSafe st pol2 := by
      unfold maxHeatSafe
      have g1 : ¬ (st.tDie ≥ pol1.tCeil ∨ st.tSink ≥ pol1.tCeil ∨ pol1.tau < 0) := by omega
      have g2 : ¬ (st.tDie ≥ pol2.tCeil ∨ st.tSink ≥ pol2.tCeil ∨ pol2.tau < 0) := by omega
      simp only [g1, g2, ↓reduceIte]; omega
    rw [hpcEq]
    exact thermalClamp_mono_heat _ _ _ hm

/-- Monotonicity in heatsink temperature `tSink`: a hotter heatsink monotonically
    reduces (or preserves) admitted power on every rail. -/
theorem cbf_mono_tSink
    (st1 st2 : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (hdie : st1.tDie = st2.tDie) (hsink : st1.tSink ≤ st2.tSink) :
    let o1 := cbfFilter st1 pol prop
    let o2 := cbfFilter st2 pol prop
    o2.pUnc ≤ o1.pUnc ∧ o2.pCpu ≤ o1.pCpu ∧ o2.pGpu ≤ o1.pGpu := by
  dsimp only
  by_cases h2 : mustFailClosed st2 pol = true
  · have hnn := cbf_nonneg_and_fan_bounds st1 pol prop
    unfold cbfFilter; simp only [h2, ↓reduceIte]
    exact ⟨hnn.2.2.1, hnn.2.1, hnn.1⟩
  · have hp2 := policyValid_of_not_guard st2 pol h2
    have hraw_le : rawHeatBudget st2 pol ≤ rawHeatBudget st1 pol := by
      unfold rawHeatBudget dieCoolDs K_DS_COND
      rw [hdie]
      split <;> omega
    have h1 : ¬ (mustFailClosed st1 pol = true) :=
      not_mustFailClosed_of_ok st1 pol (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by omega)
    have hok1 := cbf_ok_rails st1 pol prop h1
    have hok2 := cbf_ok_rails st2 pol prop h2
    rw [hok1.1, hok1.2.1, hok1.2.2, hok2.1, hok2.2.1, hok2.2.2]
    have hm : maxHeatSafe st2 pol ≤ maxHeatSafe st1 pol := by
      unfold maxHeatSafe
      have g1 : ¬ (st1.tDie ≥ pol.tCeil ∨ st1.tSink ≥ pol.tCeil ∨ pol.tau < 0) := by omega
      have g2 : ¬ (st2.tDie ≥ pol.tCeil ∨ st2.tSink ≥ pol.tCeil ∨ pol.tau < 0) := by omega
      simp only [g1, g2, ↓reduceIte]; omega
    exact thermalClamp_mono_heat _ _ _ hm

/-- Monotonicity in lookahead `tau`: a larger safety horizon `tau` monotonically
    reduces (or preserves) admitted power on every rail. -/
theorem cbf_mono_tau
    (st : ThermalState) (pol1 pol2 : WattPolicy) (prop : PowerProposal)
    (hbud : pol1.pBudget = pol2.pBudget) (hgb : pol1.pGpuBudget = pol2.pGpuBudget)
    (hce  : pol1.tCeil = pol2.tCeil)
    (htau0 : 0 ≤ pol1.tau) (htau : pol1.tau ≤ pol2.tau) :
    let o1 := cbfFilter st pol1 prop
    let o2 := cbfFilter st pol2 prop
    o2.pUnc ≤ o1.pUnc ∧ o2.pCpu ≤ o1.pCpu ∧ o2.pGpu ≤ o1.pGpu := by
  dsimp only
  by_cases h2 : mustFailClosed st pol2 = true
  · have hnn := cbf_nonneg_and_fan_bounds st pol1 prop
    unfold cbfFilter; simp only [h2, ↓reduceIte]
    exact ⟨hnn.2.2.1, hnn.2.1, hnn.1⟩
  · have hp2 := policyValid_of_not_guard st pol2 h2
    have hraw_le : rawHeatBudget st pol2 ≤ rawHeatBudget st pol1 := by
      unfold rawHeatBudget
      have nt1 : ¬ (pol1.tau < 0) := by omega
      have nt2 : ¬ (pol2.tau < 0) := by omega
      simp only [nt1, nt2, ↓reduceIte]
      rw [hce]
      have hpos : 0 ≤ pol2.tCeil - st.tDie := by omega
      have hb2 := mul_ediv_bounds (pol2.tCeil - st.tDie) (pol2.tau + 1) (by omega) hpos
      have hmul : (pol1.tau + 1) * ((pol2.tCeil - st.tDie) / (pol2.tau + 1)) ≤
          (pol2.tau + 1) * ((pol2.tCeil - st.tDie) / (pol2.tau + 1)) :=
        Int.mul_le_mul_of_nonneg_right (by omega) hb2.1
      have hcomm : (pol1.tau + 1) * ((pol2.tCeil - st.tDie) / (pol2.tau + 1)) =
          ((pol2.tCeil - st.tDie) / (pol2.tau + 1)) * (pol1.tau + 1) := Int.mul_comm _ _
      have hd : (pol2.tCeil - st.tDie) / (pol2.tau + 1) ≤
          (pol2.tCeil - st.tDie) / (pol1.tau + 1) :=
        Int.le_ediv_of_mul_le (by omega) (by omega)
      unfold THERMAL_SCALE; omega
    have h1 : ¬ (mustFailClosed st pol1 = true) :=
      not_mustFailClosed_of_ok st pol1 (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by omega)
    have hok1 := cbf_ok_rails st pol1 prop h1
    have hok2 := cbf_ok_rails st pol2 prop h2
    rw [hok1.1, hok1.2.1, hok1.2.2, hok2.1, hok2.2.1, hok2.2.2]
    have hpcEq : powerClamp pol1 prop = powerClamp pol2 prop := by
      unfold powerClamp powerClampGpu powerClampCpu powerClampUnc; rw [hbud, hgb]
    have hm : maxHeatSafe st pol2 ≤ maxHeatSafe st pol1 := by
      unfold maxHeatSafe
      have g1 : ¬ (st.tDie ≥ pol1.tCeil ∨ st.tSink ≥ pol1.tCeil ∨ pol1.tau < 0) := by omega
      have g2 : ¬ (st.tDie ≥ pol2.tCeil ∨ st.tSink ≥ pol2.tCeil ∨ pol2.tau < 0) := by omega
      simp only [g1, g2, ↓reduceIte]; omega
    rw [hpcEq]
    exact thermalClamp_mono_heat _ _ _ hm

/-- Whole-unit warm-up monotonicity: as `T_die` and `T_sink` rise together (`T_die - T_sink`
    fixed), admitted power on every rail is monotonically non-increasing. -/
theorem cbf_mono_tDie_whole_unit
    (st1 st2 : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (htau : 0 ≤ pol.tau)
    (hdie : st1.tDie ≤ st2.tDie)
    (hdelta : st1.tDie - st1.tSink = st2.tDie - st2.tSink) :
    let o1 := cbfFilter st1 pol prop
    let o2 := cbfFilter st2 pol prop
    o2.pUnc ≤ o1.pUnc ∧ o2.pCpu ≤ o1.pCpu ∧ o2.pGpu ≤ o1.pGpu := by
  dsimp only
  by_cases h2 : mustFailClosed st2 pol = true
  · have hnn := cbf_nonneg_and_fan_bounds st1 pol prop
    unfold cbfFilter; simp only [h2, ↓reduceIte]
    exact ⟨hnn.2.2.1, hnn.2.1, hnn.1⟩
  · have hp2 := policyValid_of_not_guard st2 pol h2
    have hraw_le : rawHeatBudget st2 pol ≤ rawHeatBudget st1 pol := by
      unfold rawHeatBudget dieCoolDs
      have nt : ¬ (pol.tau < 0) := by omega
      simp only [nt, ↓reduceIte]
      have hd := Int.ediv_le_ediv (by omega : 0 < pol.tau + 1) (by omega : pol.tCeil - st2.tDie ≤ pol.tCeil - st1.tDie)
      rw [hdelta]
      unfold THERMAL_SCALE; omega
    have h1 : ¬ (mustFailClosed st1 pol = true) :=
      not_mustFailClosed_of_ok st1 pol (by omega) (by omega) (by omega) (by omega)
        (by omega) (by omega) (by omega) (by omega)
    have hok1 := cbf_ok_rails st1 pol prop h1
    have hok2 := cbf_ok_rails st2 pol prop h2
    rw [hok1.1, hok1.2.1, hok1.2.2, hok2.1, hok2.2.1, hok2.2.2]
    have hm : maxHeatSafe st2 pol ≤ maxHeatSafe st1 pol := by
      unfold maxHeatSafe
      have g1 : ¬ (st1.tDie ≥ pol.tCeil ∨ st1.tSink ≥ pol.tCeil ∨ pol.tau < 0) := by omega
      have g2 : ¬ (st2.tDie ≥ pol.tCeil ∨ st2.tSink ≥ pol.tCeil ∨ pol.tau < 0) := by omega
      simp only [g1, g2, ↓reduceIte]; omega
    exact thermalClamp_mono_heat _ _ _ hm

/-- Anticipatory Pre-Cooling Theorem: raising fan duty (`fan1 <= fan2`) monotonically
    lowers next-step Node 2 heatsink temperature `T_sink'`, which by `cbf_mono_tSink`
    strictly increases or preserves sustainable GPU burst power on subsequent ticks. -/
theorem precool_fan_mono_sink
    (st : ThermalState) (pGpu pCpu pUnc fan1 fan2 : Int)
    (hamb : st.tAmb ≤ st.tSink) (hfan : fan1 ≤ fan2) :
    (stepThermal st pGpu pCpu pUnc fan2).tSink ≤
    (stepThermal st pGpu pCpu pUnc fan1).tSink := by
  unfold stepThermal nextSinkDelta
  dsimp only
  have hcool : (K_FAN_BASE * 100 + K_FAN_SLOPE * fan1) * (st.tSink - st.tAmb) ≤
      (K_FAN_BASE * 100 + K_FAN_SLOPE * fan2) * (st.tSink - st.tAmb) := by
    apply Int.mul_le_mul_of_nonneg_right
    · unfold K_FAN_BASE K_FAN_SLOPE; omega
    · omega
  have hmono := ceilDiv_mono _ _ SINK_SCALE (by decide) (by omega :
    K_SINK_IN * 100 * (st.tDie - st.tSink) -
      (K_FAN_BASE * 100 + K_FAN_SLOPE * fan2) * (st.tSink - st.tAmb) ≤
    K_SINK_IN * 100 * (st.tDie - st.tSink) -
      (K_FAN_BASE * 100 + K_FAN_SLOPE * fan1) * (st.tSink - st.tAmb))
  omega

private theorem powerClamp_of_safe_rails (pol : WattPolicy) (r : RailTriple) (fan : Int)
    (hu0 : 0 ≤ r.pUnc) (hc0 : 0 ≤ r.pCpu) (hg0 : 0 ≤ r.pGpu)
    (hunc : r.pUnc ≤ P_UNC_HARD_MAX_MW)
    (hgpu : r.pGpu ≤ min P_GPU_HARD_MAX_MW pol.pGpuBudget)
    (htot : r.pGpu + r.pCpu + r.pUnc ≤ min pol.pBudget P_TOTAL_HARD_MAX_MW) :
    powerClamp pol { pGpu := r.pGpu, pCpu := r.pCpu, pUnc := r.pUnc, fanPct := fan } = r := by
  have h1 : powerClampUnc pol { pGpu := r.pGpu, pCpu := r.pCpu, pUnc := r.pUnc, fanPct := fan } = r.pUnc := by
    unfold powerClampUnc; dsimp only; exact clampNonNeg_eq_self _ _ hu0 (by omega)
  have h2 : powerClampCpu pol { pGpu := r.pGpu, pCpu := r.pCpu, pUnc := r.pUnc, fanPct := fan } = r.pCpu := by
    unfold powerClampCpu; rw [h1]; dsimp only; exact clampNonNeg_eq_self _ _ hc0 (by omega)
  have h3 : powerClampGpu pol { pGpu := r.pGpu, pCpu := r.pCpu, pUnc := r.pUnc, fanPct := fan } = r.pGpu := by
    unfold powerClampGpu; rw [h1, h2]; dsimp only; exact clampNonNeg_eq_self _ _ hg0 (by omega)
  cases r
  unfold powerClamp
  simp only [h1, h2, h3]

private theorem thermalClamp_of_safe_heat (r : RailTriple) (maxHeat : Int)
    (hu0 : 0 ≤ r.pUnc) (hc0 : 0 ≤ r.pCpu) (hg0 : 0 ≤ r.pGpu)
    (hheat : dieHeat r.pGpu r.pCpu r.pUnc ≤ maxHeat) :
    thermalClamp r maxHeat = r := by
  unfold dieHeat at hheat
  have hmu : thermalHeatUnc r maxHeat = K_CPU_HEAT * r.pUnc := by
    unfold thermalHeatUnc K_CPU_HEAT K_GPU_HEAT at *; omega
  have hmc : thermalHeatCpu r maxHeat = K_CPU_HEAT * r.pCpu := by
    unfold thermalHeatCpu; rw [hmu]; unfold K_CPU_HEAT K_GPU_HEAT at *; omega
  have hmg : thermalHeatGpu r maxHeat = K_GPU_HEAT * r.pGpu := by
    unfold thermalHeatGpu; rw [hmu, hmc]; unfold K_CPU_HEAT K_GPU_HEAT at *; omega
  have d1 : (K_CPU_HEAT * r.pUnc) / K_CPU_HEAT = r.pUnc := by
    rw [Int.mul_comm]; exact Int.mul_ediv_cancel r.pUnc (by decide)
  have d2 : (K_CPU_HEAT * r.pCpu) / K_CPU_HEAT = r.pCpu := by
    rw [Int.mul_comm]; exact Int.mul_ediv_cancel r.pCpu (by decide)
  have d3 : (K_GPU_HEAT * r.pGpu) / K_GPU_HEAT = r.pGpu := by
    rw [Int.mul_comm]; exact Int.mul_ediv_cancel r.pGpu (by decide)
  cases r
  unfold thermalClamp
  simp only [hmu, hmc, hmg, d1, d2, d3]

private theorem cbfFilter_admit_eq (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal)
    (h : ¬ (mustFailClosed st pol = true)) :
    cbfFilter st pol prop =
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
        clamped    := clamped } := by
  unfold cbfFilter
  rw [ite_eq_right h]

/-- Full idempotence of the CBF shield: filtering an already-filtered command leaves
    `(pGpu, pCpu, pUnc, fanPct, failClosed)` unchanged, and clears `clamped` whenever
    the command was admitted (`failClosed = false`). -/
theorem cbf_idempotent
    (st : ThermalState) (pol : WattPolicy) (prop : PowerProposal) :
    let o1 := cbfFilter st pol prop
    let o2 := cbfFilter st pol { pGpu := o1.pGpu, pCpu := o1.pCpu, pUnc := o1.pUnc, fanPct := o1.fanPct }
    o2.pGpu = o1.pGpu ∧ o2.pCpu = o1.pCpu ∧ o2.pUnc = o1.pUnc ∧
    o2.fanPct = o1.fanPct ∧ o2.failClosed = o1.failClosed ∧
    (o1.failClosed = false → o2.clamped = false) := by
  dsimp only
  by_cases h : mustFailClosed st pol = true
  · unfold cbfFilter; simp [h]
  · have hp := policyValid_of_not_guard st pol h
    have pb := powerClamp_bounds pol prop (by omega) (by omega)
    have tc := thermalClamp_le_input (powerClamp pol prop) (maxHeatSafe st pol)
    have th := thermalClamp_nonneg_and_heat (powerClamp pol prop) (maxHeatSafe st pol)
      pb.1 pb.2.1 pb.2.2.1 (maxHeatSafe_nonneg st pol)
    have hok1 := cbf_ok_rails st pol prop h
    have hpc : powerClamp pol
        { pGpu := (cbfFilter st pol prop).pGpu
          pCpu := (cbfFilter st pol prop).pCpu
          pUnc := (cbfFilter st pol prop).pUnc
          fanPct := (cbfFilter st pol prop).fanPct } =
        thermalClamp (powerClamp pol prop) (maxHeatSafe st pol) := by
      rw [hok1.1, hok1.2.1, hok1.2.2]
      exact powerClamp_of_safe_rails pol (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol))
        (cbfFilter st pol prop).fanPct th.1 th.2.1 th.2.2.1
        (by omega) (by omega) (by omega)
    have htc : thermalClamp (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)) (maxHeatSafe st pol) =
        thermalClamp (powerClamp pol prop) (maxHeatSafe st pol) :=
      thermalClamp_of_safe_heat _ _ th.1 th.2.1 th.2.2.1 th.2.2.2
    have hfan_mono : safeFanFloor (pol.tCeil - st.tDie) false ≤
        safeFanFloor (pol.tCeil - st.tDie)
          (decide ((thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc < (powerClamp pol prop).pUnc ∨
                   (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu < (powerClamp pol prop).pCpu ∨
                   (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu < (powerClamp pol prop).pGpu)) :=
      safeFanFloor_mono_tc _ _
    have hfan_b := safeFanFloor_bounds (pol.tCeil - st.tDie)
      (decide ((thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc < (powerClamp pol prop).pUnc ∨
               (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu < (powerClamp pol prop).pCpu ∨
               (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu < (powerClamp pol prop).pGpu))
    have ho1_fc : (cbfFilter st pol prop).failClosed = false := by
      rw [cbfFilter_admit_eq st pol prop h]
    have ho1_fan : (cbfFilter st pol prop).fanPct =
        min FAN_MAX_PCT (max (safeFanFloor (pol.tCeil - st.tDie)
          (decide ((thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc < (powerClamp pol prop).pUnc ∨
                   (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu < (powerClamp pol prop).pCpu ∨
                   (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu < (powerClamp pol prop).pGpu)))
          (max FAN_MIN_PCT prop.fanPct)) := by
      rw [cbfFilter_admit_eq st pol prop h]
    have ho2_def := cbfFilter_admit_eq st pol
      { pGpu := (cbfFilter st pol prop).pGpu
        pCpu := (cbfFilter st pol prop).pCpu
        pUnc := (cbfFilter st pol prop).pUnc
        fanPct := (cbfFilter st pol prop).fanPct } h
    dsimp only at ho2_def
    rw [hpc, htc] at ho2_def
    have hlt_false :
        decide ((thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc <
                  (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pUnc ∨
                (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu <
                  (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pCpu ∨
                (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu <
                  (thermalClamp (powerClamp pol prop) (maxHeatSafe st pol)).pGpu) = false := by
      simp
    rw [hlt_false] at ho2_def
    have hfan_eq :
        min FAN_MAX_PCT (max (safeFanFloor (pol.tCeil - st.tDie) false)
          (max FAN_MIN_PCT (cbfFilter st pol prop).fanPct)) =
        (cbfFilter st pol prop).fanPct := by
      rw [ho1_fan]
      unfold FAN_MIN_PCT FAN_MAX_PCT at *
      omega
    rw [ho2_def]
    dsimp only
    refine ⟨hok1.1.symm, hok1.2.1.symm, hok1.2.2.symm, hfan_eq, ho1_fc.symm, ?_⟩
    intro _
    rw [hok1.1, hok1.2.1, hok1.2.2, hfan_eq]
    simp

-- =========================================================================
-- Section 5: Non-Vacuity Negative Controls (Concrete Witness Theorems)
-- =========================================================================

/-- Negative Control 1 (Trap-14 90 W Spike):
    On a warm GB10 training state (`T_die = 76.0 C`, `T_sink = 66.0 C`, `T_ceil = 78.0 C`,
    `tau = 2 s`), an UNCLAMPED 90 W GPU spike violates BOTH the 80 W Trap-14 ceiling
    (`90000 > 80000`) AND the thermal CBF barrier (`h = -700 < 0`), whereas `cbfFilter`
    clamps GPU to `62,640 mW <= 80,000 mW`, keeps `h = +668 >= 0`, `T_die' = 76.666 C <= 78.0 C`,
    and forces `fanPct = 100%`. -/
theorem neg_control_trap14_90w :
    let st   : ThermalState  := { tDie := 76000, tSink := 66000, tAmb := 25000 }
    let pol  : WattPolicy    := { pBudget := 110000, pGpuBudget := 80000, tCeil := 78000, tau := 2 }
    let prop : PowerProposal := { pGpu := 90000, pCpu := 15000, pUnc := 5000, fanPct := 40 }
    let dT_raw := nextDieDelta st prop.pGpu prop.pCpu prop.pUnc
    let out    := cbfFilter st pol prop
    let dT_cbf := nextDieDelta st out.pGpu out.pCpu out.pUnc
    prop.pGpu > P_GPU_HARD_MAX_MW ∧
    barrierH pol.tCeil st.tDie pol.tau dT_raw < 0 ∧
    out.pGpu ≤ P_GPU_HARD_MAX_MW ∧
    out.pGpu = 62640 ∧
    barrierH pol.tCeil st.tDie pol.tau dT_cbf ≥ 0 ∧
    (stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct).tDie ≤ pol.tCeil ∧
    out.fanPct = FAN_MAX_PCT ∧
    out.clamped = true := by
  decide

/-- Negative Control 2 (Over-Budget Total Power):
    An unclamped 120 W total request (`75 W GPU + 35 W CPU + 10 W Unc`) exceeds a 100 W
    whole-unit budget, while `cbfFilter` enforces `pGpu + pCpu + pUnc <= 100,000 mW`. -/
theorem neg_control_over_budget :
    let st   : ThermalState  := { tDie := 44000, tSink := 40000, tAmb := 25000 }
    let pol  : WattPolicy    := { pBudget := 100000, pGpuBudget := 80000, tCeil := 85000, tau := 2 }
    let prop : PowerProposal := { pGpu := 75000, pCpu := 35000, pUnc := 10000, fanPct := 40 }
    let out  := cbfFilter st pol prop
    prop.pGpu + prop.pCpu + prop.pUnc > pol.pBudget ∧
    out.pGpu + out.pCpu + out.pUnc ≤ pol.pBudget ∧
    out.pGpu ≤ P_GPU_HARD_MAX_MW ∧
    out.clamped = true := by
  decide

/-- Negative Control 3 (Unclamped Hot-Die Thermal Runaway):
    At `T_die = 77.5 C`, `T_sink = 68.0 C`, `T_ceil = 78.0 C`, an unclamped 70 W GPU burst
    pushes `T_die'` past `78.0 C` (`78.375 C > 78.0 C`) and violates `h >= 0` (`h = -1250 < 0`),
    whereas `cbfFilter` keeps `T_die' <= 78.0 C`, `h >= 0`, and engages `fanPct = 100%`. -/
theorem neg_control_hot_die_spike :
    let st   : ThermalState  := { tDie := 77500, tSink := 68000, tAmb := 25000 }
    let pol  : WattPolicy    := { pBudget := 100000, pGpuBudget := 80000, tCeil := 78000, tau := 2 }
    let prop : PowerProposal := { pGpu := 70000, pCpu := 10000, pUnc := 5000, fanPct := 50 }
    let st_raw := stepThermal st prop.pGpu prop.pCpu prop.pUnc prop.fanPct
    let dT_raw := nextDieDelta st prop.pGpu prop.pCpu prop.pUnc
    let out    := cbfFilter st pol prop
    let st_cbf := stepThermal st out.pGpu out.pCpu out.pUnc out.fanPct
    let dT_cbf := nextDieDelta st out.pGpu out.pCpu out.pUnc
    st_raw.tDie > pol.tCeil ∧
    barrierH pol.tCeil st.tDie pol.tau dT_raw < 0 ∧
    st_cbf.tDie ≤ pol.tCeil ∧
    barrierH pol.tCeil st.tDie pol.tau dT_cbf ≥ 0 ∧
    out.fanPct = FAN_MAX_PCT := by
  decide

/-- Negative Control 4 (Invalid Negative Budget Fail-Closed):
    A negative budget `-10,000 mW` fails closed to zero power on all rails and 100% fan. -/
theorem neg_control_invalid_budget_fail_closed :
    let st   : ThermalState  := { tDie := 44000, tSink := 40000, tAmb := 25000 }
    let pol  : WattPolicy    := { pBudget := -10000, pGpuBudget := 80000, tCeil := 85000, tau := 2 }
    let prop : PowerProposal := { pGpu := 50000, pCpu := 15000, pUnc := 5000, fanPct := 30 }
    let out  := cbfFilter st pol prop
    out.pGpu = 0 ∧ out.pCpu = 0 ∧ out.pUnc = 0 ∧
    out.fanPct = FAN_MAX_PCT ∧ out.failClosed = true := by
  decide

/-- Negative Control 5 (Reverse-Conduction & Overheated-Heatsink Fail-Closed):
    (a) Even inside `[tAmb, tCeil]` (`T_die = 77.0 C`, `T_sink = 77.9 C < 78.0 C`, `tau = 20 s`),
        reverse conduction at 0 W yields `dT = +90 mC/s` and `h = -800 < 0` (infeasible barrier);
        `cbfFilter` MUST fail closed (`0 W`, `fanPct = 100%`, `failClosed = true`).
    (b) On an overheated heatsink (`T_die = 48.7 C`, `T_sink = 150.0 C >= 85.0 C`), `cbfFilter`
        MUST fail closed rather than admitting power into a breached vapor chamber. -/
theorem neg_control_hot_sink_infeasible :
    let st1  : ThermalState  := { tDie := 77000, tSink := 77900, tAmb := 25000 }
    let pol1 : WattPolicy    := { pBudget := 100000, pGpuBudget := 80000, tCeil := 78000, tau := 20 }
    let pr1  : PowerProposal := { pGpu := 0, pCpu := 0, pUnc := 0, fanPct := 30 }
    let dT1  := nextDieDelta st1 0 0 0
    let o1   := cbfFilter st1 pol1 pr1
    let st2  : ThermalState  := { tDie := 48700, tSink := 150000, tAmb := 25000 }
    let pol2 : WattPolicy    := { pBudget := 100000, pGpuBudget := 80000, tCeil := 85000, tau := 2 }
    let pr2  : PowerProposal := { pGpu := 75000, pCpu := 17000, pUnc := 8000, fanPct := 60 }
    let o2   := cbfFilter st2 pol2 pr2
    barrierH pol1.tCeil st1.tDie pol1.tau dT1 < 0 ∧
    o1.pGpu = 0 ∧ o1.pCpu = 0 ∧ o1.pUnc = 0 ∧ o1.fanPct = FAN_MAX_PCT ∧ o1.failClosed = true ∧
    st2.tSink ≥ pol2.tCeil ∧
    o2.pGpu = 0 ∧ o2.pCpu = 0 ∧ o2.pUnc = 0 ∧ o2.fanPct = FAN_MAX_PCT ∧ o2.failClosed = true := by
  decide

#print axioms cbf_gpu_hard_cap
#print axioms cbf_gpu_budget_cap
#print axioms cbf_total_budget
#print axioms cbf_nonneg_and_fan_bounds
#print axioms cbf_never_amplifies
#print axioms cbf_fail_closed_overtemp
#print axioms cbf_fail_closed_sink_overtemp
#print axioms cbf_fail_closed_infeasible_barrier
#print axioms cbf_fail_closed_bad_budget
#print axioms cbf_fail_closed_bad_ceil
#print axioms cbf_fail_closed_bad_tau
#print axioms cbf_die_heat_le_maxHeat
#print axioms cbf_thermal_barrier_preserved
#print axioms cbf_thermal_barrier_normal_regime
#print axioms cbf_admitted_barrier_safe
#print axioms cbf_step_box_safe
#print axioms cbf_multistep_temp_safe
#print axioms powerClamp_mono_pBudget
#print axioms cbf_mono_pBudget_rails
#print axioms cbf_mono_pGpuBudget
#print axioms cbf_mono_gpu_req
#print axioms cbf_mono_tCeil
#print axioms cbf_mono_tSink
#print axioms cbf_mono_tau
#print axioms cbf_mono_tDie_whole_unit
#print axioms precool_fan_mono_sink
#print axioms cbf_idempotent
#print axioms neg_control_trap14_90w
#print axioms neg_control_over_budget
#print axioms neg_control_hot_die_spike
#print axioms neg_control_invalid_budget_fail_closed
#print axioms neg_control_hot_sink_infeasible

end WattCBF
