# seed/ng/front: the ng-front lane (Hive NG)

`seed/ng/src/front.om` is the ng front end: the lexer, parser and language checks of
`seed/omc/omc.om` @943d9555 with every machine-code path removed. It must refuse exactly what omc
refuses, on the same line with the same error code, and accept what omc accepts (DECISIONS D5, D6,
D9). It writes no program; ΩIR emission through `src/ir.om` is the next step (PR2).

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

From the first commit on, `src/front.om` is edited directly; the tools stay as the record of how it
was derived. The gate checks the result, not the derivation.

## What is not reproduced (D6)

omc refusals that come from its AArch64 code generator are not language rules: error 12 (16-register
expression pool), 14 for trap sites, 24 (branch displacement range). ng accepts such units; they are
`beyond` rows in `declared.txt`, and the gate requires omc to exit 12, 14, 24 or 25 there and the
checker to exit 0. Whether ng then compiles them correctly needs an independent referee (expected
output or a C twin): NOT_RUN until ng emits code. The value slots of `fe_alloc` keep omc's pool
numbering without the cap (slots past 16 share a number); ΩIR values replace them in PR2.

Units ng does not take exit 64 and are `scope` rows: x86/EFI targets (D8) and IR v1 units (first line
`ir`). om2 fmt units get all of omc's checks (`fe_fmtprep`) and no formatted text.

## Gate

    seed/out/omc < seed/ng/front/gate-front.om > gate-front
    gate-front seed/out/omc 5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df \
      seed/ng/src/front.om+seed/ng/front/check.om seed/ng/front/declared.txt seed/ng/front/mutants.txt \
      SCRATCH seed/ng/front/cases-front.txt seed/ng/front/cases-om2.txt seed/ng/front/cases-tests.txt \
      seed/qualification/om2/manifest-c2.txt

Cases: `cases-front.txt` (f64 rem/and/or/xor, the gate15 refusal cases error-codes.reg names, omc.om
and these sources), `cases-om2.txt` (every .om under seed/omc/om2), `cases-tests.txt` (seed/omc/tests),
and the frozen C2 manifest (5876 units). Mutants (`mutants/`): m_scope (s_end forgets to restore the
name table), m_fltop (f64 accepts rem/and/or/xor), m_fmtcr (om2 fmt misses a CR); each must be KILLED.

Local run, Spark (aarch64, Linux 7.0.0-1019-nvidia), core 1, omc sha256 5f90edea…6df, base 6d3f0c1c:

    CHECKER fecheck sha256=6c8cd9e964358f37665af3cc5c87a7f759bea799c9186a04968905489b64fd26
    KILLED m_scope at seed/omc/omc.om
    KILLED m_fltop at seed/ng/front/cases/float_and.om
    KILLED m_fmtcr at seed/omc/om2/s1/bad-fmt-cr.om
    FRONTGATE PASS cases=6315 exact=6200 beyond=10 scope=105 fail=0 mutants=3 killed=3

CI (`.github/workflows/ng-front-arm64.yml`): NOT_RUN (GitHub Actions blocked).
