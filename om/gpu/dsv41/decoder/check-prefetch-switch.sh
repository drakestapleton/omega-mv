#!/bin/sh
# Drive check-prefetch-switch across DSV41_ARBORIS_PREFETCH cases.
# usage: check-prefetch-switch.sh PATH/TO/check-prefetch-switch
# Exit codes of the control: 10 on, 11 off, 12 refused (with one stderr line).
set -u
bin=$1
# The repeated-name mode re-executes argv[0], so pass an absolute path.
case "$bin" in /*) ;; *) bin="$(pwd)/$bin" ;; esac
# An empty file runs as exit 0 under sh; refuse anything that is not a non-empty ELF executable.
if [ ! -x "$bin" ] || [ ! -s "$bin" ] || [ "$(head -c 4 "$bin" | od -An -c | tr -d ' ')" != '177ELF' ]; then
  echo "PREFETCH-SWITCH FAIL: $bin is not a non-empty ELF executable"
  exit 2
fi
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
# More entries than a 65536-entry loop bound: a default run must still work, and the key is still found last.
many=$(seq -f "V%.0f=1" 70000)
case_ 10 many-entries-unset $many
case_ 11 many-entries-zero $many "$k=0"
# Repeated names: env(1) keeps one value per name, so the control re-runs itself through execenv.
"$bin" dup 2> "$err"
got=$?
lines=$(grep -c -x -F "$msg" "$err")
other=$(grep -v -c -x -F "$msg" "$err")
if [ "$got" = 50 ] && [ "$lines" = 3 ] && [ "$other" = 0 ]; then echo "PASS repeated-name (50, 3 refusals)"
else echo "FAIL repeated-name want 50 and 3 refusal lines, got $got, $lines refusal lines, $other other lines"; fail=1; fi

if [ "$fail" = 0 ]; then echo "PREFETCH-SWITCH PASS"; else echo "PREFETCH-SWITCH FAIL"; fi
exit "$fail"
