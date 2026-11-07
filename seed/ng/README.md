# seed/ng: Omega NG

Omega NG is the next Omega compiler (Hive NG). Source goes through a front end (`src/front.om`) into
ΩIR, the intermediate form specified in [`IR.md`](IR.md); passes (`src/opt.om`) rewrite ΩIR; back ends
lower it to AArch64 (`src/a64.om`) and sm_121 (`src/gpu.om`). Everything here is Omega, compiled by
the pinned seeded compiler `seed/out/omc`.

This directory is shared by the NG lanes. Lane ng-ir owns the ΩIR spec, its in-memory form and the
tools below; the other lanes own their `src/*.om` unit and their subdirectory:

| Directory | Lane | Role |
|---|---|---|
| `front/`, `src/front.om` | ng-front | Omega source to ΩIR; every language refusal of omc. |
| `a64/`, `src/a64.om` | ng-a64 | ΩIR to AArch64. |
| `gpu/`, `src/gpu.om` | ng-gpu | Encoder conformance gate over the CUDApp units pinned in `cudapp.lock` (D10); `gpu.om` lands in `src/`. |
| `bench/` | ng-bench | A/B timing harness against omc and gcc -O2. |

## ΩIR files (lane ng-ir)

| File | Role |
|---|---|
| `IR.md` | ΩIR v1: binary format, types, ops, token chain, coverage rule, refusal classes, text form, limits. |
| `hostwords.tsv` | Normative host word table (`id word args class`) the `host` op is checked against. |
| `src/ir.om` | First unit of the `ng` program (om2): ΩIR tables, builder, the one binary reader and writer (IR.md s14). |
| `src/main.om` | Last unit: `ng` driver; mode `@ng ir-copy` reads a unit and writes it back byte for byte. |
| `ng.units` | The ordered unit list of `ng`, each with its sha256 pin. |
| `ngbuild.om` | `ngbuild build OMC UNITS OUT` checks every pin, concatenates and compiles; `ngbuild sums UNITS` prints fresh pins. |
| `sha256.om` | FIPS 180-4 SHA-256 shared by ngbuild, ngcheck and the gate. |
| `ngcheck.om` | The validator: binary ΩIR on stdin, `ACCEPT <sha256> fns= blocks= ops=` or `ngcheck: CLASS at OFFSET` with the class as exit code (IR.md s11). Its own reader: it shares no code with `src/ir.om`. `ngcheck --table` prints the host word table it was built with. |
| `ngtxt.om`, `ngas.om`, `ngdis.om` | Canonical text tools (IR.md s10): `ngas` text to binary, `ngdis` binary to text. A third independent decoder of the wire format. |
| `tests/ir/` | Text fixtures (`*.oir`) and `cases`, the expectations the gate runs. |
| `gate-ir.om` | The ΩIR gate. |

## Build and gate

From the repository root (any scratch directory works):

    cat seed/ng/sha256.om seed/ng/gate-ir.om | seed/out/omc > /tmp/gate-ir && chmod +x /tmp/gate-ir
    /tmp/gate-ir seed/out/omc /tmp/ng-ir-gate

The gate builds ngbuild, ngcheck, ngas and ngdis with that omc, builds `ng` through
`ngbuild build` (so every pin in `ng.units` is checked), requires `ngcheck --table` to equal
`hostwords.tsv`, and requires `ngbuild build` to refuse a units file with one wrong pin (exit 3,
the exact mismatch line) before it compiles anything. Then it runs every line of `tests/ir/cases`:
the text round trip `ngdis(ngas(t)) == t`; ngcheck's whole output line, either
`ACCEPT <sha256> fns=F blocks=B ops=O` (digest by the gate's own SHA-256, counts taken from the
fixture text) or the exact refusal line `ngcheck: CLASS at OFFSET` with empty stdout; `ng
ir-copy` on every unit (IR.md s14: identity, or the same refusal line for structural classes);
ngas syntax and limit refusals; byte mutants judged by ngcheck, ngdis and ng; and inputs the gate
generates at the capacities of IR.md s10 and s12 (a unit of exactly 16777216 bytes and one byte
more, 65537 type entries, text with 65537 types, globals, functions, blocks or parameters). Then
its negative controls: three deliberately wrong expectations must each trip their named check, and
three mutants of ngcheck (load and store typing disabled, the witness prefix changed, the class
name shifted) must each fail their named check at least once. Last line `NGIRGATE PASS cases=N`,
exit 0; otherwise one `FAIL` line per failure and exit 1.

The tools one by one:

    cat seed/ng/sha256.om seed/ng/ngcheck.om | seed/out/omc > ngcheck
    cat seed/ng/ngtxt.om seed/ng/ngas.om | seed/out/omc > ngas
    cat seed/ng/ngtxt.om seed/ng/ngdis.om | seed/out/omc > ngdis
    cat seed/ng/sha256.om seed/ng/ngbuild.om | seed/out/omc > ngbuild
    ./ngbuild build seed/out/omc seed/ng/ng.units ng
    ./ngas < seed/ng/tests/ir/a-arith.oir | ./ngcheck

After changing a unit listed in `ng.units`, refresh its pins with `./ngbuild sums seed/ng/ng.units`.

CI: `.github/workflows/ng-ir-arm64.yml` births omc from the seed, requires the committed
`seed/out/omc.sha256`, builds the gate and runs it. Its run lines are glue only (birth, digest
compare, `cat A B | omc`, start the gate); every check lives in the gate. It runs on any change
under `seed/` (the compiler's bootstrap closure and the ng tree) or to the workflow.

## Host dependencies

Every host binary that stays in an NG build, gate or bench path, with its version, what it does
for us and its Omega replacement (Hive NG ledger `HOST-DEPS.md`, carried here). Verification
oracles (the pinned omc, git, gh, crumb) and referees (gcc, objdump, cuobjdump, Wolfram) are exempt.

| host tool | version | where | what it does | Omega replacement |
|---|---|---|---|---|
| cat | GNU coreutils 9.4 (`/usr/bin/cat`) | bootstrap of ngbuild, ngcheck, ngas, ngdis and the gate (`cat A B \| omc`) | concatenates two units once, before ngbuild exists | ngbuild self-builds after the first birth; proposal: commit a units file per tool and drop cat after one bootstrap |
| taskset | util-linux 2.39.3 | Spark builds and timed runs | pins builds to core 1, timed runs to their cores | an Omega `sched_setaffinity` host word in ngbench (proposal to omega-mv) |
| flock | util-linux 2.39.3 | Spark lane builds and bench rounds | shared and exclusive core-pool locks between agents | an Omega flock host word, or ngbench taking the lock itself (proposal) |
| nice | GNU coreutils 9.4 (`/usr/bin/nice`) | Spark build and timing prefixes | lowers scheduling priority | a setpriority host word (proposal) |
| sh / YAML run lines | GitHub runner | CI workflows `ng-<lane>-arm64.yml` | one-line invocations of `.om` gates | none planned: CI glue only, no logic |
