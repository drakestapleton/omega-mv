#!/bin/sh
# External assembly/build orchestration. Submission behavior executes in native Omega.
# Reuses build-fw.sh's module order and the existing showbench hardware-boundary convention.
set -eu
[ "$#" = 1 ] || { echo 'usage: test-look-submit.sh FRESH_OUTPUT_DIR' >&2; exit 64; }
a=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
out=$1
mkdir "$out"
out=$(CDPATH= cd -- "$out" && pwd)
unit=$out/submit.om
{
 for f in platform.om base.om vendor/sha256-core.om font-data.om font.om look-paint.om look-skydata.om look-sky.om \
  look-night.om look-mind.om look-home.om surface.om github.om http.om net.om tls-crypto.om vendor/cert-sha384.om \
  vendor/cert-p256.om tls-p384.om vendor/cert-root.om tls-cert.om tls.om session.om repository-screen.om runtime.om \
  code.om courier.om scheduler.om memory.om intent.om reply.om context.om application.om look-chat.om look-stat.om; do
  cat "$a/$f"
 done
 # Hardware-only boundaries are unused by these input tests. The actual handlers and app remain intact.
 printf '\nfn efms to ulong\nret 1000\nend\nfn inmatch to bool\nret false\nend\nfn ininstall now ulong to void\nret\nend\n'
 sed -e 's/^st = efi 3 arg Efa mul mul y0 w 4 n$/st = ulong 0/' \
     -e 's/^st = efi 3 arg Efb mul mul sub y0 hh w 4 n$/st = ulong 0/' "$a/look-show.om"
 cat "$a/tests/look-submit.om"
} > "$unit"
"$a/build-one.sh" "$unit" "$out/submit"
"$out/submit"
echo 'LOOK_SUBMIT: PASS; offline feedback, preserved input, no job, local stats, empty Enter'
