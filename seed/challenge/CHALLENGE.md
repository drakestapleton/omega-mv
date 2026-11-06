# The seed-chain bootstrap challenge

Rebuild the Omega compiler `omc` from 408 hand-written bytes on your own AArch64 Linux machine, and check
that every rung of the chain comes out byte for byte the same as the published values.

```
seed0.hex --load0.sh (POSIX printf)--> seed0 (408 B) --> hex1 (776 B) --> asm2 (2,464 B)
          --> om4 (14,224 B) --> omc stage1 --> omc stage2 --> omc stage3 (625,676 B)
```

No C compiler, assembler or linker writes a byte of this chain. The one outside step is `load0.sh`, a
POSIX shell script whose `printf` turns the hex words of `seed0.hex` into the first 408 bytes. Each later
rung is a program written by the rung before it.

## Run it

Needs AArch64 Linux (a Raspberry Pi 4/5 on a 64-bit OS, an Ampere or Graviton box, Apple silicon running
an arm64 Linux VM, a DGX Spark) with `git`, `sh`, `awk`, `sed`, `tar` and coreutils. No root, no
network after the clone, no compiler.

```sh
git clone https://github.com/aien-dev/omega-mv
cd omega-mv
sh seed/challenge/run.sh
```

It prints one line per input file and per rung, and ends with `CHALLENGE PASS` (exit 0) or
`CHALLENGE FAIL` (exit 1). On another architecture it prints `CHALLENGE NOT_RUN` and exits 3: the seed
programs are AArch64 Linux ELF files and are never emulated or translated by this script. The full log,
with every hash, is `build/seed/challenge/challenge.log`.

The script builds in `build/seed/challenge/` from `git archive <pin>`: it never runs
`seed/omega-from-seed.sh` and never rewrites a tracked file.

Use a full clone. In a `git clone --depth 1` the pinned commit is missing, and the script stops with
`CHALLENGE NOT_RUN: pin … is not in this clone` (exit 3). Running
`git fetch --depth 1 origin <pin>` (the `pin` line of the table) first makes a shallow clone work.

## The published values

The challenge is versioned. Each version is a table naming a pin and the sha256 and size of each input
and each rung. Every value was read from the file committed at the pin (`git show <pin>:<path> |
sha256sum`) before anything was rebuilt, so a table does not come from the build it checks. A new version
adds a table; an old one is never rewritten, so a result reproduced against it stays checkable.

| Version | Table | Pin | Why |
|---|---|---|---|
| v2 (default) | `seed/challenge/expected.txt` | `c945f974674cd5ba0276759d161888bc6735fd56` | om4's function table grows from 512 to 4096 entries (omega#1013) |
| v1 | `seed/challenge/expected-v1.txt` | `369dbc96daa1684db2d7c2c7085bbf16b3fd77ee` | first published table |

`sh seed/challenge/run.sh` checks v2; `sh seed/challenge/run.sh --expect seed/challenge/expected-v1.txt`
checks v1. Until omega#1013 the v1 table was `expected.txt`.

v2:

| Rung | Written by | Bytes | sha256 |
|---|---|---:|---|
| seed0 | `load0.sh` from `seed0.hex` | 408 | `aca00cf3677236809f0f223437398c6bb429e4c65f13d58762bcf96d13799474` |
| hex1 | seed0 from `hex1.hex` | 776 | `920e1756aec399c7c74f5cedd1676abb91b844ea75448e14aa50dcb0bbc7ba5d` |
| asm2 | hex1 from `asm2.hex1` | 2,464 | `6988abe072fac3cdef2240d5ad13a3ecd8fb576fa09112d344b9e7c2315969c4` |
| om4 | asm2 from `table.s2 table3.s2 table4.s2 om4.s` | 14,224 | `bfc1cfd197348c398be19425b21704ad5ea79d28e33c0e1eff676142f47812b7` |
| omc (stages 1, 2 and 3) | om4, then omc itself, from `seed/omc/omc.om` | 625,676 | `3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194` |

v1 differs in om4 (`d0da40e45f1fcc45d9a39c9c52c9d745b545e076970729e51c12d76ef519efab`, 14,224 B) and omc
(`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`, 325,524 B); seed0, hex1 and asm2 are
the same.

Besides the hashes, the script checks that seed0 and hex1 rebuild themselves, that the `p_filesz` field
of `om4.s` already holds the size of the image it describes, and that stage3 compiles
`seed/rung4/tests/r5b_fwd.om` into a program that exits 7.

## Watch it pass, post your result

- A GitHub-hosted `ubuntu-24.04-arm` runner does the same thing in public, with three negative controls (a
  tampered rung, a wrong published value and a forged log must all fail):
  <https://github.com/aien-dev/omega-seed-challenge/actions>.
- Post your own run with the "I reproduced it" issue form, or a pull request adding your
  `challenge.log`, at <https://github.com/aien-dev/omega-seed-challenge>. A check compares the hashes in
  a submitted log with this table.

## What a pass shows, and what it does not

- It shows that your machine, starting from 408 bytes that you can read word by word
  (`seed/rung0/seed0.audit`), produced the same compiler binary that is committed in the repository, and
  that the compiler reproduces itself (stage1 = stage2 = stage3).
- A fixed-output match is not general self-hosting, and it is not diverse double compilation: every rung
  is built by the rung before it, so there is only one path. It does not show that `omc` compiles every
  program correctly.
- The pin is fixed. Later commits change `seed/omc/omc.om`, so the omc hash of `main` moves; a new pin
  needs a new table, read from the committed files the same way.
