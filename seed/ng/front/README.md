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

## What is not reproduced (D6)

omc refusals that come from its AArch64 code generator are not language rules: error 12 (16-register
expression pool), 14 for trap sites, 24 (branch displacement range). ng accepts such units; they are
`beyond` rows in `declared.txt`, and the gate requires omc to exit 12, 14, 24 or 25 there and ng to
exit 0. Whether ng then compiles them correctly needs an independent referee (expected output or a C
twin): NOT_RUN until ng emits code. The value slots of `fe_alloc` keep omc's pool numbering without
the cap (slots past 16 share a number); ΩIR values replace them.

Units ng does not take exit 64 and are `scope` rows: x86/EFI targets (D8) and IR v1 units (first line
`ir`). om2 fmt units get all of omc's checks (`fe_fmtprep`) and no formatted text. Input of 8388608
bytes or more is error 14 as in omc (cases `size_*`); the one input edge that is main.om's: a stdin
read error is `ng: refused class 27` (omc: error 1).

## Gate

    seed/out/omc < seed/ng/front/gate-front.om > gate-front
    gate-front seed/out/omc 5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df \
      units:seed/ng/ng.units+in:seed/ng/front/front-check.in \
      seed/ng/front/declared.txt seed/ng/front/mutants.txt SCRATCH seed/ng/front/cases-front.txt \
      seed/ng/front/cases-om2.txt seed/ng/front/cases-tests.txt seed/qualification/om2/manifest-c2.txt

The source is `units:seed/ng/ng.units`: the units that list names, concatenated in its order, so a
stage lane's unit (src/a64.om on the slice branches) comes with the list and no gate command changes
(CI also builds ng through `ngbuild build`, which checks their sha256 pins; this gate does not);
`in:front-check.in` puts the mode line `@ng front-check` before each case
on ng's stdin, while omc reads the case alone. A wrong mode line makes every case FAIL.

Cases: `cases-front.txt` (f64 rem/and/or/xor, the gate15 refusal cases error-codes.reg names, omc.om,
the ng-front tools and each ng unit alone), `cases-om2.txt` (every .om under seed/omc/om2),
`cases-tests.txt` (seed/omc/tests), and the frozen C2 manifest (5876 units). Mutants (`mutants/`):
m_scope (s_end forgets to restore the name table), m_fltop (f64 accepts rem/and/or/xor), m_fmtcr
(om2 fmt misses a CR); each must be KILLED.

CI (`.github/workflows/ng-front-arm64.yml`): NOT_RUN (GitHub Actions blocked). Host runs are recorded
in the lane's READY files.

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
`fn main to int` (ΩIR needs a program entry; omc writes no executable for them either), mixed-type
shifts, and every construct outside the M1 subset (read from code: the `fe_lno` call sites).
Sized array parameters are `REF` with access 1 even for `view`, since ΩIR v1 has no op that narrows a
REF's access (so a text passed to a sized `view` parameter is not lowered); PROPOSED for ng-ir: a `view`
op from an access-1 to an access-0 reference. Unsized (`*`) parameters are `SLICE`s of their own access
(0 `view`, 1 `edit`); `len` of one is the `len` op. An argument for one is the caller's slice when the
access matches, else `slice` over the whole array, and `part A o k` is `chk.slice` (trap 3, omc's two
part checks in one) then `slice`. `unroll` loops lower as plain `for` loops and `inline` functions as
calls: both are omc code-shape choices with the same results.

Gate (Omega, `gate-front-ir.om`; the scratch directory must not exist):

    cat seed/ng/sha256.om seed/ng/front/gate-front-ir.om | seed/out/omc > gate-front-ir
    gate-front-ir seed/out/omc 5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df \
      SCRATCH seed/ng/front/cases-front-ir.txt

It builds ng (the units of `seed/ng/ng.units`), ngcheck and ngrun with the pinned omc, then for each `run`
case compiles the unit with omc and runs it, lowers it with ng, requires ngcheck ACCEPT, runs the ΩIR with
ngrun and compares exit status and stdout (stderr is free: the kernels time themselves there); for each
`refuse` case ng's exit and stderr must equal omc's with empty stdout. Cases: the 15 run pairs of
`seed/ng/tests/ir`, two slice cases (`runs/p-part.om`, its `part` traps 3, and `runs/p-partok.om`), the
thirteen ng-bench kernels (the OM-2 crypto units sha, chacha, x25519 last) and 30 refusal units of
`cases/`. ngrun interprets (90-470x native) and has no step cap yet, so ten kernels run as reduced
copies (`runs/`, loop counts and sizes only, `runs/PROVENANCE.md`; each under 25 ms native); matmul,
chacha and x25519 run verbatim; the verbatim kernels (`kernels/`, `kernels/PROVENANCE.md`) stay for the
a64-vs-omc comparison.
Every child the gate starts is killed after 600 s: that case prints `NOT_RUN` and counts in `notrun=`, never
as ok, FAIL, a kill or a trip. Negative controls: three lowering mutants (the `for` latch adds 2;
`and`/`or`/`xor` shifted to the next op; a `part`'s offset and count swapped) must fail a run case,
`@ng front-check` mode must fail the first run case (no ΩIR) and `@ng ir-copy` mode the first refusal case.
Last line `FRONTIRGATE PASS|FAIL|NOT_RUN ... notrun=U`, exit 0, 1 or 4 (NOT_RUN: no failure but U > 0,
never PASS).
