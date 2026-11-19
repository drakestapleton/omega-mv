#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/spirv/check.sh: host-only check of emit.om and conform.om (AArch64 Linux, no GPU opened).
# Compiles both with seed/out/omc, emits every kernel for cl and vk, runs spirv-val, runs a
# mutant control (module must differ) and a host reference control (wrong kernel must mismatch).
# Usage: sh gpu/spirv/check.sh   (env: OMC=seed/out/omc, SPIRV_VAL=spirv-val). Exit 0 all pass, 1 fail.
OMC=${OMC:-seed/out/omc}; SV=${SPIRV_VAL:-spirv-val}; S=$(dirname "$0"); B=${B:-$(mktemp -d)}
fail=0
for f in emit conform; do "$OMC" < "$S/$f.om" > "$B/$f" || { echo "FAIL compile $f"; exit 1; }; chmod +x "$B/$f"; done
for k in vadd vmul vsub vmax fsum16 rmsnorm gemm16; do for e in cl vk; do
  env=opencl2.2; [ $e = vk ] && env=vulkan1.1
  "$B/emit" $k $e > "$B/$k.$e.spv" || fail=1
  if "$SV" --target-env $env "$B/$k.$e.spv"; then echo "PASS spirv-val $k $e"; else echo "FAIL spirv-val $k $e"; fail=1; fi
  "$B/emit" $k $e mutant > "$B/$k.$e.mut.spv"
  if cmp -s "$B/$k.$e.spv" "$B/$k.$e.mut.spv"; then echo "FAIL mutant identical $k $e"; fail=1; else echo "PASS mutant differs $k $e"; fi
done; done
for k in vadd vmul vsub vmax; do
  "$B/conform" in $k "$B/A.bin" "$B/B.bin" && "$B/conform" ref $k "$B/$k.ref" || fail=1
  "$B/conform" check $k "$B/$k.ref" || fail=1
done
"$B/conform" in fsum16 "$B/X.bin" && "$B/conform" ref fsum16 "$B/f.ref" && "$B/conform" check fsum16 "$B/f.ref" || fail=1
"$B/conform" in rmsnorm "$B/RX.bin" "$B/RW.bin" && "$B/conform" ref rmsnorm "$B/rms.ref" && "$B/conform" check rmsnorm "$B/rms.ref" || fail=1
"$B/conform" in gemm16 "$B/GA.bin" "$B/GB.bin" && "$B/conform" ref gemm16 "$B/g.ref" && "$B/conform" check gemm16 "$B/g.ref" || fail=1
for pair in "vadd vmul" "vmul vsub" "vsub vmax" "rmsnorm vadd" "gemm16 vadd"; do set -- $pair
  "$B/conform" check $1 "$B/$2.ref" >/dev/null && { echo "FAIL control: $1 accepted $2 reference"; fail=1; } || echo "PASS control: $1 rejects $2 reference"
done
[ $fail = 0 ] && echo "SPIRV-CHECK PASS" || echo "SPIRV-CHECK FAIL"
exit $fail
