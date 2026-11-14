# bridge/nvml: the NVML library files of CUDApp `compat/`, as derived files

One slice of CUDApp `compat/` (CUDApp commit `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`): its
`compat/nvml/` directory. The three files there that are C or linker script, `libnvidia-ml.c`,
`nvml.h` and `libnvidia-ml.map`, are not written by hand. CUDApp makes them with omega-bridge from
the Omega library unit that this tree already holds, `gpu/nvidia/native/nvml/api.om`:

    tools/bridge-seeded lib-c   native/nvml/api.om   > compat/nvml/libnvidia-ml.c
    tools/bridge-seeded lib-h   native/nvml/api.om   > compat/nvml/nvml.h
    tools/bridge-seeded lib-map native/nvml/api.om   > compat/nvml/libnvidia-ml.map

So this tree does not store them. `derived.tsv` lists each one with its mode, its source and the
SHA-256 of the source, of the generator and of the output, and the gate shows that the generator,
compiled by this tree's `seed/out/omc`, makes those bytes from this tree's source.

## Files

- `derived.tsv`: the table. Its header comment explains the columns and names the two generators
  by omega-bridge commit.
- `gate.om`: the gate, seeded Omega, built with `seed/ng/sha256.om` in front of it. Usage:
  `gate SCRATCH OMC TABLE [toc=TOC]... [cudapp=CUDAPP]...`. It prints one line per check and a
  summary `BRIDGE-NVML PASS|FAIL checks=N failed=F emitter=… oracle=…`; exit 0 PASS, 1 FAIL,
  2 usage or setup.

## Running it

    tests/gates/run.sh bridge-nvml

The step checks `seed/out/omc` against `seed/out/omc.sha256`, builds the gate and runs it. Tiers:

- Default: the table is well formed, every source has its pinned digest, and every source compiles
  with `seed/out/omc`. Emitter and oracle are `NOT_RUN`.
- Emitter, with `BRIDGE_NVML_TOC` set to one or more omega-bridge `src/toc.om` paths separated by
  `:`. For each, the gate refuses a file whose SHA-256 is not a generator in the table, compiles it
  with `seed/out/omc`, sends it every row of its generator (the request is the mode letter, the
  source, and a line with the generator's and the source's digests, with `toc.om` on descriptor 3)
  and requires the output to have the pinned digest.
- Oracle, with `BRIDGE_NVML_CUDAPP` set to a CUDApp checkout at `84b524ca`: each row that names a
  CUDApp file requires that file to have the pinned output digest.

Controls, run by the step: a table with one source digest changed (always caught); with
`BRIDGE_NVML_TOC`, `api.om` with one error value changed and its digest re-pinned in a copy of the
table, so only the emitted bytes can catch it; and the first `toc.om` with one line added, which
must be refused as not a generator.

## What is not in this tree, and why

- The generator. omega-bridge is its own repository, so its `src/toc.om` is an input to the gate,
  pinned by digest, and not a copy here. CUDApp's bytes come from `src/toc.om` at omega-bridge
  commit `f6b7cc4042bdf55d8f9d866c97439bb7e53506f5` ("cabi-1: C ABI library emitter"), which is
  on omega-bridge `main`: it is an ancestor of `0138839cc3e7aef1c77230505f757372b8ae6ad5`. The
  `src/toc.om` of `0138839c` makes the same three files except for line 1, where the emitter
  writes its own digest; the table pins both. In any clone of omega-bridge `main`, both
  generators come out of history:

      git -C OMEGA_BRIDGE show f6b7cc4042bdf55d8f9d866c97439bb7e53506f5:src/toc.om > toc-cabi1.om
      git -C OMEGA_BRIDGE show 0138839cc3e7aef1c77230505f757372b8ae6ad5:src/toc.om > toc-main.om
      BRIDGE_NVML_TOC="$PWD/toc-cabi1.om:$PWD/toc-main.om" tests/gates/run.sh bridge-nvml

- A launcher in Omega. The emitter reads `toc.om` from descriptor 3, and this compiler's exec
  words close every descriptor from 3 up, so the gate starts the emitter through
  `/bin/sh -c 'exec "$0" 3<"$1"'`. An exec word that keeps a chosen descriptor open would remove
  the shell.
- The library. Turning `libnvidia-ml.c` into `libnvidia-ml.so.1` needs a C compiler; omc does not
  yet write a shared object. `bridge/cuda/EXTENSION-PROPOSAL.md` describes the compiler change.
- Hardware. Nothing here opens a device; loading the library and calling it on a GPU is not run.
