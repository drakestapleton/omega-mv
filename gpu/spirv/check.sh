#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/spirv/check.sh: host-only check of emit.om, val.om, run.om, and conform.om (AArch64 Linux, no GPU opened).
# Compiles all four with seed/out/omc, emits every kernel for cl and vk, validates every module with
# pure-Omega val.om (and optionally cross-checks with external spirv-val if installed), executes every
# emitted SPIR-V module directly in pure Omega (run.om), verifies 0-ulp parity with conform.om, and
# checks validator, mutant, and cross-kernel negative controls.
# Usage: sh gpu/spirv/check.sh   (env: OMC=seed/out/omc, SPIRV_VAL=spirv-val). Exit 0 all pass, 1 fail.
OMC=${OMC:-seed/out/omc}; SV=${SPIRV_VAL:-spirv-val}; S=$(dirname "$0"); B=${B:-$(mktemp -d)}
HOST_ARCH=$(uname -m 2>/dev/null || echo aarch64)
TGT=${OMEGA_TARGET:-}
if [ -z "$TGT" ] && [ "$HOST_ARCH" = "x86_64" ]; then TGT=x86linux; fi
compile_om() {
  if [ -n "$TGT" ]; then
    { printf 'target %s\n' "$TGT"; cat "$1"; } | "$OMC" > "$2"
  else
    "$OMC" < "$1" > "$2"
  fi
}
fail=0
have_sv=0
if command -v "$SV" >/dev/null 2>&1 || [ -x "$SV" ]; then have_sv=1; fi
for f in emit val run conform; do compile_om "$S/$f.om" "$B/$f" || { echo "FAIL compile $f"; exit 1; }; chmod +x "$B/$f"; done
for k in vadd vmul vsub vmax fsum16 rmsnorm gemm16; do for e in cl vk; do
  env=opencl2.2; [ $e = vk ] && env=vulkan1.1
  "$B/emit" $k $e > "$B/$k.$e.spv" || fail=1
  if "$B/val" --target-env $env "$B/$k.$e.spv"; then echo "PASS omega-val $k $e"; else echo "FAIL omega-val $k $e"; fail=1; fi
  if [ "$have_sv" = 1 ]; then
    if "$SV" --target-env $env "$B/$k.$e.spv"; then echo "PASS spirv-val $k $e"; else echo "FAIL spirv-val $k $e"; fail=1; fi
  fi
  "$B/emit" $k $e mutant > "$B/$k.$e.mut.spv"
  if cmp -s "$B/$k.$e.spv" "$B/$k.$e.mut.spv"; then echo "FAIL mutant identical $k $e"; fail=1; else echo "PASS mutant differs $k $e"; fi
done; done
"$B/val" --target-env vulkan1.1 "$B/gemm16.cl.spv" 2>/dev/null && { echo "FAIL control: val accepted cl as vulkan1.1"; fail=1; } || echo "PASS control: val rejects cl as vulkan1.1"
"$B/val" --target-env opencl2.2 "$B/gemm16.vk.spv" 2>/dev/null && { echo "FAIL control: val accepted vk as opencl2.2"; fail=1; } || echo "PASS control: val rejects vk as opencl2.2"
printf 'BAD!' > "$B/bad.spv"
"$B/val" "$B/bad.spv" 2>/dev/null && { echo "FAIL control: val accepted bad magic"; fail=1; } || echo "PASS control: val rejects bad magic"
for k in vadd vmul vsub vmax; do
  "$B/conform" in $k "$B/A.bin" "$B/B.bin" && "$B/conform" ref $k "$B/$k.ref" || fail=1
  "$B/conform" check $k "$B/$k.ref" || fail=1
done
"$B/conform" in fsum16 "$B/X.bin" && "$B/conform" ref fsum16 "$B/f.ref" && "$B/conform" check fsum16 "$B/f.ref" || fail=1
"$B/conform" in rmsnorm "$B/RX.bin" "$B/RW.bin" && "$B/conform" ref rmsnorm "$B/rms.ref" && "$B/conform" check rmsnorm "$B/rms.ref" || fail=1
"$B/conform" in gemm16 "$B/GA.bin" "$B/GB.bin" && "$B/conform" ref gemm16 "$B/g.ref" && "$B/conform" check gemm16 "$B/g.ref" || fail=1
for e in cl vk; do
  for k in vadd vmul vsub vmax; do
    "$B/run" "$B/$k.$e.spv" 1048576 1048576 "$B/$k.$e.out" "$B/A.bin" "$B/B.bin" && "$B/conform" check $k "$B/$k.$e.out" || fail=1
  done
  "$B/run" "$B/fsum16.$e.spv" 65536 65536 "$B/fsum16.$e.out" "$B/X.bin" && "$B/conform" check fsum16 "$B/fsum16.$e.out" || fail=1
  "$B/run" "$B/rmsnorm.$e.spv" 65536 1048576 "$B/rmsnorm.$e.out" "$B/RX.bin" "$B/RW.bin" && "$B/conform" check rmsnorm "$B/rmsnorm.$e.out" || fail=1
  "$B/run" "$B/gemm16.$e.spv" 1048576 1048576 "$B/gemm16.$e.out" "$B/GA.bin" "$B/GB.bin" && "$B/conform" check gemm16 "$B/gemm16.$e.out" || fail=1
done
"$B/run" "$B/gemm16.vk.mut.spv" 1048576 1048576 "$B/gemm16.mut.out" "$B/GA.bin" "$B/GB.bin" || fail=1
"$B/conform" check gemm16 "$B/gemm16.mut.out" >/dev/null && { echo "FAIL control: gemm16 accepted mutant"; fail=1; } || echo "PASS control: gemm16 rejects mutant"
"$B/run" "$B/rmsnorm.vk.mut.spv" 65536 1048576 "$B/rmsnorm.mut.out" "$B/RX.bin" "$B/RW.bin" || fail=1
"$B/conform" check rmsnorm "$B/rmsnorm.mut.out" >/dev/null && { echo "FAIL control: rmsnorm accepted mutant"; fail=1; } || echo "PASS control: rmsnorm rejects mutant"
for pair in "vadd vmul" "vmul vsub" "vsub vmax" "rmsnorm vadd" "gemm16 vadd"; do set -- $pair
  "$B/conform" check $1 "$B/$2.ref" >/dev/null && { echo "FAIL control: $1 accepted $2 reference"; fail=1; } || echo "PASS control: $1 rejects $2 reference"
done
[ $fail = 0 ] && echo "SPIRV-CHECK PASS" || echo "SPIRV-CHECK FAIL"
exit $fail
