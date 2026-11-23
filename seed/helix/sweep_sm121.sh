#!/bin/sh
# seed/helix/sweep_sm121.sh -- Offline 46-Kernel Production SM121 Verification Sweep (ZERO GPU).
#
# Sweeps ALL production SM121 SASS kernels across three independent kernel families:
#   - 31 emit_fast kernels (modes 97..127, including mode 127 qBf16Gemv1R + patched ops 65..70)
#   -  5 emit_head kernels (modes h97..h101, all 5 Qwen 3.6 35B lm_head/ZOS kernels)
#   - 10 om_synth_gb10 kernels (op_0..op_9, covering ops 2064/565/2101/549/937 + 64-bit ISETP)
# Total: 46 real SM121 kernels (plus vecadd.bin in helix-from-seeds.sh = 47 total).
#
# Every kernel runs through:
#   Strand B Predator -> Strand A Monk (CFG scoreboard + rawFloor=6 + BB-leader + I2FP nm==29)
#   and the 12-Attack Immune System (Antibodies #1-#16).
#
# Usage:
#   sh seed/helix/sweep_sm121.sh [OMC_A] [OMC_B] [MONK_BIN] [PRED_BIN] [IMMUNE_BIN] [OUT_DIR]
set -eu
export CUDA_VISIBLE_DEVICES=""
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"

OMC_A=${1:-build/cold-regrowth/omc_A}
OMC_B=${2:-build/cold-regrowth/omc_B_fast}
MONK=${3:-build/cold-regrowth/monk_check}
PRED=${4:-build/cold-regrowth/arboris_predator}
IMMUNE=${5:-build/cold-regrowth/immune}
OUT=${6:-build/sm121-sweep}

[ -x "$OMC_A" ]  || OMC_A=seed/out/omc
[ -x "$OMC_B" ]  || OMC_B="$OMC_A"

bad() { printf 'SM121_SWEEP FAIL: %s\n' "$*" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/q36" "$OUT/synth" "$OUT/work"

# Build Monk / Predator / Immune if caller did not prebuild them
if [ ! -x "$MONK" ]; then
  { printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/om/codegen/bw_hazard.om seed/helix/hx_dec_ext.om seed/helix/monk_check.om; } | "$OMC_A" > "$OUT/monk_check"
  chmod +x "$OUT/monk_check"
  MONK="$OUT/monk_check"
fi
if [ ! -x "$PRED" ]; then
  { printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/om/codegen/bw_hazard.om seed/helix/hx_dec_ext.om seed/helix/arboris_predator.om; } | "$OMC_B" > "$OUT/arboris_predator"
  chmod +x "$OUT/arboris_predator"
  PRED="$OUT/arboris_predator"
fi
if [ ! -x "$IMMUNE" ]; then
  { printf 'om2\n'; cat seed/ng/sha256.om gpu/nvidia/om/codegen/bw_hazard.om seed/helix/hx_dec_ext.om seed/helix/immune.om; } | "$OMC_A" > "$OUT/immune"
  chmod +x "$OUT/immune"
  IMMUNE="$OUT/immune"
fi

printf '=== [SWEEP 1/3] EXTRACT ALL 36 q36 KERNELS (31 emit_fast + 5 emit_head, incl. mode 127 DEL fix) ===\n'
{ printf 'om2\n'; cat om/encoder/bw_enc_sm121.om om/gpu/q36/emit_fast.om om/gpu/q36/head/emit_head.om seed/helix/extract_q36_kernels.om; } | "$OMC_A" > "$OUT/extract_q36_A"
{ printf 'om2\n'; cat om/encoder/bw_enc_sm121.om om/gpu/q36/emit_fast.om om/gpu/q36/head/emit_head.om seed/helix/extract_q36_kernels.om; } | "$OMC_B" > "$OUT/extract_q36_B"
cmp -s "$OUT/extract_q36_A" "$OUT/extract_q36_B" || bad "extract_q36 diverged across strands"
mv "$OUT/extract_q36_A" "$OUT/extract_q36"
rm -f "$OUT/extract_q36_B"
chmod +x "$OUT/extract_q36"

# Explicit single-mode numeric check on mode 127 (qBf16Gemv1R, ASCII DEL bug fix)
"$OUT/extract_q36" 127 "$OUT/work/mode127_check.bin" >/dev/null
"$OUT/extract_q36" --all "$OUT/q36" | tail -n 5

q36_cnt=0
for k in "$OUT"/q36/fast_*.bin "$OUT"/q36/head_*.bin; do
  [ -f "$k" ] && q36_cnt=$((q36_cnt + 1))
done
[ "$q36_cnt" -eq 36 ] || bad "Expected 36 q36 kernels, got $q36_cnt"
cmp -s "$OUT/work/mode127_check.bin" "$OUT/q36/fast_127.bin" || bad "Numeric mode 127 differs from --all fast_127.bin"

printf '\n=== [SWEEP 2/3] EXTRACT ALL 10 om_synth_gb10 KERNELS (OFFLINE DUMP, ZERO GPU) ===\n'
sh seed/helix/ollm_factory/build-synth-gb10.sh "$OMC_A" "$OMC_B" "$OUT/om_synth_gb10"
"$OUT/om_synth_gb10" dump "$OUT/synth"

synth_cnt=0
for k in "$OUT"/synth/op_*.bin; do
  [ -f "$k" ] && synth_cnt=$((synth_cnt + 1))
done
[ "$synth_cnt" -eq 10 ] || bad "Expected 10 om_synth_gb10 kernels, got $synth_cnt"

printf '\n=== [SWEEP 3/3] VERIFY ALL 46 SM121 KERNELS (PREDATOR -> MONK -> 12-ATTACK IMMUNE) ===\n'
total=0
total_insns=0
total_swaps=0
total_saved=0
imm_pass=0

for kbin in "$OUT"/q36/fast_*.bin "$OUT"/q36/head_*.bin "$OUT"/synth/op_*.bin; do
  kbase=$(basename "$kbin" .bin)
  cand="$OUT/work/${kbase}.cand.bin"
  cert="$OUT/work/${kbase}.cert"
  pout=$("$PRED" "$kbin" "$cand" "$cert") || bad "Predator failed on $kbase"
  mout=$("$MONK" "$kbin" "$cand" "$cert") || bad "Monk rejected $kbase: $pout"
  iout=$("$IMMUNE" "$MONK" "$kbin" "$cand" "$cert" "$OUT/work/im_${kbase}") || bad "Immune breach on $kbase"
  printf '%s\n' "$iout" | grep -q 'IMMUNE PASS legit=PASS attacks=12 killed=12 antibodies=12/12' || bad "Immune did not kill 12/12 on $kbase"
  insns=$(printf '%s\n' "$mout" | sed -n 's/.*insns=\([0-9]*\).*/\1/p')
  swaps=$(printf '%s\n' "$pout" | sed -n 's/.*swaps=\([0-9]*\).*/\1/p')
  saved=$(printf '%s\n' "$pout" | sed -n 's/.*stall_saved=\([0-9]*\).*/\1/p')
  total=$((total + 1))
  total_insns=$((total_insns + ${insns:-0}))
  total_swaps=$((total_swaps + ${swaps:-0}))
  total_saved=$((total_saved + ${saved:-0}))
  imm_pass=$((imm_pass + 1))
done

[ "$total" -eq 46 ] || bad "Expected 46 verified kernels, got $total"
[ "$imm_pass" -eq 46 ] || bad "Expected 46/46 immune passes, got $imm_pass"

printf 'SM121_SWEEP PASS kernels=%d (emit_fast=31 emit_head=5 om_synth_gb10=10) total_insns=%d swaps=%d stall_saved=%d immune=12/12x%d\n' \
  "$total" "$total_insns" "$total_swaps" "$total_saved" "$imm_pass"
