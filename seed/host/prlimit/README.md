# prlimit (keyword 235)

`prlimit pid res A off n` returns `long`: 0 or a negative errno from Linux
`prlimit64` (AArch64 syscall 261, x86-64 syscall 302).

| operand | type | meaning |
|---|---|---|
| `pid` | int | target process; 0 is the caller |
| `res` | int | `RLIMIT_*` number (7 NOFILE, 9 AS, ...) |
| `A` | writable byte array | limit buffer; a `text` is error 20 |
| `off`, `n` | ulong | slice `A[off..off+n)`, checked first (trap 3) |

- `n` 16 reads: new = NULL, the old `{rlim_cur, rlim_max}` lands in
  `A[off..off+16)` as two little-endian u64.
- `n` 32 sets: the new pair is read from `A[off..off+16)`, the old pair is
  written to `A[off+16..off+32)`.
- any other `n`: -22 with no kernel call.

Program mode only: function mode is error 9, a contract clause error 30,
`target x86efi` error 25. Limits are inherited by `fork` and kept across
`execprog`.

## Gate

`prlimit.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=14`.

- `fixture`: `prlimit.om` on AArch64, all 15 checks against `/proc/self/limits`
  (read, set soft NOFILE 40, EMFILE at fd 40, restore, -22 for bad `n` and
  resource, -3 ESRCH, -1 EPERM on pid 1 unless root, RLIMIT_AS read, trap 3 on
  both slice shapes, RLIMIT_AS 1 GiB seen after `execprog`, a 128 MiB image
  killed under a 64 MiB cap, the same image running uncapped).
- `x86-fixture`: `x86-target.om+prlimit.om` with argument `noas` (checks 1-12;
  qemu-user ignores RLIMIT_AS writes). It runs through binfmt qemu-x86_64:
  emulator evidence, not hardware qualification.
- refusals: `fnmode.om` (9), `contract.om` (30), `textarr.om` (20),
  `longpid.om` (7), `efi-target.om+read16.om` (25), x86 `fnmode.om` (9).
- mutants: each `mutants/NAME.from` occurs once in `seed/omc/omc.om` and is
  replaced by `NAME.to`; the fixture built by that compiler must fail at the
  named check (exit = check number).

| mutant | change | fixture exit |
|---|---|---|
| a64-sysno | `hsys 261` to 163 (getrlimit) | 1 |
| a64-swap | n 32 passes new = A+16, old = A | 3 |
| a64-nguard | the n == 32 test always taken | 7 |
| x86-sysno | `xhcall 302` to 97 (getrlimit) | 1 |
| x86-swap | n 32 passes rdx = A+16 | 3 |
| x86-nguard | the n == 32 test always taken | 7 |
