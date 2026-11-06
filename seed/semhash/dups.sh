#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/semhash/dups.sh: duplicate-function report (#827 M1) over the .om units of om/ and seed/.
# Usage: seed/semhash/dups.sh SEMHASH [-i INDEX] [DIR...]   DIR defaults to "om seed", relative to
# the repo root. Each unit is hashed with `SEMHASH hash`, every FN line gets the unit's path in
# front, and `SEMHASH dups` groups the functions whose meaning hashes are equal. A unit that
# semhash refuses (or a path holding a space) becomes a "SKIP path rc=N reason" line, counted in
# the summary. With -i, the full function index (every "PATH FN name hex line=N..." record and
# every SKIP line, in path order) is also written to INDEX, relative to the caller's directory.
# The grouping is done by semhash.om; this script only lists files and runs the tool.
set -u
SH=${1:?usage: dups.sh SEMHASH [-i INDEX] [DIR...]}
case $SH in /*) ;; *) SH=$PWD/$SH ;; esac
[ -x "$SH" ] || { printf 'dups.sh: no semhash binary at %s\n' "$SH" >&2; exit 2; }
shift
IX=/dev/null
if [ "${1:-}" = -i ]; then
    IX=${2:?usage: dups.sh SEMHASH [-i INDEX] [DIR...]}
    case $IX in /*) ;; *) IX=$PWD/$IX ;; esac
    shift 2
fi
cd "$(dirname "$0")/../.." || exit 2
[ $# -gt 0 ] || set -- om seed
E=$(mktemp) || exit 2
trap 'rm -f "$E"' EXIT
find "$@" -name '*.om' -type f | LC_ALL=C sort | while IFS= read -r f; do
    case $f in *' '*) printf 'SKIP %s rc=2 space in path\n' "$(printf '%s' "$f" | tr ' ' '_')"; continue ;; esac
    if out=$("$SH" hash < "$f" 2> "$E"); then
        printf '%s\n' "$out" | sed -n "s|^FN |$f FN |p"
    else
        printf 'SKIP %s rc=%s %s\n' "$f" "$?" "$(tr '\n' ' ' < "$E" | sed 's/ *$//')"
    fi
done | tee "$IX" | "$SH" dups
