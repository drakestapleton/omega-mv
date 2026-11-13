#!/bin/sh
# TEST INSTRUMENT: generator-pin consumers derive the expected src/native.om from om/omega-bridge.lock.
# usage: generator-check.sh BRIDGE  (an omega-bridge git checkout that holds the lock commit)
# Positive: om/units.sh --check passes with the generator at the lock. Negative: the same checkout with one
# byte appended to src/native.om (not committed) is refused with NOT_RUN exit 3 before the generator runs.
# The om/*/parity runners pin a different generator (012860db) on purpose; they are not consumers of the lock. Exit 0 PASS, 1 FAIL, 3 NOT_RUN.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
BR=${1:?usage: generator-check.sh BRIDGE}
BR=$(cd "$BR" && pwd)
OMC=$ROOT/seed/out/omc
lock=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$ROOT/om/omega-bridge.lock")
git -C "$BR" cat-file -e "$lock:src/native.om" 2> /dev/null || { echo "GENERATOR-PINS NOT_RUN: $BR lacks $lock"; exit 3; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT HUP INT TERM
git clone -q --no-local "$BR" "$T/good"; git -C "$T/good" checkout -q --detach "$lock"
git clone -q --no-local "$BR" "$T/bad"; git -C "$T/bad" checkout -q --detach "$lock"
printf '\n' >> "$T/bad/src/native.om"
fails=0; n=0
ctl() { # NAME WANT_RC TEXT CMD...
  name=$1; want=$2; text=$3; shift 3; n=$((n + 1)); rc=0
  (cd "$ROOT" && "$@") > "$T/$name.log" 2>&1 || rc=$?
  if [ "$rc" = "$want" ] && grep -qF -- "$text" "$T/$name.log"; then echo "PASS $name: exit $rc, $text"
  else echo "FAIL $name: exit $rc (want $want with \"$text\")"; tail -n 5 "$T/$name.log" | sed 's/^/  | /'; fails=$((fails + 1)); fi
}
ctl units-good 0 "regenerate byte for byte" env OMEGA_OMC="$OMC" OMEGA_BRIDGE="$T/good" sh om/units.sh --check
ctl units-wrong-generator 3 "NOT_RUN: native.om is not the pinned generator" env OMEGA_OMC="$OMC" OMEGA_BRIDGE="$T/bad" sh om/units.sh --check
[ "$fails" = 0 ] || { echo "GENERATOR-PINS FAIL failed=$fails controls=$n"; exit 1; }
echo "GENERATOR-PINS PASS controls=$n"
