# `apps/omega-mesh/`: Stage 5 — Zero-Trust Personal Silicon Mesh (`omega-mesh`, DRA-1073)

> **Pillar 5 of Sovereign Intelligence 2.0.** Pure seeded OM-2 (`.om`) transparent Compile-on-Arrive remote execution mesh across personal heterogeneous silicon (MacBook `a64macos`, Steam Deck `x86linux`, PC `x86linux`, DGX Spark `a64linux` + `SM121`), gated by `TargetDesc` physical contracts, `WattCBF` thermal/power headroom, two explicit verification tiers (Tier A Owner Sovereign Mesh & Tier B Zero-Trust Mode), and fail-closed `OMEGA-MEMO` admission. Zero C, zero Python, zero Rust, zero external crypto libraries, and zero telemetry.

## Safety Invariants

- **Strictly loopback / explicit peer endpoints only:** Wildcard `0.0.0.0` bind and broadcast `255.255.255.255` endpoints are refused fail-closed (`MR_ERR_WILDCARD_BIND = 12`). Listeners bind only to `127.0.0.1` or explicit non-zero private/WireGuard unicast addresses.
- **Zero hardware writes (`hw_writes == 0`):** Zero physical GPU device opens, zero UEFI/SPI touches, zero sysfs writes. `WattCBF` thermal/power envelopes are evaluated read-only via unchanged `apps/omega-wattd/watt_cbf.om`.
- **Fail-closed `OMEGA-MEMO` admission:** Remote outputs enter `seed/ng/memo/memo_store.om` **only** via `mv_admit_to_memo`, which enforces a one-shot verified proof token, purity admission (`purity_flag == 1`, `ck_pure_verified == 1`), and a TOCTOU SHA-256 re-hash check over `mm_val_buf` before calling `mm_store`.

## Files

| File | Prefix | Role |
|---|---|---|
| `mesh_verify.om` | `mv_` / `MV_` | Two-tier verification engine: RFC 8032 Ed25519 peer allowlist & `OMRC0001` 288-byte execution receipts (reusing `protocol/omnet/om/sha512/sha512.om`, `protocol/omnet/om/ed25519/ed25519.om`, `protocol/uor-gpu/ed_sign.om`), anti-replay nonce ring + monotonic epoch check, Tier A configurable spot-check re-execution + automatic peer quarantine, Tier B Freivalds `O(R*N^2)` matmul verifier (live OS `random` or seeded), Tier B Merkle checkpoint verifier + `O(log2 M)` binary bisection, Tier B dual-peer BFT quorum (with Sybil same-peer refusal), and TOCTOU-proof one-shot `mv_admit_to_memo`. |
| `mesh_route.om` | `mr_` / `MR_` | Compile-on-Arrive mesh router: extends `target_desc.om` with heterogeneous personal profiles (`MR_TID_MACBOOK = 10`, `MR_TID_STEAMDECK = 11`, `MR_TID_PC = 12` alongside `TID_X925`, `TID_SM121`, `TID_APU_GB10`), checks `OMEGA-MEMO` first, evaluates `pk_check_contract` + live `WattCBF` headroom (`wc_cbf_filter` / `wc_must_fail_closed` / `wc_barrier_h`) + `OMPK` transfer & RTT (`coherence_cost`) vs. compute savings, implements fail-closed Ed25519-signed `OMSH` v1 wire framing, loopback-safe TCP sockets (`socknew`/`bind`/`listen`/`accept`/`connect`/`waitio`/`send`/`recv`), and pure Compute-on-Arrive worker/client execution. |
| `mesh_daemon.om` | `md_` | Standalone pure-OM-2 CLI & TCP loopback daemon (`omega-mesh`): `demo`, `route`, `serve`, `dispatch`, and `check-bind`. |
| `gate_mesh.om` | `gm_` | Standalone 7-suite, 34-negative-control pure-OM-2 verification gate (`GATE_MESH PASS checks=7/7 neg_controls=34 hw_writes=0`). |

## Architecture & Wire Protocols

### 1. Compile-on-Arrive Routing Order (`mr_route_select`)
1. **Memo short-circuit:** Query `OMEGA-MEMO` (`mm_lookup`); on hit (`MM_OK`), return `MR_DEC_MEMO_HIT` (`0` recompute, `0` network bytes).
2. **`OMPK` verification:** Verify `pk_buf` via `pk_verify` (fail-closed `MR_ERR_BAD_OMPK`).
3. **Physical contract + `WattCBF` filtering:** For local node `0` and each online, authorized, non-quarantined remote peer:
   - Check `pk_check_contract(tid, feat) == TDK_OK`.
   - Evaluate `WattCBF` (`wc_must_fail_closed` + unclamped `wc_cbf_filter` + `wc_barrier_h >= 0` + `@power` contract cap).
   - Enforce `@hard_deadline` if set.
4. **Profitability selection:** Compare local compute time against remote `RTT + coherence_cost + transfer_us + compute_us + verify_us`. Offload only when local is ineligible (contract/`WattCBF` constrained) or remote saves more than `MR_OFFLOAD_MARGIN_US` (`200 us`). Fail closed (`MR_ERR_NO_NODE`) if no safe node exists.

### 2. Two Verification Tiers (`mesh_verify.om`)

| Tier | Mode | Cryptographic & Integrity Guarantees |
|---|---|---|
| **Tier A** | **Owner Sovereign Mesh** (fast default for your own devices) | Peer pubkey MUST be in the 32B Ed25519 allowlist and not quarantined. Strict RFC 8032 Ed25519 (`mode=0`) signature over 192-byte canonical `OMRC0001` receipt binding `(ompk_sem_id, func_sem_id, inputs_sha256, output_sha256, target_tid, precision_tier, verify_tier, err_bound, nonce, epoch, output_len, compute_ns)`. Anti-replay nonce ring + monotonic epoch floor + one-way precision dominance (`mm_dominates`). Configurable probabilistic/deterministic spot-check re-execution catches silent bit flips even from trusted devices and automatically quarantines the peer. |
| **Tier B** | **Zero-Trust Mode** (untrusted remote silicon before `OMEGA-MEMO` admission) | Strict Ed25519 receipt + binding checks plus mathematical/consensus proof: (1) **Freivalds' randomized matmul check** (`O(R*N^2)` over exact `Z / 2^64 Z`, `R=32` rounds using Linux `getrandom` -> `<= 2^-32` false-positive bound on any 1-element corruption), (2) **Merkle intermediate-state checkpoint verification + `O(log2 M)` binary bisection** pinpointing the exact divergent chunk, or (3) **Dual-peer BFT quorum** requiring two distinct peer pubkeys (`Sybil` same-peer refused) to produce identical `output_sha256` and payload bytes (disagreement triggers fail-closed refusal + quarantine alarm). |

### 3. `OMSH` v1 Wire Frame & `OMRC0001` Receipt Layout
- **`OMSH` v1 Header (32 B):** `[0..3]="OMSH"`, `[4..5]=ver(1)`, `[6..7]=msg_type(1=REQ, 2=RESP, 3=ERR)`, `[8..11]=payload_len`, `[12..15]=flags`, `[16..23]=nonce`, `[24..31]=epoch`.
- **`DISPATCH_REQ` Payload:** `client_pubkey[32] || inputs_sha256[32] || ompk_len[4] || in_len[4] || work_kind[4] || prec_tier[4] || err_bound[8] || target_tid[8] || ompk_bytes || input_bytes || client_ed25519_sig[64]` (mutual authentication over header + payload).
- **`DISPATCH_RESP` Payload:** `status[4] || output_len[4] || aux_len[4] || reserved[4] || OMRC0001_receipt[288] || output_bytes || aux_bytes`.
- **`OMRC0001` Execution Receipt (288 B):** `[0..7]="OMRC0001"`, `[8..39]=ompk_sem_id`, `[40..71]=func_sem_id`, `[72..103]=inputs_sha256`, `[104..135]=output_sha256`, `[136..143]=target_tid`, `[144..147]=precision_tier`, `[148..151]=verify_tier`, `[152..159]=err_bound`, `[160..167]=nonce`, `[168..175]=epoch`, `[176..183]=output_len`, `[184..191]=compute_ns`, `[192..223]=peer_pubkey[32]`, `[224..287]=ed25519_sig[64]` over `[0..192)`.

## Build & Verify (DGX Spark AArch64, Pinned `omc`)

Pinned compiler `seed/out/omc` SHA-256: `85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`.

```sh
DEPS="si/directives/om2.om \
  apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
  seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
  protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
  seed/ng/target/target_desc.om seed/ng/pack/sem_pack.om \
  seed/ng/memo/memo_policy.om seed/ng/memo/memo_store.om \
  apps/omega-mesh/mesh_verify.om apps/omega-mesh/mesh_route.om"

# Build omega-mesh CLI/daemon and standalone verification gate
cat $DEPS apps/omega-mesh/mesh_daemon.om | seed/out/omc > /tmp/omega-mesh
cat $DEPS apps/omega-mesh/gate_mesh.om   | seed/out/omc > /tmp/gate_mesh
chmod +x /tmp/omega-mesh /tmp/gate_mesh

# Exercise CLI & loopback daemon
/tmp/omega-mesh route
/tmp/omega-mesh demo /tmp/omega-mesh-demo
/tmp/omega-mesh check-bind 0.0.0.0   # exits 12 (MR_ERR_WILDCARD_BIND)

# Run full 7-suite verification gate (34 fail-closed negative controls)
/tmp/gate_mesh /tmp/omega-mesh-gate
```

## Verification Scope

- **Status:** `HOST_TESTED` on DGX Spark Linux AArch64 (`7/7` gate suites, `34` fail-closed negative controls, `5/5` source mutation kills, real multi-process TCP loopback dispatch + `OMEGA-MEMO` persistence, `hw_writes=0`).
- **Not claimed:** Physical GB10 GPU kernel execution (`NOT_RUN` — zero GPU device opens) and live multi-host WAN/WireGuard network qualification (`NOT_RUN` — loopback TCP transport exercised natively on Linux AArch64).
