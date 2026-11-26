# `apps/omega-wattd`: Pure Seeded OM-2 Whole-Unit Power, Thermal CBF & Fan Planner (DGX Spark GB10)

Pure seeded OM-2 whole-unit power, thermal Control Barrier Function (CBF), and anticipatory pre-cooling controller for DGX Spark GB10 (Blackwell SM121 / GB20B + 20-core Grace ARMv9). Zero C, zero Python on the production path, zero `nvidia.ko` dependency for live silicon sensing, and zero telemetry.

## Safety & Actuator Policy (Stage 1)

- **Strictly READ-ONLY / DRY-RUN on physical actuators by default (`actuator_mode=DRY_RUN_READONLY`, `hw_writes=0`).**
- `--apply` is explicitly **refused** (exit code `2`, `hw_writes=0`) until Stage-2 hardware actuator qualification and explicit window approval.
- Hard physical ceilings enforced mathematically and at runtime:
  - **`P_gpu <= 80,000 mW` (`80 W`)**: margin below Trap 14's `85–92 W` hard power-off cliff on DGX Spark GB10.
  - **`P_gpu + P_cpu + P_unc <= min(P_budget, 140,000 mW)`**: whole-unit Watt conservation.
  - **`h = T_ceil - T_die - tau * dT >= 0`** and **`T_die' <= T_ceil <= 90.0°C`** (`85.0°C` default / `78.0°C` training default, all below `104.8°C` ACPI crit trips).
  - Never opens UEFI/SPI paths or PCIe FLR.

## Files

- `watt_sense.om` — Live read-only sysfs sensor reader:
  - `/sys/class/thermal/thermal_zone{0..6}/temp` & `trip_point_0_temp` (`TSOC`, `TS0E`, `TS0P`, `TS1E`, `TS1P`, live `TGPU` `zone5`, `TUNC` `zone6`).
  - `/sys/devices/system/cpu/cpu{0..19}/cpufreq/scaling_cur_freq` (A725 `338–2808 MHz`, X925 `1378–3900 MHz`).
  - `/sys/devices/system/cpu/cpu{0..19}/acpi_cppc/feedback_ctrs` (`ref:<u64> del:<u64>`).
- `watt_cbf.om` — Fixed-point Joules-per-bit (`TuringYield_J = delta_bits / delta_J`) Watt-budget allocator, Arboris anticipatory pre-cooling planner (burst lookahead -> pre-cool fan floor + pre-burst power trough), exact 1:1 fixed-point mirror of [`seed/helix/proofs/WattCBF.lean`](../../seed/helix/proofs/WattCBF.lean), and the 9-check core self-verification suite (`wc_run_core_gate`).
- `wattd_main.om` — CLI (`omega-wattd sense`, `omega-wattd plan`, `omega-wattd gate`).
- `gate_wattd.om` — Standalone 13-check pure-OM-2 verification gate (9 core checks + unconditional monotonicity sweeps, full-`i64` signed `ceilDiv` parity, 128-case adversarial & idempotence matrix, and whole-unit/sensor-fault fail-closed tests).

## Formal Safety Proof

[`seed/helix/proofs/WattCBF.lean`](../../seed/helix/proofs/WattCBF.lean) proves 32 theorems in standalone Lean 4 (`0 sorry`, standard axioms only, zero Mathlib dependency) covering the exact same constants, `ceilDiv`, `barrierH`, `rawHeatBudget`, `mustFailClosed`, 2-node thermal update, and `cbfFilter` implemented in `watt_cbf.om`, including unconditional admitted-command barrier safety (`cbf_admitted_barrier_safe`), multi-step inductive safety (`cbf_multistep_temp_safe`), unconditional budget monotonicity (`cbf_mono_pBudget_rails`), anticipatory pre-cooling (`precool_fan_mono_sink`), full command idempotence (`cbf_idempotent`), and 5 axiom-free non-vacuity negative controls (including an unclamped 90 W Trap-14 spike and reverse-conduction / overheated-heatsink fail-closed witnesses).

## Build & Verify (Linux AArch64, DGX Spark)

```sh
# 1. Machine-check Lean 4 proof (zero sorry, zero warnings)
~/.elan/bin/lean seed/helix/proofs/WattCBF.lean

# 2. Build static AArch64 pure-OM-2 binaries with seeded omc
cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om apps/omega-wattd/wattd_main.om | seed/out/omc > /tmp/om_wattd/omega-wattd
cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om apps/omega-wattd/gate_wattd.om | seed/out/omc > /tmp/om_wattd/gate_wattd
chmod +x /tmp/om_wattd/omega-wattd /tmp/om_wattd/gate_wattd

# 3. Run live sensing, dry-run planning, and full verification gates
/tmp/om_wattd/omega-wattd sense
/tmp/om_wattd/omega-wattd plan --watts 90 --tgpu-ceil 85 --mode decode
/tmp/om_wattd/omega-wattd plan --watts 100 --tgpu-ceil 78 --mode train --burst-mw 75000 --burst-sec 5
/tmp/om_wattd/omega-wattd gate
/tmp/om_wattd/gate_wattd
```
