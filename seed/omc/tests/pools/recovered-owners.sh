#!/bin/sh
# TEST INSTRUMENT: exact-byte standalone acceptance/refusal witnesses for recovered pool users.
# Source declarations carry the intent once. No path inventory is maintained here; every marked source is compiled.
# This owns standalone acceptance/refusal only; a fragment's independent composite qualification is not claimed.
set -eu
cd "$(dirname "$0")/../../../.."
OMC=${1:-${OMC:-seed/out/omc}}
OMC=$(readlink -f "$OMC")
SELF=seed/omc/tests/pools/recovered-owners.sh
mkdir -p build/seed
B=$(mktemp -d build/seed/recovered-owners.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
# A recording wrapper may be supplied: keep it as the compiler, but compare self output to the real pinned artifact.
REAL=${OMC_BINARY:-$OMC}
git grep -l -F "owner=$SELF " -- '*.om' > "$B/units" || { echo 'RECOVERED-OWNERS FAIL: no declared units'; exit 1; }
n=0
while IFS= read -r u; do
  spec=$(awk -v owner="owner=$SELF" '$1=="note" && $2=="gate-pools:" && $7==owner {for(i=8;i<=NF;i++) if($i ~ /^(compile|run|as|self|refusal)=/) print $i}' "$u")
  want= run= budget= self= refusal=
  for field in $spec; do
    case $field in compile=*) want=${field#compile=};; run=*) run=${field#run=};; as=*) budget=${field#as=};; self=*) self=${field#self=};; refusal=*) refusal=${field#refusal=};; esac
  done
  case $want in ''|*[!0-9]*) echo "RECOVERED-OWNERS FAIL: invalid compile intent $u"; exit 1;; esac
  if timeout 60 "$OMC" < "$u" > "$B/unit" 2> "$B/err"; then got=0; else got=$?; fi
  [ "$got" = "$want" ] || { echo "RECOVERED-OWNERS FAIL $u compile=$got wanted=$want"; cat "$B/err"; exit 1; }
  if [ "$got" != 0 ]; then
    # The refusal is the compiler's one named line and nothing else, with no output written.
    [ "$(wc -l < "$B/err")" = 1 ] && grep -Eqx "omc: line [0-9]+: error $want" "$B/err" || { echo "RECOVERED-OWNERS FAIL $u refusal is not the one line 'omc: line N: error $want'"; cat "$B/err"; exit 1; }
    [ ! -s "$B/unit" ] || { echo "RECOVERED-OWNERS FAIL $u refusing compilation wrote output"; exit 1; }
    if [ -n "$refusal" ]; then
      [ "$refusal" = standalone-view ] && [ "$got" = 16 ] || { echo "RECOVERED-OWNERS FAIL $u unknown refusal scope"; exit 1; }
      line=$(sed -n 's/^omc: line \([0-9][0-9]*\): error 16$/\1/p' "$B/err")
      case $line in ''|*[!0-9]*) echo "RECOVERED-OWNERS FAIL $u missing standalone-view line"; exit 1;; esac
      sed -n "${line}p" "$u" > "$B/refusal-source"
      grep -q '^fn .* view uchar \*' "$B/refusal-source" || { echo "RECOVERED-OWNERS FAIL $u refusal moved away from view parameter"; exit 1; }
    fi
    echo "RECOVERED REFUSAL $u compile=$got reason=${refusal:-numeric-contract} line=[$(cat "$B/err")]"
  fi
  if [ -n "$self" ]; then
    [ "$self" = 1 ] && cmp -s "$B/unit" "$REAL" || { echo "RECOVERED-OWNERS FAIL $u self compilation differs"; exit 1; }
  fi
  if [ -n "$run" ]; then
    [ "$got" = 0 ] || { echo "RECOVERED-OWNERS FAIL $u refuses but declares runtime"; exit 1; }
    if [ "$run" = want ]; then run=$(cat "${u%.om}.want"); fi
    case $run in ''|*[!0-9]*) echo "RECOVERED-OWNERS FAIL $u invalid runtime status"; exit 1;; esac
    chmod +x "$B/unit"
    if [ -n "$budget" ]; then
      case $budget in *[!0-9]*) echo "RECOVERED-OWNERS FAIL $u invalid address-space budget"; exit 1;; esac
      if timeout 60 prlimit --as="$budget" "$B/unit" < /dev/null > "$B/out"; then status=0; else status=$?; fi
    else
      if timeout 60 "$B/unit" < /dev/null > "$B/out"; then status=0; else status=$?; fi
    fi
    [ "$status" = "$run" ] || { echo "RECOVERED-OWNERS FAIL $u run=$status wanted=$run"; exit 1; }
  fi
  n=$((n+1)); echo "RECOVERED PASS $u compile=$got runtime=${run:-not-requested}"
done < "$B/units"
[ "$n" -gt 0 ]
echo "RECOVERED-OWNERS PASS units=$n"
