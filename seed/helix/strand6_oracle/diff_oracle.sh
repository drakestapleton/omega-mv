#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/helix/strand6_oracle/diff_oracle.sh
# Strand F ("The Differential Oracle") runner:
#   1. Builds ngrand, ngcheck, ngrun, ngas, ng, irequiv, and diff_oracle via OMC
#      into build/strand6_oracle (and attempts ng self-hosted ng_b if supported).
#   2. Runs diff_oracle across >= 50 random ΩIR seeds (default 64) across 3 engines
#      (ngrun interpreter, ng @ng a64 unopt, ng/ng_b @ng opt -> @ng a64) AND
#      15 source run-pairs (omc_A vs ng_B vs ngrun), verifying 0 divergences.
#   3. Runs diff_oracle --neg-control to verify ngrand shrink minimizes a planted
#      divergence and replays byte-identically from its .tape.
#   4. Compiles quant_equiv.unit.om to OSC IR v1 and runs exhaustive irequiv
#      equivalence checks (including a true 24-bit domain=16777216 proof) plus
#      1-bit mutant negative controls (must exit 1).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"

[ "$(uname -m)" = aarch64 ] || {
    echo "SKIP strand6_oracle: needs aarch64 Linux host (omc emits AArch64 ELF)"
    exit 0
}

OMC="${OMC:-seed/out/omc}"
START_SEED="${START_SEED:-1}"
SEED_COUNT="${SEED_COUNT:-64}"
NEG_SEED="${NEG_SEED:-6}"
B="${OUT_DIR:-build/strand6_oracle}"

[ -x "$OMC" ] || { echo "FAIL strand6_oracle: OMC not executable: $OMC" >&2; exit 2; }
mkdir -p "$B"

compile_om() {
    out=$1
    shift
    cat "$@" | "$OMC" > "$out.tmp" 2> "$out.err" || {
        echo "FAIL compile $out:" >&2
        cat "$out.err" >&2
        rm -f "$out.tmp"
        exit 1
    }
    chmod +x "$out.tmp"
    mv "$out.tmp" "$out"
}

t_start=$(date +%s)

# 1. Build all pure-Omega oracle tools under build/strand6_oracle
compile_om "$B/ngrand"      seed/ng/src/ir.om seed/ng/ngrand.om
compile_om "$B/ngcheck"     seed/ng/sha256.om seed/ng/ngcheck.om
compile_om "$B/ngrun"       seed/ng/src/ir.om seed/ng/ngrun.om
compile_om "$B/ngas"        seed/ng/ngtxt.om seed/ng/ngas.om
compile_om "$B/ng"          seed/ng/src/ir.om seed/ng/src/front.om seed/ng/src/opt.om seed/ng/src/a64.om seed/ng/src/main.om
compile_om "$B/irequiv"     seed/equiv/irequiv.om
compile_om "$B/diff_oracle" seed/helix/strand6_oracle/diff_oracle.om

# Optional cross-compiler check: build ng_b via ng itself (@ng front-ir -> @ng a64) if supported.
rm -f "$B/ng_b"
if { printf '@ng front-ir\n'; cat seed/ng/src/ir.om seed/ng/src/front.om seed/ng/src/opt.om seed/ng/src/a64.om seed/ng/src/main.om; } \
    | "$B/ng" > "$B/ng_b.ir" 2> "$B/ng_b.fir.err" \
    && "$B/ngcheck" < "$B/ng_b.ir" > "$B/ng_b.chk" 2>/dev/null \
    && { printf '@ng a64\n'; cat "$B/ng_b.ir"; } | "$B/ng" > "$B/ng_b.tmp" 2> "$B/ng_b.a64.err"; then
    chmod +x "$B/ng_b.tmp"
    mv "$B/ng_b.tmp" "$B/ng_b"
else
    rm -f "$B/ng_b.tmp" "$B/ng_b.ir"
fi

# 2. Differential oracle: >=50 random seeds across 3 engines + 15 source run-pairs (omc_A vs ng_B vs ngrun)
diff_out=$("$B/diff_oracle" run "$B" "$OMC" "$START_SEED" "$SEED_COUNT")
echo "$diff_out"
case "$diff_out" in
    *"DIFF_ORACLE PASS"*) ;;
    *) echo "FAIL strand6_oracle: diff_oracle did not pass" >&2; exit 1 ;;
esac

# 3. Shrinking negative control: planted divergence triggers ngrand shrink + exact .tape replay
neg_out=$("$B/diff_oracle" --neg-control "$B" "$NEG_SEED")
echo "$neg_out"
case "$neg_out" in
    *"NEG_CONTROL PASS"*) ;;
    *) echo "FAIL strand6_oracle: negative control did not pass" >&2; exit 1 ;;
esac

# 4. Exhaustive OSC IR v1 quantization & bit-unpack equivalence (including 24-bit domain=16777216)
{ printf 'ir\n'; cat seed/helix/strand6_oracle/quant_equiv.unit.om; } | "$OMC" > "$B/quant_equiv.ir" 2> "$B/quant_equiv.err" || {
    echo "FAIL strand6_oracle: compile quant_equiv.unit.om to IR" >&2
    cat "$B/quant_equiv.err" >&2
    exit 1
}

check_equiv() {
    want=$1; sub=$2; fa=$3; fb=$4
    set +e
    out=$("$B/irequiv" check "$fa" "$fb" < "$B/quant_equiv.ir" 2>&1)
    st=$?
    set -e
    echo "$out"
    [ "$st" = "$want" ] || { echo "FAIL irequiv $fa vs $fb: status $st, want $want" >&2; exit 1; }
    case "$out" in
        *"$sub"*) ;;
        *) echo "FAIL irequiv $fa vs $fb: missing '$sub'" >&2; exit 1 ;;
    esac
}

check_equiv 0 "EQUIV PASS a=w4_sref b=w4_sfast params=uchar domain=256 checked=256 differing=0" w4_sref w4_sfast
check_equiv 0 "EQUIV PASS a=w4_dqref b=w4_dqfast params=uchar,byte domain=65536 checked=65536 differing=0" w4_dqref w4_dqfast
check_equiv 0 "EQUIV PASS a=q8_clref b=q8_clfast params=short domain=65536 checked=65536 differing=0" q8_clref q8_clfast
check_equiv 0 "EQUIV PASS a=fp8_uref b=fp8_ufast params=uchar domain=256 checked=256 differing=0" fp8_uref fp8_ufast
check_equiv 0 "EQUIV PASS a=pk24_ref b=pk24_fast params=ushort,uchar domain=16777216 checked=16777216 differing=0" pk24_ref pk24_fast

# 1-bit mutant negative controls (must exit 1 with exact counterexample)
check_equiv 1 "EQUIV FAIL a=w4_sref b=w4_smut" w4_sref w4_smut
check_equiv 1 "EQUIV FAIL a=q8_clref b=q8_clmut params=short domain=65536 checked=65536 differing=1 first=short:127 a_result=value:byte:127 b_result=value:byte:126" q8_clref q8_clmut

t_end=$(date +%s)
elapsed=$((t_end - t_start))

echo "STRAND6_ORACLE PASS seeds=$SEED_COUNT pairs=15 neg_control=PASS equiv_pairs=5 equiv_24bit=16777216 mutants_caught=2 elapsed_s=$elapsed"
exit 0
