#!/bin/bash
set -euo pipefail
out=$1
src=/tmp/osc-literal.1JF35k/landing-plain
old=$HOME/handoffs/omega-stress-repeat-20261120-WI3xzN
mkdir -p "$out/paged"
ln -s "$src" "$out/source"
cd "$src"
rev=$(git rev-parse HEAD)
test "$rev" = 371a882a5dc8509809abd9d4bbdf1316963f9d51
test -z "$(git status --porcelain)"
test "$(git -C /tmp/physics-pin rev-parse HEAD)" = "$(cat physics.lock)"
test -z "$(git -C /tmp/physics-pin status --porcelain -uno)"
cp "$old/q38_stress_bench.c" "$out/"
nice -n 10 make -j4 PHYSICS_DIR=/tmp/physics-pin build/gpu_q38_graph_test build/gpu_q38_stroke_exact_test build/gpu_attention_test > "$out/build.log" 2>&1
cc -O2 -ffp-contract=off -Isrc "$out/q38_stress_bench.c" build/libomega_gpu.a -lpthread -lm -o "$out/q38_stress_bench"
sha256sum build/gpu_attention_test build/gpu_q38_graph_test build/gpu_q38_stroke_exact_test build/libomega_gpu.a seed/out/omc > "$out/build.sha256"
(cd "$out"; sha256sum q38_stress_bench q38_stress_bench.c >> build.sha256)
{ hostname; uname -srmo; echo "$rev"; cat physics.lock; cc --version | head -1; nvidia-smi --query-gpu=name,driver_version --format=csv; echo "$old"; } > "$out/provenance.txt"
for f in run.sh paged/run.sh; do sed -e "s/c9fe0f228095e70b2ff5e48f9e0a7b3fdcccf721/$rev/g" -e "s/c9fe0f228/371a882a5/g" "$old/$f" > "$out/$f"; done
bash "$out/run.sh" "$out"
bash "$out/paged/run.sh" "$out/paged"
