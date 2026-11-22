#!/bin/sh
# score_round.sh TAG CK CORPUS_FOR_SEEN
# Frozen-benchmark score, same method as Rounds 2-3: one greedy sample per prompt (seed 42, 128
# tokens, temp 0) with the CPU ollm, 16-way parallel, then `bench score`. CPU only, niced.
set -u
TAG="$1"; CK="$2"; CORPUS="$3"
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
VLOOP=/home/drakestapleton/work/ollm-loop-20261121
OLLM="$CAMP/bin/ollm"; BENCH="$CAMP/bin/bench"; OMC="$CAMP/bin/omc"
MERGES="$VLOOP/data/omega4096.bin"
OUT="$CAMP/rounds/bench_$TAG"
rm -rf "$OUT"; mkdir -p "$OUT"
rm -f "$CAMP/rounds/DONE_SCORE_$TAG"
t0=$(date +%s)
ls "$CAMP/prompts"/prompt-* | nice -n 10 xargs -P 16 -I{} "$CAMP/samp_one.sh" "$OLLM" "$CK" "$MERGES" "$OUT" {}
echo "SAMPLED $TAG answers=$(ls "$OUT" | grep -c '^answer-') sec=$(( $(date +%s) - t0 ))"
"$BENCH" score "$CAMP/data/tasks.om" "$CAMP/data/expect.txt" "$OMC" "$OUT" "$CORPUS" > "$CAMP/rounds/score_$TAG.txt" 2>&1
echo "SCORE_RC=$?"
grep -E "^F |^SCORE " "$CAMP/rounds/score_$TAG.txt"
grep -E " pass$| passcut$" "$CAMP/rounds/score_$TAG.txt"
echo "ANSWERS_SHA256=$(cat "$OUT"/answer-* | sha256sum | cut -c1-64) CK_SHA256=$(sha256sum "$CK" | cut -c1-64) OLLM_SHA256=$(sha256sum "$OLLM" | cut -c1-64)"
echo done > "$CAMP/rounds/DONE_SCORE_$TAG"
