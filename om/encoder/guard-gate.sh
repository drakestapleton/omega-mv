#!/bin/sh
# guard-gate.sh: the sm_121 guard predicate, on the encoder the C build links.
# Oracle: NVIDIA nvdisasm -b SM121 -hex (not shipped, not first-party).
# A guard-7 mutant of enc1 must fail both the row check and the oracle.
# The two encoder sources are compared on ops 0..63. Guards must agree, and any
# other word difference fails the gate. Run from anywhere.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OMC=${OMC:-$ROOT/seed/out/omc}
NVDISASM=${NVDISASM:-/usr/local/cuda/bin/nvdisasm}
[ -x "$OMC" ] || { echo "NOT_RUN: $OMC missing"; exit 3; }
[ -x "$NVDISASM" ] || { echo "NOT_RUN: $NVDISASM missing"; exit 3; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

compile() {
  if ! "$OMC" < "$1" > "$2"; then
    echo "COMPILE FAIL $1"
    exit 1
  fi
  chmod +x "$2"
}

echo "oracle: $("$NVDISASM" --version | grep -o 'release [0-9.]*, V[0-9.]*')"
echo "omc: $(sha256sum "$OMC" | cut -d' ' -f1)"

cat om/encoder/bw_enc_sm121.om om/encoder/guard_pred_test.om > "$D/fixed.om"
compile "$D/fixed.om" "$D/fixed"

echo "==== fixed rows ===="
set +e
"$D/fixed" > "$D/fixed.rows" 2>"$D/fixed.err"
rc=$?
set -e
cat "$D/fixed.rows"
echo "fixed rows exit $rc"
[ "$rc" = 0 ]
if grep -q . "$D/fixed.err"; then echo "fixed rows stderr:"; cat "$D/fixed.err"; exit 1; fi

echo "==== fixed oracle ===="
"$D/fixed" bin > "$D/fixed.bin"
bytes=$(wc -c < "$D/fixed.bin")
echo "fixed oracle bytes $bytes"
[ "$bytes" = 2128 ]
"$NVDISASM" -b SM121 -hex "$D/fixed.bin" > "$D/fixed.nv"
set +e
"$D/fixed" bin check < "$D/fixed.nv" > "$D/fixed.oracle" 2>"$D/fixed.oerr"
rc=$?
set -e
cat "$D/fixed.oracle"
echo "fixed oracle exit $rc"
[ "$rc" = 0 ]

echo "==== guard-7 mutant ===="
sed 's/^put w 0 or sub x and x 61440 shl pred o 12$/put w 0 or sub x and x 61440 shl ulong 7 12/' om/encoder/bw_enc_sm121.om > "$D/mutsrc.om"
if cmp -s "$D/mutsrc.om" om/encoder/bw_enc_sm121.om; then
  echo "MUTANT changed nothing"
  exit 1
fi
n=$(grep -c 'shl ulong 7 12' "$D/mutsrc.om")
[ "$n" = 1 ]
cat "$D/mutsrc.om" om/encoder/guard_pred_test.om > "$D/mut.om"
compile "$D/mut.om" "$D/mutant"
set +e
"$D/mutant" > "$D/mut.rows" 2>"$D/mut.err"
rc=$?
set -e
cat "$D/mut.rows"
echo "mutant rows exit $rc"
[ "$rc" != 0 ]
"$D/mutant" bin > "$D/mut.bin"
"$NVDISASM" -b SM121 -hex "$D/mut.bin" > "$D/mut.nv"
set +e
"$D/mutant" bin check < "$D/mut.nv" > "$D/mut.oracle" 2>"$D/mut.oerr"
rc=$?
set -e
cat "$D/mut.oracle"
echo "mutant oracle exit $rc"
[ "$rc" != 0 ]

echo "==== gpu copy (lock-pinned encoder) ===="
cat gpu/nvidia/om/encoder/bw_enc_sm121.om gpu/nvidia/om/encoder/guard_pred_test.om > "$D/gpu.om"
compile "$D/gpu.om" "$D/gpu"
set +e
"$D/gpu" > "$D/gpu.rows" 2>"$D/gpu.err"
rc=$?
set -e
cat "$D/gpu.rows"
echo "gpu rows exit $rc"
[ "$rc" = 0 ]
"$D/gpu" bin > "$D/gpu.bin"
gbytes=$(wc -c < "$D/gpu.bin")
echo "gpu oracle bytes $gbytes"
[ "$gbytes" = 2160 ]
"$NVDISASM" -b SM121 -hex "$D/gpu.bin" > "$D/gpu.nv"
set +e
"$D/gpu" bin check < "$D/gpu.nv" > "$D/gpu.oracle"
rc=$?
set -e
cat "$D/gpu.oracle"
echo "gpu oracle exit $rc"
[ "$rc" = 0 ]

echo "==== two copies ===="
sha256sum om/encoder/bw_enc_sm121.om gpu/nvidia/om/encoder/bw_enc_sm121.om
if cmp -s om/encoder/bw_enc_sm121.om gpu/nvidia/om/encoder/bw_enc_sm121.om; then
  echo "COPY sources byte-identical"
else
  echo "COPY sources differ"
fi
cat om/encoder/bw_enc_sm121.om om/encoder/guard_words.om > "$D/wa.om"
cat gpu/nvidia/om/encoder/bw_enc_sm121.om om/encoder/guard_words.om > "$D/wb.om"
compile "$D/wa.om" "$D/wa"
compile "$D/wb.om" "$D/wb"
"$D/wa" > "$D/wa.txt"
"$D/wb" > "$D/wb.txt"
la=$(wc -l < "$D/wa.txt")
lb=$(wc -l < "$D/wb.txt")
echo "word lines om $la gpu $lb"
[ "$la" = 192 ]
[ "$lb" = 192 ]
awk '
NR==FNR { k=$1" "$2; st[k]=$3; g[k]=$4; w[k]=$5" "$6" "$7" "$8; next }
{ k=$1" "$2
  if (st[k] != $3 || g[k] != $4) { print "GUARD DIFF " k " link " st[k] " " g[k] " ng " $3 " " $4; bad++ }
  if (w[k] != $5" "$6" "$7" "$8) { print "WORD DIFF " k " link " w[k] " ng " $5" "$6" "$7" "$8; words++ }
}
END { print "guard diffs " bad+0; print "word diffs " words+0; if (bad+0 > 0 || words+0 > 0) exit 1 }
' "$D/wa.txt" "$D/wb.txt"
echo "GUARD GATE PASS"
