# `apps/lean-opt`: Pure Seeded OM-2 Lean 4.36 Static Collision Analyzer & Conflict-Aware Bundler

Static, zero-hard-cap pure seeded OM-2 CLI (`lean-opt`) for analyzing large Lean 4.36 module DAGs (built for `leanprover-community/riemann-hypothesis` and PR #120 bundle diagnostics). Uses dynamic `global ... *` pools (`enlarge`), FNV-1a string interning, Kahn topological sort, `O(V + E)` culprit-instance propagation, per-bundle transitive import closure scanning, and conflict-aware DAG coarsening (`antichain` and single-importer `tree` contraction).

## Files

- `pool.om` — Dynamic zero-hard-cap arenas (`enlarge`), open-addressing string interner, buffered stdout, file reader, Linux `getdents64` directory walker, and library classifier.
- `lexer.om` — Single-pass Lean 4.36 scanner: nested `/- ... -/` block comments, `--` line comments, `"..."` strings, `-- bundled from ` / `-- ===== clump member: ` section splitting, imports, `namespace`/`section`/`end`/`open`/`attribute [-instance]` scope tracking, declaration/instance extraction (ignoring anonymous instances), 8-bit `PR120-PLAYBOOK` culprit registry, `nlinarith`/`maxHeartbeats` counters, and local binder filtering.
- `graph.om` — Forward/reverse CSR DAG builder, Kahn topological sort + cycle check, topological culprit propagation, `stats`, `scan`, `hotspots`, and conflict-aware `plan-clump`.
- `main.om` — CLI entrypoint (`stats`, `scan`, `hotspots`, `plan-clump`).
- `test.om` — Self-contained pure-Omega behavioral suite + 6 negative controls (`SHADOW`, `AMBIG`, `CULPRIT` + `attribute [-instance]`, `nlinarith` lexer accuracy, conflict-aware `plan-clump`, and 5,000-string dynamic pool growth).

## Build & Gate (Linux AArch64, `seed/out/omc`)

From the `omega-mv` repository root:

```sh
{ cat si/directives/om2.om apps/lean-opt/pool.om apps/lean-opt/lexer.om apps/lean-opt/graph.om apps/lean-opt/main.om; } | seed/out/omc > lean-opt
{ cat si/directives/om2.om apps/lean-opt/pool.om apps/lean-opt/lexer.om apps/lean-opt/graph.om apps/lean-opt/test.om; } | seed/out/omc > lean-opt-test
chmod +x lean-opt lean-opt-test
./lean-opt-test
```

Registered in `apps/units.tsv` as `lean_opt_main` (`95,240 B`, static AArch64 ELF, `ldd: not a dynamic executable`) and `lean_opt_test` (`103,500 B`). Verified by `apps/units-gate.om` (`OMEGA-APPS-UNITS PASS units=131 controls=1 caught=1 hardware=NOT_RUN`).

## CLI Usage

```text
lean-opt stats <src_dir>
lean-opt scan <src_dir> [--only-bundles] [--culprits-only] [--summary-only]
lean-opt hotspots <src_dir> [--top N]
lean-opt plan-clump <src_dir> [--max-lines N] [--mode antichain|tree] [--summary-only]
```

## Measured Runs on `riemann-hypothesis` (Spark AArch64, 2026-11-23)

- **PR #120 branch (`rohanarun/riemann-hypothesis:opt/collapse-and-consolidate-4.36`, 47,884 `.lean` files):**
  - `stats`: `47,884` modules, `20,259` bundles, `141,483` sections, `494,936` project import edges, `0` cycles, `max_depth=154`, `14,563,446` lines, `808,243` declarations, `16,138` `nlinarith` calls, `4` `maxHeartbeats` overrides, `27,504` culprit-exposed modules (`elapsed_ms=41870`).
  - `scan --only-bundles`: `shadow=5470 ambig=11194 culprit=65309 elapsed_ms=8168` (recalled live `PR120-BUGS.md` collisions including `CountingFormula/Bundle0020.lean` `gS`, `GeometryProofs/Bundle0109.lean`, `Divisors/Bundle0064.lean` `IsNormalScheme`, `GaloisCohomology₂/Bundle0010.lean` `Dec`, `AutomorphicForms₂/Bundle0007.lean` `cls`, and `45` `Dominates` shadow hits).
  - `plan-clump --max-lines 250 --mode antichain`: `47,884 -> 47,263` (`536` bundles, `shadow_avoided=8 ambig_avoided=2 culprit_avoided=44 cycles=0 elapsed_ms=16`).
  - `plan-clump --max-lines 250 --mode tree`: `47,884 -> 46,643` (`914` bundles, `shadow_avoided=1138 ambig_avoided=194 culprit_avoided=360 cycles=0 elapsed_ms=23`).
- **Upstream `main` (`leanprover-community/riemann-hypothesis`, `62,074` `.lean` files):**
  - `stats`: `62,074` modules, `12,818` bundles, `138,502` sections, `380,853` project import edges, `0` cycles, `max_depth=90`, `17,168,483` lines, `806,907` declarations, `14,596` `nlinarith` calls, `4` `maxHeartbeats` overrides, `12,922` culprit-exposed modules (`elapsed_ms=24048`).
  - `plan-clump --max-lines 250 --mode antichain`: `62,074 -> 48,756` (`-21%`, `11,312` bundles, `shadow_avoided=5 ambig_avoided=1 culprit_avoided=3666 cycles=0 elapsed_ms=139`).
  - `plan-clump --max-lines 250 --mode tree`: `62,074 -> 62,027` (`44` bundles, `shadow_avoided=17 ambig_avoided=7 culprit_avoided=4 cycles=0 elapsed_ms=3`).
