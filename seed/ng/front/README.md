# seed/ng/front: the ng-front lane (Hive NG)

`seed/ng/src/front.om` is the ng front end: the lexer, parser and language checks of
`seed/omc/omc.om` @943d9555 with every machine-code path removed. It is a unit of `seed/ng/ng.units`
(after `ir.om`, so it is OM-2 code) and runs as two ng modes (`src/main.om`). In both the payload is an
Omega unit, and ng must refuse exactly what omc refuses, on the same line with the same error code,
and accept what omc accepts (DECISIONS D5, D6, D9):

- `@ng front-check` checks only and writes nothing.
- `@ng front-ir` checks the same way (the same refusals, through `fe_check`), then lowers the unit it
  accepted to ΩIR with the `ir_*` builders of `src/ir.om` and writes the binary unit to stdout
  (`fe_lout`, the section "@ng front-ir" at the end of front.om).

## How front.om was made (provenance, not a build step)

1. `rename.om rename.map < omc.om` renames every function to `fe_NAME` (`main` to `fe_run`) and every
   global to `f_NAME` (8 bytes at most), the D1b name discipline. The renamed omc rebuilds byte for byte.
2. Hand edits, each with an `omc.om NAME @943d9555 line N` note: no output write; x86/EFI targets and
   IR v1 units exit 64; `fe_cond` reads and type-checks only; `fe_pushb` without branch places;
   `fe_s_text` without code; `fe_xefival` is error 25; `fe_alloc` without the 16-register cap;
   `fe_trapsite` keeps only the om2 diag site record; `fe_finish` without trap stubs; the
   check-point snapshot without code offsets.
3. `prune.om prune.txt` removes the rest: code buffers and code-offset globals are sinks, word writers
   and branch patchers go, and then every function, assignment and block left without an effect.

Since the first commit `src/front.om` is edited directly (the OM-2 renames `at`, `big`, `ops` to
`atp`, `bigf`, `opsb`; `fe_run` split into main.om's input and `fe_check`), so the tools are the
record of how it was derived, not a way to rebuild it. The gate checks the result.
Long names (omc `omc/long-names` 2e20b286, omc `564c5835`) were carried over by hand at the same omc sites:
`fe_tok2` interns a word of 9..63 bytes as the packed word 1 + 256 * index (`f_ln_*`, `f_tw8`), the 14 name
checks omc raised from 8 to 63 bytes are raised here, and `fe_mput_name`, `fe_findfn`, `fe_newname`,
`fe_rdval` and `fe_stmt` follow omc. Abstract, layout, layout-field and IR-mode names stay at 8 as in omc.

## What is not reproduced (D6)

omc refusals that come from its AArch64 code generator are not language rules: error 12 (16-register
expression pool), 14 for trap sites, 24 (branch displacement range). ng accepts such units; they are
`beyond` rows in `declared.txt` (`NAME beyond K REASON`), and the gate requires omc to exit exactly K
and ng to exit 0. Whether ng then compiles them correctly needs an independent referee (expected output
or a C twin): NOT_RUN until ng emits code. The value slots of `fe_alloc` keep omc's pool numbering
without the cap (slots past 16 share a number); ΩIR values replace them.

Units ng does not take exit 64 and are `scope` rows (`NAME scope K REASON`, omc must exit K): x86/EFI
targets (D8), IR v1 units (first line `ir`) and run-time pools (`global NAME T *`, OMEGESE 9.15;
`cases/pool_runtime.om`). A bound of ng's own that omc never reaches because
another omc limit refuses first is an `ngonly` row (`NAME ngonly K REASON`): both must exit K, and
their stderr lines differ (none today). omc has had no table capacities since 2026-11-11 (OMEGESE 9.6), and
ng's front has had none since the same day (no-caps arena, `src/ir.om` `ar_*`): its input, names, long names,
functions, calls, blocks, breaks, continues, inline edges, om2 diag site records, value-depth cells and the
front-ir lowering's names, block stack, snapshots, local arrays and call arguments are regions of one 128 MiB
arena that grow on demand. A full arena is error 14 with an ng-use record on stderr. Value nesting is bounded
by ng's own stack at 32768 levels, as omc's is. Names, long names, functions and lowering names have chained
hashes. A unit whose first line is `usage` is checked as usual and writes the ng-use record in place of output,
as omc's `usage` does (`seed/ng/tests/nocaps/gate.om` is the alarm).
An input ng refuses at a fixed table of its own while omc goes past it would be an `ngcap` row
(`NAME ngcap K REASON`, REASON naming ng's table): ng must exit K and omc anything else below 100. The gate prints
`NGCAP ng still refuses C inputs omc accepts` on every run with C > 0, and a row whose input ng accepts fails.
There are none since the arena: the seven former rows are ordinary rows (`calls_524289`, `size_*`, `c2-00312`,
`c2-05720` and `c2-00308` exact, `c2-00838` beyond 12). Each K is omc's exit as measured with the pinned omc. om2
fmt units get all of omc's checks (`fe_fmtprep`) and no formatted text.
An input of any size the arena holds is read whole (cases `size_*`, newlines only: both compilers' error 16). The
one input edge that is main.om's: a stdin read error is `ng: refused class 27` (omc: error 1).

Without a run-time pool declaration, `enlarge` (keyword 244, omc pools landing 1) is reserved and its misuses receive omc's same code and line (`cases/pool_enlarge_*.om`); pool `len`, `get`, `put`, `read` and `write` add no words or non-pool forms.

## Gate

    seed/out/omc < seed/ng/front/gate-front.om > gate-front
    gate-front seed/out/omc 106558ba36e28d1a55384b9e2e1387ec429ff267bb03f1215f86c9c03ca64bed \
      units:seed/ng/ng.units+in:seed/ng/front/front-check.in \
      seed/ng/front/declared.txt seed/ng/front/mutants.txt SCRATCH seed/ng/front/cases-front.txt \
      seed/ng/front/cases-om2.txt seed/ng/front/cases-tests.txt seed/qualification/om2/manifest-c2.txt \
      seed/ng/front/cases-fconv.txt seed/ng/front/cases-host.txt

The source is `units:seed/ng/ng.units`: the units that list names, concatenated in its order, so a
stage lane's unit (src/a64.om on the slice branches) comes with the list and no gate command changes
(`ngbuild build`, below, checks their sha256 pins; this gate does not);
`in:front-check.in` puts the mode line `@ng front-check` before each case
on ng's stdin, while omc reads the case alone. A wrong mode line makes every case FAIL.

Cases: `cases-front.txt` (f64 rem/and/or/xor, the gate15 refusal cases error-codes.reg names, omc.om,
the ng-front tools and each ng unit alone, the input-size edges, 524288, 524289 and 1000000 calls in one function,
and `diag_big`, an om2
`diag` unit whose 96955 stderr bytes are compared in full: omc and ng each write stderr to their own
descriptor and the gate compares the two in 65536-byte chunks), `cases-om2.txt` (every .om under
seed/omc/om2), `cases-tests.txt` (seed/omc/tests), and the frozen C2 manifest (5876 units). Mutants
(`mutants/`): m_scope (s_end forgets to restore the name table), m_fltop (f64 accepts rem/and/or/xor),
m_fmtcr (om2 fmt misses a CR), m_sitebyte (one site-record byte past 65536 corrupted), m_callcap (the
old 524288-entry call table again: `calls_524289` and `calls_1000000` fail); each must be KILLED.
Units far past every old table, run to their answers through `@ng a64`, are the no-caps gate's
(`seed/ng/tests/nocaps/gate.om`; seed/ng/README.md, No-caps gate).

The gate runs on the Spark; there is no GitHub workflow for it. Build ng through its pins and check that
the gate's checker (`SCRATCH/fecheck`) is byte-for-byte that ng:

    cat seed/ng/sha256.om seed/ng/ngbuild.om | seed/out/omc > ngbuild
    ngbuild build seed/out/omc seed/ng/ng.units ng
    cmp ng SCRATCH/fecheck

Host runs are recorded in the lane's READY files.

## @ng front-ir (M1)

The lowering is a second walk over the source after `fe_check` accepted it, reusing the front end's
tokenizer, number parser and function table. Each Omega function becomes an ΩIR function (handle =
front index + 1); `fn main to int` is the program entry (kind 2, IR.md D11). Values are SSA: a join
(if merge, loop head, `for` latch, `break` target) is a block whose parameters are the token and every
scalar name in scope; branch targets are fresh blocks that take only the token. The checks omc makes at
run time become ΩIR check ops (IR.md s13): signed add/sub/mul overflow, div/rem by zero and signed
minimum div -1, shift and rotate amounts, signed shl and neg, `get`/`put` bounds, `read`/`write` slices,
failing conversions, and `while` fuel (1000000 passes, or its `bound`). Local and global arrays are
`alloca`/`gaddr` references; texts are class 1 globals.

What it does not lower exits 64 with `ng: front-ir: line N: not lowered` (no output): units without
`fn main to int` (ΩIR needs a program entry; omc writes no executable for them either), a bool or float
shift amount, and every construct outside the M1 subset (read from code: the `fe_lno` call sites).
Sized array parameters are `REF` with access 1 even for `view`, since ΩIR v1 has no op that narrows a
REF's access (so a text passed to a sized `view` parameter is not lowered); PROPOSED for ng-ir: a `view`
op from an access-1 to an access-0 reference. Unsized (`*`) parameters are `SLICE`s of their own access
(0 `view`, 1 `edit`); `len` of one is the `len` op. An argument for one is the caller's slice when the
access matches, else `slice` over the whole array, and `part A o k` is `chk.slice` (trap 3, omc's two
part checks in one) then `slice`. `unroll` loops lower as plain `for` loops and `inline` functions as
calls: both are omc code-shape choices with the same results.

Gate (Omega, `gate-front-ir.om`; the scratch directory must not exist):

    cat seed/ng/sha256.om seed/ng/front/gate-front-ir.om | seed/out/omc > gate-front-ir
    gate-front-ir seed/out/omc 106558ba36e28d1a55384b9e2e1387ec429ff267bb03f1215f86c9c03ca64bed \
      SCRATCH seed/ng/front/cases-front-ir.txt

It builds ng (the units of `seed/ng/ng.units`), ngcheck and ngrun with the pinned omc, then for each `run`
case compiles the unit with omc and runs it, lowers it with ng, requires ngcheck ACCEPT, runs the ΩIR with
ngrun and compares exit status and stdout (stderr is free: the kernels time themselves there); for each
`refuse` case ng's exit and stderr must equal omc's with empty stdout. Cases: the 15 run pairs of
`seed/ng/tests/ir`, two default-fuel run units of `cases/` (`fuel_while`, `fuel_for`: no bound, trap 4
after 1000000 passes), two signed `for` latch units of `cases/` (`for_latch_i8`, `for_latch_i64`: the body
writes the counter's maximum and the latch's add 1 traps 1, as omc's does; fe_lendl adds it under chk.add),
two slice cases (`runs/p-part.om`, its `part` traps 3, and `runs/p-partok.om`), the
thirteen ng-bench kernels (the OM-2 crypto units sha, chacha, x25519 last), six mixed-shift and fma run
units of `cases/` (below), 33 refusal units of `cases/`, the float-to-integer cases below, and the host-word cases (`host` rows, below). ngrun interprets (90-470x native) and has no step cap yet, so twelve kernels run as reduced
copies (`runs/`, loop counts and sizes only, `runs/PROVENANCE.md` lists each change; approved by the
queen) and matmul verbatim. The full-size kernels stay verbatim in `kernels/` (`kernels/PROVENANCE.md`).
No standing gate compares all of them at full size: ng-a64's rgate front phase (ng/slice-m1, list `tfr`)
runs only the nine integer kernels (arith, branch, leafcall, fib38, fib40, isort, sieve, sort, matmul)
natively against omc; linear (f64, rgate list `tfz`) is refused by a64, and sha, chacha and x25519 are in
no rgate list. Full size for those four is one-off ngrun-vs-omc evidence recorded with the hand-off, not a gate.
Every child the gate starts is killed after 600 s: that case prints `NOT_RUN` and counts in `notrun=`, never
as ok, FAIL, a kill or a trip. Negative controls: five lowering mutants (the `for` latch adds 2;
`and`/`or`/`xor` shifted to the next op; a `part`'s offset and count swapped; a mixed-type shift amount
checked against its own width instead of the value's; fma's second and third operands swapped) must fail a
run case, two host mutants (a `long` host argument lowered as `int`; `chk.bounds` in place of a host
slice's `chk.slice`) must fail a host case, fmin and fmax swapped must fail a run case,
`@ng front-check` mode must fail the first run case (no ΩIR) and `@ng ir-copy` mode the first refusal case.
Last line `FRONTIRGATE PASS|FAIL|NOT_RUN cases=N run=R refuse=F host=H classed=Q ... notrun=U`, exit 0, 1 or 4 (NOT_RUN: no failure but U > 0,
never PASS).

### Float-to-integer conversion

A float source converts with the total IR `conv` (op 36) and no `chk.conv`: like omc's `fp_toint` it
truncates toward zero, saturates to the destination's range and maps NaN to 0 (`fe_lcf` answers false for a
float source). Integer-to-integer narrowing keeps its `chk.conv` (trap 5). Before this, front-ir emitted
`chk.conv` for a float source, so an out-of-range or NaN conversion trapped 5 where omc saturates
(CompilerBugHunt, ledger L1060; NgFrontFull). Cases at the end of `cases-front-ir.txt`: 160 programs
`runs/fconv-TYPE-FLOAT-EDGE.om` (f32 and f64 to each of the eight integer types: the destination's minimum
and maximum and a value past each, NaN, both infinities, both-sign fractions and -0), each writing all
eight bytes of the converted value so a wrong upper byte is seen, plus `seed/omc/tests/float/convert_sat.om`;
`runs/fconv-bad-bool.om` (float to bool) must be refused as omc refuses it. The input bounds are derived in
`float-bounds.txt` (Wolfram). `cases-fconv.txt` puts the same units through gate-front's check parity.

## Mixed-type shifts and fma

omc admits `shl`/`shr` with an integer value and an integer amount of another type (only a shift may mix
its operand types) and compares the amount's 64-bit register, sign- or zero-extended by its type, unsigned
with the value's width (`bo_schk`, trap 7): a negative amount traps like a wide one, and none is wrapped.
`fe_lsham` lowers the amount to `conv` u64, `lt` the width, `chk.true 7` and `conv` to the value's type,
exact because the amount is then below the width; `fe_lbop`'s checks follow unchanged. `fma a b c` lowers
to ΩIR `fma` (46, one rounding) on three values of one float type. Run cases `cases/sh_mix*.om` and
`cases/fma_mix.om`; their exits and stdout bytes, worked out before the run (constants from Wolfram), are in
`cases/groups4.expect`. omc's refusals `rot_mix` (a rotate keeps one type, 7), `fma_lit` (11) and
`fma_types` (7) are refuse cases. A bool or float shift amount, which omc also admits, stays not lowered; the scope
gate keeps it failing closed, and its bool-amount admission mutant must be KILLED:

    gate-front seed/out/omc 106558ba36e28d1a55384b9e2e1387ec429ff267bb03f1215f86c9c03ca64bed \
      units:seed/ng/ng.units+in:seed/ng/front/front-ir.in \
      seed/ng/front/declared-lower-scope.txt seed/ng/front/mutants-lower-scope.txt SCRATCH \
      seed/ng/front/cases-lower-scope.txt

## fmin and fmax

`fmin a b` and `fmax a b` lower to ΩIR `min` (24) and `max` (25) on two values of one float type (`fe_lfmm`);
IR.md s7.3 gives them OMEGESE's FMINNM/FMAXNM meaning: one quiet NaN gives the other operand, a signaling
NaN gives that NaN quieted, two quiet NaNs give the first, and -0 is below +0. Run case `cases/fmm_mix.om`
writes the bits of 28 results (f32 and f64: ordered values, signed zeros in both orders, quiet and signaling
NaNs with a number in both orders, two quiet NaNs); its 168 bytes, worked out before the run, are in
`cases/groups6.expect`. `lsc_fmin` and `lsc_fmax`, the former lower-scope cases, are run cases now. The
min/max swap mutant (8) must fail a run case.

## Host words

Every host word of `seed/ng/hostwords.tsv` (94, the words omc's keyword table admits as host operations at
the pin) lowers to ΩIR `host` (op 110, IR.md s7.11) with the word's keyword id as imm and ty i64; `cpufence`
and `cpurelax` are statements with ty 0. read, write, monons and realns keep their earlier paths; `fe_lhost`
takes the other 88 from the table's argument letters (`fe_lhfmt`, generated from the table): `i` int, `l`
long, `L` ulong, `u` a uint constant (omc requires a literal), and `r`, `w`, `S` a byte array name followed by
off and n (ulong), with `chk.slice` on the three where omc checks the slice, before the next argument is read.
mapaddr and mapget are ulong in omc: their i64 result is `conv`ed with the same bits. The check pass gained
execenv (233) and prlimit (235), which the pinned omc admits: execenv goes through `fe_hpack` with omc.om
hpack's second packet (the environment), its two pre-stack trap sites and one record scan per packet;
prlimit through `fe_hprlim` (int pid, int resource, writable byte slice; no trap site of its own).

Cases: `cases-host.txt` (the 94 programs `runs/host-WORD.om`, five refusals `runs/bad-host-*.om` and two
`om2 diag` units `runs/diag-host-*.om`) in gate-front's check parity; in `cases-front-ir.txt` one
`host NAME SRC C` row per word and the five refusals as `refuse` rows. A `host` row compiles and runs the
unit with omc (empty stdin, the repository root as working directory: the programs name only empty or
`/dev/null` paths and invalid descriptors; none opens a device), lowers it, requires ngcheck ACCEPT and runs
the ΩIR with `ngrun --scratch SCRATCH/hK` (a new directory each run). C 0: exit and stdout equal the
binary's. C 115..123: ngrun refuses the word by that class (IR.md s7.11: process, limits, device, network,
outside scratch, nondeterministic, unsafe filesystem) with exit C and no stdout, so that program's ΩIR is
checked but not executed: behavior parity for it stays NOT_RUN. The C column follows IR.md's table and
trap-first rules (empty paths are not one path component: 119; malformed packets and empty stat paths
trap 3 natively and in ngrun: 0; a negative descriptor gets -9 without a kernel call in both: 0).

## Native contracts: fail-closed lowering boundary

The check pass validates native contracts, but the M1 lowering does not implement them. Every
`requires`, `ensures` and `invariant` clause is therefore refused in front-ir with the existing
not-lowered exit 64, before any IR is written. A short clause word must never be interpreted as
an ordinary assignment that silently removes its runtime check. OM-1 names retain their meaning.

The four scope cases in `cases-contract-scope.txt` are accepted by omc but must be refused by
the lowering. Reuse the existing gate-front with its lowering-mode input and dedicated declarations:

    gate-front seed/out/omc 106558ba36e28d1a55384b9e2e1387ec429ff267bb03f1215f86c9c03ca64bed \
      units:seed/ng/ng.units+in:seed/ng/front/front-ir.in \
      seed/ng/front/declared-contract-scope.txt seed/ng/front/mutants-contract-scope.txt SCRATCH \
      seed/ng/front/cases-contract-scope.txt

Its guard-removal mutant restores the silent path and must be KILLED. This is a scope-safety gate,
not contract execution parity. Before the guard, these fixtures emitted IR and ran without the
required trap. Real lowering must replace this boundary with chk.true checks at entry, every
normal return and each loop head, with the seeded debug/release policy and trap codes.
