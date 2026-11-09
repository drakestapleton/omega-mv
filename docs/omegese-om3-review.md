# OM-3 coordinator review: `spec/omegese-om3.md` section 0 and section 1 (#1008)

Reviewer: #599 language-evolution coordinator L835 (card t_d732a0bb, run 349, bay 13), 2026-11-09.
Base: omega-mv main `1e3ecbba7` (rad `z6do9WDBhuSnvopDkgFdFr1yWA62`). Compiler: seed-born `seed/out/omc`,
sha256 `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8` (equals `seed/out/omc.sha256`).
Built and run with the CPU pool lock `pool-10-11` (`flock`, `taskset -c 10,11`), no GPU, no GitHub.

## Verdict per claim of section 1

Labels: VERIFIED (checked against `seed/omc/omc.om` at the base and, where stated, run), CORRECTED (false at
the base, spec text changed in this patch), NOT_RUN (needs a runtime this repository does not have).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Words `fopen fclose fstat stat lstat getuid geteuid getgid getegid` are admitted in an OM-2 function unit | VERIFIED | `omc.om` hostval admission 7661-7672 (AArch64) and `xhost` 16324-16335 (x86linux): ids 100, 110, 117, 140, 145..149. Probe of all 92 words of `seed/ng/hostwords.tsv` in an `om2` function unit: exactly the admitted set leaves error 9. |
| 2 | Clocks `monons realns sleepns` admitted | VERIFIED | ids 109, 130, 120 in the same checks; probe: `monons`, `realns` compile (exit 0), `sleepns` gets past admission (exit 4 = my probe's missing arguments). |
| 3 | The 12 device words are admitted | VERIFIED | ids 166..177 in the same checks; probe: all 12 get past admission. `fnhost-dev`, `fnhost-hold`, `fnhost-bind` (+ x86) emit exact sha256. |
| 4 | "on AArch64" and "any host word for another target is error 9" | CORRECTED | `target x86linux` is admitted by the same sets (`xhost`, `fnhost-x86-*` cases, `MAPPING.md` lines 80-87). `target x86efi` refuses every function unit with error 25 at line 1 (`omc.om` 14822), not 9. Probe: 92 of 92 words, error 25. New gate case `fnhost-efi`. |
| 5 | "with their program-mode meaning and machine code" | CORRECTED | Meaning is shared. Machine code is not byte-identical: the program-mode `geteuid` carries `cmp sp,x28; b.lo` (stack floor) that function mode omits (probe: `fn main` 69 words, `om2` function 14 words; function-mode sequence `sub sp; str x30; movz x8,#175; svc; ldr x30; add sp`). Text now says so. |
| 6 | "Every other host word in function mode ... is error 9"; "any host word in an OM-1 function unit is error 9" | CORRECTED | `cpufence` and `cpurelax` (#939) are accepted in every function unit, OM-1 included (OMEGESE.md section 10, `fence-om1` probe exit 0); `read` and `write` are base words. Probe of all 92 words: OM-1 function unit, AArch64: 88 error 9, 2 base words and 2 barriers pass. Same on x86linux. OM-2 function unit: 64 error 9. |
| 7 | Entry 31 is a data pointer to a 32-byte header then 1..4098 32-byte slots | VERIFIED | `mcheck` 7139-7187 and `mnew` 7285-7302: loads `[x7,#248]`, then `[table+0]` capacity, traps 3 when capacity is 0 or above 4098 (`matconst 15 4098`), slot address `table + 32 + (slot-1)*32`. Header word 2 is the generation limit (1..2^50-1), read by `mnew`. |
| 8 | Handles have 13 low slot bits | VERIFIED | `mcheck` mask 8191 in function mode (255 in program mode); slot above capacity traps. 4098 does not exceed 2^13-1 = 8191. |
| 9 | Fixed bind replaces only the whole owned PROT_NONE reservation | VERIFIED | `mbind` 7377-7429: slot access must be 0 (trap 3 otherwise), maps at the slot's own address and whole length with `MAP_SHARED\|MAP_FIXED` (17), kernel address must equal the slot's. Gate `fnhost-bind` pins the emitted bytes; mutant `fn-own` is detected. |
| 10 | Failure unmaps and retires the token if cleanup succeeds; cleanup failure traps 3 and leaves a quarantined owner | VERIFIED (by reading code) | `mbind` 7411-7427: access set to 4, `munmap`; zero result clears address, length, access (generation kept: retired); nonzero traps 3 with access 4. Mutant `fn-quarantine` is detected. The runtime behaviour itself is NOT_RUN here (no function-mode execution in this repository). |
| 11 | In quarantine bind/read/write refuse; `mapaddr` and `mapdrop` remain available | VERIFIED (by reading code) | `mcopy` 7444-7450 and `mmapio` 7583-7589 trap 3 when access is 0 or above 3; `mapaddr` (7558-7566) and `mapdrop` (7995-8010) do no access check. `mapget` and `mapset` also refuse (the spec does not list them; not an error). |
| 12 | Destroy stays busy until drop succeeds; the bridge supplies disjoint generation ranges, serializes calls, rejects incompatible fingerprints, refuses a unit naming these words unless the caller opts in; "not status 34" | NOT_RUN | Bridge behaviour. No omega-bridge checkout was available; no word in `omc.om` returns or traps 34. Compiled code never tests the table pointer, so an absent pointer faults (loads at 7286-7287 and 7149-7150). |
| 13 | Program-mode raw 128 slots, eight slot bits unchanged | VERIFIED | `mcheck` and `mnew` program-mode branches: mask 255, slot at most 128, 4096-byte `maptab`. |
| 14 | A function unit is `om2`, first non-`note` line, no `fn main` | VERIFIED | probe `note-first`: notes before `om2` compile; OM-1 function unit with a host word is error 9 (`fnhost-om1`, `fnhost-x86-om1`). |
| 15 | Gate: `fnhost.cases` and `mutants.cases` through `seed/host/check.sh` | VERIFIED | See "Gate". |

## Section 0

C2 sentence: "the frozen C2 manifest compiles byte-identically" is false at `1e3ecbba` (5835 of 5876 rows,
L835 run 300, `~/handoffs/hive-breathe/L835-evidence/run300/c2/`; 29 rows covered by neither the frozen manifest
nor a declared delta, 6 declared deltas fail again). Rewritten: C2 for an OM-3 addition is checked against the
frozen manifest plus a complete declared-delta chain at the addition's base pin; an incomplete chain makes C2
NOT_RUN. Also removed the same claim from the context-ABI bullet ("frozen C2 manifest ... stay unchanged").
C3: `grep -c '^fn ' seed/omc/omc.om` = 510 of 512; the spec now states the limit. The chain is owned by L1041
(card t_2d8ccba8); this review does not close it.

## Gate

Run: the `fnhost` block of `seed/host/check.sh` (lines 113-126, verbatim, with the whole-script C oracles and
the seed rebuild not run), conductor `gate.om` built by the pinned omc. Logs, probes and the all-words tables:
`~/handoffs/hive-breathe/L835-evidence/run349/` (SHA256SUMS).

- `fnhost.cases`: `OM2GATE PASS cases=22 pass=22 fail=0 invalid=0 not_run=0` (21 before, plus `fnhost-efi`).
- `mutants.cases`: `OM2GATE FAIL cases=24 pass=12 fail=12 invalid=0 not_run=0`; the 12 `ctl-fn-*` controls PASS
  and the 12 `fn-*` mutants FAIL, each by a changed byte stream or a missing refusal: `fn-om1`, `fn-high`,
  `fn-low` (accepted what must be refused), `fn-narrow`, `fn-clock` (refused what must compile),
  `fn-tab`, `fn-cap`, `fn-own`, `fn-slot`, `fn-quarantine`, `fn-xsys`, `fn-xfence` (emitted sha256 differs).
- New negative control for `fnhost-efi`: the same case expecting error 9 makes the gate exit 1.

## Not decided here

The context ABI revision stays DRAFT. At the base the compiler already implements it (omega-mv commits
`b80044183`, `ce35b3518`, `e59a0060d` are ancestors of main) although the spec says it requires Drake's
approval before merge; the decision was put to Drake (`~/handoffs/hive/queen/QUESTIONS.md`, 2026-11-09).
