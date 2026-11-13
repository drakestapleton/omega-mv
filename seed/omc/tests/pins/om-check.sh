#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/omc/tests/pins/om-check.sh: wrong-compiler controls for every consumer whose compiler pin is
# read from seed/out/omc.sha256 (the record seed/omega-from-seed.sh writes beside seed/out/omc).
# Usage, from anywhere: sh seed/omc/tests/pins/om-check.sh [OMC]   (OMC defaults to seed/out/omc)
# The expected pin is read only from seed/out/omc.sha256, never from the compiler under test. OMC must
# match that record; it only builds seed/profile/check.om. Each control hands its consumer a scratch
# executable whose sha256 differs from the record, with every earlier precondition satisfied, and
# requires exit 3 plus the consumer's own refusal line. Any other exit or reason is a FAIL. The scratch
# executable appends to a marker file when it runs; a control after which the marker exists is a FAIL
# (the compiler was executed before it was refused). Two more
# controls show that the pin follows the record: units.sh with the record rewritten to the scratch
# compiler gets past the compiler check, and check.om with a malformed record refuses before it.
# Positive runs with the pinned compiler are the consumers' own gates, not repeated here.
# Exit 0 PASS (last line "PINS-OM PASS controls=N"), 1 FAIL, 3 NOT_RUN (no valid record, OMC is not
# the recorded compiler, or python3/sha256sum missing).
set -eu
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
for t in sha256sum python3 sed grep; do
  command -v $t > /dev/null || { echo "PINS-OM NOT_RUN: $t missing"; exit 3; }
done
PIN=$(sed -n '$!d;1s/^\([0-9a-f]\{64\}\)  seed\/out\/omc$/\1/p' "$ROOT/seed/out/omc.sha256" 2>/dev/null) || PIN=
[ ${#PIN} = 64 ] || { echo "PINS-OM NOT_RUN: no compiler pin in seed/out/omc.sha256"; exit 3; }
[ -x "$OMC" ] && [ "$(sha256sum < "$OMC" | cut -c1-64)" = "$PIN" ] || { echo "PINS-OM NOT_RUN: $OMC is not the recorded compiler $PIN"; exit 3; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
WRONG=$T/wrong-omc
MARK=$T/executed
printf '#!/bin/sh\n# scratch compiler for om-check.sh: never the pinned omc; running it leaves the marker\nprintf '"'"'executed\\n'"'"' >> '"'"'%s'"'"'\nexit 97\n' "$MARK" > "$WRONG"; chmod 755 "$WRONG"
WSHA=$(sha256sum < "$WRONG" | cut -c1-64)
[ "$WSHA" != "$PIN" ] || { echo "FAIL scratch compiler hashes to the pin"; exit 1; }
mkdir "$T/bridge"
echo "pin $PIN"
echo "scratch compiler $WSHA"
fails=0; n=0

# ctl NAME RC TEXT CMD...: CMD (run from the repository root) must exit RC and print TEXT.
ctl() {
  name=$1; want=$2; text=$3; shift 3
  n=$((n + 1))
  rc=0; (cd "$ROOT" && "$@") > "$T/$name.log" 2>&1 || rc=$?
  if [ -e "$MARK" ]; then
    echo "FAIL $name: the scratch compiler was executed (exit $rc)"; rm -f "$MARK"; fails=$((fails + 1))
  elif [ "$rc" = "$want" ] && grep -qF -- "$text" "$T/$name.log"; then
    echo "PASS $name: exit $rc, $text, scratch compiler not executed"
  else
    echo "FAIL $name: exit $rc (want $want with \"$text\"):"; sed 's/^/  | /' "$T/$name.log" | tail -n 5
    fails=$((fails + 1))
  fi
}

# Static: no owned consumer types a compiler digest; each reads the record.
CONSUMERS="om/units.sh om/aarch64/parity/run.sh om/codec/parity/run.sh om/evidence/parity/run.sh
om/gpumath/parity/run.sh om/receipt/parity/run.sh om/tls/test/ec/run.sh om/tls/test/ecdh/run.sh
om/tls/test/rev/run.sh om/tls/test/rsa/run.sh om/tls/test/x509/run.sh om/tls/test/x509/limbo.sh"
for f in $CONSUMERS; do
  n=$((n + 1))
  if grep -qE '^(OMC_PIN|pin)=[0-9a-f]{64}' "$ROOT/$f" || ! grep -qF 'seed/out/omc.sha256' "$ROOT/$f"; then
    echo "FAIL static $f: typed compiler pin, or no seed/out/omc.sha256 reader"; fails=$((fails + 1))
  else
    echo "PASS static $f"
  fi
done

ctl units 3 "NOT_RUN: omc is not the pinned compiler" env OMEGA_OMC="$WRONG" OMEGA_BRIDGE="$T/bridge" sh om/units.sh --check
for p in aarch64:AARCH64 evidence:EVIDENCE gpumath:GPUMATH receipt:RECEIPT; do
  d=${p%%:*}; tag=${p#*:}
  ctl "$d-parity" 3 "$tag-PARITY NOT_RUN: omc is not the pinned compiler" env OMEGA_OMC="$WRONG" sh "om/$d/parity/run.sh"
done
ctl codec-parity 3 "NOT_RUN: $WRONG is not the pinned omc" env OMEGA_OMC="$WRONG" sh om/codec/parity/run.sh
ctl tls-ec 3 "EC NOT_RUN: omc is not the pinned compiler $PIN" sh om/tls/test/ec/run.sh "$WRONG"
ctl tls-ecdh 3 "ECDH NOT_RUN: omc is not the pinned compiler $PIN" sh om/tls/test/ecdh/run.sh "$WRONG"
ctl tls-rsa 3 "RSA NOT_RUN: omc is not the pinned compiler $PIN" sh om/tls/test/rsa/run.sh "$WRONG"
ctl tls-rev 3 "REV NOT_RUN: omc is not the pinned compiler" sh om/tls/test/rev/run.sh "$WRONG"
ctl tls-x509 3 "X509 NOT_RUN: omc is not the pinned compiler" sh om/tls/test/x509/run.sh "$WRONG"
ctl tls-limbo 3 "LIMBO NOT_RUN: omc is not the pinned compiler" sh om/tls/test/x509/limbo.sh "$WRONG" "$T/limbo-src"

# seed/profile/check.om reads seed/out/omc relative to its working directory: run the checker,
# built by the recorded compiler, in a scratch tree whose seed/out/omc is the scratch compiler.
"$OMC" < "$ROOT/seed/profile/check.om" > "$T/profile-check" 2> "$T/profile-check.err" && [ ! -s "$T/profile-check.err" ] || {
  echo "FAIL seed/profile/check.om does not compile: $(cat "$T/profile-check.err")"; exit 1; }
chmod 755 "$T/profile-check"
for s in profile profile-badpin; do
  mkdir -p "$T/$s/seed/out" "$T/$s/seed/qualification/om2/fixtures"
  cp "$ROOT/seed/qualification/om2/fixtures/sha256-k.dec" "$ROOT/seed/qualification/om2/fixtures/sha256-iv.dec" "$T/$s/seed/qualification/om2/fixtures/"
  cp "$WRONG" "$T/$s/seed/out/omc"
done
cp "$ROOT/seed/out/omc.sha256" "$T/profile/seed/out/omc.sha256"
printf '%s  seed/out/omc\n' "$(printf '%s' "$PIN" | cut -c1-63)" > "$T/profile-badpin/seed/out/omc.sha256"
ctl profile-check 3 "NOT_RUN profile: omc is not the pinned compiler $PIN" sh -c 'cd "$1" && exec "$2"' sh "$T/profile" "$T/profile-check"
ctl profile-check-record 3 "NOT_RUN profile: no compiler pin in seed/out/omc.sha256" sh -c 'cd "$1" && exec "$2"' sh "$T/profile-badpin" "$T/profile-check"

# qualify.py derives its root from its own path: a scratch tree with the recorded pin and the scratch
# compiler at seed/out/omc. The refusal comes before any snapshot, tool or bridge use.
Q=$T/qualify; mkdir -p "$Q/seed/out" "$Q/seed/qualification/om2/current"
cp "$ROOT/seed/qualification/om2/current/qualify.py" "$Q/seed/qualification/om2/current/"
cp "$ROOT/seed/out/omc.sha256" "$Q/seed/out/omc.sha256"; cp "$WRONG" "$Q/seed/out/omc"
ctl qualify 3 "ABI_SHA_GATE NOT_RUN: omc is not the pinned compiler $PIN" python3 "$Q/seed/qualification/om2/current/qualify.py" --bridge "$T/bridge" --output "$T/qualify-out"

# The pin follows the record: with the record naming the scratch compiler, units.sh passes its
# compiler check and stops at the generator check instead.
U=$T/units; mkdir -p "$U/om" "$U/seed/out"
cp "$ROOT/om/units.sh" "$U/om/units.sh"; cp "$ROOT/om/omega-bridge.lock" "$U/om/omega-bridge.lock"; printf '%s  seed/out/omc\n' "$WSHA" > "$U/seed/out/omc.sha256"
ctl units-record 3 "NOT_RUN: OMEGA_BRIDGE has no src/native.om at om/omega-bridge.lock" env OMEGA_OMC="$WRONG" OMEGA_BRIDGE="$T/bridge" sh "$U/om/units.sh" --check

if [ "$fails" = 0 ]; then echo "PINS-OM PASS controls=$n"; exit 0; fi
echo "PINS-OM FAIL failed=$fails controls=$n"; exit 1
