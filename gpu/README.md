# gpu: the GPU layer of Sovereign Intelligence (SI)

Drake named the combined stack Sovereign Intelligence (SI); Omega is its language and compiler. This
directory, "Omega GPU", holds SI's GPU back ends: code generators and object writers, driver-interface
data layers, launchers and the gates that check them. Everything here is seeded Omega (`.om`) built by
this repository's own compiler, `seed/out/omc`, plus the data tables those units read.

The GPU layer is moving here from CUDApp one piece at a time (aien-architecture-mv ADR 0047, accepted by
Drake on 2026-11-14). Only Omega moves in (Drake, 2026-11-14: "make sure it's pure omega when it's in
there"): a C, Python, shell or other file is rewritten in Omega first, or it stays in CUDApp and is listed
as not yet Omega. The AMD (`gpu/amd/`), NVIDIA (`gpu/nvidia/`), SPIR-V (`gpu/spirv/`), hardware-manifest
(`gpu/hw/`), runtime-slice (`gpu/runtime/`), and extra pure-Omega driver/adapter/compute units are now here;
see [`gpu/UNITS.md`](UNITS.md) and [`gpu/nvidia/README.md`](nvidia/README.md) for what remains in CUDApp.

## Layout

| Path | Contents |
| --- | --- |
| `gpu/<vendor>/` | Source: one directory per target or interface (`gpu/amd/gfx942/`, `gpu/amd/kfd/`). |
| `gpu/<vendor>/gate.om` | The back end's gate, in Omega. |
| `gpu/<vendor>/card.tsv` | The bytes the receipts record, written once from the receipts it names: what ran on hardware, and host-built references marked as such. |
| `gpu/<vendor>/import/` | How the back end came here: the filter-repo command and its commit map. |
| `gpu/targets.om` | The shared target table and code-object loader checks. |
| `gpu/driver/` | Pure-Omega GB10 VFIO/GSP GPU driver moved from `omega-gpu-driver` (`81b579e4c371`, 88 `.om` files; import record `gpu/import/omega-gpu-driver/`). |
| `gpu/cuda-crack/` | Pure-Omega sm_121 ISA table generator and reencoder moved from `cuda-crack` (`8efa1bb3f4cf`, 3 `.om` files; import record `gpu/import/cuda-crack/`). |
| `gpu/adapters/` | Pure-Omega hardware accelerator adapter and provider router (converted from `spark-adapters`, `da269adf5ff1`, 3 `.om` files). |
| `gpu/head-to-head/` | Pure-Omega paired A/B GPU benchmark comparator and parity verifier (converted from `gpu-head-to-head`, `48e331f2cf5e`, 3 `.om` files). |
| `gpu/forge/` | Pure-Omega FORGE hardware descriptor, envelope, provider and realization engine (converted from `physics-mv`, `29039514eaf8`, 6 `.om` files). |
| `gpu/extra-units.tsv`, `gpu/extra-units-gate.om` | Compile-reproducibility gate (`OMEGA-GPU-EXTRA-UNITS`, 22 units) for `gpu/driver/`, `gpu/cuda-crack/`, `gpu/adapters/`, `gpu/head-to-head/`, `gpu/forge/`, `gpu/algebra/`, `gpu/checker2/`, `gpu/rx/`, `gpu/physics0/`, and `gpu/turing/`, kept separate so `gpu/units.tsv` (405 units, `OMEGA-GPU-UNITS`) stays unchanged. |

A moved back end keeps the history of its Omega files: `git log --follow gpu/amd/gfx942/hsaco.om` shows
its CUDApp commits. To find the new commit for a CUDApp commit, look it up in
`gpu/<vendor>/import/commit-map`. Receipts stay in CUDApp where they were written.

## One compiler

Every unit here is built by `seed/out/omc`, and every gate refuses any other compiler before it builds
anything. The digest is read from `seed/out/omc.sha256`. No back end carries a compiler pin of its own.

## Gates

- `tests/gates/run.sh gpu-amd` (manifest `tests/gates/omega-gpu-amd.gate`) builds and runs `gpu/amd/gate.om`. See `gpu/amd/README.md`.
- `tests/gates/run.sh gpu-units` (`OMEGA-GPU-UNITS`) builds and runs `gpu/units-gate.om` over the 405 units in `gpu/units.tsv`. See `gpu/UNITS.md`.
- `gpu/extra-units-gate.om` (`OMEGA-GPU-EXTRA-UNITS`) checks the 22 units in `gpu/extra-units.tsv`.
- `tests/gates/run.sh gpu-driver`, `gpu-runtime`, `gpu-checks`, and `gpu-amd-rest` run the corresponding Omega gates under `gpu/nvidia/driver/`, `gpu/runtime/`, `gpu/nvidia/checks/`, and `gpu/amd/rest/`.
- `OMC=seed/out/omc sh gpu/spirv/check.sh` runs `spirv-val`, mutant and host-conform checks over `gpu/spirv/` (also run by `./uxl-run.sh`).

Host results are never hardware qualification. A hardware result applies to a later revision only for the bytes that are still identical, and `card.tsv` says which bytes those are.
