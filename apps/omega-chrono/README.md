# `omega-chrono` — Time-Travelling Speculative Counterfactual Compiler (`alien-chrono`)

> **Plain-English Summary:** Before committing a faster optimization on your hardware, `omega-chrono` takes a cryptographically hashed snapshot (`SLAB` + `OTKJ`) of your exact starting state, forks three candidate timelines in parallel OS child processes (exact baseline, `EGP3` algebraic optimization, and low-power `WattCBF` safe schedule), rejects anything unsafe or unproven, saves verified sub-results into `OMEGA-MEMO`, atomically swaps only the proven winner via strict `W^X` (`0500 RX`) memory protection, and—if out-of-domain drift ever occurs—refuses to poison the memo cache and rewinds state back to the exact `T0` checkpoint bit-for-bit.

---

## Side-by-Side Comparison

| Property | Traditional Speculative JIT | `omega-chrono` (`chrono_forge.om`) |
|---|---|---|
| **Rollback Safety** | Ad-hoc patches; partial writes can leak on bailout | Stage 2 `SLAB` checkpoint + hash-chained `OTKJ` journal rewind (`state_hash(post_rewind) == state_hash(T0)`) |
| **Optimization Proofs** | Heuristic trust | Independent zero-shared-code `EGP3` structural rewrite checker (`egp3_checker.om`) |
| **Thermal / Power Guard** | Post-hoc thermal throttling | Pre-promotion discrete `WattCBF` filter (`P_gpu < 80,000 mW`, barrier `h >= 0`) |
| **Precision Accounting** | Silent precision drift | One-way dominance monotonicity (`@exact -> @tol` allowed, `@tol -> @exact` strictly refused) |
| **Executable Permissions** | Often `PROT_WRITE \| PROT_EXEC` (`RWX`) JIT buffers | Strict `W^X`: `0600 RW -> FIPS 180-4 SHA-256 readback -> fchmod 0500 RX -> rename`, `--rwx` refused (`rc=2`) |
| **OOD Cache Protection** | Speculative results risk poisoning shared caches | `SLAB_MUTABLE_ALARMED` (`CR_ERR_ALARM`) + OOD/impure guards refuse `OMEGA-MEMO` (`OMEM`) writes |
| **Implementation Stack** | C/C++/Python/LLVM | **100% pure seeded OM-2** compiled by `seed/out/omc` + **Lean 4.36.0** formal soundness (`0 sorry`) |

---

## Files Owned by `omega-chrono`

- [`apps/omega-chrono/chrono_forge.om`](chrono_forge.om): Time-Travelling Speculative Counterfactual Compiler CLI (`status`, `forge`, `probe-watt`, `probe-dom`, `probe-ood-memo`, `--rwx`).
- [`apps/omega-chrono/gate_chrono.om`](gate_chrono.om): Pure seeded OM-2 verification suite (in-process checks + `>= 7` negative controls + live 2x deterministic `omc` compilation + disk `W^X`/`OTKJ`/`OMEM` verification + 3 `omc`-recompiled source-mutant kills).
- [`seed/helix/proofs/ChronoSoundness.lean`](../../seed/helix/proofs/ChronoSoundness.lean): Machine-checked Lean 4.36.0 proof (`-DwarningAsError=true`, `0 sorry`, standard axioms only) covering fork isolation, one-way dominance monotonicity, exact `SLAB` rewind equivalence, `WattCBF < 80 W` preservation, plus concrete `decide` negative controls.
- [`evidence/ALIEN-CHRONO-FORGE-20261127/`](../../evidence/ALIEN-CHRONO-FORGE-20261127/RECEIPT.txt): Content-addressed verification receipt (`RECEIPT.txt` and `SHA256SUMS.txt`).

---

## Architecture & Pipeline

1. **Epoch `T0` Anchor (`chf_anchor_t0`):**
   - Initializes `slab_ckpt.om` (`sck_init`, `sck_take`), captures the exact 32-byte `T0` state hash (`chf_t0_hash`), appends a hash-chained `OTKJ` checkpoint marker (`tok_journal.om`), and emits an initial `state_stream.om` checkpoint frame.
2. **3-Timeline Parallel Counterfactual Fork (`chf_fork_all_timelines`):**
   - Spawns isolated child processes over `fork` + `pipefds` + `waitpid` plus an explicit `cf_fork.om` divergence analyzer:
     - **Timeline A (`@exact`):** Baseline AArch64 ELF64 binary (`50 W` total, `0 W` GPU, latency `14,000`).
     - **Timeline B (`@tol(8)`, `EGP3`-optimized):** Proven 4-step `EGP3` algebraic optimization (`52 W` GPU, `72 W` total, latency `4,200`) with embedded OOD `trap 14` domain guard (`x1 > 100 -> exit 114`).
     - **Timeline C (`@tol(12)`, `WattCBF` low-power):** Proven 3-step `EGP3` schedule (`0 W` GPU, `22 W` total, latency `9,500`) with OOD `trap 14` guard.
3. **Live `WattCBF` + `EGP3` + One-Way Dominance Arbitration (`chf_arbitrate_and_promote`):**
   - Evaluates live Linux thermal sensors via `watt_sense.om` (`hw_writes=0`) and `watt_cbf.om` (`P_gpu < 80,000 mW`, `h >= 0`).
   - Under normal thermal headroom (`~48.9 C`), Timeline B wins (`winner=B`, `72,000 mW`). Under thermal pressure (`--hot`, `77.5 C` die / `78.0 C` ceiling) or `--power-cap 60000`, `WattCBF` rejects Timeline B and automatically promotes Timeline C (`winner=C`, `22,000 mW`).
   - Harvests verified pure sub-results into `OMEGA-MEMO` (`OMEM` v1 CAS store), confirms `@exact` satisfies `@tol(16)` (`MM_OK`, zero recompute), and refuses `@tol(8) -> @exact` (`MM_ERR_PRECISION_MISS`).
4. **Strict `W^X` Seal & `fabHotSwap` (`cfw_stage_and_seal`):**
   - Emits static AArch64 ELF64 (`isel.om` + `sm121_pe.om`) with a single `PT_LOAD` `R E` segment (`p_flags == 5`, zero `PF_W`), stages `0600 RW -> SHA-256 readback check -> fchmod 0500 RX -> atomic rename`, and promotes the winning slot via `fabHotSwap` + `cpufence`.
5. **OOD Drift Injection & Exact `T0` Rewind (`chf_run_ood_and_rewind`):**
   - Executes the promoted binary on out-of-domain input (`x1 = 150 > 100`) triggering `trap 14` (`ood_exit=114`), mutates live registers/SLAB, strictly refuses an OOD write to `OMEGA-MEMO` (`memo_poison_refused=1`, CAS store count unchanged), trips `SLAB_MUTABLE_ALARMED` (`CR_ERR_ALARM`, while `SLAB_IMMUTABLE` rejects writes with `CR_ERR_IMMUTABLE`), rolls back `fabHotSwap` to Timeline A (`0500 RX`), restores `sck_restore_id 0`, verifies `state_hash(post_rewind) == state_hash(T0)` (`t0_hash_eq=1`), and recomputes the exact fallback result (`ood_fallback_out=133`).

---

## Build & Verify (DGX Spark AArch64 Linux, Pinned `seed/out/omc`)

```bash
DEPS="si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om seed/ng/sha256.om seed/ng/target/target_desc.om seed/ng/target/isel.om seed/ng/target/sm121_pe.om seed/ng/target/fabric.om seed/ng/target/crystallize.om seed/ng/pack/sem_pack.om seed/ng/verify/egp3_checker.om seed/ng/live/arboris_spec.om seed/ng/replay/tok_journal.om seed/ng/replay/slab_ckpt.om seed/ng/replay/cf_fork.om seed/ng/replay/state_stream.om seed/ng/memo/memo_policy.om seed/ng/memo/memo_store.om seed/ng/physics/pareto_bank.om seed/ng/physics/phys_solver.om apps/omega-metabd/profile_ring.om"

# 1. Build chrono_forge and gate_chrono with pinned seed/out/omc
cat $DEPS apps/omega-chrono/chrono_forge.om | ./seed/out/omc > chrono_forge && chmod +x chrono_forge
cat $DEPS apps/omega-chrono/gate_chrono.om | ./seed/out/omc > gate_chrono && chmod +x gate_chrono

# 2. Run strict W^X refusal, status, normal forge, and --hot thermal shift
./chrono_forge --rwx        # exits 2 (PROT_WRITE|PROT_EXEC forbidden)
./chrono_forge status       # live thermal readback, hw_writes=0
./chrono_forge forge --dir /tmp/chrono-run --ood
./chrono_forge forge --dir /tmp/chrono-hot --hot --ood

# 3. Run full pure-OM-2 gate (in-process + live 2x omc + 22 negative controls + 3 source mutants)
./gate_chrono
./gate_chrono ./seed/out/omc . /tmp/chrono-gate-scratch

# 4. Machine-checked Lean 4.36.0 proof verification
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/ChronoSoundness.lean
```

---

## Verification Scope & Honest Status

| Target / Check | Verdict | Scope / Notes |
|---|---|---|
| `seed/out/omc` 2x deterministic build (`chrono_forge`, `gate_chrono`) | **HOST-VERIFIED (Spark AArch64)** | `cmp -s` exit `0`, zero stderr, pinned `85b84c6d...` |
| `gate_chrono` (standalone & full 4-arg) | **HOST-VERIFIED (Spark AArch64)** | `checks=63`, `neg_controls=22`, `caught=22`, `mutants_killed=3`, `cmp_eq=1`, `hw_writes=0` |
| `seed/helix/proofs/ChronoSoundness.lean` | **LEAN-VERIFIED (Lean 4.36.0)** | `-DwarningAsError=true` exit `0`, `0` warnings, `0` `sorry`, standard axioms only |
| `tests/gates/run.sh zero-disk-secrets` | **HOST-VERIFIED** | `0` plaintext `.env` findings |
| GB10 Physical GPU Silicon | **`NOT_RUN`** | Zero GPU device writes (`hw_writes=0`); no UEFI/SPI/driver changes |
