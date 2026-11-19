#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/omega-argus-lock.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM
GOOD=$(tr -d '\n' < "$ROOT/argus.lock")
FAILS=0

accept() {
    local name=$1 content=$2
    printf '%s' "$content" > "$TMP/argus.lock"
    if make -s -C "$TMP" -f "$ROOT/Makefile" check-argus-lock >"$TMP/make.log" 2>&1; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        FAILS=$((FAILS + 1))
    fi
}

reject() {
    local name=$1 content=$2
    printf '%s' "$content" > "$TMP/argus.lock"
    if make -s -C "$TMP" -f "$ROOT/Makefile" check-argus-lock >"$TMP/make.log" 2>&1; then
        printf 'FAIL %s\n' "$name"
        FAILS=$((FAILS + 1))
    elif grep -q 'argus.lock must contain exactly one lowercase 40-hex commit' "$TMP/make.log"; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (wrong refusal)\n' "$name"
        FAILS=$((FAILS + 1))
    fi
}

accept "one lowercase commit" "$GOOD"$'\n'
accept "commit without final newline" "$GOOD"
reject "empty lock" ""
reject "abbreviated commit" "${GOOD:0:39}"$'\n'
reject "uppercase commit" "${GOOD^^}"$'\n'
reject "leading whitespace" " $GOOD"$'\n'
reject "trailing whitespace" "$GOOD "$'\n'
reject "extra field" "$GOOD extra"$'\n'
reject "option-like value" "--$GOOD"$'\n'
reject "second commit" "$GOOD"$'\n'"$GOOD"$'\n'
reject "trailing blank line" "$GOOD"$'\n\n'
reject "trailing comment" "$GOOD"$'\n# comment\n'

PWNED="$TMP/shell-metacharacters-ran"
reject "shell metacharacters" "$GOOD ; touch $PWNED"$'\n'
if [ -e "$PWNED" ]; then
    echo "FAIL shell metacharacters executed"
    FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -ne 0 ]; then
    echo "argus lock validation: $FAILS FAILED"
    exit 1
fi
echo "argus lock validation: PASS"
