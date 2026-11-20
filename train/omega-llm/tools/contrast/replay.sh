#!/usr/bin/env bash
set -euo pipefail
bin=$(realpath "$1")
omc=$(realpath "$2")
data=$(realpath run-01)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
for panel in fresh example earlier; do
  mkdir "gold-$panel"
  (cd "gold-$panel" && "$bin/grade" "$data/$panel.json" "$omc" >grades)
  test "$(wc -l <"gold-$panel/grades")" -eq "$(jq length "$data/$panel.json")"
done
for model in parent control treatment mean starting focused; do
  for panel in $(jq -r --arg m "$model" '.[$m]|keys[]' "$data/generations.json"); do
    dir="$model-$panel"
    mkdir "$dir"
    (cd "$dir"
     jq -r --arg m "$model" --arg p "$panel" '.[$m][$p][] | .body | @base64' "$data/generations.json" |
       { i=0; while IFS= read -r encoded; do printf %s "$encoded" | base64 -d >"answer-$i"; i=$((i+1)); done; }
     "$bin/grade" "$data/$panel.json" "$omc" cached >grades
     jq -r --arg m "$model" --arg p "$panel" '.[$m][$p] | to_entries[] | "\(.key) \(.value.grade)"' "$data/generations.json" | cmp - grades)
  done
done
for mode in example compile; do
  dir="selected-$mode"
  mkdir "$dir"
  args=()
  if [[ $mode == compile ]]; then args+=(compile); fi
  (cd "$dir"
   "$bin/select" "$data/example.json" "$omc" ../parent-fresh ../control-fresh ../treatment-fresh "${args[@]}" >choices
   "$bin/grade" "$data/fresh.json" "$omc" cached >grades
   cmp grades "$data/$dir.grades" && cmp choices "$data/$dir.choices")
done
"$bin/contrast" > contrast.om
sha256sum -c "$data/contrast.sha256"
# Cross both original limits. Compare the complete record multiset including duplicates.
for _ in {1..12}; do cat contrast.om; done >old.om
"$bin/mix"
cat old.om contrast.om | LC_ALL=C sort -z >expected.records
LC_ALL=C sort -z mixed.om | cmp - expected.records
echo "All reference functions, archived generations and fresh chain selections reproduced."
