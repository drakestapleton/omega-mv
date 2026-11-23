#!/bin/sh
# Drive check-prefetch-switch across DSV41_ARBORIS_PREFETCH cases.
# usage: check-prefetch-switch.sh PATH/TO/check-prefetch-switch
# Exit codes of the control: 10 on, 11 off, 12 refused (with one stderr line).
set -u
bin=$1
fail=0
k=DSV41_ARBORIS_PREFETCH
msg="dsv41-decode: DSV41_ARBORIS_PREFETCH must be unset, 0 or 1"
err=$(mktemp)
trap 'rm -f "$err"' EXIT

case_() {
  want=$1; label=$2; shift 2
  env -i "$@" "$bin" 2> "$err"
  got=$?
  ok=1
  [ "$got" = "$want" ] || ok=0
  if [ "$want" = 12 ]; then
    [ "$(cat "$err")" = "$msg" ] || ok=0
  else
    [ ! -s "$err" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then echo "PASS $label ($got)"; else echo "FAIL $label want $want got $got stderr=$(cat "$err")"; fail=1; fi
}

# Largest single entry execve accepts: MAX_ARG_STRLEN = 131072 bytes including the trailing zero.
big="BIG=$(head -c 131067 /dev/zero | tr '\0' a)"

case_ 10 unset
case_ 10 one "$k=1"
case_ 11 zero "$k=0"
case_ 12 empty "$k="
case_ 12 two "$k=2"
case_ 12 double-zero "$k=00"
case_ 12 leading-zero "$k=01"
case_ 12 trailing-space "$k=0 "
case_ 12 word "$k=off"
case_ 10 longer-name "${k}X=0"
case_ 10 shorter-name "DSV41_ARBORIS_PREFETC=0"
case_ 10 lower-case "dsv41_arboris_prefetch=0"
case_ 10 big-entry-unset "$big"
case_ 11 big-entry-zero "$big" "$k=0"
case_ 11 zero-among-others "A=1" "$k=0" "Z=2"
# A repeated key cannot be produced with env(1), which keeps one value per name; the parser
# refuses a second matching entry (prefetch-switch.om, "if seen").

if [ "$fail" = 0 ]; then echo "PREFETCH-SWITCH PASS"; else echo "PREFETCH-SWITCH FAIL"; fi
exit "$fail"
