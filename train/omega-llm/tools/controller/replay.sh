#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
src=$PWD
bin=$(realpath "${OUT:-../../../../build/omega-controller}")
omc=$(realpath "${OMC:-../../../../seed/out/omc}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
# The sampler can end immediately after the final identifier.
printf 'note multiply the arguments\nfn calc a ulong b ulong to ulong' >boundary-prompt
printf 'note multiply the arguments\nfn calc x ulong y ulong to ulong' >boundary-normalized
"$bin/normalize" boundary-prompt | cmp - boundary-normalized
for newline in no yes; do
  printf 's = mul x y\nret mul s s\nend' >boundary-body
  printf 's = mul a b\nret mul s s\nend' >boundary-expected
  if [[ $newline == yes ]]; then printf '\n' >>boundary-body; printf '\n' >>boundary-expected; fi
  "$bin/normalize" boundary-prompt boundary-body | cmp - boundary-expected
done
# Exercise real policy decisions using saved generator proposals.
cp "$src/example/prompt.om" prompt
cp "$src/example/example.om" first
cp "$src/example/second.om" second
cp "$src/example/answer.om" good
printf 'ret 0\nend\n' >wrong
controller=("$bin/controller" prompt "$omc" unused unused first unused unused "$bin/controller.ck")
"${controller[@]}" good wrong >answer 2>trace
cmp good answer
"${controller[@]}" unavailable unused one good wrong >answer 2>trace
cmp good answer
"${controller[@]}" second "$bin/second-augmented.ck" learned good wrong >answer 2>trace
cmp good answer
grep -q '^gate [0-7] 2$' trace

printf 'note choose the larger argument\nfn calc a ulong b ulong to ulong\n' >prompt
printf 'fn main to int\nif ne calc ulong 21 ulong 10 ulong 21\nret 83\nend\nret 77\nend\n' >first
printf 'fn main to int\nif ne calc ulong 14 ulong 23 ulong 23\nret 83\nend\nret 77\nend\n' >second
printf 'ret a\nend\n' >wrong
for mode in two learned; do
  rc=0
  "${controller[@]}" second "$bin/second-augmented.ck" "$mode" wrong wrong >answer 2>trace || rc=$?
  test "$rc" -eq 3
  test ! -s answer
  grep -q '^gate 4 1$' trace
done
printf 'bad' >corrupt
rc=0
"${controller[@]}" second corrupt learned wrong wrong >answer 2>trace || rc=$?
test "$rc" -eq 72
test ! -s answer

for run in run-01 run-02; do
  data="$src/$run"
  for check in main first second; do
    jq -c --arg k "$check" '.checks as $all | [.cases[] | {prompt,reference,main:$all[.checks][$k]}]' "$data/panel.json" >"$run-$check.json"
    mkdir "$run-$check"
    (cd "$run-$check" && "$bin/grade" "../$run-$check.json" "$omc" >grades)
    test "$(awk '$2==2{n++} END{print n}' "$run-$check/grades")" -eq 80
  done
  for mode in $(jq -r 'keys[]' "$data/scores.json"); do
    mkdir "$run-$mode"
    (cd "$run-$mode"
     jq -er --arg mode "$mode" '.[$mode] | select(length==80) | .[] | @base64' "$data/answers.json" |
       { i=0; while IFS= read -r body; do printf '%s' "$body" | base64 -d >"answer-$i"; i=$((i+1)); done; test "$i" -eq 80; }
     "$bin/grade" "../$run-main.json" "$omc" cached >actual
     awk -F '\t' -v mode="$mode" '$1==mode{print $2, 2*$7+$8}' "$data/cases.tsv" >expected
     cmp expected actual
     for key in correct wrong abstained calls second_checks; do
       sum=$(awk -F '\t' -v k="$key" -v m="$mode" 'NR==1{for(i=1;i<=NF;i++)if($i==k)col=i; if(!col)exit 1} $1==m{n+=$col} END{print n+0}' "$data/cases.tsv")
       test "$sum" -eq "$(jq -er --arg m "$mode" --arg k "$key" '.[$m].all[$k]' "$data/scores.json")"
     done)
  done
done
echo "PASS: controller interfaces, 160 references on three checks each, and all 560 archived returns and abstentions."
