# execkeep (keyword 238)

`execkeep A off n B off m fd` returns `long`: it is `execenv A off n B off m`
(same packets, limits and checks: 1..32768 records, at most 2097152 bytes each)
except that descriptor `fd` stays open across the exec.

| operand | type | meaning |
|---|---|---|
| `A`, `off`, `n` | packet | argv packet (program path first, nonempty) |
| `B`, `off`, `m` | packet | environment packet (every record nonempty) |
| `fd` | int | descriptor kept open; must be >= 3 (trap 3) |

Order: both packets and `fd` are checked (trap 3) before any descriptor closes.
Then `close_range(3, fd-1, CLOSE_RANGE_UNSHARE)` (skipped when `fd` is 3) and
`close_range(fd+1, ~0U, CLOSE_RANGE_UNSHARE)`; either failure returns its
negative errno with no fallback. Then `execve(path, argv, envp)`; it returns
only on failure. The descriptor must not carry `FD_CLOEXEC` to survive the
exec (`fopen` without O_CLOEXEC, or `dupfd` with flags 0). Use: hold a flock
(e.g. a quiet-build lock on descriptor 9) across exec of the measured command.
Program mode only: function mode is error 9, a contract clause error 30,
`target x86efi` error 25. AArch64 and x86linux.

## Gate

`execkeep.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=13`.

- `fixture`: `execkeep.om` on AArch64. A forked child places a lock file on K,
  `/dev/null` on K-1 and K+1, takes a shared flock on K and execkeeps itself.
  The new image proves `flock K 6` (LOCK_EX|LOCK_NB) succeeds, K-1 and K+1 are
  closed (-9), a grandchild opening the file anew is refused with -11 (the lock
  is held across exec), and the environment is exactly `A=1`. K 9 and K 3 (the
  skipped first close); the same through `execenv` finds K closed (negative
  control); a missing program returns -2 after both closes (K-1, K+1 closed,
  K open); fd 2, 0 and -1 trap 3; 32769 environment records trap 3.
- `x86-fixture`: `x86-target.om+execkeep.om` through binfmt qemu-x86_64:
  emulator evidence, not hardware qualification.
- refusals: `fnmode.om` (9, AArch64 and x86linux), `contract.om` (30),
  `longfd.om` (7), `efi-target.om+use.om` (25).
- mutants:

| mutant | change | fixture exit |
|---|---|---|
| a64-keep | the second close_range starts at fd | 1 |
| a64-skip | the first close_range always skipped | 1 |
| a64-fdguard | no trap for fd below 3 | 5 |
| x86-keep | the second close_range starts at fd | 1 |
| x86-skip | the first close_range always skipped | 1 |
| x86-fdguard | no trap for fd below 3 | 5 |
