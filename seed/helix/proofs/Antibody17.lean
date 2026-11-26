/-
  SPDX-License-Identifier: Apache-2.0
  seed/helix/proofs/Antibody17.lean

  Permanent Lean 4 Proof of Antibody #17 — Closing the Live `helix_jit.om` Genome `G2`
  SM121 Scheduling Soundness Hole (All-Consumer RAW Non-Shadowing, Deep-Pipe Tensor Core
  Latency Floor, Anchor-Segment & SEL Predicate Integrity, Multi-Barrier `rbar` Soundness,
  and Binary-Search Delta-Shrinker Completeness).

  Model-to-System Link (verified against live extracted Qwen 3.6 35B kernels on Spark):
    In `seed/helix/helix_jit.om` (`hxCheckRawOne`, lines 530-568) and `seed/helix/monk_check.om`
    (`mkCheckRawOne`, lines 611-648), fixed-latency RAW verification scans consumers `v = u+1..u+15`
    in REFERENCE program order and returns IMMEDIATELY on the FIRST consumer `v1` (`if hxHasRaw u v:
    ret hxRawSpanOk u v false flr`).
    Under Genome `G2` (`hxDoSwapsPass` + `hxCompactStalls` + `hxAsceticPace`), whenever a producer `u`
    has two independent consumers `v1 < v2` reading the same GPR (e.g. `qSwiglu9Fast` in
    `om/gpu/q36/emit_fast.om` lines 1901-1903: `pc 8: IMAD R20`, `pc 9: SHF.R R21, R20, 9`,
    `pc 10: LOP3 R22, R20, 511`), `G2` legally swaps `(v1, v2)` so `inv[v2] < inv[v1]`.
    `hxCheckRawOne(u)` then sums candidate stalls over `[inv[u], inv[v1])` — which INCLUDES `v2`'s
    stall (6 cycles) — letting `hxCompactStalls` shave `u`'s stall from `6 -> 1` cycle!
    Both `hxMonkVerify` and `hxShaveSafe` return PASS (`rc = 0`), yet on GB10 SM121 silicon `v2`
    executes only 1 cycle after `u` (< 6-cycle SM121 ALU latency) and reads stale register data!

    Live production Qwen 3.6 35B breaches detected by auditing all 36 extracted kernels under `G2`:
      - `fast_104` (`qAttnHd256SplitFast`): 2 breaches (`u=22 -> v=24` 1 cyc; `u=38 -> v=40` 1 cyc)
      - `fast_111` (`qSwiglu9Fast`):        1 breach   (`u=8  -> v=10` 1 cyc, `st 6->1`)
      - `fast_122` (`qW4B32Gemv4R`):        1 breach   (`u=762 -> v=764` 4 cyc)
      - `fast_123` (`qW4B32Grouped94R`):    2 breaches (`u=22 -> v=25` 1 cyc; `u=779 -> v=781` 4 cyc)
      - `fast_125` (`qW4B32Grouped9Dn4R`):  1 breach   (`u=769 -> v=771` 4 cyc)

    Antibody #17 also closes three companion SM121 scheduling holes in the same verifier:
      - #17b Deep-Pipe MMA Floor: `HMMA.16816` (`op 572`, 22 cycles) and `OMMA.SF.16864` (`op 29823`,
        29 cycles) same-accumulator RAW spans must never be shaved to the 6-cycle ALU floor.
      - #17c Predicate-Reader `SEL` (`op 520`, `nm=26`, `guard=7`) anchoring and anchor-segment
        preservation (no non-anchor may jump across an anchor in candidate order).
      - #17d Exact Multi-Barrier `rbar` Release: waiting barrier `b1` must clear only bit `b1`,
        never dropping an unwaited barrier `b2 ≠ b1` on the same address register (fixing
        `hxStepHazard` lines 338-340 / `mkStepHazard` lines 402-404).

    Mirrored in pure seeded OM-2 by `seed/ng/gpu_tma/g2_shrink.om` and `seed/ng/gpu_tma/tma_lower.om`.
-/

namespace Antibody17

/-- SM121 fixed-latency pipeline classes and their silicon-verified RAW cycle floors. -/
inductive PipeClass where
  | alu6   -- General fixed-latency ALU, IMAD.WIDE, I2FP/I2F, F2FP: 6 cycles
  | hmma22 -- HMMA.16816.F32.BF16 same-accumulator RAW: 22 cycles
  | omma29 -- OMMA.SF.16864.F32.E2M1.E2M1.UE4M3.4X same-accumulator RAW: 29 cycles
  deriving DecidableEq, Repr

def pipeFloor : PipeClass → Nat
  | .alu6   => 6
  | .hmma22 => 22
  | .omma29 => 29

/-- Sum of `f k` over half-open interval `[lo, hi)`. -/
def spanSum (f : Nat → Nat) (lo hi : Nat) : Nat :=
  if lo < hi then
    (List.range (hi - lo)).foldl (fun acc d => acc + f (lo + d)) 0
  else
    0

/-- Extended SM121 schedule certificate covering Antibodies #13-#17. -/
structure Sm121ExtSchedule where
  n           : Nat
  perm        : List Nat          -- cand pc i -> ref pc perm[i]
  inv         : Nat → Nat         -- ref pc u -> cand pc inv u
  isBBLeader  : Nat → Bool        -- pc=0, BRA target, or BRA fall-through (#13)
  isSelPred   : Nat → Bool        -- SEL (op 520, nm=26): reads P0 despite guard=7 (#17c)
  isAnchor    : Nat → Bool        -- full anchor set (must include BB leaders and SEL)
  isI2fp      : Nat → Bool        -- I2FP/I2F (op 581, nm=29) (#15)
  pipe        : Nat → PipeClass   -- SM121 pipeline class of ref pc u (#14, #17b)
  refStall    : Nat → Nat         -- reference stall cycles at ref pc
  candStall   : Nat → Nat         -- candidate stall cycles at cand pc
  rawEdge     : Nat → Nat → Bool  -- true iff ref v reads GPR written by fixed-latency ref u
  wawBetween  : Nat → Nat → Bool  -- true iff WAW/flow barrier strictly separates ref u and v

/-- Exact predicate for `v1` being the FIRST reference-order RAW consumer of `u`
    before any intervening WAW/control barrier. -/
def isFirstRefConsumer (s : Sm121ExtSchedule) (u v1 : Nat) : Prop :=
  u < v1 ∧ v1 < s.n ∧ s.rawEdge u v1 = true ∧ s.wawBetween u v1 = false ∧
  ∀ w, u < w → w < v1 → s.rawEdge u w = false

/-- Faithful model of the BUGGY legacy `hxCheckRawOne` in `seed/helix/helix_jit.om` (lines 530-568):
    checks ONLY the first reference-order RAW consumer `v1` with flat floor 6, returning early! -/
def legacyFirstConsumerAccept (s : Sm121ExtSchedule) : Prop :=
  (∀ i, i < s.n → s.isBBLeader i = true → s.perm[i]? = some i) ∧
  (∀ u v1, u < s.n → isFirstRefConsumer s u v1 →
    s.inv u < s.inv v1 ∧
    spanSum s.candStall (s.inv u) (s.inv v1) ≥ min (spanSum s.refStall u v1) 6) ∧
  (∀ u, u < s.n → s.isI2fp u = true → s.candStall (s.inv u) ≥ min (s.refStall u) 6)

/-- Complete Antibody #13-#17 Acceptance Predicate:
    1. Bijective `perm` / `inv` on `[0, n)`.
    2. All BB leaders (#13) and predicate-reading `SEL` ops (#17c) are anchored.
    3. Every anchor is fixed (`perm[a]? = some a` and `inv a = a`) AND no non-anchor
       crosses an anchor in candidate order (`u < a ↔ inv u < a`, #17c).
    4. Antibody #15: I2FP/I2F own stall never shaved below `min(refStall u, 6)`.
    5. Antibody #17a & #17b (All-Consumer Candidate-Order Pipe Floor):
       For EVERY producer `u` and EVERY live RAW consumer `v` (`u < v`, no intervening WAW),
       order is preserved (`inv u < inv v`) AND candidate cycle span `[inv u, inv v)` meets
       `min(refSpan(u, v), pipeFloor(pipe u))` (6 ALU / 22 HMMA / 29 OMMA)! -/
def antibody17Accept (s : Sm121ExtSchedule) : Prop :=
  (s.perm.length = s.n) ∧
  (∀ u, u < s.n → s.inv u < s.n ∧ s.perm[s.inv u]? = some u) ∧
  (∀ i, i < s.n → s.isBBLeader i = true → s.isAnchor i = true) ∧
  (∀ i, i < s.n → s.isSelPred i = true → s.isAnchor i = true) ∧
  (∀ a, a < s.n → s.isAnchor a = true → s.perm[a]? = some a ∧ s.inv a = a) ∧
  (∀ u a, u < s.n → a < s.n → s.isAnchor a = true → (u < a ↔ s.inv u < a)) ∧
  (∀ u, u < s.n → s.isI2fp u = true → s.candStall (s.inv u) ≥ min (s.refStall u) 6) ∧
  (∀ u v, u < s.n → v < s.n → u < v → s.rawEdge u v = true → s.wawBetween u v = false →
    s.inv u < s.inv v ∧
    spanSum s.candStall (s.inv u) (s.inv v) ≥ min (spanSum s.refStall u v) (pipeFloor (s.pipe u)))

-- ==================== ANTIBODY #17 GENERAL SOUNDNESS THEOREMS ====================

/-- Antibody #17a: ANY live RAW consumer `v` (including a second consumer `v2` shadowed by an
    earlier ref consumer `v1`) whose candidate cycle span drops below `min(refSpan, pipeFloor)`
    is ALWAYS rejected by `antibody17Accept`. -/
theorem antibody17_all_consumer_raw (s : Sm121ExtSchedule) (u v : Nat)
    (hu : u < s.n) (hv : v < s.n) (huv : u < v)
    (hraw : s.rawEdge u v = true) (hnwaw : s.wawBetween u v = false)
    (hshort : spanSum s.candStall (s.inv u) (s.inv v) <
              min (spanSum s.refStall u v) (pipeFloor (s.pipe u))) :
    ¬ antibody17Accept s := by
  intro ha
  have hcheck := ha.2.2.2.2.2.2.2 u v hu hv huv hraw hnwaw
  omega

/-- Antibody #17a (Swapped-Consumer Shadowing Corollary):
    Even when the first reference consumer `v1` is swapped AFTER a second consumer `v2`
    (`v1 < v2` yet `inv v2 < inv v1`) and `v1` satisfies the legacy stall check, `antibody17Accept`
    still guarantees that `v2` receives its full SM121 pipeline latency. -/
theorem antibody17_swapped_consumer_shadowing (s : Sm121ExtSchedule) (u v1 v2 : Nat)
    (hu : u < s.n) (hv2 : v2 < s.n) (huv1 : u < v1) (hv1v2 : v1 < v2)
    (_hswap : s.inv v2 < s.inv v1)
    (hraw2 : s.rawEdge u v2 = true) (hnwaw2 : s.wawBetween u v2 = false)
    (hacc : antibody17Accept s) :
    s.inv u < s.inv v2 ∧
    spanSum s.candStall (s.inv u) (s.inv v2) ≥
      min (spanSum s.refStall u v2) (pipeFloor (s.pipe u)) := by
  have huv2 : u < v2 := Nat.lt_trans huv1 hv1v2
  exact hacc.2.2.2.2.2.2.2 u v2 hu hv2 huv2 hraw2 hnwaw2

/-- Antibody #17b (HMMA.16816 22-Cycle Tensor Core Floor):
    Shaving an `HMMA.16816` accumulator-RAW span below `min(refSpan, 22)` (even if `>= 6`!)
    is ALWAYS rejected by `antibody17Accept`. -/
theorem antibody17_hmma_floor_22 (s : Sm121ExtSchedule) (u v : Nat)
    (hu : u < s.n) (hv : v < s.n) (huv : u < v)
    (hpipe : s.pipe u = .hmma22)
    (hraw : s.rawEdge u v = true) (hnwaw : s.wawBetween u v = false)
    (hshave : spanSum s.candStall (s.inv u) (s.inv v) < min (spanSum s.refStall u v) 22) :
    ¬ antibody17Accept s := by
  intro ha
  have hcheck := ha.2.2.2.2.2.2.2 u v hu hv huv hraw hnwaw
  rw [hpipe] at hcheck
  simp [pipeFloor] at hcheck
  omega

/-- Antibody #17b (OMMA.SF.16864 29-Cycle NVFP4 Tensor Core Floor):
    Shaving an `OMMA.SF.16864` accumulator-RAW span below `min(refSpan, 29)` is ALWAYS rejected. -/
theorem antibody17_omma_floor_29 (s : Sm121ExtSchedule) (u v : Nat)
    (hu : u < s.n) (hv : v < s.n) (huv : u < v)
    (hpipe : s.pipe u = .omma29)
    (hraw : s.rawEdge u v = true) (hnwaw : s.wawBetween u v = false)
    (hshave : spanSum s.candStall (s.inv u) (s.inv v) < min (spanSum s.refStall u v) 29) :
    ¬ antibody17Accept s := by
  intro ha
  have hcheck := ha.2.2.2.2.2.2.2 u v hu hv huv hraw hnwaw
  rw [hpipe] at hcheck
  simp [pipeFloor] at hcheck
  omega

/-- Antibody #17c (Predicate-Reader `SEL` Anchoring):
    Moving a predicate-reading `SEL` (`op 520`, `nm=26`, `guard=7`) is ALWAYS rejected. -/
theorem antibody17_sel_predicate_escape (s : Sm121ExtSchedule) (i r : Nat)
    (hi : i < s.n) (hsel : s.isSelPred i = true)
    (hp : s.perm[i]? = some r) (hne : r ≠ i) :
    ¬ antibody17Accept s := by
  intro ha
  have hanc : s.isAnchor i = true := ha.2.2.2.1 i hi hsel
  have hfix : s.perm[i]? = some i := (ha.2.2.2.2.1 i hi hanc).1
  rw [hp] at hfix
  exact hne (Option.some.inj hfix)

/-- Antibody #17c (Anchor-Segment Preservation):
    Moving any non-anchor `u` across an anchor `a` (`u < a` in ref, `inv u >= a` in cand,
    or `a < u` in ref, `inv u < a` in cand) is ALWAYS rejected even if `perm[a] = a`. -/
theorem antibody17_cross_anchor_escape (s : Sm121ExtSchedule) (u a : Nat)
    (hu : u < s.n) (ha_lt : a < s.n) (hanc : s.isAnchor a = true)
    (hcross : (u < a ∧ ¬ (s.inv u < a)) ∨ (¬ (u < a) ∧ s.inv u < a)) :
    ¬ antibody17Accept s := by
  intro hacc
  have hiff := hacc.2.2.2.2.2.1 u a hu ha_lt hanc
  rcases hcross with ⟨h1, h2⟩ | ⟨h1, h2⟩
  · exact h2 (hiff.mp h1)
  · exact h1 (hiff.mpr h2)

-- ==================== ANTIBODY #17d: MULTI-BARRIER `rbar` SOUNDNESS ====================

/-- Buggy `hxStepHazard` (lines 338-340) / `mkStepHazard` (lines 402-404) release rule:
    clears ALL pending read barriers whenever ANY 1 bit intersects `waitMask`. -/
def legacyRbarRelease (rbarMask waitMask : Nat) : Nat :=
  if (rbarMask &&& waitMask) != 0 then 0 else rbarMask

/-- Sound per-barrier release rule (Antibody #17d): clears ONLY barriers named in `waitMask`. -/
def soundRbarRelease (rbarMask waitMask : Nat) : Nat :=
  rbarMask &&& (63 ^^^ (waitMask &&& 63))

/-- Antibody #17d: For any 6-bit barrier mask `m < 64`, wait mask `w < 64`, and barrier `b < 6`,
    if barrier `b` is pending in `m` and NOT waited in `w`, barrier `b` remains pending after
    `soundRbarRelease m w`! (Exhaustively kernel-checked over all 64 × 64 × 6 = 24,576 states.) -/
theorem antibody17_multibarrier_rbar_sound :
    ∀ (m w : Fin 64) (b : Fin 6),
      ((m.val >>> b.val) &&& 1) = 1 →
      ((w.val >>> b.val) &&& 1) = 0 →
      (((soundRbarRelease m.val w.val) >>> b.val) &&& 1) = 1 := by
  decide

/-- Concrete Non-Vacuity Counterexample for `hxStepHazard` `rbar` Collapse:
    Address register holds both `LDG` (`rbar=1`, bit 1 = `0b010`) and `STG` (`rbar=2`, bit 2 = `0b100`),
    so `rbarMask = 6 (0b110)`. Waiting ONLY barrier 1 (`waitMask = 2 = 0b010`) causes buggy
    `legacyRbarRelease` to zero the entire mask (dropping barrier 2!), while `soundRbarRelease`
    preserves barrier 2 (`0b100 = 4`). -/
theorem legacy_rbar_collapse_counterexample :
    legacyRbarRelease 6 2 = 0 ∧
    soundRbarRelease 6 2 = 4 ∧
    (((soundRbarRelease 6 2) >>> 2) &&& 1) = 1 := by
  decide

-- ==================== LIVE `qSwiglu9Fast` G2 WITNESS (NEGATIVE & POSITIVE) ====================

/-- Exact 4-instruction extract of real production `qSwiglu9Fast` (`fast_111.bin`, PCs 8..11):
      ref 0 (pc 8):  IMAD R20, R15, 256, R14   (stall=6 -> shaved by G2 to 1!)
      ref 1 (pc 9):  SHF.R R21, R20, 9         (stall=6, reads R20 -> swapped to cand 2!)
      ref 2 (pc 10): LOP3.AND R22, R20, 511    (stall=6, reads R20 -> swapped to cand 1!)
      ref 3 (pc 11): IMAD R23, R21, 1024, R22  (stall=6, reads R21 & R22, anchor exit)
    G2 swaps `(1, 2)` and shaves `candStall 0` from `6 -> 1`. -/
def qSwiglu9G2Witness : Sm121ExtSchedule :=
  { n := 4,
    perm := [0, 2, 1, 3],
    inv := fun u => match u with | 0 => 0 | 1 => 2 | 2 => 1 | _ => 3,
    isBBLeader := fun i => i == 0,
    isSelPred := fun _ => false,
    isAnchor := fun i => i == 0 || i == 3,
    isI2fp := fun _ => false,
    pipe := fun _ => .alu6,
    refStall := fun _ => 6,
    candStall := fun pc => if pc == 0 then 1 else 6,
    rawEdge := fun u v =>
      (u == 0 && (v == 1 || v == 2)) ||
      ((u == 1 || u == 2) && v == 3),
    wawBetween := fun _ _ => false }

/-- Smoking-Gun Proof: The real `qSwiglu9Fast` `G2` schedule PASSES buggy `legacyFirstConsumerAccept`
    (`inv[0]=0 -> inv[1]=2` gives `1 + 6 = 7 >= 6`), YET starves `v2 = 2` (`inv[2]=1`) to `1` cycle! -/
theorem g2_witness_passes_legacy_monk_yet_corrupts :
    legacyFirstConsumerAccept qSwiglu9G2Witness ∧
    spanSum qSwiglu9G2Witness.candStall
      (qSwiglu9G2Witness.inv 0) (qSwiglu9G2Witness.inv 2) = 1 := by
  refine ⟨⟨?_, ?_, ?_⟩, ?_⟩
  · intro i hi hbb
    match i, hi, hbb with
    | 0, _, _ => rfl
  · intro u v1 hu hfirst
    rcases hfirst with ⟨huv1, hv1n, hraw, _, hmin⟩
    match u, hu with
    | 0, _ =>
      match v1, hv1n with
      | 1, _ => refine ⟨by decide, by decide⟩
      | 2, _ =>
        have hbad := hmin 1 (by decide) (by decide)
        simp [qSwiglu9G2Witness] at hbad
      | 3, _ => simp [qSwiglu9G2Witness] at hraw
    | 1, _ =>
      match v1, hv1n with
      | 2, _ => simp [qSwiglu9G2Witness] at hraw
      | 3, _ => refine ⟨by decide, by decide⟩
    | 2, _ =>
      match v1, hv1n with
      | 3, _ => refine ⟨by decide, by decide⟩
    | 3, _ => dsimp [qSwiglu9G2Witness] at hv1n; omega
  · intro u _ hi2f
    simp [qSwiglu9G2Witness] at hi2f
  · decide

/-- Antibody #17 Kills the Real `qSwiglu9Fast` `G2` Witness! -/
theorem antibody17_kills_qSwiglu9_g2 : ¬ antibody17Accept qSwiglu9G2Witness := by
  apply antibody17_all_consumer_raw qSwiglu9G2Witness 0 2
  · decide
  · decide
  · decide
  · rfl
  · rfl
  · decide

/-- Positive Non-Vacuity Witness: keeping the exact same `(1, 2)` swap in `qSwiglu9Fast`
    while preserving `candStall 0 = 6` IS ADMITTED by `antibody17Accept`! -/
def qSwiglu9FixedWitness : Sm121ExtSchedule :=
  { qSwiglu9G2Witness with candStall := fun _ => 6 }

theorem antibody17_admits_safe_swap : antibody17Accept qSwiglu9FixedWitness := by
  refine ⟨rfl, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · intro u hu
    match u, hu with
    | 0, _ => exact ⟨by decide, rfl⟩
    | 1, _ => exact ⟨by decide, rfl⟩
    | 2, _ => exact ⟨by decide, rfl⟩
    | 3, _ => exact ⟨by decide, rfl⟩
  · intro i hi hbb
    match i, hi, hbb with
    | 0, _, _ => rfl
  · intro i _ hsel
    simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hsel
  · intro a ha hanc
    match a, ha with
    | 0, _ => exact ⟨rfl, rfl⟩
    | 1, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hanc
    | 2, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hanc
    | 3, _ => exact ⟨rfl, rfl⟩
  · intro u a hu ha hanc
    match a, ha with
    | 0, _ =>
      match u, hu with
      | 0, _ => decide | 1, _ => decide | 2, _ => decide | 3, _ => decide
    | 1, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hanc
    | 2, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hanc
    | 3, _ =>
      match u, hu with
      | 0, _ => decide | 1, _ => decide | 2, _ => decide | 3, _ => decide
  · intro u _ hi2f
    simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hi2f
  · intro u v hu hv huv hraw _
    match u, hu with
    | 0, _ =>
      match v, hv with
      | 1, _ => refine ⟨by decide, by decide⟩
      | 2, _ => refine ⟨by decide, by decide⟩
      | 3, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hraw
      | 0, _ => omega
    | 1, _ =>
      match v, hv with
      | 3, _ => refine ⟨by decide, by decide⟩
      | 0, _ => omega | 1, _ => omega
      | 2, _ => simp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hraw
    | 2, _ =>
      match v, hv with
      | 3, _ => refine ⟨by decide, by decide⟩
      | 0, _ => omega | 1, _ => omega | 2, _ => omega
    | 3, _ => dsimp [qSwiglu9FixedWitness, qSwiglu9G2Witness] at hv; omega

-- ==================== BINARY-SEARCH DELTA-SHRINKER COMPLETENESS ====================

/-- Pure functional model of `seed/ng/gpu_tma/g2_shrink.om`'s binary-search prefix isolator:
    given oracle `fails : Nat → Bool` with `fails lo = false` and `fails hi = true`,
    returns `m` with `lo ≤ m < hi`, `fails m = false`, and `fails (m + 1) = true`,
    identifying the exact triggering swap `swaps[m]`! -/
def bsearchPrefix (fails : Nat → Bool) : Nat → Nat → Nat → Nat
  | 0, lo, _ => lo
  | fuel + 1, lo, hi =>
    if hi ≤ lo + 1 then lo
    else
      let mid := (lo + hi) / 2
      if fails mid then bsearchPrefix fails fuel lo mid
      else bsearchPrefix fails fuel mid hi

/-- Binary-Search Delta-Shrinker Soundness Theorem:
    Whenever `fuel ≥ hi - lo`, `lo < hi`, `fails lo = false`, and `fails hi = true`,
    `bsearchPrefix` terminates with the exact minimal failure transition `m`
    (`fails m = false` AND `fails (m + 1) = true`), isolating the triggering swap `swaps[m]`. -/
theorem bsearchPrefix_isolates_trigger
    (fails : Nat → Bool) (fuel lo hi : Nat)
    (hfuel : hi - lo ≤ fuel)
    (hlt : lo < hi)
    (hlo : fails lo = false)
    (hhi : fails hi = true) :
    let m := bsearchPrefix fails fuel lo hi
    lo ≤ m ∧ m < hi ∧ fails m = false ∧ fails (m + 1) = true := by
  induction fuel generalizing lo hi with
  | zero => omega
  | succ f ih =>
    unfold bsearchPrefix
    split
    · next hle =>
      have heq : hi = lo + 1 := by omega
      refine ⟨Nat.le_refl lo, hlt, hlo, heq ▸ hhi⟩
    · next hgt =>
      have hmid_gt : lo < (lo + hi) / 2 := by omega
      have hmid_lt : (lo + hi) / 2 < hi := by omega
      dsimp only
      split
      · next hfm =>
        have hsub : (lo + hi) / 2 - lo ≤ f := by omega
        have ⟨h1, h2, h3, h4⟩ := ih lo ((lo + hi) / 2) hsub hmid_gt hlo hfm
        exact ⟨h1, Nat.lt_trans h2 hmid_lt, h3, h4⟩
      · next hfm =>
        have hfm_f : fails ((lo + hi) / 2) = false := Bool.eq_false_iff.mpr hfm
        have hsub : hi - (lo + hi) / 2 ≤ f := by omega
        have ⟨h1, h2, h3, h4⟩ := ih ((lo + hi) / 2) hi hsub hmid_lt hfm_f hhi
        exact ⟨Nat.le_trans (Nat.le_of_lt hmid_gt) h1, h2, h3, h4⟩

#print axioms antibody17_all_consumer_raw
#print axioms antibody17_swapped_consumer_shadowing
#print axioms antibody17_hmma_floor_22
#print axioms antibody17_omma_floor_29
#print axioms antibody17_sel_predicate_escape
#print axioms antibody17_cross_anchor_escape
#print axioms antibody17_multibarrier_rbar_sound
#print axioms legacy_rbar_collapse_counterexample
#print axioms g2_witness_passes_legacy_monk_yet_corrupts
#print axioms antibody17_kills_qSwiglu9_g2
#print axioms antibody17_admits_safe_swap
#print axioms bsearchPrefix_isolates_trigger

end Antibody17
