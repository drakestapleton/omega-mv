# setprio (keyword 234)

`setprio which who prio` returns `long`: 0 or a negative errno from Linux
`setpriority` (AArch64 syscall 140, x86-64 syscall 141).

| operand | type | meaning |
|---|---|---|
| `which` | int | 0 PRIO_PROCESS, 1 PRIO_PGRP, 2 PRIO_USER |
| `who` | int | id for `which`; 0 is the caller (its process, group or user) |
| `prio` | int | nice value; the kernel clamps it to -20..19 |

Lowering the nice value (raising priority) without `CAP_SYS_NICE` or a
sufficient `RLIMIT_NICE` returns -13 (EACCES); another user's process returns
-1 (EPERM); an invalid `which` -22; a missing process -3. Program mode only:
function mode is error 9, a contract clause error 30, `target x86efi` error 25.
The nice value is inherited by `fork` and kept across `execprog`/`execenv`.

## Gate

`setprio.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=9`.

- `fixture`: `setprio.om` on AArch64. Kernel truth is field 19 (nice) of
  `/proc/<child>/stat`, read by the parent while the child is an unreaped zombie
  (never `/proc/self`, which qemu-user fakes): the inherited nice `n0`, a child
  raised to `n0+3`, that child refused when lowering it again (-13 or -1 unless
  euid 0), pid 1 refused (-1 unless euid 0), `which` 7 (-22), pid 2147483647 (-3).
- `x86-fixture`: `x86-target.om+setprio.om` through binfmt qemu-x86_64:
  emulator evidence, not hardware qualification.
- refusals: `fnmode.om` (9, AArch64 and x86linux), `contract.om` (30),
  `longwho.om` (7), `efi-target.om+use.om` (25).
- mutants (each `mutants/NAME.from` occurs once in `seed/omc/omc.om`):

| mutant | change | fixture exit |
|---|---|---|
| a64-sysno | syscall 140 to 141 (getpriority) | 2 |
| x86-sysno | syscall 141 to 140 (getpriority) | 2 |
