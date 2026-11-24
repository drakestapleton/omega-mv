# Phase 3: `omega-mv` Monorepo Boundary & Spin-Out Plan

Grounded in `omega-mv` (2026-11-23). Keeps `omega-mv` focused on the core seeded compiler (`seed/`) and pure OM-2 GPU/runtime stack (`om/gpu/`, `gpu/`) while charting non-destructive spin-outs for standalone apps and retired C legacy.

## Current Footprint

| Tree | Disk Size | Role | Target Boundary |
|---|---:|---|---|
| `seed/` | `105 MB` | Seeded `omc` bootstrap ladder (`seed0 → omc`), host checks, pure-OM-2 build coordinators | **Stay in `omega-mv` core** |
| `om/gpu/` | `2.4 MB` | Pure seeded OM-2 Blackwell/SM121 engines (`q36/`, `dsv41/`, `inkling2/`, `spec/`), `slab_plan.om`, `spark_ring.om` | **Stay in `omega-mv` core** |
| `apps/` | `7.5 MB` | 13 standalone applications (`apps/lean-opt`, `apps/aienos-site`, `apps/interplane-site`, `apps/omtex`, `apps/translate`, etc.) | **Spin out** to dedicated repos once each app's `omc` pin is self-contained |
| `src/` | `18 MB` | Legacy C compiler (`src/compiler/`), reaction runtime, Physics Zero, Turing/EXP-001 frozen pins | **Retire in-place** per `docs/migration/C-TO-OM-INVENTORY.md` as frozen receipt pins roll forward |

## Spin-Out Rules (Zero Gate Breakage)
1. **Never break Spark judge manifests** (`tests/gates/*.gate`, `.aien/always`) or `evidence/` immutability.
2. **Pin `omc` by SHA-256** in any spun-out app repository (matching `seed/out/omc.sha256`) so standalone apps build identically outside `omega-mv`.
3. **Separate Model Plan IR from SM121 Codegen:** New model families add a `config.json` + Plan IR entry (`om/gpu/slab_plan.om`) instead of cloning `om/gpu/q36/`.
4. **Multi-Spark Scaling:** `om/gpu/spark_ring.om` (`OMSR01` framed slab-exchange transport) owns inter-node PP/TP slab exchange cleanly outside single-chip kernel emitters.
