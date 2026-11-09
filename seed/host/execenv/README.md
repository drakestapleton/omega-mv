# execenv (keyword 233)

`r = execenv A off n B off m` is `execprog A off n` with a private environment.

- **A, the argv packet.** It follows execprog's rules: a u16 count, then u16-length records, and the first record (the program path) must be nonempty.
- **B, the environment packet.** It is packed the same way, with these limits:
  - the count is 1..64;
  - every record is nonempty;
  - the packet is 2..4096 bytes;
  - it has no embedded zero byte and no trailing bytes.
- **Order of operations.** Both packets are checked (trap 3) before the descriptors above 2 are closed (`close_range(3, ~0, CLOSE_RANGE_UNSHARE)`). Then `execve(path, argv, envp)` runs.
- **Return value.** Like execprog, it returns only on failure, with a negative errno.
- **Refusals.** It is refused in function mode (error 9) and inside contracts (error 30).
- **Targets.** AArch64 Linux and x86linux.

## Gate files

`execenv.cases` is run by the OM-2 conductor (`seed/qualification/om2/gate.om`) from `seed/host/check.sh`. All gate logic is in `.om` files:

- **`execenv.om`, the fixture.**
  - In parent mode it runs 15 checks.
  - It re-executes itself in child mode with three entries: `AIEN_COCKPIT_TOKEN`, `AIEN_COCKPIT_ADDR` and `HIVE_DB_PATH`.
  - The child checks that its environment is exactly those entries.
  - The negative control: under plain `execprog`, the child sees no variables.
  - It also checks malformed packets, the 64-entry and 4096-byte limits, an empty non-first record, an empty program path and ENOENT.
  - The parent exits with the number of the first failed check.
- **`x86-target.om`.** A `target x86linux` header that is prepended to `execenv.om`. Those runs go through binfmt `qemu-x86_64`: this is emulator evidence, not hardware qualification. The binfmt registration is a host prerequisite.
- **`oracle.om`.** It execs `/usr/bin/printenv` with the same three entries, and the output must equal `printenv.want`. Given an argument, it uses `execprog` instead, and the output must be empty.
- **`fnmode.om`, `contract.om`.** The refusal cases.
- **`mutants/*.from|.to`.** Four `omc.om` mutants. Each one is built by the conductor and must make the fixture fail at the named check:
  - AArch64 envp replaced by an empty list;
  - AArch64 nonempty-record rule removed;
  - x86 envp replaced by an empty list;
  - x86 rule weakened so that only the first record must be nonempty.

## ORACLE

`/usr/bin/printenv` (GNU coreutils 9.4 on the qualifying host) is an **ORACLE**. It is an independent host binary that differs from the fixture by construction. It is used only to confirm what a child process actually receives. It is never built, linked or shipped.
