#!/bin/sh
# Host gate for native AArch64 macOS target (target a64macos) in seed/omc/omc.om.
# Usage: sh seed/macos/gate-macos.sh [OMC_MACOS_BIN]
set -eu
omc=${1:-seed/out/omc-macos}
[ -x "$omc" ] || { echo "NOT_RUN: $omc not executable" >&2; exit 3; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/gate-macos.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

run_case() {
    name=$1
    exp_rc=$2
    exp_out=$3
    cat > "$tmp/$name.om"
    "$omc" < "$tmp/$name.om" > "$tmp/$name"
    chmod 755 "$tmp/$name"
    codesign -s - -f "$tmp/$name" >/dev/null 2>&1
    set +e
    out=$("$tmp/$name")
    rc=$?
    set -e
    if [ "$rc" != "$exp_rc" ] || [ "$out" != "$exp_out" ]; then
        echo "FAIL $name: got rc=$rc out='$out', expected rc=$exp_rc out='$exp_out'" >&2
        exit 1
    fi
    echo "PASS $name"
}

run_case exit42 42 "" <<'OM'
target a64macos
fn main to int
x = int 20
y = int 22
ret add x y
end
OM

run_case stdout 0 "ok-mac" <<'OM'
target a64macos
text m "ok-mac\n"
fn main to int
w = write 1 m 0 len m
ret 0
end
OM

run_case loop_sum 45 "" <<'OM'
target a64macos
fn main to int
s = int 0
for i ulong 10
s = add s int i
end
ret s
end
OM

run_case om2_view 5 "" <<'OM'
target a64macos
om2
text m "abcde"
fn f s view uchar * to int
ret int len s
end
fn main to int
ret f m
end
OM

# Negative control: untyped addition must be refused with error 11
set +e
printf 'target a64macos\nfn main to int\nret add 1 2\nend\n' | "$omc" > "$tmp/bad" 2> "$tmp/bad.err"
bad_rc=$?
set -e
if [ "$bad_rc" = 0 ]; then
    echo "FAIL neg_bad_type: unexpectedly compiled" >&2
    exit 1
fi
echo "PASS neg_bad_type (rc=$bad_rc)"

# Self-rebuild fixpoint: omc-macos builds gen1, gen1 builds gen2, gen1 == gen2
{ printf 'target a64macos\n'; cat seed/omc/omc.om; } > "$tmp/omc-mac.om"
"$omc" < "$tmp/omc-mac.om" > "$tmp/omc1.unsigned"
cp "$tmp/omc1.unsigned" "$tmp/omc1"
chmod 755 "$tmp/omc1"
codesign -s - -f "$tmp/omc1" >/dev/null 2>&1
"$tmp/omc1" < "$tmp/omc-mac.om" > "$tmp/omc2"
cmp -s "$tmp/omc1.unsigned" "$tmp/omc2" || { echo "FAIL fixpoint: gen1 != gen2" >&2; exit 1; }
h=$(shasum -a 256 "$tmp/omc1.unsigned" | awk '{print $1}')
echo "PASS fixpoint sha256=$h"
echo "GATE-MACOS PASS"
