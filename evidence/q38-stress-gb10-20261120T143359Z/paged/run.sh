#!/bin/bash
set -euo pipefail
out=$1
cd "$out/../source"
test "$(git rev-parse HEAD)" = 371a882a5dc8509809abd9d4bbdf1316963f9d51
test -z "$(git status --porcelain)"
printf '%s CLAIM Codex Q38 and attention stress, 371a882a5, exclusive GPU and quiet timing window, 15 minute lease. Contact via board.\n' "$(date -u +%FT%TZ)" >> ~/handoffs/BOARD.md
spark-window open codex-paged-stress-371a882a5 --gb10 exclusive --quiet exclusive --lease 15 --wait > "$out/window.txt"
wid=$(spark-window id)
monitor=
cleanup() {
    if [ -n "$monitor" ]; then kill "$monitor" 2>/dev/null || true; wait "$monitor" 2>/dev/null || true; fi
    spark-window close "$wid" > "$out/close.log"
    cp ~/yardsticks/windows/"$wid"/{open,close}.json "$out/"
    printf '%s RELEASE Codex Q38 and attention stress %s.\n' "$(date -u +%FT%TZ)" "$wid" >> ~/handoffs/BOARD.md
}
trap cleanup EXIT
nvidia-smi --query-gpu=timestamp,utilization.gpu,clocks.sm,temperature.gpu,power.draw --format=csv,nounits -l 1 > "$out/telemetry.csv" &
monitor=$!
run() {
    name=$1; shift
    printf '%s %s start\n' "$(date -u +%FT%TZ)" "$name" >> "$out/results.txt"
    set +e
    spark-window run /usr/bin/time -v -o "$out/$name.time" "$@" > "$out/$name.log" 2>&1
    code=$?
    set -e
    printf '%s %s exit %d\n' "$(date -u +%FT%TZ)" "$name" "$code" >> "$out/results.txt"
    return "$code"
}
run timing ./build/gpu_attention_test --timing --out "$out/timing.json"
run sweep ./build/gpu_attention_test --sweep --out "$out/sweep.json"
for h in 64 128; do run "split-$h" ./build/gpu_attention_test --split-timing --hd "$h" --out "$out/split-$h.json"; done
