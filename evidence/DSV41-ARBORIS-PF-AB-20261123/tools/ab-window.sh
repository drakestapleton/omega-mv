#!/bin/bash
# One exclusive timing window running a sequence of cold dsv41-decode runs.
# usage: DSV41_BIN=... NGEN=... ab-window.sh WINDOW_NAME RUN_SPEC... ; RUN_SPEC = ARM:RUN_ID (ARM 0 = off, 1 = on)
# Runs from the source checkout so each spark-receipt records its git head.
set -u
I=$HOME/work/dsv41-pf-ab-out
cd "$HOME/work/dsv41-pf-ab" || exit 1
name=$1; shift
id=$(spark-window open "$name" --gb10 exclusive --quiet exclusive --lease 20 --wait) || { echo "open failed"; exit 1; }
echo "window $id"
trap 'spark-window close "$id"; echo "$(date -u +%FT%H:%MZ) RELEASE claude-dsv41-pf $name: done, GPU idle" >> ~/handoffs/BOARD.md' EXIT
for spec in "$@"; do
  arm=${spec%%:*} rid=${spec#*:}
  spark-window run spark-receipt "dsv41-pf-$rid" -- "$I/run-one.sh" "$arm" "$rid" "${NGEN:?set NGEN}" 0 671 6102 294 8760 344
  echo "spec $spec exit $?"
done
echo "WINDOW-DONE $name"
