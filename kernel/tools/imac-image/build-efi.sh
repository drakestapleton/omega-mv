#!/bin/sh
# Compose the firmware-hosted Allen sources in the order that compiles, add the `target x86efi`
# selector, and build the EFI application the boot image carries.
#
# The twenty sources are aienux `feat/allen-imac-competition` at `d4ffde3c`, a side branch: not on
# aienux main, so the fold into omega-mv did not bring them (kernel/MIGRATION.md, "Still outside
# omega-mv"). Fourteen equal native/omega/allen here; platform.om, surface.om, github.om, net.om,
# repository-screen.om and efi-main.om differ. Every source must have its d4ffde3c sha256 below,
# else this exits 3 (NOT_RUN) and builds nothing: other sources would publish a different EFI.
# ALLEN_SRC names a directory that holds them (default native/omega/allen, which does not).
#
#   OMEGA_COMPILER=<seed>/seed/out/omc ALLEN_SRC=<dir> sh build-efi.sh BOOTX64.EFI
#   OMEGA_COMPILER=<seed>/seed/out/omc ALLEN_SRC=<dir> sh build-efi.sh BOOTX64.EFI ff17a936...
#
# Second argument, if given, is the expected sha256; a difference exits 65 instead of passing.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
allen=${ALLEN_SRC:-"$root/native/omega/allen"}
compiler=${OMEGA_COMPILER:-}
# sha256 and path of each source at aienux d4ffde3c, in the order that compiles.
sources='a55fb803e78de4e960361a2be5bc891b82bf09109b6b155977a7da95f26031e4 platform.om
184f4270c72c4eca6a7afdd28b70a608f2e237980b12c8a7bfc2c7d2c3e625b9 base.om
992ec4a4957271b442740598136887a5c610effcd8ae9fb9480a006a4f181097 vendor/sha256-core.om
f8c559b449c81159172d3e08f185e1fcd9ac446ab594420d07221ca68ffa87d5 font-data.om
c62f5a799b601315e61b05283295810a084d1adcc06b5bddc34010f3b344b915 font.om
32d983b0d3a89f02128a34bb640ca149ca67d95cd4822c0400e91b455353af8a surface.om
826723b08cb2cf1e539486457003fdd703a5a1ba43ba70842fab8fa29e5c68ee github.om
1c6179be26afed40d04e4ec62305bbb58095e2a11202f9717a2252e5c8833946 http.om
420ae90da9acbe87540dd2ddcf35f2dc46d0afc70b88dca680824dff735df2b8 net.om
6214d2c4414a27b235125dbec79ae2fff7a14b75996108d0e3661621b317fbc6 tls-crypto.om
56dc31859c0c0ca0784944270d204fcf37466eb04afd1f7452237342b6c6ec8b vendor/cert-sha384.om
8630b74c2611ab4debf1e365f2b6fdefcb1762aa14543ca775a36fcf56cc03f4 vendor/cert-p256.om
0213aad67993b584521ff510058e99dc63605ec214a0a8132b7c64ae3a4e6ef4 tls-p384.om
794615367e5573bfebc17ee94a390a2efc662ce1086a7f80145f20e878f20cd6 vendor/cert-root.om
2c33ab254bed6094daf9498e43129371a181a5e235877aec21dfb856bd5f0154 tls-cert.om
def1491ac3c3e1f84c62080c61d5ab2c60eff9e7bf8060b5428dce66b5afe626 tls.om
8638dfe055838cdccf64905288d8dae00c2b0440357174b5533f310d6e0a4df2 session.om
bf2c8bee5987fd785846a05a83e80dca5a209a7b8e2744fc57256e5bf0fa70b7 repository-screen.om
46687280ccc430435c975116885ca123d43a375be71aef15e6a2602ca7276096 efi-main.om
2eb7dbac7f74cf0d9b8b490a45d7a35d76c498586de9d470ca5304ed191399a1 demo.om'
files=$(printf '%s\n' "$sources" | awk '{print $2}')

[ -n "$compiler" ] && [ -x "$compiler" ] || {
 echo 'OMEGA_COMPILER must name the seed compiler (seed/out/omc)' >&2
 exit 69
}

bad=''
for f in $files; do
 want=$(printf '%s\n' "$sources" | awk -v f="$f" '$2 == f {print $1}')
 if [ ! -f "$allen/$f" ]; then
  bad="$bad $f(missing)"
 elif [ "$(sha256sum < "$allen/$f" | cut -d' ' -f1)" != "$want" ]; then
  bad="$bad $f(differs)"
 fi
done
[ -z "$bad" ] || {
 echo "NOT_RUN: the Allen sources are aienux feat/allen-imac-competition d4ffde3c, outside omega-mv (kernel/MIGRATION.md); $allen does not hold them:$bad" >&2
 exit 3
}

out=${1:-BOOTX64.EFI}
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo 'fresh output required' >&2; exit 73; }
unit="${out}.om"
trap 'rm -f -- "$unit"' EXIT HUP INT TERM

{
 echo 'target x86efi'
 for f in $files; do
  cat "$allen/$f"
 done
} > "$unit"

# Compile to a scratch file and publish by link: a refused compile leaves nothing at $out, so a
# retry is not blocked by the fresh-output guard and no zero-byte EFI can be picked up by imac-image.
tmp="${out}.build.$$"
trap 'rm -f -- "$unit" "$tmp"' EXIT HUP INT TERM
if ! "$compiler" < "$unit" > "$tmp" || [ ! -s "$tmp" ]; then
 echo 'compile refused; nothing published' >&2
 exit 64
fi
got=$(sha256sum "$tmp" | cut -d' ' -f1)

want=${2:-}
if [ -n "$want" ] && [ "$got" != "$want" ]; then
 echo "expected $want; the sources or compiler differ" >&2
 exit 65
fi

ln -T -- "$tmp" "$out"
printf '%s  %s\n' "$got" "$out"
printf 'compiler %s\n' "$(sha256sum "$compiler" | cut -d' ' -f1)"
