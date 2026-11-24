#!/bin/sh
# Replay a stored routing record through the repository's Arboris harness (CPU only, AArch64 Linux).
# usage (repository root, clean tree): sh EVIDENCE/tools/replay.sh EVIDENCE/series-X/runs/RUN/routing.bin > EVIDENCE/replay.txt
set -eu
routing=$1
tools=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
test -z "$(git status --porcelain)"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
(echo om2; cat tests/arboris/online_adapt_bench.om) | seed/out/omc > "$t/bench"
chmod +x "$t/bench"
echo "head $(git rev-parse HEAD)"
echo "harness_source_sha256 $(sha256sum tests/arboris/online_adapt_bench.om | cut -d' ' -f1)"
echo "harness_binary_sha256 $(sha256sum "$t/bench" | cut -d' ' -f1)"
echo "routing_sha256 $(sha256sum "$routing" | cut -d' ' -f1)"
tokens=$(( $(wc -c < "$routing") / 60 / 40 ))
echo "columns tok_end,static_hits,arb_hits,total_picks,plain_cache_hits,arb_cache_hits,pf_hits"
for cfg in "6 0" "2 0" "2 110"; do
  set -- $cfg
  python3 -I "$tools/routing-to-art1.py" "$routing" "$1" "$tokens" "$2" > "$t/in.art1"
  echo "budget=$1 bucket=$tokens cacheCap=$2 input_sha256=$(sha256sum "$t/in.art1" | cut -d' ' -f1): $("$t/bench" < "$t/in.art1" | tail -1)"
done
