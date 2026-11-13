# Host-word effect and compatibility matrix (RCCA action R4, line container-execfds)

Status: DRAFT for `seed/host/EFFECT-MATRIX.md`. Originally inspected at `a58a31a29ed59122fc2b1d3b8462ce18fc98446a`; references refreshed for the parent-integrated
head `59eeee611acf990dbabba3e9198a4ab828551acb` (base: Radicle main `2ee0a70d1830581b706f288e722f3329d51f3583`).
The compiler bytes are unchanged by that restack; the gate-pools script anchor moved.
It is a reading of the source plus an index of the cases that exercise it. It runs nothing and is not an
acceptance verdict: a cited case says where a cell is exercised, not that the case passed at this head.
`seed/host/matrix-check.py` (a labelled TEST INSTRUMENT) checks that every reference below still resolves.

## How to read it

One `### ROW` per word, seven cells per row. A cell is one line: `- KEY: claim || EVIDENCE: evidence`.

| Key | Cell |
|---|---|
| T | targets: AArch64 Linux, x86linux and the EFI targets, with each refusal code |
| P | pool admission: what `hpoolok` answers and what a run-time pool operand gets |
| W | operands: read-only or writable, and what is written on success and on the error path |
| A | allocation and preflight that happen before the kernel call |
| S | snapshot and copy semantics between validation and use |
| D | descriptor transitions |
| L | protective limits retained |

Reference tokens (in backticks; `matrix-check.py` verifies each one):

- `src:PATH:LINE:TEXT` the line holds TEXT at the checked tree (a claim's source).
- `test:PATH:LINE:TEXT` the same check, used as evidence inside a gate script or fixture.
- `case:CASESFILE:NAME` a `run`, `emit` or `refuse` row of that name exists in the cases file.
- `check:FIXTURE#N` or `#A-B` numbered checks of a fixture (its exit status is the first failed check).
- `file:PATH` tracked; `mutant:PATH` both `PATH.from` and `PATH.to` tracked.
- `legacy:PATH` in the base tree, tracked, and the same blob as in the base (a protected fixture; a `.om` path
  is also in the corpus that `samebytes` compiles, which is every `*.om` of `git ls-tree -r` of the base).
- `samefn:PATH:NAME` function NAME of PATH is byte-identical to the base (trailing notes excluded).

Evidence is `NOT_COVERED: reason` where no case exercises the cell, and `N/A: reason` where the cell has nothing
to exercise. A shared refusal site exercised only with another word is cited for the word it was run with and
is NOT_COVERED for every other word. Root-mode checks of `container.om` (numbers below 60 and 70..89) run only in
steps 3 and 4 of `seed/host/container/check.sh` (`sudo -n`); without passwordless sudo they are NOT_RUN (exit 3).

@alias O seed/omc/omc.om
@alias CC seed/host/container/container.cases
@alias CR seed/host/container/refusals.cases
@alias CF seed/host/container/container.om
@alias OF seed/host/container/offsets.om
@alias CS seed/host/container/check.sh
@alias CM seed/host/container/mutants
@alias EC seed/host/execfds/execfds.cases
@alias EF seed/host/execfds/execfds.om
@alias ES seed/host/execfds/check.sh
@alias EM seed/host/execfds/mutants
@alias FC seed/host/fstatfs/fstatfs.cases
@alias FF seed/host/fstatfs/fstatfs.om
@alias FM seed/host/fstatfs/mutants
@alias HC seed/host/hostpool/hostpool.cases
@alias HF seed/host/hostpool/hostpool.om
@alias LF seed/host/hostpool/legacy.om
@alias HM seed/host/hostpool/mutants
@alias XC seed/host/execenv/execenv.cases
@alias PC seed/qualification/security673/packets.cases
@alias PM seed/qualification/security673/packets-mutant.cases
@alias S6 seed/qualification/security673

## Shared admission (every row refers to it)

- Dispatch: a host word reaches `src:O:11697:fn hostval`. Object mode is error 9 `src:O:11701:fail 9`.
  x86linux goes to `src:O:11714:xhost c dst`; any other non-AArch64 target (x86efi) is error 25
  `src:O:11720:fail 25`; a64efi is error 25 `src:O:11726:fail 25`. AArch64 function mode is error 9: OM-1
  `src:O:11742:fail 9`, OM-2 outside the file, identity, clock and device subset `src:O:11760:fail 9`.
- Pool flag: `src:O:11690:fn hpoolok` answers 0 for 166..177, 228..232 and 241..243
  `src:O:11691:and ge c 241 le c 243` `src:O:11692:ret 0`, else 1 `src:O:11694:ret 1`. hostval stores the answer
  in frame slot x+31 `src:O:11770:add x 31 hpoolok c` before any dispatch, the KFD dispatch included
  `src:O:11771:if and ge c 241 le c 243`. xhost stores 0 for every word `src:O:22043:add x 31 0`; the EFI words
  store 0 `src:O:23589:add x 31 0` `src:O:25028:add x 31 0`.
- Operand: every byte operand goes through `src:O:8463:fn harray`, which reads the flag
  `src:O:8464:arrname get a_ar add get a_rb 77 add x 31`. With flag 0 a pool is error 7
  `src:O:5673:if eq pk 0` `src:O:5676:fail 7`. A non-uchar array is error 7 `src:O:8468:fail 7`. A writable
  operand refuses a view or a text with error 20 `src:O:8471:vs_arr 53 e` `src:O:8143:fail 20`. The slice
  `[off, off+n)` is checked against the length (current length for a pool) `src:O:8481:vs_chk e ro rn`.
- A run-time pool cannot be declared on x86linux, x86efi or a64efi: error 25 `src:O:14032:fail 25`
  `src:O:14037:fail 25`. The flag values written by xhost and the EFI words are therefore never reached by a
  declared pool.
- At the base `harray` refused every pool (`mutant:HM/admit` restores that line), so pool admission is new at
  this head for every word that answers 1, the six legacy words included.

## Matrix

The checker generates row and NOT_COVERED counts; no duplicated hand-maintained totals.

### ROW execfds:201

- T: AArch64 Linux, program mode only: `src:O:12043:if eq c 201` `src:O:12044:hpackn c dst x`. Function mode 9 (shared sites). a64efi 25 and x86efi 25 (shared sites). x86linux 25 in every mode, tested before the x86 function-mode check `src:O:21999:if or eq c 201 eq c 215` `src:O:22002:fail 25`. Contract clause 30, raised in rdval (`src:O:12530:fail 30` or `src:O:12323:fail 30`; which one fires for a host word was not traced). || EVIDENCE: `case:EC:x86linux` `case:EC:x86efi` `case:EC:a64efi` `case:EC:fnmode` (an OM-2 function unit, site 11760) `case:EC:contract`. NOT_COVERED: no unit compiles execfds in an OM-1 function unit (site 11742) or in x86linux function mode.
- P: hpoolok 1. A, E and K each pass `harray x 0` `src:O:9358:e = harray x 0` `src:O:9368:e = harray x 0` `src:O:9372:e = harray x 0`; slot x+31 is reused for K's length only after the third read `src:O:9375:a_p 77 add x 31 a_g 77 add x 22`. || EVIDENCE: `case:HC:fixture` `check:HF#5-6` (A and E built in pools, `test:HF:199:r = execfds A 0 get an 0 E 0 get en 0 keep 0 0`) `case:HC:oracle` `case:HC:mut-admit`. NOT_COVERED: K is never a pool (`test:HF:29:global keep uchar 1`); no case passes a pool as the keep list or a slice one byte past a pool's length to execfds.
- W: all three operands are read-only (views and texts admitted). The kernel never receives a pointer into A, E or K: strings, pointer lists and the keep copy live in the frame, the static region or a private mapping. Nothing is written to caller memory on success or on any error path. `src:O:9358:e = harray x 0` || EVIDENCE: `case:EC:fixture` `check:EF#6-8` (returned errors -2 and -9). NOT_COVERED: no case asserts that A, E and K are unchanged after a failed launch, and none passes them through a view or text parameter.
- A: order: slice checks, then length at least 2 `src:O:9387:trapc 3 3` and below 2^60 `src:O:9391:trapc 1 3`, then the keep list checked in caller memory `src:O:9416:hkeepchk`, then the non-copying prepass over each packet `src:O:9423:hpackv c pv`, and only then the frame `src:O:9430:spsub fs` `src:O:9431:stkchk` and decode memory `src:O:9461:hdecpre`: the unit's 65536-byte static region when the total fits `src:O:9293:put poolb 0 add p 65536`, else mmap `src:O:9467:hsys 222`, whose failure returns minus errno `src:O:9469:mmfail = get oc 0`. || EVIDENCE: `check:EF#17-21` `check:EF#25` (ENOMEM control) `check:EF#26-29` `case:EC:mut-no-prepass` `case:EC:mut-prepass-trailing` `case:EC:mut-prepass-nul` `case:EC:mut-prepass-argv0` `case:EC:mut-prepass-env-nonempty` `mutant:EM/no-prepass` `test:ES:90:memtrace $k` (malbig and lying: trap 3 with no mapping) `test:ES:104:PASS mutant no-prepass killed by the memory check` `test:ES:109:memtrace bigok`. NOT_COVERED: the compile-time capacity refusal of the static region (error 23, `src:O:9290:fail 23`) and the boundary between the static region and mmap (total 65536 against 65537) have no case.
- S: K is validated in caller memory, copied behind the pointer lists, and validated again on the copy `src:O:9508:hkeepchk`; the launch `src:O:9598:hexecfds` reads only that copy. The copying pass repeats every framing check on the bytes it copies (`src:O:9523:trapc 0 3` and following). || EVIDENCE: `test:ES:115:PASS ptrace snapshot: caller [7]->[9] at unshare return, kept 7, closed 9` `test:ES:125:PASS mutant caller-reread killed by ptrace` `mutant:EM/caller-reread` `test:ES:129:PASS snapshot launch-failure control` `test:ES:133:PASS snapshot ptrace-denied control` `test:ES:101:no-prepass malbig exi` (the copying pass still traps without the prepass). NOT_COVERED: no case changes A or E between the prepass and the copying pass; the ptrace mutation covers K only.
- D: `src:O:9741:fn hexecfds`: unshare(CLONE_FILES) `src:O:9745:hsys 97` (failure returns, nothing changed `src:O:9747:put errs 0 mbranch 11`); F_GETFD on every kept descriptor before any change `src:O:9758:hsys 25` (one not open returns -9, nothing closed); F_GETFD then F_SETFD clearing FD_CLOEXEC `src:O:9771:hsys 25` `src:O:9777:hsys 25`; close_range over every gap `src:O:9795:hsys 436` and the tail `src:O:9807:hsys 436`; execve `src:O:9814:hsys 221`. Descriptors 0..2 are never closed. There is no rollback after the private table exists. || EVIDENCE: `check:EF#1-8` `check:EF#24` `case:EC:fault-control` `case:EC:fault-unshare` `case:EC:fault-getfd` `case:EC:fault-setfd` `case:EC:fault-closegap` `case:EC:fault-closetail` `case:EC:mut-keep-cloexec` `test:ES:73:order run exit` `test:ES:86:PASS mutant no-unshare killed by the strace order check` `mutant:EM/no-unshare`.
- L: no cap of its own on argv, environment or keep list (input-sized; only the u16 wire fields bound a record and a count). Retained: keep length a multiple of 4 `src:O:9707:trapc 1 3`, strictly increasing from 3 `src:O:9716:trapc 9 3`, at most INT_MAX `src:O:9720:trapc 1 3`; packet framing in the prepass: count at least 1 `src:O:9646:trapc 0 3`, record inside the packet `src:O:9668:trapc 8 3`, nonempty where required `src:O:9674:trapc 0 3` `src:O:9678:trapc 0 3`, no zero byte `src:O:9686:trapc 0 3`, no trailing byte `src:O:9697:trapc 1 3`. Kernel limits (E2BIG, RLIMIT_AS, RLIMIT_NOFILE) pass through as errno. || EVIDENCE: `check:EF#9-16` `case:EC:mut-keep-len4` `case:EC:mut-keep-increasing` `case:EC:mut-keep-low3` `case:EC:mut-keep-intmax` `check:EF#22-24` `check:HF#6`. NOT_COVERED: the 2^60 sizing refusals (9391 and its two siblings) have no case, and the count-0 check has no mutant (stated in `test:EC:17:Not mutated: the count-0 check`).

### ROW capget:202

- T: AArch64 Linux, program mode: `src:O:12067:if and ge c 202 le c 214` `src:O:12068:hcont c dst x` `src:O:10189:hcaps c dst x`. Function mode 9, a64efi 25, x86efi 25 (shared sites). x86linux 25 `src:O:22036:if and ge c 202 le c 214` `src:O:22039:fail 25`, after the x86 function-mode test `src:O:22008:fail 9`. Contract clause 30 (rdval, not traced per word). || EVIDENCE: `case:CR:x86-capget` `case:CR:a64efi-capget` `case:CR:fnmode-capget` (OM-1 unit). NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for capget; those shared sites run with unshare only.
- P: hpoolok 1; the operand passes `src:O:10129:e = harray x 1`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to capget.
- W: A must be writable (a view or a text is error 20). On success the kernel writes the header and the 24 data bytes of `A[off, off+32)`. On an unknown version the kernel stores its preferred version into the header before returning -22. `n` other than 32 returns -22 with no kernel call `src:O:10135:mimmed 4043309056 31 5 32` `src:O:10137:matconst 0 sub ulong 0 22`. || EVIDENCE: `case:CR:view-capget` `case:CR:text-capget` `case:CR:ulong-capget` `case:CC:offsets` `check:OF#1` (writes exactly A[8..40) through an edit parameter) `case:CC:user` `test:CF:522:ck add base 1` `test:CF:529:ck add base 2` (n 31 gives -22) `case:CC:capw`.
- A: no allocation. The slice check and the length test precede the call `src:O:10143:hsys add 90 sub c 202`. || EVIDENCE: `test:CF:529:ck add base 2` `test:CS:146:caps-n:81` `mutant:CM/caps-n` (root mode).
- S: no copy: the kernel reads and writes the caller's slice in place `src:O:10143:hsys add 90 sub c 202`. || EVIDENCE: N/A: nothing is validated and then reread; the only precondition is the length.
- D: none `src:O:10128:fn hcaps`. || EVIDENCE: N/A: capget opens and closes nothing.
- L: exact length 32 and a writable operand, both stated in W. Syscall number `src:O:10143:hsys add 90 sub c 202`. || EVIDENCE: `test:CS:146:caps-sysno:81` `mutant:CM/caps-sysno` (root mode) `case:CC:user`.

### ROW capset:203

- T: as capget: `src:O:10189:hcaps c dst x`; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-capset` `case:CR:a64efi-capset` `case:CR:fnmode-capset`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for capset.
- P: hpoolok 1; `src:O:10129:e = harray x 1`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to capset.
- W: A must be writable although capset is an input call on success: on an unknown version the kernel writes its preferred version into the header before -22 (review omega-mv-9e064822 finding 8). `n` other than 32 returns -22 with no kernel call `src:O:10135:mimmed 4043309056 31 5 32`. || EVIDENCE: `case:CC:capview` (view parameter: error 20) `case:CC:capw` (zero version: -22 and the header becomes 0x20080522) `case:CC:mut-capset-view` `mutant:CM/capset-view` `case:CR:view-capset` `case:CR:text-capset` `case:CR:ulong-capset`.
- A: no allocation; checks precede `src:O:10143:hsys add 90 sub c 202`. || EVIDENCE: `case:CC:capw` `case:CC:user` (`test:CF:545:r = capset cg 0 32`).
- S: no copy; the kernel reads the caller's slice in place `src:O:10143:hsys add 90 sub c 202`. || EVIDENCE: N/A: nothing is validated and then reread.
- D: none `src:O:10128:fn hcaps`. || EVIDENCE: N/A: capset opens and closes nothing.
- L: exact length 32 and a writable operand. `src:O:10135:mimmed 4043309056 31 5 32` || EVIDENCE: `case:CC:capview` `case:CC:mut-capset-view` `test:CS:146:caps-n:81` (root mode; the mutated length test is shared with capget).

### ROW opentree:204

- T: `src:O:10193:hpath c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-opentree` `case:CR:a64efi-opentree` `case:CR:fnmode-opentree`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for opentree.
- P: hpoolok 1; `src:O:8519:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to opentree.
- W: A read-only; flags int `src:O:8531:harg x 2 8`. The kernel sees only a private zero-terminated copy `src:O:8533:hpathcp x` `src:O:8560:hcopy`, so no kernel write can reach A. || EVIDENCE: `case:CC:offsets` `check:OF#2` (view parameter, offset 2, run-time length: the kernel saw exactly the slice) `case:CR:ulong-opentree`.
- A: length above 4095 traps 3 before the copy `src:O:8493:matconst 6 4095` `src:O:8495:trapc 8 3`; then 4096 bytes of stack `src:O:8498:spsub 4096`; then `src:O:8588:nr = ulong 428` `src:O:8614:hsys nr`. || EVIDENCE: `check:OF#2` `check:CF#70-71` (root mode) `test:CS:147:opentree-sysno:71` `mutant:CM/opentree-sysno`.
- S: one private copy made after the slice check; the kernel reads the copy `src:O:8560:hcopy`. || EVIDENCE: `check:OF#2`.
- D: returns a new descriptor on success; the compiler keeps no table entry for it and adds no flag (close-on-exec is the caller's flag bit) `src:O:8588:nr = ulong 428`. || EVIDENCE: `check:OF#2` `check:CF#70` (root mode).
- L: path at most 4095 bytes with no zero byte (hpathcp) `src:O:8493:matconst 6 4095` || EVIDENCE: NOT_COVERED: no case gives opentree a path of 4096 bytes or one holding a zero byte; `longpaths` in container.om uses mount and pivroot only.

### ROW mntattr:205

- T: `src:O:10197:hmntattr dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-mntattr` `case:CR:a64efi-mntattr` `case:CR:fnmode-mntattr`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for mntattr.
- P: hpoolok 1; `src:O:10152:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to mntattr.
- W: fd int `src:O:10151:harg x 2 8`; A read-only, and the kernel reads `struct mount_attr` straight from the caller's slice `src:O:10164:hsys 442`. That the kernel only reads it (copy_struct_from_user) is an ABI reading, not a tested fact. || EVIDENCE: `case:CR:ulong-mntattr` `check:CF#72-73` (root mode). NOT_COVERED: no unprivileged case calls mntattr, and none asserts A unchanged after the call or passes it through a view.
- A: a private 16-byte stack slot holds the empty path `src:O:10159:spsub 16`; no other allocation; `src:O:10164:hsys 442`. || EVIDENCE: `check:CF#72` (root mode) `test:CS:147:mntattr-sysno:72` `mutant:CM/mntattr-sysno`.
- S: no copy of A; the kernel reads the caller's slice in place `src:O:10164:hsys 442`. || EVIDENCE: N/A: nothing is validated by the compiler beyond the slice bounds.
- D: acts on the tree named by fd; opens and closes nothing `src:O:10150:fn hmntattr`. || EVIDENCE: `check:CF#72` `check:CF#77` (root mode: the attached clone is read-only).
- L: none of its own beyond the slice check; the kernel judges the size (8 gives -22) `src:O:10164:hsys 442`. || EVIDENCE: `check:CF#73` (root mode).

### ROW mntmove:206

- T: `src:O:10201:hmntmove dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-mntmove` `case:CR:a64efi-mntmove` `case:CR:fnmode-mntmove`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for mntmove.
- P: hpoolok 1, without effect: the word has no array operand `src:O:10172:harg x 0 8` `src:O:10173:harg x 1 8`. || EVIDENCE: N/A: two int operands, no slice.
- W: two int descriptors; nothing in caller memory is read or written `src:O:10183:hsys 429`. || EVIDENCE: `check:CF#75-76` (root mode).
- A: a private 16-byte stack slot for the two empty paths; fixed flags 68 `src:O:10182:matconst 4 68`. || EVIDENCE: `test:CS:147:mntmove-flags:75` `mutant:CM/mntmove-flags` `mutant:CM/mntmove-sysno` (root mode).
- S: none `src:O:10171:fn hmntmove`. || EVIDENCE: N/A: no memory operand.
- D: attaches the tree of `from` at `to`; neither descriptor is closed `src:O:10183:hsys 429`. || EVIDENCE: `check:CF#75-78` (root mode).
- L: the flags are fixed to the two EMPTY_PATH bits, so no path is ever resolved `src:O:10182:matconst 4 68`. || EVIDENCE: `test:CS:147:mntmove-flags:75` (root mode).

### ROW unshare:207

- T: `src:O:10205:hscalar c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CC:ctl-simple` `case:CC:x86` `case:CC:efi` (x86efi) `case:CC:fnmode` (OM-2 unit) `case:CC:contract` `case:CR:x86-unshare` `case:CR:a64efi-unshare` `case:CR:fnmode-unshare` (OM-1 unit) `case:CC:x86-fnmode` `case:CC:x86-fnmode-om2` (x86linux function units: 9 at 22008 before 25 at 22039).
- P: hpoolok 1, without effect: one scalar operand `src:O:8258:if eq c 207` `src:O:8259:ret 1`. || EVIDENCE: N/A: no slice operand.
- W: one int operand (a long is error 7); no memory operand `src:O:8385:fn hscalar`. || EVIDENCE: `case:CC:longflags`.
- A: none; syscall 97 `src:O:8354:if eq c 207` `src:O:8355:ret 97`. || EVIDENCE: `case:CC:user` `check:CF#60` `check:CF#1-2` (root mode) `test:CS:145:unshare-sysno:1` `mutant:CM/unshare-sysno`.
- S: none `src:O:8385:fn hscalar`. || EVIDENCE: N/A: no memory operand.
- D: the flags are the caller's; CLONE_FILES would give a private descriptor table, as any namespace flag changes the process `src:O:8355:ret 97`. || EVIDENCE: `check:CF#1-2` (root mode).
- L: none of its own; the kernel judges the flags `src:O:8355:ret 97`. || EVIDENCE: `check:CF#1` (root mode: a bad flag gives -22) `check:CF#60`.

### ROW mount:208

- T: `src:O:10209:hpackn c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-mount` `case:CR:a64efi-mount` `case:CR:fnmode-mount`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for mount.
- P: hpoolok 1; `src:O:9358:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to mount.
- W: A read-only; flags int `src:O:9360:harg x 2 8`. The kernel receives only pointers into the private decode copy `src:O:9609:hsys 40`; nothing is written to A. || EVIDENCE: `case:CC:offsets` `check:OF#4` (view parameter at offset 5 reaches the kernel; offset 6 traps 3) `case:CC:wordarr` `case:CR:ulong-mount`.
- A: as execfds without the keep list: length checks `src:O:9387:trapc 3 3` `src:O:9391:trapc 1 3`, prepass `src:O:9423:hpackv c pv` with the record count `src:O:9653:trapc 3 3` `src:O:9655:trapc 8 3`, then the frame and decode memory (static region or mmap `src:O:9467:hsys 222`). || EVIDENCE: `case:CC:preflight-mount` `case:CC:preflight-mount-count` `case:CC:preflight-mount-lying` `case:CC:bigpacket` `file:seed/host/container/preflight.om` `test:CS:56:PASS observer control` `test:CS:64:mutarm preflight-mut` `test:CS:65:mutarm preflight-mcount` `test:CS:67:for mode in m p c q l r` `mutant:CM/mount-count-prepass`. NOT_COVERED: a refused decode mapping (the minus-errno return at 9469) has no mount case; the ENOMEM control uses execfds.
- S: the copying pass repeats the count and framing checks on the bytes it copies `src:O:9532:trapc 3 3` `src:O:9534:trapc 8 3`; the kernel call uses only the copy. || EVIDENCE: `case:CC:badmount` `case:CC:mut-mount-count` `mutant:CM/mount-count` (removes BOTH prepass and copying count checks). NOT_COVERED: no mutation between passes separately exercises the copying count check.
- D: none; the decode mapping, when one was made, is unmapped after the call `src:O:9620:hdecfree` `src:O:9315:hsys 215`. || EVIDENCE: `check:CF#10-14` (root mode) `check:CF#62`.
- L: 3 or 4 records, each nonempty, no zero byte, no trailing byte; no byte cap of its own (the kernel refuses a 4096-byte path). `src:O:9357:fn hpackn` || EVIDENCE: `case:CC:badmount` `case:CC:bigpacket` `file:seed/host/container/bigpacket.want` `case:CC:user` (`test:CF:202:fn longpaths`) `test:CS:145:mount-flags:10` `mutant:CM/mount-flags` `mutant:CM/mount-sysno` (root mode).

### ROW umount:209

- T: `src:O:10213:hpath c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-umount` `case:CR:a64efi-umount` `case:CR:fnmode-umount`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for umount.
- P: hpoolok 1; `src:O:8519:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to umount.
- W: A read-only (a text in the fixture); flags int `src:O:8531:harg x 2 8`; the kernel sees only the private copy `src:O:8533:hpathcp x`. || EVIDENCE: `case:CC:user` `check:CF#63` `case:CR:ulong-umount`. NOT_COVERED: no case passes umount a view parameter or a nonzero offset (offsets.om covers capget, opentree, sigmask, sigwait and mount).
- A: length above 4095 traps 3 `src:O:8495:trapc 8 3`; 4096 bytes of stack `src:O:8498:spsub 4096`; `src:O:8584:nr = ulong 39`. || EVIDENCE: `check:CF#63` `check:CF#35` (root mode) `test:CS:145:umount-sysno:35` `mutant:CM/umount-sysno`.
- S: one private copy after the slice check `src:O:8560:hcopy`. || EVIDENCE: `check:CF#63`.
- D: none `src:O:8584:nr = ulong 39`. || EVIDENCE: N/A: umount2 takes a path and returns a status.
- L: path at most 4095 bytes with no zero byte `src:O:8493:matconst 6 4095`. || EVIDENCE: NOT_COVERED: no case gives umount a 4096-byte path or a path holding a zero byte.

### ROW pivroot:210

- T: `src:O:10209:hpackn c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-pivroot` `case:CR:a64efi-pivroot` `case:CR:fnmode-pivroot`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for pivroot.
- P: hpoolok 1; `src:O:9358:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to pivroot.
- W: A read-only; the kernel receives only pointers into the private decode copy `src:O:9615:hsys 41`. || EVIDENCE: `case:CC:user` `check:CF#64` `case:CR:ulong-pivroot`.
- A: as mount; the prepass count is exactly 2 `src:O:9649:trapc 1 3`. || EVIDENCE: `case:CC:preflight-pivroot` `case:CC:preflight-pivroot-count` `case:CC:preflight-pivroot-lying` `test:CS:66:mutarm preflight-pcount` `mutant:CM/pivroot-count-prepass`. NOT_COVERED: a refused decode mapping has no pivroot case, and no valid pivroot packet larger than the 65536-byte static region is run (bigpacket is a mount packet).
- S: the copying pass repeats the count check `src:O:9527:trapc 1 3`. || EVIDENCE: `case:CC:badpiv` `case:CC:mut-pivroot-count` `mutant:CM/pivroot-count` (removes BOTH prepass and copying count checks). NOT_COVERED: no mutation between passes separately exercises the copying count check.
- D: none; decode memory unmapped after the call `src:O:9620:hdecfree`. || EVIDENCE: `check:CF#30-37` (root mode) `test:CS:145:pivroot-sysno:32` `mutant:CM/pivroot-sysno`.
- L: exactly 2 nonempty records, no zero byte, no trailing byte; no byte cap of its own. `src:O:9357:fn hpackn` || EVIDENCE: `case:CC:badpiv` `case:CC:user` (`test:CF:202:fn longpaths`).

### ROW sethost:211

- T: `src:O:10217:hsethost dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-sethost` `case:CR:a64efi-sethost` `case:CR:fnmode-sethost`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for sethost.
- P: hpoolok 1; `src:O:10114:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to sethost.
- W: A read-only (a text is allowed); the kernel copies the name from the caller's slice `src:O:10120:hsys 161`. That sethostname only reads it is an ABI reading. || EVIDENCE: `case:CC:user` `check:CF#61` (a text operand; -1 without privilege) `case:CR:ulong-sethost`. NOT_COVERED: no case asserts the operand unchanged, and success runs only in root mode.
- A: none; `src:O:10120:hsys 161`. || EVIDENCE: `check:CF#20-22` (root mode) `test:CS:145:sethost-sysno:20` `mutant:CM/sethost-sysno`.
- S: no copy; the kernel reads the caller's slice in place `src:O:10120:hsys 161`. || EVIDENCE: N/A: nothing is validated beyond the slice bounds.
- D: none `src:O:10113:fn hsethost`. || EVIDENCE: N/A: no descriptor is involved.
- L: none of its own; the kernel refuses more than 64 bytes with -22 `src:O:10120:hsys 161`. || EVIDENCE: `check:CF#22` (root mode).

### ROW prctl:212

- T: `src:O:10221:hprctl dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-prctl` `case:CR:a64efi-prctl` `case:CR:fnmode-prctl`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for prctl.
- P: hpoolok 1, without effect: two int operands `src:O:10055:harg x 0 8` `src:O:10056:harg x 1 8`. || EVIDENCE: N/A: no slice operand.
- W: no memory operand; arguments 3 to 5 are zero `src:O:10084:hsys 167`. || EVIDENCE: `case:CC:user` `check:CF#65`.
- A: the op is tested against the allowlist 1, 23, 24, 36, 38, 39 at run time; any other op returns -22 with no kernel call `src:O:10075:matconst 0 sub ulong 0 22`. || EVIDENCE: `check:CF#40` (root mode: op 2 gives -22) `test:CS:146:prctl-allow:40` `mutant:CM/prctl-allow` `mutant:CM/prctl-23` `mutant:CM/prctl-39` `mutant:CM/prctl-sysno` (root mode).
- S: none `src:O:10054:fn hprctl`. || EVIDENCE: N/A: no memory operand.
- D: none `src:O:10084:hsys 167`. || EVIDENCE: N/A: none of the six ops touches a descriptor.
- L: the allowlist is the limit: no pointer-taking prctl op is reachable `src:O:10075:matconst 0 sub ulong 0 22`. || EVIDENCE: `check:CF#65` `check:CF#97` `test:CF:532:ck add base 3` `test:CF:535:ck add base 4` (unprivileged, through `case:CC:user`) `check:CF#40-45` (root mode).

### ROW sigmask:213

- T: `src:O:10224:hsigs c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-sigmask` `case:CR:a64efi-sigmask` `case:CR:fnmode-sigmask`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for sigmask.
- P: hpoolok 1; `src:O:10092:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to sigmask.
- W: `how` int `src:O:10090:harg x 2 8`; A read-only. The kernel reads the new set from the caller's slice; the old set pointer is NULL `src:O:10099:matconst 2 0`, so nothing is written back `src:O:10101:hsys 135`. || EVIDENCE: `case:CC:offsets` `check:OF#3` (view parameter at offset 8) `case:CC:user` `check:CF#66` `case:CR:ulong-sigmask`. NOT_COVERED: no case asserts the operand unchanged after the call.
- A: none; the set size is the caller's n (the kernel accepts only 8) `src:O:10100:loadarg 3 1`. || EVIDENCE: `check:CF#50-52` (root mode: size 4 gives -22) `test:CS:146:sigmask-sysno:50` `mutant:CM/sigmask-sysno`.
- S: no copy; the kernel reads the caller's slice in place `src:O:10101:hsys 135`. || EVIDENCE: N/A: nothing is validated beyond the slice bounds.
- D: none `src:O:10088:fn hsigs`. || EVIDENCE: N/A: no descriptor is involved.
- L: none of its own `src:O:10101:hsys 135`. || EVIDENCE: `check:CF#52` (root mode).

### ROW sigwait:214

- T: `src:O:10224:hsigs c dst x` from hcont; x86linux 25 `src:O:22039:fail 25`; other refusals at the shared sites. || EVIDENCE: `case:CR:x86-sigwait` `case:CR:a64efi-sigwait` `case:CR:fnmode-sigwait`. NOT_COVERED: x86efi, an OM-2 function unit, a contract clause and x86linux function mode have no unit for sigwait.
- P: hpoolok 1; `src:O:10092:e = harray x 0`. || EVIDENCE: NOT_COVERED: no case passes a run-time pool to sigwait.
- W: A read-only; siginfo and timeout pointers are NULL `src:O:10106:matconst 1 0` `src:O:10107:matconst 2 0`, so the kernel writes nothing `src:O:10109:hsys 137`. || EVIDENCE: `case:CC:offsets` `check:OF#3` `case:CC:user` `check:CF#67` `case:CR:ulong-sigwait`. NOT_COVERED: no case asserts the operand unchanged after the call.
- A: none `src:O:10109:hsys 137`. || EVIDENCE: `check:CF#53-55` (root mode) `test:CS:146:sigwait-sysno:54` `mutant:CM/sigwait-sysno`.
- S: no copy `src:O:10109:hsys 137`. || EVIDENCE: N/A: nothing is validated beyond the slice bounds.
- D: none `src:O:10088:fn hsigs`. || EVIDENCE: N/A: no descriptor is involved.
- L: none of its own; it blocks without a timeout by design `src:O:10107:matconst 2 0`. || EVIDENCE: `check:CF#67` `check:CF#55` (root mode: size 4 gives -22).

### ROW fstatfs:215

- T: AArch64 Linux, program mode only: `src:O:12047:if eq c 215` `src:O:12048:hbuffer c dst x`. x86linux 25 in every mode `src:O:21999:if or eq c 201 eq c 215` `src:O:22002:fail 25`. Function mode 9, a64efi 25, x86efi 25 at the shared sites; contract clause 30. || EVIDENCE: `case:FC:x86linux` `case:FC:x86efi` `case:FC:a64efi` `case:FC:om1-function` `case:FC:om2-function` `case:FC:contract`.
- P: hpoolok 1; `src:O:8627:e = harray x wr`. || EVIDENCE: `case:FC:fixture` `check:FF#5` (a 120-byte pool receives the same bytes).
- W: fd int; A must be writable `src:O:8624:if eq c 215` `src:O:8625:wr = ulong 1`. On success the kernel writes exactly 120 bytes; on an error it writes nothing. || EVIDENCE: `case:FC:text` `case:FC:view` `case:FC:ulong-array` `case:FC:ulong-fd` `check:FF#1-4` `check:FF#10-11` (closed descriptor: -9 and the poison stays).
- A: a slice shorter than 120 bytes traps 3 before the call `src:O:8645:matconst tmp 120` `src:O:8647:trapc 3 3`; no allocation; `src:O:8671:nr = ulong 44`. || EVIDENCE: `check:FF#6-9` `case:FC:mut-min119` `mutant:FM/min119` `case:FC:mut-sysno` `mutant:FM/sysno`.
- S: no copy; the kernel writes the caller's slice in place `src:O:8671:nr = ulong 44`. || EVIDENCE: N/A: nothing is validated and then reread.
- D: the descriptor is neither consumed nor changed `src:O:8618:fn hbuffer`. || EVIDENCE: `check:FF#1` `check:FF#12`.
- L: a minimum of 120 bytes, not a maximum; the whole supplied slice is bounds-checked `src:O:8647:trapc 3 3`. || EVIDENCE: `check:FF#6-9` `file:seed/host/fstatfs/oracle.py` (measured layout, run by `test:seed/host/fstatfs/check.sh:40:oracle.py" layout`).

### ROW execprog:124

- T: AArch64 Linux program mode `src:O:12234:eq c 124 eq c 125 eq c 141 eq c 142` `src:O:12235:hpack c dst x`; x86linux lowered by `src:O:22140:xhpack c dst x`; function mode 9 and the EFI targets 25 at the shared sites. Lowering unchanged from the base: `samefn:O:hpack` `samefn:O:xhpack` `samefn:O:hexw` `samefn:O:hnpass` `samefn:O:hplim`. || EVIDENCE: `case:PC:p00-valid-one` `case:PC:p12-echo-argv` `case:XC:oracle-execprog` `legacy:S6/pkt-consumer.om` `legacy:S6/exec-parent.om` `legacy:S6/exec-child.om`. NOT_COVERED: within the cases files read for this matrix (container, execfds, fstatfs, hostpool, execenv, security673 packets) no row compiles execprog for x86linux, an EFI target, function mode or a contract clause.
- P: hpoolok 1 (new at this head; the base refused every pool); `src:O:8901:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#2` `check:LF#8-9` `check:LF#12` (a header byte one past the pool's length traps 3) `case:HC:mut-legacy-admit` `file:seed/host/hostpool/legacy.want`.
- W: A read-only. Strings and argv pointers are decoded into the private stack frame; the kernel never receives a pointer into A, and nothing is written to A. `src:O:8901:e = harray x 0` || EVIDENCE: `check:LF#2` `case:PC:p12-echo-argv`. NOT_COVERED: no case asserts A unchanged after a failed exec.
- A: no heap and no mapping. The byte limit is tested before the frame exists `src:O:8924:matconst 16 65536` `src:O:8929:trapc 8 3` `src:O:8931:trapc 3 3`; then a fixed 81920-byte frame `src:O:8939:stack = ulong 81920` `src:O:8954:spsub stack` `src:O:8955:stkchk`; the record count is tested in the decode loop `src:O:8968:matconst 16 hplim c pass` `src:O:8970:trapc 8 3`. Every framing check precedes the first syscall. || EVIDENCE: `case:PC:p01-count-zero` `case:PC:p03-record-truncated` `case:PC:p07-record-overdeclared` `case:PC:p10-size-65537` `case:PC:trunc00` `check:LF#9`.
- S: one decode-and-copy pass from caller memory into the frame; the kernel uses only the frame `src:O:9244:hsys 221`. No second read of A. || EVIDENCE: `case:PC:p12-echo-argv` `legacy:S6/packets/p12.bin` `legacy:S6/packets/p12.out`.
- D: close_range(3, ~0, CLOSE_RANGE_UNSHARE) before execve `src:O:9050:hsys 436`; its failure returns without executing. Descriptors 0..2 are inherited. || EVIDENCE: `legacy:S6/exec-parent.om` `legacy:S6/exec-child.om` `check:LF#2`.
- L: packet 2..65536 bytes `src:O:8924:matconst 16 65536`; 1..1024 records `src:O:8882:ret 1024`; first record nonempty; no zero byte; no trailing byte. || EVIDENCE: `case:PC:p08-valid-1024` `case:PC:p09-count-1025-records` `case:PC:p10-size-65537` `case:PC:p11-size-65536` `case:PC:p04-trailing-byte` `case:PC:p05-first-empty` `case:PC:p06-embedded-zero` `case:PM:mutant-size` `case:PM:mutant-count` `case:PM:mutant-exact` `legacy:S6/packets.cases` `legacy:S6/packets-mutant.cases` `legacy:S6/packets/mut-size-from.txt` `legacy:S6/packets/mut-size-to.txt` `legacy:S6/packets/mut-count-from.txt` `legacy:S6/packets/mut-count-to.txt` `legacy:S6/packets/mut-exact-from.txt` `legacy:S6/packets/mut-exact-to.txt` `legacy:S6/packet-corpus.om` `check:LF#8-9` `case:HC:mut-execsize` `mutant:HM/execsize`.

### ROW execpure:198

- T: AArch64 Linux program mode `src:O:12039:if or eq c 198 eq c 233` `src:O:12040:hpack c dst x`; x86linux 25 (no strict-profile lowering) `src:O:22030:if eq c 198` `src:O:22033:fail 25`; function mode 9 and the EFI targets 25 at the shared sites. Lowering unchanged from the base: `samefn:O:hpack`. || EVIDENCE: `case:HC:legacy` `check:LF#3` `legacy:S6/pure-launch.om`. NOT_COVERED: no cases row at the head compiles an execpure unit for x86linux (the 25 at 22033), an EFI target, function mode or a contract clause.
- P: hpoolok 1 (new at this head); `src:O:8901:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#3` `check:LF#13` `case:HC:mut-legacy-admit`.
- W: A read-only; decoded into the private frame; the profile tables are compiler data. `src:O:8901:e = harray x 0` || EVIDENCE: `check:LF#3`. NOT_COVERED: no case asserts A unchanged after a failed launch.
- A: as execprog (81920-byte frame), plus 640 bytes of stack for the profile `src:O:9062:spsub 640`. No heap, no mapping. || EVIDENCE: `check:LF#3` `check:LF#13`.
- S: one decode-and-copy pass; the executable is pinned as descriptor 3 before the profile is applied `src:O:9071:hsys 56`, and execveat runs that descriptor `src:O:9223:hsys 281`. || EVIDENCE: `legacy:S6/pure-launch.om` `legacy:S6/pure-child.om` `legacy:S6/pure-raw.om`.
- D: close_range as execprog `src:O:9050:hsys 436`; then, for 198 only `src:O:9055:if eq c 198`: open the executable `src:O:9071:hsys 56`, Landlock ruleset `src:O:9083:hsys 444` `src:O:9098:hsys 445` `src:O:9115:hsys 446`, no-new-privs `src:O:9108:hsys 167`, close the ruleset descriptor `src:O:9121:hsys 57`, seven rlimits `src:O:9155:hsys 261`, seccomp `src:O:9209:hsys 277`, execveat `src:O:9223:hsys 281`. Each failing step returns its errno. || EVIDENCE: `check:LF#3` (the new image's fopen is refused) `legacy:S6/pure-launch.om` `legacy:S6/pure-busy.om` `legacy:S6/pure-other.om` `legacy:S6/pure-output.om`.
- L: the execprog packet limits, and the fixed strict profile: Landlock ABI3 inode-only execute/read, no-new-privs, seccomp read fd0/write fd1..2/exit/exit_group/execveat fd3 only, no weaker fallback. Retained rlimits are CPU soft/hard 1/2 s, FSIZE1MiB, STACK8MiB, CORE0, NPROC0, NOFILE4, AS128MiB (existing documented values, not new caps) `src:O:9055:if eq c 198` `src:docs/one_layer/OMEGESE.md:1324:sets seven` `src:docs/one_layer/OMEGESE.md:1325:0, descriptors 4, address space 128 MiB` || EVIDENCE: `check:LF#13` `legacy:S6/pure-launch.om`. NOT_COVERED: the security673 pure-*.om fixtures are not named by any cases row or by seed/host/check.sh at this head (they are run by the security673 gate programs, outside the files read here); the matrix binds their identity to the base, not their execution.

### ROW execenv:233

- T: AArch64 Linux program mode `src:O:12040:hpack c dst x`; x86linux `src:O:22140:xhpack c dst x`; function mode 9, contract 30, EFI targets 25. Lowering unchanged from the base: `samefn:O:hpack` `samefn:O:xhpack`. || EVIDENCE: `case:XC:fixture` `case:XC:x86-fixture` `case:XC:fnmode` `case:XC:x86-fnmode` `case:XC:contract` `legacy:seed/host/execenv/execenv.om` `legacy:seed/host/execenv/execenv.cases`.
- P: hpoolok 1 (new at this head); both packets `src:O:8901:e = harray x 0` `src:O:8909:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#4` `check:LF#14-15` `case:HC:mut-legacy-admit`.
- W: A and B read-only; both decoded into the private frame. `src:O:8909:e = harray x 0` || EVIDENCE: `check:LF#4` `case:XC:oracle`. NOT_COVERED: no case asserts A and B unchanged after a failed launch.
- A: both packets' byte limits are tested before the frame `src:O:8929:trapc 8 3` `src:O:8947:matconst 16 4096` `src:O:8949:trapc 8 3`; then a fixed 90112-byte frame `src:O:8952:stack = ulong 90112`. Both packets are fully decoded before any descriptor closes. || EVIDENCE: `case:XC:fixture` `case:XC:mut-a64-nonempty` `case:XC:mut-x86-firstonly` `check:LF#15`.
- S: one pass per packet into the frame; the kernel uses only the frame `src:O:9244:hsys 221`. || EVIDENCE: `case:XC:oracle` `case:XC:mut-a64-envp` `case:XC:mut-x86-envp`.
- D: close_range as execprog `src:O:9050:hsys 436`, after both packets are checked. || EVIDENCE: `case:XC:fixture` `check:LF#4`.
- L: argv packet as execprog; environment 2..4096 bytes `src:O:8947:matconst 16 4096`, 1..64 records `src:O:8885:ret 64`, every record nonempty. || EVIDENCE: `case:XC:mut-a64-nonempty` `check:LF#14-15` `legacy:seed/host/execenv/execenv.om`.

### ROW renames:125

- T: AArch64 Linux program mode `src:O:12235:hpack c dst x`; x86linux `src:O:22140:xhpack c dst x`; shared refusals elsewhere. Lowering unchanged from the base: `samefn:O:hpack` `samefn:O:xhpack`. || EVIDENCE: `case:HC:legacy` `check:LF#5` `legacy:S6/renames-consumer.om`. NOT_COVERED: within the cases files read for this matrix no row compiles renames for x86linux, an EFI target, function mode or a contract clause.
- P: hpoolok 1 (new at this head); `src:O:8901:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#5` `check:LF#16` `case:HC:mut-legacy-admit`.
- W: A read-only; flags int `src:O:8903:harg x 2 8`; the two paths are decoded into the private frame. || EVIDENCE: `check:LF#5`. NOT_COVERED: no case asserts A unchanged after a refused rename.
- A: byte limit before the frame `src:O:8926:matconst 16 4096` `src:O:8929:trapc 8 3`; a fixed 8192-byte frame `src:O:8937:stack = ulong 8192`; exactly two records `src:O:8973:trapc 1 3`. || EVIDENCE: `check:LF#16` `legacy:S6/renames-consumer.om` `legacy:S6/renames-corpus.om`.
- S: one decode-and-copy pass; `src:O:9255:hsys 276` uses only the frame. || EVIDENCE: `check:LF#5`.
- D: none `src:O:9255:hsys 276`. || EVIDENCE: N/A: renameat2 by path.
- L: packet 2..4096 bytes, exactly two nonempty records `src:O:8885:ret 64` `src:O:8973:trapc 1 3`. || EVIDENCE: `check:LF#16` `legacy:S6/renames-corpus.om` `case:HC:mut-pathsize` `mutant:HM/pathsize` (the 4096 constant is shared; the mutant is observed through symlnk, check 11). NOT_COVERED: no cases row at the head runs renames at its 4096-byte limit or names renames-consumer.om; check 16 cannot separate the slice check from the framing check (stated in legacy.om).

### ROW link:141

- T: AArch64 Linux program mode `src:O:12235:hpack c dst x`; x86linux `src:O:22140:xhpack c dst x`; shared refusals elsewhere. Lowering unchanged from the base: `samefn:O:hpack` `samefn:O:xhpack`. || EVIDENCE: `case:HC:legacy` `check:LF#6` `legacy:seed/host/tests/links.om` `legacy:seed/host/tests/links_short.om`. NOT_COVERED: within the cases files read for this matrix no row compiles link for x86linux, an EFI target, function mode or a contract clause.
- P: hpoolok 1 (new at this head); `src:O:8901:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#6` `check:LF#17` `case:HC:mut-legacy-admit`.
- W: A read-only; decoded into the private frame. `src:O:8901:e = harray x 0` || EVIDENCE: `check:LF#6`. NOT_COVERED: no case asserts A unchanged after a refused link.
- A: as renames: byte limit, 8192-byte frame, exactly two records `src:O:8973:trapc 1 3`. || EVIDENCE: `check:LF#17`.
- S: one decode-and-copy pass; `src:O:9265:hsys 37` uses only the frame. || EVIDENCE: `check:LF#6`.
- D: none `src:O:9265:hsys 37`. || EVIDENCE: N/A: linkat by path.
- L: packet 2..4096 bytes, exactly two nonempty records `src:O:8926:matconst 16 4096`. || EVIDENCE: `check:LF#17`. NOT_COVERED: no case runs link at its 4096-byte limit or one byte past it (legacy.om checks 10 and 11 use symlnk).

### ROW symlnk:142

- T: AArch64 Linux program mode `src:O:12235:hpack c dst x`; x86linux `src:O:22140:xhpack c dst x`; shared refusals elsewhere. Lowering unchanged from the base: `samefn:O:hpack` `samefn:O:xhpack`. || EVIDENCE: `case:HC:legacy` `check:LF#7` `legacy:seed/host/tests/links.om`. NOT_COVERED: within the cases files read for this matrix no row compiles symlnk for x86linux, an EFI target, function mode or a contract clause.
- P: hpoolok 1 (new at this head); `src:O:8901:e = harray x 0`. || EVIDENCE: `case:HC:legacy` `check:LF#7` `check:LF#10-11` `check:LF#18` `case:HC:mut-legacy-admit`.
- W: A read-only; decoded into the private frame. `src:O:8901:e = harray x 0` || EVIDENCE: `check:LF#7`. NOT_COVERED: no case asserts A unchanged after a refused symlnk.
- A: as renames: byte limit, 8192-byte frame, exactly two records `src:O:8973:trapc 1 3`. || EVIDENCE: `check:LF#10-11` `check:LF#18`.
- S: one decode-and-copy pass; `src:O:9270:hsys 36` uses only the frame. || EVIDENCE: `check:LF#7` `check:LF#10`.
- D: none `src:O:9270:hsys 36`. || EVIDENCE: N/A: symlinkat by path.
- L: packet 2..4096 bytes, exactly two nonempty records `src:O:8926:matconst 16 4096`. || EVIDENCE: `check:LF#10-11` `case:HC:mut-pathsize` `mutant:HM/pathsize`.

### ROW device-group:166-177,228-232

- T: AArch64 Linux: 166..177 program mode and OM-2 function mode `src:O:11754:if and ge c 166 le c 177`; OM-1 function mode 9. VFIO 228..232 program-only `src:O:11781:if and ge c 228 le c 232`. x86linux: 166..177 lowered by xhost (OM-2 functions allowed `src:O:22020:if and le c 177 ge c 166`); 228..232 are 9 in function mode, else 25 `src:O:11708:fail 9` `src:O:11712:fail 25`. EFI targets 25 at the shared sites; contract clauses 30. || EVIDENCE: `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-dev` `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-hold` `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-bind` `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-x86-dev` `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-x86-hold` `case:seed/omc/om2/fnhost/fnhost.cases:fnhost-x86-bind`. NOT_COVERED: no per-word EFI or contract refusal cited for this group; fnhost emit rows pin lowering bytes, not runtime effects.
- P: hpoolok 0 `src:O:11691:and ge c 166 le c 177 and ge c 228 le c 232` `src:O:11692:ret 0`; array-taking members refuse a pool with error 7 `src:O:5676:fail 7`. Scalar-only mapnew/mapdrop/mapaddr/mapget/mapset/maphold/mapbind/eventfd have no byte operand. || EVIDENCE: `case:HC:devctl` `case:HC:mut-devadmit` `mutant:HM/devadmit` `case:HC:mut-kfdadmit-dev` `file:seed/omc/tests/pools/err-devctl.om` `file:seed/omc/tests/pools/err-mapwrite.om` `test:seed/omc/gate-pools.sh:322:for c in err-x86 err-devctl err-mapwrite`. NOT_COVERED: the pool refusal is exercised for devctl 166 and mapwrite 170, not mapread 169, devcall 171, uvmctl 172, vfioctl 228, vfiomap 229, vfiomapw 230 or vfioirq 232.
- W: devctl 166 and uvmctl 172 require writable spans `src:O:12151:e = harray x 1` `src:O:12101:e = harray x 1` (kernel ioctl may write on either success or errno; no compiler rollback). mapread 169 writes A; mapwrite 170 reads A `src:O:10793:e = harray x wr`, after handle/extent checks. devcall 171: writable H and P, private 32-byte H; its pointer field never copied back, other H fields copied back even on error `src:O:10898:for i ulong 4` `src:O:10899:if ne i 2`; P passed directly. vfioctl 228: request 15210 takes a read-only device-name path `src:O:11816:e = harray x 0`; others writable `src:O:11867:e = harray x 1`, argsz stored before the call for structured requests `src:O:11880:mimmed 3103784960 16 2 0`, so errors can still leave compiler writes. vfiomap/w 229/230 read a 32-byte region-info slice `src:O:10488:harray x 0`. vfioirq 232 writable (GET_IRQ_INFO writes; SET_IRQS reads supplied eventfd values after kind checks, without rewriting them) `src:O:11949:e = harray x 1` `src:O:12012:mimmed 3107979264 10 6 0`. Other group members have scalar operands only; mapset writes owned mapping bytes. || EVIDENCE: `test:seed/host/tests/devcall.om:50:ck eq devcall` `test:seed/host/tests/devcall.om:53:ck eq get header i 0` (error-path pointer stays zero, length copied back). NOT_COVERED: no single cited case establishes every ioctl's success/error write set; Linux/driver partial writes are ABI-dependent, not erased by compiler admission.
- A: mtinit reserves a 4096-byte mapping table in unit BSS, compile capacity error 23 `src:O:10340:fail 23` `src:O:10343:put poolb 0 add p 4096`. VFIO reserves a 2048-byte descriptor table in BSS `src:O:11790:put poolb 0 add fdpool 2048`. mapnew/hold/vfiomap/w validate shapes and search a free slot before mmap `src:O:10642:matconst 0 18446744073709551592` `src:O:10653:hsys 222`; a full program table returns -24 without mapping. devcall checks H=32, P<=1048576 and nonoverlap before its 32-byte stack copy and ioctl `src:O:10888:spsub 32` `src:O:10897:hsys 29`. vfioctl device-name uses a 4096-byte stack copy; other ioctl spans are direct. mapread/write/get/set/addr have no allocation or kernel call. || EVIDENCE: `test:seed/host/tests/devcall.om:15:header 0 31` `test:seed/host/tests/devcall.om:32:large 0 1048577` `test:seed/host/tests/devcall.om:75:large 0 16384`. NOT_COVERED: no cited case forces the BSS capacity refusals or independently observes all preflight-before-call paths of this group.
- S: devcall snapshots H and substitutes pointer/length from P, then copies nonpointer H fields back `src:O:10890:for i ulong 4` `src:O:10894:mstore 11 31 2`; P is not snapshotted. vfioctl GET_DEVICE_FD copies its device-name path; other devctl/uvmctl/vfioctl/vfioirq spans are direct, no snapshot. mapread/write are byte loops between two checked spans `src:O:10824:head = get oc 0`; mapget/set use one aligned 32/64-bit load/store bracketed by DSB SY `src:O:10969:emit 3573759903` `src:O:10979:emit 3573759903`. || EVIDENCE: `test:seed/host/tests/devcall.om:53:ck eq get header i 0`. NOT_COVERED: no caller-memory mutation control challenges the private header or direct-span reads for this group.
- D: mappings use generation-bearing handles (program 128 slots, 8-bit slot index; function capacity 1..4098, 13-bit slot index) `src:O:10416:fn mcheck`. mapdrop munmaps, invalidates on success; mapbind replaces only a whole owned PROT_NONE reservation, retires it after bind failure/cleanup, with no second bind if cleanup fails `src:O:10726:fn mbind` `src:O:10768:note Preserve a droppable owner`. vfioctl GET_DEVICE_FD and eventfd record descriptor kinds only on success `src:O:11833:fdrecord 1` `src:O:11930:fdrecord 2`; eventfd always CLOEXEC|NONBLOCK `src:O:11928:matconst 1 526336`; dupfd does not propagate kind. vfioirq checks both acquired-device and eventfd kinds; other ioctls do not consume descriptors. || EVIDENCE: `test:tests/kfd/check.py:266:execute('mapping-large-aligned'` (mapbind/mapdrop/mapget/mapset in synthetic CPU fixture). NOT_COVERED: cited group evidence does not cover all VFIO kind transitions or cleanup failures; these are not hardware-qualified by CPU tests.
- L: retained: pool exclusion; program mapping table 128, function capacity 1..4098/generation limits `src:O:10430:matconst 15 4098` `src:O:10638:mimmed 4043309056 31 10 128`; mapget/set width literal4/8, aligned in live extent, write requires RW `src:O:10930:if and ne w 4 ne w 8` `src:O:10957:trapc 1 3`; mapnew/hold/vfiomap length<=68719476736 `src:O:10550:matconst 15 68719476736`; fixed reservations page-aligned, address>=65536 and end<=1099511627776 `src:O:10583:note Reservations are page aligned`; access 1/3, non-executable allowed modes only `src:O:10512:if and ne acc 1 ne acc 3`. devctl literal FIONREAD, NVRM read/write type-F or exact aien-gpu ABI allowlist, request-encoded exact size; devcall only RM_ALLOC/RM_CONTROL, H32/P1048576/nonoverlap/zero caller pointer; uvmctl exact allowlisted request and ABI580.173.02 sizes via xhreq `src:O:21844:fn xhreq`. VFIO allowlist excludes RESET; MAP_DMA requires an owned writable handle, UNMAP_DMA flags=0; IRQ argsz/count/action/event constraints remain in hostval `src:O:11795:resets the device` `src:O:11804:The caller chooses only the IOVA` `src:O:11974:matconst 7 4294967295`. || EVIDENCE: `case:seed/host/devcall-mutants.cases:devcall-cap-offbyone` `case:seed/host/devcall-mutants.cases:devcall-cap-removed` `test:seed/host/tests/devcall.om:78:large 1 1048576`. NOT_COVERED: no cited case exercises every retained mapping/VFIO containment limit; these limits must not be removed by the trusted-packet change.

### ROW kfdctl:241

- T: program-mode Linux, a64 `src:O:11774:kctl dst x` and x86linux `src:O:22047:kctl dst x`. OM-1 and OM-2 functions 9 `src:O:11760:fail 9` `src:O:22026:fail 9`; EFI 25 at the shared sites; contracts 30. || EVIDENCE: `test:tests/kfd/check.py:148:for target in ('a64','x86'):` `test:tests/kfd/check.py:150:compile_case(name,source(name),target)` `test:tests/kfd/check.py:217:compile_case('function-'+word` `test:tests/kfd/check.py:218:compile_case('om2-function-'+word`. NOT_COVERED: no EFI or contract refusal in this KFD instrument; its x86 execution is QEMU, never native/hardware evidence.
- P: hpoolok 0 `src:O:11691:and ge c 241 le c 243`; flag stored BEFORE dispatch a64 `src:O:11770:add x 31 hpoolok c`, x86 `src:O:22043:add x 31 0`; pool header is error 7. || EVIDENCE: `case:HC:kfdctl` `case:HC:mut-devadmit-kfd` `case:HC:mut-kfdadmit` `mutant:HM/kfdadmit`. NOT_COVERED: no in-tree case specifically challenges slot-store ordering; the lane static-control instrument is outside the head. Admission mutants test the hpoolok predicate, not a stale frame.
- W: H writable, optional payload P writable, distinct arrays error 19 `src:O:11530:e = harray x 1` `src:O:11557:f = harray x 1` `src:O:11561:fail 19`; runtime overlap traps 3 in kspan. Mapped payload form must be live RW and fit its bounds. Kernel receives private H; scalar fields copied back even on errno, pointer fields excluded `src:O:11676:if not kptr q mul i 8` `src:O:11678:kfdstore 1 3 mul i 8`; direct P may be written on success or error by the kernel. || EVIDENCE: `test:tests/kfd/check.py:297:compile_case('trace-'+name` `test:tests/kfd/check.py:291:if ne get H` `test:tests/kfd/check.py:304:('count',aperture(count=0,length=0))` `file:tests/kfd/trace.c`. NOT_COVERED: CPU syscall-boundary injection establishes H copy-out and pointer omission, not an actual AMD driver's partial writes into P.
- A: literal allowlisted request and literal exact H size enforced before codegen `src:O:11525:fail 9` `src:O:11535:fail 9`; dynamic exact-size check BEFORE scratch `src:O:11581:kfdtrap 1`. Scratch z+176 bytes with stack check `src:O:11587:spsub add z 176` `src:O:11588:stkchk`, private header copy, address/span/handle validation; ACQUIRE_VM performs fstat before ioctl `src:O:11602:kdrm z`. The ioctl itself `src:O:11667:hsys 29` / `src:O:11672:xhcall 16` is last; no mmap is done by kctl. || EVIDENCE: `test:tests/kfd/check.py:182:('wrong-request'` `test:tests/kfd/check.py:183:('wrong-size-literal'` `test:tests/kfd/check.py:184:('wrong-size-dynamic'` `test:tests/kfd/check.py:187:('wrong-drm-kind'`. NOT_COVERED: no stack-exhaustion case for the scratch allocation.
- S: private H copy, validate zero address fields, bind addresses only from checked handles/spans, then copy back only non-address words `src:O:11594:for i ulong div n 8` `src:O:11596:kfdstore 0 4 mul i 8` `src:O:11676:if not kptr q mul i 8`. P is not copied; no hidden snapshot claim for P. || EVIDENCE: `test:tests/kfd/check.py:300:record('trace '+name` `test:tests/kfd/check.py:307:for expected,want in [(16,0),(17,1)]:` `file:tests/kfd/trace.c`. NOT_COVERED: no concurrent caller-H mutation between validation and ioctl; the trace oracle tests the address actually received instead.
- D: uses fd without opening/closing it; ACQUIRE_VM validates a supplied DRM render fd with fstat `src:O:11361:fn kdrm` `src:O:11365:hsys 80`. Kernel KFD object handles copied out are opaque scalars, not compiler mapping handles. || EVIDENCE: `test:tests/kfd/check.py:187:('wrong-drm-kind'` `test:tests/kfd/check.py:151:103 if name=='ACQUIRE_VM' else 0`. NOT_COVERED: device/object lifecycle remains explicitly NOT_RUN `test:tests/kfd/check.py:160:NOT_RUN device`; no AMD device is opened by this CPU instrument.
- L: 13 request IDs only, exact ABI H sizes 8/16/24/32/40/88 `src:O:11087:fn ksize` `src:O:11111:fail 9`. Pointer fields zero; no USERPTR `src:O:11647:note USERPTR`; count*stride fits P, WAIT_EVENTS extension NULL `src:O:11339:note event_data.ext`; live generation/kind/extent enforced by kbind `src:O:11175:mcheck`. Ring>=1024, power-of-two `src:O:11501:fn kring`; shared wptr/rptr means queue type 2 and full 2304-byte object at compiler-owned +56/+128 offsets `src:O:11625:wshape = or shl ulong 56 32 shl ulong 2248 48` `src:O:11627:rshape = or shl ulong 128 32 shl ulong 2176 48`. || EVIDENCE: `test:tests/kfd/check.py:165:compile_case('sibling-refusal-'+name` `test:tests/kfd/check.py:185:('ring-small'` `test:tests/kfd/check.py:189:('event-extension'` `test:tests/kfd/check.py:190:('userptr'` `test:tests/kfd/check.py:198:'queue-object-short-'` `test:tests/kfd/check.py:343:('request'` `test:tests/kfd/check.py:357:('queue-object-range'` (mutants and exact expected traps; not a hardware claim).

### ROW kfdmap:242

- T: a64 Linux `src:O:11776:mnew c dst x` and x86linux `src:O:22049:xhmnew c dst x`, program only (function 9, EFI 25, contract 30 at shared sites). || EVIDENCE: `test:tests/kfd/check.py:216:('kfdmap','kfdmap neg int 1 0 4096')` `test:tests/kfd/check.py:217:compile_case('function-'+word` `test:tests/kfd/check.py:218:compile_case('om2-function-'+word`. NOT_COVERED: EFI and contract refusals not exercised in this KFD instrument; x86 is QEMU only.
- P: hpoolok 0, without effect: fd int, offset/length ulong `src:O:10476:harg x 0 8` `src:O:10477:harg x 1 5` `src:O:10478:harg x 2 5`. || EVIDENCE: N/A: no byte operand for a pool.
- W: no caller byte array; on success returns an owned RW shared mapping handle, no descriptor mutation `src:O:10479:acc = ulong 3` `src:O:10480:mode = ulong 1`; error paths leave no mapping entry. || EVIDENCE: `test:tests/kfd/check.py:314:size=68721573888` `test:tests/kfd/check.py:319:h = kfdmap int f 0 {size}` `test:tests/kfd/check.py:335:record('fd trace synthetic mode '` `file:tests/kfd/fdtrace.c` (synthetic accepted fstat, actual memfd mmap/readback, not AMD mapping evidence).
- A: kmapfd uses 352 bytes of checked stack and fstat on fd; accepts DRM render character device or compares st_rdev to stat(/dev/kfd) `src:O:11415:fn kmapfd` `src:O:11417:spsub 352` `src:O:11420:hsys 80` `src:O:11466:hsys 79`. No device is opened. Then nonzero length/free-table-slot before mmap `src:O:10548:trapc 0 3` `src:O:10653:hsys 222`. || EVIDENCE: `test:tests/kfd/check.py:268:execute('map-regular-refusal'` `test:tests/kfd/check.py:270:execute('map-character-refusal'` `test:tests/kfd/check.py:272:execute('map-invalid-fd'` `test:tests/kfd/check.py:366:('map-fd'` (admission-removal mutant). NOT_COVERED: no distinct mmap-failure or table-full kfdmap case; shared mnew logic is source-derived here.
- S: fd evaluated once and saved; class/rdev checked with fstat, not a caller pathname; mapping base comes only from mmap `src:O:10530:kmapfd` `src:O:11413:note The fd is already evaluated and saved`. No caller header to copy. || EVIDENCE: `test:tests/kfd/check.py:333:for mode in range(7):` `file:tests/kfd/fdtrace.c` (controls vary reported fd identity).
- D: caller fd stays open; mmap returns a generation-tagged mapping entry, consumed by mapdrop, usable by mapget/set/addr/bind and KFD binders `src:O:10703:mstore 0 9 0` `src:O:10706:mstore 11 9 2`. || EVIDENCE: `test:tests/kfd/check.py:323:r = mapset h {size-8} 8 12345` `test:tests/kfd/check.py:324:if ne mapget h {size-8} 8 12345` `test:tests/kfd/check.py:327:r = mapdrop h` (synthetic trace fixture).
- L: nonzero full-ulong length, no 64-GiB cap for c>=242 `src:O:10549:if lt c 242`; mapping offset/page/device/address-space limits remain kernel-enforced. Character-device allowlist above; program table/generation bounds unchanged. || EVIDENCE: `test:tests/kfd/check.py:314:size=68721573888` `test:tests/kfd/check.py:367:('kmapfd'` (kind mutation) `test:tests/kfd/check.py:268:map-regular-refusal`. NOT_COVERED: no real AMD mapping qualified, and zero-length kfdmap is not an isolated case in this instrument.

### ROW kfdres:243

- T: a64 Linux `src:O:11776:mnew c dst x` and x86linux `src:O:22049:xhmnew c dst x`, program only (function 9, EFI 25, contract 30 at shared sites). || EVIDENCE: `test:tests/kfd/check.py:216:('kfdres','kfdres 4096')` `test:tests/kfd/check.py:217:compile_case('function-'+word` `test:tests/kfd/check.py:218:compile_case('om2-function-'+word`. NOT_COVERED: EFI and contract refusals not exercised in this KFD instrument; x86 is QEMU only.
- P: hpoolok 0, without effect: one ulong length `src:O:10483:harg x 2 5`. || EVIDENCE: N/A: no byte operand.
- W: no caller byte array; returns an owned PROT_NONE reservation, no physical backing committed by the reservation `src:O:10473:acc = ulong 0` `src:O:10484:mode = ulong 34`. || EVIDENCE: `test:tests/kfd/check.py:224:r = kfdres 68721573888` `test:tests/kfd/check.py:241:r = kfdres 4096`.
- A: nonzero/page-multiple length, addition-overflow check before over-reserving length+2MiB `src:O:10565:trapc 1 3` `src:O:10568:trapc 2 3`; free slot then mmap `src:O:10653:hsys 222`; align base and munmap only the fresh prefix/suffix `src:O:10672:hsys 215` `src:O:10682:hsys 215`, trapping if trim fails. || EVIDENCE: `test:tests/kfd/check.py:273:('reserve-zero','kfdres 0')` `test:tests/kfd/check.py:266:execute('mapping-large-aligned'`. NOT_COVERED: no injected mmap/trim failure or kfdres table-exhaustion case.
- S: no caller memory; stores exact requested length, not over-reservation length, in the owned table `src:O:10686:mload 1 31 0` `src:O:10704:mstore 1 9 1`. || EVIDENCE: `test:tests/kfd/check.py:243:if ne mapbind r int f 0 3 0` (whole-reservation bind), `test:tests/kfd/check.py:193:('short-handle'` (size used by KFD binding).
- D: no fd opened; creates a generation-tagged reservation handle, later consumable by mapbind/mapdrop `src:O:10706:mstore 11 9 2`. || EVIDENCE: `test:tests/kfd/check.py:231:if ne mapdrop r 0` `test:tests/kfd/check.py:243:if ne mapbind r int f 0 3 0`.
- L: no old maphold address/64GiB limit, but nonzero page multiple, no addition overflow, 2MiB alignment, exact extent, live generation/table bounds retained `src:O:10549:if lt c 242` `src:O:10562:matconst 15 4095` `src:O:10658:matconst 15 2097152`. || EVIDENCE: `test:tests/kfd/check.py:273:('reserve-overflow','kfdres 18446744073709547520')` `test:tests/kfd/check.py:228:if ne and mapaddr r 2097151 0` `test:tests/kfd/check.py:266:execute('mapping-large-aligned'`.

### ROW efi:178

- T: a64efi calls `src:O:12473:aefival dst`; all other targets dispatch to `src:O:12482:xefival dst`, error25 unless x86efi `src:O:23580:if ne get xtarget 0 2` `src:O:23583:fail 25`. OP literal 0..14, else25 `src:O:23594:fail 25` `src:O:25033:fail 25`. a64efi requires correctly typed fn efirt (missing16/type9); x86efi implements firmware ops itself. || EVIDENCE: `test:tests/a64efi/run.sh:71:refuse "efi OP above 14" "7 25"` `test:tests/a64efi/run.sh:70:refuse "efi without fn efirt" "4 16"` `test:tests/x86efi/run.sh:83:boot refusals`. NOT_COVERED: no cited compile-refusal case for efi in a64 Linux/x86linux; the runtime file/refusal tests select x86efi.
- P: efi is dispatched outside hostval/hpoolok, so hpoolok(178)=1 is NOT the effective rule. Both EFI handlers explicitly write slot31=0 before harray: x86efi `src:O:23589:add x 31 0` then `src:O:23597:e = harray x 1`; a64efi `src:O:25028:add x 31 0` then `src:O:25036:e = harray x 1`. Pool declarations already fail25 on either target. || EVIDENCE: `test:tests/a64efi/run.sh:69:refuse "run-time pool" "2 25"`. NOT_COVERED: no in-tree removal/order mutant for either slot31 write; x86efi has no pool-declaration refusal row. Slot-store protection is currently lane-static evidence only, not runtime coverage.
- W: writable uchar span always required, even for input-only ops `src:O:23597:e = harray x 1`. x86efi op0/info, 5/entropy, 6/receive, 9/pointer, 14/identity write within A; 3/blit, 7/transmit, 13/console read it. 11/file and 12/file are direction-dependent (read writes A, write/path reads A) `src:O:24540:note finds the boot one` `src:O:24646:note result FileSize`. Firmware I/O errors have no universal no-write guarantee (a partial read may have written bytes). a64efi passes A+OFF,N to user-defined efirt without copying `src:O:25076:emit or 2483027968 bdisp`; that function defines effects, not Linux ABI. || EVIDENCE: `test:tests/x86efi/refusals/g4.om:90:hx efi 12 65280 db 12 8` (slice overflow trap3) `test:tests/x86efi/file/t1.om:29:w = efi 12 65283 db 0 2` `test:tests/x86efi/run.sh:88:boot file`. NOT_COVERED: no view/text admission refusal or firmware partial-error write-set test cited; no blanket unchanged-buffer claim.
- A: x86efi creates 65536-byte private stack area and checks the floor before xeop/firmware `src:O:23606:note Firmware runs on the owned stack` `src:O:23607:xcheck 65536`. Paths/console conversion use that scratch, not caller addresses. Protocol discovery may allocate firmware buffers, with its own cleanup; a64efi only saves registers and calls efirt `src:O:25069:save` `src:O:25076:emit or 2483027968 bdisp`. || EVIDENCE: `test:tests/x86efi/run.sh:83:boot refusals` `test:tests/x86efi/run.sh:88:boot file`. NOT_COVERED: no injected stack-floor or firmware-allocation failure in the cited EFI tests.
- S: the x86 snapshot is saved REGISTERS, not a snapshot of A `src:O:23598:note RBX anchors the snapshot`. x86 paths converted privately; console validates every input byte before output and chunks into private UCS-2 `src:O:24125:note efi 13` `src:O:24127:note characters in private 4096`; transmit keeps its private packet until firmware reclaims that address `src:O:24026:note Transmit always owns its private packet`. No input snapshot on a64efi before efirt. || EVIDENCE: `test:tests/x86efi/run.sh:88:boot file`. NOT_COVERED: no caller-memory mutation control challenges path/console/transmit snapshot ownership.
- D: no Linux fds. op11 closes private file/root handles on every path `src:O:24542:note root handles are closed on every path`. op12 persists one file/root pair between operations; invalid sub/path/busy/no-open/readonly-write refusals preserve existing ownership; read/write failures preserve it; volume failures empty it; open/GetInfo failures close it; close flushes and closes even on flush failure; shared exit closes a still-open file `src:O:24649:note and its volume root in 2312` `src:O:24651:note 41 GetInfo` `src:O:24655:note failed. A file still open at exit`. a64efi efirt owns its own resources. || EVIDENCE: `test:tests/x86efi/refusals/g4.om:75:hx efi 12 65281 pa 0 7` `test:tests/x86efi/refusals/g4.om:78:hx efi 12 65284 db 0 0` `test:tests/x86efi/refusals/g4.om:85:hx efi 12 65283 db 0 4` `test:tests/x86efi/run.sh:83:boot refusals`. NOT_COVERED: no injected firmware Flush/GetInfo/Open failure to prove every cleanup branch.
- L: OP0..14; slice/type/writability checks. File path1..255 printable bytes starting backslash; one open file; enumerated volumes<=64; console printable/tab/CR/LF only; exact op-specific buffer minima, no arbitrary firmware pointer operand `src:O:24644:note loaded from), position bits16..63` `src:O:24409:note Volumes` `src:O:24125:note efi 13`. a64efi restricts efirt signature (four ulong parameters, ulong return), not its implementation `src:O:25043:note efirt takes four ulong values`. || EVIDENCE: `test:tests/x86efi/refusals/g4.om:69:hx efi 12 65280 pa 0 0` `test:tests/x86efi/refusals/g4.om:71:hx efi 12 65280 pa 0 256` `test:tests/x86efi/refusals/g4.om:73:hx efi 12 65280 pa 0 255` `test:tests/a64efi/run.sh:71:refuse "efi OP above 14" "7 25"`. NOT_COVERED: no x86efi OP>14 compile refusal or over-64-volume case cited; op-specific firmware/device tests do not establish all possible error write sets.

## Source observations (found while building this matrix; resolved in this head)

1. The omc.om note before the x86linux container refusal said "207..214" while its test refuses 202..214; the note now
   says 202..214 (`src:O:22035:note Container words 202..214`).
2. seed/host/execfds/check.sh said "24 checks" and "five check-removal mutants"; it now says 29 checks and ten mutants
   (five keep-list, five prepass), as execfds.cases has them.
3. Under x86linux a container word in a function unit is error 9 (the function-mode test comes first), while execfds 201
   and fstatfs 215 are error 25 in every mode. OMEGESE.md now states this, and container.cases holds the two units
   (`case:CC:x86-fnmode`, `case:CC:x86-fnmode-om2`).
4. OMEGESE.md said only execfds is input-sized; mount and pivroot decode their caller-owned packed lists through the same
   sizing path (`src:O:10209:hpackn c dst x`), and the paragraph now names them.
