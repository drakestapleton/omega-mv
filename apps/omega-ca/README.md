# `omega-ca` — Lean-4-Proven Bit-Reversible Lossless Cellular Automaton (`OMCA01`)

## Plain-English Overview

Most computer simulations are **one-way streets**. When a standard simulation overwrites grid cells or drops carries, information is destroyed — by Rolf Landauer's principle, erasing a single bit irreversibly dissipates at least $k_B T \ln 2$ of heat and makes it impossible to recover the exact starting grid from the final state alone.

**`omega-ca` works like a frictionless billiard-ball table.** Every two-by-two block of cells follows the reversible **Margolus Billiard-Ball Model (BBM)**: isolated balls keep moving cleanly along their diagonals, two balls colliding head-on bounce apart at 90 degrees, and every particle present at step `0` is still present at step `T` — nothing is ever created, merged, or erased. Because the local `2×2` rule is a strict mathematical bijection (`invBlock (fwdBlock x) = x`), you can run a lattice forward `T` generations, save the `OMCA01` checkpoint, run it backward `T` generations, and get back the **exact byte-identical starting lattice** (`0-byte diff`, matching `SHA-256`).

No C, Python, Rust, or `gcc` is used anywhere in the stack: the IR emitter, the `@ng opt` + `@ng a64` static worker binary, the multi-core coordinator, and the self-test gate are written in 100% pure seeded `.om` and cross-checked by machine-verified theorems in Lean 4.

## Lossy Simulations vs. `OMCA01` Reversible Compute

| Property | Typical Irreversible / Lossy CA | `omega-ca` (`OMCA01` + BBM) |
|---|---|---|
| Transition bijection | Many-to-one (information erased every step) | **1-to-1 involution** (`fwdBlock (fwdBlock x) = x`) proven in Lean 4 |
| Logical bit erasure | Yes (irreversible state merges) | **Zero logical erasure** within BBM rules |
| Particle conservation | Optional / drifts | **Exact per-step invariant** (`gridPop(t) = gridPop(0)` every step) |
| Exact time reversal | Impossible without full history log | **Bit-exact recovery** of `T0` state and `SHA-256` from final frame + step count |
| Parallel halo splitting | Approximate boundary drift | **Proven exact** light-cone halo theorem (`evolveFrom_halo_sound`), `0-byte diff` vs. scalar |
| Implementation stack | Usually C / C++ / Python glue | **100% pure seeded `.om`** (`seed/out/omc` + `@ng opt`/`@ng a64` static ELF, `PT_DYNAMIC = 0`) |

## `OMCA01` Canonical Container Layout

Every serialized lattice file has an exact `72`-byte little-endian header followed immediately by `payload_bytes = (width / 8) * height` bytes of row-major packed `u64` lattice bits (`width % 64 == 0`, `height % 2 == 0`):

| Offset | Size | Field | Validation Rule & Fail-Closed Exit Code |
|---|---|---|---|
| `0x00` | `6` | `magic` | Exact ASCII `"OMCA01"` (else exit `66`) |
| `0x06` | `1` | `version` | Exact `1` (else exit `66`) |
| `0x07` | `1` | `rule_id` | Exact `1` = Margolus BBM `2×2` (else exit `66`) |
| `0x08` | `4` | `width` | `64 <= width <= 4096`, `width % 2 == 0`, `width % 64 == 0`, `(width/64)*height <= 65536` (else exit `63`) |
| `0x0c` | `4` | `height` | `2 <= height <= 2048`, `height % 2 == 0` (else exit `63`) |
| `0x10` | `8` | `step` | Unsigned generation counter `t >= 0` (`reverse N` requires `N <= step`, else exit `69`) |
| `0x18` | `8` | `popcount` | Recomputed `popcount(lattice)` must equal header before & after every run (else `65` / `61`) |
| `0x20` | `8` | `payload_bytes` | Must equal `(width / 8) * height` and `file_size == 72 + payload_bytes` (else exit `67`) |
| `0x28` | `32` | `state_sha256` | FIPS 180-4 SHA-256 of canonical `lattice_bits`; checked before execution (else exit `64`) |
| `0x48` | `payload_bytes` | `lattice_bits` | Row-major `u64` words (`bit (x & 63)` in word `x / 64` of row `y`) |

Distinct fail-closed exit codes: `61` popcount conservation violation, `62` reversibility SHA-256 mismatch, `63` invalid/odd lattice dimensions, `64` tampered `state_sha256`, `65` header `popcount` mismatch, `66` bad `magic`/`version`/`rule_id`, `67` truncated/oversized file, `68` worker subprocess fault exit (`49`) caught via `waitpid`/pipe check, `69` reverse step underflow, `70` file/CLI usage error.

## Files in This Slice

- [`apps/omega-ca/emit_ca_ir.om`](emit_ca_ir.om) — Pure OM-2 generator emitting binary ΩIR (`OSC1IR` v9, `omega.ng.ir.v1`) for the static `ca_worker` binary, with explicit constant-bound guards unlocking `@ng opt` BCE (`bce=39`) and loop rotation (`rotated=20`), compiled to static AArch64 ELF via `@ng a64`.
- [`apps/omega-ca/ca_engine.om`](ca_engine.om) — Pure OM-2 coordinator (`init`, `inspect`, `evolve`, `reverse`, `verify`, `selftest`, `bench`), implementing both a cell-by-cell scalar OM-2 BBM oracle and a pinned Grace worker pool (`pipefds` + `fork` + `dupfd` + `cpuset` + `execprog` + `waitpid`).
- [`apps/omega-ca/gate_ca.om`](gate_ca.om) — Standalone pure OM-2 verification gate checking 2× deterministic builds, `ngcheck`, `@ng opt-count`, `PT_DYNAMIC == 0`, positive collider `T=64`/`T=128` round-trips, `scalar == W=1 == W=10 == W=20` `0-byte diff`, and 9 fault-injection/negative controls (`exit 61..69`).
- [`seed/helix/proofs/CaReversibleSoundness.lean`](../../seed/helix/proofs/CaReversibleSoundness.lean) — Lean 4.36.0 machine-checked proofs (`0` warnings, `0` `sorry`, standard axioms only).
- [`evidence/WAVE4-REVERSIBLE-CA-20261127/RECEIPT.txt`](../../evidence/WAVE4-REVERSIBLE-CA-20261127/RECEIPT.txt) & [`SHA256SUMS.txt`](../../evidence/WAVE4-REVERSIBLE-CA-20261127/SHA256SUMS.txt) — Immutable verification receipt and SHA-256 manifest.

## Lean 4 Verification Scope

Verified on Spark (`Lean 4.36.0`, `lean -DwarningAsError=true`) with zero warnings and zero `sorryAx`:
- **Block & SWAR soundness**: `fwdBlock_involutive`, `invBlock_fwdBlock`, `fwdBlock_invBlock`, `fwdBlock_injective`, `fwdBlock_surjective`, `fwdBlock_conserves_pop`, `invBlock_conserves_pop`, `swarBlock_eq_fwdBlock` (verifying the branchless 64-bit SWAR formula matches `fwdBlock` for all `16` `2×2` configurations).
- **Toroidal grid multi-step reversibility & particle conservation**: `unshift_shift_grid`, `shift_unshift_grid`, `stepRev_stepFwd`, `stepFwd_stepRev`, `reverseFrom_evolveFrom`, `stepFwd_conserves_pop`, `evolveFrom_conserves_pop`, `reverseFrom_conserves_pop`.
- **Parallel halo light-cone soundness**: `stepEven_preserves_even_strip`, `stepFwd_light_cone`, `evolveFrom_halo_sound` (proving interior owned rows stay bit-identical when evolved over halo-padded strips).
- **Executable negative & positive controls**: `pos_ctrl_6x6_collider_roundtrip`, `neg_ctrl_broken_rule_fails`, `neg_ctrl_odd_dims_refused`, `neg_ctrl_container_tampers_refused`.

## Reproducible Build & Verification Commands (AArch64 Linux Host)

```bash
# 1. Build ngcheck and ng from seed/ng/ manifests (requires seeded seed/out/omc via `sh seed/omega-from-seed.sh`)
awk '{print $2}' seed/ng/ngcheck.units | xargs cat | seed/out/omc > ngcheck && chmod +x ngcheck
awk '{print $2}' seed/ng/ng.units | xargs cat | seed/out/omc > ng && chmod +x ng

# 2. Build static @ng a64 worker (ca_worker) via emit_ca_ir.om
seed/out/omc < apps/omega-ca/emit_ca_ir.om > emit_ca_ir && chmod +x emit_ca_ir
./emit_ca_ir > ca_worker.ir
./ngcheck < ca_worker.ir
{ printf '@ng opt-count\n'; cat ca_worker.ir; } | ./ng
{ printf '@ng opt\n'; cat ca_worker.ir; } | ./ng > ca_worker.opt.ir
./ngcheck < ca_worker.opt.ir
{ printf '@ng a64\n'; cat ca_worker.opt.ir; } | ./ng > ca_worker && chmod +x ca_worker
readelf -d ca_worker   # expects: There is no dynamic section in this file.

# 3. Build pure OM-2 engine and gate
cat si/directives/om2.om seed/ng/sha256.om apps/omega-ca/ca_engine.om | seed/out/omc > ca_engine && chmod +x ca_engine
cat si/directives/om2.om apps/omega-ca/gate_ca.om | seed/out/omc > gate_ca && chmod +x gate_ca

# 4. Run end-to-end gate, selftest, med9 benchmark, and Lean proof check
mkdir -p /tmp/ca-gate && ./gate_ca --omc seed/out/omc --ng ./ng --ngcheck ./ngcheck --srcdir apps/omega-ca --om2 si/directives/om2.om --sha seed/ng/sha256.om --workdir /tmp/ca-gate
./ca_engine selftest --worker ./ca_worker
./ca_engine bench --worker ./ca_worker
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/CaReversibleSoundness.lean
```

## Honest Scope & Limits

- **Qualification status**: `HOST-VERIFIED` on DGX Spark AArch64 Grace Linux (`10× Cortex-X925 @ 3900 MHz` + `10× Cortex-A725 @ 2808 MHz`) and `LEAN-VERIFIED` on `Lean 4.36.0` (`-DwarningAsError=true`).
- **Physical GB10 GPU**: `NOT_RUN` — this slice runs purely on the AArch64 Grace CPU and worker pool (`ca_worker` emits AArch64 ELF via `@ng a64`; it does not open `/dev/nvidia*`).
- **Physical thermodynamics**: "zero Landauer erasure" describes the **logical transition function** (`fwdBlock` is bijective and preserves `popcount` and state entropy); physical CMOS switching in the CPU still dissipates real circuit energy.
- **Dimension constraints**: Margolus `2×2` neighborhood partitioning requires even dimensions (`width % 2 == 0`, `height % 2 == 0`), SWAR bit-packing requires `width` in multiples of `64` (`64..4096`), and single-worker static buffers cap `words <= 65536` (`512 KiB` per lattice).
