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
| `a64/`, `src/a64.om` | ng-a64 | ΩIR to AArch64: the integer slice and scalar f32/f64 (`a64/DESIGN.md` sections 2 and 9; gates `a64/gate.om` and `a64/rgate.om`, whose float phase runs `a64/tests/frand.om`). |
| `gpu/`, `src/gpu.om` | ng-gpu | Encoder conformance gate over the CUDApp units pinned in `cudapp.lock` (D10); `gpu.om` lands in `src/`. |
| `bench/` | ng-bench | A/B timing harness against omc and gcc -O2. |

## ΩIR files (lane ng-ir)

| File | Role |
|---|---|
| `IR.md` | ΩIR v1: binary format, types, ops, token chain, coverage rule, refusal classes, text form, limits. |
| `hostwords.tsv` | Normative host word table (`id word args class`) the `host` op is checked against. |
| `src/ir.om` | First unit of the `ng` program (om2): ΩIR tables, builder, the one binary reader and writer (IR.md s14). |
| `src/opt.om` | Unit after ir.om: the ΩIR optimizer (IR.md s15.1). Per function: preheaders, PHI (a block parameter whose `br` arguments are one value besides itself becomes that value), bounds-check elimination (a `chk.bounds` proved by a const index or a dominating compare-and-branch becomes `fact.inbounds` origin 1; a `chk.divz` of a nonzero const goes), loop-invariant code motion of class P ops (checks, memory and calls stay on the token chain), PHI, BCE and LICM repeated while one of them changes something, then loop rotation (header after its latch). |
| `src/main.om` | Last unit: `ng` driver. `@ng ir-copy` reads a unit and writes it back byte for byte; `@ng front-check` and `@ng front-ir` run `src/front.om` (front/README.md); `@ng opt` writes it optimized; `@ng opt-count` prints `opt fns= loops= inloop=A->B phi= bce= hoisted= merged= rotated= preheaders=` (A, B: executing ops in loop blocks before and after; phi: block parameters removed; bce: checks deleted; counts of later passes come before `bce=`, and the gate's fixed-point check reads the tail from `phi=` on). |
| `ng.units` | The ordered unit list of `ng`, each with its sha256 pin. |
| `ngbuild.om` | `ngbuild build OMC UNITS OUT` validates the list, checks every pin, joins and compiles; `ngbuild sums UNITS` prints fresh pins. |
| `*.units`, `tests/ngbuild/gate.om` | Per-tool pinned lists, including `ngbuild.units` for its own self-build; standalone Omega first-birth and refusal gate. |
| `sha256.om` | FIPS 180-4 SHA-256 shared by ngbuild, ngcheck and the gate. |
| `ngcheck.om` | The validator: binary ΩIR on stdin, `ACCEPT <sha256> fns= blocks= ops=` or `ngcheck: CLASS at OFFSET` with the class as exit code (IR.md s11). Its own reader: it shares no code with `src/ir.om`. `ngcheck --table` prints the host word table it was built with. |
| `ngtxt.om`, `ngas.om`, `ngdis.om` | Canonical text tools (IR.md s10): `ngas` text to binary, `ngdis` binary to text. A third independent decoder of the wire format. |
| `ngrun.om` | The reference interpreter (IR.md s7): `ngrun FILE.ir [STEPS] [--scratch NEW-DIR] [-- ARGS...]` runs the program entry of an accepted unit; exit status = the entry's result, a failing check exits 100 + code. Host words follow IR.md s7.11: argument, environment, clock, id and cpu words execute (ARGS after `--` are arguments 1..), file words only inside the fresh `--scratch` directory on one-component names and descriptors ngrun created, and every other word prints `ngrun: refused host class C word W at OFFSET` and exits C, 115..123. Scalar f32/f64 bitcasts preserve all bits; every defined f32/f64 conversion mode and fused FMA are supported. Unsupported ops (vectors, tiles, kernels, fmath, f16/bf16/fp8) print `ngrun: unsupported op N at OFFSET` and exit 125. Its own limits stay off the trap exits 100..114: `ngrun FILE.ir STEPS` stops after STEPS executed ops (default 2^36, about an hour) with `ngrun: step limit at OFFSET` and exit 124, and an element outside the object its REF or SLICE names (reachable only from input ngcheck refuses) gives `ngrun: access outside storage at OFFSET` and exit 126. Its exit status is an IR result only for a unit ngcheck accepts; on refused input it means nothing. Back ends diff their output against it (D9). It reads through `src/ir.om`, the reader `ng` itself uses, so a diff against ngrun alone cannot see a reader fault both share: that is what the gate's run pairs are for, which judge ngrun against omc's build of the same program in Omega (no shared code). Exercised: `sub` operands swapped in both the reader and the writer of `ir.om` pass every round-trip and ir-copy case and are caught by the run pairs `x-fib` and `x-float`. The gate also mutates ngrun nine ways (fuel one pass late; rem MIN/-1, u64 `chk.add` and `chk.mul`, `chk.shl` negative side, signed conv lower bound, `chk.bounds` with e = 0, narrow `neg`, depth cap): each is caught by a run pair or an N case (`n-*.oir`, ngrun alone, for the semantics Omega cannot state). |
| `ngrand.om` | Random programs, valid by construction (IR.md s10): `ngrand SEED` writes a binary unit (helpers, diamonds, counted loops, calls, checks with their codes, i64 memory, host write) built with `src/ir.om`; `ngrand tape FILE` replays a choice tape; `ngrand shrink SEED STATUS OUT CMD [ARG...]` deletes and zeroes tape bytes while `CMD ARG... OUT` exits STATUS and leaves the smallest unit in OUT and its tape in OUT.tape (the predicate runs at most 20001 times). The D9 differential source: a back end runs the same units as ngrun and the outputs must agree. |
| `tests/ir/` | Text fixtures (`*.oir`), run pairs (`x-*.oir` + `x-*.om`) and `cases`, the expectations the gate runs. |
| `tests/opt/` | Optimizer fixtures (`O`/`L` lines of `tests/ir/cases`): ng-front's 23 lowered run units and six by hand (`o-pre2`, `o-zero`, `o-bce0`, `o-bce1`, and the kernel loops `o-shfl` and `o-mma`, whose invariant `shfl` and `mma` must not leave the loop). |
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
more, which ngcheck and ngdis refuse as LIMIT while ng and ngrun, reading into the no-caps arena of
`src/ir.om`, read it whole and refuse the byte as TRAILING; 65537 type entries, text with 65537 types,
globals, functions, blocks or parameters); and
run pairs: ngrun on `x-NAME.oir` against omc's build of `x-NAME.om` (exit status, stdout and
stderr equal); N cases: ngrun alone on `n-NAME.oir` with a step budget of 1000000 (exit status,
empty stdout, the step-limit or outside-storage line); random units of ngrand for seeds 1..1000 (ngcheck's whole ACCEPT line,
`ngas(ngdis(b)) == b`, the same bytes twice for seed 1, ngrun ending with exit 0..63 and 0 or 8
stdout bytes, 64..95 by `exit` or 101..114 by a trap, empty stderr); one shrink with ngrun as
the predicate (accepted, still trapping, smaller, its tape replays it); and the optimizer on every
random seed and every `tests/opt/` fixture (`@ng opt` exit 0, ngcheck's whole ACCEPT line on the
output, its text round trip, ngrun before and after equal, a second `@ng opt-count` finding nothing
to move; a row `ok O NAME fns=.. inloop=A->B ...` per fixture, which must equal the row written on
its `O`/`L` line, so a pass that stops doing its work fails). The `L` fixtures are the long
kernels (ngrun takes 25 s to several minutes each on the Spark, twice: about 19 min of ngrun per pass
on an idle Spark core, sum of the measured per-kernel runs), which makes a full gate run take about 40
minutes (2353 s at 854d8152 on core 11). The workflow `.github/workflows/ng-ir-arm64.yml` keeps main's
30-minute timeout, so a CI run of this gate would be cut off; the gate is run on the Spark. Then its negative controls:
three deliberately wrong expectations must each trip
their named check, three mutants of ngcheck (load and store typing disabled, the witness prefix
changed, the class name shifted), ten mutants of ngrun (`chk.fuel` one pass late, rem MIN/-1
giving a, u64 `chk.add` and `chk.mul` never failing, `chk.shl` without its negative bound, the signed
conv lower bound at -2^(w-1), `chk.bounds` passing e = 0, narrow `neg` left uncanonical, the depth
cap at 70000, the step limit one op late: `n-loop2` then names 87, not 116), a mutant ngrand (a
random check's new token not made current) and five of opt.om (a load hoisted past the loop's
stores and checks hoisted past their guard, both refused by ngcheck; preheader merging that
ignores imm and BCE accepting an index one past its proof, a run differs; LICM moving a convergent
`shfl`, the pinned `o-shfl` row differs) must each fail their named check at least once (the
ngrand mutant: ngcheck refuses TOKEN); each mutant's pattern must occur exactly once in its source.
Under a mutant, Q runs 100 seeds and `L` cases are skipped. Last line `NGIRGATE PASS cases=N`,
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
| 6 / 7 | Cannot write output / fork or wait failure, or OMC ended by a signal (`ngbuild: fork or wait failed, or omc ended by a signal`). A failed exec or redirect in the child exits 127 and is reported as `ngbuild: omc exit 127`, exit 1. OUT.src is written before OUT is opened and OMC runs, and stays after a successful build; exit 6 can leave OUT.src, and exits 1 and 7 can leave both. After OMC exits 0, OUT is read back for its sha256; exit 5 (`ngbuild: unreadable: OUT`) or exit 9 (`ngbuild: too large: OUT`, OUT of 16777216 bytes or more) then leaves both. |
| 8 / 9 | Duplicate unit / list, unit count, unit file or joined-source limit exceeded. |

Exact diagnostic formats are in `ngbuild.om`; malformed-line offsets count bytes from zero.
Regression gate: `tests/ngbuild/gate.om`, with no shared implementation with ngbuild.

CI: `.github/workflows/ng-ir-arm64.yml` births omc from the seed, requires the committed
`seed/out/omc.sha256`, builds the gate and runs it. That historical workflow's `cat` bootstrap is
unchanged here (protected path); use the host commands above for the no-cat build. It runs on any
pull request that changes `seed/**` or the workflow, and on every push to main.

## No-caps gate

ng's input-sized tables (the front's, the front-ir lowering's, the ΩIR payload, output, global data and
globals of `src/ir.om`, and a64's per-function wires, liveness bitsets, call sites, global addresses and code
image) are regions of one arena, `ar_m` in `src/ir.om` (16777216 words, 128 MiB; omc.om's arena design,
OmcNoCaps 2026-11-11). A region doubles when an index reaches its capacity, and the arena is compacted when the
copies do not fit, so the only capacity left is the arena itself: a full arena is a defined refusal (front error 14,
ΩIR reader LIMIT 23, otherwise `ng: arena full`, exit 14) followed by the ng-use record `ng-use 1 arena=A top=T
waste=W full=F GROUP=N/H ...` on stderr. A front unit whose first line is `usage` writes that record in place of
output (the alarm's input). Value nesting stays bounded by ng's 8 MiB stack at 32768 levels (front.om's note at the
depth check). The tables of IR.md s12 that the ΩIR builder, ngcheck and the text tools keep are refused with a line,
never overrun (`ir_lim`).

    cat seed/ng/sha256.om seed/ng/tests/nocaps/gate.om | seed/out/omc > nocaps-gate
    nocaps-gate seed/out/omc $(sha256sum seed/out/omc | cut -c1-64) SCRATCH [NG]

It builds ng from `ng.units`, generates units far past every old table (100,000 globals, texts and long names,
60,000 functions, 1,000,000 calls in one function and 1,100,000 in 1100, a 64 MiB input, 5000 nested blocks,
3000 breaks and continues, values 5000 and 32767 deep, nested calls, 2,000,000 front-ir name snapshots, 10,000
local arrays, 22,500 inline edges, an om2 diag unit of 1,000,000 sites, 17 MiB of text data; past the front's old
loop bounds, 1,000,001 rets in one inline body, one text literal of 16,777,219 bytes and 16,777,232 blank lines in
one block; past a64's 262144 branch fixups a function, 270,000 overflow branches, once with the trap taken), has
omc compile and run each and ng check, lower, compile and run it, and requires the same answers. 32 mutants
(each old table or loop bound put back, the trap-label tag of a64 back at 1000, a moved region losing its words)
must be KILLED, and a control (a wrong expected answer) tripped. The usage alarm: ng checks
`seed/omc/omc.om` and its own units after a `usage` line; the arena top must stay at or below 10% of the arena,
every group at or below 5%, a check at or below 2 s
(both stand near 1.3% and 20 ms); ng with the arena shrunk to 1048576 words must trip it. With NG given, that binary
is judged and nothing is built (the ng of the base must FAIL here). Last line `NOCAPSGATE PASS cases=31 fail=0
mutants=32 killed=32 controls=2 tripped=2 notrun=0`, exit 0.

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
