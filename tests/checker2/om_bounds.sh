#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
FRONT=${1:?omegese}
EMIT=${2:?omega_emit}
C2=${3:?checker2}
WORK=${4:?work directory}
mkdir -p "$WORK"
"$FRONT" emit tests/osc_gpu/shared-bounds-edge.omegese "$WORK/good.json"
"$EMIT" emit "$WORK/good.json" "$WORK/good.ir"
"$FRONT" emit tests/osc_gpu/omegese/bad/shared_oob.omegese "$WORK/bad.json"
"$EMIT" emit "$WORK/bad.json" "$WORK/bad.ir"
sh tests/checker2/om_build.sh "$WORK/checker2.om.exe"
sh tests/checker2/om_build.sh "$WORK/checker2.mutant.exe" --mutant shared-bounds
for checker in "$C2" "$WORK/checker2.om.exe"; do
    "$checker" check "$WORK/good.ir" >"$WORK/good.out"
    if "$checker" check "$WORK/bad.ir" >"$WORK/bad.out"; then
        echo "FAIL: $checker accepted literal shared OOB" >&2; exit 1
    fi
    grep -q 'C2-GPU-BOUNDS' "$WORK/bad.out" || { cat "$WORK/bad.out"; exit 1; }
    echo "$checker: accepted edge / refused OOB"
    cat "$WORK/good.out" "$WORK/bad.out"
done
"$WORK/checker2.mutant.exe" check "$WORK/bad.ir" >"$WORK/mutant.out"
grep -q 'checker2=ACCEPT' "$WORK/mutant.out" || { cat "$WORK/mutant.out"; exit 1; }
echo 'SHARED BOUNDS PASS: C/Omega accepted edge, named OOB refusal, removed-guard mutant caught'
