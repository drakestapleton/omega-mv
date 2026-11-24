#!/bin/bash
# One cold-cache dsv41-decode run for the Arboris prefetch A/B.
# usage: run-one.sh ARM(0|1) RUN_ID NUM_GEN TOK...
set -euo pipefail
arm=$1 id=$2 ngen=$3; shift 3
out=$HOME/work/dsv41-pf-ab-out
ck=$HOME/models/deepseek-v4.1-flash-314113f8
bin=${DSV41_BIN:?set DSV41_BIN}
map=$HOME/work/dsv41-pf-ab/om/gpu/dsv41/decoder/engram-token-map.u32
case "$arm" in 0|1) ;; *) echo "bad arm" >&2; exit 2 ;; esac
r=$out/runs/$id
mkdir -p "$r"
sha256sum "$bin" > "$r/binary.sha256"
# Preflight (host only, no GPU): the binary must report the arm this run is for.
DSV41_ARBORIS_PREFETCH=$arm "$bin" pfcheck "$out/tensors.bin" "$map" "$out/sidecars" "$ck" 2> "$r/preflight"
if [ "$(cat "$r/preflight")" != "ARBORIS pf_enabled=$arm" ]; then
  echo "RUN $id PREFLIGHT FAILED: $(cat "$r/preflight")"
  exit 3
fi
shards=("$ck"/model-*.safetensors)
python3 -I "$out/pagecache.py" evict "${shards[@]}" > "$r/cache-before"
sync
grep -E 'MemAvailable|MemFree|Mapped' /proc/meminfo > "$r/meminfo-before"
t0=$(date +%s%N)
set +e
DSV41_ARBORIS_PREFETCH=$arm "$bin" gen "$out/tensors.bin" "$map" "$out/sidecars" "$ck" \
  "$r/trace.bin" "$ngen" "$@" > "$r/tokens" 2> "$r/stats"
rc=$?
set -e
t1=$(date +%s%N)
echo "$rc" > "$r/rc"
echo $((t1 - t0)) > "$r/wall_ns"
echo "$arm" > "$r/arm"
sha256sum "$r/tokens" "$r/trace.bin" > "$r/outputs.sha256"
echo "RUN $id arm=$arm rc=$rc wall_ns=$((t1 - t0)) cache_before=$(cat "$r/cache-before")"
cat "$r/stats"
sleep 10
