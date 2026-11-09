# Omegese / seeded compiler coverage matrix (#625, ledger L839)

Audit only. Baseline: omega-mv rad `main` at `1e3ecbba779ee84e2de70ec231e83533a9c61f45`; compiler
`seed/omc/omc.om` (19052 lines); `seed/out/omc` born from the seed for this audit by
`sh seed/omega-from-seed.sh` (rc 0) with sha256 `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`,
equal to the committed `seed/out/omc.sha256`. omega-bridge rad `main` at `f6b7cc4042bdf55d8f9d866c97439bb7e53506f5`.
Inspected 2026-11-09. This replaces the first version of this matrix (branch `om2/coverage-matrix` @`ae0816a03`,
baseline `acb3f15c`, 2026-10-25), which was never merged and which 1484 later commits on main made stale.
Every cell was re-read at `1e3ecbba`; claims of the first version that could not be re-checked are marked UNKNOWN.
Candidate work is checked with `git merge-base --is-ancestor <sha> 1e3ecbba`.

## Status vocabulary

- **SUPPORTED**: implemented in source and exercised by a named gate or test (the cell says when that test is not wired into a gate).
- **QUALIFIED**: an independent review or qualification receipt exists; the path or commit is given.
- **UNSUPPORTED**: absent and refused with a named compiler error, or absent and stated absent.
- **UNKNOWN**: inspection did not establish the status.
- *doc-only*: the claim appears only in documentation; no source or gate was found behind it.

## Abbreviations

- `omc.om`: `seed/omc/omc.om`. `OMG`: `docs/one_layer/OMEGESE.md`. `OMC-DONE`: `docs/one_layer/OM_COMPLETION.md`. `SPEC2`: `spec/omegese-om2.md`.
- **OMEGA-SEED** is `tests/gates/omega-seed.gate:4` (`gate: OMEGA-SEED`), which execs `tests/gates/run.sh seed` (:17-18). The `seed` case is at run.sh:171-179:
  - :172 builds the C oracles; :173 runs `seed/omega-from-seed.sh`.
  - :174 runs `sh seed/host/check.sh`; :175 fails on any `^SKIP`; :178 requires `PASS native-host qualification`.
  - :176-177 run `sh seed/omc/gate5.sh`; :179 requires `GATE5 PASS`. **gate5 is now wired.** It came in `56dfcbd9b` (2026-10-27, A).
- **`seed/host/check.sh`** at `1e3ecbba` (174 lines, last changed `a0d12c250`) does the following:
  - Without the oracles it exits 3 with NOT_RUN (:5-9).
  - Numbered gates: gate-ir (:11), gate7 (:12), gate8 (:13), gate-fma (:14), gate9..gate15 (:15-21), `seed/explain/gate.sh` (:22), gate16..18 (:23-25), gate-recursion (:26).
  - OM-2 `seed/qualification/om2/gate.om` (built :30) runs contracts.cases (:34), s5 (21 cases plus mutants, :36-48), contracts mutants (:49-59) and devcall mutants #1042 (:61-71).
  - security673 packets plus mutants #671 (:73-85).
  - om2 hex, 51 cases plus mutants (:87-99); bnd, 47 cases plus mutants (:101-113); fnhost (:115-127).
  - execenv (:130) and prlimit (:133); contract C parity (:140-153).
  - `seed/host/gate.om` (:155-157), negative.sh (:158), regression.sh (:159), cpufence.sh (:160), irq.sh (:161).
  - aien-ioctl.om (:162-164), readelf with no INTERP/NEEDED (:165-168), om/tls gcmsiv and reuse (:172-173).
  - `seed/host/gate.sh` no longer exists; `seed/host/gate.om` replaces it.
- **Not wired into OMEGA-SEED** (no reference from `tests/gates/` or check.sh at `1e3ecbba`):
  - `seed/omc/gate6.sh`, the structs gate. Only `seed/omc/qualify-ir-trap.sh:27` runs it, and that script is not referenced by any gate.
  - `seed/qualification/security673/gate669.om`.
  - `seed/omc/om2/s1..s4/*.cases`. Only evidence JSON references them (`evidence/x86_current_acceptance.1db7902d….json:161`).
  - `gate5.sh:68-74` (the `g4` helper) and `:130` rerun `seed/rung4/gate4.sh` with omc. That now runs inside OMEGA-SEED.
- Separate gate: `tests/gates/omega-security758.gate` runs run.sh security758 (:436-457). Its L4 tripwire is a "known false negative" (:456). It is not part of OMEGA-SEED.
- A probe is evidence, not a gate.
- Probe ids carry a group prefix (A arithmetic, M memory, B ABI, C control, T targets, L ledger and drift, X extra); Appendix A lists every probe with its exact source.

## Ledger

Ledger rows are the latest row per id in `~/handoffs/LEDGER.tsv` (`TSV:N` is its line). In the ledger table, A = ancestor of `1e3ecbba` (on main), NA = not an ancestor.

| Ledger | Owner, scope | State (updated) | Evidence @ 1e3ecbba |
|---|---|---|---|
| L408 | cc-omega-in-omega, compiler owner | done (11-09 02:00Z) TSV:409 | Cites rad main `408c76b7`, gate5 log `evidence/SEED-0/omc/gate5.log`, GATE5 PASS, and DDC parent L412 `10d75652`. gate5 is now in OMEGA-SEED (run.sh:176-179). Export compiler `seed/definition-export-L408@43f86be20` is NA. |
| L834 | worker/t_aff33175, om2 omc.om writer | open (11-09 07:17Z) TSV:830 | S1-S4 merges are all A: #750 `9e5039294`, #753 `996176a67`, #754 `15f349da7`, #764 `638aa4daa`, plus #752 `725ca8397`, #776 `7505b3a3e`, #777 `9c5ccd85b`. Still open: #748 qualification OVERALL NOT_RUN (sec8 trace; leakscan E13), per `~/handoffs/hive-breathe/L834.md`. |
| L835 | worker/t_e782e1c3, #599/#625 coordinator | open (11-09 05:05Z) TSV:831 | **Ledger text is stale.** It says om2/contract is unmerged. The rad `om2/contract@23fc7f5c9` is NA, but `spec/omegese-om2.md`, `-errata.md` and `-measure.md` on main are byte-identical to it (`git diff --quiet 23fc7f5c9 1e3ecbba -- …` exits 0). They landed via `60c803074` (2026-10-26). |
| L836 | worker/t_40ad2585, om2 qualification | done (11-09 07:21Z) TSV:832 | #752 `725ca839` (A). S1-S4 and SHA functional, ABI and mutants PASS. The sec8 trace is NOT_RUN. Re-anchor patch head `27d56a360` is NA (desk merge pending). |
| L837 | worker/t_88646c88, om2 ABI (bridge) | done (11-09 06:49Z) TSV:833 | omega-bridge rad main `f6b7cc40` via `826cb8ae` (#15). NATIVE-V2 PASS, 138/0, 7 callers. omc `export fn` is on main (omc.om:253-255, :12374); see L-P6. |
| L838 | worker/t_97cddecb, om2 SHA | open (11-09 02:00Z) TSV:834 | **Ledger text is stale.** It says om2/sha-compact is unmerged. `om2/sha-compact@f5d14cb23` is NA, but the #776 sha-cutover merge `7505b3a3e` is A: `om/sha256/sha256-om2.om` is on main (README.md:11) and `src/sha256.c` is absent. README.md:40 cites L836 qualification of 158 vectors. The L836 sec8 trace is still NOT_RUN. |
| L569 | hermes-universal, #625 semantics v1 | done (05:52Z) TSV:570 | `d9ce93af`, `f8068d85`, `c1da86d6`, `69790fb4` and `5f6436d6` are all A. Review commit `b00de4a6` is NA. |
| L575 | desk, #625 semantics v1 | dropped (05:13Z) TSV:576 | Superseded; `69790fb4` is A via `5f6436d6`. |
| L729 | worker/t_44438234, recursion #645 | done (05:45Z) TSV:730 | Candidate `hive/t_44438234-recursion-v2@e9081717e` is NA; patch `366e2667` awaits merge. `universal/645-bounded-recursion-L729@c434565c6` is NA. The main gate `seed/omc/gate-recursion.sh` is wired at check.sh:26 (landed via `f5c9bd89`, A). |
| L789 | codex-security673 | done (02:00Z) TSV:790 | `seed/qualification/security673` is on main; packets plus mutants are wired at check.sh:73-85. Ledger note: stale `embed.bin` needs re-derive. `gate669.om` is not wired. |
| L830 | orphan-01a170d6, #624 coordinator | dropped (05:05Z) TSV:828 | Superseded by omega-bridge. |
| L832 | codec-v2-owner, #621 | done (05:03Z) TSV:829 | `1683caaa`, `9a6392b0`, `fa9d9d19`, `29aafd45` and `82021724` are all A. Ledger says "gate not rerun by triage". |
| L608 | worker/t_481af7ed, #622 C exporter | open (05:02Z) TSV:609 | C17 u64 exporter v1 via #972 `f5c9bd89` (A). Ledger: TESTED, not QUALIFIED. |
| L615 | codex-macos-port | done (10-23 00:19Z) TSV:616 | Candidate `f67fea2c6` is NA. Rad `dev/macos-target-public-L615@809197d92` contains it; that branch is NA, as are `dev/macos-arm64-L615@f43e6755d` and `verify/macos-native-L615@80d88a6af`. |
| L624 | worker/t_7892a3be, macOS publication | open (05:13Z) TSV:625 | **Ledger text is partly stale.** It says `f67fea2c` exists only in local clones, but the commit is now on rad in `dev/macos-target-public-L615@809197d92`. It is still not on main. |
| L801 | worker/t_74c48f3b, x86-64 FR-9 | open (05:03Z) TSV:802 | Ledger: 233/16220 FAIL after `fix/x86-fma-order@0062602e`. `0062602e` and `1a7aa1e5` are A. OMC-DONE:72 says FR-9 is DRAFT (#923) and was last EMULATED. x86 source is in omc.om (:138, :144). |
| L184 | hermes-chat, #601 kernel words | dropped (05:52Z) TSV:185 | `d16aa5a4` and `268c9854` are A. OMC-DONE:71 still says FR-8 kernel words are absent. |
| L117 | cc-seed-rungs56, sm_121 rung 6 | done (10-20 10:50Z) TSV:118 | `217b7cc8` is A; GATE6 6091 programs (ledger). gate6.sh is not in OMEGA-SEED. |
| L775 | worker/t_33621d1e, #652 lead | open (05:05Z) TSV:776 | Rad `learning/652-lead-L775@dd28ebc0a` (NA) and `learning/652-corpus-L776@1a14972c3`. |
| L798 | unassigned, own/free doc drift | done (02:00Z) TSV:799 | It cites OMG:70, :95, :162, :524 and :584; those lines read as cited. Its claim that "omc refuses all four" is **wrong for break and trap** (L-P10 exit 4, L-P11 exit 105). It is right for `free` (L-P8 error 9) and for `own` (L-P14/L-P15 error 9; omc.om:11175-11176, :8506-8507). OMG:95 and :120 still list `own` with no omc refusal note (N5). There is no owner. |
| L839 | worker/t_ea4a6e7f, this matrix | open TSV:835 | `om2/coverage-matrix@ae0816a03` is NA; `docs/omegese-coverage-matrix.md` is absent on main. |

## Matrix

| # | Area | Status @ main | Owner (issue / ledger) | Evidence | Gap / next owner |
|---|---|---|---|---|---|
| 1a | Unsigned integer wrap (u8..u64) | SUPPORTED | #625 / L835 (open); compiler lane L408 (done) | omc.om:3526-3531 bo_fix: u8/u16/u32 canon after op; u64 native wrap. OMG:491. gate14.sh:39 u8_add, :45 u64_shl63_hi (Wolfram expectations, gate14.sh:2-4); gate14 wired via check.sh:20 (OMEGA-SEED). All 35 gate14 cases re-run at pin 6d1b1cf5: 0 fails. A-P20 ulong max+1 wraps to 0. | x86 wrap exercised by probe only, no wired x86 gate. |
| 1b | Signed overflow traps 1 (add/sub/mul/neg/shl/div MIN/-1) | SUPPORTED | #625 / L835; L408 (done) | omc.om:3535 chkext trap 1 (i8..i32); :3571-3573 i64 add/sub trapc 6 1; :3596-3600 i64 mul SMULH check trapc 1 1; :3619-3621,3644-3649 i64 div MIN/-1 trap 1; x86 twins xarith/xdiv (:16611, :16669). OMG:493-494. gate14.sh:58-65 (byte/short/int/long add, sub, neg, int_min_div, int_shl31, all 101); wired check.sh:20. A-P21 x86linux int add ovf exits 101 under qemu-x86_64. | x86 traps: probe only (qualify-x86.py not in OMEGA-SEED). |
| 1c | Div/rem by zero trap 2; MIN rem -1 = 0 | SUPPORTED | #625 / L835; L408 (done) | omc.om:3619 note; :3627-3628 `trapsite or 3019898880 rb 2` (CBZ to trap 2 unless fl bit 1); :3630 rem via MSUB. OMG:495-496. gate14.sh:70 div0, :71 rem0 (102), :51 i32_min_rem_neg1 (0); wired check.sh:20. A-P22 x86linux div 0 exits 102. | none on AArch64; x86 probe only. |
| 1d | Shift amount out of range traps 7 (all types, imm and reg) | SUPPORTED | #625 / L835; L408 (done) | omc.om:3538-3548 bo_schk CMP + trapc 2 7; :3688 bo_shl, :3724 bo_shr call bo_schk on the register path only; immediate path chosen only when the count is below the width (:4926-4928), so an out-of-range literal falls to the checked register path. OMG:497. gate14.sh:69 shift8 (107), wired check.sh:20. A-P7 `shl uchar 1 8`, A-P8 `shl ulong 1 64`, A-P10 `shr uchar 128 8` all exit 107; A-P9 register count 107; A-P27 x86 107. | Old gap (immediate path) closed by A-P7-A-P10 + :4926-4928. |
| 1e | Integer narrowing conversion traps 5 | SUPPORTED | #625 / L835; L408 (done) | omc.om:5541-5553 narrowing path, `chkext ra tt 5` at :5553. OMG:499-502 (trap 5; no implicit conversions, error 7). gate14.sh:66 conv_300, :67 conv_m129, :68 conv_2p31 (105); gate15.sh:49 e7_type_mismatch (error 7); both wired check.sh:20-21. Re-run at pin: gate14 0 fails, e7 gives error 7. | none. |
| 1e2 | Float to integer cast: truncate, saturate to destination, NaN to 0 | SUPPORTED | #625 / L835; commit b31ce3f2 (#815/#816) | omc.om:4684-4688 fp_toint (FCVTZS/FCVTZU, SQXTN/UQXTN for 8/16-bit); x86 xftoint :4055. OMG:663-665. gate8.sh:106 convert_sat (tests/float/convert_sat.om, e.g. :46 300.0 to uchar 255), wired check.sh:13; re-run exit 0. A-P13 300.0 to uchar = 255; A-P14 NaN to int = 0; A-P26 x86linux 255. | x86 path probe only. |
| 1f | Decimal literal parse / range (errors 6, 8) | SUPPORTED | #625 / L835; L408 (done) | omc.om:619 tok_num (calls tok_hex only when om2, :620-624); nfail 6 at :652,:655,:662 (more than 20 digits :654); nfail 8 at :667,:670,:679. OMG:503-507. gate15.sh:48 e6_bad_number, :50 e8_out_of_range; wired check.sh:21; re-run: 6 and 8. gate8.sh:119-121 float literal overflow error 8 (A-P23). | none. |
| 1g | Hex literals `0x..` | QUALIFIED (OM-2 units only); UNSUPPORTED in OM-1 units (error 6) | #745 / L834 (done), L836 (done) | 87a4f9bf (S1, merged 9e503929 PR #750); gates 4376c211 (#979). omc.om:1873-1876 tok_hex: `0X` (:1898-1899), no digits (:1905-1906), more than 16 digits (:1908-1909), bad digit (:1921) error 6. OMG:751-753; spec/omegese-om2.md:52-58. check.sh:87-88 hex.cases 51/51 + :89-99 3 tok_hex mutants killed (OMEGA-SEED). Re-run here: OM2GATE PASS cases=51. Qualification: seed/qualification/om2/candidates/s1/RESULTS.txt:58 PASS; L836 re-exercised at 6d1b1cf5. A-P1 16; A-P2 OM-1 error 6; A-P3 error 6; A-P4 error 8; A-P29 x86 16. | genkw.awk:1-7 header still says the language has no hex numbers (drift N3, left for the next reseed). |
| 1h | `qty` checked unsigned 64-bit quantity (new) | SUPPORTED (tests NOT wired into OMEGA-SEED) | #756 / no ledger row found | 107f9354 (Refs #756), merge dfda5ea7 PR #909; d94a503f (#914) domains. genkw.awk:20 `qty:223`; omc.om:3441-3442 type 13; :3576-3582 add trapc 2 1 / sub trapc 3 1; :3603-3608 mul UMULH trapc 1 1; :3640 unsigned div; :4915-4918 bitwise ops error 7; :5442-5444 `not` error 7; x86 :16631-16645. language.cases:38-40 (101), :59 narrow 105, :62 mixed error 7, :77 and error 7, :82 rotr error 3; run here: OM2GATE PASS cases=75. A-P15,A-P16 101; A-P17,A-P18 error 7; A-P19 42; A-P28 x86 101. | Wire language.cases into check.sh; spec/quantities-and-modular.md:7 still PROPOSED; OMEGESE has no qty section. Owner #756. |
| 2 | Floats f32/f64: IEEE arithmetic, compare, convert, literals | SUPPORTED (AArch64 gated; x86linux probe only) | #625 / L835; v registers #853 (4722cba5, fix 9920aab1 #994); literal rounding #1024 | omc.om:112-125 float twins; :4193-4197 one scalar FP instruction, round to nearest even; :4636-4638 fp_tov. OMG:618-651. gate8.sh:75-79 f64_bits/f32_bits/arith/compare/convert, :84 intrinsics, :107 vreg, :108 vcmp, :109 bitcast_int, :119-122 refusals (error 8, IR error 3), :131-138 lit_round 512 literals; wired check.sh:13; fixtures re-run: all exit 0, refusals match. A-P25 x86linux float exits 6. OMC-DONE:17-18. | x86 float has no wired runtime gate. IR floats refused error 3 (OMC-DONE:51). |
| 2b | Explicit fused `fma` | SUPPORTED (AArch64); UNSUPPORTED on x86 (error 9) | #1024/#1027 (7e93ca8e, merge 555562c6 PR #1049 into #1050); x86 order 0062602e | genkw.awk:20 `fma:227`; omc.om:4500-4502 ffma FMADD; :8438-8441 dispatch. OMG:627, :652-662. gate8.sh:86 fma run, :87-94 neg_fma error 7/11, :95-102 x86-target type refusals 7/11, :103-104 x86/x86efi error 9, :105 IR error 3; gate-fma.sh:11-45 fused control + 4 mutants, wired at check.sh:14. A-P11 fma 2 3 1 = 7; A-P12 x86 error 9. | None in AArch64 scope; the stale gate-fma.sh:2 header is fixed in this change (N6). |
| 3 | SIMD / vector words | UNSUPPORTED | none found (no issue, no ledger row, no rad candidate branch) | genkw.awk:18,20 keyword table: no vector/lane word (v-prefixed only view, void, vfio*). omc.om uses SIMD&FP registers for scalar float only (:4193-4197, :4686 scalar SIMD FCVTZ); "vector" occurs only as env vector (:6246, :6272). OMG:625 "SIMD twin" = scalar twin register. A-P5 `vadd` error 3 (OM-1), A-P6 error 3 (OM-2). Rad refs scanned: 56 heads, no SIMD candidate (only hit is rad main = 1e3ecbba, vaddr notes). NEON appears only in C kernels (spec/mixed-algebra-ma2.md:58-66). | Needs a spec + owner issue; none exists. |
| 4a | Initialization of storage | SUPPORTED | #746 / L834 (open) | `new T N v` fills each element: OMEGESE.md:94, M-P9 (`new uchar 8 7`, `get q 5` exits 7). Globals zero at start: `omc.om:9443`, OMEGESE.md:514, M-P10 exits 0. `new S` without values refused: `gate6.sh:95` `missing_val` -> 4 (gate6 NOT wired). OM-2 `fresh` scratch read before write -> error 27: `gate15.sh:65` `e27_fresh_get` (gate15 wired, `check.sh:21`) | Old cite `gate16.sh:41` no longer an init case (now a `const` case); dropped. gate6 not in OMEGA-SEED. #746 |
| 4b | Definite assignment across branches | SUPPORTED by scoping; no dedicated gate case | #746 / L834 | OMEGESE.md:39-41 (name first written in `if`/`else`/`while`/`for` dies at `end`). M-P1 (branch-only write, read after) -> `error 3` line 6; M-P12 control (written before `if`) runs, exits 5 | No named branch-only-write case in gate15/16; only generic `e3_unknown_name` (`gate15.sh:45`, wired). Add a wired case. #746 |
| 5a | Allocation: stack arrays/structs, fixed pools; no heap | SUPPORTED | L408 (done) | No heap: `omc.om:5`, `:11358-11360`. Local cap 4 MiB -> 23: `omc.om:8876-8877`, `:11702-11703`, `:17096-17097`; `gate15.sh:63` `e23_size_capacity` (wired); M-P7 (4194305 B) -> error 23, M-P8 (4194304 B) runs 0. `new` only in outermost block: `gate6.sh:91` `new_in_if` -> 9. Stack floor: `omc.om:3296-3297` `stkchk` B.LO trap 6 | gate6 cases not wired |
| 5b | `free` / `own` words | UNSUPPORTED (error 9); *doc drift* | L798 (state done, owner unassigned) | Keywords own:77, free:81 (`genkw.awk:18`). Refusal: `omc.om:11175-11176` (77/78/79/81 -> fail 9), `:14174-14175` (77 -> fail 9). M-P3 `own q` -> error 9; M-P4 `free q` -> error 9; M-P14 `own` as param kind -> error 16. `free` gate: `gate6.sh:89` `still_free` -> 9 (NOT wired). OMEGESE.md:524 says free refused | OMEGESE.md:95 still lists `own` as a move word that omc refuses; no gate case for `own`; `still_free` not in OMEGA-SEED. Fix doc row and add wired cases. L798 needs reopen/owner |
| 5c | Allocation failure / cleanup; mapping table; fixed-bind quarantine | SUPPORTED (bounded) | L408; #636; L834 | Stack exhaustion: `seed/rung4/tests/t_stack.want`=106 via `gate4.sh:92-96` loop, run with omc by `gate5.sh:130` (`gate5.sh:75` runs the same tests under rung-4 om4); gate5 now wired (`run.sh:177-179`, 56dfcbd9b). M-P11 unbounded recursion exits 106. Mapping table 128 slots: `omc.om:7052-7053`; `host/gate.om:57-60,741-742` (`check.sh:156-158`). Owned fixed bind b80044183, quarantine ce35b3518 (both ancestors of 1e3ecbba): `omc.om:7415-7419`; `fnhost.cases:23` `fnhost-bind`; mutants `fn-own`, `fn-quarantine` (`mutants.cases:41-54`), wired `check.sh:115-126`; MAPPING.md:118-121 | fnhost cases are emit-sha + mutant only; no run of the double-failure path. No user finalizer; lifetimes lexical (`omc.om:11359-11360`) |
| 6a | Aliasing: one array/struct passed twice -> 19; globals never passed | SUPPORTED (globals, wired); same name: UNKNOWN by gate (in source, probes only) | #746 / L834 | `omc.om:5665-5672` `ca_arr`, `:12999-13004` `ca_dist`; `gate15.sh:59` `e19_global_passed` (wired). M-P2 `f q q` -> error 19; M-P5 struct `f p p` -> error 19; M-P6 control (two arrays) runs 0. OM-2 two parts of one array: `s4.cases:44` `s4-p-bad-two` -> 19 (s4.cases not wired into OMEGA-SEED) | No gate case for the same array or struct passed twice. #746 |
| 6b | Struct layout: 8-byte cells, no padding; `sizeof`/`offsetof` | SUPPORTED | L408 | `omc.om:2294-2296`, `:11358-11361`; `tests/layout/sizes.om` via `gate10.sh:9` (wired, `check.sh:16`); M-P13 `sizeof` {uchar,ulong} = 16. `gate6.sh` 26 cases (`:115`) NOT wired (only `qualify-ir-trap.sh:27`, itself unwired) | gate6 not in OMEGA-SEED |
| 6c | External C layout (packed fields, endianness) | SUPPORTED (run cases in s3.cases, explicitly NOT wired; refusal e29 wired) | #746 / L834 (df8291ecd) | OM-2 `layout NAME SIZE` / `field F T [N] at OFF little` (or `big`): `omc.om:12280-12285`, `:12412`, `:12568`. `gate15.sh:68` `e29_layout_past` (wired). `s3.cases:6-12` `s3-l-rw`, `-trap`, `-bad-overlap` (not wired); M-P16 `l-rw.om` exits 0, stdout = `l-rw.out`; M-P15 overlap -> error 29 | s3.cases not in OMEGA-SEED; wire it. #746 |
| 6d | SHA-256 104-byte context | SUPPORTED (exercised by gate OMEGA-OM-UNITS, which is separate from OMEGA-SEED; not rerun here) | #747 / L838 (ledger still open; text stale) | #776 merged 7505b3a3e (cutover 450bbefd4); `src/sha256.c` deleted. `om/sha256/sha256-om2.om:23-26` `layout shactx 104` (state@0, count@32, buf@40); generated `src/omega_api_decl.h:23-25` `OMBR_ASSERT` size and offsets; that header is compiled by `om/units.sh` and `om/sha256/parity/run.sh`, both run by `tests/gates/run.sh:400-410` (`om-units`) | Not in OMEGA-SEED. L838 ledger row says unmerged although #776 is on main |
| 7a | Fixed-length `view`/`edit` parameters | SUPPORTED | L408 (done) | B-P2 view read gives 7. B-P3 put to a view is refused with error 20 (`seed/omc/error-codes.reg:25`). B-P4 edit write gives 9. `seed/omc/gate6.sh:86` `refuse put_view ... 20` (gate6 is not seed-wired: check.sh does not call it. It runs from `seed/omc/qualify-ir-trap.sh:27`). `gate15.sh:60` e20 is a write-to-text case and is seed-wired (check.sh:21). | The `put_view` view-param refusal is not in OMEGA-SEED. Wire gate6 into check.sh, or add a view-param e20 case to gate15 (omega lane). |
| 7b | Variable-length slices in .om (OM-2 `view T *` / `edit T *`) | SUPPORTED (OM-2 units only); UNSUPPORTED in OM-1 (error 16) | #747 / L837 (done), L836 | `seed/omc/omc.om:244-247` (unsized view: count register nm_lr), `:5199`, `:9774` peekstar. B-P6 `len` gives 5. B-P7 out-of-range get traps 103 (trap 3). B-P5: OM-1 `*` gives error 16. Cases: `seed/omc/om2/s4/s4.cases` (s4-v-ok, s4-v-len, s4-v-trap-get=103, s4-v-bad-sized=7), not seed-wired: among the `.cases` lists check.sh runs only contracts, s5, hex, bnd, fnhost, devcall mutants, security673 packets, execenv and prlimit. Exercised end to end by `om/sha256/sha256-om2.om:283,321` (`d view uchar *`) in gate OMEGA-OM-UNITS (`tests/gates/run.sh:400-408`). | Wire s4.cases into check.sh (omega lane). MUTANTS.md M9b slice-check mutant: B NOT_RUN. |
| 7c | Native call ABI v1/v2 (function-mode units from C/C++/Python/Rust/Zig/Go) | SUPPORTED | #747 / L837 (done); bridge L483 (done) | `om/units.sh:26` OMC_PIN 6d1b1cf5... = W/omc = seed/out/omc.sha256. `:27` NATIVE_PIN 2c1bf637... = sha256 of bridge `962924233:src/native.om` (= `om/omega-bridge.lock`, ancestor of bridge f6b7cc40). Bridge main `src/native.om` is now e2077722, which is not the pin. bridge NATIVE-ABI.md:586-590 (status 1..14, 32..35). Refusal between ABI versions: an OM-2 unit gets no `omega_NAME`, so a v1 caller fails to link (NATIVE-ABI.md:784-786). Identity check is `om/units.sh:52` + `--check`. Gate OMEGA-OM-UNITS (`tests/gates/omega-om-units.gate`, not seed-wired). | Runtime ABI version negotiation is still absent (link-time refusal only). The omega pin is 10 bridge commits behind on native.om (a215e62..). Re-pin is the bridge/omega lane's job. No independent review receipt found. |
| 7d | Slices across the native ABI (bridge ABI v2) | SUPPORTED | #747 / L837 (done); bridge #15 | bridge `826cb8a` merge of feat/slice-abi (2026-10-28), ancestor of bridge f6b7cc40 (merge-base check OK). bridge `docs/NATIVE-ABI.md:773-805`: unsized view/edit = 2 slots (ptr, count), with status 32 checks. Case: bridge `tests/native/v2/run.sh:278` (eight slots refused). omega: SHA cutover `450bbefd` deleted `src/sha256.c` and `om/sha256/sha256.om`, so the old 4096-byte chunk limit is gone. `om/units.sh:31` UNITS includes sha256-om2.om, and `src/omega_om_units.ident` gives `abi=2 profile=OM-2`, src sha `dbf002dd...` = sha256 of sha256-om2.om (checked). | L838 (SHA adapter removal) is still `open` in the ledger, but the cutover is merged (`450bbefd`). Close L838 or record why it stays open. |
| 8 | Modules / import / separate compilation | UNSUPPORTED (single unit) | #601 K5 / L184 (dropped); #636 FR-3 / L408 (done) | B-P1 `import sha` and B-P8 `use sha` both give `error 16` (`error-codes.reg:21`). `seed/omc/genkw.awk:18` keyword list has no import/use/module. Capacity is now 4096 functions and 8192 globals: `gate12.sh:45-48` (accept g8192 / refuse g8193 14, accept f4095 / refuse f4096 14), seed-wired (check.sh:18). Within one unit, OM-2 `export fn` gives several entries (NATIVE-ABI.md:788 multi-entry). Units still link only as C bindings in one translation unit (`om/units.sh:29,54`). | Modules or a linker have no owner now that L184 is dropped. A #601/#636 successor needs a fresh issue. |
| 9a | Traps (1..14), program exit 100+N, function mode `OscRt.trap` | SUPPORTED | L408 (done) | OMG:76-78, 431-432; `omc.om:11134-11140` (s_trap, code outside 1..14 is `fail 8`); `gate14.sh:58-73` (16 trap rows: 101/102/103/104/105/107), check.sh:20; `gate7.sh:65-66` t1 105, t2 107, `:71-72` bad_trap0/bad_trap15 error 8, check.sh:12; `seed/host/gate.om:472` `trap3` (used :780, :786, :842), check.sh:155-157; trap 6 `t_stack` (gate4 under omc, gate5.sh:130). All wired into OMEGA-SEED. C-P9 (103), C-P8 (106) | Trap 6, 9, 10 not in gate14 (6 via gate4/gate5; 9/10 via contracts OMG:1559-1560) |
| 9b | Exceptions / handlers | UNSUPPORTED (absent) | #625 (spec) | No try/catch/throw/raise/handler entry in `genkw.awk:18` or `:20` (keyword lists). C-P10: `try` as a statement is error 4. A trap ends the program or calls `OscRt.trap` (OMG:76-78) | Absence only; no dedicated refusal code |
| 9c | Effects / capabilities (general least authority) | UNSUPPORTED | #670 / L789 (done) | OMG:976-977 host words "do not form a sandbox", run with the process's permissions. `evidence/SECURITY-673/STATUS.md:30` grant identity/generation/revocation/durable budgets BLOCKED. `seed/effects/effects.om` (manifest, syscall verify, seccomp cBPF; added f56a372ae #971) gated only by `seed/effects/check.sh`, **not wired** (no reference in tests/gates or seed/host/check.sh) | #670 grants/revocation; wire `seed/effects/check.sh` into OMEGA-SEED |
| 9d | Cancellation / deadlines | UNSUPPORTED in the language; process-level words SUPPORTED | #670/#673 L789 (done) | No cancel/deadline keyword in `genkw.awk:18,20`. Words: `sleepns` OMG:1027, `waitio` timeout OMG:1038, `killpid`/`waitpid` OMG:1044-1045 (ids 127/116/120/123, genkw.awk:18); exercised by `seed/host/gate.om:414-459` (waitx, killpid, waitpid, sleepns, fork), check.sh:155-157, wired. `prlimit` CPU limit is 9f. Deadline coordinator `security673/gate669.om` (README:30 "30-second deadline"), **not wired** | No language cancellation construct; #625 spec |
| 9e | Strict exec profile `execpure` (198) + close_range before exec | execpure: SUPPORTED, gate **not wired**; close_range: QUALIFIED (narrow) | #670 / L789 | `genkw.awk:18` execpure:198; `omc.om:6534-6537` close_range for 124/198/233, `:6546-6553` profile, `:16340-16342` x86 error 25; OMG:1049, 1147 ("fixed profile, not a general sandbox"). Gate `seed/qualification/security673/gate669.om` + pure-*.om, evidence `pure2`/`pure3`, **not wired**. close_range: `evidence/SECURITY-673/independent670/REPORT.md:7` (independent, base 7a169290, narrow descriptor property only). Merge 1db941627 (#970), ancestor of 1e3ecbba | Wire gate669/pure-launch into OMEGA-SEED; no wired check of close_range in check.sh |
| 9f | `execenv` (233) exact child env, `prlimit` (235) rlimits | SUPPORTED (wired) | none in ledger (searched) | `genkw.awk:20` execenv:233, prlimit:235; OMG:1050, 1051; `omc.om:6397-6400`, `:6919-6922` (prlimit64), x86 `:15537-15539`. Gates: `seed/host/execenv/execenv.cases` (24 rows incl. oracle, fnmode, contract, 4 mutants) at check.sh:130; `seed/host/prlimit/prlimit.cases` (37 rows incl. 7 mutants) at check.sh:133; wired. Merges 6efc45728 (#1074, execenv 7d9ed10fd), 1e3ecbba (prlimit a0d12c25 / 0610a848d) | Not a sandbox; no ledger row; output/wall-clock budgets need a supervisor (OMG:1147-1148) |
| 10a | Recursion: program mode self and mutual | SUPPORTED | L408; #645 L729 (done) | OMG:482-487; `seed/rung4/gate4.sh:81-82` (fib), `:159-161` (`r5b_mut`), run with omc by `seed/omc/gate5.sh:130`, now wired (`tests/gates/run.sh:176-179`, commit 56dfcbd9b). `seed/omc/gate-recursion.sh` (nest.om depth 16/17 status 40, fuel 42, source mutants) wired at check.sh:26 (f5c9bd89a, #972). C-P2 (55), C-P8 (106) | No compiler depth limit; only the 8 MiB stack (trap 6) |
| 10b | Recursion: function mode / IR mode | UNSUPPORTED (error 9 / error 3) | L408 | Function mode: `omc.om:10834-10838` (unsettled call-graph node: `put dsev 0 3`, `fail 9`); `gate4.sh:162` `r5b_cycle.om` error 9 (under omc via gate5:130, wired). C-P1: error 9. IR mode: OMG:1226-1227 (self and forward calls error 3); C-P7: error 3 | Design decision; #645 v2 candidate does not lift it |
| 10c | Fuel / logical recursion budget | UNSUPPORTED in the compiler at main; program-level pattern SUPPORTED | #645/#646 L729 (done) | Compiler global `fuel` is expansion fuel (`omc.om:94-96`), not runtime. Runtime bound only stack trap 6 (`omc.om:3296-3297` stkchk) and `while` bound trap 4 (`gate14.sh:73` `bound` 104). Program-level fuel status 42: OMG:484-487, gate-recursion.sh (check.sh:26, wired). **candidate** recursion-v2: rad `hive/t_44438234-recursion-v2`@e9081717, `universal/645-bounded-recursion-L729`@c434565c: `merge-base --is-ancestor` rc=1 (not on main). Desk merge e1f4c382 is bundle-only; verdict MERGE_AFTER_FIX (`~/handoffs/hive/manager/reviews/omega-mv-e1f4c382*.verdict.txt`) | Fix the untested ">64 nodes" refusal, merge v2; #646 cache fuel open |
| 11a | Concurrency: CPU threads, atomics | UNSUPPORTED | #636 FR-6 / L408; #601 K3 / L184 (dropped) | `OM_COMPLETION.md:69` FR-6 threads/atomics absent, decision 37 no design. OMG:1134-1135 (forked children independent; "no shared-memory threads"). No thread/atomic/ldxr/stxr/ldar/stlr keyword in `genkw.awk:18,20`; no LDXR/LDAXR/STLR/STXR/LDAR emit in omc.om (grep). In value position `y = ldxr x` and `y = atomic x` are error 3 (X-P1, X-P2). As statements, `ldxr x` / `atomic x` compile (C-P3, C-P11) because `<name> <value>` is assignment with `=` left out (OMG:61; control C-C1), so they bind a local, not an atomic | #636 / decision 37 |
| 11b | Process concurrency (fork/wait) | SUPPORTED | L408 | OMG:1044-1045, 1134-1135; `seed/host/gate.om:447` fork, `:420` waitpid, `:435` killpid, PASS text `:107`, `:109`; check.sh:155-157, wired | (gate.sh replaced by gate.om) |
| 11c | GPU memory ordering / synchronization | UNSUPPORTED in Omegese (no .om GPU target ordering model) | #625 spec; #638 | OMG:1220 "Ordering against a GPU is not qualified here" (cpufence comment `omc.om:11148` claims GPU visibility, unqualified). MEMBAR/ATOMG/BAR exist only in asm2 tables `seed/sm121/names.tsv:28-32,71`; `seed/sm121/gate6.sh` **not wired** (no reference in tests/gates or check.sh); `evidence/SEED-0/sm121/gate6.log` last line "GATE6 PASS" (historical log, not rerun) | Ordering model for a .om GPU target; qualify cpufence vs GPU |
| 11d | Races / race detection | UNKNOWN (no shared-memory threads to race; no detector found) | #625 spec | No race detector found in omc.om or seed/ (grep); no shared-memory threads (OMG:1134-1135) | Not inspected beyond grep |
| 11e | CPU ordering: `cpufence` (199), `cpurelax` (200) | SUPPORTED (wired) | #939 / #946 (no ledger row found) | `genkw.awk:20`; `omc.om:11145-11169` (DSB SY 3573759903=d5033f9f / MFENCE; YIELD / PAUSE); OMG:1204-1220. `seed/host/cpufence.sh` (fixture exit 42 AArch64 + qemu x86, objdump count, 5 refusals :71-75, NOP mutant :84-90) at check.sh:160, wired. IR refusal error 16 not gated (OMG:1212-1213); C-P6 error 16. C-P4 (7), C-P5 (fn mode compiles). Merge d94617177 (#946), ancestor | cpufence.sh exits NOT_RUN 3 without qemu-x86_64 (:15-16); IR refusal ungated |
| 12 | Serialization / format evolution: omc outputs | UNSUPPORTED (no version refusal in omc's own outputs); one consumer refuses | #621 / L832 (done); #625 | omc writes OSC IR version 1 (`omc.om:13012`, `:14425` header magic/version 1/nfuncs). ELF and the unit stream (`om/units.sh:48-49`, `omega-ident 1`) are not refused by version. The seeded consumer `seed/wasm/irwasm.om:57,1849` refuses with irwasm 21 VERSION for anything except v1/v7 (`error-codes.reg` irwasm 21). `gate-irwasm.sh` is not seed-wired (only `gate-ir.sh`, check.sh:11). | Unknown-version refusal in omc's stream readers (`om/units.sh` ident, OSC IR) is an open omega task. irwasm gate is not in OMEGA-SEED. |
| 12b | #621 source-aware codec v2/v3 | SUPPORTED (host/nativeCPU) | #621 / L832 (done) | Merged in train `f5c9bd89` (#972, 2026-10-30). Old candidate `1683caaa` is an ancestor of 1e3ecbba. `src/source-aware/core-v2.om:564-566` refuses any header version other than 1 or 2 with 66. `core-v3.om:2` accepts 1, 2, 3. Spec: `spec/universal/source-aware-v2.md:23,171` (66 UNKNOWN_VERSION). Gate: `mk/source-aware-v2.mk` target `test-source-aware-v2` -> `tests/universal/source-aware/v2_compat.mjs:154-159,197` (versions 0, 3, 255, envelope, dialect, op and sidecar all give 66; frozen v1 refuses v2 with 66). This is a make target: no tests/gates/*.gate, not seed-wired. | No .gate manifest exists, so OMEGA gates do not run it. NOT_RUN here (the make target needs bridge SA_SEED_REPO and node). |
| 13a | Diagnostics | SUPPORTED: line + code, plus byte span, category, finality, repairability in `check`/`next` modes and `om2 diag` records | #655, #797 (RM8) / L834 (done), L775 | `omc.om:346-379` `fail` (human line, then `drec` :370-374 om2 diag, `diagrec` :375-377 check mode, exit code :378); `chk_mode` :1507; `diagrec` :2703-2788 (repairability :2762); `emit_query` :2790. Wire format `docs/one_layer/DIAGNOSTICS_V1.md`. Registry `seed/omc/error-codes.reg` (33 cases in `gate15.sh`, count check :124, codereg drift :126-134, 3 negative controls :146-152, PASS :154; wired, check.sh:21). T-P6, T-P7, T-P8, T-P10. Added by faa30a8b, 91c83438 | `check`/`next` text output (`omega-diag v1`, `omega-query v1`) is exercised only by `tests/diagnostics/experiment_issue655.sh`, which no gate, mk or workflow references. No wired case asserts a span/category/repairable record. #655 / #797 |
| 13b | Source maps / debug info (DWARF, symbols) | UNSUPPORTED (absent); trap-site to source-line records SUPPORTED under `om2 diag` | #797 (RM8); none for DWARF | No DWARF/`.debug`/symtab/shstrtab string in `omc.om` (grep empty). ELF header note `omc.om:10731-10733`: 2 program headers, no sections; T-P2 and T-P15 `readelf -S`: "There are no sections". `omc-site 1 line=N iter=k` per trap site: `omc.om:10479-10481`, OMEGESE.md:793-795; T-P15 stderr `omc-site 1 line=5 iter=-`. Wired via `contracts.cases:41-42` (`diag.want`, `diagunroll.want`), check.sh:34 | No address-to-line map, symbols or debugger format. No owner found |
| 14 | Language profile versioning / compatibility | SUPPORTED: in-band profile line OM-1 / OM-2 (`om2`, `om2 diag`, `om2 fmt`, `om2 debug/release`); no numeric version. OM-3 is *doc-only* | #625 / L835 (open); #745; #1008 (OM-3) | OMEGESE.md:735-739: the opt-in rule (non-note first line exactly `om2`, otherwise OM-1). Also :754 fmt, :1490 debug/release. Spec frozen `spec/omegese-om2.md` (`60c80307`). B-P6 OM-2 is accepted. B-P10 `om2 fmt` writes the canonical text and the run fails 127 (the output is source, as designed). B-P9 `om3` gives error 16. `spec/omegese-om3.md:3` "Status: PROPOSED (draft omega-mv#1008)". Profile is recorded per unit in `src/omega_om_units.ident` (`om/units.sh:47,52`). Seed-wired: om2 s5/hex/bnd/fnhost (check.sh:36,87,101,115), regression.sh (check.sh:159), gate17, gate18 (check.sh:24-25). #625 `spec/universal/semantics.md` is on main (`f5c9bd89`). `profiles.json` lists c17/rust/python/cpython/osc-v5 only. | The #625 contract has no seeded-omc OM-1/OM-2 profile (L835 open). Independent review receipt for the profile mechanism: UNKNOWN (the old b00de4a6 receipt was not re-verified). |
| 15a | AArch64 Linux host | SUPPORTED | L408 (done), L834 (done); #650 (DDC) | `omc.om:1-4`; ELF header `omc.om:10731-10734`; fixpoint `seed/omega-from-seed.sh:52-59` (stage1==stage2==stage3, writes `seed/out/omc.sha256`); `tests/gates/run.sh:171-179` (OMEGA-SEED). Committed pin 6d1b1cf5 = W/omc sha256 (checked). T-P2 exit 7. Ledger L834: `run.sh seed` RC=0 on 1e3ecbba (run280, ledger claim, not rerun here). DDC: `seed/qualification/ddc650/ddc.om` (a48b60410, ancestor), ROADMAP-1.0.md:75 "PROPOSED gate, host EXERCISED at 62d1d0d6", not in a gate manifest | DDC650 not wired into OMEGA-SEED. No whole-compiler independent qualification receipt found; same-lineage fixpoint only. #650 |
| 15b | sm_121 words | SUPPORTED for asm2 table words (gate not wired); UNSUPPORTED as an omc target | L117 (done); #638 | `seed/sm121/gate6.sh` present (last touched d04110e89); chip receipt `evidence/SEED-0/sm121/chip/receipt.json` present, not rerun (no GPU). Not referenced by `tests/gates/run.sh` or `seed/host/check.sh`. omc targets: only `x86linux`/`x86efi`, anything else error 25 (`omc.om:17238-17246`; T-P4). Host device words 166..177 (README.md:34); `seed/host/aien-ioctl.om` wired check.sh:162-164; `devcall` OMEGESE.md:1184-1197 | omc emits no GPU code. #638 |
| 15c | macOS ARM64 (L615) | UNSUPPORTED on main; candidate f67fea2c6 (object only, no branch ref) | L615 (done), L624 (open); #634 | `target macos` error 25 (T-P9; `omc.om:17245`). `git merge-base --is-ancestor f67fea2c6 1e3ecbba` false; same for 80d88a6a, f43e6755. No `ports/` dir on main. No local or Radicle head contains them (`git branch -a --contains` empty; 56 rad heads, none macOS). f67fea2c6 tree has 65 `ports/macos-arm64/` files incl. `evidence/final-review/independent-review-80d88a6.md` (not reread) | Not merged; candidate QUALIFIED claim not re-verified (UNKNOWN). L624 / #634 |
| 15d | x86-64 Linux (FR-9) | SUPPORTED (emulated); not QUALIFIED | L801 (open); #629, #923 | `target x86linux`: `omc.om:17238-17240`, OMEGESE.md:438-449; bf54b19f (#923). T-P1 exit 7 under qemu-x86_64; T-P13/T-P14 AArch64-only words refused 25. Wired x86 cases: `gate8.sh:55-104` (refusals), `cpufence.sh` (check.sh:160), fnhost x86 mutants (check.sh:114-127), execenv (:128-130), prlimit (:131-133), aien-ioctl with qemu-x86_64 (:162-164). Qualifier `seed/omc/qualify-x86.py` not wired; receipt `seed/qualification/x86-linux/20261030-main-62d1d0d6.json` status EXERCISED_NOT_QUALIFIED, EMULATED | X86-LINUX.md:3 "native x86 qualification NOT_RUN"; :438-445 aggregate FAIL (NOT_RUN cases), independent review outstanding. L801 / #629 |
| 15e | RV64 (note) | UNSUPPORTED on main | #630 | `target riscv64` error 25 (T-P4). No riscv/rv64 file in `git ls-files`. Candidate `c02989f2` (object only, no branch ref) not an ancestor; its tree adds `evidence/UNIVERSAL-630/qemu-prerequisite/README.md`. ROADMAP-1.0.md:305 "PROPOSED, out of 1.0" | #630 |
| 15f | x86-64 UEFI PE32+ (`target x86efi`) | SUPPORTED in source; exercised only under emulation, run harness not wired | none found (5ce9ecaa) | `omc.om:17241-17243` (xtarget 2), `:144-145`; OMEGESE.md:451-461 (whole programs only, `efi` word 178). 5ce9ecaa (ancestor). T-P3: PE32+ EFI application; T-P5 bare unit error 25. Wired: `gate8.sh:55-104` fma refusals, `gate18.sh:30` keyword scope. `tests/x86efi/run.sh` (QEMU q35 + OVMF) referenced by no gate. X86-EFI.md:3 "EXERCISED under emulation; not QUALIFIED on hardware" | ROADMAP-1.0.md:304 corrected in this change (N7). Hardware qualification and wiring of `tests/x86efi/run.sh` have no owner |
| 16a | Source adapters on main | SUPPORTED in source, not in OMEGA-SEED; built by an off-main compiler | #624 / L830 (DROPPED) | On main via f5c9bd89a (#972): `src/source-aware/{core,core-v2,core-v3,main}.om`, 17 `src/adapters/*.om`, `spec/universal/*`. Makefile targets `mk/translation.mk:30-56` (G1..G3); advisory workflow `.github/workflows/translation-g1-arm64.yml:1-5` ("GitHub gates no merge"). Pinned omc 734f0a39 from seed f8588e10 (`mk/translation.mk:7-8`), not the current pin. Codec needs bridge 0fc7d866: not an ancestor of omega-bridge f6b7cc40, no `tools/source-aware` there. Current omc refuses them (T-P16-T-P20) | Not wired into any `tests/gates/*.gate`. L830 dropped: "superseded by omega-bridge". Rebuild path against the current pin and bridge main has no owner |
| 16b | #621 codec, #622 C import (u64) | SUPPORTED in source; #622 import QUALIFIED (bounded); #621 v1/v2 codec review UNKNOWN / pending | #621 / L832 (done); #622 / L608 (open) | cd2c41f3, f5b5b3f6, 1683caaa, e63768a9 are ancestors of 1e3ecbba. #622 receipt `evidence/UNIVERSAL-622/independent-L602/review-L602.md:3` "PASS for the reviewed, explicitly bounded source contracts". #621: `evidence/UNIVERSAL-621/README.md:3` "Author verification only. Independent reviewer ... PENDING"; `spec/universal/source-aware-v2.md:7` "Independent review is pending". Tests `mk/c-u64-import.mk`, `mk/source-aware*.mk` not wired | #621 independent review; #622 export / other widths (L608) |
| 16c | G1 C17 <-> .om (import, lower, export, native call) | SUPPORTED in source (Make target, not wired); QUALIFIED claim UNKNOWN | #624 / L830 (DROPPED); #623; #622 / L608 | 2ef48347, 9cae82c8, fc2c2f93, e8227f6d, e671e7be, 42117f51 are ancestors of 1e3ecbba. `mk/translation.mk:30-37` `test-translation-g1`. Hosted run 40203533129 and the #624 "G1 QUALIFIED" comment were not re-verified (gh blocked by local guard); no G1 receipt under `evidence/` on main. Status vocabulary `spec/universal/translation-v1.md:136-142` | Re-verify the G1 receipt against the current pin. Owner dropped (L830) |
| 16d | Rust #626, Python #627, C++ #739, Zig #740, Go #741 (u64 profiles) | SUPPORTED in source, author self-test only | #626/#627/#739/#740/#741 via L830 (DROPPED); L832 | 4b7e8b76, 8439284e, 0c1c1b3c, dbe268cf, 07b0e889 are ancestors of 1e3ecbba. `src/adapters/{rust,python,cpp,zig,go}-u64-{import,export}.om` (+ `rust-i64-export.om`). `mk/rust-u64.mk:2` "Author self-test only (TESTED)"; G2/G3 targets `mk/translation.mk:40-56` not wired | No independent receipt found in `evidence/` for these profiles; v2 review pending (`source-aware-v2.md:7`) |
| 17a | #669 branch displacement | SUPPORTED; QUALIFIED only for the 2026-10-23 bounded slice, before the bdisp refactor | #669/#673 L789 (done) | `omc.om:3042-3057` `bdisp` (w=19 / 26, error 24 at :3050, :3054), `patch19` :3059-3072, `patch26` :3075-3090 (dc0d06e95, #948). Wired: `gate15.sh:112-122` accept side 262142 lines (:119) and `expect e24_branch_range 24 262147` (:122). Review `evidence/SECURITY-673/independent669/REPORT.md:3-7` (2026-10-23, "no remaining finding in the tested branch-limit slice"). `gate669.om` run: security673/README.md:185 (omc 7a8b84fc) | `gate669.om` not referenced by any gate/sh/mk. No review after dc0d06e95. STATUS.md:28-29: long backward reachability NOT_RUN; release/consumer audit BLOCKED. #669 |
| 17b | #670 least authority / #671 hostile parsers / #672 device isolation | #670 strict launch profile SUPPORTED (not wired), descriptor slice QUALIFIED (bounded); #671 packed-list ingress SUPPORTED and wired, source families QUALIFIED (bounded); #672 devcall cap SUPPORTED; device isolation otherwise UNKNOWN | L789 (done); #670, #671, #672, #1042 | #670: `execpure` 198 (`omc.om:838`, `:7926`; OMEGESE.md:1049), security673/README.md:73-87, `seed/authority/*.om` (workflow `om-profile-arm64.yml` only), review `independent670/REPORT.md:7`. #671: `packets.cases` + 3 mutants check.sh:72-85; review `independent671/REPORT.md:7`. #672: devcall cap mutants check.sh:60-71, OMEGESE.md:1184-1197 | #670 grants, generations, revocation BLOCKED (README.md:87, STATUS.md:30). No #672 review receipt found. Assembled-system review NOT_RUN (STATUS.md:53) |
| 17c | Timing / secret-dependent leakage | SUPPORTED: `dit`/`scrub` words (AArch64, OM-2 program mode); general constant-time UNSUPPORTED (NO CLAIM); TLS timing screen measured, not wired | #748 (L838 open); #875; #673 | OMEGESE.md:861-900; 23678743 (#875); s5 21 cases + 9 mutants wired check.sh:35-48; T-P12 exit 1; T-P13/T-P14 x86linux error 25. OM2-TUTORIAL.md:231 "NO CLAIM"; ROADMAP-1.0.md:35 out of scope. `om/tls/THREAT_MODEL.md:40`: `timing.om` v3 Welch t-test 2026-10-26, `tls_cteq` LEAK SUSPECT, host only, no gate. `om/sha256/README.md:42` "no constant-time claim" | No `.om` outside `seed/omc/om2/s5` uses `dit`/`scrub`. `om/tls/README.md:277-279` corrected in this change (N8); the library still does not set DIT. No x86 DIT equivalent. No constant-time codegen contract owner |

## Candidate missing dependencies

Search method: `rad issue list --repo rad:z6do9WDBhuSnvopDkgFdFr1yWA62 --all` returned "Nothing to show" (rad storage has 30 patches and no issues). I also grepped the ledger and the repo at `1e3ecbba`. GitHub issue search was NOT_RUN (no gh in this audit).

- **C1. CPU SIMD/vector semantics in .om: unowned for omc.**
  - genkw.awk has no vector keyword. OMG:625 says floats use the "SIMD twin" register for one scalar FP instruction only.
  - New partial owner outside omc: Hive NG `seed/ng/IR.md`. It is "PROPOSED draft v0.1" (:5), with a VEC type (:95), and :170 plans NEON lowering in `src/a64.om`. That file has no vector ops.
  - No ledger id covers NG vector work. `~/handoffs/hive-ng/DECISIONS.md:237` says "VEC and CALL wait on a64/NEON".
- **C2. Debug info: partly owned.**
  - There is still no DWARF or section table. `omc.om:10731` elfhdr is a 176-byte header (the old cite was :5767).
  - New: an om2 trap-site source map. SPEC2:114, OMG:793 and omc.om:10479 provide `omc-site 1 line=N iter=k` under `om2 diag`, with fixtures `seed/omc/om2/s2/sites.err` and `s1/diag-ok.err`.
  - Runtime symbols and a line table remain unowned.
- **C3. Constant-time: partly owned (L836).**
  - SPEC2 §8 (:225) defines a trace-equivalence leakage model; :239 says speculative constant-time is UNSUPPORTED.
  - `seed/qualification/om2/leak/leakscan.om:2` is a static scan (#748).
  - OMEGA-SECURITY758 has a known L4 false negative (run.sh:456).
  - The L836 sec8 trace is NOT_RUN. Owner: L836/L834.
- **C4. Gate wiring: partly resolved.**
  - gate5 is wired (run.sh:176-179, `56dfcbd9b` A). The L813 fix `e17039d9c` is A.
  - Still unwired and unowned: gate6.sh, gate669.om, and the om2 s1..s4 case files.
  - L798 is "done" with owner "unassigned", and `own` drift remains (N5).
  - Git grep of `seed/omc/*.sh`, `seed/omc/**/*.om`, `error-codes.reg`, `seed/host/*.sh` and `tests/gates/*` found no gate case that pins the `own` refusal.
- **C5. GPU memory ordering: owned at PROPOSED draft only.**
  - `seed/ng/IR.md` defines atom scope and order (:303) and the `sync` block barrier (:353). It calls the GB10 path "untested until ng-gpu's chip check" (:376-379).
  - The ng-gpu lane (`~/handoffs/hive-ng/gpu/IR-GPU-DRAFT.md`) has no ledger id.
  - omc has no atomics, only `cpufence`/`cpurelax` (genkw ids 199, 200).

## Observed drift

- **D1.**
  - FR-5 is **resolved**: OMC-DONE:68 now says it is implemented (ids 166..177, matching `genkw.awk:18`; gate `seed/host/gate.om:744-745` mapio).
  - FR-7 was drift (fixed in this change; OMC-DONE FR-7 row rewritten): the row said "shared objects/C ABI | absent", but omc.om:253-255 and :12374 implement `export fn` multi-entry units (SPEC2 §6 :167, OMG:739). L-P6 compiles two exports to a 24-byte unit with a B table. omega-bridge NATIVE-V2 is done (L837).
  - OMC-DONE:3-7 says its counts are not refreshed since OM-2. OMC-DONE was last changed in `96ea448ad` (2026-10-31).
- **D2.** OMG §3 and §9.8 match omc for break (OMG:70, L-P10), trap (OMG:610-613, L-P11) and free (OMG:524 and :584, L-P8). They do **not** match for `own` (N5). L798's text is wrong for break and trap.

New drift items (doc vs source, both at `1e3ecbba`):

- **N1.** (fixed in this change; FR-2 row rewritten) OMC-DONE:65 said for FR-2 that "packed u8/u16/u32/u64 fields are not expressible", and OMC-DONE:78 listed FR-2 as decision-bound (section 4 now says FR-2/7 stay decision-bound only for OM-1 units). In fact omc.om:12280 implements `layout NAME SIZE` / `field … at OFF little|big` (OMG:796-802). L-P3 runs and exits 1, which is the big-endian high byte.
- **N2.** (fixed in this change; item 4 rewritten) OMC-DONE:55 said generic byte utilities need "open arrays". omc.om:244-246 implements unsized `view T *` / `edit T *` (OMG:833). L-P4 exits 7; the OM-1 control L-P5 gives error 16.
- **N3.** `seed/omc/genkw.awk:2` says "The language has no hex numbers". omc.om:1873-1876 `tok_hex` implements OM-2 hex (OMG:751). L-P1 exits 42; the OM-1 control L-P2 gives error 6. This is generator-comment drift.
- **N4.** OMG:732 says the `seed/omc/om2/` fixtures are "run by the #748 gate". check.sh runs only s5 (:36), hex (:87), bnd (:101) and fnhost (:115) from that tree. The s1..s4 `*.cases` files have no runner.
- **N5.** OMG:95 lists `own arr` as "move" and OMG:120 lists "Arrays: `own|edit|view`". omc refuses `own`: omc.om:11175-11176 (statement) and :8506-8507 (value) both give `fail 9`. L-P14 and L-P15 give error 9; L-P12 (`f own b`) gives error 16.
- **N6.** (fixed in this change) `seed/omc/gate-fma.sh:2` called the gate candidate-only, but `seed/host/check.sh:14` runs it in OMEGA-SEED (row 2b).
- **N7.** (fixed in this change) `docs/ROADMAP-1.0.md:304` said x86efi was removed from the draft; `target x86efi` is on main (5ce9ecaa, row 15f). `README.md:34` calls AArch64 Linux the one supported profile and its next bullet describes x86linux as a DRAFT candidate; that is consistent and unchanged.
- **N8.** (README fixed in this change) `om/tls/README.md:277-279` said `msr DIT, #1` needs a compiler word omc lacks; `dit` landed in 23678743 (#875) (row 17c). The library still does not set DIT, which stays true. `om/tls/THREAT_MODEL.md:52-56` is the dated outside-audit brief and is left as written.

Left open, with the reason: N3 sits in `seed/omc/genkw.awk`, a compiler input, so a change belongs with the next reseed by the compiler lane (L834/L408). N4 and N5 are OMEGESE.md rows, and OMEGESE.md is under an active claim by bay-2 t_82f66d3d (CLAIMS.md 2026-11-09T07:25:38Z); they go to the OMEGESE owner after that lane lands.

## Appendix A: probes

All probes ran with the omc above (sha256 `6d1b1cf5…7f1f8`) under `nice -n 19 taskset -c 19`. Source lines are shown separated by ` / `. Compile result is omc's stderr and exit code; run exit is the program's status (100+N is trap N). x86linux binaries ran under `qemu-x86_64` (EMULATED).

| id | source | compile | run exit |
|---|---|---|---|
| A-P1 | `om2 / fn main to int / x = uint 0x10 / ret int x / end` | 0 | 16 |
| A-P2 | `fn main to int / x = uint 0x10 / ret int x / end` | `omc: line 2: error 6` | n/a |
| A-P3 | `om2 / fn main to int / x = uint 0X10 / ret int x / end` | `omc: line 3: error 6` | n/a |
| A-P4 | `om2 / fn main to int / x = int 0xffffffff / ret 0 / end` | `omc: line 3: error 8` | n/a |
| A-P5 | `fn main to int / x = vadd ulong 1 ulong 2 / ret 0 / end` | `omc: line 2: error 3` | n/a |
| A-P6 | `om2 / fn main to int / x = vadd ulong 1 ulong 2 / ret 0 / end` | `omc: line 3: error 3` | n/a |
| A-P7 | `fn main to int / x = shl uchar 1 8 / ret int x / end` | 0 | 107 |
| A-P8 | `fn main to int / x = shl ulong 1 64 / ret int x / end` | 0 | 107 |
| A-P9 | `fn main to int / s = uchar 8 / x = shl uchar 1 s / ret int x / end` | 0 | 107 |
| A-P10 | `fn main to int / x = shr uchar 128 8 / ret int x / end` | 0 | 107 |
| A-P11 | `fn f a f64 b f64 c f64 to f64 / ret fma a b c / end / fn main to int / r = f f64 2.0 f64 3.0 f64 1.0 / ret int r / end` | 0 | 7 |
| A-P12 | `target x86linux / fn main to int / x = fma 1.0f64 2.0f64 3.0f64 / ret 0 / end` | `omc: line 3: error 9` | n/a |
| A-P13 | `fn c x f64 to uchar / ret uchar x / end / fn main to int / ret int c 300.0 / end` | 0 | 255 |
| A-P14 | `fn c x f64 to int / ret int x / end / fn main to int / z = f64 0.0 / n = div z z / ret int c n / end` | 0 | 0 |
| A-P15 | `fn main to int / a = qty 18446744073709551615 / b = qty 1 / c = add a b / ret int 0 / end` | 0 | 101 |
| A-P16 | `fn main to int / a = qty 1 / b = qty 2 / c = sub a b / ret int 0 / end` | 0 | 101 |
| A-P17 | `fn main to int / a = qty 5 / b = and a 1 / ret int 0 / end` | `omc: line 3: error 7` | n/a |
| A-P18 | `fn main to int / a = qty 5 / b = ulong 3 / c = add a b / ret int 0 / end` | `omc: line 4: error 7` | n/a |
| A-P19 | `fn main to int / a = qty 40 / b = add a 2 / ret int ulong b / end` | 0 | 42 |
| A-P20 | `fn main to int / x = ulong 18446744073709551615 / y = add x 1 / ret int y / end` | 0 | 0 |
| A-P21 | `target x86linux / fn main to int / x = add int 2147483647 1 / ret int x / end` | 0 | 101 |
| A-P22 | `target x86linux / fn main to int / x = div int 1 int 0 / ret int x / end` | 0 | 102 |
| A-P23 | `fn main to int / x = f64 1.0e400 / ret 0 / end` | `omc: line 2: error 8` | n/a |
| A-P24 | `fn main to int / z = f64 0.0 / y = div f64 1.0 z / if gt y f64 1.0e300 / ret 0 / end / ret 1 / end` | 0 | 0 (1/0 = +inf, no float trap) |
| A-P25 | `target x86linux / fn f a f64 b f64 to f64 / ret add mul a b f64 0.5 / end / fn main to int / r = f f64 2.0 f64 3.0 / ret int r / end` | 0 (x86-64 ELF) | 6 |
| A-P26 | `target x86linux / fn c x f64 to uchar / ret uchar x / end / fn main to int / ret int c 300.0 / end` | 0 | 255 |
| A-P27 | `target x86linux / fn main to int / x = shl uchar 1 8 / ret int x / end` | 0 | 107 |
| A-P28 | `target x86linux / fn main to int / a = qty 18446744073709551615 / b = qty 1 / c = add a b / ret int 0 / end` | 0 | 101 |
| A-P29 | `target x86linux / om2 / fn main to int / x = uint 0x10 / ret int x / end` | 0 | 16 |
| A-P30 | `om2 / target x86linux / fn main to int / x = uint 0x10 / ret int x / end` | `omc: line 2: error 16` | n/a |
| M-P1 | fn main to int / c = int 1 / if eq c int 1 / x = int 5 / end / ret x / end | error 3 (line 6) | - |
| M-P2 | fn f a edit uchar 4 b edit uchar 4 to void / end / fn main to int / q = new uchar 4 0 / f q q / ret 0 / end | error 19 (line 5) | - |
| M-P3 | fn main to int / q = new uchar 4 0 / own q / ret 0 / end | error 9 (line 3) | - |
| M-P4 | fn main to int / q = new uchar 4 0 / free q / ret 0 / end | error 9 (line 3) | - |
| M-P5 | struct P x uint end / fn f a view P b view P to void / end / fn main to int / p = new P 1 / f p p / ret 0 / end | error 19 (line 6) | - |
| M-P6 | fn f a view uchar 4 b view uchar 4 to void / end / fn main to int / q = new uchar 4 0 / r = new uchar 4 0 / f q r / ret 0 / end | 0 | 0 |
| M-P7 | fn main to int / q = new uchar 4194305 0 / ret 0 / end | error 23 (line 2) | - |
| M-P8 | fn main to int / q = new uchar 4194304 0 / ret 0 / end | 0 | 0 |
| M-P9 | fn main to int / q = new uchar 8 7 / ret int get q 5 / end | 0 | 7 |
| M-P10 | global g ulong 4 / fn main to int / ret int get g 3 / end | 0 | 0 |
| M-P11 | fn d n ulong to ulong / ret add d add n 1 1 / end / fn main to int / ret int d 0 / end | 0 | 106 |
| M-P12 | fn main to int / c = int 1 / x = int 0 / if eq c int 1 / x = int 5 / end / ret x / end | 0 | 5 |
| M-P13 | struct S a uchar b ulong end / fn main to int / ret int sizeof S / end | 0 | 16 |
| M-P14 | fn f a own uchar 4 to void / end / fn main to int / q = new uchar 4 0 / f q / ret 0 / end | error 16 (line 1) | - |
| M-P15 | om2 / layout z 8 / field a uint at 0 little / field b ushort at 2 big / end / fn main to int / ret 0 / end | error 29 (line 4) | - |
| M-P16 | seed/omc/om2/s3/l-rw.om (repo file) | 0 | 0, stdout cmp l-rw.out SAME |
| B-P1 | `import sha / fn main to ulong / ret 0 / end` | `omc: line 1: error 16` | - |
| B-P2 | `fn f a view ulong 4 to ulong / ret get a 1 / end / fn main to ulong / a = new ulong 4 0 / put a 1 7 / ret f a / end` | 0 | 7 |
| B-P3 | `fn f a view ulong 4 to void / put a 1 7 / end / fn main to ulong / a = new ulong 4 0 / f a / ret 0 / end` | `line 2: error 20` | - |
| B-P4 | `fn f a edit ulong 4 to void / put a 1 9 / end / fn main to ulong / a = new ulong 4 0 / f a / ret get a 1 / end` | 0 | 9 |
| B-P5 | `fn f a view ulong * to ulong / ret len a / end / fn main to ulong / a = new ulong 4 0 / ret f a / end` (OM-1) | `line 1: error 16` | - |
| B-P6 | `om2 / fn f a view ulong * to ulong / ret len a / end / fn main to ulong / a = new ulong 5 0 / ret f a / end` | 0 | 5 |
| B-P7 | `om2 / fn f a view ulong * to ulong / ret get a 9 / end / fn main to ulong / a = new ulong 5 0 / ret f a / end` | 0 | 103 (trap 3 bounds) |
| B-P8 | `use sha / fn main to ulong / ret 0 / end` | `line 1: error 16` | - |
| B-P9 | `om3 / fn main to ulong / ret 0 / end` | `line 1: error 16` | - |
| B-P10 | `om2 fmt / fn main to ulong / ret 0 / end` | 0, stdout = the 27-byte canonical source | 127 (output is text, not ELF) |
| C-P1 | `fn f x ulong to ulong / if eq x 0 / ret 0 / end / ret f sub x 1 / end` | `omc: line 5: error 9` | - |
| C-P2 | `fn f x ulong to ulong / if lt x 2 / ret x / end / ret add f sub x 1 f sub x 2 / end / fn main to int / ret int f 10 / end` | 0 | 55 |
| C-P3 | `fn main to int / x = ulong 1 / ldxr x / ret 0 / end` | 0 (binds local `ldxr`) | 0 |
| C-P4 | `fn main to int / cpufence / cpurelax / ret 7 / end` | 0 | 7 |
| C-P5 | `fn f x ulong to ulong / cpufence / cpurelax / ret x / end` | 0 (12-byte unit) | - |
| C-P6 | `ir / fn f x ulong to ulong / cpufence / ret x / end` | `omc: line 3: error 16` | - |
| C-P7 | `ir / fn f x ulong to ulong / if eq x 0 / ret 0 / end / ret f sub x 1 / end` | `omc: line 6: error 3` | - |
| C-P8 | `fn f x ulong to ulong / ret add 1 f add x 1 / end / fn main to int / ret int f 0 / end` | 0 | 106 (stack trap 6) |
| C-P9 | `fn main to int / trap 3 / end` | 0 | 103 |
| C-P10 | `fn main to int / try / ret 0 / end / end` | `omc: line 3: error 4` | - |
| C-P11 | `fn main to int / x = ulong 0 / atomic x / ret 0 / end` | 0 (binds local `atomic`) | 0 |
| C-C1 | `fn main to int / zqzq ulong 6 / ret int zqzq / end` (control for C-P3/C-P11) | 0 (om4 also 0) | 6 |
| T-P1 | `target x86linux / fn main to ulong / ret 7 / end` | 0; ELF 64-bit x86-64 static | 7 (qemu-x86_64) |
| T-P2 | `fn main to ulong / ret 7 / end` | 0; ELF AArch64, no sections, 2 LOAD | 7 |
| T-P3 | `target x86efi / fn main to ulong / ret 7 / end` | 0; PE32+ executable (EFI application) x86-64 | not run |
| T-P4 | `target riscv64 / fn main to ulong / ret 7 / end` | 25, `omc: line 1: error 25` | n/a |
| T-P5 | `target x86efi / fn f a ulong to ulong / ret a / end` | 25 at line 1 | n/a |
| T-P6 | `check / fn main to ulong / ret 7 / end` | 0; stdout `omega-diag v1` | n/a |
| T-P7 | `check / fn main to ulong / x = ulong 1 / ret q / end` | 3; stderr `omc: line 4: error 3`; stdout `om1 NAME span=33-34 UNKNOWN REPAIRABLE code=3 line=3 expect=name found=q` | n/a |
| T-P8 | `check / fn main to ulong / while true` | 15; `om1 SYNTAX span=28-28 INCOMPLETE REPAIRABLE code=15 line=3 expect=end found=eof` | n/a |
| T-P9 | `target macos / fn main to ulong / ret 7 / end` | 25 at line 1 | n/a |
| T-P10 | `next / fn main to int / a = ulong 3 / while lt a 9` | 0; stdout `omega-query v1`, `scope: function`, constructs list, `a ulong local`, `fn main to int` | n/a |
| T-P11 | `target x86linux / fn main to ulong / emit 3573751839 / ret 7 / end` | 11 at line 3 (does not reach the emit-on-x86 refusal) | n/a |
| T-P12 | `om2 / fn main to int / d = dit int 1 / e = dit int 0 / ret int add d e / end` | 0 | 1 |
| T-P13 | `target x86linux / om2 / fn main to int / d = dit int 1 / ret int d / end` | 25 at line 4 | n/a |
| T-P14 | `target x86linux / om2 / fn main to int / k = scrub 16 / ret int k / end` | 25 at line 4 | n/a |
| T-P15 | `om2 diag / fn main to int / x = int 4 / if eq x 4 / trap 3 / end / ret 0 / end` | 0; stderr `omc-site 1 line=5 iter=-`; `readelf -S`: no sections | 103 |
| T-P16 | file `src/source-aware/core.om` | 4, `omc: line 62: error 4` | n/a |
| T-P17 | file `src/source-aware/core-v2.om` | 4 at line 63 | n/a |
| T-P18 | file `src/adapters/c-u64-import.om` | 4 at line 587 | n/a |
| T-P19 | file `src/adapters/rust-u64-import.om` | 4 at line 820 | n/a |
| T-P20 | file `src/adapters/go-u64-export.om` | 3 at line 73 | n/a |
| L-P1 | `om2 / fn main to int / ret int 0x2a / end` | 0 | 42 |
| L-P2 | `fn main to int / ret int 0x2a / end` | `line 2: error 6` | - |
| L-P3 | `om2 / layout pk 4 / field a ushort at 0 big / field b uchar 2 at 2 little / end / fn fill c edit pk to void / put c a 0x0102 / put c b 1 9 / end / fn main to int / c = new uchar 4 0 / fill c / if ne get c 3 9 / ret 2 / end / ret int get c 0 / end` | 0 | 1 |
| L-P4 | `om2 / fn plen v view uchar * to ulong / ret len v / end / fn main to int / a = new uchar 7 0 / ret int plen a / end` | 0 | 7 |
| L-P5 | L-P4 without the `om2` line | `line 1: error 16` | - |
| L-P6 | `om2 / export fn f a ulong to ulong / ret add a 1 / end / export fn g a ulong to ulong / ret add a 2 / end` | 0 (24 bytes: `14000002 14000003 91000400 d65f03c0 91000800 d65f03c0`) | not run (function mode) |
| L-P7 | L-P6's first export plus `fn main to int / ret 0 / end` | `line 2: error 9` | - |
| L-P8 | `fn main to int / a = new uchar 4 0 / free a / ret 0 / end` | `line 3: error 9` | - |
| L-P9 | `fn f a own uchar 4 to ulong / ret ulong get a 0 / end / fn main to int / b = new uchar 4 3 / ret int f b / end` | `line 1: error 16` | - |
| L-P10 | `fn main to int / k = ulong 0 / while lt k 10 bound 20 / k = add k 1 / if eq k 4 / break / end / end / ret int k / end` | 0 | 4 |
| L-P11 | `fn main to int / trap 5 / end` | 0 | 105 |
| L-P12 | `fn f a view uchar 4 to ulong / ret ulong get a 0 / end / fn main to int / b = new uchar 4 3 / ret int f own b / end` | `line 6: error 16` | - |
| L-P13 | L-P9 with `edit` instead of `own` in the parameter (negative control) | 0 | 3 |
| L-P14 | `fn main to int / b = new uchar 4 3 / own b / ret 0 / end` | `line 3: error 9` | - |
| L-P15 | `fn main to int / b = new uchar 4 3 / c = own b / ret int get c 0 / end` | `line 3: error 9` | - |
| X-P1 | `fn main to int / x = ulong 1 / y = ldxr x / ret 0 / end` | `omc: line 3: error 3` | - |
| X-P2 | `fn main to int / x = ulong 0 / y = atomic x / ret 0 / end` | `omc: line 3: error 3` | - |

Arithmetic probe expectations were computed with WolframLanguageEvaluator: `{FromDigits["10",16], 2*3+1, IntegerPart[2.0*3.0+0.5], Min[IntegerPart[300.0],255], 40+2, Mod[2^64-1+1,2^64]}` -> `{16, 7, 6, 255, 42, 0}`.

## Appendix B: changes from the first version (`ae0816a03`, baseline `acb3f15c`)

### Rows 1-3

- 1a: status unchanged; bo_fix now omc.om:3526-3531 (file grew 7838 to 19052 lines); old OMG:431 not re-verified, replaced by OMG:491; L408 now done; gate5 now wired (56dfcbd9).
- 1b: unchanged status; bo_div/bo_add lines moved from 1963-1966 to 3571-3573/3644-3649; x86 xarith/xdiv twins added and probed (A-P21).
- 1c: unchanged; CBZ trap now omc.om:3627-3628; x86 probe A-P22 added.
- 1d: gap "immediate-shift path not separately audited" closed: immediate path only for count below width (omc.om:4926-4928), A-P7/A-P8/A-P10 trap 107.
- 1e: unchanged; old OMG:439-441 and gate15:33 replaced by OMG:499-502 and gate15.sh:49 (lines shifted).
- 1e2: new split; saturating float-to-int casts landed b31ce3f2 (#815/#816), gated gate8.sh:106.
- 1f: unchanged; tok_num moved 171 to 619; gate15 lines 32/34 now 48/50.
- 1g: UNSUPPORTED (error 6) -> QUALIFIED for OM-2 units: 87a4f9bf merged 9e503929 (#750), gates 4376c211 (#979), wired check.sh:87-99; OM-1 units still error 6 (A-P2).
- 1h: new row; qty landed 107f9354 / dfda5ea7 (#909, #756), d94a503f (#914); tests exist but are not wired.
- 2: AArch64 status unchanged; floats now in v registers 4722cba5 (#853), literal rounding #1024 (gate8.sh:131-138); x86linux float compiles and runs (A-P25), was "AArch64 only"; old omc.om:856-1107, OMG:543-580, OMC-DONE:65 not re-verified, replaced.
- 2b: new split; fma landed 7e93ca8e (merge 555562c6), x86 refusal order 0062602e; gate8 + gate-fma wired.
- 3: unchanged UNSUPPORTED; old genkw.awk:16 and omc.om:3407 now genkw.awk:18,20 and omc.om:6246/6272; A-P5/A-P6 error 3.

### Rows 4-6

- 4a: dropped `gate16.sh:41` (no longer an init case); added `e27_fresh_get` (fresh scratch); line numbers refreshed (omc.om 7838 -> 19052).
- 4b: OMEGESE cite moved to :39-41; M-P1/M-P12 rerun at 1e3ecbba, same result.
- 5a: cap sites now `omc.om:8876/11702/17096`; M-P7/M-P8 boundary probes added.
- 5b: refusal moved to `omc.om:11175,14174`; new M-P14; doc drift OMEGESE.md:95 found; L798 now state done but `own` gap remains.
- 5c: gate5 now wired (56dfcbd9b), so t_stack=106 is OMEGA-SEED evidence; old `seed/host/gate.sh` deleted (1db941627), replaced by `host/gate.om`; owned fixed bind b80044183 and quarantine ce35b3518 on main with wired mutants.
- 6a: added struct-twice M-P5 and OM-2 `s4-p-bad-two`; still no wired same-name case.
- 6b: gate6 still not wired; gate10 cite confirmed wired.
- 6c: packed layouts no longer absent: OM-2 `layout` (df8291ecd) with endianness; was UNSUPPORTED.
- 6d (split from 6c): `src/sha256.c` assert gone; ctx is now an .om layout after #776 (7505b3a3e).

### Rows 7, 8, 12, 14

- 7a: status is unchanged. The old `gate15.sh:44` e20 citation is replaced by `gate15.sh:60` (that case is a text write). gate6 is not seed-wired. Re-proved by B-P2-B-P4.
- 7b: UNSUPPORTED becomes SUPPORTED for OM-2 units, from the #747 S4 compiler work and the SHA cutover `450bbefd`. The `n <= 4096` / `src/sha256.c:31` evidence is gone because both files were deleted in `450bbefd`. s4.cases is not seed-wired.
- 7d (new split): bridge ABI v2 slices merged (bridge #15 `826cb8a`, ancestor of f6b7cc40). omega binds sha256 as abi=2.
- 7c: pins re-read (`om/units.sh:26-27`, lock 96292423). The ABI version refusal is at link time in v2. The old bridge PR #14 candidate was not re-checked: UNKNOWN.
- 8: still UNSUPPORTED (B-P1, B-P8). Capacities moved from 1024/512 to 8192 globals / 4096 functions (`gate12.sh:45-48`). L184 is now `dropped`.
- 12: split. The old omc.om line refs (5767, 7079) are replaced by `:13012`, `:14425`. irwasm VERSION refusal added. #621 v2 (old candidate 1683caaa) merged via `f5c9bd89`, so 12b is SUPPORTED with refusal 66.
- 14: "no profile id" becomes in-band OM-1/OM-2 profile selection (`60c80307` spec, OMEGESE 9.13). OM-3 is doc-only (`78fa7ec3`). #625 semantics is on main (`f5c9bd89`), still without a seeded omc profile. The old review receipt is UNKNOWN.

### Rows 9-11

- 9a: same status; cites moved (OMG 406-407 to 76-78/431-432); `seed/host/gate.sh` replaced by wired `seed/host/gate.om`; trap 6 now wired via gate5 (56dfcbd9b).
- 9b: unchanged; cite moved genkw.awk:16 to :18/:20; refusal now evidenced by C-P10 (error 4).
- 9c: still UNSUPPORTED; cite OMG:633-634 to 976-977; new unwired `seed/effects` manifest (f56a372ae #971); split into 9e/9f.
- 9e: new row: execpure 198 + close_range (1db941627 #970); gate669 not wired; close_range independent review (independent670).
- 9f: new row: execenv 233 (6efc45728 #1074) and prlimit 235 (1e3ecbba / a0d12c25), both wired at check.sh:130/133.
- 9d: same status; word cites moved to OMG:1027-1045; process words now gated by wired gate.om; gate669 still not wired.
- 10a: gate5 now wired by run.sh:176-179 (56dfcbd9b); gate-recursion.sh added and wired check.sh:26 (f5c9bd89a #972).
- 10b: same; resolve moved omc.om:5826-5827 to 10834-10838; IR error 3 now OMG:1226-1227; re-probed C-P1, C-P7.
- 10c: still UNSUPPORTED in compiler; program-level fuel now documented and wired (gate-recursion); candidate v2 still not on main (c434565c, e9081717 rc=1); old L736 independent-review path not re-verified: UNKNOWN; new verdict on e1f4c382 MERGE_AFTER_FIX.
- 11a: still UNSUPPORTED; `y = ldxr x` in value position is still error 3 (X-P1). In statement position `ldxr x` compiles as `<name> <value>` assignment with `=` left out (OMG:61; C-P3), so a statement-position absence probe proves nothing; `dmb`/ordering split to 11e.
- 11e: new row: cpufence/cpurelax (d94617177 #946), wired by cpufence.sh at check.sh:160.
- 11b: cites moved OMG:694-697 to 1044-1045/1134-1135; gate.sh to gate.om.
- 11c: same status; added OMG:1220; sm121/gate6.sh confirmed not wired.
- 11d: unchanged (UNKNOWN).

### Rows 13, 15-17

- 13a: span, category, finality and repairability now exist (faa30a8b, 1fe5976d, d94a503f); the registry and drift check have been added (91c83438); the old `omc.om:122-147` and `gate15.sh:29-47` refs are replaced; the check/next harness is not wired.
- 13b: still no debug info; the ELF ref moved from `omc.om:5767` to `:10731`; `om2 diag` trap-site line records are new (wired via contracts.cases).
- 15a: same status; refs moved; DDC650 gate added (a48b60410), not wired; L834 now records `run.sh seed` RC=0 on 1e3ecbba.
- 15b: same status; the `omc.om:3817,4152` refs are replaced by the target switch `:17238-17246` and the device words; gate6 is confirmed not wired.
- 15c: still not on main; the candidate shas now have no branch ref anywhere; the candidate QUALIFIED claim is downgraded to UNKNOWN (receipt not reread).
- 15d: UNSUPPORTED -> SUPPORTED (emulated) via bf54b19f (#923); not QUALIFIED (native NOT_RUN).
- 15f: new row; x86efi was added by 5ce9ecaa.
- 15e: unchanged; c02989f2 is still not an ancestor and has no branch ref.
- 16a: absent -> on main via f5c9bd89a (#972); wired into no gate; built by the pinned omc 734f0a39 and bridge 0fc7d866 (off bridge main); the current omc refuses them (T-P16-T-P20); L830 dropped.
- 16b: candidate -> on main (ancestors); #622 bounded review receipt is now in-tree; the #621 review is pending per its own README.
- 16c: candidate -> on main (ancestors); the G1 QUALIFIED comment and hosted run could not be re-verified -> UNKNOWN.
- 16d: candidate -> on main (ancestors); still self-test only.
- 17a: refs moved to `bdisp` (dc0d06e95, #948); `gate15` e24 accept and refuse are wired; the independent669 receipt is now in-tree, but it predates dc0d06e95; gate669 is still not wired.
- 17b: UNSUPPORTED/UNKNOWN -> partly SUPPORTED: execpure #670, packed-list ingress #671 (wired), devcall cap #672/#1042 (wired); the independent670/671 receipts are in-tree.
- 17c: UNKNOWN -> `dit`/`scrub` SUPPORTED (23678743); the general constant-time NO CLAIM is now explicit; the TLS timing screen is measured but not wired.

### Ledger, dependencies and drift

- **Abbreviations:** gate5 is now wired into OMEGA-SEED (`56dfcbd9b`, run.sh:176-179). `seed/host/gate.sh` was replaced by `gate.om`. check.sh now also runs the om2 gates (s5, hex, bnd, fnhost), security673, execenv, prlimit, cpufence, irq and tls (last changed `a0d12c250`). The probe compiler changed from `734f0a39` to sha256 `6d1b1cf5…`.
- **Ledger states:**
  - open to done: L408, L836, L837, L569, L729 (patch unmerged), L789, L832, L798.
  - open to dropped: L575, L830, L184.
  - Still open: L834, L835, L838, L608, L624, L801, L775.
  - L835 and L838 have stale "unmerged" text (merged via `60c803074` and `7505b3a3e`). L624's text is partly stale (`809197d92` is on rad).
- **C1:** still unowned for omc. Hive NG `seed/ng/IR.md` (PROPOSED) adds VEC, but no ledger id covers it.
- **C2:** the old cite moved from `omc.om:5767` to `:10731`. om2 `omc-site` trap mapping is new.
- **C3:** now partly owned. SPEC2 §8, leakscan and security758 are new; sec8 is NOT_RUN.
- **C4:** gate5 is resolved. gate6, gate669 and om2 s1..s4 are still unwired. L798 is done but unowned, and the `own` drift remains.
- **C5:** changed from spec-only to the NG IR PROPOSED draft. There is still no ledger id or gate.
- **D1:** FR-5 is fixed in OMC-DONE (`96ea448ad`). FR-7 was drift at 1e3ecbba (it contradicted `export fn` in omc); fixed in this change.
- **D2:** break, trap and free are confirmed by probe. `own` is a newly found mismatch (N5).
- **Old probes:**
  - `own_word` and `free_array` reconfirmed (L-P14, L-P8).
  - `hex_literal` reconfirmed for OM-1 (L-P2); under OM-2 it is now accepted (L-P1).
  - `vector_word`, `import_word`, `atomic_word` and both recursion probes were re-run by the other groups: A-P5/A-P6, B-P1, X-P1, C-P1 and C-P8/M-P11.
