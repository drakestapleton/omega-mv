#!/bin/sh
# passk.sh TAG CK K TEMPMILLI CORPUS : DIAGNOSTIC ONLY (never a training source, never the headline).
# K sampled answers per frozen-benchmark prompt, each graded by `bench score`; reports tasks passing in
# at least one of K samples. Headline benchmark stays one greedy sample.
set -u
TAG="$1"; CK="$2"; K="$3"; TEMP="$4"; CORPUS="$5"
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
VLOOP=/home/drakestapleton/work/ollm-loop-20261121
OLLM="$CAMP/bin/ollm"; BENCH="$CAMP/bin/bench"; OMC="$CAMP/bin/omc"; M="$VLOOP/data/omega4096.bin"
D="$CAMP/rounds/passk_$TAG"; rm -rf "$D"; mkdir -p "$D"
cat > "$D/one.sh" <<EOS
#!/bin/sh
P="\$1"; S="\$2"; id=\$(basename "\$P" | sed "s/^prompt-//")
"$OLLM" sample "$CK" "\$S" 128 $TEMP "\$(cat "\$P")" "$M" > "$D/s\$S/answer-\$id"
EOS
chmod +x "$D/one.sh"
for s in $(seq 1 "$K"); do
  mkdir -p "$D/s$s"
  ls "$CAMP/prompts"/prompt-* | nice -n 10 xargs -P 14 -I{} "$D/one.sh" {} "$s"
  "$BENCH" score "$CAMP/data/tasks.om" "$CAMP/data/expect.txt" "$OMC" "$D/s$s" "$CORPUS" > "$D/score_s$s.txt" 2>&1
  echo "seed $s: $(grep '^SCORE' "$D/score_s$s.txt")"
done
cat "$D"/score_s*.txt | grep -E "^R .* pass$" | awk '{print $2, $3}' | sort | uniq -c | sort -k2 > "$D/pass_any.txt"
echo "PASSK $TAG K=$K temp=$TEMP tasks_passing_in_any_sample=$(wc -l < "$D/pass_any.txt")"
awk '{print $3}' "$D/pass_any.txt" | sort | uniq -c | tr "\n" " "; echo
echo done > "$D/DONE"
