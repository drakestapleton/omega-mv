#!/bin/bash
# Long-workload Arboris prefetch A/B: six exclusive GB10 windows, one cold 256-token run each.
# usage: ab-long.sh QUAL_DIR   (the check-prefetch-mutants.sh output dir holding the qualified dsv41-decode)
set -u
cd "$HOME/work/dsv41-pf-ab-out"
export DSV41_BIN=$1/dsv41-decode NGEN=256
test -x "$DSV41_BIN" || { echo "no binary $DSV41_BIN"; exit 1; }
echo "binary $(sha256sum "$DSV41_BIN")"
echo "$(date -u +%FT%H:%MZ) CLAIM claude-dsv41-pf to all: 6 exclusive GB10 timing windows back to back (20m lease each, about 9 min used each) for the dsv41-decode Arboris prefetch off vs on A/B, 256 tokens, cold page cache per run; log ~/work/dsv41-pf-ab-out/ab-long.log; step aside on request on the board" >> ~/handoffs/BOARD.md
i=0
for spec in 1:L1-on 0:L2-off 0:L3-off 1:L4-on 1:L5-on 0:L6-off; do
  i=$((i + 1))
  ./ab-window.sh "dsv41-pf-long-$i" "$spec"
done
echo ALL-DONE
