#!/bin/sh
# A compiler and a sidecar that name each other, but are not the compiler the
# seed source builds, must turn the birth red. The birth must leave that pair
# on disk. Restores the committed pair before it returns.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
OMC=$ROOT/seed/out/omc
SIDE=$ROOT/seed/out/omc.sha256
[ -f "$OMC" ] && [ -f "$SIDE" ] || { echo 'FAIL pin-plant: seed/out/omc or its sidecar is missing'; exit 1; }
T=$(mktemp -d)
cp "$OMC" "$T/omc"
cp "$SIDE" "$T/side"
restore() {
    cp "$T/omc" "$OMC"
    cp "$T/side" "$SIDE"
    chmod +x "$OMC"
    rm -rf "$T"
}
trap restore EXIT
printf 'planted-compiler\n' > "$OMC"
chmod +x "$OMC"
sum=$(sha256sum "$OMC" | awk 'NR==1 { print $1; exit }')
printf '%s  seed/out/omc\n' "$sum" > "$SIDE"
set +e
nice -n 19 sh "$ROOT/seed/omega-from-seed.sh" > "$T/log" 2>&1
rc=$?
set -e
real=$(awk 'NR==1 { print $1; exit }' "$T/side")
now=$(awk 'NR==1 { print $1; exit }' "$SIDE")
if [ "$rc" = 0 ]; then
    echo 'FAIL pin-plant: a compiler that is not the seed fixpoint was accepted'
    exit 1
fi
if [ "$now" != "$sum" ]; then
    echo "FAIL pin-plant: birth rewrote the sidecar from $sum to $now"
    exit 1
fi
grep -q "$sum" "$T/log" || { echo 'FAIL pin-plant: birth did not name the planted compiler'; exit 1; }
grep -q "$real" "$T/log" || { echo 'FAIL pin-plant: birth did not name the seed fixpoint'; exit 1; }
grep -q 'sidecar left unchanged' "$T/log" || { echo 'FAIL pin-plant: birth did not refuse to rewrite the sidecar'; exit 1; }
echo "ok   planted compiler $sum refused; sidecar still names it, not $real"
