#!/bin/sh
# gpu_round.sh N PREV_CK STEPS LRMICRO [LEASE_MIN]
# One GPU training round for the looped core: tune (CPU) -> claim board -> spark-window (chip lock
# only, this is training not a timing) -> gtrainf + full geval under spark-receipt -> close -> release.
# Same commands as run-win3-r3.sh (loop half). Writes $RD/gpu_round.out and $RD/DONE_GPU (rc inside).
set -u
N="$1"; PREV="$2"; STEPS="$3"; LR="$4"; LEASE="${5:-18}"
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
VLOOP=/home/drakestapleton/work/ollm-loop-20261121
OLLM="$CAMP/bin/ollm"
OLLM_GPU="$CAMP/bin/ollm-helix-gb10"
MERGES="$VLOOP/data/omega4096.bin"
BOARD=/home/drakestapleton/handoffs/BOARD.md
RD="$CAMP/rounds/r$N"
CK="$CAMP/ckpt/loop_r$N.ck"
TOK="$RD/r${N}_mix.tok"
NAME="ollm-rlvr-r$N-gb10"
LANE="claude-agy-finish"
rm -f "$RD/DONE_GPU"
fail() { echo "FAIL $*"; echo "rc=1 $*" > "$RD/DONE_GPU"; exit 1; }

[ -s "$TOK" ] || fail "missing $TOK"
[ -s "$PREV" ] || fail "missing $PREV"
[ ! -e "$CK" ] || fail "$CK already exists, refusing to overwrite"

# look first (Play well together): refuse if the chip is busy or another lane holds a claim
APPS=$(nvidia-smi --query-compute-apps=pid,name --format=csv,noheader 2>/dev/null | wc -l)
[ "$APPS" = "0" ] || fail "chip busy: $(nvidia-smi --query-compute-apps=pid,name --format=csv,noheader | tr '\n' ';')"
spark-window status 2>&1 | head -5

"$OLLM" tune "$PREV" "$CK" "$STEPS" "$LR" || fail "tune rc=$?"
echo "TUNE_OK prev_sha256=$(sha256sum "$PREV" | cut -c1-64) steps=$STEPS lrmicro=$LR"

RUNNER="$RD/run-win-r$N.sh"
cat > "$RUNNER" <<EOF
#!/bin/sh
set -u
printf "6\n" > /tmp/helix_genome.cfg
t0=\$(date +%s)
"$OLLM_GPU" gtrainf "$CK" "$TOK" $STEPS 200 > "$RD/train_loop_r$N.log" 2>&1
rc_t=\$?
t1=\$(date +%s)
echo "LOOP_R${N}_TRAIN rc=\$rc_t sec=\$((t1 - t0))"
cat "$RD/train_loop_r$N.log"
sleep 8
"$OLLM_GPU" geval "$CK" "$VLOOP/data/held.tok" 2475 "$MERGES" > "$RD/geval_loop_r$N.log" 2>&1
rc_e=\$?
echo "LOOP_R${N}_HELD_2475 rc=\$rc_e \$(grep '^E ' "$RD/geval_loop_r$N.log")"
rm -f /tmp/helix_genome.cfg
[ "\$rc_t" = "0" ] && [ "\$rc_e" = "0" ]
EOF
chmod +x "$RUNNER"

echo "$(date -u +%FT%H:%MZ) CLAIM $LANE $NAME to all: GB10 chip lock (lease ${LEASE}m, no quiet lock: training, not a timing) for Round-$N RLVR training of the 15.8M looped Omega LLM (+$STEPS steps) + full 2475-window geval; finishing antigravity's interrupted ab4 campaign at Drake's request; pause/reach me on this board" >> "$BOARD"
WID=$(spark-window open "$NAME" --lease "$LEASE" --gb10 exclusive --quiet none --wait | tail -n 1)
echo "OPENED_WINDOW=$WID"
cleanup() {
  rm -f /tmp/helix_genome.cfg
  spark-window close "$WID" >/dev/null 2>&1 || true
  echo "$(date -u +%FT%H:%MZ) RELEASE $LANE $NAME: done, GPU idle" >> "$BOARD"
}
trap cleanup EXIT INT TERM
XB=$(sudo -n dmesg 2>/dev/null | grep -c "NVRM: Xid" || true)
spark-window run spark-receipt "$NAME" -- sh "$RUNNER"
RC=$?
XA=$(sudo -n dmesg 2>/dev/null | grep -c "NVRM: Xid" || true)
echo "XID_BEFORE=$XB XID_AFTER=$XA"
echo "CK_SHA256=$(sha256sum "$CK" | cut -c1-64)"
echo "RECEIPT=$(ls -t /home/drakestapleton/yardsticks/receipts/*"$NAME"*.json 2>/dev/null | head -1)"
echo "rc=$RC" > "$RD/DONE_GPU"
exit "$RC"
