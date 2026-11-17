#!/bin/sh
# ck_allen_ui_stream_test.sh -- a streamed answer keeps the letters already
# showing (L853, native/kernel/ui/tests/allen_ui_stream_test.c). The courier
# hands each later fragment over as the whole text so far through
# ck_allen_ui_said_more: it joins the words on screen, gliding a centred line
# that grew, and starts fresh only when the words are not those, are gone, or
# belong to a reply not yet shown. The old call (ck_allen_ui_said) must still
# blank the strip, so the checks can see the defect, and two mutants of the UI
# must be caught: a join that always refuses, and a continuation that ignores a
# fresh reply still waiting. Hosted only. Ends with "AIENOS_ALLEN_UI_STREAM:
# PASS" or "AIENOS_ALLEN_UI_STREAM: FAIL <why>".
set -u
cd "$(dirname "$0")/.."
K=native/kernel
CC=${HOSTCC:-cc}
W=$(mktemp -d "${TMPDIR:-/tmp}/ck_allen_ui_stream.XXXXXX")
trap 'rm -rf "$W"' EXIT
fail() { echo "AIENOS_ALLEN_UI_STREAM: FAIL $*"; exit 1; }
build() { # build OUT ALLEN_UI_C
    $CC -std=gnu11 -O2 -Wall -Wextra -Werror -pthread -I "$K" -I "$K/ui" -o "$1" \
        $K/ui/tests/allen_ui_stream_test.c "$2" $K/svc/allen_code.c $K/ui/paint.c $K/ui/night.c \
        $K/ui/sky_real.c $K/ui/sky_data.c $K/ui/mind.c $K/ui/flow.c $K/ui/allen_font.c $K/ui/canvas.c \
        $K/svc/allen_scene.c $K/svc/allen_reply.c $K/svc/allen_notes.c $K/svc/allen_intent.c \
        $K/svc/setup_wizard.c $K/svc/setup_inv.c
}
build "$W/stream" $K/ui/allen_ui.c || fail "stream test does not build"
"$W/stream" join || fail "a later fragment blanked the letters"
"$W/stream" glide || fail "a fragment that wraps to a new line blanked the letters or left a partial redraw"
"$W/stream" restart || fail "the old call did not blank; the check cannot see the defect"
"$W/stream" mismatch || fail "a different reply was glued on"
"$W/stream" pending || fail "an early continuation restarted"
"$W/stream" faded || fail "a continuation after the words were gone did not start fresh"
"$W/stream" coalesced || fail "a continuation of a reply not yet shown was glued to the old words"

# Mutant 1: the join refuses every continuation. The join arm must fail.
awk '
/^static int join_words\(const char \*reply, uint32_t t\)$/ { print; getline; print
    print "    return 0; /* mutant: every continuation starts over */"; next }
{ print }' $K/ui/allen_ui.c > "$W/refuse.c"
grep -q "mutant: every continuation" "$W/refuse.c" || fail "the refusing mutant did not land"
build "$W/refuse" "$W/refuse.c" || fail "the refusing mutant does not build"
if "$W/refuse" join; then fail "the refusing mutant still passed the join arm"; fi

# Mutant 2: a continuation always joins, even when a fresh reply has not been
# taken yet. The coalesced arm must fail.
awk '
/if \(note\.said_gen == ui\.seen_said\) \{/ { sub(/note\.said_gen == ui\.seen_said/, "1 /* mutant */") }
{ print }' $K/ui/allen_ui.c > "$W/always.c"
grep -q "1 /\* mutant \*/" "$W/always.c" || fail "the always-join mutant did not land"
build "$W/always" "$W/always.c" || fail "the always-join mutant does not build"
if "$W/always" coalesced; then fail "the always-join mutant still passed the coalesced arm"; fi
echo "AIENOS_ALLEN_UI_STREAM: PASS"
