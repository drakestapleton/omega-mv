#!/bin/sh
# Synthetic routing tests. The real symbolic engines and compiler execute every checked case.
set -eu
umask 077
[ "$#" = 1 ] || { echo 'usage: test.sh BUILT_KIT' >&2; exit 2; }
installed=$(CDPATH= cd -- "$1" && pwd)
d=$(mktemp -d)
trap 'rm -rf -- "$d"' EXIT
trap 'exit 1' HUP INT TERM
cd "$d"
mkdir kit
for name in solve combined omc om_formalize om_sketch om_synth; do
    ln -s "$installed/$name" "kit/$name"
done
touch kit/r6.ck kit/r3.ck kit/base.ck kit/trace.ck kit/merges.bin kit/S2_fold.sp
cat > kit/ollm <<'MOCK'
#!/bin/sh
set -eu
REPLAY=$(dirname -- "$0")/../replay
test -f "$2"
name=$(basename "$2")
case "$1" in
sample)
    test "$#" = 7 && test "$3/$4/$5" = "42/128/0" && test -s "$REPLAY/$name" && test -f "$7" || exit 2
    cat "$REPLAY/$name";;
spsamp)
    test "$#" = 8 && test "$4/$5" = "64/700" && test "$name" = r3.ck && test -f "$3" && test -f "$8" || exit 2
    cat "$REPLAY/strand-$7";;
*) exit 2;;
esac
MOCK
chmod 700 kit/ollm
mkdir replay
for ck in r6.ck r3.ck base.ck trace.ck; do printf 'ret 0\nend\n' > "replay/$ck"; done
for s in 1100 1101 1102 1103; do cp replay/r6.ck "replay/strand-$s"; done
prompt() { printf 'note %s\nfn solve %s\n' "$1" "$2" > prompt; }
answer() { kit/solve "$@" > got 2> route; }
route_is() { grep -Fx "route $1" route >/dev/null; }
refuse() {
    rc=0
    kit/solve "$@" > got 2> route || rc=$?
    [ "$rc" = "$want" ] && [ ! -s got ] || { echo "expected $want, got $rc" >&2; exit 1; }
}
prompt 'return the argument rounded down to a multiple of 14' 'a ulong to ulong'
answer prompt
route_is om_synth
printf '41 28\n70 70\n0 0\n13 0\n' > examples
answer prompt examples
route_is om_synth
prompt 'demo operation' 'a ulong b ulong to ulong'
printf '2 3 5\n7 11 18\n5 0 5\n21 3 24\n' > examples
answer prompt examples
grep -Eq '^route om_(sketch|synth)$' route
prompt 'demo operation' 'a view ulong 8 n ulong to ulong'
printf '4 1 3 9 4 0 0 0 0 17\n2 1 1 7 2 0 0 0 0 2\n' > examples
answer prompt examples
route_is om_sketch
# Historical r-030, including tails after the active length.
prompt 'return the sum of the items at even indexes minus the sum of the items at odd indexes among the first n items, or zero when the odd sum is larger' 'a view ulong 8 n ulong to ulong'
cat > examples <<'ROWS'
0 7 0 3 11 3 2 9 13 0
2 7 0 3 11 3 2 9 13 7
5 7 0 3 11 3 2 9 13 2
8 7 0 3 11 3 2 9 13 0
0 9 2 3 2 1 12 0 9 0
2 9 2 3 2 1 12 0 9 7
5 9 2 3 2 1 12 0 9 9
8 9 2 3 2 1 12 0 9 0
ROWS
answer prompt examples
route_is om_sketch
prompt 'demo operation' 'a edit ulong 8 n ulong to void'
printf '2 1 3 0 0 0 0 0 0 3 1 0 0 0 0 0 0\n3 7 5 9 0 0 0 0 0 9 5 7 0 0 0 0 0\n' > examples
answer prompt examples
route_is om_sketch
prompt 'demo operation' 'a ulong to ulong'
answer prompt
route_is r6.ck
cmp got replay/r6.ck
# Nine cases force checking beyond the eight lanes used to propose a symbolic program.
n=1
: > examples
while [ "$n" -le 9 ]; do
    expected=$((n * 937 + 417))
    printf '%s %s\n' "$n" "$expected" >> examples
    n=$((n + 1))
done
printf 'if eq a 9\nret 0\nend\nret add mul a 937 417\nend\n' > replay/r6.ck
printf 'ret add mul a 937 417\nend\n' > good
cp good replay/trace.ck
answer prompt examples
route_is trace.ck
cmp good got
cp replay/base.ck replay/trace.ck
cp good replay/strand-1102
answer prompt examples
route_is S2_fold.sp
cmp good got
cp replay/base.ck replay/strand-1102
want=1
refuse prompt examples
# Every candidate below would satisfy all nine rows if its invalid line were ignored.
for local in se so runningTotal local_with_underscores; do
    printf '%s = mul a 937\nret add %s 417\nend\n' "$local" "$local" > replay/r3.ck
    answer prompt examples
    route_is r3.ck
    cmp got replay/r3.ck
done
printf 'subtotal = ulong 0\nfor position ulong a bound 9\nsubtotal = add subtotal 937\nend\nret add subtotal 417\nend\n' > replay/r3.ck
answer prompt examples
route_is r3.ck
cmp got replay/r3.ck
for body in 'ret add mul missing 937 417' 'ret add mul z 937 417' 'for add ulong 0' 'for note ulong 0' 'for getpid ulong 0'; do
    { printf '%s\n' "$body"; case "$body" in 'for '*) printf 'end\n';; esac; cat good; } > replay/r3.ck
    refuse prompt examples
done
{ printf 'unused = getpid\n'; cat good; } > replay/r3.ck
refuse prompt examples
{ cat good; printf 'fn extra to int\nret 0\nend\n'; } > replay/r3.ck
refuse prompt examples
printf '18446744073709551616 2\n' > invalid
want=65
refuse prompt invalid
: > invalid
refuse prompt invalid
printf 'note demo\nfn solve a ulong to ulong\nend\n' > invalid-prompt
refuse invalid-prompt
printf '9 0 0 0 0 0 0 0 0 0\n' > invalid
prompt 'demo' 'a view ulong 8 n ulong to ulong'
refuse prompt invalid
rm kit/om_formalize
want=70
refuse prompt
echo 'PASS symbolic, checked scalar and array, neural fallback, trace, specialist, rejection, setup error'
