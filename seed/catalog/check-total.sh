#!/bin/sh
# Targeted total-operation and resolver regression checks. Existing directories are never removed.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
OMC=${OMC:-$root/seed/out/omc}
OUT=${1:?usage: check-total.sh NEW_OUTPUT_DIRECTORY}
mkdir "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
{ sed 's/^export fn /fn /' om/sha256/sha256-om2.om; cat seed/catalog/resolve.om; } > "$OUT/full.om"
"$OMC" < "$OUT/full.om" > "$OUT/resolve"
chmod +x "$OUT/resolve"
R=$OUT/resolve
C=seed/catalog/total.om
"$R" ids "$C" > "$OUT/ids"
cmp "$OUT/ids" seed/catalog/tests/total.lock.b
for arm in b c; do
  "$R" build "$C" "seed/catalog/tests/total.lock.$arm" seed/catalog/tests/total-check.om "$OUT/$arm.map" > "$OUT/$arm.om" 2> "$OUT/$arm.acct"
  "$OMC" < "$OUT/$arm.om" > "$OUT/$arm.bin"
  chmod +x "$OUT/$arm.bin"
  "$OUT/$arm.bin"
  echo "PASS full-width total operation arm=$arm"
  "$R" build "$C" "seed/catalog/tests/total.lock.$arm" seed/catalog/tests/total-check.om "$OUT/$arm.map2" > "$OUT/$arm.om2" 2> "$OUT/$arm.acct2"
  cmp "$OUT/$arm.om" "$OUT/$arm.om2"
  cmp "$OUT/$arm.map" "$OUT/$arm.map2"
  cmp "$OUT/$arm.acct" "$OUT/$arm.acct2"
done
# A changed implementation with its identity deliberately refreshed must fail the independent oracle.
sed 's/s = add s long k/s = add s long 1/' "$C" > "$OUT/mut.cat"
"$R" ids "$OUT/mut.cat" > "$OUT/mut.lock"
"$R" build "$OUT/mut.cat" "$OUT/mut.lock" seed/catalog/tests/total-check.om "$OUT/mut.map" > "$OUT/mut.om" 2> "$OUT/mut.acct"
"$OMC" < "$OUT/mut.om" > "$OUT/mut.bin"
chmod +x "$OUT/mut.bin"
rc=0; "$OUT/mut.bin" || rc=$?
[ "$rc" = 1 ]
echo "PASS re-locked wrong constant detected"
# Signatures have variable card record lengths; free-form descriptions cannot be parsed as structure.
cat > "$OUT/cards.cat" <<'EOF'
fn one x int to int
ret x
end
note card two x int to int (this is description text)
fn two x int to int
ret x
end
note card arbitrary prose
note eg ret three 3
fn three x int to int
ret x
end
EOF
"$R" ids "$OUT/cards.cat" > "$OUT/cards.lock"
"$R" sig "$OUT/cards.cat" "$OUT/cards.lock" > "$OUT/sig"
printf 'one x int to int
two x int to int
three x int to int
' > "$OUT/expected.sig"
cmp "$OUT/sig" "$OUT/expected.sig"
echo "PASS signature-only records"
# Catalog identifiers cannot acquire different meanings in OM2.
for word in inline requires; do
  printf 'fn choose %s int to int
ret %s
end
' "$word" "$word" > "$OUT/kw.cat"
  "$R" ids "$OUT/kw.cat" > "$OUT/kw.lock"
  rc=0; "$R" card "$OUT/kw.cat" "$OUT/kw.lock" > "$OUT/kw.out" 2> "$OUT/kw.err" || rc=$?
  [ "$rc" = 16 ]; [ ! -s "$OUT/kw.out" ]
  grep 'RESOLVE_NOT_ADMITTED' "$OUT/kw.err"
done
# Full compiler is the syntax/type authority after lexical effect admission.
printf 'fn wrong to int
ret true
end
' > "$OUT/type.cat"
"$R" ids "$OUT/type.cat" > "$OUT/type.lock"
printf 'fn main to int
ret wrong
end
' > "$OUT/type.compact"
"$R" build "$OUT/type.cat" "$OUT/type.lock" "$OUT/type.compact" "$OUT/type.map" > "$OUT/type.om" 2> "$OUT/type.acct"
rc=0; "$OMC" < "$OUT/type.om" > "$OUT/type.bin" 2> "$OUT/type.err" || rc=$?
[ "$rc" = 7 ]; grep 'error 7' "$OUT/type.err"
echo "PASS compiler refuses ill-typed admitted tokens"
if [ -e /dev/full ]; then
  rc=0; "$R" build "$C" seed/catalog/tests/total.lock.b seed/catalog/tests/total-check.om /dev/full > "$OUT/io.out" 2> "$OUT/io.err" || rc=$?
  [ "$rc" = 3 ]; [ ! -s "$OUT/io.out" ]; grep 'RESOLVE_IO line 0 map write failed' "$OUT/io.err"
fi
# Explicit target and OM2 directives survive assembly byte for byte.
{ printf 'target x86linux\nom2\n'; cat seed/catalog/tests/total-check.om; } > "$OUT/target.compact"
"$R" build "$C" seed/catalog/tests/total.lock.c "$OUT/target.compact" "$OUT/target.map" > "$OUT/target.om" 2> "$OUT/target.acct"
head -n 2 "$OUT/target.compact" > "$OUT/target.head"
head -n 2 "$OUT/target.om" > "$OUT/unit.head"
cmp "$OUT/target.head" "$OUT/unit.head"
"$OMC" < "$OUT/target.om" > "$OUT/target.bin"
echo 'PASS target and OM2 directives preserved (cross-compiled, not executed)'
sha256sum "$OMC" seed/catalog/resolve.om "$C" "$R"
echo 'TOTAL GATE PASS'
