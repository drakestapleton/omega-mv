# OM-2 coordinator record (#599, #625, #748)

Coordinator: ledger L835, the #599 language-evolution coordinator named in `spec/omegese-om2.md`.
This record was written on 2026-11-09 at omega-mv Radicle main `1e3ecbba779ee84e2de70ec231e83533a9c61f45`
(rid `z6do9WDBhuSnvopDkgFdFr1yWA62`). It lists the merged PRs, the identities, the evidence, the
coverage matrix and the open gates. It makes no claim beyond what it cites. NOT_RUN is never PASS.
Evidence classes are those of contract section 9.

## 1. Contract

The frozen contract governs #655, #745, #746, #665 and #747. Commit `60c80307` brought it to main as a
byte-identical copy of branch `om2/contract` at `23fc7f5c`. Rechecked on 2026-11-09 against the rad
branch and main:

| File | sha256 |
|---|---|
| `spec/omegese-om2.md` (FROZEN 2026-10-25) | `245bb74e940c811ab325e6fabb33f0599ad46aaf6b9064fd2750c43980040881` |
| `spec/omegese-om2-errata.md` (E1 to E18) | `7b8c1ea58738806cfc29a145a2d60ede5e1c399366a1665004859304bdd2d671` |
| `spec/omegese-om2-measure.md` (predeclared measurement protocol) | `507702d0e69ccc76cefb3675e2b22f7279497d362b42ee3043f3a1057aa17bad` |

`spec/omegese-om3.md` is the place for any change after the freeze. It is PROPOSED, a draft for #1008,
and this coordinator has not reviewed it. Its context ABI revision needs Drake's approval before merge.
See section 7 for its compatibility sentence.

## 2. Lanes, owners and merged PRs

The lanes write separate paths. Authors do not certify their own lane: L836 qualifies independently.

| Lane | Issues | Paths written | Merged on main (GitHub PR, merge commit) | Ledger state |
|---|---|---|---|---|
| L834 compiler slices | #655 #745 #746 #665 | `seed/omc/omc.om`, `seed/omc/om2/**`, `evidence/OM2-COMPILER/**` | S1 #750 `9e503929`, S2 #753 `996176a6`, S3 #754 `15f349da`, S4 #764 `638aa4da` | done |
| L836 independent qualification | #748 | `seed/qualification/om2/**` | #752 squash `725ca839` | done; re-anchor patch `2bf3ff98` awaits the desk merge |
| L837 native ABI v2 | #747 | omega-bridge `src/native.om`, `docs/NATIVE-ABI.md` | omega-bridge #15 `826cb8ae` (on bridge rad main `f6b7cc40`) | done |
| L838 SHA consumer | #747 #748 | `om/sha256/**`, `om/units.sh`, cutover of `src/sha256.c` | #776 merge `7505b3a3`; cutover commit `450bbefd` | open on contract section 8 (open gate 1 below) |
| L839 coverage matrix | #625 | `docs/omegese-coverage-matrix.md` | rad patch `35883be5`, head `f5f88d77`, awaits the desk merge | done |
| L1039 leak lane | #748 | `seed/qualification/om2/leak/**`, an addendum to `candidates/sha/RESULTS.txt` section 4 | none yet | open; card ready, not started |
| L835 coordinator | #599 | `spec/omegese-om2*.md`, measurement, this record | contract `60c80307`; measurement `775bcc14` (in #776); tutorial #777 `9c5ccd85` | open |

Branches superseded by these merges. Do not merge them.

| Branch (rad namespace of the delegate) | Head | Superseded by |
|---|---|---|
| `om2/contract` | `23fc7f5c` | `60c80307`; the three spec files are byte-identical |
| `om2/sha-compact` | `f5d14cb2` | #776; the unit source at main has the same sha256 `dbf002dd…94bb` |
| `om2/coverage-matrix` | `ae0816a0` | rad patch `35883be5`; the old matrix described main `acb3f15c`, 1484 commits earlier |

## 3. Identities at main, reproduced on 2026-11-09

Host CPU, AArch64 Linux. Rebuilt from a `git archive` of main with `sh seed/omega-from-seed.sh` and the
omc it bore. Two rows differ: the OM-1 omc was reborn from seed at `acb3f15c`, and the slice-compiler
row cites the slice PINS files and was not rebuilt.

| Object | Identity |
|---|---|
| seed-born omc (stage fixpoint) | `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`, equal to `seed/out/omc.sha256` and to the committed binary |
| OM-1 omc (contract section 0) | `734f0a39319fbfa930bcc62cb30dbf06d47d78e126372b74f5baf478e6126b61`, reborn from seed at `acb3f15c` |
| slice compilers | S1 `31342447…049f`, S1 fix `ce4facbe…f019`, S2 `c23b3376…b533`, S2 fix `20d00b6e…bf87`, S4 `49923639…03ec` (`evidence/OM2-COMPILER/*/PINS.txt`) |
| SHA unit source `om/sha256/sha256-om2.om` | `dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb` |
| SHA unit artifact (omc `6d1b1cf5`) | 21340 bytes, `27775fb2106dc0695d32417b1545af0027c136fe05bcdc4abd12cb473460570b`, the bytes L836 qualified with S4 |
| bridge generator | omega-bridge `96292423` (`om/omega-bridge.lock`), `src/native.om` `2c1bf637…f27d` = `NATIVE_PIN` |
| generated binding | `OMEGA_OMC=… OMEGA_BRIDGE=… sh om/units.sh --check`: rc 0, all five generated files regenerate byte for byte |
| #748 conductor `seed/qualification/om2/gate.om` | `49914d72313d9b0e3693dc52119658c81d6f955af29d24551275b5e4f7936caf` |
| leak scanner `seed/qualification/om2/leak/leakscan.om` | `aa60061ea85184d98f8fed41ad5b0ab2335d3697aba00a1eca80ba33b910e633` |

## 4. Evidence

| Claim | Class | Where | Result |
|---|---|---|---|
| slice gates S1 to S5 at main | HOST | `seed/omc/om2/s*/*.cases`, run by `gate.om` | 52/52, 21/21, 70/70, 64/64, 21/21; every compiled-omc.om mutant detected, every control PASS (L834 run 274, 2026-11-09) |
| seed gates at main | HOST | `bash tests/gates/run.sh seed` | rc 0, GATE5 PASS (179 cases), no SKIP (L834 run 280) |
| per-slice independent verdicts | HOST | `seed/qualification/om2/candidates/s{1,2,3,4}/RESULTS.txt` | S1 PASS after D1 fix `66af34d9`; S2 PASS after D-S2-1 fix `9a92f3c4`; S3 PASS; S4 head `f6a6492f` PASS |
| SHA unit qualification | HOST, SOURCE/RULE | `seed/qualification/om2/candidates/sha/RESULTS.txt` | OVERALL NOT_RUN, no FAIL, no defect: 158 vectors, ABI v2, E1/E3 receipts, updates of at least 2^32 bytes and 17/17 mutants PASS; section 8 static trace equivalence NOT_RUN for `update` and `final`; dynamic traces 28/28 equal |
| SHA parity with the replaced C | HOST | `sh om/sha256/parity/run.sh` (oracle: `src/sha256.c` at `a647b6a9`) | SHA256-PARITY PASS, lengths 0..9000 and 2000 cases, diff 0 (L838 run 293) |
| freestanding SHA parity | HOST | `make test-sha256-freestanding-parity` | rc 0; the K[0] red control fails as intended (L838 run 293) |
| tutorial and guarantee matrix | SOURCE | `docs/one_layer/OM2-TUTORIAL.md`, `examples/om2-tour.om` (#777) | merged |
| measurement | HOST | `om/sha256/om2-evidence/s4/measure/` | section 6 |

## 5. Coverage matrix (#625)

`docs/omegese-coverage-matrix.md` (L839) is the owner-linked matrix: 58 rows, evidence in every cell,
105 probes with the seed-born omc `6d1b1cf5`. At patch head `f5f88d77` it has sha256
`417b4cf98eb674e3137acb108e244566c6c759f9c06b15fd60c73fb9bbaa9b0b`. It is on main when rad patch
`35883be5` lands. Until then the patch is the canonical copy.

## 6. Measurement (`spec/omegese-om2-measure.md`)

The recorded run (`om/sha256/om2-evidence/s4/measure/RESULTS.txt`, commit `775bcc14`) ran on cpu 3. That
core is a Cortex-A725; the protocol requires a Cortex-X925. The run's arm B commit `0e5f02630` is not in
the repository. It also left out load, cold calls, per-arm SHA code size, stack, RSS and compile time
without declaring the omissions. The dated addendum `ADDENDUM-20261109-L835.txt` in the same directory
audits that run and records a new one: delivered main `1e3ecbba` against baseline `acb3f15c` on cpu 8
(Cortex-X925). Arms, drivers, raw samples, the Wolfram code that computed every statistic, and
`SHA256SUMS` are in `run-20261109/`.

| Result (new run, HOST, load 7.74 to 11.57) | Value |
|---|---|
| policy verdict | REGRESSION at 31, 32 and 55 bytes (B/A 1.053, 1.053, 1.105: +16 to +32 ns per call); PASS at every other size |
| bulk, at least 64 KiB | B/A 0.712 to 0.727 (PASS, limit 1.02) |
| 1 MiB in 1-byte chunks | B/A 0.494 |
| cold first call | 64 B: B/A 1.364; 1 MiB: B/A 0.714 |
| SHA unit machine code | A 20520 bytes, B 21340 bytes |
| peak RSS of the driver | 17772 KiB in both arms |
| unit compile time | median of 41: A 1.987 ms, B 2.329 ms |

Both runs agree that small single calls are slower and bulk hashing is faster. The small-input
regression is the open measurement item in section 8.

## 7. C1 and C2 at main

Contract section 0 states C1 (meaning) and C2 (bytes) for "734f0a39 and the OM-2 compiler". At the S4
compiler the frozen manifest `manifest-c2.txt` passes `OM2GATE PASS cases=5876 pass=5876` (#752; L834
run 274 reproduced it at `725ca839`). Rerun on 2026-11-09 at main with omc `6d1b1cf5` and conductor
`49914d72`, one manifest per call: `omc < seed/qualification/om2/gate.om > gate`, then
`./gate "$OMC" "$(cut -c1-64 seed/out/omc.sha256)" MANIFEST SCRATCH`.

| Manifest (declared delta for) | Result at main |
|---|---|
| `manifest-c2.txt` (#752, frozen) | 5835/5876, 41 FAIL |
| `manifest-c2-capacity.txt` (#768) | 3/3 |
| `manifest-c2-batch2.txt` (omc `2c824805`, #808 #810) | 1/3 (`c2-00015`, `c2-00033` fail) |
| `manifest-c2-fpvreg.txt` (#853) | 8/8 |
| `manifest-c2-closerange.txt` (#970, through omc `be8c5130` at main `474197e4`) | 0/4 |

Of the 41 frozen failures, 37 are output byte changes with the expected exit status. The other 4 are
the 3 former error-14 refusals, which now compile, and 1 error-3 refusal reported on a different line.
(L834 run 274 had counted 38 byte changes.) 66 later commits changed `omc.om` after `725ca839`.

Later OM-1 output changes are outside the OM-2 freeze. The project accepts them as declared deltas:
each delta manifest names the compiler and the cause and records how behaviour was checked. For
example, `manifest-c2-closerange.txt` compiles each row with the old and the new omc, runs both and
compares exit, stdout and stderr. `seed/omc/qualify-x86.py` layers the deltas over the frozen
manifest. No gate on main runs these manifests; L839's matrix lists `qualify-x86.py` as unwired.

Finding: at main the delta chain is incomplete. 18 of the 41 failing frozen rows have a declared
delta. All 4 changes of meaning are among them, and their deltas pass at main. But 6 of those 18
deltas fail again (batch2 `c2-00015` and `c2-00033`, all four closerange rows). The other 23 failing
rows have no delta. So 29 rows emit code that matches neither the frozen value nor a declared delta.
All 29 compile with the expected exit status, and only their bytes differ. Their behaviour has not
been compared with the old binaries. That is open gate 6.

The OM-3 draft says "the frozen C2 manifest compiles byte-identically". That sentence is false at main.
An OM-3 addition can be held to C2 only against the frozen manifest plus a complete delta chain at its
base pin. That correction belongs to the OM-3 review (open gate 5).

## 8. Open gates

1. **Section 8 static trace equivalence of the SHA unit.** Owner: L1039, then L838. The scanner
   revokes the E11 count declaration on 277 stores (`update`) and 357 stores (`final`). L1039 must
   land a sound leakscan E13 precision change with an independent review MERGE, then rerun the
   `update` and `final` scans on artifact `27775fb2`. Any new assumption in the scanner is a trust
   change for this coordinator and Drake. Until then #748 stays open and no constant-time claim is made.
2. **Desk merges.** Rad patches `2bf3ff98` (L836 re-anchor of two compiler mutants, reviewed MERGE)
   and `35883be5` (L839 coverage matrix, reviewed MERGE_AFTER_FIX, fixed), and the patch that carries
   this record.
3. **Small-input SHA calls.** Ledger L1043, not yet assigned. Under the predeclared policy, single
   `sha256_hash` calls of 31, 32 and 55 bytes are a REGRESSION (section 6). The likely cause is the
   ABI v2 call path in the generated binding [INFERENCE]. The omega-bridge generator pinned in
   `om/omega-bridge.lock` produces that binding. A change there needs its own run under the protocol.
   Bulk and streaming are faster.
4. **GitHub issues #599, #625 and #748** are open with no comments. Drake's order of 2026-11-07 stops
   every push and PR or issue update to github.com except the front-door repository. This record on
   Radicle is the issue update. Radicle holds no issues for this repository.
5. **OM-3 review.** Owner: L1042. `spec/omegese-om3.md` is PROPOSED and unreviewed by this
   coordinator. Its context ABI revision needs Drake's approval. Its C2 sentence needs the correction
   in section 7.
6. **OM-1 delta chain at main.** Owner: L1041. 29 frozen C2 rows emit code at main that matches
   neither the frozen value nor a declared delta (section 7). Each needs its causing commit and a
   behaviour comparison between the old and the new binary, in the form of
   `manifest-c2-closerange.txt`, recorded as a new declared delta. A row whose behaviour changed is a
   regression and must be fixed in `omc.om`.
