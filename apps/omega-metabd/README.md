# `apps/omega-metabd`: Sovereign Intelligence 2.0 Stage 4 — Living Proof-Carrying Self-Specialization Daemon

Pure seeded OM-2 (`.om`) implementation of **Pillar 1 (`omega-metabd`, DRA-1072)**: continuous background self-specialization of hot multi-block ΩIR functions with shared-memory hot-path profiling, equality-saturation `EGP3` structural proofs verified by zero-shared-code `egp3_checker.om`, strict `W^X` (`RW -> SHA-256 -> RX`, never `RWX`) native AArch64 code sealing, cooperative `fabWtbl` atomic slot hot-swap on efficiency cores (`TID_A725`), and instant `SLAB_MUTABLE_ALARMED` / `ORACLE` out-of-domain rollback.

Zero C, zero Python, zero Rust on production paths. Links existing `seed/ng/*` units unchanged. Never maps `RWX` pages, never touches UEFI/SPI, and never opens physical GPU hardware.

## Files

| File | Role |
|---|---|
| [`profile_ring.om`](profile_ring.om) | Shared-memory hot-path profile ring (`mapnew` strictly `RW`, `cpufence` + 64-bit `mapget`/`mapset`) recording `(sem_id, arg_sig, branch_bias_bp, sparsity_pct, cycle_cost, call_count, pid, flags)` across processes. No silent hard caps: wraps cleanly with loud overwrite counters and structured eviction alarms (`pr_*`). |
| [`general_pe.om`](general_pe.om) | General multi-block ΩIR partial evaluator (`gpe_*`) over `seed/ng/src/ir.om` (dominant constant operands, hot-branch folding with `trap 14` OOD deopt guard, sparse/fixed-shape loop unrolling & zero-skip), exact multi-block ΩIR interpreter oracle, live `ir_egraph.om` -> `EGP3` -> zero-shared-code `egp3_checker.om` proof bridge, native AArch64 static ELF64 emitter (`isel.om` + Arm ARM DDI 0487 encodings), strict `W^X` staging/sealing/execution (`wx_*`), 3-bit proof gate (`Contract(1) \| EGP3(2) \| Monk+Immune(4) == 7`), and cooperative `fabWtbl` hot-swap + `SLAB_MUTABLE_ALARMED` OOD rollback (`mb_*`). |
| [`metabd_main.om`](metabd_main.om) | Production `omega-metabd` CLI (`status`, `spec [--workload affine\|branch\|sparse\|all] [--dir PATH] [--ood]`, `gate [--dir PATH]`, refusing `--rwx` fail-closed). |
| [`gate_metabd.om`](gate_metabd.om) | Standalone verification gate testing cross-process shared-memory profiling + loud wrap/eviction alarms, all 3 multi-block ΩIR workloads (`affine_route`, `branch_diamond`, `sparse_dot_loop`) through live `ir_egraph` + `egp3_checker`, native AArch64 `W^X` parity and instruction/op/timing reduction, cooperative `TID_A725` `fabWtbl` swap + live OOD `trap 14` rollback, 7 fail-closed negative controls, 3 built-in mutation kills, and optional CLI + 2 live `omc`-recompiled source-level mutation kills. |

## Safety Invariants

1. **Strict `W^X` Discipline (NEVER `RWX`):**
   - `wx_validate_prot` rejects any mask with both `PROT_WRITE (2)` and `PROT_EXEC (4)` set (`WX_ERR_RWX_FORBIDDEN`).
   - `wx_verify_elf_wx` rejects any ELF64 `PT_LOAD` segment carrying `PF_W | PF_X` (`3`); requires exact `PF_R | PF_X` (`5`).
   - `wx_stage_and_seal` writes non-executable `0600` (`rw-------`), reads back and verifies FIPS 180-4 SHA-256 (`seed/ng/sha256.om`), strips write bits and seals `0500` (`r-x------`) via `fchmod` + `fsync` + atomic `renames`, and re-verifies `stat` mode has zero write bits (`(st_mode & 0222) == 0`) before every execution.
2. **Fail-Closed 3-Bit Proof Gate (`eff_mask == 7`):**
   - **Bit 0 (`Contract` = 1):** `tdCheckKernelContract` (`seed/ng/target/target_desc.om`) + ΩIR v2 `ir_fc_ok`.
   - **Bit 1 (`EGP3` = 2):** Live `eg3_opt_ir_block` (`seed/ng/egraph/ir_egraph.om`) -> `EGP3` binary proof -> independent zero-shared-code `vc3_verify` (`seed/ng/verify/egp3_checker.om`).
   - **Bit 2 (`Monk+Immune` = 4):** Strict `W^X` + instruction framing + 3-point ORACLE differential parity (CPU) / Antibodies #13–#15 stall-floor checks (SM121).
   - Any missing bit or failed check leaves `fabWtbl` (`fabVer`, `fabPtr`, `fabMode`) untouched.
3. **Instant `SLAB_MUTABLE_ALARMED` OOD Rollback:**
   - Every specialized slot is paired with an immutable baseline (`SLAB_IMMUTABLE`) and an alarmed specialization envelope (`SLAB_MUTABLE_ALARMED`).
   - On live out-of-domain input (`trap 14`, exit `114`) or spot-check divergence, `mb_dispatch_slot` trips `CR_ERR_ALARM`, records a structured alarm, atomically flips `fabWtbl` back to the immutable baseline with `cpufence`, and returns the exact baseline output.

## Build & Verify (Linux AArch64, DGX Spark with pinned `seed/out/omc`)

```sh
# Confirm pinned compiler SHA-256 (85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134)
sha256sum seed/out/omc

# Build omega-metabd CLI
cat seed/ng/src/ir.om seed/ng/sha256.om seed/ng/target/target_desc.om \
    seed/ng/target/isel.om seed/ng/target/sm121_pe.om seed/ng/target/fabric.om \
    seed/ng/target/crystallize.om seed/ng/egraph/ir_egraph.om \
    seed/ng/verify/egp3_checker.om seed/ng/live/arboris_spec.om \
    apps/omega-metabd/profile_ring.om apps/omega-metabd/general_pe.om \
    apps/omega-metabd/metabd_main.om | seed/out/omc > /tmp/omega-metabd && chmod +x /tmp/omega-metabd

# Build standalone verification gate
cat seed/ng/src/ir.om seed/ng/sha256.om seed/ng/target/target_desc.om \
    seed/ng/target/isel.om seed/ng/target/sm121_pe.om seed/ng/target/fabric.om \
    seed/ng/target/crystallize.om seed/ng/egraph/ir_egraph.om \
    seed/ng/verify/egp3_checker.om seed/ng/live/arboris_spec.om \
    apps/omega-metabd/profile_ring.om apps/omega-metabd/general_pe.om \
    apps/omega-metabd/gate_metabd.om | seed/out/omc > /tmp/gate_metabd && chmod +x /tmp/gate_metabd

# Run CLI & full verification gate (including live CLI checks & omc-recompiled source mutation kills)
/tmp/omega-metabd status
/tmp/omega-metabd spec --workload all --dir /tmp/metabd-cli-wx --ood
/tmp/omega-metabd gate --dir /tmp/metabd-cli-wx
/tmp/gate_metabd /tmp/metabd-gate-wx /tmp/omega-metabd seed/out/omc .
```
