# `seed/ng/replay/` — Stage 2 (Pillar 4): Reversible & Counterfactual Time-Travel Execution

Pure seeded OM-2 (`.om`) implementation of Sovereign Intelligence 2.0 Stage 2:
hash-chained `tok`-boundary journaling, periodic `SLAB`+VM checkpointing, live
`ngrun` trap-to-cause backwards stepping, multi-branch counterfactual forking,
and compact semantic state-stream delta reconstruction.

## Files

| File | Purpose |
|---|---|
| `tok_journal.om` | Hash-chained `tok`-boundary effect journal (`"OTKJ"` v1, SHA-256 chain) backed by growable OM-2 run-time pools (`global ... *`, no small hard cap), disk file persistence, direct unbounded streaming writer, configurable byte alarm threshold, and fail-closed verification. |
| `slab_ckpt.om` | Periodic `SLAB` + VM register/PC checkpointing using hybrid keyframes + sparse deltas in growable run-time pools. Every checkpoint stores a 32-byte SHA-256 digest of full logical state; `sck_restore_nearest` jumps directly to the nearest checkpoint `<= target_step` and fails closed on any 1-bit corruption. |
| `cf_fork.om` | Counterfactual fork engine running deterministic baseline timelines over `SLAB` + `tok_journal` + `slab_ckpt`, then forking `>= 16` (18 in matrix) isolated branches from checkpoint `T` with mutated `tok` events (12 W power drop 300 ms earlier, delayed/dropped network packet `#42`, sensor faults, SLAB store perturbation) and reporting the exact first causal divergence `(step, block, op_idx, tok_seq, field_mask, base_val, cf_val, slab_off)`. |
| `state_stream.om` | Compact semantic state-stream delta codec (`"OSTM"` v1) coalescing contiguous mutated SLAB byte spans + changed registers per `tok` frame with per-frame full-state SHA-256 verification. Shrinks multi-megabyte raw state dumps to kilobytes with bit-exact reconstruction. |
| `gate_replay.om` | Standalone pure-OM-2 verification gate covering all 5 stages (in-process journal/checkpoint/18-branch counterfactual/state-stream + live `ngrun` trap-to-cause backwards stepping & regression checks) and 12 fail-closed negative controls. |

Also adds a cleanly-gated additive hook in `seed/ng/ngrun.om` (`--journal PATH`,
`--rewind`, `--ckpt-every N`) that leaves standard `ngrun` behavior, exit codes,
stderr, and all `gate-ir` / `gate-front-ir` mutant checks 100% unchanged.

## Wire Formats

### `"OTKJ"` v1 (`tok_journal.om` and `ngrun --journal`)
- **Header (16 B, little-endian):** `magic[4] = "OTKJ"`, `version u8 = 1`, `flags u8 = 0`, `reserved u16 = 0`, `entry_count u64`.
- **Entry (`85 + payload_len` B, little-endian):**
  `seq u64`, `op_kind u8 (1..13)`, `block_id u32`, `op_idx u32`, `payload_len u32`,
  `payload_bytes[payload_len]`, `prev_hash[32]`, `entry_hash[32]`.
- **Chain Hash:** `entry_hash = SHA-256("OTKJ1\0" || seq || op_kind || block_id || op_idx || payload_len || payload_bytes || prev_hash)`.
- **Fail-closed refusals:** bad magic (`1`), version/reserved (`2`), truncation (`3`), trailing bytes (`4`), non-monotonic/duplicate `seq` (`5`), unknown `op_kind` (`6`), broken `prev_hash` chain (`7`), digest mismatch (`8`).

### `"OSTM"` v1 (`state_stream.om`)
- **Header (24 B, little-endian):** `magic[4] = "OSTM"`, `version u8 = 1`, `reserved[3] = 0`, `n_regs u32`, `slab_size u32`, `frame_count u64`.
- **Frame:** `frame_seq u64`, `tok_seq u64`, `reg_delta_cnt u16` + `(reg_idx u16, val u64)*`, `span_cnt u32` + `(off u32, slen u16, bytes[slen])*`, `state_hash[32] = SHA-256("OSTM1\0" || n_regs || slab_size || regs || slab)`.

## Live `ngrun` Backwards Stepping (Target 1)

```sh
# Build ngrun (unchanged 2-unit composition)
cat seed/ng/src/ir.om seed/ng/ngrun.om | seed/out/omc > ngrun && chmod +x ngrun

# Run any ΩIR program with periodic SLAB checkpoints + trap-to-cause rewind + OTKJ journal
./ngrun prog.ir --rewind --ckpt-every 4 --journal /tmp/run.otkj
```

When the program hits an explicit trap (`chk.bounds`, `chk.divz`, `chk.add`, `chk.sub`, `chk.mul`, `chk.conv`, `chk.fuel`, `chk.true`, `trap`, etc.), `ngrun` jumps to the nearest checkpoint before the trap step, replays forward to verify bit-exact parity (`replay_parity=EXACT`), walks backwards across SSA definitions, `br` block parameters, `call` arguments, and `load`→`store` memory dependencies (stepping back across checkpoint windows as needed), emits a structured `ngrun-rewind:` causal report on stderr, flushes the SHA-256 `"OTKJ"` v1 journal, and exits with the exact trap code (`100 + code`).

## Building & Running the Verification Gate (Linux AArch64)

```sh
cat seed/ng/src/ir.om seed/ng/sha256.om \
    seed/ng/replay/tok_journal.om \
    seed/ng/replay/slab_ckpt.om \
    seed/ng/replay/cf_fork.om \
    seed/ng/replay/state_stream.om \
    seed/ng/replay/gate_replay.om | seed/out/omc > /tmp/gate_replay
chmod +x /tmp/gate_replay

mkdir -p /tmp/replay_scratch
/tmp/gate_replay /tmp/ngrun /tmp/replay_scratch
```
