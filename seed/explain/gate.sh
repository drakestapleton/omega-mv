#!/bin/sh
# gate.sh -- the explain tool (seed/explain/explain.om): plain-language refusals without changing omc.
#   sh seed/explain/gate.sh         build explain with seed/out/omc and run every check below
#   sh seed/explain/gate.sh table   print the MEANS line generated from seed/omc/error-codes.reg
# Checks: (1) the MEANS line in explain.om equals the registry; a changed meaning is caught (negative
# control). (2) Every gate15 refusal case, read from gate15.sh itself, keeps omc's exit code and prints
# exactly "p.om:L: error C: MEANING" and "    L | <line L of p.om>". (3) A valid program compiles to the
# same bytes as omc alone and runs. (4) Stand-in compilers: a wrong-form message, a code that differs
# from the message, a signal, a missing compiler, 100 KB of stderr; and usage. (5) Two runs are identical.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=seed/out/omc
E=seed/explain/explain.om
REG=$R/seed/omc/error-codes.reg
table() { awk -F'|' 'BEGIN{printf "text means \""} $1=="omc"{printf "%s\\n", $5} END{printf "\"\n"}' "$REG"; }
if [ "${1:-}" = table ]; then table; exit 0; fi
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
mkdir -p build/seed/explain
T=$(mktemp -d build/seed/explain/run.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf 'PASS %s\n' "$*"; }
meaning() { awk -F'|' -v c="$1" '$1=="omc" && $2==c {print $5}' "$REG"; }

# (1) table drift, with its negative control
drift() { [ "$(grep '^text means "' "$1")" = "$(table)" ]; }
drift "$E" || bad "explain.om MEANS differs from $REG; regenerate with: sh seed/explain/gate.sh table"
sed 's/\\ntype mismatch\\n/\\ntype mismatches\\n/' "$E" > "$T/mut.om"
cmp -s "$E" "$T/mut.om" && bad "negative control: the mutant table equals the original"
drift "$T/mut.om" && bad "negative control: a changed meaning was not caught"
say "table equals the registry (30 codes); a changed meaning is caught"

"$S" < "$E" > "$T/explain" 2> "$T/build.err" || bad "omc refused explain.om: $(cat "$T/build.err")"
chmod +x "$T/explain"
X=$R/$T/explain
O=$R/$S
say "explain builds with $S ($(wc -c < "$T/explain") bytes)"

# (2) every gate15 refusal case
awk "/<<'CASES'/{f=1;next} /^CASES\$/{f=0} f" seed/omc/gate15.sh > "$T/cases"
want_n=$(grep -c '|' "$T/cases")
[ "$want_n" -ge 20 ] || bad "read only $want_n cases from gate15.sh"
n=0
cd "$T"
while IFS='|' read -r name want line src; do
    [ -n "$name" ] || continue
    printf '%b\n' "$src" > p.om
    set +e; "$X" "$O" p.om p.bin > p.out 2> p.err; rc=$?; set -e
    [ "$rc" = "$want" ] || bad "$name: exit $rc, wanted $want ($(cat p.err))"
    m=$(meaning "$want")
    [ -n "$m" ] || bad "$name: no registry meaning for $want"
    [ "$(sed -n 1p p.err)" = "p.om:$line: error $want: $m" ] || bad "$name: line 1 '$(sed -n 1p p.err)'"
    src_line=$(sed -n "${line}p" p.om)
    [ "$(grep -c '' p.om)" -ge "$line" ] || src_line='(end of file)'
    [ "$(sed -n 2p p.err)" = "    $line | $src_line" ] || bad "$name: line 2 '$(sed -n 2p p.err)', wanted '    $line | $src_line'"
    [ "$(grep -c '' p.err)" = 2 ] || bad "$name: $(grep -c '' p.err) stderr lines, wanted 2"
    [ -s p.out ] && bad "$name: wrote to stdout"
    n=$((n + 1))
done < cases
[ "$n" = "$want_n" ] || bad "ran $n of $want_n gate15 cases"
say "all $n gate15 refusal cases: omc's exit code kept, meaning and source line shown"

# (3) valid control: same bytes as omc alone, and the program runs
printf 'fn main to int\nret 7\nend\n' > g.om
"$O" < g.om > g.direct 2> g.derr || bad "valid control refused by omc"
set +e; "$X" "$O" g.om g.bin > g.out 2> g.err; rc=$?; set -e
[ "$rc" = 0 ] || bad "valid control: exit $rc ($(cat g.err))"
[ -s g.err ] && bad "valid control: stderr '$(cat g.err)'"
[ "$(cat g.out)" = "g.om: compiled, program written to g.bin" ] || bad "valid control: stdout '$(cat g.out)'"
cmp -s g.direct g.bin || bad "valid control: output differs from omc alone"
chmod +x g.bin
set +e; ./g.bin; rc=$?; set -e
[ "$rc" = 7 ] || bad "valid control: program exit $rc, wanted 7"
say "valid program: same bytes as omc alone, runs with exit 7"

# om2 diag: the machine record passes through after the explanation
printf 'om2 diag\nfn main to int\nx = add int 1 uint 2\nret 0\nend\n' > d.om
set +e; "$X" "$O" d.om d.bin 2> d.err; rc=$?; "$O" < d.om > /dev/null 2> d.direct; set -e
[ "$rc" = 7 ] || bad "om2 diag: exit $rc"
[ "$(sed -n 1p d.err)" = "d.om:3: error 7: $(meaning 7)" ] || bad "om2 diag: line 1 '$(sed -n 1p d.err)'"
[ "$(sed -n 3p d.err)" = "$(sed -n 2p d.direct)" ] || bad "om2 diag: record not passed through"
say "om2 diag record passed through unchanged after the explanation"

# (4) stand-in compilers and usage
odd="explain: the compiler's message is not in the form omc: line L: error C"
stand() { printf '#!/bin/sh\n%s\n' "$2" > "$1"; chmod +x "$1"; }
stand c_form 'echo boom >&2; exit 7'
stand c_code 'echo "omc: line 2: error 7" >&2; exit 9'
stand c_sig 'kill -9 $$'
stand c_big 'i=0; while [ $i -lt 1600 ]; do printf "%%064d\\n" 0 >&2; i=$((i+1)); done; exit 3'
stand c_huge 'echo "omc: line 99999999999999999999999: error 7" >&2; exit 7'
chk() { # chk NAME COMPILER WANT_RC WANT_LAST_LINE
    set +e; "$X" "$R/$T/$2" g.om s.bin > s.out 2> s.err; rc=$?; set -e
    [ "$rc" = "$3" ] || bad "$1: exit $rc, wanted $3 ($(tail -1 s.err))"
    [ "$(tail -1 s.err)" = "$4" ] || bad "$1: last line '$(tail -1 s.err)', wanted '$4'"
}
chk "wrong-form message" c_form 7 "$odd"
chk "code differs from message" c_code 9 "$odd"
chk "compiler killed" c_sig 66 "explain: the compiler was stopped by signal 9"
chk "100 KB of stderr" c_big 3 "$odd"
chk "line number past 20 digits" c_huge 7 "$odd"
set +e; "$X" /nonexistent/omc g.om s.bin 2> s.err; rc=$?; set -e
[ "$rc" = 65 ] && [ "$(cat s.err)" = "explain: the compiler could not be started" ] || bad "missing compiler: exit $rc '$(cat s.err)'"
set +e; "$X" "$O" no-such.om s.bin 2> s.err; rc=$?; set -e
[ "$rc" = 65 ] && [ "$(cat s.err)" = "explain: cannot open no-such.om" ] || bad "missing source: exit $rc '$(cat s.err)'"
set +e; "$X" "$O" g.om 2> s.err; rc=$?; set -e
[ "$rc" = 64 ] && [ "$(cat s.err)" = "usage: explain OMC SRC OUT" ] || bad "usage: exit $rc '$(cat s.err)'"
say "stand-ins: odd message, code mismatch, signal, missing compiler, missing source, 100 KB stderr, usage"

# (5) determinism
printf 'fn f to int\nret q\nend\n' > r.om
set +e; "$X" "$O" r.om r.bin 2> r1.err; "$X" "$O" r.om r.bin 2> r2.err; set -e
cmp -s r1.err r2.err || bad "two runs differ"
say "two runs identical"
printf 'RC=0\n'
