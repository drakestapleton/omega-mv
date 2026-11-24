#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The OM-2 est_replay against the C est_replay reference goldens (generated from
# est_replay.c -DEST_REPLAY_MAIN at f744696dd) on inputs with no size cap: more
# than 8192 steps, more than 16384 lines and 2 MiB, lines longer than 8 KiB with
# the thermal key past byte 8192, a file without a final newline, and SHA256SUMS
# files over 64 KiB, with a line fgets splits at 1023 bytes, and with an embedded
# NUL. stdout SHA-256, normalized stderr SHA-256 and exit code must be identical.
#   tools/estimation/test_est_replay_parity.sh <gold-file> <OM est_replay> <workdir>
set -u
GOLD=${1:?gold file}
OM=${2:?OM est_replay}
W=${3:?workdir}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0

# gen <file> <lines> <pad every k (0 none)> <pad bytes> [nokey every k]
gen() {
    awk -v n="$2" -v pk="$3" -v pb="$4" -v nk="${5:-0}" 'BEGIN {
        s = 1790864594; ns = 47074690; v = 35000
        pad = ""; for (j = 0; j < pb; j++) pad = pad "x"
        for (i = 0; i < n; i++) {
            d = 1000000000 + (i * 104729) % 6000001 - 3000000
            if (i % 997 == 500) d = 4000000000
            ns += d; while (ns >= 1000000000) { ns -= 1000000000; s++ }
            v += ((i * 7919) % 7 - 3) * 100
            l = sprintf("{\"t\":%d.%09d", s, ns)
            if (pk > 0 && i % pk == 0) l = l ",\"pad\":\"" pad "\""
            if (!(nk > 0 && i % nk == 0)) l = l sprintf(",\"thermal_mc\":\"%d 33200 \"", v)
            print l "}"
        }
    }' > "$1"
}
sum() { sha256sum "$1" | cut -c1-64; }
mkcase() { mkdir -p "$W/$1"; echo "$W/$1/machine-state.ndjson"; }

f=$(mkcase steps9000); gen "$f" 9000 0 0; echo "$(sum "$f")  machine-state.ndjson" > "$W/steps9000/SHA256SUMS"
f=$(mkcase lines20000); gen "$f" 20000 1 120; echo "$(sum "$f")  machine-state.ndjson" > "$W/lines20000/SHA256SUMS"
f=$(mkcase longkey); gen "$f" 120 4 9000 31; echo "$(sum "$f")  machine-state.ndjson" > "$W/longkey/SHA256SUMS"
f=$(mkcase edgewin); gen "$f" 400 100 8129; echo "$(sum "$f")  machine-state.ndjson" > "$W/edgewin/SHA256SUMS"
f=$(mkcase edgewin2); gen "$f" 400 100 8130; echo "$(sum "$f")  machine-state.ndjson" > "$W/edgewin2/SHA256SUMS"
f=$(mkcase nonl); gen "$W/nonl.tmp" 9500 0 0; head -c -1 "$W/nonl.tmp" > "$f"; echo "$(sum "$f")  machine-state.ndjson" > "$W/nonl/SHA256SUMS"
f=$(mkcase bigsums); gen "$f" 300 0 0
awk 'BEGIN { for (i = 0; i < 1200; i++) printf "%064d  other-%06d.ndjson\n", i, i }' > "$W/bigsums/SHA256SUMS"
echo "$(sum "$f")  machine-state.ndjson" >> "$W/bigsums/SHA256SUMS"
f=$(mkcase sumschunk); gen "$f" 300 0 0
{ awk 'BEGIN { for (i = 0; i < 1023; i++) printf "a" }'; echo "$(sum "$f")  machine-state.ndjson"; } > "$W/sumschunk/SHA256SUMS"
f=$(mkcase sumsnul); gen "$f" 300 0 0
{ printf '%s  machine-state.ndjson' "$(sum "$f")"; printf '\000junk\n'; } > "$W/sumsnul/SHA256SUMS"
f=$(mkcase sumsnull2); gen "$f" 300 0 0
{ printf '%s  machine-state.nd' "$(sum "$f")"; printf '\000json\n'; } > "$W/sumsnull2/SHA256SUMS"

# the cases must really be past the former caps
[ "$(wc -c < "$W/lines20000/machine-state.ndjson")" -gt 2097152 ] && ok=1 || ok=0
[ "$(wc -l < "$W/lines20000/machine-state.ndjson")" -gt 16384 ] || ok=0
[ "$(wc -c < "$W/bigsums/SHA256SUMS")" -gt 65536 ] || ok=0
[ "$(awk 'length > 8192' "$W/longkey/machine-state.ndjson" | wc -l)" -gt 0 ] || ok=0
[ "$(awk 'length == 8192' "$W/edgewin/machine-state.ndjson" | wc -l)" -gt 0 ] || ok=0
[ "$(awk 'length == 8193' "$W/edgewin2/machine-state.ndjson" | wc -l)" -gt 0 ] || ok=0
if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: a generated case is not past its former cap" >&2; fi

while IFS="$(printf '\t')" read -r c m q r crc cout cerr; do
    case "$c" in ''|'#'*) continue ;; esac
    "$OM" "$m" "$q" "$r" "$W/$c/machine-state.ndjson" > "$W/o.out" 2> "$W/o.err"
    orc=$?
    sed "s|$W|<W>|g" "$W/o.err" > "$W/o.err.norm"
    oout=$(sum "$W/o.out")
    oerr=$(sum "$W/o.err.norm")
    if [ "$orc" = "$crc" ] && [ "$oout" = "$cout" ] && [ "$oerr" = "$cerr" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1)); echo "FAIL: est_replay $m $q $r $c (exit C $crc OM $orc, out $oout vs $cout, err $oerr vs $cerr)" >&2
    fi
done < "$GOLD"

# the 9000-step case replays every step (C output above 8192 steps)
n=$("$OM" 0 1 100 "$W/steps9000/machine-state.ndjson" 2>/dev/null | wc -l)
if [ "$n" -gt 8192 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: steps9000 streamed $n steps" >&2; fi
echo "test_est_replay_parity: $pass passed, $fail failed"
[ $fail = 0 ]
