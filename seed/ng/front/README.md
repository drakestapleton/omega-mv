# seed/ng/front: the ng-front lane (Hive NG)

`seed/ng/src/front.om` is the ng front end: the lexer, parser and language checks of
`seed/omc/omc.om` @943d9555 with every machine-code path removed. It is a unit of `seed/ng/ng.units`
(after `ir.om`, so it is OM-2 code) and runs as the ng mode `@ng front-check` (`src/main.om`): the
payload is an Omega unit, and ng must refuse exactly what omc refuses, on the same line with the same
error code, and accept what omc accepts (DECISIONS D5, D6, D9). It writes no program yet; ΩIR
emission through `src/ir.om` is the next step.

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
`beyond` rows in `declared.txt` (`NAME beyond K REASON`), and the gate requires omc to exit exactly K
and ng to exit 0. Whether ng then compiles them correctly needs an independent referee (expected output
or a C twin): NOT_RUN until ng emits code. The value slots of `fe_alloc` keep omc's pool numbering
without the cap (slots past 16 share a number); ΩIR values replace them.

Units ng does not take exit 64 and are `scope` rows (`NAME scope K REASON`, omc must exit K): x86/EFI
targets (D8) and IR v1 units (first line `ir`). A bound of ng's own that omc never reaches because
another omc limit refuses first is an `ngonly` row (`NAME ngonly K REASON`): both must exit K, and
their stderr lines differ. The one today is ng's 524288-entry call table (`calls_524289`; omc stops at
its 8192-entry trap-site table, so `calls_524288` is a beyond row). Each K is omc's exit as measured
with the pinned omc. om2 fmt units get all of omc's checks (`fe_fmtprep`) and no formatted text.
Input of 8388608 bytes or more is error 14 as in omc (cases `size_*`); the one input edge that is
main.om's: a stdin read error is `ng: refused class 27` (omc: error 1).

## Gate

    seed/out/omc < seed/ng/front/gate-front.om > gate-front
    gate-front seed/out/omc 5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df \
      seed/ng/src/ir.om+seed/ng/src/front.om+seed/ng/src/main.om+in:seed/ng/front/front-check.in \
      seed/ng/front/declared.txt seed/ng/front/mutants.txt SCRATCH seed/ng/front/cases-front.txt \
      seed/ng/front/cases-om2.txt seed/ng/front/cases-tests.txt seed/qualification/om2/manifest-c2.txt

The source is the units of `ng.units` in order (CI also builds ng through `ngbuild build`, which
checks their sha256 pins); `in:front-check.in` puts the mode line `@ng front-check` before each case
on ng's stdin, while omc reads the case alone. A wrong mode line makes every case FAIL.

Cases: `cases-front.txt` (f64 rem/and/or/xor, the gate15 refusal cases error-codes.reg names, omc.om,
the ng-front tools and each ng unit alone, the input-size and call-table edges, and `diag_big`, an om2
`diag` unit whose 96955 stderr bytes are compared in full: omc and ng each write stderr to their own
descriptor and the gate compares the two in 65536-byte chunks), `cases-om2.txt` (every .om under
seed/omc/om2), `cases-tests.txt` (seed/omc/tests), and the frozen C2 manifest (5876 units). Mutants
(`mutants/`): m_scope (s_end forgets to restore the name table), m_fltop (f64 accepts rem/and/or/xor),
m_fmtcr (om2 fmt misses a CR), m_sitebyte (one site-record byte past 65536 corrupted), m_callcap (the
call table takes one call more); each must be KILLED.

CI (`.github/workflows/ng-front-arm64.yml`) also checks that the gate's checker (`SCRATCH/fecheck`) is
byte-for-byte the ng that `ngbuild` built. CI: NOT_RUN (GitHub Actions blocked). Host runs are recorded
in the lane's READY files.
