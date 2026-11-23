#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# gpu_wait_parity.sh -- differential qualification of the pure OM-2 GPU completion wait
# (src/omega_gpu_wait.om: omega_gpu_wait_fixed, omega_gpu_wait_sequence and the poll loop under
# them) against the live C primitive it ports (src/omega_gpu_wait.c, which the C GPU paths link),
# on the same scripted scenarios: watched word, marker2 and snapshot values that move at each
# relax, scripted valid and abort answers, and a scripted clock.
#
# Every corpus runs through tests/gpu_wait_dump.om (built with the shipped src/omega_gpu_wait.om,
# as mk/omega-gpu-wait.mk joins it) and is compared byte for byte with
# tests/gpu_wait_golden/<corpus>.out: the return value, every report field, and the count and
# order of the hook calls (abort, barrier, snapshot, clock, valid, relax). The goldens were
# generated ONCE from the C at main commit 3f2c70dc5 by the reference-only C dumper
# tests/gpu_wait_dump.c (committed once, then removed); tests/gpu_wait_golden/MANIFEST records the
# commit, the generator and the sha256 of every corpus and golden. Needs no C compiler.
#
# Corpora: hand (tests/gpu_wait_corpus.txt) and gen-random (600 scenarios from a Park-Miller
# generator, seed 77: both kinds, every flag combination, word values near the target and across
# the u32 wrap, scripted answers, clocks given or stepped).
#
# usage: tests/gpu_wait_parity.sh [OMC]
#          prints PARITY lines and GPU_WAIT_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/gpu_wait_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
#   env: GPU_WAIT_PARITY_WORK (default: a new temporary dir), GPU_WAIT_OM_SRC (the OM wait to build
#        the dumper with; default src/omega_gpu_wait.om, gpu_wait_mutants.sh passes a mutated copy)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GOLD=$ROOT/tests/gpu_wait_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: gpu_wait_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${GPU_WAIT_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/gpu_wait_corpus.txt "$C/hand.txt"
awk 'function rnd() { s = (s * 16807) % 2147483647; return s }
     function ri(a, b) { return a + rnd() % (b - a + 1) }
     function lst(cmd, n, lo, hi,   i, l) { l = cmd; for (i = 0; i < n; i++) l = l " " ri(lo, hi); print l }
     function val(ex,   r) { r = rnd() % 10; if (r < 6) return (ex + ri(0, 4) + 4294967294) % 4294967296
       if (r < 8) return ri(0, 9); return (ex + 2147483646 + ri(0, 4)) % 4294967296 }
     function vals(cmd, n, ex,   i, l) { l = cmd; for (i = 0; i < n; i++) l = l " " val(ex); print l }
     BEGIN { s = 77
       for (k = 0; k < 600; k++) {
         print "R"; kind = ri(1, 2); r = rnd() % 4
         ex = (r == 0) ? ri(0, 9) : (r == 1) ? 4294967295 - ri(0, 3) : (r == 2) ? ri(0, 3) : 2147483647 + ri(0, 2)
         fl = ri(0, 63); if (rnd() % 5) { if (fl % 2 == 0) fl += 1; if (int(fl / 32) % 2 == 0) fl += 32 }
         if (rnd() % 12 == 0) fl += 64; if (rnd() % 12 == 0) fl += 128
         tot = (rnd() % 20 == 0) ? 0 : ri(1, 25); pr = (rnd() % 20 == 0) ? 0 : ri(1, 12)
         print "K " kind " " ex " " tot " " pr " " fl " " ri(0, 3)
         vals("W", ri(1, 12), ex)
         if (rnd() % 2) lst("M", ri(1, 8), 0, 3)
         if (rnd() % 2) lst("P", 2 * ri(1, 6), 0, 2)
         if (rnd() % 2) { l = "V"; n = ri(1, 8); for (i = 0; i < n; i++) l = l " " (rnd() % 6 ? 1 : 0); print l }
         if (rnd() % 2) { l = "A"; n = ri(1, 10); for (i = 0; i < n; i++) l = l " " (rnd() % 8 ? 0 : 1); print l }
         if (rnd() % 3 == 0) { l = "T"; t = ri(0, 1000000) * 1000; n = ri(1, 10)
           for (i = 0; i < n; i++) { t += ri(0, 3) * 700000 - (rnd() % 9 == 0 ? 1500000 : 0); if (t < 0) t = 0; l = l " " t }
           print l }
         print "S " (ri(1, 30) * 100000)
         print "G" } }' > "$C/gen-random.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "GPU_WAIT_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "GPU_WAIT_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "GPU_WAIT_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "GPU_WAIT_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "GPU_WAIT_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "GPU_WAIT_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "GPU_WAIT_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "GPU_WAIT_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "GPU_WAIT_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "GPU_WAIT_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "GPU_WAIT_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped module (as mk/omega-gpu-wait.mk joins it) ----
OMS=${GPU_WAIT_OM_SRC:-src/omega_gpu_wait.om}
(printf 'om2\n'; sed '/^om2$/d' "$OMS" tests/gpu_wait_dump.om) | "$OMC" > "$W/gpu_wait_dump_om"
chmod +x "$W/gpu_wait_dump_om"

# ---- compare ----
files=0; runs=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/gpu_wait_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
  n=$(grep -c '^G$' "$c")
  files=$((files + 1)); runs=$((runs + n))
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b runs=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b runs=$n DIFF exit=$rc"
    diff "$GOLD/$b.out" "$W/out/$b.om" | cut -c1-240 | head -20 || true
  fi
done
echo "GPU_WAIT_PARITY files=$files runs=$runs diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
