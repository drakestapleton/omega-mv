# realset (keyword 236)

`realset ns` returns `long`: 0 or a negative errno from Linux
`clock_settime(CLOCK_REALTIME)` (AArch64 syscall 112, x86-64 syscall 227).
It sets the machine's wall clock; `realns` reads it.

| operand | type | meaning |
|---|---|---|
| `ns` | long | nanoseconds since the Unix epoch; negative traps 3 before any kernel call |

- The timespec `{ns / 1e9, ns mod 1e9}` is built on the stack exactly as
  `sleepns` builds its interval.
- Without `CAP_SYS_TIME` the kernel returns -1 (EPERM). It validates the
  timespec first, so a second at or past `TIME_SETTOD_SEC_MAX` (8277292036)
  returns -22 (EINVAL) whatever the privilege.

Program mode only: function mode is error 9, a contract clause error 30,
a `ulong` operand error 7, `target x86efi` error 25.

## Gate

`realset.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=15`. It runs as an ordinary user and never changes the
host clock: the kernel's check order makes the clock id, the syscall number
and the seconds/nanoseconds split observable through EPERM versus EINVAL.

- `fixture`: `realset.om` on AArch64, 7 checks: the current time gives -1;
  2^63-1 ns gives -22; 8277292035999999999 ns (the last valid instant) gives
  -1 and 8277292036000000000 ns gives -22, which pins the split; a negative
  `ns` traps 3 in a child (exit 103); 0 gives -1; the clock did not jump. The
  fixture refuses to run as euid 0 (exit 90).
- `x86-fixture`: `x86-target.om+realset.om` through binfmt qemu-x86_64, whose
  `clock_settime` reaches the host kernel: emulator evidence, not hardware
  qualification.
- refusals: `fnmode.om` (9), `contract.om` (30), `ulongarg.om` (7),
  `efi-target.om+one.om` (25), x86 `fnmode.om` (9), x86 `ulongarg.om` (7).
- mutants: each `mutants/NAME.from` occurs once in `seed/omc/omc.om` and is
  replaced by `NAME.to`; the fixture built by that compiler must fail at the
  named check (exit = check number).

| mutant | change | fixture exit |
|---|---|---|
| a64-sysno | `hsys 112` to 113 (clock_gettime) | 1 |
| a64-clock | x0 = 1 (CLOCK_MONOTONIC) | 1 |
| a64-swap | seconds and nanoseconds stored in each other's slot | 1 |
| a64-noguard | negative-`ns` trap removed | 5 |
| x86-sysno | `xhcall 227` to 228 (clock_gettime) | 1 |
| x86-clock | RDI = 1 (CLOCK_MONOTONIC) | 1 |
| x86-noguard | negative-`ns` trap removed (shared with `sleepns`) | 5 |

Not observable without privilege: the value of the nanosecond field (any
value below 1e9 is valid), so a lowering that stored 0 there would pass this
gate. The privileged path, a clock actually set and read back with a
sub-second part of 999 ms, is exercised by aienux
`native/omega/interplane/tests/time_gate.sh` (QEMU guests, ledger L236).
