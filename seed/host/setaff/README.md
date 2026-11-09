# setaff (keyword 237)

`setaff pid A off n` returns `long`: 0 or a negative errno from Linux
`sched_setaffinity` (AArch64 syscall 122, x86-64 syscall 203).

| operand | type | meaning |
|---|---|---|
| `pid` | int | target thread; 0 is the caller |
| `A` | byte array | CPU mask, bit c of byte c/8 is CPU c; a read-only view or `text` is accepted |
| `off`, `n` | ulong | mask `A[off..off+n)`; the slice is checked first (trap 3), then `n` must be 1..1024 (trap 3) |

An empty mask (or one naming no allowed CPU) returns -22; another user's
process -1; a missing process -3. Program mode only: function mode is error 9,
a contract clause error 30, `target x86efi` error 25. Affinity is inherited by
`fork` and kept across exec.

## Gate

`setaff.cases`, run by the OM-2 conductor from `seed/host/check.sh`:
`OM2GATE PASS cases=14`.

- `fixture`: `setaff.om` on AArch64. Kernel truth is the `Cpus_allowed_list`
  line of `/proc/<child>/status`, read while the child is an unreaped zombie:
  the inherited first CPU k, a one-CPU mask {k} giving exactly "k" (n 128, n
  1024, and at the unaligned offset 7), the same through a read-only view, an
  all-zero mask -22 with the list unchanged, n 0, n 1025 and an out-of-array
  slice trapping 3, pid 1 -1 unless euid 0, pid 2147483647 -3. A never-executed
  `text` use proves read-only slices compile.
- `x86-fixture`: `x86-target.om+setaff.om` through binfmt qemu-x86_64:
  emulator evidence, not hardware qualification.
- refusals: `fnmode.om` (9, AArch64 and x86linux), `contract.om` (30),
  `longpid.om` and `intn.om` (7), `efi-target.om+use.om` (25).
- mutants:

| mutant | change | fixture exit |
|---|---|---|
| a64-sysno | syscall 122 to 123 (sched_getaffinity) | 2 |
| a64-zguard | n 0 reaches the kernel | 4 |
| a64-nguard | n above 1024 reaches the kernel | 5 |
| x86-sysno | syscall 203 to 204 (sched_getaffinity) | 2 |
| x86-zguard | n 0 reaches the kernel | 4 |
| x86-nguard | n above 1024 reaches the kernel | 5 |
