# effects: capability manifest derived from Omega source

A seeded-Omega program reaches the kernel only through the closed keyword set in
[OMEGESE section 10](../../docs/one_layer/OMEGESE.md) and
[MAPPING.md](../host/MAPPING.md): there is no raw syscall and no address-to-pointer
conversion. The host words that appear in a unit are therefore a complete, finite list
of the OS effects it can have. This tool turns that list into a manifest, checks it
against the compiled binary, and emits a seccomp filter that enforces it.

```
seed/out/omc < seed/effects/effects.om > effects && chmod +x effects
effects src [allow=C,..] < unit.om      host words, classes, Linux syscalls; policy check
effects elf < binary                    syscalls the omc ELF can issue (fail closed)
effects verify SRC BIN [allow=C,..]     ELF syscalls must lie within the source manifest
effects bpf [launch] < unit.om          seccomp cBPF allow-list for bwrap --seccomp
effects table                           word, class and syscalls, one per line
```

Classes: `io` (read, write), `fd`, `path`, `net`, `proc`, `ident`, `time`, `env`,
`random`, `device`, `mem` (`enlarge`: anonymous memory growth via mremap 216 / mmap 222,
separated from `device` so verifiers need not allow GPU ioctl 29). `exit`/traps (syscall 93) are always allowed.

Exit status: 0 pass, 1 refused or undeclared syscall, 2 usage, 3 invalid or
unresolvable input, 4 read error.

`elf` treats every SVC in an executable load segment as reachable. Each SVC must be
immediately preceded by `MOVZ X8,#n`, and the segment may contain no `BR`/`BLR`; both
rules apply to every word of the segment, instruction or not. No direct branch may land
on an SVC. That rule applies to the words control can reach: omc puts texts in the same
segment as the instructions, and a text can hold the bit pattern of a branch (the four
bytes `@-(6` read as `TBZ`), so holding data to it refused correct programs, omc itself
among them. Reach starts at the entry word and follows the next word and the target of
every direct branch; it stops after an unconditional `B`, a `RET`, and an SVC whose
number is 93 or 94 (exit, exit_group). Such an SVC does not return, and the reason is part
of the rule: it can be entered only through the `MOVZ X8` before it, because a reached
branch onto it is refused and an entry point on an SVC is refused, so X8 holds 93 or 94
when it runs. Reach must not lose control, so three more things are refused: an entry
point that is an SVC, a reached direct branch whose target lies outside the segment, and
a reached word that falls through past the last word of the segment. A reached
register-branch instruction other than `RET` (the pointer-authentication forms, `ERET`) and
a reached `BC.cond` are refused as well, because the walk cannot follow them. When the entry point
is not in the segment, every word is held to the rule. Anything else is `ELF UNRESOLVED`
(exit 3). W+X segments are refused. A binary from another producer will usually fail
closed.

What this does not show: that a `RET` returns to the word after a `BL`. The calling
sequence the compiler emits is relied on for that, as it was before this rule was narrowed.

## Qualification

`sh seed/effects/check.sh` (pinned omc; strace, bwrap, od and dd as oracles):

- closure: every keyword with a host code in `seed/omc/genkw.awk` (all `split("…")` lists,
  found by content) is in the table, except `const`/`qty` (types), `cpufence`/`cpurelax`,
  which lower to `DSB SY`/`YIELD`, and `fma` (fused multiply-add, one `FMADD`); a probe shows
  they add no syscall beyond exit (93). The VFIO words are `device` (`vfioctl`, `vfioirq`:
  ioctl 29; `vfiomap`, `vfiomapw`: mmap 222) and `eventfd` is `fd` (eventfd2 19). `enlarge` (run-time
  pools) maps the process's own anonymous memory and is in the dedicated `mem` class (mmap 222 at the
  first growth, mremap 216 past the capacity) so verifiers can grow pools without allowing `device` ioctl 29.
  `omc.om` has exactly 7 SVC emit sites (a new site means the table needs review); `fn en_help` holds
  two of them, the omc_enlarge helper's mremap and mmap
- probe parity: one compiled probe per word; the ELF syscalls equal the table row. A row
  lists any number of syscalls (`execpure` lowers to ten, `execprog` to execve and close_range). A word
  that cannot be an expression names a whole probe program instead (`enlarge|@probe-enlarge.om` in
  `cases/probes.txt`)
- self manifest, fixtures, policy refusals with word, class and line
- every program-mode unit in `seed/host/tests` and `seed/rung4/tests`, and omc itself:
  binary syscalls lie within the source manifest
- strace: syscalls observed at run time lie within the ELF set
- seccomp: each fixture runs under its own filter; a binary run under a narrower
  filter is killed (exit 159, SIGSYS)
- fail-closed controls: SVC without `MOVZ X8`, `MOVZ X9`, branch into an SVC, `BR`,
  W+X segment, non-ELF input, a syscall number of 512 or more, no executable segment; the
  last two also check the reason text, which was empty before because the message numbers
  in the source pointed past the end of the message table
- data is not code: a text word patched into a `B` onto an SVC behind the entry branch,
  behind a `RET` and behind an exit SVC passes with the syscalls of the unpatched binary
  (`cases/tb-entry.om`, `tb-ret.om`, `tb-exit.om`); the same word is refused once the entry
  word branches to it; a `B` onto the SVC in the word after a returning SVC is refused; an
  entry point outside the segment holds every word; an entry point off a word boundary is
  invalid; an entry point on an SVC, a reached branch to past the end or to before the start
  of the segment, a reached word that falls off the end, a reached `BRAAZ` and a reached
  `BC.cond` are refused; a text word with the `BRAAZ` pattern passes
- tool mutants are killed, each by the control named for it in `check.sh`: dropped row,
  wrong syscall number, weakened MOVZ check, every word held again, nothing held, the
  outside-entry fallback off, fall-through after `B`, after `RET` and after exit, and the
  entry-SVC, leaves-segment and falls-off-the-end refusals each removed, and the two
  message numbers put back wrong, and the two unknown-branch refusals each removed

## Limits

- Classes and the filter work at syscall granularity. `fopen` is `path` whether it
  reads or writes; argument-level policy (literal open flags, socket families) is
  future work.
- `bpf launch` adds `execve` (221) so that bwrap can start the program. The program
  can therefore call execve itself under that filter. An in-program install would close
  this gap but needs a `prctl`/`seccomp` host word, which is a compiler change.
- The filter restricts syscalls only. The check runs bwrap with `--dev-bind / /`, so
  filesystem and namespace isolation are separate.
- The table is pinned to the compiler in `om/units.sh`. A compiler that changes how
  host words lower is caught by closure and probe parity, not silently accepted.
