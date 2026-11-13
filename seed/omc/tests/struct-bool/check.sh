#!/bin/sh
# check.sh -- structs with bool fields (regression for: struct W a uint f bool end, new W 1 false,
# which omc accepted and compiled to a program that dies by SIGILL). The compiler under test is
# seed/out/omc (argument 1 or OMC overrides it). Every row of cases.tsv must compile and the program
# must give its exact exit status. Controls, which must pass even on a broken compiler, keep the rows
# honest: bool logic without a struct, the uchar twin of each row, source mutants of the twins, and a
# self-test that gives the row runner two fake broken compilers and requires it to fail every row.
# Exit 0: all rows and controls pass. Exit 1: controls pass, some row fails (the bug is present).
# Exit 2: a control failed, so the result of the rows cannot be trusted. Host only, no GPU, no build.
# Run as: nice -n19 taskset -c 0 sh seed/omc/tests/struct-bool/check.sh
set -u
R=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
cd "$R"
D=seed/omc/tests/struct-bool
mkdir -p build/seed
B=$(mktemp -d build/seed/struct-bool.XXXXXX)
S=${1:-${OMC:-seed/out/omc}}
case "$S" in /*) ;; *) S="$R/$S";; esac
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 2; }
printf "STRUCTBOOL compiler %s %s scratch %s\n" "$S" "$(sha256sum "$S" | cut -d' ' -f1)" "$B"
ulimit -c 0
say() { printf '%s\n' "$*"; }

# run_status BIN -> prints the exit status (132 = SIGILL), nothing else, no shell job messages
run_status() { timeout 15 sh -c '"$1" >/dev/null 2>&1; echo $?' sh "$1" 2>/dev/null; }

# twin SRC DST: bool -> uchar, true -> 1, false -> 0
twin() { sed -E 's/\bbool\b/uchar/g; s/\btrue\b/1/g; s/\bfalse\b/0/g' "$1" > "$2"; }

# compile COMPILER SRC OUT -> sets crc; OUT is the object, OUT.err the diagnostics
compile() { timeout 60 "$1" < "$2" > "$3" 2> "$3.err"; crc=$?; [ "$crc" != 0 ] || chmod +x "$3"; }

# rows COMPILER PREFIX: run every row of cases.tsv, one PASS/FAIL line each into PREFIX.log
rows() {
    : > "$2.log"
    grep -v '^#' "$D/cases.tsv" | while IFS='	' read -r name want tw kind; do
        [ -n "$name" ] || continue
        o="$2.$name"
        compile "$1" "$D/$name.om" "$o"
        if [ "$crc" != 0 ]; then echo "FAIL $name compiler exit $crc ($(head -c 80 "$o.err"))"; continue; fi
        rc=$(run_status "$o")
        if [ "$rc" = "$want" ]; then echo "PASS $name exit $rc"
        elif [ "$rc" = 132 ]; then echo "FAIL $name SIGILL (exit 132), wanted $want"
        else echo "FAIL $name exit $rc, wanted $want"; fi
    done >> "$2.log"
}

controls=0; cfail=0
cbad() { cfail=$((cfail+1)); say "FAIL control: $*"; }
cok() { controls=$((controls+1)); say "PASS control: $*"; }

# 1. bool logic without a struct runs correctly
compile "$S" "$D/control_nostruct.om" "$B/nostruct"
if [ "$crc" != 0 ]; then cbad "control_nostruct does not compile ($(head -c 80 "$B/nostruct.err"))"
else rc=$(run_status "$B/nostruct")
     if [ "$rc" = 15 ]; then cok "bool locals and function without a struct give 15"; else cbad "control_nostruct exit $rc, wanted 15"; fi; fi

# 2. the uchar twin of each row gives the same status
grep -v '^#' "$D/cases.tsv" | while IFS='	' read -r name want tw kind; do
    [ "$tw" = yes ] || continue
    twin "$D/$name.om" "$B/$name.tw.om"
    cmp -s "$D/$name.om" "$B/$name.tw.om" && { echo "BAD $name twin equals source"; continue; }
    compile "$S" "$B/$name.tw.om" "$B/$name.tw"
    if [ "$crc" != 0 ]; then echo "BAD $name twin does not compile ($(head -c 80 "$B/$name.tw.err"))"; continue; fi
    rc=$(run_status "$B/$name.tw")
    [ "$rc" = "$want" ] && echo "OK $name twin exit $rc" || echo "BAD $name twin exit $rc, wanted $want"
done > "$B/twins.log"
nt=$(grep -c '^OK' "$B/twins.log"); nb=$(grep -c '^BAD' "$B/twins.log")
expected_twins=$(awk -F '\t' '$3 == "yes" {n++} END {print n+0}' "$D/cases.tsv")
if [ "$nb" = 0 ] && [ "$nt" = "$expected_twins" ] && [ "$nt" -gt 0 ]; then cok "$nt uchar twins give the expected status"
else cat "$B/twins.log"; cbad "uchar twins: $nt ok, $nb bad"; fi

# 3. mutants of the twins change the status (each site occurs exactly once)
grep -v '^#' "$D/mutants.tsv" | while IFS='	' read -r name expr; do
    [ -n "$name" ] || continue
    want=$(grep "^$name	" "$D/cases.tsv" | cut -f2)
    twin "$D/$name.om" "$B/$name.tw.om"
    sed -E "$expr" "$B/$name.tw.om" > "$B/$name.mut.om"
    cmp -s "$B/$name.tw.om" "$B/$name.mut.om" && { echo "BAD $name mutant site not found"; continue; }
    compile "$S" "$B/$name.mut.om" "$B/$name.mut"
    if [ "$crc" != 0 ]; then echo "BAD $name mutant does not compile"; continue; fi
    rc=$(run_status "$B/$name.mut")
    if [ "$rc" = "$want" ]; then echo "BAD $name mutant not detected (exit $rc)"
    elif [ "$rc" -ge 100 ]; then echo "BAD $name mutant only crashed (exit $rc)"
    else echo "OK $name mutant exit $rc, not $want"; fi
done > "$B/mutants.log"
nm=$(grep -c '^OK' "$B/mutants.log"); nmb=$(grep -c '^BAD' "$B/mutants.log")
expected_mutants=$(grep -v '^#' "$D/mutants.tsv" | grep -c .)
if [ "$nmb" = 0 ] && [ "$nm" = "$expected_mutants" ] && [ "$nm" -gt 0 ]; then cok "$nm twin mutants change the status"
else cat "$B/mutants.log"; cbad "mutants: $nm detected, $nmb not"; fi

# 4. the row runner fails every row on fake broken compilers (the control that catches a broken one)
total=$(grep -v '^#' "$D/cases.tsv" | grep -c .)
nonzero=$(grep -v '^#' "$D/cases.tsv" | awk -F '\t' 'NF && $2 != "0"' | wc -l)
printf '#!/bin/sh\ncat >/dev/null\nprintf "#!/bin/sh\\nkill -ILL \\$\\$\\n"\n' > "$B/fake-sigill"
printf '#!/bin/sh\ncat >/dev/null\nprintf "#!/bin/sh\\nexit 0\\n"\n' > "$B/fake-zero"
chmod +x "$B/fake-sigill" "$B/fake-zero"
rows "$B/fake-sigill" "$B/fs"; rows "$B/fake-zero" "$B/fz"
fs=$(grep -c '^FAIL' "$B/fs.log"); fz=$(grep -c '^FAIL' "$B/fz.log")
if [ "$fs" = "$total" ] && grep -q 'SIGILL' "$B/fs.log"; then cok "a compiler whose programs die by SIGILL fails all $total rows"
else cbad "fake SIGILL compiler failed $fs of $total rows"; fi
if [ "$fz" = "$nonzero" ]; then cok "a compiler whose programs always exit 0 fails the $nonzero rows that want a non-zero status"
else cbad "fake zero compiler failed $fz rows, wanted $nonzero"; fi

# 5. the row runner passes every twin-able row on a stand-in for a fixed compiler: the real compiler
# fed the uchar twin of the source. A pass path that never fires would hide a runner that cannot pass.
cat > "$B/fake-twin" <<TWIN
#!/bin/sh
sed -E 's/\\bbool\\b/uchar/g; s/\\btrue\\b/1/g; s/\\bfalse\\b/0/g' | exec "$S"
TWIN
chmod +x "$B/fake-twin"
rows "$B/fake-twin" "$B/ft"
twins=$(grep -v '^#' "$D/cases.tsv" | awk -F '\t' '$3 == "yes"' | wc -l)
bad=0
for name in $(grep -v '^#' "$D/cases.tsv" | awk -F '\t' '$3 == "yes" {print $1}'); do
    grep -q "^PASS $name " "$B/ft.log" || { bad=$((bad+1)); grep "^FAIL $name " "$B/ft.log"; }
done
if [ "$bad" = 0 ]; then cok "a stand-in fixed compiler (uchar twin) passes all $twins twin-able rows"
else cbad "stand-in fixed compiler failed $bad of $twins twin-able rows"; fi

# the rows against the compiler under test
rows "$S" "$B/real"
cat "$B/real.log"
pass=$(grep -c '^PASS' "$B/real.log"); fail=$(grep -c '^FAIL' "$B/real.log")
if [ "$cfail" != 0 ]; then
    say "STRUCTBOOL INVALID controls=$controls failed=$cfail rows pass=$pass fail=$fail (the rows cannot be trusted)"
    exit 2
fi
if [ "$fail" != 0 ] || [ "$pass" != "$total" ]; then
    say "STRUCTBOOL FAIL rows pass=$pass fail=$fail of $total (controls PASS $controls): struct bool field is broken"
    exit 1
fi
say "STRUCTBOOL PASS rows=$pass controls=$controls"
