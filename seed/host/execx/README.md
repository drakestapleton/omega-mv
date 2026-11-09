# execx (keyword 240)

`execx A off n B off m K off k` returns `long`: it execs the program named by
the first record of the argv packet with argv taken from the remaining records,
the environment packet B, and every descriptor from 3 closed except those listed
in K. It returns only on failure, with the negative errno.

| operand | type | meaning |
|---|---|---|
| `A`, `off`, `n` | packet | path record, then argv records (at least 2 records: path and argv[0]) |
| `B`, `off`, `m` | packet | environment packet (every record nonempty) |
| `K`, `off`, `k` | uchar slice | descriptors kept open, one byte each, `k` 0..64 |

Packets use the execenv limits: 1..1024 records, at most 131072 bytes each.
The keep list is checked like every host slice (trap 3), then `k` above 64 traps
3, then both packets (trap 3; an argv packet of a single record traps 3) — all
before any descriptor closes. Descriptors 0..2 are never touched; K bytes below
3 are ignored, duplicates and any order are allowed. The closes are
`close_range(lo, d-1, CLOSE_RANGE_UNSHARE)` over each gap between kept
descriptors (skipped when empty) and `close_range(lo, ~0U, CLOSE_RANGE_UNSHARE)`
after the last; a failure returns its negative errno with no fallback. An empty
K is exactly `execenv`. Kept descriptors must not carry `FD_CLOEXEC`. Then
`execve(path, argv, envp)` with `argv[0]` the second record, so the path and
`argv[0]` can differ (a login shell's `-sh`, a multi-call binary's name).
Program mode only: function mode is error 9, a contract clause error 30,
`target x86efi` error 25. AArch64 and x86linux.

## Gate

`execx.cases`, run by the OM-2 conductor from `seed/host/check.sh`.

- `fixture`: `execx.om` on AArch64. A forked child puts `/dev/null` on 0 and
  3..9 and execx's this program as path with `argv[0]` `omega-execx-argv0`.
  The new image proves `argv[0]` is the marker (not the path), 0 is open, each
  of 3..9 is open exactly when kept (`flock d 8`: 0 or -9) and the environment
  is exactly `A=1`, for keep lists [7, 5] (two kept, the rest closed), [] (all
  closed, as execenv), [3] (the first close skipped) and [9, 1, 9]. A missing
  program returns -2 after the closes (4 and 6 closed, 5 kept); a 65-byte keep
  list, an argv packet without `argv[0]` and 1025 environment records trap 3.
- `x86-fixture`: `x86-target.om+execx.om` through binfmt qemu-x86_64: emulator
  evidence, not hardware qualification.
- refusals: `fnmode.om` (9, AArch64 and x86linux), `contract.om` (30),
  `intkeep.om` (7), `efi-target.om+use.om` (25).
- mutants:

| mutant | change | fixture exit |
|---|---|---|
| a64-argv0 | argv starts at the path record | 1 |
| a64-range | each middle close_range ends at the kept descriptor | 1 |
| a64-kcap | no trap for k above 64 | 6 |
| a64-count | no trap for an argv packet without argv[0] | 7 |
| x86-argv0 | argv starts at the path record | 1 |
| x86-range | each middle close_range ends at the kept descriptor | 1 |
| x86-kcap | no trap for k above 64 | 6 |
| x86-count | no trap for an argv packet without argv[0] | 7 |
