#!/bin/sh
# FR-3: import by source digest. Four units, from a clean repo root.
# The driver is Omega (seed/ng/sha256.om + seed/modules/driver.om), built by seed/out/omc.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
omc=$R/seed/out/omc
sha256sum -c seed/out/omc.sha256 >/dev/null
side=$(awk 'NR==1 { print $1; exit }' seed/out/omc.sha256)
have=$(sha256sum "$omc" | awk '{ print $1 }')
[ "$side" = "$have" ]
work=$(mktemp -d "${TMPDIR:-/tmp}/omc-fr3.XXXXXX")
trap 'rm -rf "$work"' EXIT
store=$work/store
mkdir "$store"
{ printf 'om2\n'; cat seed/ng/sha256.om seed/modules/driver.om; } > "$work/ommod.om"
"$omc" < "$work/ommod.om" > "$work/ommod"
chmod +x "$work/ommod"
leaf=$R/seed/modules/fr3/leaf.om
lh=$(sha256sum "$leaf" | awk '{ print $1 }')
bout=$("$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$leaf" "$lh")
la=$(printf '%s\n' "$bout" | awk '{ print $NF }')
[ "$(printf '%s' "$la" | wc -c)" = 64 ]
root=$work/root.om
printf 'om2\nimport dep %s answer\nexport fn answer to int\nret dep\nend\n' "$lh" > "$root"
rh=$(sha256sum "$root" | awk '{ print $1 }')
rout=$("$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$root" "$rh")
ra=$(printf '%s\n' "$rout" | awk '{ print $NF }')
link() {
  "$work/ommod" link "$store" "$have" debug aarch64-linux "$rh" "$ra" program answer "$1"
}
link "$work/out1"
link "$work/out2"
set +e
"$work/out1" >/dev/null
rc=$?
set -e
[ "$rc" = 7 ]
s1=$(sha256sum "$work/out1" | awk '{ print $1 }')
s2=$(sha256sum "$work/out2" | awk '{ print $1 }')
[ "$s1" = "$s2" ]
cmp -s "$work/out1" "$work/out2"
printf 'PASS correct-digest exit 7\n'
printf 'PASS reproducible %s\n' "$s1"
chmod u+w "$store/$la.mod"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); b=bytearray(p.read_bytes());
assert len(b)>176; b[176]^=1; p.write_bytes(b)' "$store/$la.mod"
set +e
"$work/ommod" link "$store" "$have" debug aarch64-linux "$rh" "$ra" program answer "$work/out3" >"$work/bad.out" 2>"$work/bad.err"
rc=$?
set -e
[ "$rc" = 24 ]
grep -qx 'ommod: digest-mismatch' "$work/bad.err"
[ ! -e "$work/out3" ]
printf 'PASS one-byte-change refused digest-mismatch\n'
miss=$R/seed/modules/fr3/missing.om
mh=$(sha256sum "$miss" | awk '{ print $1 }')
set +e
"$work/ommod" build "$omc" "$have" debug aarch64-linux "$store" "$miss" "$mh" >"$work/miss.out" 2>"$work/miss.err"
rc=$?
set -e
[ "$rc" = 34 ]
grep -qx 'ommod: digest-missing' "$work/miss.err"
if grep -q BUILT "$work/miss.out"; then
  printf 'FAIL missing-digest published a module\n' >&2
  exit 1
fi
printf 'PASS missing-digest refused digest-missing\n'
