#!/bin/sh
# TEST INSTRUMENT: run the existing seeded front gate with a supplied compiler (also accepts the recording wrapper).
# This runner by itself is not a pinned qualification: its supplied compiler hash is self-derived.
# No first-party runtime implementation. The gate program decides every case and mutant result.
set -eu
cd "$(dirname "$0")/../../.."
OMC=${1:-${OMC:-seed/out/omc}}
OMC=$(readlink -f "$OMC")
[ -x "$OMC" ] || { echo 'FRONTGATE NOT_RUN: compiler missing' >&2; exit 3; }
mkdir -p build
B=$(mktemp -d build/front-owner.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
"$OMC" < seed/ng/front/gate-front.om > "$B/gate"
chmod +x "$B/gate"
pin=$(sha256sum "$OMC")
pin=${pin%% *}
"$B/gate" "$OMC" "$pin" units:seed/ng/ng.units+in:seed/ng/front/front-check.in \
  seed/ng/front/declared.txt seed/ng/front/mutants.txt "$B/run" \
  seed/ng/front/cases-front.txt seed/ng/front/cases-om2.txt seed/ng/front/cases-tests.txt \
  seed/qualification/om2/manifest-c2.txt seed/ng/front/cases-fconv.txt seed/ng/front/cases-host.txt
