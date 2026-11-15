#!/bin/sh
# The compiler pin is the first field of seed/out/omc.sha256.
# seed/omega-from-seed.sh writes that file from the compiler it just built.
# Source this file, set OMC_PIN_ROOT to the repository root, then call omc_pin_load.
# OMC_PIN_FILE overrides the sidecar path (the disagree control uses a forged file).
# omc_pin_load sets OMC_PIN and returns 0 when it is 64 lowercase hex digits.
# omc_pin_match BINARY LABEL returns 0 when the binary matches, 1 when it disagrees
# (a FAIL line naming both digests), 3 when the binary or the sidecar is missing.

omc_pin_load() {
    _root=${OMC_PIN_ROOT:-.}
    _file=${OMC_PIN_FILE:-$_root/seed/out/omc.sha256}
    OMC_PIN=$(awk 'NR==1 { print $1; exit }' "$_file" 2>/dev/null || true)
    case $OMC_PIN in
        *[!0-9a-f]*|'') OMC_PIN=; return 1 ;;
    esac
    if [ ${#OMC_PIN} -ne 64 ]; then
        OMC_PIN=
        return 1
    fi
    return 0
}

omc_pin_match() {
    _bin=$1
    _label=$2
    if [ ! -f "$_bin" ]; then
        echo "NOT_RUN $_label: no omc at $_bin"
        return 3
    fi
    if ! omc_pin_load; then
        echo "NOT_RUN $_label: seed/out/omc.sha256 has no compiler pin"
        return 3
    fi
    _have=$(sha256sum < "$_bin" | cut -c1-64)
    if [ "$_have" != "$OMC_PIN" ]; then
        echo "FAIL $_label: omc sha256 $_have disagrees with seed/out/omc.sha256 pin $OMC_PIN"
        return 1
    fi
    return 0
}
