#!/bin/sh
# supplement.sh REVIEW_CLONE : pins and records asked for by review 1 (CPU only, read-only on inputs).
set -u
CLONE="$1"
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
VLOOP=/home/drakestapleton/work/ollm-loop-20261121
R=$CAMP/rounds
S=$R/supplement
rm -rf "$S"; mkdir -p "$S"

# 1. generators: binary sha256, and whether today's repository source compiles to the same bytes
{
  echo "# generator binaries used for the task records, and a rebuild from repository source"
  echo "# source tree: $CLONE at $(cd "$CLONE" && cat .git/HEAD 2>/dev/null) ; compiler $CAMP/bin/omc sha256 $(sha256sum "$CAMP/bin/omc" | cut -c1-64)"
  for g in rlvr_factory rlvr_compositional rlvr_idioms rlvr_breadth; do
    b=$(sha256sum "$CAMP/bin/$g" | cut -c1-64)
    r=$("$CAMP/bin/omc" < "$CLONE/seed/helix/ollm_factory/$g.om" 2>/dev/null | sha256sum | cut -c1-64)
    s=$(sha256sum "$CLONE/seed/helix/ollm_factory/$g.om" | cut -c1-64)
    if [ "$b" = "$r" ]; then v=IDENTICAL; else v=DIFFERENT; fi
    echo "$g binary_sha256 $b source_sha256 $s rebuilt_from_source_sha256 $r rebuild $v"
  done
  echo "# variant outputs first used in round 6: for v in 6 7 8 9: <generator> corpus \$v, appended"
  for g in rlvr_idioms rlvr_compositional rlvr_factory; do
    t=$(mktemp); for v in 6 7 8 9; do "$CAMP/bin/$g" corpus $v >> "$t"; done
    echo "$g corpus 6..9 regenerated_sha256 $(sha256sum "$t" | cut -c1-64) used_file_sha256 $(sha256sum "$R/r5/${g}_v6_9.om" | cut -c1-64)"
    rm -f "$t"
  done
  t=$(mktemp); for v in 1 2 3 4 5 6 7 8 9; do "$CAMP/bin/rlvr_breadth" corpus $v >> "$t"; done
  echo "rlvr_breadth corpus 1..9 regenerated_sha256 $(sha256sum "$t" | cut -c1-64) used_file_sha256 $(sha256sum "$CAMP/ab4_cycle2/breadth/breadth_raw.om" | cut -c1-64)"
  rm -f "$t"
} > "$S/generator_pins.txt" 2>&1

# 2. token counts of the mixes of rounds 4 to 7 (2 bytes per token; bpeenc prints `K bytes tokens`)
{
  echo "# round tok_file bytes tokens sha256"
  for n in 4 6 7; do f="$R/r$n/r${n}_mix.tok"; b=$(wc -c < "$f"); echo "r$n $f $b $((b / 2)) $(sha256sum "$f" | cut -c1-64)"; done
  f="$R/r5/r5_mix.tok"; b=$(wc -c < "$f"); echo "r5 $f $b $((b / 2)) $(sha256sum "$f" | cut -c1-64) (byte copy of $CAMP/data/r3_mix.tok sha256 $(sha256sum "$CAMP/data/r3_mix.tok" | cut -c1-64))"
} > "$S/mix_tokens_r4_r7.txt"

# 3. what each benchmark score was computed from
{
  echo "# tag	checkpoint	checkpoint_sha256	seen_corpus	seen_corpus_sha256	answers_sha256"
  while read -r tag ck corpus; do
    [ -d "$R/bench_$tag" ] || continue
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$tag" "$ck" "$(sha256sum "$ck" | cut -c1-64)" "$corpus" "$(sha256sum "$corpus" | cut -c1-64)" "$(cat "$R/bench_$tag"/answer-* | sha256sum | cut -c1-64)"
  done <<EOF
r3ctl $CAMP/ckpt/loop_r3.ck $CAMP/data/full_corpus_r3.om
r4 $CAMP/ckpt/loop_r4.ck $R/r4/full_corpus_r4.om
r5ctl $CAMP/ckpt/loop_r5.ck $CAMP/data/full_corpus_r3.om
r6 $CAMP/ckpt/loop_r6.ck $R/r6/full_corpus_r6.om
r7 $CAMP/ckpt/loop_r7.ck $R/r7/full_corpus_r7.om
r8 $CAMP/ckpt/loop_r8.ck $R/r8/full_corpus_r8.om
r9 $CAMP/ckpt/loop_r9.ck $R/r9/full_corpus_r9.om
r10 $CAMP/ckpt/loop_r10.ck $R/r10/full_corpus_r10.om
r11 $CAMP/ckpt/loop_r11.ck $R/r11/full_corpus_r11.om
EOF
  echo "# pass-at-8: passk_r3 used $CAMP/data/full_corpus_r3.om ; passk_r6 used $R/r6/full_corpus_r6.om (harness/passk.sh argument 5)"
} > "$S/score_inputs.tsv"

# 4. every NVRM line the kernel logged today, with wall-clock time (no Xid lines are among them if the count below is unchanged)
{
  echo "# sudo dmesg -T | grep NVRM, lines dated Nov 22 2026 (local time, UTC-6). Xid lines in the whole log: $(sudo -n dmesg | grep -c 'NVRM: Xid')"
  sudo -n dmesg -T | grep NVRM | grep "Nov 22" | cut -c1-260
} > "$S/nvrm_dmesg_20261122.txt" 2>&1
wc -l "$S"/*
cat "$S/generator_pins.txt" | cut -c1-250
