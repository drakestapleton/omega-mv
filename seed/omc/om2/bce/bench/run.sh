set -u
# forbnd benchmark (DRA-189). Run from the omega-mv root on an idle pinned core:
#   flock -o POOL taskset -c CORE nice -n 10 sh seed/omc/om2/bce/bench/run.sh OUT [N]
# Builds every arm with seed/out/omc, checks that both arms of each workload give the same exit and
# stdout, then times them with bench.om (alternating A = om2, B = om2 bce). Writes OUT/*.tsv raw samples,
# OUT/arms.txt (artifact sizes and sha256) and OUT/meta.txt (compiler, sources, host).
OUT=$1; N=${2:-200}
OMC=seed/out/omc
D=seed/omc/om2/bce
[ -e "$OUT" ] && { echo "OUT exists: $OUT" >&2; exit 91; }
mkdir -p "$OUT/bin"
$OMC < $D/bench/bench.om > "$OUT/bin/bench" && chmod +x "$OUT/bin/bench" || exit 3
: > "$OUT/arms.txt"
arm() { # name lead srcfile
  { cat $D/lead-$2.om; cat "$3"; } > "$OUT/bin/$1.om"
  $OMC < "$OUT/bin/$1.om" > "$OUT/bin/$1" 2> "$OUT/bin/$1.cerr" || { echo "compile $1 failed" >&2; exit 3; }
  chmod +x "$OUT/bin/$1"
  echo "$1 $(wc -c < "$OUT/bin/$1") $(sha256sum < "$OUT/bin/$1" | cut -c1-64)" >> "$OUT/arms.txt"
}
for w in mb-sum mb-axpy mb-ctl; do arm $w-om2 om2 $D/bench/$w.om; arm $w-bce bce $D/bench/$w.om; done
# kemu: the real SASS emulator (seed/kflow/kemu.om); its OM-2 lead line is line 35
K=seed/kflow/kemu.om
ln=$(awk '!/^[ \t]*$/ && !/^[ \t]*note([ \t(]|$)/ {print NR; exit}' $K)
awk -v n=$ln 'NR==n {next} {print}' $K > "$OUT/bin/kemu-body.om"
awk -v n=$ln 'NR==n {print "om2"; next} {print}' $K > "$OUT/bin/kemu-om2.om"
awk -v n=$ln 'NR==n {print "om2 bce"; next} {print}' $K > "$OUT/bin/kemu-bce.om"
for v in om2 bce; do
  $OMC < "$OUT/bin/kemu-$v.om" > "$OUT/bin/kemu-$v" || exit 3; chmod +x "$OUT/bin/kemu-$v"
  echo "kemu-$v $(wc -c < "$OUT/bin/kemu-$v") $(sha256sum < "$OUT/bin/kemu-$v" | cut -c1-64)" >> "$OUT/arms.txt"
done
# same observable behaviour in both arms
for w in mb-sum mb-axpy mb-ctl; do
  "$OUT/bin/$w-om2" > "$OUT/$w-om2.out"; a=$?; "$OUT/bin/$w-bce" > "$OUT/$w-bce.out"; b=$?
  [ $a = $b ] && cmp -s "$OUT/$w-om2.out" "$OUT/$w-bce.out" || { echo "MISMATCH $w $a $b" >&2; exit 1; }
  echo "SAME $w exit=$a" >> "$OUT/arms.txt"
done
KA="121 seed/kflow/sm121/resadd.c.bin radd 7"
"$OUT/bin/kemu-om2" $KA > "$OUT/kemu-om2.out"; a=$?; "$OUT/bin/kemu-bce" $KA > "$OUT/kemu-bce.out"; b=$?
[ $a = $b ] && cmp -s "$OUT/kemu-om2.out" "$OUT/kemu-bce.out" || { echo "MISMATCH kemu" >&2; exit 1; }
echo "SAME kemu exit=$a $(cat "$OUT/kemu-om2.out")" >> "$OUT/arms.txt"
# timing: runtime arms, then compile time (A pinned-by-hash omc on the om2 source, B the same omc on the
# om2 bce source is run separately because bench gives both arms one stdin)
P=$(pwd)
for w in mb-sum mb-axpy mb-ctl; do
  "$OUT/bin/bench" "$N" /dev/null "$P/$OUT/bin/$w-om2" "$P/$OUT/bin/$w-bce" > "$OUT/$w.tsv" || exit 1
done
"$OUT/bin/bench" "$N" /dev/null "$P/$OUT/bin/kemu-om2" "$P/$OUT/bin/kemu-bce" $KA > "$OUT/kemu.tsv" || exit 1
"$OUT/bin/bench" "$N" "$OUT/bin/kemu-om2.om" "$P/$OMC" "$P/$OMC" > "$OUT/compile-om2.tsv" || exit 1
"$OUT/bin/bench" "$N" "$OUT/bin/kemu-bce.om" "$P/$OMC" "$P/$OMC" > "$OUT/compile-bce.tsv" || exit 1
{ echo "omc $(sha256sum < $OMC | cut -c1-64)"; echo "bench.om $(sha256sum < $D/bench/bench.om | cut -c1-64)";
  echo "kemu.om $(sha256sum < $K | cut -c1-64)"; echo "N $N"; echo "host $(uname -srm)";
  echo "affinity $(taskset -p $$ 2>/dev/null | awk '{print $NF}')"; echo "date $(date -u +%Y-%m-%dT%H:%M:%SZ)";
  echo "head $(git rev-parse HEAD 2>/dev/null)"; } > "$OUT/meta.txt"
echo "BENCHRUN PASS $OUT"
