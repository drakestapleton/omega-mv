# gpu/nvidia: the NVIDIA units of Omega GPU

Omega GPU is the GPU layer of Sovereign Intelligence (SI), the stack Drake named, with Omega as its language and
compiler. This directory holds its NVIDIA (sm_121, Blackwell, GB10) units. They are seeded Omega built by this
repository's own `seed/out/omc`, and they come from CUDApp one piece at a time (aien-architecture-mv ADR 0047).

| Path | What it is |
| --- | --- |
| `om/encoder/bw_enc_sm121.om` | The sm_121 encoder: a solved BlackwellIR program to machine code, four 32-bit words per instruction. |
| `om/components/bw_alloc.om` | The BlackwellIR builder and register allocator (native migration of `omega_bw_ir_append` and `regalloc_solve`). |
| `om/cubin/cubin_elf.om` | The cubin writer (the body of `omega_cubin_pack`). |
| `native/blackwell/launch.om` | The Blackwell launch unit (VECTOR_1D launch ABI). |
| `native/nvrm/context.om` | The nvrm context unit (NVIDIA driver client, ABI 580.173.02). |
| `import/` | How these came from CUDApp: the filter-repo command and its commit map. |

## Where they came from

These are exactly the five files `seed/ng/cudapp.lock` pins, at CUDApp `1988c50e93c4dd971bcb94e69692c8e57e53f54b`,
with the history of those paths (27 CUDApp commits, `import/filter-repo-command.txt`). Old paths: `om/` became
`gpu/nvidia/om/`, `native/` became `gpu/nvidia/native/`. Each file's sha256 equals its row in `seed/ng/cudapp.lock`.

## The gate

`seed/ng/gpu/gate.cases`, run by `seed/qualification/om2/gate.om` (see `seed/ng/gpu/README.md`), checks these
bytes: the `lock-*` cases hash each file against its lock row, `enc-pin` pins the encoder's compiled bytes, and the
fixture, refusal and mutant cases check the encoder's output. The move changed only the paths the cases read
(`../CUDApp/` became `gpu/nvidia/`). Every digest, golden file, expected exit and mutant is unchanged, so no
re-qualification was needed. `seed/ng/cudapp.lock` keeps its bytes because `lock-self` pins them; its rows still
name the CUDApp paths.

## Not here yet

- Newer versions in CUDApp. CUDApp main (`f85309f4`) has later work on three of these files: the encoder (8
  commits, including the DRA-483 predicate guards and freestanding builders, 2026-11-07 to 2026-11-10),
  `cubin_elf.om` (`a86d199f`, 2026-11-05) and `launch.om` (`3b4f5807`, batched launches with one submit,
  2026-11-09). Moving them is a follow-up step with its own qualification: a change to any of these bytes changes
  the `lock-*` and `enc-pin` digests of `seed/ng/gpu/gate.cases`.
- Retiring `seed/ng/cudapp.lock`. Under ADR 0047 Decision 5 it is deleted with its last row. Here it stays as the
  identity table of the five files, because removing it changes the gate (`lock-self` and the `lock-*` rows). That
  change goes with the follow-up above.
- Everything else of CUDApp's NVIDIA layer (the rest of `om/`, `nvrm/`, `m16/`, `native/`, the C runtime) moves in
  later steps, as Omega only.
