#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# run.sh: OMEGA-CRYPTO-REUSE-1 gates 1 and 2 (issue #639), receipt contract version 1, its negative
# controls and its verifier mutants. Usage: sh om/tls/test/reuse/run.sh OMC (from the repository root)
# The driver rows are only recorded here and judged by receipt.om:
# 1. builds the verifier (om2 + om/tls/sha2.om + receipt.om + verify.om) and the controls
#    (om2 + om/tls/sha2.om + receipt.om + controls.om); a build failure is INVALID (3);
# 2. builds om2 + om/tls/chacha.om + om/tls/aesgcm.om + om/tls/gcmsiv.om + driver.om (base) and one
#    unit per driver mutant, runs each under env -i and a 60 s deadline and writes the raw facts (build exit,
#    compiler stderr bytes, program exit, sha256 of the unit, input and stdout files kept in
#    build/tls/reuse/rows/) to build/tls/reuse/receipt.facts. A mutant site that no longer occurs
#    exactly once is not run: its row is missing and the verdict is NOT_RUN, never PASS;
# 3. receipt.om re-hashes every file, classifies every row from its stdout, and prints the classes
#    and verdict, appended to form build/tls/reuse/receipt.txt, which must verify again unchanged;
# 4. on PASS, controls.om must pass all its controls on receipt.txt, and every verifier mutant (one
#    changed line of receipt.om, built with controls.om) must build, exit 1 and fail exactly the
#    controls named for it. This meta-gate is decided here, in shell, by exact comparison of the
#    failed control numbers: a survivor is FAIL, a build failure, other exit or other set INVALID, a
#    missing site NOT_RUN (precedence FAIL > INVALID > NOT_RUN).
# Exit: 0 PASS, 1 FAIL, 2 REFUSED, 3 INVALID (also a verifier that traps or is killed), 4 NOT_RUN.
set -u
OMC=${1:?usage: sh om/tls/test/reuse/run.sh OMC}
D=om/tls/test/reuse
B=build/tls/reuse
R=$B/rows
V=$B/vmut
rm -rf "$R" "$V"
mkdir -p "$R" "$V"
say() { printf '%s\n' "$*"; }
hash() { sha256sum < "$1" | cut -c1-64; }

tool() { # $1 receipt.om (or a mutant of it), $2 main unit, $3 output; 0 when it built clean
  { printf 'om2\n'; cat om/tls/sha2.om "$1" "$2"; } > "$3.unit"
  "$OMC" < "$3.unit" > "$3" 2> "$3.err" && [ ! -s "$3.err" ] && chmod +x "$3"
}
for p in verify controls; do
  tool "$D/receipt.om" "$D/$p.om" "$B/$p" || { say "REUSE INVALID: $p build: $(cat "$B/$p.err")"; exit 3; }
done

unit() { { printf 'om2\n'; cat om/tls/chacha.om om/tls/aesgcm.om om/tls/gcmsiv.om "$1"; } > "$R/$2.unit"; }

rows=
case_() { # $1 name, $2 binary to build, $3 input
  "$OMC" < "$R/$1.unit" > "$2" 2> "$R/$1.err"; brc=$?
  erb=$(wc -c < "$R/$1.err")
  : > "$R/$1.out"
  ex=none
  if [ "$brc" -eq 0 ]; then
    chmod +x "$2"
    env -i timeout 60 "$2" < "$3" > "$R/$1.out"; ex=$?
  fi
  rows="${rows}row $1 $(hash "$R/$1.unit") $(hash "$R/$1.in") $brc $erb $ex $(hash "$R/$1.out")
"
}

unit "$D/driver.om" base
cp "$D/vectors.txt" "$R/base.in"
case_ base "$B/driver" "$R/base.in"

mut() { # $1 name, $2 site (must occur exactly once), $3 replacement
  c=$(grep -cxF "$2" "$D/driver.om")
  if [ "$c" -ne 1 ]; then say "mutant $1 NOT_RUN: site found $c times"; return; fi
  awk -v s="$2" -v r="$3" '$0 == s { print r; next } { print }' "$D/driver.om" > "$R/$1.om"
  unit "$R/$1.om" "$1"
  cp "$D/vectors.txt" "$R/$1.in"
  case_ "$1" "$R/$1" "$R/$1.in"
}

mut tags-in-detector 'dchk kreuse w OC1 OC2 OP1 OP2 RLEN add b 2' 'dchk kreuse w OC1 OC2 OP1 OP2 SLEN add b 2'
mut detector-always-reuse 'ret not ne acc 0' 'ret true'
mut nonce-not-distinct 'put w last xor get w last 1' 'put w last xor get w last 0'
mut tamper-not-applied 'put w add OT 5 xor get w add OT 5 1' 'put w add OT 5 xor get w add OT 5 0'
mut siv-as-other-mode 'r1 = dseal 2 w ON1 nl OC1' 'r1 = dseal 1 w ON1 nl OC1'

# vector mutant: one digit of X wrong, the base unit unchanged
c=$(grep -c '^X 6' "$D/vectors.txt")
if [ "$c" -eq 1 ]; then
  sed 's/^X 6/X 7/' "$D/vectors.txt" > "$R/wrong-expected-xor.in"
  unit "$D/driver.om" wrong-expected-xor
  case_ wrong-expected-xor "$R/wrong-expected-xor" "$R/wrong-expected-xor.in"
else
  say "mutant wrong-expected-xor NOT_RUN: X line found $c times"
fi

src=$(git rev-parse HEAD 2>/dev/null) || src=none
if [ "$src" = none ]; then dirty=none
elif [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty=1
else dirty=0; fi
{
  say "CRYPTO-REUSE-RECEIPT 1"
  say "source $src"
  say "dirty $dirty"
  say "omc $(hash "$OMC") $OMC"
  say "driver $(hash "$B/driver" 2>/dev/null)"
  say "fixture $(hash "$D/vectors.txt")"
  say "checker $(hash "$B/verify.unit")"
  say "runner $(hash "$D/run.sh")"
  say "env empty"
  printf '%s' "$rows"
} > "$B/receipt.facts"

"$B/verify" < "$B/receipt.facts" > "$B/receipt.verdict"; v=$?
case $v in
  0|1|3|4) ;;
  2) say "REUSE REFUSED: $(cat "$B/receipt.verdict")"; exit 2 ;;
  *) say "REUSE INVALID: the verifier exited $v (trap, signal or deadline)"; exit 3 ;;
esac
cat "$B/receipt.facts" "$B/receipt.verdict" > "$B/receipt.txt"
"$B/verify" < "$B/receipt.txt" > "$B/receipt.check"; v2=$?
if [ "$v2" -ne "$v" ] || ! cmp -s "$B/receipt.check" "$B/receipt.verdict"; then
  say "REUSE REFUSED: stored receipt does not verify (exit $v2): $(cat "$B/receipt.check")"
  exit 2
fi
cat "$B/receipt.verdict"
verdict=$(sed -n 's/^verdict //p' "$B/receipt.verdict")
if [ "$v" -ne 0 ]; then
  say "REUSE $verdict receipt=$B/receipt.txt (controls and verifier mutants NOT_RUN: they need a PASS receipt)"
  exit "$v"
fi

timeout 120 "$B/controls" < "$B/receipt.txt" > "$B/controls.out"; c=$?
tail -n 1 "$B/controls.out"
if [ "$c" -ne 0 ]; then
  grep -v ' PASS$' "$B/controls.out"
  [ "$c" -eq 1 ] && { say "REUSE FAIL: a receipt control failed"; exit 1; }
  say "REUSE INVALID: controls exit $c"; exit 3
fi
nctl=$(grep -c '^control [0-9]* PASS$' "$B/controls.out")

# The verifier-mutant meta-gate is decided here, in shell, by exact comparison of the failed
# control numbers with the expected list.
vsurv=0 vinv=0 vnr=0 vok=0 vall=0
vmut() { # $1 name, $2 receipt.om site (exactly once), $3 replacement, $4 the controls it must fail
  vall=$((vall + 1))
  n=$(grep -cxF "$2" "$D/receipt.om")
  if [ "$n" -ne 1 ]; then say "verifier mutant $1 NOT_RUN: site found $n times"; vnr=1; return; fi
  awk -v s="$2" -v r="$3" '$0 == s { print r; next } { print }' "$D/receipt.om" > "$V/$1.om"
  if ! tool "$V/$1.om" "$D/controls.om" "$V/$1"; then
    say "verifier mutant $1 INVALID: build: $(cat "$V/$1.err")"; vinv=1; return
  fi
  timeout 120 "$V/$1" < "$B/receipt.txt" > "$V/$1.out"; e=$?
  got=$(sed -n 's/^control \([0-9]*\) FAIL exit .*/\1/p' "$V/$1.out" | tr '\n' ' ')
  sum=$(grep -c '^controls [0-9]* passed [0-9]* failed$' "$V/$1.out")
  if [ "$e" -eq 0 ]; then say "verifier mutant $1 SURVIVED"; vsurv=1; return; fi
  if [ "$e" -ne 1 ] || [ "$sum" -ne 1 ] || [ "$got" != "$4 " ]; then
    say "verifier mutant $1 INVALID: exit $e, failed controls [$got], want [$4 ]"; vinv=1; return
  fi
  vok=$((vok + 1))
  say "verifier mutant $1 CAUGHT by controls $4"
}
vmut log-hash-skipped 'ok = and ok rc_hrow i eout get qrw add b 6' 'ok = and ok true' '5 6'
vmut any-failure-kills 'if and okk eq fset rc_want i' 'if okk' '18'
vmut exit-not-checked 'okk = and and eq ex 1 gt f 0 eq f m' 'okk = and gt f 0 eq f m' '38'
vmut repeated-check-counted 'if ne and get qgs 17 bit 0' 'if false' '40'
vmut verdict-claim-ignored 'rc_refuse 17' 'ret' '3'
vmut class-claim-ignored 'rc_refuse 16' 'put qgs 2 0' '4'
vmut fixture-not-rehashed 'if not rc_hxeq sub get qgs 8 1' 'if false' '7'
vmut pin-not-checked 'ret 8' 'ret 0' '8'
vmut stale-base-source 'if not rc_hxeqs 0 get qrw 1' 'if false' '11'
vmut missing-row-passes 'c = ulong 5' 'c = ulong 0' '13'
vmut zero-checks-pass 'okshape = and okshape eq get qgs 14 27' 'okshape = okshape' '17'
vmut noop-mutant-kills 'c = 4' 'c = add c 0' '21 22'

# the evidence must be intact after the controls: the stored receipt verifies to the same result
"$B/verify" < "$B/receipt.txt" > "$B/receipt.check"; v2=$?
if [ "$v2" -ne 0 ] || ! cmp -s "$B/receipt.check" "$B/receipt.verdict"; then
  say "REUSE REFUSED: evidence changed during the controls"; exit 2
fi
if [ "$vsurv" -ne 0 ]; then say "REUSE FAIL: a verifier mutant survived"; exit 1; fi
if [ "$vinv" -ne 0 ]; then say "REUSE INVALID: a verifier mutant was not validly caught"; exit 3; fi
if [ "$vnr" -ne 0 ]; then say "REUSE NOT_RUN: a verifier mutant site is missing"; exit 4; fi
say "REUSE PASS receipt=$B/receipt.txt sha256=$(hash "$B/receipt.txt") controls=$nctl verifier-mutants=$vok/$vall"
