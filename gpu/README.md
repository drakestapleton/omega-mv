# gpu: the GPU layer of Sovereign Intelligence (SI)

Drake named the combined stack Sovereign Intelligence (SI); Omega is its language and compiler. This
directory, "Omega GPU", holds SI's GPU back ends: code generators and object writers, driver-interface
data layers, launchers and the gates that check them. Everything here is seeded Omega (`.om`) built by
this repository's own compiler, `seed/out/omc`, plus the data tables those units read.

The GPU layer is moving here from CUDApp one piece at a time (aien-architecture-mv ADR 0047, accepted by
Drake on 2026-11-14). Only Omega moves in (Drake, 2026-11-14: "make sure it's pure omega when it's in
there"): a C, Python, shell or other file is rewritten in Omega first, or it stays in CUDApp and is listed
as not yet Omega. Only the AMD back end has moved so far; NVIDIA and the rest are not here yet.

## Layout

| Path | Contents |
| --- | --- |
| `gpu/<vendor>/` | Source: one directory per target or interface (`gpu/amd/gfx942/`, `gpu/amd/kfd/`). |
| `gpu/<vendor>/gate.om` | The back end's gate, in Omega. |
| `gpu/<vendor>/card.tsv` | The bytes the receipts record, written once from the receipts it names: what ran on hardware, and host-built references marked as such. |
| `gpu/<vendor>/import/` | How the back end came here: the filter-repo command and its commit map. |
| `gpu/targets.om` | The shared target table and code-object loader checks. |

A moved back end keeps the history of its Omega files: `git log --follow gpu/amd/gfx942/hsaco.om` shows
its CUDApp commits. To find the new commit for a CUDApp commit, look it up in
`gpu/<vendor>/import/commit-map`. Receipts stay in CUDApp where they were written.

## One compiler

Every unit here is built by `seed/out/omc`, and every gate refuses any other compiler before it builds
anything. The digest is read from `seed/out/omc.sha256`. No back end carries a compiler pin of its own.

## Gates

`tests/gates/run.sh gpu-amd` (manifest `tests/gates/omega-gpu-amd.gate`) builds and runs
`gpu/amd/gate.om`. See `gpu/amd/README.md`. Host results are never hardware qualification. A hardware
result applies to a later revision only for the bytes that are still identical, and `card.tsv` says
which bytes those are.
