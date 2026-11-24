#!/bin/bash
# Series B: the Arboris prefetch A/B on the final decoder binary.
# usage: ab-series-b.sh QUAL_DIR EXPECTED_HEAD   (QUAL_DIR = check-prefetch-mutants.sh output for that head)
set -u
I=$HOME/work/dsv41-pf-ab-out
export DSV41_BIN=$1/dsv41-decode
head=$2
cd "$HOME/work/dsv41-pf-ab" || exit 1
test "$(git rev-parse HEAD)" = "$head" || { echo "checkout is not at $head"; exit 1; }
test -z "$(git status --porcelain)" || { echo "checkout dirty"; exit 1; }
test -x "$DSV41_BIN" || { echo "no binary $DSV41_BIN"; exit 1; }
echo "head $head"
echo "binary $(sha256sum "$DSV41_BIN")"
echo "$(date -u +%FT%H:%MZ) CLAIM claude-dsv41-pf to all: 1 short value window, then 8 exclusive GB10 timing windows back to back (20m lease each, 6 to 9 min used each) for the dsv41-decode Arboris prefetch off vs on A/B on the final binary; log ~/work/dsv41-pf-ab-out/ab-series-b.log; step aside on request on the board" >> ~/handoffs/BOARD.md

# Does `spark-window run` pass the caller's environment to the command? (value check, chip lock only)
wid=$(spark-window open dsv41-pf-envcheck --gb10 exclusive --quiet none --lease 5 --wait) || { echo "open failed"; exit 1; }
d=om/gpu/dsv41/decoder; ck=$HOME/models/deepseek-v4.1-flash-314113f8
for v in 0 1; do
  line=$(DSV41_ARBORIS_PREFETCH=$v spark-window run "$DSV41_BIN" pfcheck "$I/tensors.bin" "$d/engram-token-map.u32" "$I/sidecars" "$ck" 2>&1 >/dev/null | grep -E "^ARBORIS" | tail -1)
  echo "ENVCHECK DSV41_ARBORIS_PREFETCH=$v spark-window run ... pfcheck -> $line"
done
spark-window close "$wid"

export NGEN=32
"$I/ab-window.sh" dsv41-pf-b-short-1 1:BS1-on 0:BS2-off
"$I/ab-window.sh" dsv41-pf-b-short-2 0:BS3-off 1:BS4-on
export NGEN=256
i=0
for spec in 0:BL1-off 1:BL2-on 1:BL3-on 0:BL4-off 0:BL5-off 1:BL6-on; do
  i=$((i + 1))
  "$I/ab-window.sh" "dsv41-pf-b-long-$i" "$spec"
done
echo ALL-DONE
