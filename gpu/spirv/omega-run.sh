#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/spirv/omega-run.sh: run one kernel through pure seeded Omega (emit.om -> val.om -> run.om -> conform.om).
# Usage: sh gpu/spirv/omega-run.sh vadd|fsum16|gemm16|rmsnorm cl|vk
# Exit 0 prints PASS <kernel> omega-<env> n=<n> wrong=0 sha256=<hex>.
# Exit 2 when seed/out/omc cannot execute on this host; exit 1 on any failure or mismatch.
set -u
if [ $# -ne 2 ]; then
  echo "usage: sh gpu/spirv/omega-run.sh vadd|fsum16|gemm16|rmsnorm cl|vk" >&2
  exit 2
fi
K=$1
E=$2
OMC=${OMC:-seed/out/omc}
S=$(dirname "$0")
case "$E" in
  cl) TENV=opencl2.2 ;;
  vk) TENV=vulkan1.1 ;;
  *) echo "omega-run: bad env $E" >&2; exit 2 ;;
esac
case "$K" in
  vadd|gemm16) NWORK=1048576; NOUT=1048576; NIN=2 ;;
  fsum16) NWORK=65536; NOUT=65536; NIN=1 ;;
  rmsnorm) NWORK=65536; NOUT=1048576; NIN=2 ;;
  *) echo "omega-run: bad kernel $K" >&2; exit 2 ;;
esac
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
for f in emit val run conform; do
  "$OMC" < "$S/$f.om" > "$B/$f" 2>"$B/$f.err"
  CRC=$?
  if [ "$CRC" -ne 0 ]; then
    if [ "$CRC" -eq 126 ] || [ "$CRC" -eq 127 ]; then
      echo "NOT_RUN $K omega-$E: cannot execute $OMC"
      exit 2
    fi
    cat "$B/$f.err" >&2
    echo "FAIL $K omega-$E: omc failed on $f.om (exit $CRC)"
    exit 1
  fi
  chmod +x "$B/$f"
done
"$B/emit" "$K" "$E" > "$B/$K.$E.spv" || { echo "FAIL $K omega-$E: emit failed"; exit 1; }
"$B/val" --target-env "$TENV" "$B/$K.$E.spv" || { echo "FAIL $K omega-$E: val.om rejected module"; exit 1; }
if [ "$NIN" = 2 ]; then
  "$B/conform" in "$K" "$B/in0.bin" "$B/in1.bin" || { echo "FAIL $K omega-$E: conform in failed"; exit 1; }
  "$B/run" "$B/$K.$E.spv" "$NWORK" "$NOUT" "$B/out.bin" "$B/in0.bin" "$B/in1.bin" || { echo "FAIL $K omega-$E: run.om failed"; exit 1; }
else
  "$B/conform" in "$K" "$B/in0.bin" || { echo "FAIL $K omega-$E: conform in failed"; exit 1; }
  "$B/run" "$B/$K.$E.spv" "$NWORK" "$NOUT" "$B/out.bin" "$B/in0.bin" || { echo "FAIL $K omega-$E: run.om failed"; exit 1; }
fi
LINE=$("$B/conform" check "$K" "$B/out.bin")
RC=$?
SHA=$(printf '%s\n' "$LINE" | sed -n 's/.*sha256=\([0-9a-f]\{64\}\).*/\1/p')
if [ "$RC" -ne 0 ] || [ -z "$SHA" ]; then
  echo "FAIL $K omega-$E $LINE"
  exit 1
fi
echo "PASS $K omega-$E n=$NOUT wrong=0 sha256=$SHA"
exit 0
