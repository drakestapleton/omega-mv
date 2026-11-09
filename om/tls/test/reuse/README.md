# OMEGA-CRYPTO-REUSE-1: gates 1 to 4 and checker2 obligations, receipt contracts version 1

Issue #639. Host only, synthetic keys and payloads (`vectors.txt`); no real key, trace or model
weight enters a fixture or receipt.

## Reproduce

From the repository root, with the pinned compiler:

```
sh om/tls/test/reuse/run.sh seed/out/omc
```

`seed/host/check.sh` runs the same command. Exit: 0 PASS, 1 FAIL, 2 REFUSED, 3 INVALID (also when
the verifier itself traps or is killed), 4 NOT_RUN. The last line on success is
`REUSE PASS receipt=build/tls/reuse/receipt.txt sha256=<hex> controls=47 verifier-mutants=13/13`.
To re-check a stored receipt against the tree and its evidence files:

```
build/tls/reuse/verify < build/tls/reuse/receipt.txt
```

Gate 3 (the protections in Open Humanity, Aienux and Sovereign Core) and the checker2 obligations
run through a second Omega program, `aggregate.om`, driven by plan files:

```
sh om/tls/test/reuse/agg.sh seed/out/omc om/tls/test/reuse/prov.plan \
  om/tls/test/reuse/c2/c2.plan om/tls/test/reuse/agg/gate3.plan
```

Without plan arguments it only runs the runner's own self-test. With them it first runs the
self-test, then joins the plans into `build/tls/reuse/aggregate.plan`, runs every row, writes
`build/tls/reuse/aggregate.txt` (contract `CRYPTO-REUSE-AGGREGATE 1`, written out at the top of
`aggregate.om`) and requires `aggregate check` to accept it: check recomputes the receipt from the
plan, logs, outputs and fixtures and compares it byte for byte. Its exit is the plan's verdict (0
PASS, 1 FAIL, 2 REFUSED, 3 INVALID, 4 NOT_RUN). A runner that stops before printing a verdict (an
I/O failure, a malformed plan) is INVALID (3), with its stderr kept in `build/tls/reuse/aggregate.err`
and printed as the reason; the receipt file is removed before every run, so an earlier run's receipt
is never left in its place. On a shared host, hold the CPU pool lock for the
whole run (on the Spark: `flock ~/handoffs/hive/queen/pool-8-9.lock taskset -c 8-9 nice -n 19`);
rows take no lock themselves. The gate 3 rows need the other repositories checked out under
`build/tls/reuse/src/` (`agg/README.md`); a missing checkout makes its rows NOT_RUN, never PASS.

## Files

| File | Role |
| --- | --- |
| `driver.om` | the 27 checks of gates 1 and 2 (ChaCha20-Poly1305, AES-128-GCM, AES-128-GCM-SIV) |
| `vectors.txt` | the fixture: synthetic plaintexts, keys, nonces and the expected XOR (computed with Wolfram) |
| `receipt.om` | receipt contract version 1 and the verifier: parsing, re-hashing, classification, verdict |
| `verify.om` | the verifier program (`om2`, `om/tls/sha2.om`, `receipt.om`, `verify.om`) |
| `controls.om` | 46 negative controls of the verifier and a last rerun of the untouched receipt (control 99) that proves every edited evidence file was restored (`om2`, `om/tls/sha2.om`, `receipt.om`, `controls.om`) |
| `run.sh` | orchestration: builds, runs each case under `env -i` and a 60 s deadline, writes facts; decides the verifier-mutant meta-gate |
| `aggregate.om` | the plan runner: runs each row under a deadline, hashes logs, outputs and fixtures, classifies every row and prints the aggregate receipt; `check` mode recomputes it from the files (`om2`, `om/tls/sha2.om`, `aggregate.om`) |
| `fixture.om` | a test program for the runner's self-test: prints its arguments as lines and exits with the first |
| `selftest.plan` | 31 rows, one per classification branch of `aggregate.om`, each with its wanted class |
| `agg.sh` | orchestration: builds the runner, runs the self-test, 8 tamper controls, 6 refusals (5 malformed plans, 1 stale log) and the runner mutants, then the given plans, always under `env -i HOME PATH LC_ALL=C` |
| `prov.plan` | provenance rows: commit, clean tree, compiler pin, the environment every row receives, runner sources |
| `c2/` | the checker2 obligations: four IR units, `c2.plan`, `README.md` |
| `agg/` | the gate 3 adapter plan for the three other repositories, their mutant patches, `README.md` |

For the driver rows `run.sh` only records facts (exit codes, byte counts, sha256 of every unit,
input and stdout file). `receipt.om` re-hashes each file with the Omega SHA-256 in `om/tls/sha2.om`
(an implementation independent of the `sha256sum` that wrote the facts), classifies every row from
the stdout file itself and prints the verdict. Three numbers per row are trusted as `run.sh`
recorded them: the build exit, the compiler stderr byte count (the stderr file is not in the
receipt) and the program exit. The verifier-mutant meta-gate (below) is decided in `run.sh` by an
exact comparison of the failed control numbers. The contract is written out at the top of
`receipt.om`.

## Coverage matrix

| #639 item | Where | State in this tree |
| --- | --- | --- |
| Gate 1: (P1 xor K) xor (P2 xor K) = P1 xor P2, independent expected bytes, broken detector | `driver.om` checks 1-3; mutants `detector-always-reuse`, `wrong-expected-xor` | EXERCISED, host |
| Gate 2: payload XOR disclosure for a repeated key and nonce in ChaCha20-Poly1305 and AES-GCM, tags excluded | checks 4-19; mutants `tags-in-detector`, `nonce-not-distinct`, `tamper-not-applied` | EXERCISED, host |
| Gate 2: AES-GCM-SIV tested separately (published vectors in `om/tls/test/gcmsiv/`, repeated-input cases here) | checks 20-27; mutant `siv-as-other-mode` | EXERCISED, host |
| Gate 3: Open Humanity replay cache, contributory X25519, transport boundaries (open-humanity #29, #30, #31) | `agg/gate3.plan`: `oh-control` (28 + 89 tests) and eight mutants `oh-replay-clear` … `oh-write-resume`, each killed only by one failure of its named test at its named panic location, with exactly one test run (`once`, counts); pin d929a34 with the `oh-lockfix.diff` lock fixture (`agg/README.md`) | EXERCISED, host; transcript binding has no Open Humanity test, so no mutant covers it |
| Gate 3: Aienux sealed-store rollback and nonce safety (aienux #445) | `ux-store-control`, `ux-crypto-control`, mutant `ux-v1-predictable-envid` | EXERCISED, host; `STORE_RUST_CROSSCHECK` NOT_RUN in aienux itself |
| Gate 3: Sovereign Core sealed KV nonce source and recovery (aien-sovereign-core-mv #708) | `sc-control`, mutants `sc-m1-entropy-error-dropped`, `sc-m2-aad-shortened`, `sc-m3-aad-removed` | EXERCISED, host |
| Gate 3 and checker2 aggregate result | `aggregate.om`, receipt `CRYPTO-REUSE-AGGREGATE 1`, `agg.sh`; self-test of every class, 8 tamper controls, 6 refusals, 20 runner mutants | IMPLEMENTED, EXERCISED |
| Gate 4: a named negative mutant per protection, observed failing assertion, control run | six driver mutants, each bound to the exact set of checks it must fail | EXERCISED, host |
| Gate 4: build error, crash, timeout, missing executable or skipped test is INVALID or NOT_RUN | `receipt.om` classes; controls 13, 14, 16, 17, 19, 24-26, 38-40, 43, 45, 46 | EXERCISED, host |
| Versioned fixture and receipt format | `CRYPTO-REUSE-RECEIPT 1` in `receipt.om` | IMPLEMENTED, EXERCISED |
| Bind source commit, dirty state, compiler pin, binary, fixture digest, command, environment, expected and observed result, mutant identity, logs, checker version | `source`, `dirty`, `omc`, `driver`, `fixture`, `runner`, `env`, `row`, `checker` lines | IMPLEMENTED, EXERCISED |
| Tampering, mismatched pins, stale inputs and missing evidence refused | controls 3-12, 27-37, 41, 42, 44 | EXERCISED, host |
| checker2 bounded XOR and counter properties | `c2/`: two IR units proved trap-free for every input (checker2 `prove-cnf`, solver, checker2's own LRAT replay `prove-check`); two mutants refused with the solver's counterexample | EXERCISED, host; bit-level facts about the two formulas only (`c2/README.md`) |
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
listed controls; a survivor is FAIL, anything else INVALID, a missing site NOT_RUN.

| Mutant | Change | Controls |
| --- | --- | --- |
| `log-hash-skipped` | stdout files are not re-hashed | 5, 6 |
| `any-failure-kills` | any failing mutant counts as caught | 18 |
| `exit-not-checked` | a caught mutant need not exit 1 | 38 |
| `repeated-check-counted` | a repeated `MISMATCH check N` line is accepted | 40 |
| `log-leading-zero` | `MISMATCH check 06` is read as check 6 | 45 |
| `verdict-claim-ignored` | a claimed verdict is not compared | 3 |
| `class-claim-ignored` | a claimed class is not compared | 4 |
| `fixture-not-rehashed` | the fixture is not compared | 7 |
| `pin-not-checked` | the compiler pin is not compared | 8 |
| `stale-base-source` | the base unit is not compared with the current sources | 11 |
| `missing-row-passes` | a missing row counts as PASS | 13 |
| `zero-checks-pass` | the check count is not required to be 27 | 17 |
| `noop-mutant-kills` | a mutant equal to the base is accepted | 21, 22 |

## Aggregate runner self-test

`selftest.plan` gives every classification branch of `aggregate.om` a row with its wanted class.
The three findings of the L698 review each have rows: an unrelated failure that prints the
intended marker in the middle of a line (`mut-unrelated`, `ctl-midline`) or prints a verbatim copy
of the intended panic line and then panics elsewhere (`mut-forged`: two panic lines, so `once
thread '` fails), a missing executable (`ctl-missing-exe`, `mut-missing-exe`) and zero selected or
skipped tests (`ctl-zero-tests`, `mut-zero`, `mut-ignored`). `once` itself has `ctl-once-ok`,
`ctl-once-none` and `ctl-once-twice`. `agg.sh` then edits copies and requires `aggregate check` to refuse
each one: a log byte (`t-log`), a class word (`t-class`), the verdict word (`t-verdict`), a deleted
row line (`t-row`), a removed log (`t-nolog`), a changed bound fixture (`t-fixture`), a changed
plan (`t-plan`) and a status number (`t-status`). A tamper that leaves the bytes unchanged is
reported as a harness error, never as refused. Five malformed plans must stop both `run` and
`check` with exit 3 at their exact plan line, before their command runs: 58 arguments (`r-args`;
`execenv` takes at most 64 entries and the runner adds 7), a 201-byte row name (`r-name`), a
mutant expecting exit 0 (`r-mutexit0`), an argument packet over 4096 bytes (`r-bytes`) and a
repeated row name (`r-dup`). The packet size is computed while parsing, so both modes accept the
same plans; on the Spark a 4034-byte argument after `echo` makes a packet of exactly 4096 bytes and
runs, 4035 bytes is refused. Stale results (`r-stale`): a second `run` of the self-test plan over
the first run's logs must stop at its first row with exit 3, the line `aggregate: cannot create the
log (left from an earlier run?)` and an empty stdout, so no row is ever classified from an earlier
run's log.

What `once` does not cover: a test that forges the whole harness output (its own `test ... FAILED`,
panic line and summary) and then ends the process itself with the expected status prints no second
panic line. The mutants change product code, not the tests, so this needs a changed test.

### Runner mutants

One changed line of `aggregate.om`. Each must build and change exactly the listed self-test rows
(class or reason), tamper and refusal controls; a survivor is FAIL, any other set INVALID, a missing site
NOT_RUN.

| Mutant | Change | Rows and controls |
| --- | --- | --- |
| `control-need-skipped` | a control passes without its `need` lines | `ctl-zero-tests`, `ctl-midline`, `ctl-no-digits` |
| `mutant-need-skipped` | a mutant is killed by its exit alone | `mut-unrelated`, `mut-build-error` |
| `zero-tests-survive` | a survivor need not show its `pass` lines | `mut-zero`, `mut-ignored` |
| `exec-failure-ignored` | status 124 to 127 is classified like any other | `ctl-missing-exe`, `ctl-deadline`, `mut-missing-exe` |
| `signal-ignored` | a killed command is classified by its status | `ctl-signal` |
| `fixture-not-required` | an absent bound fixture is accepted | `ctl-fixture-missing` |
| `empty-not-checked` | `empty` is not enforced | `ctl-empty-bad` |
| `after-ignored` | a row runs after a failed `after` row | `ctl-after-fail` |
| `empty-digit-run` | `#` matches zero digits | `ctl-no-digits` |
| `big-log-accepted` | a log over 8 MiB is classified from its first 8 MiB | `ctl-big-log` |
| `survivor-killed` | a survivor counts as killed | `mut-survived` |
| `receipt-bytes-unchecked` | check compares only the receipt length | `t-log`, `t-class`, `t-verdict`, `t-fixture`, `t-plan` |
| `env-not-passed` | rows get an empty environment (`execprog`) instead of the runner's | `ctl-env` |
| `args-unbounded` | a row may have more than 57 arguments (the child then traps in `execenv`) | `r-args` |
| `name-unbounded` | a row name may exceed 200 bytes | `r-name` |
| `mutant-exit0-accepted` | a mutant may expect exit 0 (killed and survived then share a status) | `r-mutexit0` |
| `packet-unchecked-in-plan` | the parser skips the packet size (run still stops in `arun`, check does not) | `r-bytes` |
| `control-once-skipped` | a control passes without its `once` counts | `ctl-once-none`, `ctl-once-twice` |
| `mutant-once-skipped` | a mutant is killed with a second panic next to the intended one | `mut-forged` |
| `stale-log-overwritten` | the log is opened with truncation instead of exclusively | `r-stale` |
