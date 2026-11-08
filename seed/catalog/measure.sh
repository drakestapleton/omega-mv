#!/bin/sh
# seed/catalog/measure.sh: bytes and times of arms A (hand), B (catalog call), C (catalog inline).
# usage: seed/catalog/measure.sh OUTDIR REPS   (run under the CPU pool lock; see README.md)
# Writes OUTDIR/measure.tsv: raw byte counts and summed wall-clock nanoseconds over REPS runs.
# Times include process start; means are computed outside (README.md).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OA=${OA:-$root/seed/out/omc}
OB=${OB:-$HOME/work/omega-node-e5b3/seed/out/omc}
OUT=$1
REPS=$2
T=$here/tests
CAT=$here/catalog.om
mkdir -p "$OUT"
{ sed 's/^export fn /fn /' "$root/om/sha256/sha256-om2.om"; cat "$here/resolve.om"; } > "$OUT/resolve-full.om"
"$OA" < "$OUT/resolve-full.om" > "$OUT/resolve"; chmod +x "$OUT/resolve"
R=$OUT/resolve
sz() { wc -c < "$1" | tr -d ' '; }
now() { date +%s%N; }
printf 'omc\tprog\tarm\tsrc_bytes\tlock_bytes\tcatalog_bytes\tentry_bytes\tunit_bytes\texe_bytes\texit\treps\tresolve_ns\tomc_ns\trun_ns\n' > "$OUT/measure.tsv"
for c in A B; do
  eval omc=\$O$c
  for prog in item76666 item83423 item82342 item85188 big; do
    if [ $prog = big ]; then a=$T/big.a.om; p=$T/big.compact.om; else a=$T/f4/$prog.a.om; p=$T/f4/$prog.compact.om; fi
    for arm in a b c; do
      u=$OUT/$c.$prog.$arm.om; e=$OUT/$c.$prog.$arm.bin
      rns=0; lb=0; cb=0; eb=0
      if [ $arm = a ]; then
        cp "$a" "$u"; src=$(sz "$a")
      else
        src=$(sz "$p"); lb=$(sz "$T/lock.$arm"); cb=$(sz "$CAT")
        t0=$(now); i=0
        while [ $i -lt "$REPS" ]; do "$R" build "$CAT" "$T/lock.$arm" "$p" "$OUT/m" > "$u" 2> "$OUT/acct"; i=$((i + 1)); done
        rns=$(( $(now) - t0 ))
        eb=$(sed 's/.*entry_bytes=\([0-9]*\).*/\1/' "$OUT/acct")
      fi
      t0=$(now); i=0
      while [ $i -lt "$REPS" ]; do "$omc" < "$u" > "$e"; i=$((i + 1)); done
      ons=$(( $(now) - t0 ))
      chmod +x "$e"
      t0=$(now); i=0
      while [ $i -lt "$REPS" ]; do "$e"; x=$?; i=$((i + 1)); done
      xns=$(( $(now) - t0 ))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$c" $prog $arm "$src" "$lb" "$cb" "$eb" \
        "$(sz "$u")" "$(sz "$e")" "$x" "$REPS" "$rns" "$ons" "$xns" >> "$OUT/measure.tsv"
    done
  done
done
