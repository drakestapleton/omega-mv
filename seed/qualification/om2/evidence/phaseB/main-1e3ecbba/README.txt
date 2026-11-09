L836 regression run of the #748 OM-2 qualification on omega-mv main 1e3ecbba, 2026-11-09
=========================================================================================
Tree: main 1e3ecbba779ee84e2de70ec231e83533a9c61f45 plus the two mutant re-anchors in this commit
(fixtures/PROVENANCE.txt, re-pin 2026-11-09). Host: GB10 Linux AArch64, one CPU core (taskset 19).
Compiler: `sh seed/omega-from-seed.sh` on a clean `git archive` of the tree, rc 0, born omc
sha256 6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8 = committed seed/out/omc.sha256.
Gate: gate.om built by that omc, sha256 49914d72313d9b0e3693dc52119658c81d6f955af29d24551275b5e4f7936caf.
Command (repository root): sh seed/qualification/om2/evidence/phaseB/main-1e3ecbba/run.sh build/omc-born OUT
Logs: logs/<list>.log, totals in logs/summary.txt.

Comparison with the last recorded per-slice run (evidence/phaseB/s4-f6a6492f, S4 head):
  s0s2 (sections 0-2)      161 PASS 0 FAIL 2 NOT_RUN   per-case verdicts identical
  s3s4 (sections 3-4)      202 PASS 0 FAIL 3 NOT_RUN   identical
  s4fuel (E14/E16)         8/8 PASS                    identical
  s5s7 (sections 5-7)      99 PASS 0 FAIL 48 NOT_RUN   identical to s4-f6a6492f/s5s7-with-e17.log (147 rows;
                                                       48 = ABI-driver, OM-2 SHA and 2^64-1 rows)
  S1 rotate mutants        26/26 PASS                  identical after the rol-reg-as-ror re-anchor
  S1 lexer/fmt/diag        6 PASS, 15 FAIL             identical (each FAIL is a killed mutant row)
  S2 mutants               9 PASS, 8 FAIL              identical (unroll+1 refused 21; fold-div0 survives
                                                       the selectors for other traps, as recorded)
  S3 mutants               17/17 PASS                  identical
  S4 view-nocheck          4/4 PASS                    identical
  S4 part mutants          20/20 PASS                  the 16 recorded rows identical; the 4 part-order
                                                       rows (added after that run) now run: healthy
                                                       compiler traps 102, mutant 105
Harness controls: selftest pass 4/4; fail, controls and emit give the intended FAIL/INVALID rows (verdicts
identical to evidence/phaseA); sec/s3s4/mutant-kills.cases under the unmutated compiler is 31/31 FAIL
(no false kills); a wrong compiler pin makes the gate INVALID, exit 3, with every case NOT_RUN.
leak/leak.cases is the list for the OM-1 compiler 734f0a39: its one FAIL, s1-rot-refused, expects OM-1 to
refuse the om2 opt-in, which an OM-2 compiler accepts by contract. leak/candidate.cases is the OM-2 list:
37 PASS, 1 NOT_RUN (sha256-om2-scan).

Before the re-anchor (same tree, same compiler) two mutants could not be applied: rol-reg-as-ror
(exact-once substitution matched 0 times: #923 put an x86 branch between `rr = alloc` and the RORV
NEG) and part-order (arrpart now accepts operand type 5 or 13), plus ctl-part-order-sha named the
deleted om/sha256/sha256.om. The gate reported them INVALID, never as kills.
NOT_RUN here: x86, GPU, native ABI driver rows (already NOT_RUN in the slice verdicts).
