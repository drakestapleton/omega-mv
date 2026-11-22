#!/bin/sh
# chain2.sh: the follow-up rounds registered in PLAN-B.md, run back to back. Each step: build the
# leakage-checked mix, encode it, train + geval in a claimed window, score the frozen benchmark.
set -u
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
VLOOP=/home/drakestapleton/work/ollm-loop-20261121
AB4=$CAMP/ab4_cycle2
R=$CAMP/rounds
M=$VLOOP/data/omega4096.bin
BOARD=/home/drakestapleton/handoffs/BOARD.md
R4SRC="breadth=$AB4/breadth/breadth_raw.om:4 c2direct=$AB4/stage5/direct_c2.om:4 c2align=$AB4/stage5/align_c2.om:1 c2repair=$AB4/stage5/repair_c2.om:1 idioms=$CAMP/data/rlvr_idioms_raw.om:2 comp=$CAMP/data/rlvr_comp_raw.om:1 factory=$CAMP/data/rlvr_r1.om:1 contrast=$VLOOP/data/contrast.om:1"
R6SRC="idioms=$CAMP/data/rlvr_idioms_raw.om:3 comp=$CAMP/data/rlvr_comp_raw.om:2 factory=$CAMP/data/rlvr_r1.om:1 contrast=$VLOOP/data/contrast.om:1 breadth=$AB4/breadth/breadth_raw.om:1 c2direct=$AB4/stage5/direct_c2.om:1 idioms69=$R/r5/rlvr_idioms_v6_9.om:1 comp69=$R/r5/rlvr_compositional_v6_9.om:1 factory69=$R/r5/rlvr_factory_v6_9.om:1"

prep() { # N REPO_PCT EPOCHS SOURCES...
  n="$1"; pct="$2"; ep="$3"; shift 3
  mkdir -p "$R/r$n"
  python3 "$R/build_mix.py" "$n" "$R/r$n" "$pct" "$ep" "$@" > "$R/r$n/build.out" 2>&1 || { echo "PREP_FAIL r$n"; return 1; }
  "$CAMP/bin/ollm" bpeenc "$M" 4096 "$R/r$n/r${n}_mix.om" "$R/r$n/r${n}_mix.tok" > "$R/r$n/bpeenc.out" 2>&1
  b=$(wc -c < "$R/r$n/r${n}_mix.tok")
  echo "tok $R/r$n/r${n}_mix.tok bytes $b tokens $((b / 2)) sha256 $(sha256sum "$R/r$n/r${n}_mix.tok" | cut -c1-64) bpeenc_K_line: $(cat "$R/r$n/bpeenc.out")" >> "$R/r$n/r${n}_manifest.txt"
  cat "$VLOOP/data/train.om" "$R/r$n/r${n}_audit.om" > "$R/r$n/full_corpus_r$n.om"
  echo "PREP_OK r$n $(tail -1 "$R/r$n/r${n}_manifest.txt" | cut -c1-200)"
}
train_score() { # N PREV
  n="$1"; prev="$2"
  sh "$R/gpu_round.sh" "$n" "$prev" 1400 350 18 > "$R/r$n/gpu_round.out" 2>&1
  echo "GPU r$n $(cat "$R/r$n/DONE_GPU") $(grep '^E ' "$R/r$n/geval_loop_r$n.log")"
  sh "$R/score_round.sh" "r$n" "$CAMP/ckpt/loop_r$n.ck" "$R/r$n/full_corpus_r$n.om" > "$R/score_r$n.out" 2>&1
  echo "SCORE r$n $(grep '^SCORE' "$R/score_r$n.txt")"
  sleep 10
}

# step 0: baseline held-out loss of the pre-campaign looped checkpoint with today's binary
NAME=ollm-r0-baseline-geval
echo "$(date -u +%FT%H:%MZ) CLAIM claude-agy-finish $NAME to all: GB10 chip lock (lease 6m, no quiet lock) for one 2475-window geval of the pre-campaign looped checkpoint, then four more training rounds r8..r11 back to back (each with its own claim line); reach me on this board" >> "$BOARD"
WID=$(spark-window open "$NAME" --lease 6 --gb10 exclusive --quiet none --wait | tail -n 1)
cat > "$R/run-r0-geval.sh" <<EOF
#!/bin/sh
printf "6\n" > /tmp/helix_genome.cfg
"$CAMP/bin/ollm-helix-gb10" geval "$VLOOP/run/loop/ck6000.bin" "$VLOOP/data/held.tok" 2475 "$M" > "$R/geval_loop_r0_ck6000.log" 2>&1
rc=\$?
rm -f /tmp/helix_genome.cfg
exit \$rc
EOF
spark-window run spark-receipt "$NAME" -- sh "$R/run-r0-geval.sh"
spark-window close "$WID" >/dev/null 2>&1 || true
echo "$(date -u +%FT%H:%MZ) RELEASE claude-agy-finish $NAME: done, GPU idle" >> "$BOARD"
echo "R0 $(grep '^E ' "$R/geval_loop_r0_ck6000.log") ck6000_sha256=$(sha256sum "$VLOOP/run/loop/ck6000.bin" | cut -c1-64)"
sleep 10

prep 8 50 10 $R4SRC && train_score 8 "$CAMP/ckpt/loop_r3.ck"
REPO_FROM_MIX="$R/r4/r4_mix.om" prep 9 50 10 $R4SRC && train_score 9 "$CAMP/ckpt/loop_r3.ck"
prep 10 50 10 $R6SRC && train_score 10 "$CAMP/ckpt/loop_r6.ck"
prep 11 50 10 $R6SRC && train_score 11 "$CAMP/ckpt/loop_r10.ck"
echo CHAIN2_DONE
