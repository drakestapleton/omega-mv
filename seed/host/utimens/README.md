# utimens (keyword 239)

`utimens A off n as ans ms mns flags` returns `long`: 0 or a negative errno
from Linux `utimensat(AT_FDCWD, path, {{as, ans}, {ms, mns}}, flags)` (AArch64
syscall 88, x86-64 syscall 280).

| operand | type | meaning |
|---|---|---|
| `A`, `off`, `n` | byte array, ulong, ulong | path `A[off..off+n)`, relative to the current directory; the slice is checked (trap 3), n above 4095 or an embedded zero byte traps 3, and a private zero-terminated copy reaches the kernel, as for the other path words |
| `as`, `ans` | long | atime seconds and nanoseconds |
| `ms`, `mns` | long | mtime seconds and nanoseconds |
| `flags` | int | passed unchanged; `AT_SYMLINK_NOFOLLOW` (256) sets a symbolic link's own times |

A nanosecond of `UTIME_NOW` (1073741823) or `UTIME_OMIT` (1073741822) passes
through unchanged (the seconds are then ignored). An empty path (n 0) is not
trapped: the kernel returns -2, as for the other path words. Other errors:
-2 for a missing path, -22 for a nanosecond outside 0..999999999 or an unknown
flag, -1/-13 without permission. Program mode only: function mode is error 9, a
contract clause error 30, `target x86efi` error 25.

## Gate

`utimens.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=14`.

- `fixture`: `utimens.om` on AArch64. Kernel truth is the 128-byte stat record
  (atime at bytes 72/80, mtime at 88/96) from `stat` and `lstat` of
  `/tmp/omega-utimens-<pid>-f` and the link `-l` to it: exact atime/mtime
  pairs, `UTIME_OMIT` keeping a field, `UTIME_NOW` inside the `realns` window,
  `AT_SYMLINK_NOFOLLOW` setting the link and not the target, flags 0 following
  the link, -2 for a missing path (in a global array and as read-only
  `text`) and for an empty path, -22 for a nanosecond of
  1000000000 and for flags 1, and traps 3 (child exit 103) for a slice past the
  array, an embedded zero and a 4096-byte path.
- `x86-fixture`: `x86-target.om+utimens.om` through binfmt qemu-x86_64:
  emulator evidence, not hardware qualification.
- refusals: `fnmode.om` (9, AArch64 and x86linux), `contract.om` (30),
  `longflags.om` and `intsec.om` (7), `efi-target.om+use.om` (25).
- mutants:

| mutant | change | fixture exit |
|---|---|---|
| a64-sysno | syscall 88 to 87 (timerfd_gettime) | 2 |
| a64-order | atime and mtime timespecs swapped | 2 |
| a64-flags | flags dropped (x3 = 0) | 5 |
| x86-sysno | syscall 280 to 281 (epoll_pwait) | 2 |
| x86-order | atime and mtime timespecs swapped | 2 |
| x86-flags | flags dropped (R10 = 0) | 5 |
