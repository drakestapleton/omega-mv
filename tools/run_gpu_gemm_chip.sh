#!/bin/sh
# run_gpu_gemm_chip.sh: the C3 GEMM chip tier (208 shapes, both types, four layouts, red checks) in ONE exclusive spark-window, with a
# provenance header at the top of the log (git head, dirty flag, binary sha256, kernel, driver, memory, buddyinfo). Output names carry
# the window id and an existing file is never overwritten. usage: tools/run_gpu_gemm_chip.sh OUTDIR [gpu_gemm_test args]
# (OUTDIR outside the checkout, so the dirty flag in the header is honest)
# Needs the GB10 and the spark-window tools of the Spark; build first with `make build/gpu_gemm_test`.
set -u
out=${1:?usage: run_gpu_gemm_chip.sh OUTDIR [args]}; shift
bin=build/gpu_gemm_test; [ -x "$bin" ] || { echo "NOT_RUN: $bin not built" >&2; exit 3; }
mkdir -p "$out"
spark-window open "dra485-gemm-$$" --lease 20 --wait >/dev/null || exit 3
win=$(spark-window id) || exit 3
log="$out/chip-$win.log"; [ -e "$log" ] && { echo "refusing to overwrite $log" >&2; spark-window close >/dev/null; exit 4; }
{
  echo "provenance: window $win"
  echo "provenance: git head $(git rev-parse HEAD) dirty=$(git status --porcelain | wc -l) files"
  echo "provenance: binary $(sha256sum $bin | cut -d' ' -f1)"
  echo "provenance: kernel $(uname -r) driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader) arch $(uname -m)"
  echo "provenance: $(grep MemAvailable /proc/meminfo | tr -s ' ') buddyinfo $(tail -1 /proc/buddyinfo | tr -s ' ')"
  echo "provenance: args $*"
} > "$log"
spark-window run spark-receipt "dra485-gemm-$win" --idle 3 -- "$bin" "$@" >> "$log" 2>&1
rc=$?
echo "provenance: exit $rc"  >> "$log"
cp "$HOME/yardsticks/receipts/$(date -u +%F)-dra485-gemm-$win.json" "$out/receipt-$win.json" 2>/dev/null
cp "$HOME/yardsticks/windows/$win/open.json" "$out/window-$win-open.json"; spark-window close >/dev/null 2>&1
cp "$HOME/yardsticks/windows/$win/close.json" "$out/window-$win-close.json" 2>/dev/null
echo "window $win exit $rc log $log"
exit $rc
