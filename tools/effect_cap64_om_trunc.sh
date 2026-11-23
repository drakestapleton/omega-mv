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

# effect_cap64_om_trunc.sh -- the OM-2 half of the effect capability generation
# truncation grep (spec/effect-cap64-migration.md section 2.5). The console
# wiring that tools/omega.c held is now OM-2 (tools/omega*.om, src/visor/*.om),
# where a C `(uint32_t)` cast or `%u` cannot occur; the OM forms of the same
# mistake are a generation held in a narrower type, decoded or encoded through a
# 16/32-bit helper, or encoded with a width below 8 bytes.
#
#   tools/effect_cap64_om_trunc.sh [root]   (default: the repository root)
#
# Prints one line per hit (file:line: text) on stdout. A bite control runs
# first: each truncation form is planted in a copy of visor_effect_request.om
# and must be caught, and the unplanted copy must be clean.
# Exit 0: no hit. Exit 1: hits. Exit 2: the bite control or the file list failed.
set -u
ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}

# trunc_scan file...: code lines (note lines skipped, string literals blanked)
# that name a generation and also a sub-64-bit type, a 16/32-bit codec helper,
# or a v_enc_*pay call with a width of 1 to 7 bytes.
trunc_scan() {
    awk '
    BEGIN { bad = 0 }
    /^[[:space:]]*note([[:space:]]|$)/ { next }
    {
        code = $0
        gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
        if (code !~ /(cap_gen|capability_generation|generation)/) next
        if (code ~ /(^|[^A-Za-z0-9_])(uint|int|ushort|short|uchar|char)([^A-Za-z0-9_]|$)/ ||
            code ~ /(u32|u16|32le|32be|16le|16be)/ ||
            code ~ /v_enc_[a-z_]*pay[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[1-7]([^0-9]|$)/) {
            print FILENAME ":" FNR ": " $0; bad = 1
        }
    }
    END { exit bad }' "$@"
}

files=""
for f in "$ROOT"/tools/omega*.om "$ROOT"/om/visor/*.om "$ROOT"/src/visor/*.om \
         "$ROOT"/src/language/*.om "$ROOT"/om/aarch64/aarch64_om2.om; do
    [ -e "$f" ] && files="$files $f"
done
BASE="$ROOT/src/visor/visor_effect_request.om"
if [ -z "$files" ] || [ ! -e "$BASE" ] || [ ! -e "$ROOT/tools/omega_ops.om" ]; then
    echo "effect_cap64_om_trunc: OM-2 sources not found under $ROOT" >&2; exit 2
fi

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/cap64-trunc.XXXXXX") || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
cp "$BASE" "$TMPD/p.om"
trunc_scan "$TMPD/p.om" > /dev/null || { echo "effect_cap64_om_trunc: bite baseline not clean" >&2; exit 2; }
for plant in 'global verq_cap_gen32 uint 1' \
             '  put verq_cap_gen 0 v_dec_u32le_pay pb 8' \
             '  v_enc_be_pay pb 8 4 cap_gen'; do
    cp "$BASE" "$TMPD/p.om" && printf '%s\n' "$plant" >> "$TMPD/p.om"
    if trunc_scan "$TMPD/p.om" > /dev/null; then
        echo "effect_cap64_om_trunc: bite control not caught: $plant" >&2; exit 2
    fi
done
echo "effect_cap64_om_trunc: 3/3 bite controls caught" >&2

# shellcheck disable=SC2086
trunc_scan $files
