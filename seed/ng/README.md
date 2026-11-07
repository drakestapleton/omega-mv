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
| `src/opt.om` | Unit after ir.om: the ΩIR optimizer (IR.md s15.1). Per function: preheaders, bounds-check elimination (a `chk.bounds` proved by a const index or a dominating compare-and-branch becomes `fact.inbounds` origin 1; a `chk.divz` of a nonzero const goes), loop-invariant code motion of class P ops (checks, memory and calls stay on the token chain), loop rotation (header after its latch). |
| `src/main.om` | Last unit: `ng` driver. `@ng ir-copy` reads a unit and writes it back byte for byte; `@ng opt` writes it optimized; `@ng opt-count` prints `opt fns= loops= inloop=A->B bce= hoisted= merged= rotated= preheaders=` (A, B: executing ops in loop blocks before and after; bce: checks deleted). |
| `ng.units` | The ordered unit list of `ng`, each with its sha256 pin. |
| `ngbuild.om` | `ngbuild build OMC UNITS OUT` checks every pin, concatenates and compiles; `ngbuild sums UNITS` prints fresh pins. |
| `sha256.om` | FIPS 180-4 SHA-256 shared by ngbuild, ngcheck and the gate. |
| `ngcheck.om` | The validator: binary ΩIR on stdin, `ACCEPT <sha256> fns= blocks= ops=` or `ngcheck: CLASS at OFFSET` with the class as exit code (IR.md s11). Its own reader: it shares no code with `src/ir.om`. `ngcheck --table` prints the host word table it was built with. |
| `ngtxt.om`, `ngas.om`, `ngdis.om` | Canonical text tools (IR.md s10): `ngas` text to binary, `ngdis` binary to text. A third independent decoder of the wire format. |
| `ngrun.om` | The reference interpreter (IR.md s7): `ngrun FILE.ir` runs the program entry of an accepted unit; output through the real host words, exit status = the entry's result, a failing check exits 100 + code. Unsupported ops (vectors, tiles, kernels, fma, fmath, f16/bf16/fp8) print `ngrun: unsupported op N at OFFSET` and exit 125. Its own limits stay off the trap exits 100..114: `ngrun FILE.ir STEPS` stops after STEPS executed ops (default 2^36, about an hour) with `ngrun: step limit at OFFSET` and exit 124, and an element outside the object its REF or SLICE names (reachable only from input ngcheck refuses) gives `ngrun: access outside storage at OFFSET` and exit 126. Its exit status is an IR result only for a unit ngcheck accepts; on refused input it means nothing. Back ends diff their output against it (D9). It reads through `src/ir.om`, the reader `ng` itself uses, so a diff against ngrun alone cannot see a reader fault both share: that is what the gate's run pairs are for, which judge ngrun against omc's build of the same program in Omega (no shared code). Exercised: `sub` operands swapped in both the reader and the writer of `ir.om` pass every round-trip and ir-copy case and are caught by the run pairs `x-fib` and `x-float`. The gate also mutates ngrun nine ways (fuel one pass late; rem MIN/-1, u64 `chk.add` and `chk.mul`, `chk.shl` negative side, signed conv lower bound, `chk.bounds` with e = 0, narrow `neg`, depth cap): each is caught by a run pair or an N case (`n-*.oir`, ngrun alone, for the semantics Omega cannot state). |
| `ngrand.om` | Random programs, valid by construction (IR.md s10): `ngrand SEED` writes a binary unit (helpers, diamonds, counted loops, calls, checks with their codes, i64 memory, host write) built with `src/ir.om`; `ngrand tape FILE` replays a choice tape; `ngrand shrink SEED STATUS OUT CMD [ARG...]` deletes and zeroes tape bytes while `CMD ARG... OUT` exits STATUS and leaves the smallest unit in OUT and its tape in OUT.tape. The D9 differential source: a back end runs the same units as ngrun and the outputs must agree. |
| `tests/ir/` | Text fixtures (`*.oir`), run pairs (`x-*.oir` + `x-*.om`) and `cases`, the expectations the gate runs. |
| `tests/opt/` | Optimizer fixtures (`O`/`L` lines of `tests/ir/cases`): ng-front's 23 lowered run units and two by hand. |
| `gate-ir.om` | The ΩIR gate. |

## Build and gate

From the repository root (any scratch directory works):

    cat seed/ng/sha256.om seed/ng/gate-ir.om | seed/out/omc > /tmp/gate-ir && chmod +x /tmp/gate-ir
    /tmp/gate-ir seed/out/omc /tmp/ng-ir-gate

The gate builds ngbuild, ngcheck, ngas, ngdis, ngrun and ngrand with that omc, builds `ng` through
`ngbuild build` (so every pin in `ng.units` is checked), requires `ngcheck --table` to equal
`hostwords.tsv`, and requires `ngbuild build` to refuse a units file with one wrong pin (exit 3,
the exact mismatch line) before it compiles anything. Then it runs every line of `tests/ir/cases`:
the text round trip `ngdis(ngas(t)) == t`; ngcheck's whole output line, either
`ACCEPT <sha256> fns=F blocks=B ops=O` (digest by the gate's own SHA-256, counts taken from the
fixture text) or the exact refusal line `ngcheck: CLASS at OFFSET` with empty stdout; `ng
ir-copy` on every unit (IR.md s14: identity, or the same refusal line for structural classes);
ngas syntax and limit refusals; byte mutants judged by ngcheck, ngdis and ng; inputs the gate
generates at the capacities of IR.md s10 and s12 (a unit of exactly 16777216 bytes and one byte
more, 65537 type entries, text with 65537 types, globals, functions, blocks or parameters); and
run pairs: ngrun on `x-NAME.oir` against omc's build of `x-NAME.om` (exit status, stdout and
stderr equal); N cases: ngrun alone on `n-NAME.oir` with a step budget of 1000000 (exit status,
empty stdout, the step-limit or outside-storage line); random units of ngrand for seeds 1..1000 (ngcheck's whole ACCEPT line,
`ngas(ngdis(b)) == b`, the same bytes twice for seed 1, ngrun ending with exit 0..63 and 0 or 8
stdout bytes, 64..95 by `exit` or 101..114 by a trap, empty stderr); one shrink with ngrun as
the predicate (accepted, still trapping, smaller, its tape replays it); and the optimizer on every
random seed and every `tests/opt/` fixture (`@ng opt` exit 0, ngcheck's whole ACCEPT line on the
output, its text round trip, ngrun before and after equal, a second `@ng opt-count` finding nothing
to move; a row `ok O NAME fns=.. inloop=A->B ...` per fixture). The `L` fixtures are the long
kernels (ngrun takes 25 s to several minutes each on the Spark, twice), which makes a full gate run
take tens of minutes. Then its negative controls:
three deliberately wrong expectations must each trip
their named check, three mutants of ngcheck (load and store typing disabled, the witness prefix
changed, the class name shifted), nine mutants of ngrun (`chk.fuel` one pass late, rem MIN/-1
giving a, u64 `chk.add` and `chk.mul` never failing, `chk.shl` without its negative bound, the signed
conv lower bound at -2^(w-1), `chk.bounds` passing e = 0, narrow `neg` left uncanonical, the depth
cap at 70000), a mutant ngrand (a
random check's new token not made current) and four of opt.om (a load hoisted past the loop's
stores and checks hoisted past their guard, both refused by ngcheck; preheader merging that
ignores imm and BCE accepting an index one past its proof, a run differs) must each fail their named check at least once (the
ngrand mutant: ngcheck refuses TOKEN); each mutant's pattern must occur exactly once in its source.
Under a mutant, Q runs 100 seeds and `L` cases are skipped. Last line `NGIRGATE PASS cases=N`,
exit 0; otherwise one `FAIL` line per failure and exit 1.

The tools one by one:

    cat seed/ng/sha256.om seed/ng/ngcheck.om | seed/out/omc > ngcheck
    cat seed/ng/ngtxt.om seed/ng/ngas.om | seed/out/omc > ngas
    cat seed/ng/ngtxt.om seed/ng/ngdis.om | seed/out/omc > ngdis
    cat seed/ng/sha256.om seed/ng/ngbuild.om | seed/out/omc > ngbuild
    cat seed/ng/src/ir.om seed/ng/ngrun.om | seed/out/omc > ngrun
    cat seed/ng/src/ir.om seed/ng/ngrand.om | seed/out/omc > ngrand
    ./ngrand 7 > r7.ir && ./ngcheck < r7.ir && ./ngrun r7.ir; echo $?
    ./ngbuild build seed/out/omc seed/ng/ng.units ng
    ./ngas < seed/ng/tests/ir/a-arith.oir | ./ngcheck
    ./ngas < seed/ng/tests/ir/x-fib.oir > fib.ir && ./ngrun fib.ir; echo $?

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
