# seed/ng: Omega NG

Omega NG is the next Omega compiler (Hive NG). Source goes through a front end (`src/front.om`) into
ΩIR, the intermediate form specified in [`IR.md`](IR.md); passes (`src/opt.om`) rewrite ΩIR; back ends
lower it to AArch64 (`src/a64.om`) and sm_121 (`src/gpu.om`). Everything here is Omega, compiled by
the pinned seeded compiler `seed/out/omc`.

This directory is shared by the NG lanes. Lane ng-ir owns the ΩIR spec, its in-memory form and the
tools below; the other lanes own their `src/*.om` unit and their subdirectory:

| Directory | Lane | Role |
|---|---|---|
| `front/`, `src/front.om` | ng-front | Omega source to ΩIR (`@ng front-ir`, gate `front/gate-front-ir.om`); every language refusal of omc (`@ng front-check`, gate `front/gate-front.om`). |
| `a64/`, `src/a64.om` | ng-a64 | ΩIR to AArch64. |
| `gpu/`, `src/gpu.om` | ng-gpu | Encoder conformance gate over the CUDApp units pinned in `cudapp.lock` (D10); `gpu.om` lands in `src/`. |
| `bench/` | ng-bench | A/B timing harness against omc and gcc -O2. |

## ΩIR files (lane ng-ir)

| File | Role |
|---|---|
| `IR.md` | ΩIR v1: binary format, types, ops, token chain, coverage rule, refusal classes, text form, limits. |
| `hostwords.tsv` | Normative host word table (`id word args class`) the `host` op is checked against. |
| `src/ir.om` | First unit of the `ng` program (om2): ΩIR tables, builder, the one binary reader and writer (IR.md s14). |
| `src/main.om` | Last unit: `ng` driver; mode `@ng ir-copy` reads a unit and writes it back byte for byte; `@ng front-check` and `@ng front-ir` run `src/front.om` (front/README.md). |
| `ng.units` | The ordered unit list of `ng`, each with its sha256 pin. |
| `ngbuild.om` | `ngbuild build OMC UNITS OUT` validates the list, checks every pin, joins and compiles; `ngbuild sums UNITS` prints fresh pins. |
| `*.units`, `tests/ngbuild/gate.om` | Per-tool pinned lists, including `ngbuild.units` for its own self-build; standalone Omega first-birth and refusal gate. |
| `sha256.om` | FIPS 180-4 SHA-256 shared by ngbuild, ngcheck and the gate. |
| `ngcheck.om` | The validator: binary ΩIR on stdin, `ACCEPT <sha256> fns= blocks= ops=` or `ngcheck: CLASS at OFFSET` with the class as exit code (IR.md s11). Its own reader: it shares no code with `src/ir.om`. `ngcheck --table` prints the host word table it was built with. |
| `ngtxt.om`, `ngas.om`, `ngdis.om` | Canonical text tools (IR.md s10): `ngas` text to binary, `ngdis` binary to text. A third independent decoder of the wire format. |
| `ngrun.om` | The reference interpreter (IR.md s7): `ngrun FILE.ir` runs the program entry of an accepted unit; output through the real host words, exit status = the entry's result, a failing check exits 100 + code. Scalar f32/f64 bitcasts preserve all bits; every defined f32/f64 conversion mode and fused FMA are supported. Unsupported ops (vectors, tiles, kernels, fmath, f16/bf16/fp8) print `ngrun: unsupported op N at OFFSET` and exit 125. Its own limits stay off the trap exits 100..114: `ngrun FILE.ir STEPS` stops after STEPS executed ops (default 2^36, about an hour) with `ngrun: step limit at OFFSET` and exit 124, and an element outside the object its REF or SLICE names (reachable only from input ngcheck refuses) gives `ngrun: access outside storage at OFFSET` and exit 126. Its exit status is an IR result only for a unit ngcheck accepts; on refused input it means nothing. Back ends diff their output against it (D9). It reads through `src/ir.om`, the reader `ng` itself uses, so a diff against ngrun alone cannot see a reader fault both share: that is what the gate's run pairs are for, which judge ngrun against omc's build of the same program in Omega (no shared code). Exercised: `sub` operands swapped in both the reader and the writer of `ir.om` pass every round-trip and ir-copy case and are caught by the run pairs `x-fib` and `x-float`. The gate also mutates ngrun nine ways (fuel one pass late; rem MIN/-1, u64 `chk.add` and `chk.mul`, `chk.shl` negative side, signed conv lower bound, `chk.bounds` with e = 0, narrow `neg`, depth cap): each is caught by a run pair or an N case (`n-*.oir`, ngrun alone, for the semantics Omega cannot state). |
| `ngrand.om` | Random programs, valid by construction (IR.md s10): `ngrand SEED` writes a binary unit (helpers, diamonds, counted loops, calls, checks with their codes, i64 memory, host write) built with `src/ir.om`; `ngrand tape FILE` replays a choice tape; `ngrand shrink SEED STATUS OUT CMD [ARG...]` deletes and zeroes tape bytes while `CMD ARG... OUT` exits STATUS and leaves the smallest unit in OUT and its tape in OUT.tape (the predicate runs at most 20001 times). The D9 differential source: a back end runs the same units as ngrun and the outputs must agree. |
| `tests/ir/` | Text fixtures (`*.oir`), run pairs (`x-*.oir` + `x-*.om`) and `cases`, the expectations the gate runs. |
| `gate-ir.om` | The ΩIR gate. |

## Build and gate

From the repository root (any scratch directory works):

    seed/out/omc < seed/ng/tests/ngbuild/gate.om > /tmp/ngbuild-gate && chmod +x /tmp/ngbuild-gate && /tmp/ngbuild-gate seed/out/omc /tmp/ngbuild-birth
    /tmp/ngbuild-birth/ngbuild build seed/out/omc seed/ng/gate-ir.units /tmp/gate-ir
    /tmp/gate-ir seed/out/omc /tmp/ng-ir-gate

The first line is the only bootstrap invocation. The standalone Omega gate independently joins
`sha256.om` and `ngbuild.om`, compiles the result, then has ngbuild read `ngbuild.units` and build
itself. It requires both joined source and binary to match byte for byte. It also exercises the
refusal exits 3, 4, 5, 8 and 9 below with exact exit status and diagnostic, no stdout and no
created output/source; exits 1, 2, 6 and 7 are not gate cases. The 64-argument usage refusal
cannot be a gate case: an `execprog` packed list holds at most 64 records (OMEGESE s10), so an
Omega parent never starts ngbuild with more than 63 arguments after the program name.
`ngbuild build` invokes OMC directly with `fork`, `dupfd`, `execprog` and `waitpid`, not a shell.
No `cat` is needed by these commands. Gate negative control: append `wrong` to its arguments; the
missing-unit expectation is inverted and the gate must end `NGBUILDGATE FAIL`, exit 1.

The ΩIR gate also runs the native seeded-omc float and conversion-range oracles in
`tests/ir/float-oracle.om` and `tests/ir/intcv-oracle.om` (IR.md s10), including sign-bit,
rounding-mode, fused FMA and unsigned-to-signed range-check mutants.
It builds ngbuild, ngcheck, ngas, ngdis, ngrun and ngrand with that omc, builds `ng` through
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
stdout bytes, 64..95 by `exit` or 101..114 by a trap, empty stderr); and one shrink with ngrun as
the predicate (accepted, still trapping, smaller, its tape replays it). Then its negative controls:
three deliberately wrong expectations must each trip
their named check, three mutants of ngcheck (load and store typing disabled, the witness prefix
changed, the class name shifted), ten mutants of ngrun (`chk.fuel` one pass late, rem MIN/-1
giving a, u64 `chk.add` and `chk.mul` never failing, `chk.shl` without its negative bound, the signed
conv lower bound at -2^(w-1), `chk.bounds` passing e = 0, narrow `neg` left uncanonical, the depth
cap at 70000, the step limit one op late: `n-loop2` then names 87, not 116) and a mutant ngrand (a
random check's new token not made current) must each fail their named check at least once (the
ngrand mutant: ngcheck refuses TOKEN). Last line `NGIRGATE PASS cases=N`,
exit 0; otherwise one `FAIL` line per failure and exit 1.

The tools one by one, after first birth:

    /tmp/ngbuild-birth/ngbuild build seed/out/omc seed/ng/ngbuild.units ngbuild
    ./ngbuild build seed/out/omc seed/ng/ngcheck.units ngcheck
    ./ngbuild build seed/out/omc seed/ng/ngas.units ngas
    ./ngbuild build seed/out/omc seed/ng/ngdis.units ngdis
    ./ngbuild build seed/out/omc seed/ng/ngrun.units ngrun
    ./ngbuild build seed/out/omc seed/ng/ngbench.units ngbench
    ./ngbuild build seed/out/omc seed/ng/ngrand.units ngrand
    ./ngrand 7 > r7.ir && ./ngcheck < r7.ir && ./ngrun r7.ir; echo $?
    ./ngbuild build seed/out/omc seed/ng/ng.units ng
    ./ngas < seed/ng/tests/ir/a-arith.oir | ./ngcheck
    ./ngas < seed/ng/tests/ir/x-fib.oir > fib.ir && ./ngrun fib.ir; echo $?

After changing a listed unit, refresh every affected `*.units` file with `./ngbuild sums LIST`.
Capture its output into a separate file before replacing LIST; never truncate a list while `sums`
is reading it.

### Unit-list contract and exit status

Each line is exactly 64 lowercase SHA-256 hex digits, one space, a nonempty path of at most 4095
bytes (no NUL), then LF. A relative path resolves against the working directory; an absolute path
is used as given. No comments, blank lines or ordering metadata are accepted. Order is the line
order, with no inserted byte between files.
There is no dependency graph in this format, so a cycle has no representation. At least one and
at most 64 units, at most 65536 list bytes, and at most 8388607 joined source bytes are accepted.
The entire list is validated before any unit is read. In `build`, paths and digest pins must be
unique (this also catches aliases with identical contents); `sums` permits equal placeholder pins
but still refuses duplicate paths. All units and pins are checked before output is opened or OMC runs.

| Exit | Meaning |
|---|---|
| 0 | Built, or sums printed. |
| 1 / 2 / 3 | OMC refused (its status is printed) / usage, including any argument count other than `build`'s 4 or `sums`' 2 (checked before any argument is read) / pin mismatch. |
| 4 / 5 | Malformed or empty list / unreadable list or unit. |
| 6 / 7 | Cannot write output / fork or wait failure, or OMC ended by a signal (`ngbuild: fork or wait failed, or omc ended by a signal`). A failed exec or redirect in the child exits 127 and is reported as `ngbuild: omc exit 127`, exit 1. OUT.src is written before OUT is opened and OMC runs, and stays after a successful build; exit 6 can leave OUT.src, and exits 1 and 7 can leave both. |
| 8 / 9 | Duplicate unit / list, unit count, unit file or joined-source limit exceeded. |

Exact diagnostic formats are in `ngbuild.om`; malformed-line offsets count bytes from zero.
Regression gate: `tests/ngbuild/gate.om`, with no shared implementation with ngbuild.

CI: `.github/workflows/ng-ir-arm64.yml` births omc from the seed, requires the committed
`seed/out/omc.sha256`, builds the gate and runs it. That historical workflow's `cat` bootstrap is
unchanged here (protected path); use the host commands above for the no-cat build. It runs on any
pull request that changes `seed/**` or the workflow, and on every push to main.

## Host dependencies

Every host binary that stays in an NG build, gate or bench path, with its version, what it does
for me and its Omega replacement (Hive NG ledger `HOST-DEPS.md`, carried here). Verification
oracles (the pinned omc, git, gh, crumb) and referees (gcc, objdump, cuobjdump, Wolfram) are exempt.

| host tool | version | where | what it does | Omega replacement |
|---|---|---|---|---|
| cat | Not required by the host commands above | historical workflow bootstrap only (unchanged) | concatenates units in the historical workflow | standalone `tests/ngbuild/gate.om` owns first birth; `ngbuild build` owns all later pinned builds |
| taskset | util-linux 2.39.3 | Spark builds and timed runs | pins builds to core 1, timed runs to their cores | an Omega `sched_setaffinity` host word in ngbench (proposal to omega-mv) |
| flock | util-linux 2.39.3 | Spark lane builds and bench rounds | shared and exclusive core-pool locks between agents | an Omega flock host word, or ngbench taking the lock itself (proposal) |
| nice | GNU coreutils 9.4 | Spark build and timing prefixes | lowers scheduling priority | a setpriority host word (proposal) |
| sh / YAML run lines | GitHub runner | CI workflows `ng-<lane>-arm64.yml` | one-line invocations of `.om` gates | none planned: CI glue only, no logic |
