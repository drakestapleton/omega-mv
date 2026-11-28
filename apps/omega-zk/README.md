# `apps/omega-zk`: Pure Seeded-Omega Goldilocks Fiat-Shamir STARK / FRI (`OMZK01`)

> **Plain-English Summary:** Imagine checking a 32-step math ledger without re-running all 32 steps from scratch—or letting someone hide a bogus step in the middle. `omega-zk` acts like a tamper-evident sealed receipt for an entire calculation: it encodes the computation table as low-degree polynomials over the 64-bit Goldilocks prime field (`p = 2^64 - 2^32 + 1`), locks every trace and constraint column inside SHA-256 Merkle trees, derives non-interactive verifier challenges strictly from a domain-separated Fiat-Shamir transcript hash chain, and folds the combined polynomial down 6 rounds via FRI until only a single constant remains. Any non-canonical field value (`>= p`), wrong output claim, altered intermediate step, degree cheat, forged Merkle sibling, or transcript swap is rejected fail-closed by an independent verifier binary that holds zero prover state.

---

## Side-by-Side Comparison

| Property | Ad-Hoc Execution Check | `omega-zk` (`goldilocks_stark.om`) |
|---|---|---|
| **Arithmetic Field** | 64-bit wrapping integers (overflows silently) | Exact 128-bit modular multiplication in Goldilocks prime field `p = 2^64 - 2^32 + 1` (`18446744069414584321`), canonical `< p` enforced on every word |
| **Computation Model** | Re-run raw steps imperatively | 32-step cubic MiMC-Fibonacci AIR (`x_{t+1} = y_t`, `y_{t+1} = y_t^3 + x_t + rc_t mod p`) with boundary + transition quotient constraints over coset domain `D` (`256` points, `8x` blowup) |
| **Commitments** | Unhashed / mutable trace buffers | Domain-separated FIPS 180-4 SHA-256 Merkle trees (`trace_root`, `comp_root`, `fri_root[1..5]`) with depth-prefixed sibling paths |
| **Verifier Randomness** | Interactive or hardcoded test vectors | Tagged injective Fiat-Shamir SHA-256 chain (`"OMEGA-ZK-STARK-GL64-V1"`) absorbing public statement + roots + OOD values before every challenge squeeze |
| **Low-Degree Proof** | None (trusts trace degree) | DEEP-ALI out-of-domain evaluation at `zeta ∉ H ∪ D` + 6-round FRI `2-to-1` folding (`256 -> 128 -> 64 -> 32 -> 16 -> 8 -> 4`) + `16` query openings |
| **Container Format** | Unframed / variable ad-hoc blobs | Fixed `44,408 B` `OMZK01` binary container; exact length + version + domain check + `< p` range check on all field words |
| **Implementation Stack** | Rust/C++/Python ZK libraries | **100% pure seeded OM-2** (`seed/out/omc`) + **Lean 4.36.0** formal soundness (`0` warnings, `0 sorry`, standard axioms only) |

---

## Files Owned by `omega-zk`

- [`apps/omega-zk/goldilocks_stark.om`](goldilocks_stark.om): Standalone pure-OM-2 Goldilocks STARK/FRI prover, fail-closed verifier, container inspector, and field/NTT self-test (`selftest`, `prove`, `verify`, `inspect`).
- [`apps/omega-zk/gate_zk.om`](gate_zk.om): Pure-OM-2 verification harness checking `omc` SHA-256 pin (`exit 69` on mismatch), `2x` deterministic `omc` builds, static ELF64 verification (zero `PT_DYNAMIC`), cross-run verification independence (`stark_1` proves, separate `stark_2` verifies), parameterized proofs, `18` attack controls across `7` threat classes, and `5` live `omc`-recompiled prover/verifier mutants.
- [`seed/helix/proofs/ZkTranscriptSoundness.lean`](../../seed/helix/proofs/ZkTranscriptSoundness.lean): Machine-checked Lean 4.36.0 proof (`-DwarningAsError=true`, `0` warnings, `0 sorry`, standard axioms only) covering Goldilocks modulus identities (`2^64 ≡ 2^32 - 1`, `2^96 ≡ -1`), 128-bit reduction congruence, overflow-safe `glAdd`/`glSub`, canonical uniqueness `< p`, inverse uniqueness, injective Fiat-Shamir frame & multi-frame absorption, FRI `2-to-1` folding preservation, AIR quotient soundness, and concrete `decide` negative witnesses.
- [`evidence/WAVE4-ZK-STARK-20261127/`](../../evidence/WAVE4-ZK-STARK-20261127/RECEIPT.txt): Content-addressed verification receipt (`RECEIPT.txt` and `SHA256SUMS.txt`).

---

## How Each Layer Works

1. **Goldilocks Field (`p = 2^64 - 2^32 + 1`):**
   - Multiplication splits two `64`-bit inputs into `32`-bit limbs, builds the exact `128`-bit product `(hi, lo)` without 64-bit overflow, and reduces `(h1 * 2^96 + h0 * 2^64 + lo)` using `2^96 ≡ -1 (mod p)` and `2^64 ≡ 2^32 - 1 (mod p)`.
   - Notice `(2^32 - 1)^2 < p`, so `h0 * (2^32 - 1)` never needs a second reduction, and `gl_add` subtracts `p - b` cleanly whenever `a >= p - b` so `a + b` never wraps `2^64`.
   - Every deserialized word is checked `< GL_P` (`ZK_ERR_NONCANON = 61`) before any arithmetic so `val = GL_P` can never impersonate `0`.
2. **AIR & DEEP-ALI Composition (`N = 32`, `D = 256`):**
   - Interpolates trace columns `X, Y` and round constants `RC` over primitive `32`-nd root `ZK_G32 = 70368744161280` (`INTT`), evaluates on coset `7 * <ZK_W256>` (`ZK_W256 = 13797081185216407910`, `7^256 != 1 mod p` so `D ∩ H = ∅`).
   - Forms degree-`< 64` composition polynomial `C(z)` from `4` boundary constraints and `2` cubic transition constraints, commits `trace_root` and `comp_root`, samples `zeta ∉ H ∪ D`, verifies `C(zeta) == AIR(zeta)`, and constructs the degree-`< 64` DEEP quotient `F_0(z)`.
3. **6-Round FRI & `OMZK01` Container (`44,408` bytes):**
   - Folds `F_0 -> F_1 -> ... -> F_6` (`256 -> 128 -> 64 -> 32 -> 16 -> 8 -> 4`), committing `fri_root[1..5]` to Fiat-Shamir before squeezing each next folding challenge `gamma_r`, then absorbs `fri_final[0..3]` before squeezing `16` query indices.
   - `verify` loads the `44,408`-byte `OMZK01` file with zero prover state, verifies all header/canonical bounds (`60`/`61`), public statement flags (`62`), constant `fri_final` (`65`), OOD identity (`63`), all `16` Merkle opening paths across `7` trees (`64`), and every FRI fold consistency check (`65`).

---

## Build & Verify (DGX Spark AArch64 Linux, Pinned `seed/out/omc`)

```bash
# 1. Extract pinned omc (expected sha256: 85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134)
git -C ~/git/omega-mv.git show main:seed/out/omc > /tmp/zk-omc && chmod +x /tmp/zk-omc

# 2. Build goldilocks_stark and gate_zk deterministically
cat si/directives/om2.om seed/ng/sha256.om apps/omega-zk/goldilocks_stark.om | /tmp/zk-omc > /tmp/zk-stark && chmod +x /tmp/zk-stark
cat si/directives/om2.om seed/ng/sha256.om apps/omega-zk/gate_zk.om | /tmp/zk-omc > /tmp/zk-gate && chmod +x /tmp/zk-gate

# 3. Run standalone prover, verifier, and container inspector
/tmp/zk-stark selftest
/tmp/zk-stark prove --out /tmp/proof.omzk
/tmp/zk-stark verify --in /tmp/proof.omzk --x0 3 --y0 5 --c0 11 --delta 7 \
  --out-x 11405389917247412905 --out-y 13819602497355422025
/tmp/zk-stark inspect --in /tmp/proof.omzk

# 4. Run full pure-OM-2 gate (2x deterministic omc build + 18 attack controls + 5 OMC mutants)
/tmp/zk-gate /tmp/zk-omc . /tmp/zk-gate-scratch

# 5. Machine-checked Lean 4.36.0 proof verification
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/ZkTranscriptSoundness.lean
```

---

## Verification Scope & Honest Status

| Target / Check | Verdict | Scope / Notes |
|---|---|---|
| `seed/out/omc` 2x deterministic build (`goldilocks_stark`, `gate_zk`) | **HOST-VERIFIED (Spark AArch64)** | `cmp -s` exit `0`, zero stderr, `readelf -d` reports `no dynamic section`, pinned `85b84c6d...` |
| `gate_zk` full suite (`OMC_BIN REPO_ROOT SCRATCH`) | **HOST-VERIFIED (Spark AArch64)** | `checks=29`, `attack_controls=18`, `caught=18`, `mutants_killed=5`, `cmp_eq=1`, `hw_writes=0` |
| `seed/helix/proofs/ZkTranscriptSoundness.lean` | **LEAN-VERIFIED (Lean 4.36.0)** | `-DwarningAsError=true` exit `0`, `0` warnings, `0` `sorry`, standard axioms only |
| `tests/gates/run.sh zero-disk-secrets` | **HOST-VERIFIED** | `0` plaintext `.env` findings |
| GB10 Physical GPU Silicon | **`NOT_RUN`** | Zero GPU device writes (`hw_writes=0`); no UEFI/SPI/driver changes |
