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

# parity_check.sh -- are two sides of a head-to-head row doing the same work?
# (docs/perf/HEAD_TO_HEAD_PROTOCOL.md sections 4 and 5.) Reads files only.
#
#   parity_check.sh <side-a.decl> <side-b.decl>
#
# A declaration is "key=value" lines ('#' comments allowed). Every key below
# must be present and non-empty on both sides; "unknown", "default", "tbd"
# and "n/a" are not values. Exit 0 = SAME_WORK, 1 = DIFFERENT_WORK (the row
# may still be published, labelled with both formats, never as "same
# precision"), 2 = usage, 3 = a declaration is incomplete (no row at all).
#
# Must be equal:        weights_dtype activation_dtype kv_cache_dtype
#                       tokenizer_sha256 bos chat_template_applied_by
#                       prompt_set_sha256 prompt_token_counts_sha256
#                       output_tokens sampler context_tokens
# Must be declared:     engine engine_commit weights_format weights_sha256
#                       source_checkpoint_sha256
# Must be equal too:    source_checkpoint_sha256 (same model, whatever the container)
set -u
EQ="weights_dtype activation_dtype kv_cache_dtype tokenizer_sha256 bos chat_template_applied_by prompt_set_sha256 prompt_token_counts_sha256 output_tokens sampler context_tokens source_checkpoint_sha256"
DECL="engine engine_commit weights_format weights_sha256"

[ $# -eq 2 ] && [ -r "$1" ] && [ -r "$2" ] || { sed -n '17,34p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# get <file> <key>: last value of key, trimmed, lower-cased.
get() {
    awk -v k="$2" '
        /^[ \t]*#/ { next }
        { i = index($0, "="); if (!i) next
          key = substr($0, 1, i - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
          if (key != k) next
          v = substr($0, i + 1); gsub(/^[ \t]+|[ \t\r]+$/, "", v) }
        END { print tolower(v) }' "$1"
}
placeholder() { case "$1" in ''|unknown|default|tbd|n/a|'?') return 0 ;; *) return 1 ;; esac; }

missing=0; differ=0
for k in $DECL $EQ; do
    a=$(get "$1" "$k"); b=$(get "$2" "$k")
    if placeholder "$a"; then echo "MISSING $k in $1"; missing=1; fi
    if placeholder "$b"; then echo "MISSING $k in $2"; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "VERDICT INCOMPLETE"; exit 3; }

for k in $EQ; do
    a=$(get "$1" "$k"); b=$(get "$2" "$k")
    if [ "$a" = "$b" ]; then echo "SAME      $k = $a"
    else echo "DIFFERENT $k: $a | $b"; differ=1; fi
done
for k in $DECL; do echo "DECLARED  $k: $(get "$1" "$k") | $(get "$2" "$k")"; done

if [ "$differ" -eq 0 ]; then echo "VERDICT SAME_WORK"; exit 0; fi
echo "VERDICT DIFFERENT_WORK"; exit 1
