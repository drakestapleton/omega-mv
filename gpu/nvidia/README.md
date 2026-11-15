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

These are exactly the five files `seed/ng/cudapp.lock` pins. Step 2 brought them at CUDApp
`1988c50e93c4dd971bcb94e69692c8e57e53f54b`, with the history of those paths (27 CUDApp commits,
`import/filter-repo-command.txt`). Old paths: `om/` became `gpu/nvidia/om/`, `native/` became `gpu/nvidia/native/`.
On 2026-11-14 `bw_enc_sm121.om` and `cubin_elf.om`, and then in its own commit `launch.om`, were replaced by the
bytes of CUDApp main `84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`; each commit names the CUDApp commits between, and
that later history was not imported. `bw_alloc.om` and `context.om` are the same at both commits, so all five files
are now 84b524ca's, the commit `seed/ng/cudapp.lock` names. Each file's sha256 equals its row there.

This repository also has another copy of the encoder at the top level: `om/encoder/bw_enc_sm121.om`.
The `Makefile`, `mk/om-encoder.mk` and `mk/omega-gpu-engine.mk` link that copy. The encoder Omega NG pins,
and `seed/ng/cudapp.lock` hashes, is `gpu/nvidia/om/encoder/bw_enc_sm121.om`. They are not one source:
the pinned file encodes ops 64..79 and a few payloads this import's consumers do not, and the linked
file is the one that has to stay on the C oracle's unpredicated words. Both write the same 4-bit guard.
`om/encoder/guard-gate.sh` checks that, prints both sha256 values, and names the rows whose other bits
differ. Edit the copy whose consumers you mean to change.

## The gate

`seed/ng/gpu/gate.cases`, run by `seed/qualification/om2/gate.om` (see `seed/ng/gpu/README.md`), checks these
bytes: the `lock-*` cases hash each file against its lock row, `enc-pin` pins the encoder's compiled bytes, and the
fixture, refusal and mutant cases check the encoder's output. The move changed only the paths the cases read
(`../CUDApp/` became `gpu/nvidia/`). The 2026-11-14 replacements changed the `lock-self`, `lock-bw_enc_sm121`,
`lock-cubin_elf`, `lock-launch` and `enc-pin` digests and nothing else: every golden file, expected exit and mutant is
unchanged, and all 18 cases pass with the new bytes. `enc-pin` is what this repository's `seed/out/omc` emits for the
new encoder, an identity pin; the behaviour evidence is the fixture, refusal and mutant cases. The gate checks no
behaviour of `launch.om`, only its identity. The rows of `seed/ng/cudapp.lock` still name the CUDApp paths.

## Not here yet

- A behaviour check of `launch.om` here. CUDApp's is `tests/host-trace/run-host-trace.sh`: Omega checks with a fake
  device (`tests/host-trace/*.om`) composed by shell, including the batch path `native/blackwell/batch.om` and a
  mutant of `launch.om`. It has not moved. `launch.om` has not been run on the GPU from this repository.
- Retiring `seed/ng/cudapp.lock`. Under ADR 0047 Decision 5 it is deleted with its last row. Here it stays as the
  identity table of the five files, because removing it changes the gate (`lock-self` and the `lock-*` rows). That
  is its own change.
- The rest of CUDApp's NVIDIA layer that is Omega came in steps 3 (`om/`) and 4 (`native/`): see `gpu/UNITS.md`.
  The driver client in C (`nvrm/`, `m16/`) and the C runtime stay in CUDApp until they are rewritten in Omega.
