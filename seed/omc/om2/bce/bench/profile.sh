set -u
# Static profile of rule forbnd (DRA-189). Run from the omega-mv root:
#   sh seed/omc/om2/bce/bench/profile.sh OMC OUT
# For every tracked .om whose OM-2 lead line is exactly `om2` or `om2 diag`, compile it with the lead
# `om2 diag` and with `om2 diag bce`. Count trap sites (omc-site records) and erased checks (forbnd
# records); require sites(diag) - sites(diag bce) == records and identical artifacts when there are
# none; run the certificate checker (seed/omc/om2/bce/bcecheck.om, built by OMC) on every unit.
# Writes OUT/units.tsv (unit, sites_diag, sites_bce, erased, bytes_diag, bytes_bce) and prints
# PROFILE and CHECKER summary lines; OUT/bad.txt lists any inconsistency. Exit 1 on any.
OMC=$1; OUT=$2
[ -e "$OUT" ] && { echo "OUT exists: $OUT" >&2; exit 91; }
mkdir -p "$OUT"
"$OMC" < seed/omc/om2/bce/bcecheck.om > "$OUT/bcecheck" && chmod +x "$OUT/bcecheck" || exit 3
git ls-files '*.om' > "$OUT/list.txt"
: > "$OUT/units.tsv"; : > "$OUT/bad.txt"
units=0; withsites=0; S0=0; S1=0; E=0; bad=0; unitsE=0; CP=0; CF=0; CR=0
while read f; do
  [ -f "$f" ] || continue
  ln=$(awk '!/^[ \t]*$/ && !/^[ \t]*note([ \t(]|$)/ {print NR; exit}' "$f")
  [ -n "$ln" ] || continue
  lead=$(sed -n "${ln}p" "$f")
  [ "$lead" = "om2" ] || [ "$lead" = "om2 diag" ] || continue
  awk -v n=$ln 'NR==n {print "om2 diag"; next} {print}' "$f" > "$OUT/u0.om"
  awk -v n=$ln 'NR==n {print "om2 diag bce"; next} {print}' "$f" > "$OUT/u1.om"
  "$OMC" < "$OUT/u0.om" > "$OUT/u0.bin" 2> "$OUT/u0.err"; r0=$?
  "$OMC" < "$OUT/u1.om" > "$OUT/u1.bin" 2> "$OUT/u1.err"; r1=$?
  [ $r0 = 0 ] || continue
  units=$((units+1))
  if [ $r1 != 0 ]; then bad=$((bad+1)); echo "BAD-RC $f $r1" >> "$OUT/bad.txt"; continue; fi
  s0=$(grep -c '^omc-site ' "$OUT/u0.err"); s1=$(grep -c '^omc-site ' "$OUT/u1.err")
  e=$(grep -c 'rule=forbnd' "$OUT/u1.err")
  [ $s0 -gt 0 ] && withsites=$((withsites+1))
  if [ $((s0 - s1)) != $e ]; then bad=$((bad+1)); echo "BAD-COUNT $f s0=$s0 s1=$s1 e=$e" >> "$OUT/bad.txt"; fi
  if [ $e = 0 ] && ! cmp -s "$OUT/u0.bin" "$OUT/u1.bin"; then bad=$((bad+1)); echo "BAD-BYTES $f" >> "$OUT/bad.txt"; fi
  [ $e -gt 0 ] && unitsE=$((unitsE+1))
  "$OUT/bcecheck" "$OUT/u1.om" "$OUT/u1.err" "$OUT/u0.err" > "$OUT/chk.out" 2>&1; cr=$?
  if [ $cr = 0 ] && grep -q '^BCECHK PASS ' "$OUT/chk.out"; then CP=$((CP+1)); else
    CF=$((CF+1)); echo "CHECKER-FAIL $f rc=$cr" >> "$OUT/bad.txt"; cat "$OUT/chk.out" >> "$OUT/bad.txt"; fi
  CR=$((CR + $(grep -c '^BCECHK OK ' "$OUT/chk.out")))
  S0=$((S0+s0)); S1=$((S1+s1)); E=$((E+e))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" $s0 $s1 $e $(wc -c < "$OUT/u0.bin") $(wc -c < "$OUT/u1.bin") >> "$OUT/units.tsv"
done < "$OUT/list.txt"
echo "PROFILE units=$units units_with_sites=$withsites units_with_erasure=$unitsE sites_diag=$S0 sites_bce=$S1 erased=$E inconsistent=$bad"
echo "CHECKER units_pass=$CP units_fail=$CF records_admitted=$CR"
[ $bad = 0 ] && [ $CF = 0 ] && [ $CR = $E ]
