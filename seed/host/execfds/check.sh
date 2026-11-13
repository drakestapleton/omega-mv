#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/host/execfds/check.sh [OMC]: TEST INSTRUMENT (shell) for execfds (keyword 201); never a product path.
# Run from anywhere; it works in the repository root. OMC defaults to seed/out/omc.
# 1. execfds.cases through the OM-2 conductor: the fixture's 29 checks, refusals (25, 9, 30), ten
#    check-removal mutants (five keep-list, five prepass; each killed at its named check) and five ENOSYS faults (fail closed, exit 38).
# 2. ORACLE parity: seed/host/execfds/oracle.py (Python ctypes ORACLE) decodes the packets the fixture built
#    ("packets S"), prepares the same descriptors with its own calls and launches the same compiled program;
#    for scenarios 1..6 exit status and stdout must be byte-identical with the fixture's own "launch S".
#    Expected exits: 1, 2, 3 (the report image), 4 (ENOENT, in-process report) and 5 (EBADF, in-process
#    report) 0; 6 (unsorted keep list) 103.
# 3. ORACLE order: strace, an independent observer, traces one execfds ("order"): exactly one
#    unshare(CLONE_FILES) before every fcntl, two F_GETFD then one F_SETFD clearing every flag of the kept 7,
#    close_range(3, 6) and close_range(8, ~0) after it, execve last. The no-unshare mutant (unshare(0))
#    must FAIL this check: the private table is visible only here.
# 4. ORACLE memory: strace of three runs. A 4 MiB argv packet with one trailing byte (malbig) and a 9-byte
#    environment packet whose count field claims 65535 records (lying) must trap 3 (exit 103) with no mmap,
#    mremap or brk at all: framing is checked against the bytes actually supplied before any decode memory,
#    and a count field never sizes memory. The valid 4 MiB packet (bigok) must show its decode mapping (the
#    control that the observer sees one) and map at most 5(n+m)+65+k bytes plus a page per mapping. Under the
#    no-prepass omc.om mutant, malbig must be seen mapping before its trap (the withdrawn decoder's order).
# 5. Controls: the oracle's framing validator (selftest); a changed native output must be detected.
# 6. snapshot.py: ptrace rewrites caller K=[7] to [9] at unshare return. The launch must still keep 7/close 9.
#    caller-reread compiler mutant must keep 9/close 7 and fail semantically. Launch failure is not a kill;
#    denied ptrace is NOT_RUN, never PASS (both branches have controls).
# Exit 0 PASS, 1 FAIL, 3 NOT_RUN (strace or ptrace unavailable).
set -u
R=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd) || exit 1
cd "$R" || exit 1
OMC=${1:-seed/out/omc}
OMC=$(cd "$(dirname -- "$OMC")" && pwd)/$(basename -- "$OMC")
C=seed/host/execfds
B=build/seed/execfds
mkdir -p "$B" || exit 1
run=$(mktemp -d "$B/run.XXXXXX") || exit 1
run=$(cd "$run" && pwd)
fail() { echo "EXECFDS FAIL: $*"; exit 1; }
[ -x "$OMC" ] || fail "no compiler $OMC"
pin=$(sha256sum "$OMC" | cut -d' ' -f1)
echo "omc $OMC sha256 $pin scratch $run"
"$OMC" < seed/qualification/om2/gate.om > "$B/gate" 2> "$run/gate-build.err" || fail "gate build: $(cat "$run/gate-build.err")"
chmod +x "$B/gate" || fail "chmod gate"
"$B/gate" "$OMC" "$pin" "$C/execfds.cases" "$run/cases" > "$run/cases.log" 2>&1
st=$?
[ "$st" = 0 ] && grep -Eqx 'OM2GATE PASS cases=([0-9]+) pass=\1 fail=0 invalid=0 not_run=0' "$run/cases.log" || { cat "$run/cases.log"; fail "execfds.cases exit $st"; }
echo "PASS execfds.cases: $(grep '^OM2GATE' "$run/cases.log")"
"$OMC" < "$C/execfds.om" > "$run/execfds" 2> "$run/build.err" || fail "fixture build: $(cat "$run/build.err")"
chmod +x "$run/execfds" || fail "chmod fixture"
python3 "$C/oracle.py" selftest > "$run/selftest.log" 2>&1 || { cat "$run/selftest.log"; fail "oracle selftest"; }
echo "PASS $(tail -1 "$run/selftest.log")"
for s in 1 2 3 4 5 6; do
  want=0; [ $s = 6 ] && want=103
  (cd "$run" && "$run/execfds" launch $s > "$run/native-$s.out" 2> "$run/native-$s.err"); n=$?
  (cd "$run" && python3 "$R/$C/oracle.py" execfds $s "$run/execfds" > "$run/oracle-$s.out" 2> "$run/oracle-$s.err"); o=$?
  [ $n = $want ] || fail "scenario $s: native exit $n, expected $want ($(head -c 300 "$run/native-$s.err"))"
  [ $o = $want ] || fail "scenario $s: oracle exit $o, expected $want ($(head -c 300 "$run/oracle-$s.err"))"
  [ ! -s "$run/native-$s.err" ] && [ ! -s "$run/oracle-$s.err" ] || fail "scenario $s: stderr not empty"
  cmp -s "$run/native-$s.out" "$run/oracle-$s.out" || { diff "$run/native-$s.out" "$run/oracle-$s.out" | head -20; fail "scenario $s: native and oracle stdout differ"; }
  echo "PASS parity scenario $s: exit $n, stdout $(wc -c < "$run/native-$s.out") bytes sha256 $(sha256sum < "$run/native-$s.out" | cut -c1-16)"
done
sed '1s/^/x/' "$run/native-1.out" > "$run/control-1.out" || fail "control copy"
if cmp -s "$run/control-1.out" "$run/oracle-1.out"; then fail "control: a changed native output compared equal"; fi
echo "PASS control: a changed native output is detected"
grep -qx 'fd 7 open' "$run/native-1.out" && grep -qx 'fd 9 closed' "$run/native-1.out" && grep -qx 'env 1 DUP=1' "$run/native-1.out" || fail "scenario 1 report lacks fd 7 open / fd 9 closed / duplicate entry"
grep -qx 'argc 1100' "$run/native-3.out" && grep -qx 'envc 73' "$run/native-3.out" && grep -qx 'fd 2099 open' "$run/native-3.out" && grep -qx 'fd 2100 closed' "$run/native-3.out" || fail "scenario 3 report lacks argc 1100 / envc 73 / fd 2099 open / fd 2100 closed"
grep -qx 'result -2' "$run/native-4.out" && grep -qx 'result -9' "$run/native-5.out" || fail "scenarios 4/5 results"
echo "PASS scenario content: kept 7, closed 9, duplicate entry, 1100 args, 73 entries, 1100 kept fds, -2, -9"
if ! command -v strace > /dev/null 2>&1; then
  echo "NOT_RUN strace order: strace is not installed"
  exit 3
fi
(cd "$run" && strace -f -qq -e trace=unshare,fcntl,close_range,execve -o "$run/order.trace" "$run/execfds" order > "$run/order.out" 2>&1); s=$?
[ $s = 0 ] || { cat "$run/order.out"; fail "order run exit $s"; }
python3 "$C/oracle.py" order "$run/order.trace" "$run/execfds" > "$run/order.log" 2>&1 || { cat "$run/order.log"; fail "strace order"; }
echo "PASS $(tail -1 "$run/order.log")"
python3 "$C/oracle.py" subst "$C/mutants/no-unshare.from" "$C/mutants/no-unshare.to" seed/omc/omc.om "$run/omc-no-unshare.om" || fail "no-unshare mutant source"
"$OMC" < "$run/omc-no-unshare.om" > "$run/omc-no-unshare" 2> "$run/omc-no-unshare.err" || fail "no-unshare compiler build: $(head -c 300 "$run/omc-no-unshare.err")"
chmod +x "$run/omc-no-unshare" || fail "chmod mutant compiler"
"$run/omc-no-unshare" < "$C/execfds.om" > "$run/execfds-no-unshare" 2> "$run/execfds-no-unshare.err" || fail "fixture under no-unshare: $(cat "$run/execfds-no-unshare.err")"
chmod +x "$run/execfds-no-unshare" || fail "chmod mutant fixture"
(cd "$run" && strace -f -qq -e trace=unshare,fcntl,close_range,execve -o "$run/order-mut.trace" "$run/execfds-no-unshare" order > "$run/order-mut.out" 2>&1); s=$?
[ $s = 0 ] || fail "order run under no-unshare exit $s"
python3 "$C/oracle.py" order "$run/order-mut.trace" "$run/execfds-no-unshare" > "$run/order-mut.log" 2>&1; m=$?
[ $m = 1 ] || { cat "$run/order-mut.log"; fail "no-unshare mutant: order check exit $m (1 = killed expected)"; }
grep -q 'ORDER PROBLEM exactly one unshare(CLONE_FILES)' "$run/order-mut.log" || fail "no-unshare mutant killed for another reason"
echo "PASS mutant no-unshare killed by the strace order check"
for k in malbig lying; do
  (cd "$run" && strace -f -qq -e trace=execve,mmap,munmap,mremap,brk -o "$run/mem-$k.trace" "$run/execfds" $k > "$run/mem-$k.out" 2>&1); s=$?
  [ $s = 103 ] || { cat "$run/mem-$k.out"; fail "$k exit $s, expected 103 (trap 3)"; }
  python3 "$C/oracle.py" memtrace $k "$run/mem-$k.trace" "$run/execfds" > "$run/mem-$k.log" 2>&1 || { cat "$run/mem-$k.log"; fail "memory $k"; }
  echo "PASS $(tail -1 "$run/mem-$k.log")"
done
# Mapping-order mutant: without the framing prepass (execfds/mutants/no-prepass) the 4 MiB malformed argv packet
# is mapped before the copying pass traps, the one mapping the withdrawn decoder made; the memory check must see it.
python3 seed/host/container/subst.py "$C/mutants/no-prepass.from" "$C/mutants/no-prepass.to" seed/omc/omc.om "$run/omc-no-prepass.om" > /dev/null || fail "no-prepass mutant source"
"$OMC" < "$run/omc-no-prepass.om" > "$run/omc-no-prepass" 2> "$run/omc-no-prepass.err" || fail "no-prepass compiler build: $(head -c 300 "$run/omc-no-prepass.err")"
chmod +x "$run/omc-no-prepass" || fail "chmod no-prepass compiler"
"$run/omc-no-prepass" < "$C/execfds.om" > "$run/execfds-no-prepass" 2> "$run/execfds-no-prepass.err" || fail "fixture under no-prepass: $(cat "$run/execfds-no-prepass.err")"
chmod +x "$run/execfds-no-prepass" || fail "chmod no-prepass fixture"
(cd "$run" && strace -f -qq -e trace=execve,mmap,munmap,mremap,brk -o "$run/mem-mut-malbig.trace" "$run/execfds-no-prepass" malbig > "$run/mem-mut-malbig.out" 2>&1); s=$?
[ $s = 103 ] || { cat "$run/mem-mut-malbig.out"; fail "no-prepass malbig exit $s, expected 103 (the copying pass still traps)"; }
python3 "$C/oracle.py" memtrace malbig "$run/mem-mut-malbig.trace" "$run/execfds-no-prepass" > "$run/mem-mut-malbig.log" 2>&1; m=$?
[ $m = 1 ] && grep -q '^MEMORY malbig FAIL calls=[1-9]' "$run/mem-mut-malbig.log" || { cat "$run/mem-mut-malbig.log"; fail "no-prepass mutant: memory check exit $m, a mapping before the trap expected"; }
echo "PASS mutant no-prepass killed by the memory check: $(tail -1 "$run/mem-mut-malbig.log")"
(cd "$run" && strace -f -qq -e trace=execve,mmap,munmap,mremap,brk -o "$run/mem-bigok.trace" "$run/execfds" bigok > "$run/mem-bigok.out" 2>&1); s=$?
[ $s = 0 ] || { cat "$run/mem-bigok.out"; fail "bigok exit $s, expected 0 (execfds returned -2)"; }
nm=$(sed -n 's/^bytes \([0-9][0-9]*\) \([0-9][0-9]*\) \([0-9][0-9]*\)$/\1 \2 \3/p' "$run/mem-bigok.out")
[ -n "$nm" ] || fail "bigok printed no packet sizes"
python3 "$C/oracle.py" memtrace bigok "$run/mem-bigok.trace" "$run/execfds" $nm > "$run/mem-bigok.log" 2>&1 || { cat "$run/mem-bigok.log"; fail "memory bigok"; }
echo "PASS $(grep '^MEMORY bigok argv' "$run/mem-bigok.log"); $(tail -1 "$run/mem-bigok.log")"
# Deterministic caller-memory TOCTOU control. No ptrace means NOT_RUN, never a vacuous PASS.
(cd "$run" && python3 "$R/$C/snapshot.py" "$run/execfds") > "$run/snapshot.log" 2>&1; s=$?
if [ "$s" = 3 ]; then cat "$run/snapshot.log"; exit 3; fi
[ "$s" = 0 ] && grep -qx 'SNAPSHOT PASS caller mutation did not change kept=\[7\] closed=\[9\]' "$run/snapshot.log" || { cat "$run/snapshot.log"; fail "snapshot exit $s"; }
echo "PASS ptrace snapshot: caller [7]->[9] at unshare return, kept 7, closed 9"
python3 "$C/oracle.py" subst "$C/mutants/caller-reread.from" "$C/mutants/caller-reread.to" seed/omc/omc.om "$run/omc-caller-reread.om" || fail "caller-reread source"
"$OMC" < "$run/omc-caller-reread.om" > "$run/omc-caller-reread" 2> "$run/omc-caller-reread.err" || fail "caller-reread compiler build"
chmod +x "$run/omc-caller-reread" || fail "chmod caller-reread compiler"
"$run/omc-caller-reread" < "$C/execfds.om" > "$run/execfds-caller-reread" 2> "$run/execfds-caller-reread.err" || fail "caller-reread fixture build"
chmod +x "$run/execfds-caller-reread" || fail "chmod caller-reread fixture"
(cd "$run" && python3 "$R/$C/snapshot.py" "$run/execfds-caller-reread") > "$run/snapshot-mutant.log" 2>&1; m=$?
if [ "$m" = 3 ]; then cat "$run/snapshot-mutant.log"; exit 3; fi
[ "$m" = 1 ] && grep -qx 'SNAPSHOT MISMATCH caller mutation changed kept/closed descriptors' "$run/snapshot-mutant.log" || { cat "$run/snapshot-mutant.log"; fail "caller-reread mutant exit $m (expected semantic mismatch 1)"; }
grep -qx 'SNAPSHOT observed kept=\[9\] closed=\[7\] before execve' "$run/snapshot-mutant.log" || fail "mutant not killed by wrong descriptor survival"
echo "PASS mutant caller-reread killed by ptrace: kept 9, closed 7"
# A launch failure must be instrument failure, not a semantic mutant kill.
python3 "$C/snapshot.py" "$run/nonexistent-fixture" > "$run/snapshot-launch-control.log" 2>&1; s=$?
[ "$s" = 2 ] && grep -q '^SNAPSHOT INSTRUMENT FAIL:' "$run/snapshot-launch-control.log" || fail "snapshot launch-failure control exit $s"
echo "PASS snapshot launch-failure control: 2, not mutant-killed 1"
# A tracee cannot TRACEME again: force real ptrace denial, require NOT_RUN rather than PASS or mutant kill.
(cd "$run" && strace -f -qq -e trace=ptrace -o "$run/snapshot-denied.trace" python3 "$R/$C/snapshot.py" "$run/execfds") > "$run/snapshot-denied.log" 2>&1; s=$?
[ "$s" = 3 ] && grep -q '^SNAPSHOT NOT_RUN ' "$run/snapshot-denied.log" || { cat "$run/snapshot-denied.log"; fail "snapshot ptrace-denied control exit $s"; }
echo "PASS snapshot ptrace-denied control: NOT_RUN 3, not PASS"
echo "EXECFDS PASS scratch $run"
