#!/bin/bash
# layer.sh TREE OMC OUT : run every C2 manifest of TREE through the conductor (seed/qualification/om2/gate.om built by OMC)
# with the deltas layered: manifest order, oldest first, is manifest-c2 (frozen), capacity, batch2, fpvreg, closerange, hostwords;
# in each file a row whose id a LATER file declares is replaced by that later row (the latest declaration wins). The committed
# manifests are never edited; the layered copies live in OUT.
set -u
T=$1; OMC=$2; OUT=$3; mkdir -p "$OUT"; cd "$T" || exit 2
H=$(sha256sum < "$OMC" | cut -c1-64)
[ -x "$OUT/gate" ] || { "$OMC" < seed/qualification/om2/gate.om > "$OUT/gate" && chmod 700 "$OUT/gate"; }
D=seed/qualification/om2
ORDER=(manifest-c2 manifest-c2-capacity manifest-c2-batch2 manifest-c2-fpvreg manifest-c2-closerange manifest-c2-hostwords)
echo "tree $(git -C "$T" rev-parse --short HEAD 2>/dev/null) omc $H gate $(sha256sum < "$OUT/gate" | cut -c1-64)"
for i in "${!ORDER[@]}"; do
  n=${ORDER[$i]}; [ -f $D/$n.txt ] || continue
  later=(); for ((j=i+1;j<${#ORDER[@]};j++)); do [ -f $D/${ORDER[$j]}.txt ] && later+=("$D/${ORDER[$j]}.txt"); done
  if [ ${#later[@]} -gt 0 ]; then
    awk -v nl=${#later[@]} 'FNR==1{f++} f<=nl {if ($1 ~ /^c2-/) ov[$1]=$0; next} {if ($1 in ov) print ov[$1]; else print}' "${later[@]}" $D/$n.txt > "$OUT/$n.layered"
  else cp $D/$n.txt "$OUT/$n.layered"; fi
  rows=$(grep -c '^c2-' "$OUT/$n.layered"); repl=$(grep -c '^c2-' $D/$n.txt)
  changed=$(diff <(grep '^c2-' $D/$n.txt) <(grep '^c2-' "$OUT/$n.layered") | grep -c '^>')
  rc=0; "$OUT/gate" "$OMC" "$H" "$OUT/$n.layered" "$OUT/scr-$n" > "$OUT/$n.log" 2>&1 || rc=$?
  echo "$n rows=$rows replaced_by_later_delta=$changed rc=$rc $(tail -1 "$OUT/$n.log")"
done
