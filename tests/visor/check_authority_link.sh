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

# Omega Visor V1, lane 7: authority isolation check (objects and OM-2 sources).
# "The Visor can ask. The Visor cannot grant."
#
# Two halves:
#  1. Objects (nm): fails when a Visor C object in $BUILD/visor (the test-only
#     runtime-linked adapters) references an authority-mutating symbol from
#     forbidden_symbols.txt, references any runtime / Aienux / publish-gate
#     symbol at all (^rx_ ^aienos_cap_ ^rc_), or DEFINES a forbidden name, and
#     checks that visor_effect_request.o exports only its four public functions.
#  2. OM-2 sources: the omega binary is pure seeded OM-2 with no symbol table,
#     so `nm` sees nothing in it. Its isolation is checked on the sources it is
#     built from (every tools/omega*.om, om/visor/*.om, src/visor/*.om,
#     src/language/*.om, om/aarch64/aarch64_om2.om, plus any file named in
#     $OMEGA_OM_SRCS, which the mk rule passes). On every code line (note lines
#     skipped, string literals blanked) no identifier may be a forbidden name or
#     start with rx_, aienos_cap_ or rc_ (a call to, or a local definition of,
#     an authority operation), and no identifier may contain `authorized` (the
#     Visor holds no authorization state). In string literals an `authorized`
#     key may only be followed by false.
#  A bite control runs every time: each forbidden form is planted in a copy of
#  a shipped source and the OM scan must fail on it; a planted note line and
#  string literal must not trip it. A control that does not bite fails the check.
# Usage: tests/visor/check_authority_link.sh [build_dir]   (default: build)
set -u
BUILD=${1:-build}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LIST="$HERE/forbidden_symbols.txt"
NM=${NM:-nm}
fail=0
checked=0

[ -f "$LIST" ] || { echo "FAIL: missing $LIST"; exit 1; }
forbidden=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$LIST" | grep -v '^$')
[ -n "$forbidden" ] || { echo "FAIL: forbidden list is empty"; exit 1; }

set -- "$BUILD"/visor/*.o
if [ ! -e "$1" ]; then
    echo "FAIL: no objects in $BUILD/visor (build the omega target first)"
    echo "OMEGA_VISOR_AUTHORITY_ISOLATION_FAIL"
    exit 1
fi

check_file() {
    f=$1
    if [ ! -e "$f" ]; then
        echo "skip: $f (not built)"
        return 0
    fi
    checked=$((checked + 1))
    undef=$($NM -u "$f" 2>/dev/null | awk '{print $NF}' | sed 's/@.*//')
    defs=$($NM --defined-only "$f" 2>/dev/null | awk '{print $NF}')
    for s in $forbidden; do
        if printf '%s\n' "$undef" | grep -qx "$s"; then
            echo "FAIL: $f references forbidden symbol $s"; fail=1
        fi
        if printf '%s\n' "$defs" | grep -qx "$s"; then
            echo "FAIL: $f defines forbidden symbol $s"; fail=1
        fi
    done
    bad=$(printf '%s\n' "$undef" | grep -E '^(rx_|aienos_cap_|rc_)' || true)
    if [ -n "$bad" ]; then
        for s in $bad; do echo "FAIL: $f references runtime/authority symbol $s"; done
        fail=1
    fi
}

for f in "$BUILD"/visor/*.o; do
    check_file "$f"
done
nobj=$checked

# The adapter exports exactly its four public functions: no setter, no submit.
ER="$BUILD/visor/visor_effect_request.o"
if [ -e "$ER" ]; then
    exports=$($NM --defined-only -g "$ER" | awk '$2 ~ /^[TDBR]$/ {print $3}' | sort | tr '\n' ' ')
    want="visor_effect_request_build visor_effect_request_classify visor_effect_request_format_json visor_effect_request_format_text "
    if [ "$exports" != "$want" ]; then
        echo "FAIL: $ER exports [$exports], expected [$want]"; fail=1
    fi
else
    echo "FAIL: $ER missing (lane 7 adapter not built)"; fail=1
fi

# No Visor C source (the test-only adapters left in src/visor) assigns `authorized`
# anything but false.
[ -d "$ROOT/src/visor" ] || { echo "FAIL: $ROOT/src/visor missing"; fail=1; }
hits=$(grep -rnE --include='*.c' --include='*.h' '(\.|->)authorized[[:space:]]*=[^=]' "$ROOT/src/visor" \
        | grep -vE 'authorized[[:space:]]*=[[:space:]]*false[[:space:]]*;' || true)
if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "FAIL: a Visor C source assigns 'authorized' other than false"; fail=1
fi

# ---- OM-2 sources of the omega binary ------------------------------------------
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/visor-auth.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT INT TERM
printf '%s\n' $forbidden > "$TMPD/forbidden"

# om_scan file...: prints one line per hit, exits 1 on any hit. Note lines are
# skipped; string literals are checked for an `authorized` key with a value
# other than false, then blanked before the identifiers are checked.
om_scan() {
    awk -v flist="$TMPD/forbidden" '
    BEGIN { while ((getline l < flist) > 0) F[l] = 1; bad = 0 }
    function hit(msg) { print "FAIL: " FILENAME ":" FNR ": " msg ": " $0; bad = 1 }
    /^[[:space:]]*note([[:space:]]|$)/ { next }
    {
        s = $0
        while (match(s, /"([^"\\]|\\.)*"/)) {
            t = substr(s, RSTART, RLENGTH)
            s = substr(s, RSTART + RLENGTH)
            while (match(t, /(^|[^A-Za-z0-9_])authorized(\\")?[[:space:]]*[:=][[:space:]]*/)) {
                t = substr(t, RSTART + RLENGTH)
                if (t !~ /^false/) hit("string literal gives authorized a value other than false")
            }
        }
        code = $0
        gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
        n = split(code, w, /[^A-Za-z0-9_]+/)
        for (i = 1; i <= n; i++) {
            if (w[i] == "") continue
            if (w[i] in F) hit("names forbidden authority symbol " w[i])
            else if (w[i] ~ /^(rx_|aienos_cap_|rc_)/) hit("names runtime/authority symbol " w[i])
            if (w[i] ~ /authorized/) hit("identifier " w[i] " holds authorization state")
        }
    }
    END { exit bad }' "$@"
}

om_files=""
for f in "$ROOT"/tools/omega*.om "$ROOT"/om/visor/*.om "$ROOT"/src/visor/*.om \
         "$ROOT"/src/language/*.om "$ROOT"/om/aarch64/aarch64_om2.om; do
    [ -e "$f" ] && om_files="$om_files $f"
done
# Every file the mk rule says omega is built from must be scanned too.
for f in ${OMEGA_OM_SRCS:-}; do
    case $f in /*) ;; *) f="$ROOT/$f" ;; esac
    [ -e "$f" ] || { echo "FAIL: OMEGA_OM_SRCS names $f, which does not exist"; fail=1; continue; }
    case " $om_files " in *" $f "*) ;; *) om_files="$om_files $f" ;; esac
done
nom=$(printf '%s\n' $om_files | grep -c . || true)
if [ "$nom" -eq 0 ] || [ ! -e "$ROOT/tools/omega.om" ] || [ ! -e "$ROOT/tools/omega_ops.om" ]; then
    echo "FAIL: the OM-2 sources of the omega binary were not found under $ROOT"; fail=1
fi
# shellcheck disable=SC2086
om_scan $om_files || { echo "FAIL: an OM-2 source of the omega binary names an authority operation"; fail=1; }

# Bite control: plant each forbidden form in a copy of a shipped source; the scan
# must fail on every one, and must stay clean on the unplanted copy and on a copy
# that carries the names only in a note line and a string literal.
BASE="$ROOT/src/visor/visor_effect_request.om"
bites=0
nbite=0
bite() {   # bite <label> <planted line>
    nbite=$((nbite + 1))
    cp "$BASE" "$TMPD/plant.om" && printf '%s\n' "$2" >> "$TMPD/plant.om"
    if om_scan "$TMPD/plant.om" > "$TMPD/plant.out"; then
        echo "FAIL: bite control '$1' was not caught by the OM source scan"; fail=1
    else
        bites=$((bites + 1))
        echo "bite control '$1': caught ($(head -n 1 "$TMPD/plant.out" | sed -e 's/^FAIL: [^ ]* //' -e 's/: .*//'))"
    fi
}
cp "$BASE" "$TMPD/plant.om"
om_scan "$TMPD/plant.om" > /dev/null || { echo "FAIL: bite control baseline (unplanted copy) is not clean"; fail=1; }
bite "local definition of a forbidden name" 'fn rx_capadmin_mint slot ulong to void'
bite "call to an Aienux mint" '  aienos_cap_mint 0 0'
bite "call to the publish gate" '  rc_produce 0'
bite "call to an unlisted runtime symbol" '  x = rx_world_poke 1'
bite "authorization state" 'global verq_authorized ulong 1'
bite "JSON literal authorized true" 'text verq_bad "\",\"authorized\":true}"'
bite "text literal authorized yes" 'text verq_bad2 "  authorized: yes\n"'
cp "$BASE" "$TMPD/plant.om"
printf '%s\n' 'note rx_capadmin_mint authorized aienos_cap_mint' \
    'text verq_ok "rx_capadmin_mint \",\"authorized\":false"' >> "$TMPD/plant.om"
om_scan "$TMPD/plant.om" > /dev/null || { echo "FAIL: bite control false positive (a note line or a literal tripped the scan)"; fail=1; }

if [ "$fail" -ne 0 ]; then
    echo "OMEGA_VISOR_AUTHORITY_ISOLATION_FAIL"
    exit 1
fi
echo "checked $nobj object(s) and $nom OM-2 source(s) against $(printf '%s\n' $forbidden | wc -l) forbidden symbols; $bites/$nbite bite controls caught"
echo "OMEGA_VISOR_AUTHORITY_ISOLATION_PASS"
exit 0
