#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# agg.sh: CRYPTO-REUSE-AGGREGATE 1 (issue #639: gate 3 adapters and checker2 rows) and the self-test
# of its runner. Usage, from the repository root: sh om/tls/test/reuse/agg.sh OMC [PLAN...]
# Every classification and the verdict are decided by aggregate.om (contract in its header); this
# script only builds, runs, tampers copies and compares results:
# 1. builds the runner (om2 + om/tls/sha2.om + aggregate.om) and fixture.om; a build failure is
#    INVALID (3);
# 2. self-test: selftest.plan must give every row its wanted class (runner verdict PASS), `aggregate
#    check` must accept that receipt and refuse (exit 2) each tampered copy: t-log (a log byte),
#    t-class and t-verdict (one word of the receipt), t-row (a row line deleted), t-nolog (a log
#    removed), t-fixture (a bound fixture changed), t-plan (the plan changed), t-status (a status);
#    and five malformed plans must stop both `run` and `check` with exit 3 at their exact line,
#    before their command runs: r-args (58 args), r-name (a 201-byte name), r-mutexit0 (a mutant
#    expecting exit 0), r-bytes (an argument packet over 4096 bytes), r-dup (a repeated row name);
# 3. runner mutants: each one-line change of aggregate.om must build and change exactly the named
#    self-test rows (class and reason), tamper and refusal controls; a survivor is FAIL, a build
#    failure or another set INVALID, a site that does not occur exactly once NOT_RUN;
# 4. with PLANs: joins them in order into build/tls/reuse/aggregate.plan (row names are unique across
#    them), runs it from a fresh build/tls/reuse/agg/ into build/tls/reuse/aggregate.txt, and
#    `aggregate check` (which recomputes the receipt from the plan and files and compares it byte for
#    byte) must accept it. Hold the host's CPU pool lock for the whole run; rows take no lock.
# Exit: 0 PASS, 1 FAIL, 2 REFUSED, 3 INVALID, 4 NOT_RUN (with PLAN: the plan's verdict).
set -u
OMC=${1:?usage: sh om/tls/test/reuse/agg.sh OMC [PLAN...]}
shift
D=om/tls/test/reuse
B=build/tls/reuse
S=$B/aggself
say() { printf '%s\n' "$*"; }
# every row gets exactly this environment (aggregate.om passes its own to each command)
agg() { env -i HOME="$HOME" PATH="$PATH" LC_ALL=C "$@"; }
hash() { sha256sum < "$1" | cut -c1-64; }
rm -rf "$S"
mkdir -p "$S"

build() { # $1 aggregate source, $2 binary; 0 when it built with no compiler output
  { printf 'om2\n'; cat om/tls/sha2.om "$1"; } > "$2.unit"
  "$OMC" < "$2.unit" > "$2" 2> "$2.err" && [ ! -s "$2.err" ] && chmod +x "$2"
}
build "$D/aggregate.om" "$B/aggregate" || { say "AGG INVALID: runner build: $(cat "$B/aggregate.err")"; exit 3; }
"$OMC" < "$D/fixture.om" > "$B/fixture" 2> "$S/fixture.err" && [ ! -s "$S/fixture.err" ] && chmod +x "$B/fixture" \
  || { say "AGG INVALID: fixture build: $(cat "$S/fixture.err")"; exit 3; }

fresh() { rm -rf "$B/agg" "$B/selftest.out"; mkdir -p "$B/agg"; }

refused() { # $1 runner, $2 plan, $3 receipt: 0 when check refuses
  "$1" check "$2" "$3" > "$S/t.out" 2>&1
  [ $? -eq 2 ] && grep -q '^REFUSED ' "$S/t.out"
}

# malformed NAME LINE RUNNER: `run` and `check` (receipt /dev/null) of $S/NAME.plan must both stop
# with exit 3 and "aggregate: malformed plan, line LINE", so before the refused row's command runs;
# prints NAME when either did not
malformed() {
  agg "$3" run "$S/$1.plan" > "$S/m.out" 2>&1; a=$?
  agg "$3" check "$S/$1.plan" /dev/null > "$S/c.out" 2>&1; c=$?
  [ "$a" -eq 3 ] && [ "$c" -eq 3 ] && grep -qx "aggregate: malformed plan, line $2" "$S/m.out" \
    && grep -qx "aggregate: malformed plan, line $2" "$S/c.out" || printf '%s\n' "$1"
}
rep() { i=0; while [ "$i" -lt "$1" ]; do printf '%s\n' "$2"; i=$((i + 1)); done; }
{ printf 'row r-args control\nexit 0\narg true\n'; rep 57 'arg x'; printf 'end\n'; } > "$S/r-args.plan"
{ printf 'row r-name-%s control\nexit 0\narg true\nend\n' "$(rep 194 a | tr -d '\n')"; } > "$S/r-name.plan"
printf 'row r-mutexit0 mutant\nexit 0\narg true\nneed x\npass y\nend\n' > "$S/r-mutexit0.plan"
{ printf 'row r-bytes control\nexit 0\narg echo\narg '; rep 4100 a | tr -d '\n'; printf '\nend\n'; } > "$S/r-bytes.plan"
printf 'row r-dup control\nexit 0\narg true\nend\nrow r-dup control\nexit 0\narg true\nend\n' > "$S/r-dup.plan"

# tamper NAME RUNNER PLAN COPY: COPY must differ from the receipt and be refused; prints NAME when it
# was accepted and NAME-noop when the tamper changed nothing (a harness error, never a pass)
tamper() {
  if cmp -s "$4" "$r"; then printf '%s-noop\n' "$1"; return; fi
  refused "$2" "$3" "$4" || printf '%s\n' "$1"
}
# word K of the first line starting with PREFIX: A becomes B, anything else becomes A
flip() { awk -v p="$1" -v k="$2" -v a="$3" -v b="$4" \
  'index($0, p) == 1 && !d { $k = ($k == a) ? b : a; d = 1 } { print }' "$r"; }

# selftest RUNNER RECEIPT: runs the self-test plan; prints the names of the tamper controls that
# were not refused; returns the runner's exit
selftest() {
  fresh
  agg "$1" run "$D/selftest.plan" > "$2"; rc=$?
  r=$2
  refused "$1" "$D/selftest.plan" "$r" && printf 'untampered-refused\n'
  l=$B/agg/ctl-fail.log
  cp "$l" "$S/keep"; sed 's/a::b/c::b/' "$S/keep" > "$l"
  cmp -s "$l" "$S/keep" && printf 't-log-noop\n'
  refused "$1" "$D/selftest.plan" "$r" || printf 't-log\n'
  cp "$S/keep" "$l"
  flip 'row ctl-fail ' 13 PASS FAIL > "$S/t.rcpt"; tamper t-class "$1" "$D/selftest.plan" "$S/t.rcpt"
  flip 'verdict ' 2 PASS FAIL > "$S/t.rcpt"; tamper t-verdict "$1" "$D/selftest.plan" "$S/t.rcpt"
  grep -v '^row mut-killed ' "$r" > "$S/t.rcpt"; tamper t-row "$1" "$D/selftest.plan" "$S/t.rcpt"
  mv "$B/agg/ctl-pass.log" "$S/keep"
  refused "$1" "$D/selftest.plan" "$r" || printf 't-nolog\n'
  mv "$S/keep" "$B/agg/ctl-pass.log"
  cp "$B/fixture" "$S/keep"; printf 'x' >> "$B/fixture"
  refused "$1" "$D/selftest.plan" "$r" || printf 't-fixture\n'
  cp "$S/keep" "$B/fixture"
  { cat "$D/selftest.plan"; printf '# changed\n'; } > "$S/t.plan"
  refused "$1" "$S/t.plan" "$r" || printf 't-plan\n'
  flip 'row mut-killed ' 5 101 0 > "$S/t.rcpt"; tamper t-status "$1" "$D/selftest.plan" "$S/t.rcpt"
  # refusal lines: the 58th arg; the row line; and the `end` line for r-mutexit0, r-bytes and the
  # repeated r-dup row (the first r-dup row runs in run mode; the repeat never does)
  malformed r-args 60 "$1"; malformed r-name 1 "$1"; malformed r-mutexit0 6 "$1"
  malformed r-bytes 5 "$1"; malformed r-dup 8 "$1"
  return $rc
}

classes() { sed -n 's/^row \([^ ]*\) .* class \([A-Z_]*\) reason \([a-z-]*\)$/\1 \2 \3/p' "$1"; }

selftest "$B/aggregate" "$S/base.rcpt" > "$S/base.tamper"; rc=$?
tail -n 1 "$S/base.rcpt"
if [ "$rc" -ne 0 ]; then say "AGG FAIL: self-test verdict exit $rc (a row did not get its wanted class)"; exit 1; fi
if [ -s "$S/base.tamper" ]; then say "AGG FAIL: tamper controls not refused: $(tr '\n' ' ' < "$S/base.tamper")"; exit 1; fi
"$B/aggregate" check "$D/selftest.plan" "$S/base.rcpt" > "$S/base.check"; c=$?
if [ "$c" -ne 0 ]; then say "AGG FAIL: check of the self-test receipt exit $c: $(cat "$S/base.check")"; exit 1; fi
classes "$S/base.rcpt" > "$S/base.cls"
nrows=$(wc -l < "$S/base.cls")

vsurv=0 vinv=0 vnr=0 vok=0 vall=0
vmut() { # $1 name, $2 aggregate.om site (exactly once), $3 replacement, $4 rows and controls it must change
  vall=$((vall + 1))
  n=$(grep -cxF -- "$2" "$D/aggregate.om")
  if [ "$n" -ne 1 ]; then say "vmut $1 NOT_RUN site occurs $n times"; vnr=$((vnr + 1)); return; fi
  awk -v s="$2" -v r="$3" '$0 == s { print r; next } { print }' "$D/aggregate.om" > "$S/m-$1.om"
  if ! build "$S/m-$1.om" "$S/m-$1"; then
    say "vmut $1 INVALID build: $(cat "$S/m-$1.err")"; vinv=$((vinv + 1)); return
  fi
  selftest "$S/m-$1" "$S/m-$1.rcpt" > "$S/m-$1.tamper"
  classes "$S/m-$1.rcpt" > "$S/m-$1.cls"
  got=$( { awk 'NR == FNR { c[$1] = $2 " " $3; next } c[$1] != $2 " " $3 { print $1 }' \
      "$S/base.cls" "$S/m-$1.cls"; cat "$S/m-$1.tamper"; } | tr '\n' ' ' | sed 's/ $//')
  if [ "$(wc -l < "$S/m-$1.cls")" -ne "$nrows" ]; then got="$got rows-missing"; fi
  if [ -z "$got" ]; then say "vmut $1 SURVIVED"; vsurv=$((vsurv + 1))
  elif [ "$got" = "$4" ]; then say "vmut $1 CAUGHT by $got"; vok=$((vok + 1))
  else say "vmut $1 INVALID changed [$got] expected [$4]"; vinv=$((vinv + 1)); fi
}
vmut control-need-skipped 'if not allneed' 'if false' 'ctl-zero-tests ctl-midline ctl-no-digits'
vmut mutant-need-skipped 'if and eq s get rf 12 allneed' 'if eq s get rf 12' 'mut-unrelated mut-build-error'
vmut zero-tests-survive 'if and eq s 0 allpass' 'if eq s 0' 'mut-zero mut-ignored'
vmut exec-failure-ignored 'if ge s 124' 'if false' 'ctl-missing-exe ctl-deadline mut-missing-exe'
vmut signal-ignored 'if ne get xs 1 0' 'if false' 'ctl-signal'
vmut fixture-not-required 'if ne fx 0' 'if false' 'ctl-fixture-missing'
vmut empty-not-checked 'if and ne get rf 14 0 ne get lbn 0 0' 'if false' 'ctl-empty-bad'
vmut after-ignored 'if ne w 1' 'if false' 'ctl-after-fail'
vmut empty-digit-run 'if not dg0' 'if false' 'ctl-no-digits'
vmut big-log-accepted 'if ne get lbig 0 0' 'if false' 'ctl-big-log'
vmut survivor-killed 'ret add ulong 32 3' 'ret add ulong 16 2' 'mut-survived'
vmut receipt-bytes-unchecked 'if ne get ob i get rb i' 'if false' 't-log t-class t-verdict t-fixture t-plan'
vmut env-not-passed 'if eq get evn 0 0' 'if true' 'ctl-env'
vmut args-unbounded 'if ge j 57' 'if false' 'r-args'
vmut name-unbounded 'if gt sub q v 200' 'if false' 'r-name'
vmut mutant-exit0-accepted 'if and eq get rf 2 1 eq get rf 12 0' 'if false' 'r-mutexit0'
vmut packet-unchecked-in-plan 'if gt pksize len av' 'if false' 'r-bytes'
if [ "$vsurv" -ne 0 ]; then say "AGG FAIL: a runner mutant survived"; exit 1; fi
if [ "$vinv" -ne 0 ]; then say "AGG INVALID: a runner mutant was not validly caught"; exit 3; fi
if [ "$vnr" -ne 0 ]; then say "AGG NOT_RUN: a runner mutant site is missing"; exit 4; fi
say "AGG SELFTEST PASS rows=$nrows tamper=8 refusals=5 runner-mutants=$vok/$vall receipt sha256=$(hash "$S/base.rcpt")"
[ "$#" -gt 0 ] || exit 0

P=$B/aggregate.plan
cat "$@" > "$P" || { say "AGG NOT_RUN: a plan file is missing"; exit 4; }
for f in "$@"; do say "plan $f sha256=$(hash "$f")"; done
fresh
agg "$B/aggregate" run "$P" > "$B/aggregate.txt"; v=$?
"$B/aggregate" check "$P" "$B/aggregate.txt" > "$S/plan.check"; v2=$?
if [ "$v2" -ne "$v" ] || ! grep -q '^CHECK OK verdict ' "$S/plan.check"; then
  say "AGG REFUSED: the receipt does not verify (run $v, check $v2): $(cat "$S/plan.check")"; exit 2
fi
grep -v ' class PASS reason ' "$B/aggregate.txt" | grep '^row ' || true
tail -n 1 "$B/aggregate.txt"
head=$(cat "$B/agg/prov-head.log" 2>/dev/null) || head=-
say "AGG $(sed -n 's/^verdict \([A-Z_]*\) .*/\1/p' "$B/aggregate.txt") source=$head receipt=$B/aggregate.txt sha256=$(hash "$B/aggregate.txt")"
exit "$v"
