#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Verification driver (not part of the delivered closure): contract section 8 static scan of the four
# exports of the OM-2 SHA artifact with leakscan e14, plus the all-exports obligation.
# Usage (repository root): sh seed/qualification/om2/leak/sha-exports.sh LEAKSCAN ARTIFACT OUTDIR
#   LEAKSCAN  a leakscan built from seed/qualification/om2/leak/leakscan.om by the pinned seed/out/omc
#   ARTIFACT  the S4 SHA artifact (words 0..3 are `b init`, `b update`, `b final`, `b hash`)
#   OUTDIR    must not exist; receives entry-K.bin, K-NAME.txt (scan report), K-NAME.xcheck, summary.txt
# For export K the scan input is the artifact with word 0 replaced by word K's branch re-based to byte 0
# (oracle/sha/entry.py): the scanner starts where the binding enters export K. Entry slots follow the
# signatures: init x0=c; update x0=c x1=d.ptr x2=d.len; final x0=c x1=out; hash x0=d.ptr x1=d.len x2=out.
# pub:0:32:8 is the E11 declaration of `field count ulong at 32` for the exports that take c (init, update,
# final). hash takes no context. The all-exports obligation printed by e14 is met only when no export that
# takes c reports PUBLIC-MEM-REVOKED. hash is left out of the obligation as an ASSUMPTION (its `out` digest
# could only reach ctx if the caller aliased it; the binding refuses that): not proved by the scanner, see
# PROPOSAL-E14-final-out.txt.
set -u
S=$1
A=$2
O=$3
HERE=$(dirname "$0")
ORA=$HERE/../oracle
[ -x "$S" ] && [ -f "$A" ] || { echo "usage: $0 LEAKSCAN ARTIFACT OUTDIR" >&2; exit 90; }
mkdir "$O" || exit 91
{
  echo "date $(date -u +%FT%TZ) host $(uname -srm)"
  echo "leakscan $S sha256 $(sha256sum < "$S" | cut -d' ' -f1)"
  echo "artifact $A sha256 $(sha256sum < "$A" | cut -d' ' -f1) bytes $(wc -c < "$A")"
} > "$O/summary.txt"
met=yes
rows=""
for e in 0:init:pub:0:32:8 1:update:pub:0:32:8 2:final:pub:0:32:8 3:hash:; do
  k=${e%%:*}; r=${e#*:}; name=${r%%:*}; d=${r#*:}
  [ "$d" = "$name" ] && d=""
  python3 "$ORA/sha/entry.py" "$A" "$k" "$O/entry-$k.bin" > /dev/null || exit 92
  "$S" $d e14 < "$O/entry-$k.bin" > "$O/$k-$name.txt"; x=$?
  python3 "$ORA/leak/xcheck.py" "$O/entry-$k.bin" "$O/$k-$name.txt" > "$O/$k-$name.xcheck" 2>&1
  rev=$(grep -c '^PUBLIC-MEM-REVOKED' "$O/$k-$name.txt")
  v=$(grep '^VERDICT' "$O/$k-$name.txt" | sed 's/^VERDICT TRACE-EQUIV-STATIC //')
  ex=$(grep '^E14 excused' "$O/$k-$name.txt" | sed 's/^E14 excused //')
  xc=$(tail -n 1 "$O/$k-$name.xcheck")
  rows="$rows$name decl=${d:-none} exit=$x verdict=$v revoked=$rev excused[$ex] $xc
"
  if [ "$k" != 3 ] && [ "$rev" != 0 ]; then met=no; fi
done
printf '%s' "$rows" >> "$O/summary.txt"
echo "all-exports obligation (init, update, final scanned with pub:0:32:8, none revokes): $( [ $met = yes ] && echo MET || echo NOT_MET )" >> "$O/summary.txt"
cat "$O/summary.txt"
