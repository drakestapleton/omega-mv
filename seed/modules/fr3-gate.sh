#!/bin/sh
# FR-3: import by source digest. Eight units, from a clean repo root.
# The driver is Omega (seed/ng/sha256.om + seed/modules/driver.om), built by seed/out/omc.
# Every unit prints PASS <unit>; a failed unit prints FAIL <unit> and what it saw, then exits 1.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
omc=$R/seed/out/omc
sha256sum -c seed/out/omc.sha256 >/dev/null 2>&1 || fail "setup: sha256sum -c seed/out/omc.sha256 does not match"
side=$(awk 'NR==1 { print $1; exit }' seed/out/omc.sha256)
have=$(sha256sum "$omc" | awk '{ print $1 }')
[ "$side" = "$have" ] || fail "setup: sidecar $side, compiler $have"
work=$(mktemp -d "${TMPDIR:-/tmp}/omc-fr3.XXXXXX")
trap 'rm -rf "$work"' EXIT
store=$work/store
mkdir "$store"
{ printf 'om2\n'; cat seed/ng/sha256.om seed/modules/driver.om; } > "$work/ommod.om"
"$omc" < "$work/ommod.om" > "$work/ommod" 2> "$work/ommod.err" || fail "setup: driver does not compile: $(cat "$work/ommod.err")"
chmod +x "$work/ommod"
run() { # unit out err cmd...: run cmd, set rc, never stop on its exit status
  u=$1 o=$2 e=$3
  shift 3
  set +e
  "$@" > "$o" 2> "$e"
  rc=$?
  set -e
}

u=correct-digest
leaf=$R/seed/modules/fr3/leaf.om
lh=$(sha256sum "$leaf" | awk '{ print $1 }')
run $u "$work/leaf.out" "$work/leaf.err" "$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$leaf" "$lh"
[ "$rc" = 0 ] || fail "$u: leaf build rc=$rc: $(cat "$work/leaf.err")"
la=$(awk '{ print $NF }' "$work/leaf.out")
[ "$(printf '%s' "$la" | wc -c)" = 64 ] || fail "$u: leaf build printed no artifact digest: $(cat "$work/leaf.out")"
root=$work/root.om
printf 'om2\nimport dep %s answer\nexport fn answer to int\nret dep\nend\n' "$lh" > "$root"
rh=$(sha256sum "$root" | awk '{ print $1 }')
run $u "$work/root.out" "$work/root.err" "$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$root" "$rh"
[ "$rc" = 0 ] || fail "$u: root build rc=$rc: $(cat "$work/root.err")"
ra=$(awk '{ print $NF }' "$work/root.out")
link() {
  run $u "$work/link.out" "$work/link.err" "$work/ommod" link "$store" "$have" debug aarch64-linux "$rh" "$ra" program answer "$1"
  [ "$rc" = 0 ] || fail "$u: link $1 rc=$rc: $(cat "$work/link.err")"
}
link "$work/out1"
link "$work/out2"
run $u "$work/run.out" "$work/run.err" "$work/out1"
[ "$rc" = 7 ] || fail "$u: linked program exit $rc, wanted 7"
printf 'PASS correct-digest exit 7\n'

u=reproducible
s1=$(sha256sum "$work/out1" | awk '{ print $1 }')
s2=$(sha256sum "$work/out2" | awk '{ print $1 }')
[ "$s1" = "$s2" ] || fail "$u: two links differ, $s1 and $s2"
cmp -s "$work/out1" "$work/out2" || fail "$u: two links differ in bytes"
printf 'PASS reproducible %s\n' "$s1"

u=one-byte-change
chmod u+w "$store/$la.mod"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); b=bytearray(p.read_bytes());
assert len(b)>176; b[176]^=1; p.write_bytes(b)' "$store/$la.mod" || fail "$u: could not flip a byte in $la.mod"
run $u "$work/bad.out" "$work/bad.err" "$work/ommod" link "$store" "$have" debug aarch64-linux "$rh" "$ra" program answer "$work/out3"
[ "$rc" = 24 ] || fail "$u: link rc=$rc, wanted 24: $(cat "$work/bad.err")"
grep -qx 'ommod: digest-mismatch' "$work/bad.err" || fail "$u: stderr lacks 'ommod: digest-mismatch': $(cat "$work/bad.err")"
[ ! -e "$work/out3" ] || fail "$u: refused link left an output file"
printf 'PASS one-byte-change refused digest-mismatch\n'

u=missing-digest
miss=$R/seed/modules/fr3/missing.om
mh=$(sha256sum "$miss" | awk '{ print $1 }')
before=$(ls -A "$store")
run $u "$work/miss.out" "$work/miss.err" "$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$miss" "$mh"
[ "$rc" = 34 ] || fail "$u: build rc=$rc, wanted 34: $(cat "$work/miss.err")"
grep -qx 'ommod: digest-missing' "$work/miss.err" || fail "$u: stderr lacks 'ommod: digest-missing': $(cat "$work/miss.err")"
! grep -q BUILT "$work/miss.out" || fail "$u: refused build printed BUILT"
after=$(ls -A "$store")
[ "$before" = "$after" ] || fail "$u: refused build changed the store"
printf 'PASS missing-digest refused digest-missing\n'

u=source-digest-mismatch
bad=0000000000000000000000000000000000000000000000000000000000000000
before=$(ls -A "$store")
run $u "$work/sd.out" "$work/sd.err" "$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$leaf" "$bad"
[ "$rc" = 24 ] || fail "$u: build rc=$rc, wanted 24: $(cat "$work/sd.err")"
grep -qx 'ommod: digest-mismatch' "$work/sd.err" || fail "$u: stderr lacks 'ommod: digest-mismatch': $(cat "$work/sd.err")"
[ "$before" = "$(ls -A "$store")" ] || fail "$u: refused build changed the store"
printf 'PASS source-digest-mismatch refused digest-mismatch\n'

u=compiler-digest-mismatch
run $u "$work/cd.out" "$work/cd.err" "$work/ommod" build "$omc" "$bad" debug aarch64-linux "$store" "$leaf" "$lh"
[ "$rc" = 24 ] || fail "$u: build rc=$rc, wanted 24: $(cat "$work/cd.err")"
grep -qx 'ommod: digest-mismatch' "$work/cd.err" || fail "$u: stderr lacks 'ommod: digest-mismatch': $(cat "$work/cd.err")"
[ "$before" = "$(ls -A "$store")" ] || fail "$u: refused build changed the store"
printf 'PASS compiler-digest-mismatch refused digest-mismatch\n'

u=wrong-length
printf 'x' >> "$store/$la.mod"
run $u "$work/wl.out" "$work/wl.err" "$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$leaf" "$lh"
[ "$rc" = 24 ] || fail "$u: build rc=$rc, wanted 24: $(cat "$work/wl.err")"
grep -qx 'ommod: digest-mismatch' "$work/wl.err" || fail "$u: stderr lacks 'ommod: digest-mismatch': $(cat "$work/wl.err")"
printf 'PASS wrong-length refused digest-mismatch\n'

u=artifact-absent
rm -f "$store/$la.mod"
run $u "$work/aa.out" "$work/aa.err" "$work/ommod" link "$store" "$have" debug aarch64-linux "$rh" "$ra" program answer "$work/out4"
[ "$rc" = 34 ] || fail "$u: link rc=$rc, wanted 34: $(cat "$work/aa.err")"
grep -qx 'ommod: digest-missing' "$work/aa.err" || fail "$u: stderr lacks 'ommod: digest-missing': $(cat "$work/aa.err")"
[ ! -e "$work/out4" ] || fail "$u: refused link left an output file"
printf 'PASS artifact-absent refused digest-missing\n'
