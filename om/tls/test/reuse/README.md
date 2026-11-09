# OMEGA-CRYPTO-REUSE-1: gates 1 and 2, receipt contract version 1

Issue #639. Host only, synthetic keys and payloads (`vectors.txt`); no real key, trace or model
weight enters a fixture or receipt.

## Reproduce

From the repository root, with the pinned compiler:

```
sh om/tls/test/reuse/run.sh seed/out/omc
```

`seed/host/check.sh` runs the same command. Exit: 0 PASS, 1 FAIL, 2 REFUSED, 3 INVALID, 4 NOT_RUN.
The last line on success is
`REUSE PASS receipt=build/tls/reuse/receipt.txt sha256=<hex> controls=37 verifier-mutants=10/10`.
To re-check a stored receipt against the tree and its evidence files:

```
build/tls/reuse/verify < build/tls/reuse/receipt.txt
```

## Files

| File | Role |
| --- | --- |
| `driver.om` | the 27 checks of gates 1 and 2 (ChaCha20-Poly1305, AES-128-GCM, AES-128-GCM-SIV) |
| `vectors.txt` | the fixture: synthetic plaintexts, keys, nonces and the expected XOR (computed with Wolfram) |
| `receipt.om` | receipt contract version 1 and the verifier: parsing, re-hashing, classification, verdict |
| `verify.om` | the verifier program (`om2`, `om/tls/sha2.om`, `receipt.om`, `verify.om`) |
| `controls.om` | 37 negative controls of the verifier and a last rerun of the untouched receipt that proves every edited evidence file was restored (`om2`, `om/tls/sha2.om`, `receipt.om`, `controls.om`) |
| `run.sh` | orchestration only: builds, runs each case under `env -i` and a 60 s deadline, writes facts |

`run.sh` records facts (exit codes, byte counts, sha256 of every unit, input and stdout file) and
decides nothing. `receipt.om` re-hashes each file with the Omega SHA-256 in `om/tls/sha2.om` (an
implementation independent of the `sha256sum` that wrote the facts), classifies every row from the
stdout file itself and prints the verdict. The contract is written out at the top of `receipt.om`.

## Coverage matrix

| #639 item | Where | State in this tree |
| --- | --- | --- |
| Gate 1: (P1 xor K) xor (P2 xor K) = P1 xor P2, independent expected bytes, broken detector | `driver.om` checks 1-3; mutants `detector-always-reuse`, `wrong-expected-xor` | EXERCISED, host |
| Gate 2: payload XOR disclosure for a repeated key and nonce in ChaCha20-Poly1305 and AES-GCM, tags excluded | checks 4-19; mutants `tags-in-detector`, `nonce-not-distinct`, `tamper-not-applied` | EXERCISED, host |
| Gate 2: AES-GCM-SIV tested separately (published vectors in `om/tls/test/gcmsiv/`, repeated-input cases here) | checks 20-27; mutant `siv-as-other-mode` | EXERCISED, host |
| Gate 3: Open Humanity replay cache, contributory X25519, transport boundaries (open-humanity #29, #30, #31) | Open Humanity's own tests | outside this repository; not run by this gate (NOT_RUN here) |
| Gate 3: Aienux sealed-store rollback and nonce safety (aienux #445) | Aienux's own tests | outside this repository; NOT_RUN here |
| Gate 3: Sovereign Core sealed KV nonce source and recovery (aien-sovereign-core-mv #708) | Sovereign Core's own tests | outside this repository; NOT_RUN here |
| Gate 4: a named negative mutant per protection, observed failing assertion, control run | six driver mutants, each bound to the exact set of checks it must fail | EXERCISED, host |
| Gate 4: build error, crash, timeout, missing executable or skipped test is INVALID or NOT_RUN | `receipt.om` classes; controls 13, 14, 16, 17, 19, 24-26 | EXERCISED, host |
| Versioned fixture and receipt format | `CRYPTO-REUSE-RECEIPT 1` in `receipt.om` | IMPLEMENTED, EXERCISED |
| Bind source commit, dirty state, compiler pin, binary, fixture digest, command, environment, expected and observed result, mutant identity, logs, checker version | `source`, `dirty`, `omc`, `driver`, `fixture`, `runner`, `env`, `row`, `checker` lines | IMPLEMENTED, EXERCISED |
| Tampering, mismatched pins, stale inputs and missing evidence refused | controls 3-12, 27-37 | EXERCISED, host |
| checker2 bounded XOR and counter properties | not attempted in this change (`src/checker2` has an XOR operator, `c2_ir.h`, so a bounded obligation may be expressible) | NOT_RUN, UNKNOWN |
| Signature binding of provenance | not part of version 1 | NOT_RUN: a receipt and its evidence rewritten together and consistently are not detected |

## Driver mutants

Each mutant must build cleanly, exit 1, print one summary with 27 checks, and fail exactly the
listed checks. Failing any other check, or failing for any other reason, is INVALID, not a kill.

| Row | Change | Checks it must fail | Why that proves the test |
| --- | --- | --- | --- |
| `tags-in-detector` | the AEAD detector compares 96 bytes (tags included) | 6, 14 | the tags differ, so a detector that includes them misses the reuse |
| `detector-always-reuse` | the detector always answers "reused" | 3, 7, 15, 23 | every distinct-keystream control catches a detector that cannot say no |
| `nonce-not-distinct` | the "distinct" nonce equals the first | 7, 11, 15, 19, 27 | the no-reuse and wrong-nonce controls catch a nonce source that repeats |
| `tamper-not-applied` | the ciphertext flip is removed | 10, 18 | the forgery checks catch a tamper test that tampers nothing |
| `siv-as-other-mode` | the first GCM-SIV seal uses AES-GCM | 21 | the SIV-is-not-GCM check catches a mode substitution |
| `wrong-expected-xor` | one digit of the expected XOR in the fixture | 1, 5, 13 | the independent expected bytes are really compared |

## Verifier mutants

One changed line of `receipt.om`, built with `controls.om`. Each must exit 1 and fail exactly the
listed controls; a survivor is FAIL and anything else INVALID.

| Mutant | Change | Controls |
| --- | --- | --- |
| `log-hash-skipped` | stdout files are not re-hashed | 5, 6 |
| `any-failure-kills` | any failing mutant counts as caught | 18 |
| `verdict-claim-ignored` | a claimed verdict is not compared | 3 |
| `class-claim-ignored` | a claimed class is not compared | 4 |
| `fixture-not-rehashed` | the fixture is not compared | 7 |
| `pin-not-checked` | the compiler pin is not compared | 8 |
| `stale-base-source` | the base unit is not compared with the current sources | 11 |
| `missing-row-passes` | a missing row counts as PASS | 13 |
| `zero-checks-pass` | the check count is not required to be 27 | 17 |
| `noop-mutant-kills` | a mutant equal to the base is accepted | 21, 22 |
