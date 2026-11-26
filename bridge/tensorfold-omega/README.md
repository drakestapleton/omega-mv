# bridge/tensorfold-omega: Zero-Touch Zig ABI v2 Plugin for TensorFold (`--backend omega`)

Optional, zero-touch drop-in plugin allowing Ash Hart's **`TensorFold`** (Zig local LLM engine) to consume compiled pure seeded-Omega (`OM-2`) subsystems over `omega-bridge` ABI v2 (`omega2_*`) without altering TensorFold's core inference loop, tokenizer, or output tokens.

## What It Provides (Zero Core-Engine Drift)

1. **Zero-Drift Live Arboris MoE Prefetch (`omega2_tf_arboris_observe`, `omega2_tf_arboris_predict`)**:
   - Online Space-Saving `(count << 16) | target_eid` co-activation predictor operating exclusively on caller-owned `[]u32` state.
   - `tf_arboris_predict` accepts `table view uint *` (statically read-only in OM-2) and writes up to 16 predicted next-layer expert IDs to an ABI v2 `out uint 16` buffer — 100% pure prefetch hints, **zero modification to logits or generated tokens**.
2. **SM121 Scoreboard Stall-Floor & Basic-Block Pinning Verifier (`omega2_tf_sm121_check_stall`)**:
   - Enforces Blackwell SM121 `rawFloor >= 6` via an OM-2 executable `requires ge raw_floor 6` contract (traps `9` / `OmegaError.Requires` on any floor `< 6`), checks fixed-latency ALU stall floors (Antibodies #14/#15/#16), RAW spans across a 16-instruction window with WAW early stop, and strict basic-block pinning (`bb_id == orig_bb_id`, monotonic blocks).
3. **Standalone EGP3 Structural Proof Checker (`omega2_tf_egp3_check_cert`)**:
   - Verifies binary `EGP3` single-cert rewrite proofs (`add(mul(a,b), c) = fma(a,b,c)`) before realizing fused kernels.
4. **Byte-Traceable Identity & Fail-Closed Lock (`omega2_ident_tf_omega_unit`, `omega2_tf_omega_ident`, `tf_lock_verify.om`)**:
   - Pins exact SHA-256 digests across `.om` source, `omc` compiler, `EGP3` cert, emitted AArch64 `.bin`, ABI v2 `.c`, ELF `.o`, and Zig binding (`TF_OMEGA.lock` + `CHAIN_ROOT_SHA256`), failing closed on any 1-bit drift (`exit 100..108`).

## 60-Second Omega Rosetta Card (Prefix `.om` <-> Zig)

| Concept | Pure Seeded Omega (`.om`, OM-2) | Zig (`omega_plugin.zig`) |
| --- | --- | --- |
| Read-only slice | `cur_ids view uint *` (`len cur_ids`) | `cur_ids: []const u32` (`ptr`, `len`) |
| Mutable slice | `table edit uint *` | `table: []u32` (`ptr`, `len`) |
| Isolated output | `pred out uint 16` (copied ONLY on status `0`) | `var pred: [16]u32` (untouched on trap) |
| Executable contract | `requires ge raw_floor 6` (Trap 9) | `OmegaError.Requires` (`status == 9`) |
| Prefix arithmetic | `add mul a b c` | `a *% b +% c` |
| Checked index | `get table add base h` (Trap 3 OOB) | `OmegaError.Bounds` (`status == 3`) |
| Alias / null guard | Automatic in ABI v2 (`ombr2_overlap`) | `OmegaError.InvalidOrAlias` (`status == 32`) |

## Zero-Touch `--backend omega` Integration in TensorFold (`build.zig`)

TensorFold keeps its existing default engine untouched. When the user passes `-Dbackend=omega` (or `--backend omega` at runtime):

1. Build and verify the locked static archive once via `sh bridge/tensorfold-omega/gate_tf_omega.sh` (producing `libtf_omega_native.a` and `TF_OMEGA.lock`).
2. Link `libtf_omega_native.a` in TensorFold's `build.zig` behind an optional flag:
   ```zig
   const use_omega = b.option(bool, "omega", "Enable optional pure-Omega ABI v2 plugin") orelse false;
   if (use_omega) {
       exe.addObjectFile(b.path("vendor/tensorfold-omega/libtf_omega_native.a"));
       exe.linkLibC();
       exe.root_module.addAnonymousImport("omega_plugin", .{
           .root_source_file = b.path("vendor/tensorfold-omega/src/omega_plugin.zig"),
       });
   }
   ```
3. Call it strictly as an advisory prefetcher / verifier hook:
   ```zig
   const omega = @import("omega_plugin");
   try omega.verifyIdent(EXPECTED_LOCK_IDENT);
   _ = try prefetcher.observe(prev_expert, active_experts);
   const hints = try prefetcher.predict(active_experts);
   // Issue async DMA/prefetch for hints.slice(); never alter MoE routing or logits.
   ```

## Verification (DGX Spark, Linux AArch64)

```sh
sh bridge/tensorfold-omega/gate_tf_omega.sh
```
