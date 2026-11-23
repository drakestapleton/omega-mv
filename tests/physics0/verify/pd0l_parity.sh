#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0l_parity.sh -- differential qualification of the OM-2 ports of the PD-0 ladder checker and scorer
# (src/physics0/ladder/pd0_ladder.om, src/physics0/score/pd0_score.om with its memoriser mode 1) against
# the live C they port (src/physics0/ladder/pd0_ladder.c, src/physics0/score/pd0_score.c and the
# memoriser of src/physics0/controls/pd0_controls.c; the learners and planner link the C), on the same
# evidence ledgers and scoring sets.
#
# Every corpus runs through tests/physics0/verify/pd0l_dump.om (built from P0V_OM_VERIFY of
# mk/physics0-verify.mk and the test bundle builder tests/physics0/verify/pd0_bundle.om) and is
# compared byte for byte with tests/physics0/verify/ladder_golden/<corpus>.out.gz (gzip -9n, so the
# directory holds about 0.4 MB instead of 6 MB; the MANIFEST hashes the .gz files): the ledger each bundle
# produces (length and sha256), the whole ladder report (state, codes, counts, candidate hash, eps,
# chain root, entry and record counts, the last NRMSE, void counts, the last r and p as IEEE-754 bits),
# the law the report supports (PDLAW1 bytes, which carry the domain, exceptions, experiments and
# relation) and its claim text, every T8 verdict on tampered, saved and fabricated laws, the
# statistics (Pearson r and permutation p as bits, NRMSE plain and pooled), the parameter defaults,
# state names, confidence, and every scorer result (code, fail mask, NRMSEs, reference NRMSE, size,
# bits) and reference fit. The goldens were generated ONCE from the C at main commit 3f2c70dc5
# (identical to the live C) by the reference-only C dumper tests/physics0/verify/pd0l_dump.c (committed
# once, then removed); ladder_golden/MANIFEST records the commit, the generator and the sha256 of every
# corpus and golden. This script needs no C compiler.
#
# Corpus commands (one per line, decimal numbers, '-' allowed; '#' and blank lines skipped):
#   b lv seed [opt val]...  build the bundle (bundle.h b_build) with options 0..20 (bundle_opts in order:
#                           skip_corr fake_corr no_rival reuse_schedule trial_without_prereg wrong_k
#                           rep_before_candidate batch_seed_reuse all_planner eps_above_bound
#                           stop_after_prereg stop_after_trials demote_after_law null_world null_seed
#                           end_last quiet_trials obs_noise void_rep void_rep_four void_trial), check it
#   i lv seed      a fresh empty bundle         c   check the ledger as it is
#   x off v | X off | z n   set a ledger byte, flip its low bit, cut the ledger to n bytes
#   e n            an episode of n steps of the truth world     O n  OUT_OF_BOUNDS at step n of the next ones
#   g ep tag batch origin | G tag batch origin   a harness tag (G: for the next episode)
#   B id seed nep  a batch entry     H hex | a kind   load a payload, append it as an entry of that kind
#   Q field v      set a ladder parameter (0..16 in pd0_ladder_params order)   d nobs nch  the defaults
#   L | v          save the current law, verify it against the current report
#   t k            T8 on the current law: parse, tamper (0 conf, 1 forbidden claim, 2 claim text, 3 one
#                  experiment fewer, 4 chain root, 5 relation, 6 domain, 7 exceptions, 8 state, 9 none),
#                  write and verify; 12 HYPOTHESIS, 13 REFUTED, 14 REJECTED state, 15 one refutation more;
#                  10 flip the last byte, 11 cut it by one byte
#   f              a fabricated PROVISIONAL_LAW with no evidence (M4)
#   s state | k p f | r n seed mode nshuf pseed | q n nobs seed sdmode noise obsmode   names and stats
#   S lv seed eseed nin nex fseed nep steps cap   scoring set (truth.h)
#   o k [a b]      score: 0 oracle, 1 M1 scale a/b, 2 M2 pad a terms of b, 3 memoriser, 4 a degree 4 term,
#                  5 bits + 1, 6 reference fit with a terms, 7 latent-free form, 8 n_vars 3, 9 two
#                  channels, 10 one more latent, 11 the oracle with a stored numbers, 12 its first s1 term zeroed
#   u field v [i]  set a score parameter (0 inbox 1 extrap 2 onestep 3 score_constants 4 const_tol 5
#                  require_latent 6 latent_ref_factor 7 size_bound 8 n_true_terms 9 true coef[i] 10 true
#                  expo[i][0] 11 n_fit 12 in_box[i] 13 n_eps)    F mt nobs nch  the reference fit alone
#   C va vb nshuf seed npairs fake epmax   a correlation entry over the bundle's records (x: s<va> before
#                  a step, y: the change of s<vb>, episodes below epmax): fake 0 honest, 1 r 0.9 p 0.0001,
#                  2 one pair more, 3 nothing computed (r = p = 0, no pairs), 4 r off by 0.0015, 5 p 0.015
#   R role mode [num den]   a relation entry: mode 0 the oracle, 1 the oracle with a degree-4 term, 2 the
#                  null relation, 3 the oracle with k scaled by num/den
#   K slot | A nriv eps mint cslot rslot...   remember the last entry hash; a falsifier (slot 9: zeros)
#   P nhyp | T     a preregistration (oracle and null predictions) of a fresh schedule; its trial episode
#   W num den      scale the truth world's k by num/den
# The bundle builders are test code on both sides (bundle.h, truth.h and pd0_bundle.om); a difference in
# what they build shows in the ledger line before any verdict. Inputs stay where the C is defined: no
# tamper 3 on a law without experiments, no permutation test on zero pairs, at most 32 scoring episodes,
# no void_rep together with void_rep_four (bundle.h then crashes), no min_batches 0 (pd0_ladder.c then
# crashes). A law that does not parse is verified as written (nothing is rewritten from a failed parse).
# The OM NRMSE takes the checker's rollout shape, at most 20 rows of n_obs values ([20][8]).
#
# usage: tests/physics0/verify/pd0l_parity.sh [OMC]
#        tests/physics0/verify/pd0l_parity.sh --generate <C dumper binary>
#        tests/physics0/verify/pd0l_parity.sh --corpora <dir>   (write the corpora only)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
GOLD=$ROOT/tests/physics0/verify/ladder_golden
GEN=""; ONLY=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: pd0l_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
elif [ "${1:-}" = "--corpora" ]; then
  ONLY=${2:?usage: pd0l_parity.sh --corpora <dir>}
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${PD0L_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/physics0/verify/pd0l_corpus.txt "$C/hand.txt"
# Bundle options: every option alone on levels 1, 2, 4, 6 and an unknown level, seeds 1..3; every
# pair of options on level 1; observation noise at three sizes.
awk 'BEGIN { split("1 2 4 6 9", lv, " ");
       for (l = 1; l <= 5; l++) for (s = 1; s <= 3; s++) { print "b " lv[l] " " s;
         for (o = 0; o <= 20; o++) { if (o == 14 || o == 17) continue; print "b " lv[l] " " s " " o " 1" }
         print "b " lv[l] " " s " 13 1 14 " (100 + s); print "b " lv[l] " " s " 17 " (s * 9000) }
       for (o = 0; o <= 20; o++) for (p = o + 1; p <= 20; p++) { if (o == 14 || o == 17 || p == 14 || p == 17 || (o == 18 && p == 19)) continue; print "b 1 1 " o " 1 " p " 1" }
       print "b 1 2 16 1 17 5000"; print "b 2 2 17 100000"; print "b 4 1 16 1 17 60000 15 1" }' > "$C/gen-opts.txt"
# Ladder parameters: each field of pd0_ladder_params set to values around and past its default on
# the honest level 1 bundle, on a bundle that stops after the trials, and on a noisy one.
awk 'BEGIN { v[0] = "1 2 3"; v[1] = "0 1 2"; v[2] = "0 1"; v[3] = "-2000000 -1000000 0 1000000"; v[4] = "-1000000 0 1000000 2000000";
       v[5] = "-1000000 0 1000000"; v[6] = "-1000000 0 1000000"; v[7] = "0 20 50 99 100 101 200"; v[8] = "0 1 49999 50000 50001";
       v[9] = "0 1 2 3 4 5 6 100"; v[10] = "0 1 10000 19999 20000 20001 50000 1000000"; v[11] = "0 99 100 101 1000 100000";
       v[12] = "0 4 5 6 7 8 9 10 11"; v[13] = "0 1 4 5 6 9 100"; v[14] = "1 2 3 4 32 33"; v[15] = "0 1 9 10 11 100";
       v[16] = "1 2 19 20";
       split("b 1 1|b 1 1 11 1|b 2 3 17 20000|b 1 2 12 1", bs, "|");
       for (k = 0; k <= 16; k++) { n = split(v[k], vv, " "); for (i = 1; i <= n; i++) for (q = 1; q <= 4; q++) { print bs[q]; print "Q " k " " vv[i]; print "c" } } }' > "$C/gen-params.txt"
# Ledger damage: the honest bundle cut to every 2071st length and the first 64 lengths, then the low
# bit of every byte of the first 4 KiB and of every 997th byte after it flipped (and flipped back).
awk 'BEGIN { print "b 1 1"; for (n = 414534; n >= 0; n -= 2071) { print "z " n; print "c" }
       print "b 1 1"; for (n = 64; n >= 0; n--) { print "z " n; print "c" }
       print "b 1 1 11 1"; for (o = 0; o < 4096; o += 1) { print "X " o; print "c"; print "X " o }
       for (o = 4096; o < 420000; o += 997) { print "X " o; print "c"; print "X " o } }' > "$C/gen-damage.txt"
# Hand-made ledgers: entries of every kind out of order, malformed payloads of every kind and length,
# unknown kinds, extra episodes, tags and batches after a law, too many batches, void episodes.
awk 'BEGIN { seed = 7;
       for (k = 0; k <= 9; k++) for (n = 0; n <= 80; n += (n < 20 ? 1 : 15)) { print "i 1 1"; print "e 5"; print "g 0 0 0 0";
         s = "H "; for (j = 0; j < n; j++) { seed = (seed * 1103515245 + 12345) % 2147483648; s = s sprintf("%02x", int(seed / 65536) % 256) } print s; print "a " k; print "c" }
       print "i 1 1"; print "B 1 1000 10"; print "c"; print "i 2 2"; for (e = 0; e < 12; e++) print "e 100"; print "c";
       print "i 1 1"; for (e = 0; e < 3; e++) { print "G 3 0 0"; print "e 20" } print "c";
       print "i 1 1"; print "O 5"; print "e 20"; print "O 0"; print "g 0 0 0 0"; print "e 20"; print "g 1 0 0 0"; print "g 1 1 0 0"; print "g 7 0 0 0"; print "c";
       for (t = 0; t <= 6; t++) for (o = 0; o <= 2; o++) { print "i 1 1"; print "e 100"; print "g 0 " t " 3 " o; print "g 0 " t " 3 " o; print "e 30"; print "c" }
       print "b 1 1"; for (e = 0; e < 6; e++) { print "G 4 1 " (e % 2); print "e 20" } print "c";
       print "b 1 1"; for (e = 0; e < 4; e++) { print "G 3 0 0"; print "e 20" } print "c";
       print "b 1 1"; print "B 1 1000 10"; print "c"; print "b 1 1"; print "B 77 1001 10"; print "c";
       print "b 1 1"; for (b = 10; b < 45; b++) print "B " b " " (5000 + b) " 1"; print "c";
       print "b 1 1"; print "B 50 9000 2"; print "G 4 50 0"; print "O 3"; print "e 20"; print "O 0"; print "G 4 50 1"; print "e 20"; print "G 4 50 0"; print "e 20"; print "c";
       print "b 1 1 12 1"; for (e = 0; e < 3; e++) { print "G 4 9 1"; print "e 20" } print "c"; print "t 9"; print "L"; print "b 1 1"; print "v";
       print "b 1 1 5 1"; print "t 9"; print "t 7"; print "t 8"; print "b 1 1 0 1"; print "t 8"; print "t 9";
       print "i 1 1"; print "e 0"; print "e 1"; print "e 100"; print "c" }' > "$C/gen-ledgers.txt"
# Statistics: Pearson r and permutation p on independent, linear, constant and anti-linear pairs; NRMSE
# plain and pooled for every shape, sd mode, noise size and a constant series.
awk 'BEGIN { split("1 2 3 10 100 1000", ns, " "); split("0 1 10 200", sh, " ");
       print "r 0 1 0 0 1"; print "r 0 2 4 2000 3";
       for (a = 1; a <= 6; a++) for (m = 0; m <= 4; m++) for (h = 1; h <= 4; h++) print "r " ns[a] " " (a * 31 + m) " " m " " sh[h] " " (a + h);
       for (no = 1; no <= 8; no++) for (n = 0; n <= 20 && n * no <= 160; n += (n < 4 ? 1 : 4)) for (sd = 0; sd <= 3; sd++) {
         print "q " n " " no " " (n * 8 + no) " " sd " 0 0"; print "q " n " " no " " (n * 8 + no) " " sd " 1000 0";
         print "q " n " " no " " (n * 8 + no) " " sd " 4600000000000000000 0"; print "q " n " " no " " (n * 8 + no) " " sd " 5000 1" }
       for (p = 0; p <= 40; p++) for (f = 0; f <= 3; f++) print "k " p " " f; print "k 4294967294 1"; print "k 1 4294967294";
       for (s = -2; s <= 9; s++) print "s " s; for (no = 0; no <= 8; no++) for (nc = 0; nc <= 4; nc++) print "d " no " " nc }' > "$C/gen-stats.txt"
# Scorer: levels 1, 2, 4, 6 and an unknown level, three seeds, five scoring-set shapes (including fewer
# than 8 fit transitions and no extrapolation episodes), every variant, then the score parameters moved.
awk 'BEGIN { split("1 2 4 6 9", lv, " "); split("10 10 30 100 4096|5 0 30 100 4096|0 5 3 3 7|0 5 2 3 7|16 16 4 50 4096|1 1 30 100 0", sh, "|");
       for (l = 1; l <= 5; l++) for (s = 1; s <= 3; s++) for (h = 1; h <= 6; h++) { split(sh[h], x, " ");
         print "S " lv[l] " " s " " (500 + s) " " x[1] " " x[2] " " (900 + s) " " x[3] " " x[4] " " x[5];
         print "o 0"; print "o 1 110 100"; print "o 1 100 100"; print "o 1 -1 1"; print "o 2 5 1"; print "o 2 2 1"; print "o 2 3 1"; print "o 2 40 1";
         print "o 3"; print "o 4"; print "o 5"; print "o 12"; print "o 6 4"; print "o 6 1"; print "o 6 0"; print "o 6 20"; print "o 7"; print "o 8"; print "o 9"; print "o 10"; print "o 11 2";
         if (h > 1 || s > 1) continue;
         print "F 4 2 1"; print "F 0 2 1"; print "F 17 2 1"; print "F 4 1 0"; print "F 4 3 2";
         print "u 2 0"; print "o 0"; print "o 3"; print "u 3 0"; print "o 1 110 100"; print "u 3 1"; print "u 4 0"; print "o 1 1000001 1000000"; print "o 0";
         print "u 4 1000000"; print "o 1 150 100"; print "u 5 1"; print "o 0"; print "o 10"; print "u 6 0"; print "o 10"; print "u 6 1000"; print "o 10";
         print "u 11 7"; print "o 10"; print "u 11 3000"; print "u 5 0"; print "u 7 0"; print "o 0"; print "u 7 100"; print "o 2 40 1"; print "u 8 0"; print "o 0";
         print "u 8 1"; print "u 9 1 0"; print "o 0"; print "u 10 3 0"; print "o 0"; print "u 0 0"; print "u 1 0"; print "o 0"; print "u 12 0 3"; print "u 12 1 15"; print "o 0";
         print "u 13 0"; print "o 0"; print "o 3"; print "u 13 2"; print "u 11 0"; print "o 0"; print "o 3"; print "F 4 2 1";
         print "S " lv[l] " 1 501 10 10 901 30 100 4096"; print "u 5 1"; print "u 7 1"; print "o 0"; print "u 7 0"; print "o 0"; print "u 6 0"; print "o 0" } }' > "$C/gen-score.txt"
# Hand-made ladders from the entry writers: correlation claims (honest, false, other variables, too few
# shuffles, pairs or records), a degree-4 candidate, falsifiers (unknown candidate or rival, none,
# duplicate, the candidate as its own rival, after a trial), preregistrations without the rival's
# prediction, replication in a changed world, and every law state against every report.
# Boundaries: candidates whose FIT error falls just under, in and over the T3 band 50000..60000 ppm
# (R 0 3 q 100 for q = 180, 181, 190, 196, 197), and a correlation whose permutation p is just above
# 0.01 while its claimed p_micro truncates to 10000 (10098 shuffles, 101 pairs), beside p = 0.01 exactly.
awk 'function obs(ne,   e) { print "i 1 1"; for (e = 0; e < ne; e++) print "e 100"; for (e = 0; e < ne; e++) print "g " e " " (e < 6 ? 0 : e < 8 ? 1 : 2) " 0 0" }
     function upto_cand() { obs(10); print "C 1 0 2000 77 6 0 8"; print "R 0 0"; print "K 0"; print "R 2 2"; print "K 1" }
     BEGIN { split("0 1 10 99 100 1000 1999 2000", ns, " "); split("1 6 30 100 1000", np, " ");
       for (a = 0; a <= 1; a++) for (b = 0; b <= 1; b++) for (i = 1; i <= 8; i++) for (j = 1; j <= 5; j++) { obs(10); print "C " a " " b " " ns[i] " " (i * 7 + j) " " np[j] " 0 8"; print "c" }
       for (f = 1; f <= 5; f++) for (m = 1; m <= 10; m += (m == 8 ? 2 : m == 7 ? 1 : 3)) { obs(10); print "C 1 0 2000 77 6 " f " " m; print "c" }
       for (a = 0; a <= 2; a++) { obs(10); print "C 255 " a " 2000 77 6 3 8"; print "c" } obs(10); print "C 2 0 2000 77 6 3 8"; print "c"; obs(10); print "C 1 0 2000 77 0 0 8"; print "c";
       for (ne = 0; ne <= 3; ne++) { obs(ne); print "C 1 0 2000 77 6 3 8"; print "c" } obs(1); print "C 1 0 100 5 6 0 8"; print "c";
       for (q = 100; q <= 140; q += 2) { obs(10); print "C 1 0 2000 77 6 0 8"; print "R 0 3 " q " 100"; print "c"; obs(10); print "C 1 0 2000 77 6 0 8"; print "R 0 3 " (200 - q) " 100"; print "c" }
       split("180 181 190 196 197", qb, " "); for (i = 1; i <= 5; i++) { obs(10); print "C 1 0 2000 77 6 0 8"; print "R 0 3 " qb[i] " 100"; print "c" }
       obs(10); print "C 1 0 10098 77 101 0 8"; print "c"; obs(10); print "C 1 0 10099 77 101 0 8"; print "c";
       print "b 1 1 11 1"; for (bt = 1; bt <= 3; bt++) { print "B " bt " " (1000 + bt) " 10"; for (e = 0; e < 10; e++) { print "G 4 " bt " " (e < (bt + 4) ? 0 : 1); print "e 20" } } print "c";
       print "b 1 1 11 1"; print "B 1 1001 10"; for (e = 0; e < 14; e++) { if (e < 4) print "O 5"; print "G 4 1 " (e % 2); print "e 20"; print "O 0" }
       for (bt = 2; bt <= 4; bt++) { print "B " bt " " (1000 + bt) " 10"; for (e = 0; e < 10; e++) { print "G 4 " bt " " (e % 2); print "e 20" } } print "c";
       upto_cand(); print "c"; obs(10); print "C 1 0 2000 77 6 0 8"; print "R 0 1"; print "c"; obs(10); print "C 1 0 2000 77 6 0 8"; print "R 1 0"; print "R 2 0"; print "c";
       split("1 20000 5 0 1|1 20000 5 9 1|1 20000 5 0 9|0 20000 5 0|2 20000 5 0 1 1|1 20000 5 0 0|1 0 5 0 1|1 50000 5 0 1|1 20001 5 0 1|1 20000 0 0 1|1 20000 1 0 1|1 20000 100 0 1|1 20000 5 1 0", fs, "|");
       for (i = 1; i <= 13; i++) { upto_cand(); print "A " fs[i]; print "c"; upto_cand(); print "A " fs[i]; print "A " fs[i]; print "c" }
       for (h = 0; h <= 4; h++) { upto_cand(); print "A 1 20000 5 0 1"; print "P " h; print "G 3 0 0"; print "T"; print "c" }
       upto_cand(); print "A 1 20000 5 0 1"; for (t = 0; t < 5; t++) { print "P 2"; print "G 3 0 0"; print "T" } print "c"; print "A 1 20000 5 0 1"; print "c";
       upto_cand(); print "A 1 20000 5 0 1"; for (t = 0; t < 5; t++) { print "P 2"; print "P 2"; print "G 3 0 0"; print "T"; print "T" } print "c";
       upto_cand(); print "A 1 20000 5 0 1"; print "P 2"; print "W 3 1"; print "G 3 0 0"; print "T"; print "c";
       for (w = 1; w <= 4; w++) { print "b 1 " w " 11 1"; print "W " (w + 1) " 1"; for (bt = 1; bt <= 3; bt++) { print "B " bt " " (1000 + bt) " 10"; for (e = 0; e < 10; e++) { print "G 4 " bt " " (e % 2); print "e 20" } } print "c" }
       split("1001 1000|1003 1000|101 100|102 100|103 100|105 100|11 10|99 100|97 100|9 10", wf, "|");
       for (i = 1; i <= 10; i++) { print "b 1 1 11 1"; print "W " wf[i]; for (bt = 1; bt <= 3; bt++) { print "B " bt " " (1000 + bt) " 10"; for (e = 0; e < 10; e++) { print "G 4 " bt " " (e % 2); print "e 20" } } print "c" }
       upto_cand(); print "G 3 0 0"; print "e 20"; print "A 1 20000 5 0 1"; print "c"; upto_cand(); print "g 2 3 0 0"; print "A 1 20000 5 0 1"; print "c"; upto_cand(); print "G 3 0 0"; print "A 1 20000 5 0 1"; print "c"; upto_cand(); print "G 3 0 0"; print "e 10"; print "A 1 20000 5 0 1"; print "c";
       print "b 1 1 11 1"; print "W 1 2"; for (bt = 1; bt <= 3; bt++) { print "B " bt " " (1000 + bt) " 10"; for (e = 0; e < 10; e++) { print "G 4 " bt " " (e % 2); print "e 20" } } print "c";
       split("b 1 1|b 1 1 5 1|b 1 1 10 1|b 1 1 11 1|b 1 1 12 1|b 1 1 1 1|b 1 1 2 1", ls, "|");
       for (i = 1; i <= 7; i++) { print ls[i]; for (k = 12; k <= 15; k++) print "t " k; print "t 8"; print "t 9" } }' > "$C/gen-crafted.txt"
[ -z "$ONLY" ] || { mkdir -p "$ONLY"; cp "$C"/*.txt "$ONLY"/; echo "PD0L_PARITY corpora in $ONLY"; exit 0; }

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "PD0L_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "PD0L_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out.gz
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$W/out/$b.c" || { echo "PD0L_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$W/out/$b.c" ] || { echo "PD0L_PARITY FAIL empty C output for $b"; exit 2; }
    gzip -9n < "$W/out/$b.c" > "$GOLD/$b.out.gz"
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out.gz")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "PD0L_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "PD0L_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "PD0L_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "PD0L_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "PD0L_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "PD0L_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out.gz" ] && [ "$want" = "$(sha "$GOLD/$b.out.gz")" ] || { echo "PD0L_PARITY FAIL golden $b.out.gz missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the verifier modules and the test bundle builder (as mk/physics0-verify.mk joins them) ----
OMS="src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om
src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om src/physics0/ladder/pd0_ladder.om
src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om tests/physics0/verify/pd0_bundle.om
tests/physics0/verify/pd0l_dump.om"
{ echo om2; echo 'text PD0_VERIFIER_COMMIT "parity"'; cat $OMS; } | "$OMC" > "$W/pd0l_dump_om"
chmod +x "$W/pd0l_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/pd0l_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  gzip -dc "$GOLD/$b.out.gz" > "$W/out/$b.c"
  if [ "$rc" -eq 0 ] && cmp -s "$W/out/$b.c" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$W/out/$b.c" "$W/out/$b.om" | head -20 | cut -c1-300 || true
  fi
done
echo "PD0L_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
