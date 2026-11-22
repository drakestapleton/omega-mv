#!/bin/sh
# teacher_window.sh TAG IN_AUDIT.om MAX_RECORDS DEADLINE_SEC SEED [LEASE_MIN]
# One cold boot of the q36-35b teacher under a claimed chip window; it only rewords instruction
# lines of verified records (teacher_paraphrase.py). The teacher is always shut down by the trap.
set -u
TAG="$1"; SRC="$2"; MAXN="$3"; DL="$4"; SEED="$5"; LEASE="${6:-18}"
CAMP=/home/drakestapleton/work/ollm-helix-rlvr-20261121
R="$CAMP/rounds"
OUTD="$R/para"; mkdir -p "$OUTD"
BOARD=/home/drakestapleton/handoffs/BOARD.md
NAME="ollm-teacher-para-$TAG"
LANE="claude-agy-finish"
rm -f "$OUTD/DONE_$TAG"
APPS=$(nvidia-smi --query-compute-apps=pid,name --format=csv,noheader 2>/dev/null | wc -l)
[ "$APPS" = "0" ] || { echo "FAIL chip busy"; echo "rc=1" > "$OUTD/DONE_$TAG"; exit 1; }

RUNNER="$OUTD/run-$TAG.sh"
cat > "$RUNNER" <<EOF
#!/bin/sh
set -u
SPID=""
cleanup() { if [ -n "\$SPID" ]; then kill "\$SPID" 2>/dev/null || true; wait "\$SPID" 2>/dev/null || true; SPID=""; fi; }
trap cleanup EXIT INT TERM
/home/drakestapleton/.local/bin/q36-35b --port 18099 > "$OUTD/q36_$TAG.log" 2>&1 &
SPID=\$!
READY=0
for i in \$(seq 1 120); do
  if curl -sf http://127.0.0.1:18099/health >/dev/null 2>&1; then READY=1; echo "Q36_READY_SEC=\$i"; break; fi
  sleep 1
done
[ "\$READY" = "1" ] || { echo "FAIL q36-35b not ready in 120s"; exit 1; }
python3 "$R/teacher_paraphrase.py" 18099 "$SRC" "$OUTD/para_$TAG.om" $MAXN $DL $SEED "$OUTD/asked_all.txt"
rc=\$?
cleanup
sleep 8
exit \$rc
EOF
chmod +x "$RUNNER"
echo "$(date -u +%FT%H:%MZ) CLAIM $LANE $NAME to all: GB10 chip lock (lease ${LEASE}m, no quiet lock) for one cold boot of the q36-35b teacher on private port 18099 to reword instruction lines of verified OM-2 records; teacher goes down by trap; reach me on this board" >> "$BOARD"
WID=$(spark-window open "$NAME" --lease "$LEASE" --gb10 exclusive --quiet none --wait | tail -n 1)
echo "OPENED_WINDOW=$WID"
closew() { spark-window close "$WID" >/dev/null 2>&1 || true; echo "$(date -u +%FT%H:%MZ) RELEASE $LANE $NAME: done, teacher down, GPU idle" >> "$BOARD"; }
trap closew EXIT INT TERM
spark-window run spark-receipt "$NAME" -- sh "$RUNNER"
RC=$?
cat "$OUTD/para_$TAG.om.asked" >> "$OUTD/asked_all.txt" 2>/dev/null || true
echo "rc=$RC" > "$OUTD/DONE_$TAG"
exit "$RC"
