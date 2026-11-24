#!/bin/sh
# Decoder-level control for DSV41_ARBORIS_PREFETCH: runs the real dsv41-decode in pfcheck mode (host only,
# no GPU), which parses the variable, loads the inputs and starts the payload workers exactly as gen does.
# usage: check-decoder-prefetch.sh DSV41_DECODE TENSORS ENGRAM_MAP SIDECAR_DIR CKPT_DIR
set -u
bin=$1 tensors=$2 map=$3 sidecars=$4 ckpt=$5
k=DSV41_ARBORIS_PREFETCH
msg="dsv41-decode: DSV41_ARBORIS_PREFETCH must be unset, 0 or 1"
if [ ! -x "$bin" ] || [ ! -s "$bin" ] || [ "$(head -c 4 "$bin" | od -An -c | tr -d ' ')" != '177ELF' ]; then
  echo "DECODER-PREFETCH FAIL: $bin is not a non-empty ELF executable"
  exit 2
fi
err=$(mktemp)
trap 'rm -f "$err"' EXIT
fail=0

# case_ WANT_RC WANT_STDERR LABEL ENV...
case_() {
  want_rc=$1 want_err=$2 label=$3; shift 3
  env -i "$@" "$bin" pfcheck "$tensors" "$map" "$sidecars" "$ckpt" > /dev/null 2> "$err"
  rc=$?
  got_err=$(cat "$err")
  if [ "$rc" = "$want_rc" ] && [ "$got_err" = "$want_err" ]; then echo "PASS $label ($rc: $got_err)"
  else echo "FAIL $label want $want_rc [$want_err] got $rc [$got_err]"; fail=1; fi
}

case_ 0 "ARBORIS pf_enabled=1" unset
case_ 0 "ARBORIS pf_enabled=1" one "$k=1"
case_ 0 "ARBORIS pf_enabled=0" zero "$k=0"
case_ 64 "$msg" two "$k=2"
case_ 64 "$msg" empty "$k="

if [ "$fail" = 0 ]; then echo "DECODER-PREFETCH PASS"; else echo "DECODER-PREFETCH FAIL"; fi
exit "$fail"
