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

# Omega Visor V1, lane 7: authority isolation check (pure seeded OM-2 sources).
# "The Visor can ask. The Visor cannot grant."
#
# Checks:
#  1. Zero C/H files remain under src/visor (Visor is 100% pure seeded OM-2).
#  2. OM-2 sources: the omega binary is pure seeded OM-2 with no symbol table,
#     so `nm` sees nothing in it. Its isolation is checked on the sources it is
#     built from (every tools/omega.om, tools/omega_*.om, om/visor/*.om,
#     src/visor/*.om, src/language/*.om, om/aarch64/aarch64_om2.om, plus any
#     file named in $OMEGA_OM_SRCS, which the mk rule passes). On every code line (note lines
#     skipped, string literals blanked) no identifier may be a forbidden name or
#     start with rx_, aienos_cap_ or rc_ (a call to, or a local definition of,
#     an authority operation), and no identifier may contain `authorized` (the
#     Visor holds no authorization state). In string literals an `authorized`
#     key may only be followed by false.
#     Host words: an ALLOWLIST. The host words are derived from the compiler's own
#     keyword table, seed/omc/genkw.awk, as seed/effects/check.sh derives them
#     (every keyword with code >= 100 except the non-host const, qty, fma, cpufence
#     and cpurelax, plus read and write). A code line may use only these host words,
#     the ones the omega sources use today (derived by scanning them, 2026-11-23):
#       read     stdin session lines (visor_console) and bytes of files opened read-only
#       write    stdout/stderr renderings (visor.om ob_write_fd/v_write_all, visor_console,
#                tools/omega.om); it writes only to descriptors the parent passed in, as no
#                allowed word creates a writable descriptor
#       fopen    open for reading only: the flags must be the literal 0 (O_RDONLY) or
#                16384 (O_RDONLY|O_DIRECTORY), checked below
#       fclose   close those read-only descriptors
#       stat     size and type of a file or directory before reading it
#       lstat    the evidence explorer refuses symbolic links (visor_evidence)
#       getdnts  list a directory opened read-only (the evidence explorer)
#       argcnt   the command-line argument count (tools/omega.om)
#       argread  a command-line argument (tools/omega.om)
#     Any other host word fails (process, socket, mapping, device, file-system change,
#     descriptor duplication, environment, timing, ...). An allowlisted word that no
#     scanned source uses any more also fails, so the list stays what omega uses.
#     Residual (not claimed): write on a descriptor the parent left open is not
#     restricted further; the Visor cannot open, duplicate or create one.
#  A bite control runs every time: each forbidden form is planted in a copy of
#  a shipped source and the OM scan must fail on it; a planted note line and
#  string literal must not trip it. A control that does not bite fails the check.
# Usage: tests/visor/check_authority_link.sh [build_dir]   (default: build)
set -u
BUILD=${1:-build}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LIST="$HERE/forbidden_symbols.txt"
fail=0

[ -f "$LIST" ] || { echo "FAIL: missing $LIST"; exit 1; }
forbidden=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$LIST" | grep -v '^$')
[ -n "$forbidden" ] || { echo "FAIL: forbidden list is empty"; exit 1; }

# Pure seeded OM-2 Visor: no C or header files remain under src/visor.
[ -d "$ROOT/src/visor" ] || { echo "FAIL: $ROOT/src/visor missing"; fail=1; }
c_left=$(find "$ROOT/src/visor" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null || true)
if [ -n "$c_left" ]; then
    printf '%s\n' "$c_left"
    echo "FAIL: unexpected C/H source remains under $ROOT/src/visor"; fail=1
fi

# ---- OM-2 sources of the omega binary ------------------------------------------
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/visor-auth.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT INT TERM
printf '%s\n' $forbidden > "$TMPD/forbidden"
# Host words, from the compiler's keyword table (the derivation seed/effects/check.sh uses).
GENKW="$ROOT/seed/omc/genkw.awk"
[ -f "$GENKW" ] || { echo "FAIL: missing $GENKW (the compiler keyword table)"; exit 1; }
{ grep 'split("[a-z]' "$GENKW" | grep -oE '[a-z0-9]+:[0-9]+' \
    | awk -F: '$2 >= 100 && $1 != "const" && $1 != "qty" && $1 != "cpufence" && $1 != "cpurelax" && $1 != "fma" { print $1 }'
  printf '%s\n' read write; } | sort -u > "$TMPD/host"
nhost=$(grep -c . "$TMPD/host")
[ "$nhost" -ge 100 ] || { echo "FAIL: only $nhost host words derived from $GENKW (expected >= 100)"; exit 1; }
for w in fopen fork socknew mapnew execprog read write; do
    grep -qx "$w" "$TMPD/host" || { echo "FAIL: host word $w not derived from $GENKW"; exit 1; }
done
ALLOW="read write fopen fclose stat lstat getdnts argcnt argread"
printf '%s\n' $ALLOW > "$TMPD/allow"
: > "$TMPD/used"

# om_scan file...: prints one line per hit, exits 1 on any hit. Note lines are
# skipped; string literals are checked for an `authorized` key with a value
# other than false, then blanked before the identifiers are checked.
om_scan() {
    awk -v flist="$TMPD/forbidden" -v hlist="$TMPD/host" -v alist="$TMPD/allow" -v used="${OM_SCAN_USED:-/dev/null}" '
    BEGIN { while ((getline l < flist) > 0) F[l] = 1; bad = 0
            while ((getline l < hlist) > 0) H[l] = 1
            while ((getline l < alist) > 0) A[l] = 1 }
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
            if (w[i] in H) {
                if (!(w[i] in A)) hit("uses OM-2 host word " w[i] ", which is not on the allowlist of host words omega uses")
                else print w[i] > used
            }
            if (w[i] == "fopen") {
                # fopen path off len flags mode: only literal read-only flags (0, O_DIRECTORY 16384)
                if (!(i + 4 <= n && (w[i + 4] == "0" || w[i + 4] == "16384")))
                    hit("fopen whose flags are not literally read-only (0 or 16384)")
            }
        }
    }
    END { exit bad }' "$@"
}

om_files=""
for f in "$ROOT"/tools/omega.om "$ROOT"/tools/omega_*.om "$ROOT"/om/visor/*.om "$ROOT"/src/visor/*.om \
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
OM_SCAN_USED="$TMPD/used" om_scan $om_files || { echo "FAIL: an OM-2 source of the omega binary names an authority operation"; fail=1; }
for w in $ALLOW; do
    grep -qx "$w" "$TMPD/used" || { echo "FAIL: allowlisted host word $w is used by no scanned source; remove it from the allowlist"; fail=1; }
done

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
bite "process start" '  pid = fork'
bite "program exec" '  r = execprog verq_bad 0 0'
bite "socket" '  s = socknew 2 1 0'
bite "device control" '  devctl 3 0 0'
bite "file system change" '  unlink verq_bad 0 0'
bite "descriptor duplication (not on the allowlist)" '  fd = dupfd 1 9 0'
bite "pipe (not on the allowlist)" '  r = pipefds verq_bad'
bite "event descriptor (not on the allowlist)" '  fd = eventfd 0 0'
bite "working directory change (not on the allowlist)" '  r = chdir verq_bad 0 0'
bite "umask (not on the allowlist)" '  r = umask 0'
bite "map read (not on the allowlist)" '  r = mapread 0 verq_bad 0 0'
bite "kfd control (in the compiler table, not in seed/ng/hostwords.tsv)" '  r = kfdctl 0 0 0'
bite "environment read (not on the allowlist)" '  r = envread 0 verq_bad 0 0'
bite "fopen for writing" '  fd = fopen verq_bad 0 8 577 420'
bite "fopen with computed flags" '  fd = fopen verq_bad 0 8 get verq_fl 0 0'
cp "$BASE" "$TMPD/plant.om"
printf '%s\n' 'note rx_capadmin_mint authorized aienos_cap_mint fork socknew' \
    'text verq_ok "rx_capadmin_mint \",\"authorized\":false fork execprog dupfd umask"' \
    '  fd = fopen verq_ok 0 8 0 0' '  fd = fopen verq_ok 0 8 16384 0' \
    '  k = read 0 verq_ok 0 1' '  k = write 1 verq_ok 0 1' '  r = stat verq_ok 0 8 verq_ok 0 1' >> "$TMPD/plant.om"
om_scan "$TMPD/plant.om" > /dev/null || { echo "FAIL: bite control false positive (a note line or a literal tripped the scan)"; fail=1; }

if [ "$fail" -ne 0 ]; then
    echo "OMEGA_VISOR_AUTHORITY_ISOLATION_FAIL"
    exit 1
fi
echo "checked $nom OM-2 source(s) (0 Visor C/H files) against $(printf '%s\n' $forbidden | wc -l) forbidden symbols and $nhost host words (allowlist: $ALLOW); $bites/$nbite bite controls caught"
echo "OMEGA_VISOR_AUTHORITY_ISOLATION_PASS"
exit 0
