# Pure Seeded-OM-2 CDCL SAT Solver & Independent RUP/DRAT/LRAT Proof Checker (`omega-sat`)

Think of boolean satisfiability like checking a huge wiring puzzle or Sudoku: **finding** a solution (`SAT`) or a proof that no solution exists (`UNSAT`) takes smart search with backtracking, while **checking** the finished answer uses a completely separate, simpler rulebook.

`omega-sat` splits those two jobs into two completely separate pure `.om` programs with **zero shared solver code**, backed by a **Lean 4.36.0** machine-checked soundness proof:

- If a solver claims **SAT**, it hands back a concrete true/false assignment (`OMSAT1`) and the separate checker evaluates every original clause directly.
- If a solver claims **UNSAT**, it hands back a step-by-step elimination trail (`OMDR01` RUP/DRAT/LRAT proof) ending in the empty contradiction `[]`, and the separate checker replays every inference independently against the original formula.
- Both containers lock the original CNF SHA-256 hash, proof body SHA-256 hash, and an Ed25519 signature (`OMSR01` or embedded footer), so tampering with even 1 bit of a clause, witness, hint, or magic header fails closed.

| Component | File | Plain-English Role | Code Shared With Solver |
| :--- | :--- | :--- | :--- |
| CDCL Solver & Prover | [sat_cdcl.om](file:///apps/omega-sat/sat_cdcl.om) | 2-watched-literal CDCL solver, 1-UIP clause learning, VSIDS heap, Luby restarts, clause deletion (`op=2`), `OMSAT1`/`OMDR01`/`OMSR01` emitter | Solver binary (`2056` lines) |
| Zero-Shared-Code Verifier | [sat_check.om](file:///apps/omega-sat/sat_check.om) | Independent DIMACS parser, direct SAT evaluator, independent occurrence-list RUP/DRAT/LRAT checker (`op=1`/`op=2`), Ed25519 + SHA-256 verifier (no solver, no `ed_sign.om`) | **None (`0` lines shared)** |
| Verification Gate | [gate_sat.om](file:///apps/omega-sat/gate_sat.om) | Checks `seed/out/omc.sha256` pin (`exit 69` on mismatch), builds both binaries 2x byte-identically, verifies 7 SAT/UNSAT benchmarks, 16 container/DRAT attacks, and 6 live `omc`-recompiled solver-bypass mutants | Harness (`1864` lines) |
| Lean 4 Soundness Proof | [OmegaSatSoundness.lean](file:///seed/helix/proofs/OmegaSatSoundness.lean) | Proves unit propagation soundness, RUP equisatisfiability, RAT equisatisfiability, multi-step empty-clause refutation -> `Unsatisfiable`, and 5 `decide` negative witnesses (`0` warnings, `0` `sorry`, zero Mathlib) | Independent formal kernel (`738` lines) |
| Wave 5 Receipt & Sums | [RECEIPT.txt](file:///evidence/WAVE5-SAT-DRAT-20261127/RECEIPT.txt) | Exact observed outputs, SHA-256 hashes, `readelf -d` checks, and `SHA256SUMS.txt` | Additive evidence |

## Scope & Honest Status

- **Status:** `HOST-VERIFIED` (DGX Spark AArch64 Linux static ELF64 + MacBook Apple Silicon Mach-O ARM64) and `LEAN-VERIFIED` (`Lean 4.36.0` with `-DwarningAsError=true`).
- **What is NOT built / NOT run here:** No physical GB10 GPU kernels run here (`GPU = NOT_RUN`, `hw_writes = 0`). No `.c`, `.h`, `.py`, `.rs`, or `gcc` code is added or invoked.
- **Pinned compiler:** Built cleanly from stdin with `seed/out/omc` (`85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`).

## Binary Containers & Fail-Closed Exit Codes

| Artifact | Magic / Layout | Bound Digests & Signature |
| :--- | :--- | :--- |
| `OMSAT1` | `64B` header + `nvars` witness bytes (`0`/`1`) + `128B` footer | `cnf_sha256[32]`, `body_sha256[32]`, `pk[32]`, `sig[64]` (`edverify` over domain `"OMSAT1-RCPT"`) |
| `OMDR01` | `64B` header + variable-length `u32` LE step records (`op=1` add with hints+lits, `op=2` delete lits) + `128B` footer | `cnf_sha256[32]`, `body_sha256[32]`, `pk[32]`, `sig[64]` (`edverify` over domain `"OMDR01-RCPT"`) |
| `OMSR01` | Fixed `352B` standalone receipt (`64B` header + `224B` fields + `64B` sig) | Binds `cnf_sha256`, `proof_sha256`, `verdict`, `nvars`, `nclauses`, `steps`, `pk`, RFC 8032 `sig` |

| Exit Code | Meaning |
| :--- | :--- |
| `0` | Verification passed (`sat_check`) or `selftest` passed |
| `10` / `20` | `sat_cdcl solve`: `10` = `SAT` (`OMSAT1` written), `20` = `UNSAT` (`OMDR01` written) |
| `2` / `3` / `4` / `5` | CLI usage / file I/O / DIMACS parse error / capacity limit |
| `60` (`CK_ERR_FORMAT`) | Bad magic, version, length, truncation, or trailing bytes |
| `61` (`CK_ERR_HASH`) | `cnf_sha256`, `body_sha256`, or receipt hash mismatch (cross-CNF replay) |
| `62` (`CK_ERR_SIG`) | Strict Ed25519 signature or `--pubkey` pin mismatch |
| `63` (`CK_ERR_SAT`) | Invalid witness byte (not `0`/`1`) or witness falsifies a clause |
| `64` (`CK_ERR_LIT`) | Bad DRAT opcode, literal `0`, out-of-range variable, or malformed record |
| `65` (`CK_ERR_RUP`) | Added proof clause fails both RUP and RAT check |
| `66` (`CK_ERR_EMPTY`) | Proof omits empty clause `[]` or has trailing records after `[]` |
| `67` (`CK_ERR_HINT`) | LRAT hint ID invalid, deleted, or fails causal unit-conflict trace |
| `69` (`SG_ERR_PIN`) | `gate_sat`: `omc` binary SHA-256 does not match `seed/out/omc.sha256` |

## Clean-Room Verification Commands

### 1. DGX Spark / Linux AArch64 (with pinned `seed/out/omc` + Lean 4.36.0)

Run from the repository root (`seed/out/omc` reads concatenated source from stdin):

```sh
mkdir -p /tmp/omega-sat-verify
cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om apps/omega-sat/sat_cdcl.om | seed/out/omc > /tmp/omega-sat-verify/sat_cdcl
cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om apps/omega-sat/sat_check.om | seed/out/omc > /tmp/omega-sat-verify/sat_check
cat si/directives/om2.om seed/ng/sha256.om apps/omega-sat/gate_sat.om | seed/out/omc > /tmp/omega-sat-verify/gate_sat
chmod +x /tmp/omega-sat-verify/sat_cdcl /tmp/omega-sat-verify/sat_check /tmp/omega-sat-verify/gate_sat

readelf -d /tmp/omega-sat-verify/sat_cdcl /tmp/omega-sat-verify/sat_check /tmp/omega-sat-verify/gate_sat
/tmp/omega-sat-verify/sat_cdcl selftest
/tmp/omega-sat-verify/sat_check selftest
/tmp/omega-sat-verify/gate_sat seed/out/omc "$(pwd)" /tmp/omega-sat-verify/scr

~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/OmegaSatSoundness.lean
shasum -a 256 -c evidence/WAVE5-SAT-DRAT-20261127/SHA256SUMS.txt
bash tests/gates/run.sh zero-disk-secrets
rm -rf /tmp/omega-sat-verify
```

Expected key outputs:
- `readelf -d` on all three binaries: `There is no dynamic section in this file.`
- `SAT-GATE PASS checks=86 attack_controls=22 caught=22 mutants_killed=6 cmp_eq=1 hw_writes=0`
- `lean -DwarningAsError=true`: exit `0`, `0` warnings, `0` `sorry`, standard Lean core axioms only across all `33` `#print axioms` checks.
- `shasum -a 256 -c`: `6/6` `OK`.

### 2. MacBook Apple Silicon (`target a64macos`, Mach-O ARM64)

Run from the repository root using native Mach-O `~/.local/bin/omc` (`68a590c37dfb1ec37a183f0032e02db1570db299266f574f65556edfc70feb9c`):

```sh
mkdir -p /tmp/omega-sat-mac
printf 'target a64macos\n' > /tmp/omega-sat-mac/target_macos.om
cat /tmp/omega-sat-mac/target_macos.om si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om apps/omega-sat/sat_cdcl.om | ~/.local/bin/omc > /tmp/omega-sat-mac/sat_cdcl
cat /tmp/omega-sat-mac/target_macos.om si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om apps/omega-sat/sat_check.om | ~/.local/bin/omc > /tmp/omega-sat-mac/sat_check
chmod +x /tmp/omega-sat-mac/sat_cdcl /tmp/omega-sat-mac/sat_check
codesign --force --sign - /tmp/omega-sat-mac/sat_cdcl
codesign --force --sign - /tmp/omega-sat-mac/sat_check
/tmp/omega-sat-mac/sat_cdcl selftest
/tmp/omega-sat-mac/sat_check selftest
rm -rf /tmp/omega-sat-mac
```

(Pre-codesign binaries on Apple Silicon are deterministic: `99232` bytes each; ad-hoc `codesign --force --sign -` updates the Mach-O signature after comparison.)

## CLI Reference

```text
sat_cdcl selftest
sat_cdcl solve --in FORMULA.cnf --out PROOF.bin [--receipt RCPT.omsr] [--seed-tag TAG] [--no-lrat] [--no-del]

sat_check selftest
sat_check verify --cnf FORMULA.cnf --proof PROOF.bin [--pubkey HEX64]
sat_check verify-drat --cnf FORMULA.cnf --drat PROOF.drat
sat_check verify-receipt --receipt RCPT.omsr [--cnf FORMULA.cnf] [--proof PROOF.bin] [--pubkey HEX64]
sat_check inspect (--proof PROOF.bin | --receipt RCPT.omsr)
```
