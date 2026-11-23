# apps: Interplane Forge, sites, Hop and publishing tools of Sovereign Intelligence (SI)

Mirrors [gpu/README.md](../gpu/README.md) for the user-facing applications, sites and publishing layer (`interplane-forge`, `aienos.com`, `interplane.io`, `hop`, `omtex`, plus pure-Omega conversions of `omega-projects`, `aien-edge`, `readings-window`, and `aien-translate`).

Everything under `apps/` is pure seeded Omega (`.om`) built by `omega-mv`'s own `seed/out/omc`, plus provenance records (`apps/import/`) and tables listing what compiles and what remains non-Omega upstream (`apps/NOT-YET-OMEGA.tsv`). **Only pure Omega lives here.**

## Layout

| Path | Upstream repo | Canonical head | `.om` files | Imported commits | Non-`.om` upstream |
| --- | --- | --- | ---: | ---: | ---: |
| `apps/interplane-forge/` | `interplane-forge` (`interplane:interplane-forge`) | `3df50b9554ac` | 158 | 241 | 413 |
| `apps/aienos-site/` | `aienos.com` (`rad:z3iwnx2pktbGhnfBpJSsaFcTmKgHU`) | `fd9dd20cde24` | 200 | 223 | 1277 |
| `apps/interplane-site/` | `interplane.io` (`rad:z399yKvnXcBQNkKoq86iBDgTvQ5QV`) | `4573e1d996e0` | 4 | 27 | 140 |
| `apps/hop/` | `hop` (`interplane:hop`) | `59208f4d3b4a` | 28 | 38 | 129 |
| `apps/omtex/` | `omtex` (`rad:zcBSb6QfXYD2tVRHF6GmXBALFx66`) | `6f01dcf896a3` | 5 | 1 | 17 |
| `apps/omega-projects/` | `omega-projects` (`rad:z4Yun5Auii2oWtmDnHrm2V4wcZkhU`) | `e97e46efbb7b` | 3 | converted | 13 |
| `apps/edge/` | `aien-edge` (`rad:z2Ajufz3KS3GompMJ2SJmAz8mRnk6`) | `8ad4253d8855` | 3 | converted | 20 |
| `apps/readings-window/` | `readings-window` (`rad:z2Jhza2V51dFcMFUhNiFcXHpE5Ewy`) | `1f2f34702c2a` | 3 | converted | 22 |
| `apps/translate/` | `aien-translate` (`rad:z49FTK9M33MFjenns3vqDqqN66zj7`) | `cfcd35fbd150` | 3 | converted | 33 |

Total in `apps/`: **407 `.om` files** imported/converted across upstream SI apps, plus native pure-Omega additions under `apps/core/`, `apps/site_builder/`, and `apps/lean-opt/` (`131` units in `apps/units.tsv`, gated by `apps/units-gate.om`; non-`.om` upstream files for the imported repos are listed in [`apps/NOT-YET-OMEGA.tsv`](NOT-YET-OMEGA.tsv)).

## One compiler

Every unit in [`apps/units.tsv`](units.tsv) is built by `seed/out/omc`, and [`apps/units-gate.om`](units-gate.om) refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69).

## Gate

Build and run `apps/units-gate.om` (`OMEGA-APPS-UNITS`) from the repository root:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om apps/units-gate.om; } | seed/out/omc > apps-units-gate
chmod +x apps-units-gate
./apps-units-gate seed/out/omc /tmp/apps-units-gate-scratch
```

Wiring `OMEGA-APPS-UNITS` into `tests/gates/` is a separate operator-gated change (`AGENTS.md`). Deterministic host compilation proves reproducible building with `seed/out/omc`; it is never hardware, QEMU, or deployment qualification.
