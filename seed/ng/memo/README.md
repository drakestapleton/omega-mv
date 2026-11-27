# `seed/ng/memo/`: Stage 1 — Universal Content-Addressed Memoization (`OMEGA-MEMO`)

> **Pillar 2 of Sovereign Intelligence 2.0.** Pure seeded OM-2 (`.om`) disk-backed content-addressed memoization for structurally verified `@pure` ΩIR v2 functions, enforcing one-way precision dominance, per-`SEMANTIC_ID` profitability filtering, cryptographic verification on every read, uncapped disk sharding, loud disk-floor alarms without silent truncation, and explicit oldest-first pruning.

## Files

| File | Role |
|---|---|
| `memo_policy.om` | Per-`SEMANTIC_ID` profitability profiler (`mp_should_memoize`, `mp_precheck`, explicit `MP_OVR_FORCE` test override), uncapped on-disk store scanner (`mp_scan_store`), loud structured disk-floor alarm (`mp_check_disk_floor`), and explicit oldest-first streaming `mp_memo_prune` (prefix `mp_` / `MP_`). |
| `memo_store.om` | Disk-backed sharded CAS store (`<root>/<2hex>/<64hex>.ome`), purity & contract admission (`mm_check_admission`, `mm_admit_ompk_v2`), one-way precision dominance (`mm_dominates`, `mm_strictly_tighter`), atomic temp+rename writes, fail-closed `output_sha256` + `entry_sha256` verification on every read, and `OMEGA_MEMO_DIR` / `$HOME/.local/share/omega-memo` root resolution (prefix `mm_` / `MM_`). |
| `gate_memo.om` | Standalone pure-OM-2 verification gate testing default env root resolution, ΩIR v2 + OMPK v2 purity admission, true cross-process persistence (`fork` + `execprog`), one-way precision dominance (in-proc & cross-proc), 1-bit output/header tamper & truncation refusals, profitability skipping, uncapped 128+ entry disk scaling, loud disk-floor alarms without silent truncation, explicit `mm_prune`, and optional live `ng` + `ngcheck` `ck_pure` end-to-end integration. |

Both `memo_policy.om` and `memo_store.om` are standalone pure-OM-2-compatible library units (no `om2` header, no `fn main`): they depend only on `seed/ng/sha256.om` and link cleanly either standalone or alongside `seed/ng/src/ir.om` + `seed/ng/pack/sem_pack.om`.

## Keying & One-Way Precision Dominance

Every memoized call is bound to `(func_sem_id [32B], inputs_sha256 [32B], precision_tier [1=@exact, 2=@tol], err_bound [u64])`.

1. **Purity admission (fail-closed):** Both `purity_flag == 1` (`@pure`) and `ck_pure_verified == 1` (structurally verified by `ngcheck.om`) are required on every `mm_lookup` and `mm_store`. Unverified or impure functions fail closed with `MM_ERR_IMPURE (20)`.
2. **Total precision order & one-way dominance (`mm_dominates`):**
   - `@exact` `(tier=1, err=0)` satisfies `@exact` `(1, 0)` and **any** `@tol(eps)` `(2, eps)` with zero recomputation.
   - Tighter `@tol(eps_1)` satisfies looser `@tol(eps_2)` iff `eps_1 <= eps_2`.
   - **NEVER the reverse:** `@tol` (even `@tol(0)`) **never** satisfies `@exact`, and looser `@tol(eps_2)` **never** satisfies tighter `@tol(eps_1)` (`MM_ERR_PRECISION_MISS = 17`).
3. **Monotonic disk upgrade:** Each `(func_sem_id, inputs_sha256)` maps to `<root>/<2hex>/<64hex>.ome` where `base_key = SHA-256("omega.memo.key.v1\0" || func_sem_id || inputs_sha256)`. Storing a strictly tighter precision atomically upgrades the entry; storing a looser precision never downgrades (`MM_OK_DOMINATED = 2`); storing a conflicting `@exact` digest for identical `(func_sem_id, inputs_sha256)` fails closed (`MM_ERR_NONDET = 22`).

## Binary `.ome` Format (`OMEM` v1)

Fixed 224-byte little-endian header followed immediately by `output_bytes[0..output_len)`:

| Offset | Size | Field | Rules |
|---|---|---|---|
| `0..3` | 4 | `magic` | `"OMEM"` (`79, 77, 69, 77`) |
| `4..7` | 4 | `version` | `u32 LE` = `1` |
| `8` | 1 | `purity_flag` | `u8` MUST be `1` |
| `9` | 1 | `precision_tier` | `u8` `1` (`@exact`) or `2` (`@tol`) |
| `10` | 1 | `prov_flags` | `u8` bit 0 = `ck_pure` verified, bit 1 = OMPK v2 verified; bits 2..7 = `0` |
| `11` | 1 | `reserved0` | `u8` MUST be `0` |
| `12..15` | 4 | `reserved1` | `u32 LE` MUST be `0` |
| `16..23` | 8 | `err_bound` | `u64 LE` (`0` when `precision_tier == 1`) |
| `24..55` | 32 | `func_sem_id` | Canonical ΩIR v2 per-function `SEMANTIC_ID` |
| `56..87` | 32 | `inputs_sha256` | FIPS 180-4 SHA-256 of canonical inputs |
| `88..95` | 8 | `output_len` | `u64 LE` (exact file size MUST equal `224 + output_len`) |
| `96..127` | 32 | `output_sha256` | FIPS 180-4 SHA-256 of `output_bytes[0..output_len)` |
| `128..135` | 8 | `prov_created_ns` | `realns` creation timestamp |
| `136..143` | 8 | `prov_compute_ns` | Measured compute duration (ns) |
| `144..151` | 8 | `prov_creator_pid` | Creator process ID |
| `152..159` | 8 | `prov_target_id` | TargetDesc ID (`0` = generic host) |
| `160..191` | 32 | `prov_ir_sha256` | Optional module/OMPK SHA-256 provenance |
| `192..223` | 32 | `entry_sha256` | FIPS 180-4 SHA-256 of header bytes `[0..192)` |
| `224..end` | `output_len` | `output_bytes` | Raw output payload |

Every read opens with `O_NOFOLLOW`, enforces exact length (refusing truncated and trailing-garbage files), verifies key match, verifies `output_sha256`, and verifies `entry_sha256` (defeating both 1-bit payload flips and 1-bit header/precision-tier forgery).

## Disk-Floor Alarm & Uncapped Storage

- **Root resolution:** Explicit caller path (`mm_set_root_from_envbuf`), else `OMEGA_MEMO_DIR`, else `$HOME/.local/share/omega-memo`.
- **No arbitrary entry cap:** Entries live directly in sharded `<root>/<2hex>/<64hex>.ome` files with no fixed slot limit.
- **Disk-floor alarm (`mp_check_disk_floor`):** Walks all shards via `getdnts` + `stat` and checks `store_bytes > max_store_bytes` or `free_bytes < free_floor_bytes`. On breach, emits a loud structured `OMEGA-MEMO ALARM disk_floor ... action=EXPLICIT_PRUNE_REQUIRED` record to `stderr` (and `mp_alarm_buf`) **without silently truncating or modifying any entry**.
- **Explicit pruning (`mm_prune` / `mp_memo_prune`):** Streaming oldest-first (`st_mtim` ascending, path tie-break) eviction in 16-entry passes until `store_bytes <= target_bytes`.

## Build & Verify (Linux AArch64 with pinned `seed/out/omc`)

```sh
cat seed/ng/src/ir.om seed/ng/sha256.om seed/ng/target/target_desc.om \
    seed/ng/pack/sem_pack.om seed/ng/memo/memo_policy.om \
    seed/ng/memo/memo_store.om seed/ng/memo/gate_memo.om \
    | seed/out/omc > /tmp/gate_memo && chmod +x /tmp/gate_memo

# Standalone (Stages 1-7):
/tmp/gate_memo /tmp/omega-memo-gate

# With live ng + ngcheck structural purity integration (Stages 1-8):
/tmp/gate_memo /tmp/omega-memo-gate /path/to/ng /path/to/ngcheck
```
