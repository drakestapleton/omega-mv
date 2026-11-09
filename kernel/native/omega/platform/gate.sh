#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Host verification oracle only. No hardware access; the implementation under
# test is readback.om. POSIX sh, awk, od, sha256sum, nice and the pinned omc.
#
# Usage: sh native/omega/platform/gate.sh /absolute/pinned/omc EXPECTED_SHA256 OUT_DIR
#
# Builds unit.om and a descriptor-parity program generated from
# cppc-fixture.json (twenty CPUs, twelve selected CPPC descriptors each, plus
# seven thermal zones), requires both to compile and exit 0, then compiles six
# single-site mutants of readback.om and requires each to compile and exit
# nonzero. A compiler failure is never counted as a killed mutant.
# Writes per-program .om, binary, .compile.stderr, .stdout, .stderr and
# results.json into OUT_DIR.
set -eu
export LC_ALL=C
# cd prints the directory when CDPATH supplies it, which would corrupt $(cd ...).
unset CDPATH

die() { printf 'PLATFORM READBACK FAIL: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 3 ] || die "usage: gate.sh OMC EXPECTED_SHA256 OUT_DIR"
here=$(cd "$(dirname "$0")" && pwd -P)
omc=$1
expected=$2
mkdir -p "$3"
out=$(cd "$3" && pwd -P)

[ -f "$omc" ] || die "compiler not found: $omc"
got=$(sha256sum < "$omc" | cut -d' ' -f1)
[ "$got" = "$expected" ] || die "compiler pin mismatch (got $got)"
case "$omc" in /*) ;; *) omc=$(cd "$(dirname "$omc")" && pwd -P)/$(basename "$omc") ;; esac

source=$here/readback.om
unit=$here/unit.om
fixture=$here/cppc-fixture.json
for f in "$source" "$unit" "$fixture"; do
  [ -f "$f" ] || die "missing input $f"
  # The byte concatenations below rely on each input ending in a newline.
  [ "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" = '\n' ] || die "$f does not end in a newline"
done

# Descriptor-parity program from the fixture. The reader is a small
# recursive-descent JSON parser: strings without escapes or control characters,
# objects, arrays, JSON numbers and the literals true, false and null. It
# requires a cpus array of exactly 20 objects, each with a registers array of
# exactly 21 objects whose space, bits, offset, address and access fields are
# strings (no duplicate keys anywhere), hex values written 0x..., a known
# address space, offset 0 and the access width implied by the space.
parity=$out/descriptor-parity.checks
count=$out/descriptor-parity.count
awk -v countfile="$count" '
function fail(m) { printf "PLATFORM READBACK FAIL: fixture: %s\n", m > "/dev/stderr"; failed = 1; exit 1 }
function hexval(s,    i, v) {
  if (s !~ /^0[xX][0-9A-Fa-f]+$/) fail("not a 0x hex value: " s)
  s = substr(s, 3); sub(/^0+/, "", s)
  if (length(s) > 13) fail("hex value too wide: " s)
  v = 0
  for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
  return v
}
function tokenize(    n, p, q, c) {
  n = length(text); p = 1; nt = 0
  while (p <= n) {
    c = substr(text, p, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") { p++; continue }
    if (index("[]{}:,", c)) { tt[++nt] = c; tv[nt] = c; p++; continue }
    if (c == "\"") {
      q = p + 1
      while (q <= n && substr(text, q, 1) != "\"") {
        if (substr(text, q, 1) == "\\") fail("escaped strings are not supported")
        if (substr(text, q, 1) ~ /[\001-\037]/) fail("control character in a string")
        q++
      }
      if (q > n) fail("unterminated string")
      tt[++nt] = "s"; tv[nt] = substr(text, p + 1, q - p - 1); p = q + 1; continue
    }
    q = p
    while (q <= n && substr(text, q, 1) ~ /[-+.0-9A-Za-z]/) q++
    if (q == p) fail("unexpected character " c)
    tt[++nt] = "v"; tv[nt] = substr(text, p, q - p); p = q
    if (tv[nt] !~ /^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?)$/) fail("not a JSON value: " tv[nt])
  }
}
function want(t) { if (P > nt || tt[P] != t) fail("expected " t " at token " P); P++ }
# Parses one value at depth d (path[1..d] names where it sits).
function value(d,    t, key, idx, seen) {
  if (P > nt) fail("unexpected end of input")
  t = tt[P]
  # Every cpus and registers element must be an object, so a stray scalar
  # cannot pad or shape the counts below.
  if (path[1] == "cpus") {
    if (d == 1 && t != "[") fail("cpus is not an array")
    if (d == 2 && t != "{") fail("cpu " path[2] " is not an object")
    if (d == 3 && path[3] == "registers" && t != "[") fail("cpu " path[2] ": registers is not an array")
    if (d == 4 && path[3] == "registers" && t != "{") fail("cpu " path[2] " register " path[4] " is not an object")
  }
  if (t == "s" || t == "v") {
    if (d == 5 && path[1] == "cpus" && path[3] == "registers") {
      if (t != "s") fail("register field " path[5] " is not a string")
      reg[path[2], path[4], path[5]] = tv[P]
    }
    P++; return
  }
  if (t == "{") {
    P++
    if (d == 2 && path[1] == "cpus") ncpu = path[2] + 1
    if (d == 4 && path[1] == "cpus" && path[3] == "registers") nreg[path[2]] = path[4] + 1
    if (P <= nt && tt[P] == "}") { P++; return }
    for (;;) {
      if (P > nt || tt[P] != "s") fail("object key expected at token " P)
      key = tv[P]; P++
      seen = d SUBSEP objid[d] SUBSEP key
      if (seen in dup) fail("duplicate key " key)
      dup[seen] = 1
      want(":")
      path[d + 1] = key; objid[d + 1] = ++nobj
      value(d + 1)
      if (P <= nt && tt[P] == ",") { P++; continue }
      want("}"); return
    }
  }
  if (t == "[") {
    P++
    if (d == 1 && path[1] == "cpus") cpus_seen = 1
    if (d == 3 && path[1] == "cpus" && path[3] == "registers") nreg[path[2]] = 0
    if (P <= nt && tt[P] == "]") { P++; return }
    for (idx = 0; ; idx++) {
      path[d + 1] = idx; objid[d + 1] = ++nobj
      value(d + 1)
      if (P <= nt && tt[P] == ",") { P++; continue }
      want("]"); return
    }
  }
  fail("value expected at token " P)
}
{ text = text $0 "\n" }
END {
  if (failed) exit 1
  tokenize()
  P = 1; objid[0] = 0
  if (nt == 0 || tt[1] != "{") fail("top level is not an object")
  value(0)
  if (P <= nt) fail("trailing data after the top-level object")
  if (!cpus_seen) fail("no cpus array")
  if (ncpu != 20) fail("expected 20 cpus, found " ncpu + 0)
  split("space bits offset address access", F, " ")
  for (c = 0; c < 20; c++) {
    if (nreg[c] != 21) fail("cpu " c ": expected 21 registers, found " nreg[c] + 0)
    for (r = 0; r < 21; r++)
      for (k = 1; k <= 5; k++)
        if (!((c, r, F[k]) in reg)) fail("cpu " c " register " r ": missing " F[k])
  }
  print "fn main to int"
  seq = 0
  split("0 1 2 3 4 10 11 12 13 18 19 20", sel, " ")
  for (c = 0; c < 20; c++) {
    for (j = 1; j <= 12; j++) {
      f = sel[j] + 0
      sp = reg[c, f, "space"]
      if (sp == "SystemMemory") space = 0
      else if (sp == "FFixedHW") space = 127
      else fail("cpu " c " field " f ": unknown space " sp)
      bits = hexval(reg[c, f, "bits"])
      addr = hexval(reg[c, f, "address"])
      if (hexval(reg[c, f, "offset"]) != 0) fail("cpu " c " field " f ": offset is not 0")
      if (hexval(reg[c, f, "access"]) != (space == 0 ? 3 : 0)) fail("cpu " c " field " f ": access width does not match the space")
      seq++
      printf "if ne plstart 1 %d %d %d 0\nret 1\nend\n", c, f, seq
      printf "if ne plack %d %d %.0f %.0f 3132 1 0\nret 2\nend\n", seq, space, addr, bits
      print "if or ne get Pl 5 3132 ne get Pl 6 1"; print "ret 3"; print "end"
    }
  }
  # Thermal zone registers (fixed addresses, not from the fixture).
  split("0x1C238818 0x1C238820 0x1C238824 0x1C238828 0x1C23882C 0x1C238830 0x1C238834", zone, " ")
  for (z = 1; z <= 7; z++) {
    seq++
    printf "if ne plstart 0 %d 0 %d 0\nret 4\nend\n", z - 1, seq
    printf "if ne plack %d 0 %.0f 32 3132 1 0\nret 5\nend\n", seq, hexval(zone[z])
  }
  print "ret 0"; print "end"
  print seq > countfile
}
' "$fixture" > "$parity" || die "fixture rejected"
seq=$(cat "$count")
case "$seq" in ''|*[!0-9]*) die "fixture reader returned no descriptor count" ;; esac

results=''
run() { # name input_file expect(pass|fail)
  name=$1 input=$2 expect=$3
  src=$out/$name.om
  bin=$out/$name
  cp "$input" "$src"
  rc=0
  nice -n 15 "$omc" < "$src" > "$bin" 2> "$out/$name.compile.stderr" || rc=$?
  [ "$rc" -eq 0 ] || die "$name: compile failed (exit $rc), not a valid mutant kill"
  chmod 755 "$bin"
  rc=0
  nice -n 15 "$bin" > "$out/$name.stdout" 2> "$out/$name.stderr" || rc=$?
  case "$expect" in
    pass) [ "$rc" -eq 0 ] || die "$name: unexpected exit $rc" ;;
    fail) [ "$rc" -ne 0 ] || die "$name: unexpected exit $rc" ;;
  esac
  sum=$(sha256sum < "$bin" | cut -d' ' -f1)
  entry=$(printf '  {\n    "name": "%s",\n    "compile_exit": 0,\n    "run_exit": %d,\n    "sha256": "%s"\n  }' "$name" "$rc" "$sum")
  if [ -n "$results" ]; then results="$results,
$entry"; else results=$entry; fi
}

cat "$source" "$unit" > "$out/unit.input"
cat "$source" "$parity" > "$out/descriptor-parity.input"
run unit "$out/unit.input" pass
run descriptor-parity "$out/descriptor-parity.input" pass

# Each mutant changes exactly one literal site in readback.om.
nmut=0
mutant() { # name old new test(unit|parity)
  name=$1 old=$2 new=$3 test=$4
  awk -v old="$old" -v new="$new" '
    function count(s,    n, i) { n = 0; while ((i = index(s, old)) > 0) { n++; s = substr(s, i + length(old)) } return n }
    function repl(s,    r, i) { r = ""; while ((i = index(s, old)) > 0) { r = r substr(s, 1, i - 1) new; s = substr(s, i + length(old)) } return r s }
    { line[NR] = $0; total += count($0) }
    END {
      if (total != 1) { printf "PLATFORM READBACK FAIL: mutant site occurs %d times: %s\n", total, old > "/dev/stderr"; exit 1 }
      for (k = 1; k <= NR; k++) print repl(line[k])
    }' "$source" > "$out/$name.mutated" || die "mutant $name: site is not unique"
  if [ "$test" = parity ]; then t=$parity; else t=$unit; fi
  cat "$out/$name.mutated" "$t" > "$out/$name.input"
  run "$name" "$out/$name.input" fail
  nmut=$((nmut + 1))
}
mutant stale-ack 'if or ne seq get Pl 1 ne space get Pl 2' 'if ne space get Pl 2' unit
mutant wrong-address 'if or ne addr get Pl 3 ne bits get Pl 4' 'if ne bits get Pl 4' unit
mutant write-selector 'if lt field 5' 'if lt field 6' unit
mutant wide-raw 'if gt raw 4294967295' 'if gt raw 18446744073709551615' unit
mutant thermal-address 'ret 472090648' 'ret 472090649' parity
mutant cppc-stride 'mul unit 232' 'mul unit 233' parity

printf '[\n%s\n]\n' "$results" > "$out/results.json"
printf 'PLATFORM READBACK PASS: %d descriptor reads; boundary suite; %d runnable mutants rejected\n' "$seq" "$nmut"
