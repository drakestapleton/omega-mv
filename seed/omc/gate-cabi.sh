#!/bin/sh
# C ABI units. cc links the fixture; it is not part of the compiler.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${1:-seed/out/omc}
case "$S" in /*) ;; *) S="$R/$S";; esac
test -x "$S"
D=seed/omc/cabi
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM

refuse() { # name file expect
    rc=0
    "$S" < "$D/$2" > "$T/$1.o" 2> "$T/$1.err" || rc=$?
    test "$rc" = "$3" || { echo "FAIL $1 status=$rc want=$3"; cat "$T/$1.err"; exit 1; }
    grep -q "error $3" "$T/$1.err" || { echo "FAIL $1 stderr"; cat "$T/$1.err"; exit 1; }
    echo "PASS cabi $1 error $3"
}

refuse few arity-few.om 4
refuse many arity-many.om 5
refuse float float.om 7
refuse struct struct.om 7
refuse slots slots.om 9
refuse main named-main.om 9

"$S" < "$D/call.om" > "$T/call.o" 2> "$T/call.err" || { cat "$T/call.err"; exit 1; }
readelf -h "$T/call.o" | grep -q 'REL (Relocatable file)'
readelf -h "$T/call.o" | grep -q 'AArch64'
readelf -rW "$T/call.o" | grep -q 'CALL26'
readelf -sW "$T/call.o" | grep -q ' add2$'
readelf -sW "$T/call.o" | grep -q ' om_add$'
readelf -sW "$T/call.o" | grep -q ' UND add2'
cc -o "$T/call" "$D/call.c" "$T/call.o"
"$T/call"
echo "PASS cabi call both directions"

"$S" < "$D/trap.om" > "$T/trap.o" 2> "$T/trap.err" || { cat "$T/trap.err"; exit 1; }
cc -o "$T/trap" "$D/trap.c" "$T/trap.o"
rc=0
"$T/trap" || rc=$?
test "$rc" = 101 || { echo "FAIL cabi trap status=$rc"; exit 1; }
echo "PASS cabi trap exits 101"

echo "CABIGATE PASS"
