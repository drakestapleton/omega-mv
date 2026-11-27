# `seed/ng/physics`: Sovereign Intelligence 2.0 Stage 3 — Physics-Typed Computing

Pure seeded OM-2 Pareto Realization Bank and Real-Time Physics Dispatch Solver connecting [`apps/omega-wattd/watt_cbf.om`](../../../apps/omega-wattd/watt_cbf.om) (linked unchanged), ΩIR v2 function contracts ([`seed/ng/IR.md`](../IR.md) §16), and [`seed/ng/target/fabric.om`](../target/fabric.om) (`fabHotSwap`), backed by the standalone machine-checked Lean 4 safety proof [`seed/helix/proofs/PhysicsDispatch.lean`](../../helix/proofs/PhysicsDispatch.lean).

## Safety & Actuator Policy

- **Strictly `DRY_RUN_READONLY` (`hw_writes = 0`)**: zero writes to sysfs, GPU MMIO/GSP, UEFI NVRAM, or SPI flash. Never opens the physical GB10 GPU.
- **Locked Strict Priority Hierarchy** (enforced both at runtime in `phys_solver.om` and formally proved with `0 sorry` in `PhysicsDispatch.lean`):
  1. **Hardware `WattCBF` thermal/power safety ceiling is INVIOLABLE**: every dispatched realization is admitted un-clamped by `wc_cbf_filter` (`P_gpu <= min(80,000 mW, P_gpu_budget)`, `P_total <= min(P_budget, 140,000 mW)`, discrete thermal CBF barrier `h >= 0`, `T_die' <= T_ceil`, `fail_closed == 0`), plus the function's `@power` ceiling when nonzero.
  2. **Declared `@err` accuracy bound is NEVER silently broken**: `0 <= proven_err_bound <= @err` (and strictly `0` under `@exact`).
  3. **Minimize latency / honor `@deadline` inside `(1) & (2)`**:
     - If no safe realization meets `@deadline` and `@hard_deadline == 1`: fail closed with `PHYS_ERR_HARD_DEADLINE` (does not mutate `fabWtbl`).
     - If no safe realization meets `@deadline` and `@hard_deadline == 0`: dispatch the fastest safe realization inside `(1) & (2)` and emit a structured `ALARM_DEADLINE_SLIP` record (never silent).
- **Proof Gate**: Every realization must carry `proof_mask == 7` (`Contract | EGP3 | Antibody`) both on bank registration (`pareto_bank.om`) and before dispatch into `fabHotSwap`.

## Files

- [`pareto_bank.om`](pareto_bank.om) — Multi-precision Pareto realization bank per `SEMANTIC_ID` (`FP64`, `FP32`, `BF16`, `FP8`, `NVFP4`, `CPU_X925`, `CPU_A725`, `SM121`, `ARBORIS_SHORTCUT`) with `(target_tid, precision_id, est_power_mw, est_latency_us, est_joules_uj, proven_err_bound, proof_mask)` and strict `proof_mask == 7` admission.
- [`phys_solver.om`](phys_solver.om) — Real-time physics dispatch solver, live 28-byte ΩIR v2 wire contract parser (`IR.md` §16.1), `watt_cbf.om` thermal/power envelope integration, direct `fabHotSwap` dispatch wiring, `TuringYield_J` & structured `ALARM_DEADLINE_SLIP` telemetry, and additive/Lipschitz sequential call-chain error-composition tracker.
- [`gate_physics.om`](gate_physics.om) — Standalone 10-check pure-OM-2 verification gate (10 negative controls) covering `60°C -> 84°C` thermal ramp dynamic precision scaling over a `16.6 ms` frame budget, Trap-14 `90 W` clamping and refusal, `@err` inviolability, `@hard_deadline` fail-closed vs. soft `ALARM_DEADLINE_SLIP`, sequential chain error composition & overflow refusal, ΩIR v2 binary contract parsing, over-temperature fail-closed guards, `@power` cap + `ARBORIS_SHORTCUT`, and `hw_writes == 0`.
- [`../../helix/proofs/PhysicsDispatch.lean`](../../helix/proofs/PhysicsDispatch.lean) — Standalone Lean 4 proof (`0 sorry`, 0 warnings, zero Mathlib dependency, standard axioms only) proving `admitted_respects_wattcbf`, `admitted_respects_err_bound`, `hard_deadline_fail_closed`, `hard_deadline_miss_exact`, `soft_deadline_slip_never_silent`, `admitted_is_min_latency_among_safe`, `unproved_never_admitted`, `chain_error_composition_sound`, `chain_overflow_refused`, and 6 concrete non-vacuity negative-control witnesses.

## Build & Verify (Linux AArch64, DGX Spark)

```sh
# 1. Machine-check standalone Lean 4 safety proof (0 sorry, 0 warnings, standard axioms only)
~/.elan/bin/lean seed/helix/proofs/PhysicsDispatch.lean

# 2. Build static AArch64 pure-OM-2 verification gate with pinned seeded omc (85b84c6d...)
cat si/directives/om2.om \
    apps/omega-wattd/watt_sense.om \
    apps/omega-wattd/watt_cbf.om \
    seed/ng/target/target_desc.om \
    seed/ng/target/isel.om \
    seed/ng/target/sm121_pe.om \
    seed/ng/target/fabric.om \
    seed/ng/physics/pareto_bank.om \
    seed/ng/physics/phys_solver.om \
    seed/ng/physics/gate_physics.om | seed/out/omc > /tmp/gate_physics
chmod +x /tmp/gate_physics

# 3. Run standalone verification gate (DRY_RUN_READONLY, hw_writes=0)
/tmp/gate_physics
```
