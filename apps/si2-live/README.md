# `apps/si2-live` — Live End-to-End Sovereign Intelligence 2.0 Integration

Pure seeded OM-2 cross-machine integration uniting all six Sovereign Intelligence 2.0 layers across Apple Silicon macOS (`a64macos` Mach-O) and DGX Spark / Raspberry Pi 5 Linux (`aarch64` ELF) with `hw_writes=0` strictly enforced:

| Stage | Layer | Module(s) Used | Role in Live Loop |
| :--- | :--- | :--- | :--- |
| 0 | `omega-wattd` | `apps/omega-wattd/{watt_sense,watt_cbf}.om` | Read-only 7-zone thermal telemetry & fixed-point CBF safety envelope |
| 1 | `OMEGA-MEMO` | `seed/ng/pack/sem_pack.om`, `seed/ng/memo/{memo_policy,memo_store}.om` | `OMPK v2` content-addressed package + `.ome` CAS (`OMEGA_MEMO_HIT`, `recompute=0`) |
| 2 | `replay` | `seed/ng/replay/{tok_journal,slab_ckpt,cf_fork,state_stream}.om` | `OTKJ v1` hash-chained journal + `SLAB` checkpoint rewind + `OSTM v1` stream |
| 3 | `physics` | `seed/ng/physics/{pareto_bank,phys_solver}.om` | `TargetDesc` + `WattCBF`-bounded realization solver (`ProofMask == 7`) |
| 4 | `omega-metabd` | `apps/omega-metabd/{profile_ring,general_pe}.om` | `EGP3` partial evaluator + strict `W^X` (`0500 RX`) + `fabHotSwap` + Trap-14 OOD rollback |
| 5 | `omega-mesh` | `apps/omega-mesh/{mesh_verify,mesh_route}.om` | Ed25519-signed `OMSH v1` TCP dispatch + `OMRC0001` verify + TOCTOU-proof memo admission |

## Files

- `si2_live_main.om` — Spark/Hub `aarch64` Linux server and CLI (`status`, `check-bind`, `--rwx`, `demo`, `serve`, `dispatch`).
- `si2_mac_peer.om` — MacBook Apple Silicon `a64macos` Mach-O peer (`selfcheck` offline mode + physical LAN client over Darwin `libSystem` sockets via `libfn`/`libptr`/`libcall`).
- `gate_si2_live.om` — Pure OM-2 verification gate exercising all 6 stages, TCP loopback Calls 1/2/3, 5+ negative controls, CLI checks, and 3 live `omc`-recompiled source mutants on `si2_live_main.om`.

## Build & Run

### 1. Build Spark / Hub `aarch64` Linux binaries (2x deterministic with pinned `omc`)

```bash
{
  cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om
  tail -n +2 seed/ng/src/ir.om
  cat seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
      protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
      seed/ng/target/target_desc.om seed/ng/target/isel.om seed/ng/target/sm121_pe.om \
      seed/ng/target/fabric.om seed/ng/target/crystallize.om \
      seed/ng/egraph/ir_egraph.om seed/ng/verify/egp3_checker.om \
      seed/ng/live/arboris_spec.om seed/ng/pack/sem_pack.om \
      seed/ng/memo/memo_policy.om seed/ng/memo/memo_store.om \
      seed/ng/replay/tok_journal.om seed/ng/replay/slab_ckpt.om \
      seed/ng/replay/cf_fork.om seed/ng/replay/state_stream.om \
      seed/ng/physics/pareto_bank.om seed/ng/physics/phys_solver.om \
      apps/omega-metabd/profile_ring.om apps/omega-metabd/general_pe.om \
      apps/omega-mesh/mesh_verify.om apps/omega-mesh/mesh_route.om \
      apps/si2-live/si2_live_main.om
} | /tmp/omc-pin > /tmp/si2_live && chmod +x /tmp/si2_live
```

Substitute `apps/si2-live/gate_si2_live.om` for `si2_live_main.om` to build `/tmp/gate_si2_live`:

```bash
/tmp/gate_si2_live /tmp/si2-live-gate /tmp/si2_live /tmp/omc-pin .
```

### 2. Cross-compile MacBook Apple Silicon (`a64macos` Mach-O) peer via Omega NG

```bash
cat seed/ng/src/ir.om seed/ng/sha256.om seed/ng/src/front.om seed/ng/src/opt.om \
    seed/ng/src/a64.om seed/ng/src/main.om | /tmp/omc-pin > /tmp/ng && chmod +x /tmp/ng

{
  printf '@ng front-ir\ntarget macos\nom2\n'
  cat seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
      protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
      seed/ng/target/target_desc.om seed/ng/pack/sem_pack.om \
      apps/si2-live/si2_mac_peer.om
} | /tmp/ng > /tmp/si2_mac_peer.ir
{ printf '@ng opt\n'; cat /tmp/si2_mac_peer.ir; } | /tmp/ng > /tmp/si2_mac_peer.opt
{ printf '@ng a64 macho\n'; cat /tmp/si2_mac_peer.opt; } | /tmp/ng > /tmp/si2_mac_peer
# Copy /tmp/si2_mac_peer to MacBook and ad-hoc sign:
codesign --force --sign - /tmp/si2_mac_peer
SI2_MAC_MODE=selfcheck /tmp/si2_mac_peer
```

### 3. Live 3-Node LAN Check (`MacBook <-> Spark <-> Hub`)

- On Spark (`192.168.1.108:14323`, inside `atlas_ingress` owner-sanctioned `14318-14323` allowlist): `/tmp/si2_live serve 192.168.1.108 14323 /tmp/si2-m /tmp/si2-w /tmp/si2.otkj 0`
- On MacBook (`192.168.1.193`): `SI2_SPARK_IP=192.168.1.108 SI2_SPARK_PORT=14323 /tmp/si2_mac_peer`
- On Pi 5 Hub (`192.168.1.192`): `/tmp/si2_live status --hub`, `/tmp/si2_live demo ... --hub`, and `/tmp/si2_live dispatch 192.168.1.108 14323 ...` (without touching `omega-edge.target` production ports; Hub inbound arbitrary ports remain gated by Hub's firewall).

## Safety Guarantees

- `hw_writes=0` strictly (zero GPU device opens, zero sysfs writes, zero flash/firmware touches).
- `0.0.0.0` bind strictly refused (`rc=12`).
- `--rwx` W^X violation strictly refused (`rc=2`).
- Physical GPU kernel launch is `NOT_RUN` (`ProofMask == 7` verified purely over host CPU + LAN thermal telemetry).
