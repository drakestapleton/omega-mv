# `apps/omega-fhe`: Pure Seeded-Omega Exact-Integer Ring-LWE / Leveled BFV Homomorphic Evaluator (`OMFHE1`)

> **Plain-English Summary:** Imagine putting a locked glass glovebox around sensitive numbers so an untrusted worker can multiply and combine them without ever opening the lock—or seeing what is inside. `omega-fhe` turns that analogy into exact 64-bit integer algebra: plaintexts live modulo `t = 257` across 64-coefficient polynomials in `Z_q[X]/(X^64 + 1)`, scaled by `Delta = floor(q / t)` inside ciphertexts modulo a 56-bit NTT-friendly prime `q = 72057594036480257`. A blind evaluator computes `add`, `sub`, `const-mul`, relinearized ciphertext `mul`, and quadratic polynomials `a*x^2 + b*x*y + c*y + d (mod t)` using **only** the public evaluation key (`evk`) while holding zero secret key (`sk`), then an independent schoolbook verifier and a machine-checked Lean 4.36.0 proof confirm that every coefficient stays canonical (`< q`), every noise growth step stays strictly within budget, and `Dec(Eval(Enc(x), Enc(y))) == f(x, y) mod 257` byte-for-byte.

---

## Side-by-Side Comparison

| Property | Ad-Hoc / Float-Backed Toy Crypto | `omega-fhe` (`fhe_rlwe.om` + `fhe_check.om`) |
|---|---|---|
| **Arithmetic Precision** | Floating-point (`f64` FFT/CRT rounding drift, 53-bit mantissa truncation) | **Zero floats**: exact unsigned 64-bit Montgomery REDC (`q`), exact 2-prime CRT-NTT (`p_1 * p_2 > 2 * 2N * (q/2)^2`) for tensor rounding `round(t * z / q)` |
| **Algebraic Structure** | Integer vectors without negacyclic wrap | Cyclotomic ring `Z_q[X]/(X^64 + 1)` with bit-reversed 64-point NTT/INTT (`psi^64 = -1 mod q`) & balanced 7-digit base-`256` relinearization |
| **Canonical `< q` Gate** | Trusts caller array bounds (silent wraparound alias `x >= q`) | Strict `fh_is_canon` (`< q`) checked on every parsed word; `val >= q` fails closed with `exit 74` (`NONCANON`) |
| **Noise Discipline** | Unbounded / guessed depth | Explicit worst-case integer `noiseBound` & `noiseBudget` tracked in signed `OMFHE1` header (`MAX = 140189871666303`); excess fails closed (`exit 75`) |
| **Blind Evaluation Isolation** | Single binary holding `sk` during `eval` | Physically audited by `fhe_check audit-blind` inside an isolated `blind_sandbox/` subprocess with zero `sk` access and `exit 77` key-kind enforcement |
| **Container Authentication** | Raw binary dumps | `256`-byte header + fixed payload `OMFHE1` (`SK=768 B`, `EVK=8448 B`, `CT=1280 B`), domain tag `"OMEGA-FHE-BFV-RLWE-V1"`, double SHA-256 + RFC 8032 Ed25519 signature |
| **Implementation & Proof** | C / C++ / Rust / Python FHE libraries | **100% pure seeded OM-2** (`seed/out/omc`) + **Lean 4.36.0** soundness (`0` warnings, `0 sorry`, standard axioms only) |

---

## Owned Files

- [`apps/omega-fhe/fhe_rlwe.om`](fhe_rlwe.om): Standalone pure-OM-2 exact-integer Ring-LWE / leveled BFV evaluator, key generator, encryptor, decryptor, `OMFHE1` container signer/inspector, and self-test (`selftest`, `keygen`, `encrypt`, `add`, `sub`, `const-mul`, `mul`, `eval-poly`, `decrypt`, `inspect`).
- [`apps/omega-fhe/fhe_check.om`](fhe_check.om): Independent verifier (zero shared NTT, Montgomery, or CRT code) using naive schoolbook cyclotomic multiplication + 128-bit long division (`verify-ct`, `verify-op`, `audit-blind`, `selftest`), verifying ciphertext canonical bounds `< q`, noise budget, `OMFHE1` SHA-256 + Ed25519 integrity, blind subprocess isolation, and exact decryption against `Z_t[X]/(X^64 + 1)`.
- [`apps/omega-fhe/gate_fhe.om`](gate_fhe.om): Pure-OM-2 verification gate checking `omc` SHA-256 pin (`exit 69` mismatch), `2x` deterministic Spark `omc` compilation of both binaries (`cmp -s`, zero stderr, static ELF64 with zero `PT_DYNAMIC`), cross-binary evaluation + independent verification, `19` negative attack assertions across `15` attack scenarios (including attacker re-signed non-canonical `>= q`, zeroed `rk0`, exceeded noise budget, wrong `sk`, and malformed containers), and `5` live `omc`-recompiled source mutants.
- [`seed/helix/proofs/OmegaFheSoundness.lean`](../../seed/helix/proofs/OmegaFheSoundness.lean): Machine-checked Lean 4.36.0 soundness proof (`-DwarningAsError=true`, `0` warnings, `0 sorry`, standard core axioms only) proving exact ring/CRT/NTT parameter identities (`by decide`), Montgomery REDC correctness, cyclotomic linearity & infinity-norm bounds, exact `bfvDecodeCoeff` rounding theorem up to `FHE_MAX_NOISE`, `BFVInv` preservation for `add`, `sub`, `constMul`, `addConst`, `mul + relin`, end-to-end `evalQuadPlain` soundness (`noise <= 13,800,000,000 <= 140,189,871,666,303`), and concrete `decide` negative witnesses.
- [`evidence/WAVE5-FHE-RLWE-20261127/`](../../evidence/WAVE5-FHE-RLWE-20261127/RECEIPT.txt): Content-addressed verification receipt (`RECEIPT.txt` and `SHA256SUMS.txt`).

---

## Algebraic Parameters & `OMFHE1` Layout

- **Ring & Plaintext Modulus:** `N = 64` (`Z_q[X]/(X^64 + 1)`), `t = 257`, `Delta = floor(q / t) = 280379743332608` (`t * Delta = q - 1`).
- **Ciphertext Modulus:** `q = 72057594036480257` (`q ≡ 1 (mod 256 * 257)`, `q < 2^56 < 2^63`), primitive `128`-th root `psi = 27844242908845386`, Montgomery inverse `q' = 12330114045378619647` (`q * q' + 1 ≡ 0 (mod 2^64)`).
- **Exact Tensor Product CRT-NTT:** `p_1 = 4611686018427379201`, `p_2 = 2305843009213689601` (`p_1 = 2 * p_2 - 1`, so CRT recombination over `p_1 * p_2 ≈ 2^{123}` needs zero multi-limb inverse search and strictly exceeds `2 * 2 * N * (q/2)^2 ≈ 2^{118}` without overflow or floating point).
- **Relinearization & Noise Budget:** `7` balanced base-`256` digits (`|digit| <= 128`); `FHE_E_FRESH = 162`, `FHE_MAX_NOISE = 140189871666303` (`floor((floor(q/2) - (t - 1)) / t)`), giving exact multiplicative depth `2` (`a*x^2 + b*x*y + c*y + d` worst-case bound `<= 1.38e10`, `> 10,000x` headroom; depth `3` crosses `FHE_MAX_NOISE` and is cleanly rejected with `exit 75`).
- **`OMFHE1` Fixed Container (`256 B` header + payload):**
  - `[0..6)` magic `"OMFHE1"`, `[6..8)` `version=1`, `[8..12)` `kind` (`1=SK`, `2=EVK`, `3=CT`), `[12..16)` `N=64`, `[16..24)` `q`, `[24..32)` `t=257`
  - `[32..40)` `noise_bound`, `[40..48)` `noise_budget = MAX - noise_bound`, `[48..52)` `mul_depth`, `[52..56)` `relin_digits=7`, `[56..64)` `payload_bytes`
  - `[64..96)` domain `"OMEGA-FHE-BFV-RLWE-V1"`, `[96..128)` `payload_sha256`, `[128..160)` `header_body_sha256`, `[160..192)` `signer_pk`, `[192..256)` Ed25519 signature over `[0..160)`

---

## Build & Verify

### DGX Spark Linux AArch64 (Pinned `seed/out/omc`)

```bash
# 1. Extract pinned omc (expected sha256: 85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134)
git -C ~/git/omega-mv.git show main:seed/out/omc > /tmp/fhe-omc && chmod +x /tmp/fhe-omc

# 2. Compile fhe_rlwe, fhe_check, and gate_fhe deterministically
cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
  protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
  apps/omega-fhe/fhe_rlwe.om | /tmp/fhe-omc > /tmp/fhe_rlwe && chmod +x /tmp/fhe_rlwe

cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
  protocol/omnet/om/ed25519/ed25519.om apps/omega-fhe/fhe_check.om \
  | /tmp/fhe-omc > /tmp/fhe_check && chmod +x /tmp/fhe_check

cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
  protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
  apps/omega-fhe/gate_fhe.om | /tmp/fhe-omc > /tmp/gate_fhe && chmod +x /tmp/gate_fhe

# 3. Run full pure-OM-2 gate (pin + 2x det builds + static ELF + blind audit + 19 attack assertions + 5 OMC mutants)
/tmp/gate_fhe /tmp/fhe-omc . /tmp/fhe-gate-scratch

# 4. Run machine-checked Lean 4.36.0 proof
~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/OmegaFheSoundness.lean
```

### Apple Silicon macOS Bonus (`fhe_rlwe.om` via `target a64macos`)

`fhe_check.om` and `gate_fhe.om` use Linux `fork`/`execprog` subprocess sandboxes (Linux AArch64 host targets), while standalone `fhe_rlwe.om` cross-compiles directly to native Apple Silicon Mach-O (`~/.local/bin/omc`), passes `2x` pre-codesign determinism (`cmp -s`), and produces byte-for-byte identical `OMFHE1` ciphertexts (`eval-poly` SHA-256 matches Spark ELF bit-for-bit):

```bash
{ printf 'target a64macos\n'; cat si/directives/om2.om seed/ng/sha256.om \
  protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
  protocol/uor-gpu/ed_sign.om apps/omega-fhe/fhe_rlwe.om; } \
  | ~/.local/bin/omc > /tmp/fhe_rlwe_mac
codesign --force --sign - /tmp/fhe_rlwe_mac && chmod +x /tmp/fhe_rlwe_mac
/tmp/fhe_rlwe_mac selftest
```

---

## Verification Scope & Honest Status

| Target / Check | Verdict | Scope / Notes |
|---|---|---|
| `seed/out/omc` 2x deterministic build (`fhe_rlwe`, `fhe_check`, `gate_fhe`) | **HOST-VERIFIED (Spark AArch64)** | `cmp -s` exit `0`, zero stderr, `readelf -d` reports `no dynamic section`, pinned `85b84c6d...` |
| `gate_fhe` full suite (`OMC_BIN REPO_ROOT SCRATCH`) | **HOST-VERIFIED (Spark AArch64)** | `checks=22`, `attack_controls=19`, `caught=19`, `mutants_killed=5`, `cmp_eq=1`, `hw_writes=0` |
| `fhe_rlwe` native Mach-O build & CLI pipeline | **HOST-VERIFIED (macOS ARM64)** | `2x` pre-codesign `cmp -s` OK, ad-hoc signed, `selftest` + `keygen/encrypt/eval-poly/decrypt/inspect` match Spark SHA-256 identically |
| `seed/helix/proofs/OmegaFheSoundness.lean` | **LEAN-VERIFIED (Lean 4.36.0)** | `-DwarningAsError=true` exit `0`, `0` warnings, `0 sorry`, standard axioms only |
| `tests/gates/run.sh zero-disk-secrets` | **HOST-VERIFIED** | `0` plaintext `.env` findings |
| GB10 Physical GPU Silicon | **`NOT_RUN`** | Zero GPU device writes (`hw_writes=0`); no UEFI/SPI/driver changes |
