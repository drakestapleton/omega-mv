#!/bin/sh
# External development orchestration. Every compiler invocation verifies its pin.
set -eu
[ "$#" = 2 ] || { echo 'usage: build-one.sh SOURCE OUTPUT' >&2; exit 64; }
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
compiler=${OMEGA_COMPILER:-"$root/build/allen-toolchain/seed/out/omc"}
[ -f "$compiler" ] && [ -x "$compiler" ] || {
 echo 'pinned compiler missing; follow native/omega/allen/README.md' >&2
 exit 69
}
# Pin: omega-mv b8bd1d03 (local branch fix/imac-net-L974-snp on 81ab1900; compiler change pending its own review): register slots, live-slot calls, the efi 11 file word, const/bitcast, the site tables and the efi 8 link keep. AArch64 output is byte-identical to 81ab1900.
[ "$(sha256sum "$compiler" | cut -d' ' -f1)" = 2eeab5147deb8320cb1bc7f86a5f3de534955ff89f76be2832155348706e0164 ] || {
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
