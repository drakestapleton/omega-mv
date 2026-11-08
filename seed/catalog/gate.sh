#!/bin/sh
# seed/catalog/gate.sh: thin glue around resolve.om, omc and irequiv (README.md, section Gate).
# usage: seed/catalog/gate.sh [OUTDIR]     env: OA (default seed/out/omc), OB (second compiler)
# Every check prints one PASS or FAIL line; the last line is GATE PASS or GATE FAIL n.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OA=${OA:-$root/seed/out/omc}
OB=${OB:-$HOME/work/omega-node-e5b3/seed/out/omc}
OUT=${1:-/tmp/semcat-gate}
T=$here/tests
CAT=$here/catalog.om
# Reserve a fresh directory; never remove or reuse retained evidence.
if ! mkdir -- "$OUT"; then
  printf '%s\n' "ERROR: output directory must be new with an existing parent: $OUT" >&2
  exit 2
fi
# Output directory reserved.
fails=0
checks=0
ok() { checks=$((checks + 1)); echo "PASS $*"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL $*"; }
want() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got $1 want $2)"; fi; }

for f in "$OA" "$OB" "$CAT" "$here/resolve.om" "$root/om/sha256/sha256-om2.om" "$T/expected.tsv"; do
  echo "HASH $(sha256sum "$f")"
done

# 1. resolve built by both compilers (sha256-om2.om first; its export words dropped).
{ sed 's/^export fn /fn /' "$root/om/sha256/sha256-om2.om"; cat "$here/resolve.om"; } > "$OUT/resolve-full.om"
for c in A B; do
  eval omc=\$O$c
  "$omc" < "$OUT/resolve-full.om" > "$OUT/resolve.$c"; rc=$?
  chmod +x "$OUT/resolve.$c"
  want $rc 0 "build resolve.$c"
done
R=$OUT/resolve.A

# 2. identity = sha256 of the record bytes (catalog lines 5..end hold the one record of entry #1).
id=$("$R" ids "$CAT" | awk '{print $2}')
want "$id" "$(tail -n +5 "$CAT" | sha256sum | awk '{print $1}')" "identity add_times = sha256(record)"
want "$(awk '{print $2}' "$T/lock.b")" "$id" "lock.b carries the catalog identity"

# map check: every unit line equals the compact or catalog line its map line names. A catalog fn line
# carries the suffix " inline" exactly when the lock marks that entry inline; no other line may.
mapchk() { # unit map compact catalog lock
  awk -v U="$1" -v P="$3" -v C="$4" -v L="$5" '
    BEGIN { while ((getline l < U) > 0) u[++nu] = l; while ((getline l < P) > 0) p[++np] = l
            while ((getline l < C) > 0) c[++nc] = l
            while ((getline l < L) > 0) { split(l, f, " "); if (f[3] == "inline") inl[f[1]] = 1 } }
    { n++; s = u[n]
      if ($0 == "R om2") { if (s != "om2") bad = 1 }
      else if ($1 == "C") { if (s != p[$2]) bad = 1 }
      else if ($1 == "E") { w = c[$3]; if (($2 in inl) && w ~ /^fn /) w = w " inline"; if (s != w) bad = 1 }
      else bad = 1 }
    END { if (n != nu) bad = 1; exit bad }' "$2"
}
# inline fn lines in a unit: must equal the inline lines of its lock (1 in arm C, 0 in arm B).
inlchk() { # unit lock label
  want "$(grep -c ' inline$' "$1")" "$(grep -c ' inline$' "$2")" "$3"
}

# 3. f4: resolve twice per resolver, compare across resolvers, check the map.
for it in 76666 83423 82342 85188; do
  P=$T/f4/item$it.compact.om
  for arm in b c; do
    for c in A B; do
      "$OUT/resolve.$c" build "$CAT" "$T/lock.$arm" "$P" "$OUT/$it.$arm.$c.map" > "$OUT/$it.$arm.$c.om" 2> "$OUT/$it.$arm.$c.acct"; rc=$?
      want $rc 0 "resolve.$c item$it arm $arm"
      "$OUT/resolve.$c" build "$CAT" "$T/lock.$arm" "$P" "$OUT/$it.$arm.$c.map2" > "$OUT/$it.$arm.$c.om2" 2>/dev/null
      if cmp -s "$OUT/$it.$arm.$c.om" "$OUT/$it.$arm.$c.om2" && cmp -s "$OUT/$it.$arm.$c.map" "$OUT/$it.$arm.$c.map2"; then
        ok "deterministic resolve.$c item$it arm $arm"; else bad "deterministic resolve.$c item$it arm $arm"; fi
    done
    if cmp -s "$OUT/$it.$arm.A.om" "$OUT/$it.$arm.B.om" && cmp -s "$OUT/$it.$arm.A.map" "$OUT/$it.$arm.B.map"; then
      ok "resolve.A = resolve.B item$it arm $arm"; else bad "resolve.A = resolve.B item$it arm $arm"; fi
    if mapchk "$OUT/$it.$arm.A.om" "$OUT/$it.$arm.A.map" "$P" "$CAT" "$T/lock.$arm"; then
      ok "map item$it arm $arm"; else bad "map item$it arm $arm"; fi
    inlchk "$OUT/$it.$arm.A.om" "$T/lock.$arm" "inline fn lines item$it arm $arm"
  done
done

# 4. f4 programs compiled by both compilers: A (hand), B (call), C (inline) exit with the same value.
#    Exit = (x + k*n) mod 256 with x, k, n of each item (README.md, Wolfram):
#    WolframLanguageEvaluator: Mod[{70+4*3, 71+5*3, 72+1*6, 70+2*4}, 256] -> {82, 86, 78, 78}
for c in A B; do
  eval omc=\$O$c
  for it in 76666 83423 82342 85188; do
    case $it in 76666) exp=82 ;; 83423) exp=86 ;; 82342) exp=78 ;; 85188) exp=78 ;; esac
    for arm in a b c; do
      if [ $arm = a ]; then src=$T/f4/item$it.a.om; else src=$OUT/$it.$arm.A.om; fi
      "$omc" < "$src" > "$OUT/$it.$arm.$c.bin"; rc=$?
      want $rc 0 "omc.$c compiles item$it arm $arm"
      chmod +x "$OUT/$it.$arm.$c.bin"
      "$OUT/$it.$arm.$c.bin"; rc=$?
      want $rc $exp "omc.$c item$it arm $arm exit"
    done
  done
done

# 5. behavior over the Wolfram table (expected.tsv): f4 rows on arms a b c, entry rows on b c.
drive() { # name prog lock -> $OUT/drv.name.om (resolved when lock is given)
  { cat "$T/drive.om"; head -n -3 "$2"; cat "$T/dmain.om"; } > "$OUT/drv.$1.src"
  if [ -n "$3" ]; then
    "$R" build "$CAT" "$3" "$OUT/drv.$1.src" "$OUT/drv.$1.map" > "$OUT/drv.$1.om" 2>/dev/null
  else cp "$OUT/drv.$1.src" "$OUT/drv.$1.om"; fi
}
rows() { # case bin argsmode -> prints mismatch count
  awk -F'\t' -v k="$1" '$1 == k' "$T/expected.tsv" | {
    n=0; m=0
    while IFS="$(printf '\t')" read -r cs x k nn e; do
      if [ "$3" = entry ]; then o=$("$2" "$x" "$k" "$nn"); s=$?; else o=$("$2" "$x"); s=$?; fi
      case $e in trap*) w="$((100 + ${e#trap}))|" ;; *) w="0|$e" ;; esac
      n=$((n + 1))
      if [ "$s|$o" != "$w" ]; then m=$((m + 1)); echo "  MISMATCH $cs x=$x k=$k n=$nn got $s|$o want $w" >&2; fi
    done
    echo "$n $m"
  }
}
for it in 76666 83423 82342 85188; do
  drive "$it.a" "$T/f4/item$it.a.om" ""
  drive "$it.b" "$T/f4/item$it.compact.om" "$T/lock.b"
  drive "$it.c" "$T/f4/item$it.compact.om" "$T/lock.c"
done
{ cat "$T/entry.compact.om"; printf 'fn main to int\nret 0\nend\n'; } > "$OUT/entry.prog"
drive entry.b "$OUT/entry.prog" "$T/lock.b"
drive entry.c "$OUT/entry.prog" "$T/lock.c"
for c in A B; do
  eval omc=\$O$c
  for it in 76666 83423 82342 85188; do
    for arm in a b c; do
      "$omc" < "$OUT/drv.$it.$arm.om" > "$OUT/drv.$it.$arm.$c"; chmod +x "$OUT/drv.$it.$arm.$c"
      set -- $(rows "item$it" "$OUT/drv.$it.$arm.$c" f4)
      want "$2" 0 "omc.$c item$it arm $arm: $1 table rows"
    done
  done
  for arm in b c; do
    "$omc" < "$OUT/drv.entry.$arm.om" > "$OUT/drv.entry.$arm.$c"; chmod +x "$OUT/drv.entry.$arm.$c"
    set -- $(rows entry "$OUT/drv.entry.$arm.$c" entry)
    want "$2" 0 "omc.$c entry arm $arm: $1 table rows"
  done
done

# 5b. dependency closure: add_twice (two.cat.om) calls add_times; the lock lists add_twice first and
#     the unit must hold add_times first. 70 + 2*4*3 = 94 (Wolfram, README.md).
TWO=$T/two.cat.om
{ "$R" ids "$TWO" | awk '$1 == "add_twice"'; "$R" ids "$TWO" | awk '$1 == "add_times"'; } > "$OUT/two.b.lock"
awk '{ print $0 " inline" }' "$OUT/two.b.lock" > "$OUT/two.c.lock"
for arm in b c; do
  "$R" build "$TWO" "$OUT/two.$arm.lock" "$T/dep.compact.om" "$OUT/two.$arm.map" > "$OUT/two.$arm.om" 2> "$OUT/two.$arm.acct"; rc=$?
  want $rc 0 "resolve two-entry closure arm $arm"
  want "$(awk '$1 == "E" { print $2; exit }' "$OUT/two.$arm.map")" add_times "dependency emitted first arm $arm"
  if mapchk "$OUT/two.$arm.om" "$OUT/two.$arm.map" "$T/dep.compact.om" "$TWO" "$OUT/two.$arm.lock"; then
    ok "map two-entry arm $arm"; else bad "map two-entry arm $arm"; fi
  inlchk "$OUT/two.$arm.om" "$OUT/two.$arm.lock" "inline fn lines two-entry arm $arm"
  for c in A B; do
    eval omc=\$O$c
    "$omc" < "$OUT/two.$arm.om" > "$OUT/two.$arm.$c"; chmod +x "$OUT/two.$arm.$c"
    "$OUT/two.$arm.$c"; rc=$?
    want $rc 94 "omc.$c two-entry arm $arm exit"
  done
done

# 5c. a compact that already starts with om2: nothing is inserted, the map starts with C 1.
"$R" build "$CAT" "$T/lock.c" "$T/om2.compact.om" "$OUT/om2.map" > "$OUT/om2.om" 2> "$OUT/om2.acct"; rc=$?
want "$rc $(head -n 1 "$OUT/om2.map") $(sed 's/.* //' "$OUT/om2.acct")" "0 C 1 om2_added=0" "om2 compact keeps its own om2"
"$OA" < "$OUT/om2.om" > "$OUT/om2.bin"; chmod +x "$OUT/om2.bin"; "$OUT/om2.bin"; rc=$?
want $rc 82 "om2 compact arm c exit"

# 5d. every om2 header omc accepts (om2lead and cp_mode: om2 [diag] [debug|release]) is kept: nothing is
#     inserted, the map starts with C 1, and arm C runs on both compilers with the f4 item76666 exit 82.
#     check/next then om2 (chk_mode, compiler A only) is kept too; it makes a check report, not a program.
for h in diag debug release diagdebug diagrelease checkom2; do
  "$R" build "$CAT" "$T/lock.c" "$T/hdr/$h.compact.om" "$OUT/hdr.$h.map" > "$OUT/hdr.$h.om" 2> "$OUT/hdr.$h.acct"; rc=$?
  want "$rc $(head -n 1 "$OUT/hdr.$h.map") $(sed 's/.* //' "$OUT/hdr.$h.acct")" "0 C 1 om2_added=0" "header $h kept"
  if mapchk "$OUT/hdr.$h.om" "$OUT/hdr.$h.map" "$T/hdr/$h.compact.om" "$CAT" "$T/lock.c"; then
    ok "map header $h"; else bad "map header $h"; fi
  [ $h = checkom2 ] && continue
  for c in A B; do
    eval omc=\$O$c
    "$omc" < "$OUT/hdr.$h.om" > "$OUT/hdr.$h.$c" 2>/dev/null; rc=$?; chmod +x "$OUT/hdr.$h.$c"
    "$OUT/hdr.$h.$c" 2>/dev/null; want "$rc $?" "0 82" "omc.$c header $h arm c exit"
  done
done

# 5e. OM-2-only words: requires used as an OM-1 name is refused with an inline lock (section 8) and runs
#     with a call lock: 0 + 4*3 = 12 (Wolfram, README.md). Words inside a text literal are not scanned.
"$R" build "$CAT" "$T/lock.b" "$T/requires.compact.om" "$OUT/req.map" > "$OUT/req.om" 2>/dev/null; rc=$?
want $rc 0 "resolve requires as a name, arm b"
"$R" build "$CAT" "$T/lock.c" "$T/textok.compact.om" "$OUT/txt.map" > "$OUT/txt.om" 2> "$OUT/txt.acct"; rc=$?
want "$rc $(sed 's/.* //' "$OUT/txt.acct")" "0 om2_added=1" "resolve OM-2 words inside a text literal, arm c"
for c in A B; do
  eval omc=\$O$c
  "$omc" < "$OUT/req.om" > "$OUT/req.$c"; rc=$?; chmod +x "$OUT/req.$c"
  "$OUT/req.$c"; want "$rc $?" "0 12" "omc.$c requires as a name arm b exit"
  "$omc" < "$OUT/txt.om" > "$OUT/txt.$c"; rc=$?; chmod +x "$OUT/txt.$c"
  "$OUT/txt.$c"; want "$rc $?" "0 82" "omc.$c text literal arm c exit"
done

# 6. wrong constant in a catalog body: refused with the old lock; re-locked it builds and the
#    table comparison and irequiv catch it. Every step must succeed and produce bytes, and the table
#    must detect some rows but not all (all rows wrong means a broken program, not a wrong constant).
NC=$T/neg/wrongk.cat.om
"$R" build "$NC" "$T/lock.b" "$T/f4/item76666.compact.om" "$OUT/wk.map" > "$OUT/wk.om" 2> "$OUT/wk.err"; rc=$?
want "$rc $(cut -d' ' -f1-4 "$OUT/wk.err")" "11 RESOLVE_IDENTITY line 1 lock" "wrong constant, old lock: refused"
"$R" ids "$NC" > "$OUT/wk.lock"; rc=$?
want "$rc $(grep -c . "$OUT/wk.lock")" "0 1" "wrong constant: ids re-lock"
{ cat "$T/drive.om"; head -n -3 "$T/f4/item76666.compact.om"; cat "$T/dmain.om"; } > "$OUT/wk.src"
"$R" build "$NC" "$OUT/wk.lock" "$OUT/wk.src" "$OUT/wk.map" > "$OUT/wk.om" 2>/dev/null; rc=$?
want $rc 0 "wrong constant re-locked: resolve"
"$OA" < "$OUT/wk.om" > "$OUT/wk.bin"; rc=$?; chmod +x "$OUT/wk.bin"
want "$rc $([ -s "$OUT/wk.om" ] && [ -s "$OUT/wk.bin" ] && echo nonempty)" "0 nonempty" "wrong constant re-locked: omc"
set -- $(rows item76666 "$OUT/wk.bin" f4 2>/dev/null)
if [ "$1" -gt 0 ] && [ "$2" -gt 0 ] && [ "$2" -lt "$1" ]; then ok "wrong constant re-locked: table detects $2 of $1 rows"
else bad "wrong constant re-locked: table detects $2 of $1 rows (want 0 < detected < rows)"; fi

# 7. irequiv on the resolved ir unit (arm B only: inline is OM-2 and ir units are not).
"$OA" < "$root/seed/equiv/irequiv.om" > "$OUT/irequiv"; chmod +x "$OUT/irequiv"
"$R" build "$CAT" "$T/lock.b" "$T/ir.compact.om" "$OUT/ir.map" > "$OUT/ir.om" 2>/dev/null; rc=$?
want $rc 0 "resolve ir unit"
for c in A B; do
  eval omc=\$O$c
  "$omc" < "$OUT/ir.om" > "$OUT/ir.$c.ir"
  for p in "ha hb" "la lb" "ma mb"; do
    "$OUT/irequiv" check $p < "$OUT/ir.$c.ir" > "$OUT/ir.$c.out"; rc=$?
    want $rc 0 "irequiv omc.$c $p: $(cut -d' ' -f1-8 "$OUT/ir.$c.out")"
  done
done
"$R" build "$NC" "$OUT/wk.lock" "$T/ir.compact.om" "$OUT/irw.map" > "$OUT/irw.om" 2>/dev/null
"$OA" < "$OUT/irw.om" > "$OUT/irw.ir"
"$OUT/irequiv" check ha hb < "$OUT/irw.ir" > "$OUT/irw.out"; rc=$?
want $rc 1 "irequiv wrong constant: $(cut -d' ' -f1-2 "$OUT/irw.out")"

# 8. refusals: exit status, first four words of the diagnostic, empty stdout, no map file.
"$R" ids "$T/neg/cycle.cat.om" > "$OUT/cycle.lock"
"$R" ids "$T/neg/self.cat.om" > "$OUT/self.lock"
"$R" ids "$T/neg/notadm.cat.om" > "$OUT/notadm.lock"
"$R" ids "$T/two.cat.om" | awk '$1 == "add_twice"' > "$OUT/needs.lock"
for i in $(seq 33); do cat "$T/lock.b"; done > "$OUT/cap.lock"
{ for i in $(seq 1200); do echo "note padding line padding line padding line padding line padding"; done
  cat "$T/f4/item76666.compact.om"; } > "$OUT/big.om"
P=$T/f4/item76666.compact.om
N=$T/neg
neg() { # name want-status want-prefix catalog lock compact
  rm -f "$OUT/neg.map"
  "$R" build "$4" "$5" "$6" "$OUT/neg.map" > "$OUT/neg.out" 2> "$OUT/neg.$1.err"; rc=$?
  got="$rc $(cut -d' ' -f1-4 "$OUT/neg.$1.err")"
  if [ "$got" = "$2 $3" ] && [ ! -s "$OUT/neg.out" ] && [ ! -e "$OUT/neg.map" ]; then
    ok "refuse $1: $(cat "$OUT/neg.$1.err")"; else bad "refuse $1: $got"; fi
}
neg wrong_identity 11 "RESOLVE_IDENTITY line 1 lock" "$CAT" "$N/badid.lock" "$P"
neg collision_global 12 "RESOLVE_COLLISION line 1 compact" "$CAT" "$T/lock.b" "$N/global.compact.om"
neg collision_userfn 12 "RESOLVE_COLLISION line 1 compact" "$CAT" "$T/lock.b" "$N/userdef.compact.om"
neg collision_binding 12 "RESOLVE_COLLISION line 2 compact" "$CAT" "$T/lock.b" "$N/binding.compact.om"
neg not_admitted 16 "RESOLVE_NOT_ADMITTED line 3 catalog" "$N/notadm.cat.om" "$OUT/notadm.lock" "$P"
neg capacity_lock 15 "RESOLVE_CAPACITY line 33 lock" "$CAT" "$OUT/cap.lock" "$P"
neg capacity_compact 15 "RESOLVE_CAPACITY line 0 compact" "$CAT" "$T/lock.b" "$OUT/big.om"
neg cycle 14 "RESOLVE_CYCLE line 2 catalog" "$N/cycle.cat.om" "$OUT/cycle.lock" "$P"
neg cycle_self 14 "RESOLVE_CYCLE line 3 catalog" "$N/self.cat.om" "$OUT/self.lock" "$P"
neg unknown 10 "RESOLVE_UNKNOWN line 1 lock" "$CAT" "$N/unknown.lock" "$P"
neg unlocked_compact 18 "RESOLVE_UNLOCKED line 2 compact" "$CAT" "$N/empty.lock" "$P"
neg unlocked_dep 18 "RESOLVE_UNLOCKED line 17 catalog" "$T/two.cat.om" "$OUT/needs.lock" "$P"
neg duplicate_catalog 13 "RESOLVE_DUPLICATE line 17 catalog" "$N/dup.cat.om" "$T/lock.b" "$P"
neg duplicate_lock 13 "RESOLVE_DUPLICATE line 2 lock" "$CAT" "$N/dup.lock" "$P"
neg syntax_lock 19 "RESOLVE_SYNTAX line 1 lock" "$CAT" "$N/syntax.lock" "$P"
neg mode_ir_inline 17 "RESOLVE_MODE line 1 compact" "$CAT" "$T/lock.c" "$N/ir.compact.om"
neg mode_fmt 17 "RESOLVE_MODE line 1 compact" "$CAT" "$T/lock.b" "$N/fmt.compact.om"
neg mode_target 17 "RESOLVE_MODE line 1 compact" "$CAT" "$T/lock.c" "$N/target.compact.om"
neg mode_reserved 17 "RESOLVE_MODE line 2 compact" "$CAT" "$T/lock.c" "$N/reserved.compact.om"
neg mode_requires 17 "RESOLVE_MODE line 2 compact" "$CAT" "$T/lock.c" "$T/requires.compact.om"
neg mode_ensures 17 "RESOLVE_MODE line 2 compact" "$CAT" "$T/lock.c" "$N/ensures.compact.om"
neg mode_invariant 17 "RESOLVE_MODE line 4 compact" "$CAT" "$T/lock.c" "$N/invariant.compact.om"
neg mode_hex 17 "RESOLVE_MODE line 5 compact" "$CAT" "$T/lock.c" "$N/hex.compact.om"
neg mode_star 17 "RESOLVE_MODE line 4 compact" "$CAT" "$T/lock.c" "$N/star.compact.om"
neg mode_check 17 "RESOLVE_MODE line 1 compact" "$CAT" "$T/lock.c" "$N/check.compact.om"
"$R" build "$CAT" "$T/lock.b" > /dev/null 2> "$OUT/usage.err"; rc=$?
want "$rc $(cut -d' ' -f1 "$OUT/usage.err")" "2 RESOLVE_USAGE" "refuse usage"
# a diagnostic longer than its 1000-byte cap is cut and still ends with its line feed (one line).
{ head -c 3000 /dev/zero | tr '\0' a; echo " $id"; } > "$OUT/long.lock"
"$R" build "$CAT" "$OUT/long.lock" "$P" "$OUT/long.map" > /dev/null 2> "$OUT/long.err"; rc=$?
want "$rc $(wc -l < "$OUT/long.err") $(tail -c 1 "$OUT/long.err" | od -An -tu1 | tr -d ' ')" "10 1 10" "long diagnostic is one line"

if [ $fails -eq 0 ]; then echo "GATE PASS checks=$checks"; exit 0; fi
echo "GATE FAIL $fails of $checks"
exit 1
