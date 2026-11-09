#!/bin/sh
# difftrees.sh OLD NEW OUT : rows c2-00128 (gate669.om) and c2-05721 (om2 gate.om) from the 725ca839 tree, old and new compiler
OLD=$1; NEW=$2; OUT=$3; T=~/work/L1041/t725; S=~/work/L1041/src29; mkdir -p "$OUT"; : > "$OUT/summary.tsv"
for which in old new; do
  [ $which = old ] && omc=$OLD || omc=$NEW
  R=$OUT/tree.$which; rm -rf "$R"; mkdir -p "$R/build"; cp -r "$T"/. "$R"/ ; cp "$omc" "$R/omc-test"; omc=$R/omc-test; cd "$R"
  # c2-00128: gate669 built by the compiler under test, run from the tree root
  "$omc" < "$S/c2-00128.om" > g669 2>/dev/null; chmod 700 g669; timeout 1500 ./g669 > "$OUT/g669.$which.out" 2> "$OUT/g669.$which.err"; echo $? > "$OUT/g669.$which.rc"
  # c2-05721: gate.om built by the compiler under test, run over the four selftest lists with that compiler
  "$omc" < "$S/c2-05721.om" > gom 2>/dev/null; chmod 700 gom
  h=$(sha256sum < "$omc" | cut -c1-64)
  : > "$OUT/gom.$which.out"
  for c in controls emit fail pass; do
    timeout 600 ./gom "$omc" $h seed/qualification/om2/selftest/$c.cases "$R/scr-$c" > "$OUT/gom.$which.$c.out" 2> "$OUT/gom.$which.$c.err"; echo "$c $?" >> "$OUT/gom.$which.out"
  done
done
cd "$OUT"
for f in g669 gom; do :; done
echo "g669 old rc=$(cat g669.old.rc) new rc=$(cat g669.new.rc)" > "$OUT/summary.tsv"
cmp -s g669.old.out g669.new.out && echo g669 stdout same >> summary.tsv || echo g669 stdout DIFF >> summary.tsv
cmp -s g669.old.err g669.new.err && echo g669 stderr same >> summary.tsv || echo g669 stderr DIFF >> summary.tsv
echo "gom old: $(tr '\n' ' ' < gom.old.out)" >> summary.tsv; echo "gom new: $(tr '\n' ' ' < gom.new.out)" >> summary.tsv
for c in controls emit fail pass; do
  # verdict lines carry scratch paths and the compiler hash; compare after removing them
  for w in old new; do sed -e "s#$OUT/tree.$w#TREE#g" -e "s#$(sha256sum < $( [ $w = old ] && echo $OLD || echo $NEW ) | cut -c1-64)#OMCSHA#g" -e "s#TREE/omc-test#OMC#g" gom.$w.$c.out > gom.$w.$c.norm; done
  cmp -s gom.old.$c.norm gom.new.$c.norm && echo "gom $c output same" >> summary.tsv || echo "gom $c output DIFF" >> summary.tsv
  cmp -s gom.old.$c.err gom.new.$c.err || echo "gom $c stderr DIFF" >> summary.tsv
done
cat summary.tsv
