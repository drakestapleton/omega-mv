#!/bin/sh
# External development orchestration. Every compiler invocation verifies its pin.
set -eu
[ "$#" = 2 ] || { echo 'usage: build-one.sh SOURCE OUTPUT' >&2; exit 64; }
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
compiler=${OMEGA_COMPILER:-"$root/../seed/out/omc"}
[ -f "$compiler" ] && [ -x "$compiler" ] || {
 echo 'pinned compiler missing; follow native/omega/allen/README.md' >&2
 exit 69
}
# Pin: omega-mv's own seed/out/omc, whose sha256 is in seed/out/omc.sha256 at the omega-mv root (kernel/ is folded
# into omega-mv, Drake 2026-11-17). Until then this was omega-mv b8bd1d03 (omc 2eeab514, branch fix/imac-net-L974-snp).
pin=$(head -n 1 "$root/../seed/out/omc.sha256" 2>/dev/null | cut -c1-64)
printf '%s\n' "$pin" | grep -qxE '[0-9a-f]{64}' || { echo "compiler pin refused: no sha256 in $root/../seed/out/omc.sha256" >&2; exit 65; }
[ "$(sha256sum "$compiler" | cut -d' ' -f1)" = "$pin" ] || {
 echo 'compiler digest differs from the qualified pin' >&2
 exit 65
}
[ ! -e "$2" ] && [ ! -L "$2" ] || { echo 'fresh output required' >&2; exit 73; }
temporary=$(mktemp "${2}.build.XXXXXX")
trap 'rm -f -- "$temporary" "$temporary.header" "$temporary.dynamic"' EXIT
trap 'exit 74' HUP INT TERM
"$compiler" < "$1" > "$temporary"
[ -s "$temporary" ]
readelf -h "$temporary" > "$temporary.header"
grep -q 'Machine:.*AArch64' "$temporary.header"
grep -q 'Type:.*EXEC' "$temporary.header"
readelf -l -d "$temporary" > "$temporary.dynamic"
if grep -Eq 'INTERP|NEEDED' "$temporary.dynamic"; then exit 65; fi
chmod 700 "$temporary"
# Atomic no-replace publication also refuses a link created during compilation.
ln -T -- "$temporary" "$2"
