#!/bin/sh
# Host-only admission controls, not backend or hardware qualification.
# Each unchanged gate is copied with the repository's canonical pin to private scratch.
# A wrong executable must be refused before any dependency, compiler or backend runs.
# Exit 0: all eight exact mismatch controls caught; 1: wrong behavior; 3: setup incomplete.
set -eu
cd "$(dirname "$0")/../../../.."
ROOT=$(pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/omega-seed-pins.XXXXXXXX")
trap 'rm -rf "$W"' EXIT HUP INT TERM
mkdir -p "$W/tree/seed/out"
cp seed/out/omc.sha256 "$W/tree/seed/out/omc.sha256"
pin=$(cut -d ' ' -f 1 seed/out/omc.sha256)
case "$pin" in *[!0-9a-f]*) pin= ;; esac
[ ${#pin} -eq 64 ] || { echo 'SEEDPINS SETUP canonical pin malformed'; exit 3; }
cat > "$W/wrong-omc" <<'WRONG'
#!/bin/sh
printf 'executed\n' > "$SEEDPINS_MARKER"
exit 97
WRONG
chmod +x "$W/wrong-omc"
got=$(sha256sum "$W/wrong-omc" | cut -d ' ' -f 1)
[ "$got" != "$pin" ] || { echo 'SEEDPINS SETUP decoy equals canonical compiler'; exit 3; }
export SEEDPINS_MARKER="$W/executed"
pass=0
fail=0
setup=0
for gate in seed/equiv/gate-irequiv.sh seed/json/tests/gate-json.sh \
    seed/nki/gate-irnki.sh seed/spirv/gate-irspirv.sh seed/spirv/gate-vkspirv.sh \
    seed/stablehlo/gate-irstablehlo.sh seed/tensix/gate-tensix.sh seed/wasm/gate-irwasm.sh; do
    mkdir -p "$W/tree/$(dirname "$gate")"
    cp "$ROOT/$gate" "$W/tree/$gate"
    tag=$(basename "$gate" .sh)
    prefix=
    [ "$tag" = gate-json ] && prefix='JSONGATE '
    printf '%sNOT_RUN %s: compiler %s sha256 %s differs from pin %s\n' \
        "$prefix" "$tag" "$W/wrong-omc" "$got" "$pin" > "$W/expected"
    rc=0
    OMC="$W/wrong-omc" sh "$W/tree/$gate" > "$W/output" 2>&1 || rc=$?
    if [ -e "$SEEDPINS_MARKER" ]; then
        echo "SEEDPINS FAIL $gate: decoy compiler executed (exit $rc)"
        fail=$((fail + 1))
        rm -f "$SEEDPINS_MARKER"
    elif [ "$rc" -eq 3 ] && cmp -s "$W/expected" "$W/output"; then
        echo "SEEDPINS PASS $gate: exact mismatch exit 3, compiler not executed"
        pass=$((pass + 1))
    elif grep -Eq '^(NOT_RUN|JSONGATE NOT_RUN|SKIP)' "$W/output"; then
        echo "SEEDPINS SETUP $gate: mismatch guard not reached (exit $rc)"
        cat "$W/output"
        setup=$((setup + 1))
    else
        echo "SEEDPINS FAIL $gate: expected exact mismatch exit 3, got exit $rc"
        cat "$W/output"
        fail=$((fail + 1))
    fi
done
printf 'SEEDPINS controls=8 pass=%s fail=%s setup=%s\n' "$pass" "$fail" "$setup"
[ "$fail" -eq 0 ] || exit 1
[ "$setup" -eq 0 ] || exit 3
[ "$pass" -eq 8 ]
