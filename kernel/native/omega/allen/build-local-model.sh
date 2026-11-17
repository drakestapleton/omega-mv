#!/bin/sh
# Opt-in firmware build. Does not change the default Allen firmware.
# Usage: [OMEGA_COMPILER=/pinned/omc] sh build-local-model.sh AIEN_TRAIN OUT.EFI (default: omega-mv seed/out/omc)
set -eu
[ "$#" = 2 ] || { echo 'usage: build-local-model.sh AIEN_TRAIN OUT.EFI' >&2; exit 64; }
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
train=$1/native/omegallm
out=$2
compiler=${OMEGA_COMPILER:-"$here/../../../../seed/out/omc"}
# Pin: omega-mv's own seed/out/omc.sha256 (kernel/ is folded into omega-mv, Drake 2026-11-17); before, omc 3ad9f10f.
pin=$(cut -c1-64 "$here/../../../../seed/out/omc.sha256")
[ "$(sha256sum "$compiler" | cut -d' ' -f1)" = "$pin" ] || { echo 'compiler pin mismatch' >&2; exit 65; }
[ ! -e "$out" ] || { echo 'fresh output required' >&2; exit 73; }
mkdir -p "$(dirname "$out")"
unit=$out.om
{
 printf '%s\n' 'target x86efi'
 cat "$here/base.om" "$here/runtime.om"
 for f in math data epool model adam ckpt bpe cli; do cat "$train/$f.om"; done
 # Only the platform entry point and output hook are replaced. Model math is unmodified.
 sed -e 's/^fn main to int$/fn ollm_file_main to int/' \
     -e 's/^fn oflush to void$/fn ollm_file_flush to void/' "$train/eio.om"
 cat "$train/nogpu.om" "$here/local-model.om"
} > "$unit"
dup=$(grep -E '^(fn|global|const|text|struct) ' "$unit" | awk '{print $2}' | sort | uniq -d)
[ -z "$dup" ] || { echo "duplicate declarations: $dup" >&2; exit 65; }
rc=0
"$compiler" < "$unit" > "$out.tmp" 2> "$out.err" || rc=$?
if [ "$rc" != 0 ]; then
 cat "$out.err" >&2
 rm -f "$out.tmp"
 exit "$rc"
fi
[ "$(head -c 2 "$out.tmp")" = MZ ] || { echo 'not an EFI image' >&2; rm -f "$out.tmp"; exit 65; }
mv "$out.tmp" "$out"
sha256sum "$compiler" "$unit" "$out"
