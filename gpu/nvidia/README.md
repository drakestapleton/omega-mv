# gpu/nvidia: the NVIDIA units of Omega GPU

Omega GPU is the GPU layer of Sovereign Intelligence (SI), the stack Drake named, with Omega as its language and
compiler. This directory holds its NVIDIA (sm_121, Blackwell, GB10) units. They are seeded Omega built by this
repository's own `seed/out/omc`, and they come from CUDApp one piece at a time (aien-architecture-mv ADR 0047).

| Path | What it is |
| --- | --- |
| `om/encoder/bw_enc_sm121.om` | The sm_121 encoder ng pins: a solved BlackwellIR program to machine code, four 32-bit words per instruction. |
| `om/components/bw_alloc.om` | The BlackwellIR builder and register allocator (native migration of `omega_bw_ir_append` and `regalloc_solve`). |
| `om/cubin/cubin_elf.om` | The cubin writer (the body of `omega_cubin_pack`). |
| `native/blackwell/launch.om` | The Blackwell launch unit (VECTOR_1D launch ABI). |
| `native/nvrm/context.om` | The nvrm context unit (NVIDIA driver client, ABI 580.173.02). |
| `import/` | How these came from CUDApp: the filter-repo command and its commit map. |

The table lists the five units step 2 brought. Step 3 brought the rest of CUDApp's `om/` tree to `gpu/nvidia/om/`;
`gpu/UNITS.md` describes it and its gate.

## Where they came from

These are the five files `seed/ng/cudapp.lock` pins. They came at CUDApp `1988c50e93c4dd971bcb94e69692c8e57e53f54b`,
with the history of those paths (27 CUDApp commits, `import/filter-repo-command.txt`). Old paths: `om/` became
`gpu/nvidia/om/`, `native/` became `gpu/nvidia/native/`. Two were later replaced by their bytes at CUDApp main
`84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`: `om/encoder/bw_enc_sm121.om` and `om/cubin/cubin_elf.om` (the lock says
so in a comment; `launch.om` is still at its `1988c50e` bytes). Each file's sha256 equals its row in
`seed/ng/cudapp.lock`.

This repository also has another, different copy of the encoder at the top level: `om/encoder/bw_enc_sm121.om`
(sha256 b69455c2...). The `Makefile`, `mk/om-encoder.mk` and `mk/omega-gpu-engine.mk` reference that copy, and this
step does not touch it. The encoder Omega NG pins and its gate checks is
`gpu/nvidia/om/encoder/bw_enc_sm121.om` (its row in `seed/ng/cudapp.lock`). Edit the copy whose consumers you mean to change.

## The gate

`seed/ng/gpu/gate.cases`, run by `seed/qualification/om2/gate.om` (see `seed/ng/gpu/README.md`), checks these
bytes: the `lock-*` cases hash each file against its lock row, `enc-pin` pins the encoder's compiled bytes, and the
fixture, refusal and mutant cases check the encoder's output. The move changed only the paths the cases read
(`../CUDApp/` became `gpu/nvidia/`). Replacing the encoder and `cubin_elf.om` with their `84b524ca` bytes changed
only the pins: the two `lock-*` rows, `lock-self` (the lock file changed) and `enc-pin`. Every golden file,
expected exit and mutant is unchanged and passes with the new encoder. `seed/ng/cudapp.lock` rows still name the
CUDApp paths.

## Not here yet

- Newer versions in CUDApp. The encoder and `cubin_elf.om` are at CUDApp main `84b524ca`, because the check
  `gpu/nvidia/checks/bwctl.om` compares the encoder with the C encoder of that commit (the guard predicate on every
  op, ops 65 to 79, the DRA-483 refusal of a P0 guard on LDCU). `launch.om` has one later commit in CUDApp
  (`3b4f5807`, batched launches with one submit, 2026-11-09). Moving it is a follow-up with its own qualification:
  a change to its bytes changes its `lock-*` digest in `seed/ng/gpu/gate.cases`.
- Retiring `seed/ng/cudapp.lock`. Under ADR 0047 Decision 5 it is deleted with its last row. Here it stays as the
  identity table of the five files, because removing it changes the gate (`lock-self` and the `lock-*` rows). That
  change goes with the follow-up above.
- The rest of CUDApp's NVIDIA layer that is Omega came in steps 3 (`om/`) and 4 (`native/`): see `gpu/UNITS.md`.
  The driver client in C (`nvrm/`, `m16/`) and the C runtime stay in CUDApp until they are rewritten in Omega.
