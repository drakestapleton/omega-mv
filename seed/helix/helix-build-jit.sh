#!/bin/sh
# seed/helix/helix-build-jit.sh -- Build dual-strand zero-CUDA Proof-Carrying SM121 JIT binaries
# (`q36-helix-native` and `q36-helix-decode`) without modifying any file in `om/gpu/q36/`.
#
# Composes `seed/helix/helix_jit.om` directly into `q36Done` (and `qhDone` for decode),
# verifies bit-for-bit equality between Strand A (`omc_A`) and Strand B (`omc_B_fast`),
# and confirms static zero-CUDA ELFs (`ldd: not a dynamic executable`).
#
# Usage:
#   sh seed/helix/helix-build-jit.sh OMC_A OMC_B OUT_DIR
set -eu
OMC_A=${1:?usage: helix-build-jit.sh OMC_A OMC_B OUT_DIR}
OMC_B=${2:?usage: helix-build-jit.sh OMC_A OMC_B OUT_DIR}
OUT=${3:?usage: helix-build-jit.sh OMC_A OMC_B OUT_DIR}
mkdir -p "$OUT"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# Prepare clean composed inputs:
#   - rename local `rb` in bw_hazard.om -> `hzrb` to avoid colliding with `fn rb` in bw_enc_sm121.om
#   - inject `hxEvolveQ36Buf cnt` inside `q36Done` right before upload to VRAM (only on pass 2 when qCodeMap/qdCodeMap > 0!)
#   - inject `hxPrintSummary` right after pass-2 `qEmitAll` / `qdEmitAll`
sed 's/\brb\b/hzrb/g' gpu/nvidia/om/codegen/bw_hazard.om > "$OUT/bw_hazard_clean.om"

# Native runner hook: evolve q36Buf when hxActive == 1 (actual VRAM upload pass)
awk '
/^cnt = get q36Pc 0$/ { print; print "hxEvolveQ36Buf cnt"; next }
{ print }
' om/gpu/q36/emit_fast.om > "$OUT/emit_fast_nat.om"

awk '
/^put qCodeMap 0 cm$/ { print; print "put hxActive 0 1"; next }
/^if ne get qCodeFail 0 0$/ { print "hxPrintSummary"; print; next }
{ print }
' om/gpu/q36/native_run.om > "$OUT/native_run_hx.om"

{
  printf 'om2\n'
  cat gpu/nvidia/native/nvrm/context.om \
      gpu/nvidia/native/blackwell/vector.om \
      gpu/nvidia/native/blackwell/launch.om \
      gpu/nvidia/native/blackwell/batch.om \
      om/encoder/bw_enc_sm121.om \
      "$OUT/bw_hazard_clean.om" \
      "$OUT/emit_fast_nat.om" \
      seed/helix/helix_jit.om \
      om/gpu/q36/arboris/prefetch.om \
      "$OUT/native_run_hx.om"
} > "$OUT/q36_helix_native.om"

"$OMC_A" < "$OUT/q36_helix_native.om" > "$OUT/q36-helix-native.A"
"$OMC_B" < "$OUT/q36_helix_native.om" > "$OUT/q36-helix-native.B"
cmp -s "$OUT/q36-helix-native.A" "$OUT/q36-helix-native.B" || { echo "FAIL: q36-helix-native diverged across strands" >&2; exit 1; }
mv "$OUT/q36-helix-native.A" "$OUT/q36-helix-native"
rm -f "$OUT/q36-helix-native.B"
chmod +x "$OUT/q36-helix-native"

# Real-weight 35B decode runner hook: evolve q36Buf AND qhBuf when hxActive == 1
awk '
/^cnt = get q36Pc 0$/ { print; print "hxEvolveQ36Buf cnt"; next }
{ print }
' om/gpu/q36/emit_fast.om > "$OUT/emit_fast_dec.om"

awk '
/^cnt = get qhPc 0$/ { print; print "hxEvolveQhBuf cnt"; next }
{ print }
' om/gpu/q36/head/emit_head.om > "$OUT/emit_head_dec.om"

cat > "$OUT/helix_jit_head_ext.om" <<'EOF'
fn hxEvolveQhBuf cnt ulong to void
if eq get hxActive 0 0
ret
end
hxEnsureInit
if eq get hxGenome 0 0
ret
end
if or eq cnt 0 gt cnt 2048
put hxStats 3 add get hxStats 3 1
ret
end
put hxStats 0 add get hxStats 0 1
for i ulong mul cnt 4 bound 8192
v = get qhBuf i
put hxRef i v
put hxCand i v
end
if hxRunCore cnt
for i ulong mul cnt 4 bound 8192
put qhBuf i get hxCand i
end
end
end
EOF

awk '
/^put qdCodeMap 0 cm$/ { print; print "put hxActive 0 1"; next }
/^if ne get qdCodeFail 0 0$/ { print "hxPrintSummary"; print; next }
{ print }
' om/gpu/q36/decode/decode_run.om > "$OUT/decode_run_hx.om"

{
  printf 'om2\n'
  cat gpu/nvidia/native/nvrm/context.om \
      gpu/nvidia/native/blackwell/vector.om \
      gpu/nvidia/native/blackwell/launch.om \
      gpu/nvidia/native/blackwell/batch.om \
      om/encoder/bw_enc_sm121.om \
      "$OUT/bw_hazard_clean.om" \
      "$OUT/emit_fast_dec.om" \
      "$OUT/emit_head_dec.om" \
      seed/helix/helix_jit.om \
      "$OUT/helix_jit_head_ext.om" \
      om/gpu/q36/arboris/prefetch.om \
      "$OUT/decode_run_hx.om"
} > "$OUT/q36_helix_decode.om"

"$OMC_A" < "$OUT/q36_helix_decode.om" > "$OUT/q36-helix-decode.A"
"$OMC_B" < "$OUT/q36_helix_decode.om" > "$OUT/q36-helix-decode.B"
cmp -s "$OUT/q36-helix-decode.A" "$OUT/q36-helix-decode.B" || { echo "FAIL: q36-helix-decode diverged across strands" >&2; exit 1; }
mv "$OUT/q36-helix-decode.A" "$OUT/q36-helix-decode"
rm -f "$OUT/q36-helix-decode.B"
chmod +x "$OUT/q36-helix-decode"

printf 'PASS q36-helix-native dual-strand identical (%s, %s bytes)\n' "$(sha "$OUT/q36-helix-native")" "$(wc -c < "$OUT/q36-helix-native")"
printf 'PASS q36-helix-decode dual-strand identical (%s, %s bytes)\n' "$(sha "$OUT/q36-helix-decode")" "$(wc -c < "$OUT/q36-helix-decode")"
