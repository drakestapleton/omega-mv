# execenv (keyword 233)

`r = execenv A off n B off m` is `execprog A off n` with a private environment.

- **A, the argv packet.** It follows execprog's rules (a u16 count, then u16-length records, the first record, the program path, nonempty), with execenv's limits below.
- **B, the environment packet.** It is packed the same way, with these limits:
  - the count is 1..32768;
  - every record is nonempty;
  - the packet is 2..2097152 bytes (2 MiB);
  - it has no embedded zero byte and no trailing bytes.
- **Limits.** Both execenv packets hold 1..32768 records and at most 2097152 bytes (a real caller environment of 76 entries exceeds the 64-record limit of execprog, and a measurement tool handed 1100 command words exceeded the earlier 1024-record limit). The decoder frame is 0x482000 bytes of the program's 8 MiB stack pool (argv strings at SP, argv pointers at SP+0x200000, env strings at SP+0x241000, env pointers at SP+0x441000). `execprog` and `execpure` keep 64 records and 4096 bytes, with unchanged machine code. A single record is at most 65535 bytes (u16 length). The kernel's own limits (`MAX_ARG_STRLEN` 131072 per string, the total under `RLIMIT_STACK`/4) still apply after the checks: under the default 8 MiB `RLIMIT_STACK`, ARG_MAX is 2 MiB for strings and pointers together, so maximal packets return -7 (E2BIG) unless the caller raises the stack limit first (`prlimit 0 3 ...`; at most 6 MiB).
- **Order of operations.** Both packets are checked (trap 3) before the descriptors above 2 are closed (`close_range(3, ~0, CLOSE_RANGE_UNSHARE)`). Then `execve(path, argv, envp)` runs.
- **Return value.** Like execprog, it returns only on failure, with a negative errno.
- **Refusals.** It is refused in function mode (error 9) and inside contracts (error 30).
- **Targets.** AArch64 Linux and x86linux.

## Gate files

`execenv.cases` is run by the OM-2 conductor (`seed/qualification/om2/gate.om`) from `seed/host/check.sh`. All gate logic is in `.om` files:

- **`execenv.om`, the fixture.**
  - In parent mode it runs 18 checks.
  - It re-executes itself in child mode with three entries: `AIEN_COCKPIT_TOKEN`, `AIEN_COCKPIT_ADDR` and `HIVE_DB_PATH`.
  - The child checks that its environment is exactly those entries.
  - The negative control: under plain `execprog`, the child sees no variables.
  - It first raises its soft `RLIMIT_STACK` to 64 MiB (prlimit 235) and reads it back. It also checks malformed packets, 32768 records and a 2097152-byte packet accepted and 32769 records and 2097153 bytes trapped (environment and argv), both packets at the maximum delivered intact (child verifies 32768 entries and 2031614 bytes of each; when the stack limit could not be raised, as under qemu-user, the required outcome is E2BIG, child exit 97), execprog still trapping a 65-record and a 4097-byte argv that execenv runs, an empty non-first record, an empty program path and ENOENT.
  - The parent exits with the number of the first failed check.
- **`x86-target.om`.** A `target x86linux` header that is prepended to `execenv.om`. Those runs go through binfmt `qemu-x86_64`: this is emulator evidence, not hardware qualification. The binfmt registration is a host prerequisite.
- **`oracle.om`.** It execs `/usr/bin/printenv` with the same three entries, and the output must equal `printenv.want`. Given an argument, it uses `execprog` instead, and the output must be empty.
- **`fnmode.om`, `contract.om`.** The refusal cases.
- **`mutants/*.from|.to`.** Eight `omc.om` mutants. Each one is built by the conductor and must make the fixture fail at the named check:
  - AArch64 envp replaced by an empty list (check 1);
  - AArch64 nonempty-record rule removed (check 4);
  - x86 envp replaced by an empty list (check 1);
  - x86 rule weakened so that only the first record must be nonempty (check 13);
  - AArch64 and x86 count limit left at 64 (check 10);
  - AArch64 and x86 byte limit 131071 (check 11).

## ORACLE

`/usr/bin/printenv` (GNU coreutils 9.4 on the qualifying host) is an **ORACLE**. It is an independent host binary that differs from the fixture by construction. It is used only to confirm what a child process actually receives. It is never built, linked or shipped.
