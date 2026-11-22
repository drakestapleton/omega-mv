#!/bin/sh
# seed/helix/ollm_factory/build-ollm-jit.sh
# Build dual-strand zero-CUDA Omega LLM CPU (`ollm`) and Proof-Carrying SM121 Evolutionary
# Training JIT (`ollm-helix-gb10`) binaries WITHOUT modifying any file under `train/omega-llm/native/`.
#
# Usage:
#   sh seed/helix/ollm_factory/build-ollm-jit.sh OMC_A OMC_B OUT_DIR
set -eu
OMC_A=${1:?usage: build-ollm-jit.sh OMC_A OMC_B OUT_DIR}
OMC_B=${2:?usage: build-ollm-jit.sh OMC_A OMC_B OUT_DIR}
OUT=${3:?usage: build-ollm-jit.sh OMC_A OMC_B OUT_DIR}
mkdir -p "$OUT"

sha() { sha256sum "$1" | cut -d' ' -f1; }

COMMON="si/directives/om2.om \
  train/omega-llm/native/net/http.om \
  train/omega-llm/native/net/json.om \
  train/omega-llm/native/net/jsonw.om \
  train/omega-llm/native/math.om \
  train/omega-llm/native/data.om \
  train/omega-llm/native/lpool.om \
  train/omega-llm/native/model.om \
  train/omega-llm/native/adam.om \
  train/omega-llm/native/ckpt.om \
  train/omega-llm/native/bpe.om \
  train/omega-llm/native/spec.om \
  train/omega-llm/native/cli.om \
  train/omega-llm/native/lio.om \
  train/omega-llm/native/serve.om"

# 1. Dual-strand CPU `ollm` (bit-for-bit identical across Strand A & Strand B)
cat $COMMON train/omega-llm/native/nogpu.om > "$OUT/ollm_cpu.om"
"$OMC_A" < "$OUT/ollm_cpu.om" > "$OUT/ollm.A"
"$OMC_B" < "$OUT/ollm_cpu.om" > "$OUT/ollm.B"
cmp -s "$OUT/ollm.A" "$OUT/ollm.B" || { echo "FAIL: ollm diverged across strands" >&2; exit 1; }
mv "$OUT/ollm.A" "$OUT/ollm"
rm -f "$OUT/ollm.B"
chmod +x "$OUT/ollm"
printf 'PASS ollm dual-strand identical (%s, %s bytes)\n' "$(sha "$OUT/ollm")" "$(wc -c < "$OUT/ollm" | tr -d ' ')"

# 2. Prepare clean non-invasive hooks for `ollm-helix-gb10`:
#    - strip `hxEvolveQ36Buf` from `seed/helix/helix_jit.om` so `helix_jit_core.om` has zero q36 references
#    - hook `otjRecSlot id` at the end of `gkemitb`, `gkemit`, and `grall` slot loop
#    - hook `otjEvolveAll` right before `mapwrite get gbmem 4 0 gkcode 0 1048576` in `gkopen`
awk '/^fn hxEvolveQ36Buf/{exit} {print}' seed/helix/helix_jit.om | sed 's/\bow\b/hxow/g' > "$OUT/helix_jit_core.om"

awk '
/^put gkthr id 128$/ { print "otjRecSlot id"; print; next }
/^put gkthr id 64$/  { print "otjRecSlot id"; print; next }
/^r = mapwrite get gbmem 4 0 gkcode 0 1048576$/ { print "otjEvolveAll"; print; next }
{ print }
' train/omega-llm/native/gpu/gk.om > "$OUT/gk_hx.om"

awk '
/^put gkthr id 64$/ { print "otjRecSlot id"; print; next }
{ print }
' train/omega-llm/native/gpu/gr.om > "$OUT/gr_hx.om"

# Verify hooks actually fired cleanly (fail-closed!)
grep -q "otjEvolveAll" "$OUT/gk_hx.om" || { echo "FAIL: gkopen hook did not match" >&2; exit 1; }
grep -q "otjRecSlot id" "$OUT/gr_hx.om" || { echo "FAIL: grall hook did not match" >&2; exit 1; }

# 3. Compose `ollm-helix-gb10`: place `bw_hazard.om` + `helix_jit_core.om` + `ollm_train_jit.om`
#    right after `gk.om`'s global declarations? No: `otjRecSlot` reads `gkat` and `otjEvolveAll`
#    reads `gkcode`, so put `gk_globals`? Better: `gk_hx.om` calls `otjRecSlot`/`otjEvolveAll`,
#    so declare `gkcode` & `gkat`? Wait: in OM-2 functions can be called before definition!
#    Only globals must be declared before use! Placing `ollm_train_jit.om` AFTER `gk_hx.om`
#    guarantees `gkcode` and `gkat` are already declared AND OM-2 allows forward calls to `otjRecSlot`/`otjEvolveAll`!
cat $COMMON \
    train/omega-llm/native/gpu/context.om \
    train/omega-llm/native/gpu/vector.om \
    train/omega-llm/native/gpu/launch.om \
    train/omega-llm/native/gpu/batch.om \
    gpu/nvidia/om/codegen/bw_hazard.om \
    "$OUT/helix_jit_core.om" \
    "$OUT/gk_hx.om" \
    seed/helix/ollm_factory/ollm_train_jit.om \
    "$OUT/gr_hx.om" \
    train/omega-llm/native/gpu/gb.om \
    train/omega-llm/native/gpu/gg.om > "$OUT/ollm_helix_gb10.om"

"$OMC_A" < "$OUT/ollm_helix_gb10.om" > "$OUT/ollm-helix-gb10.A"
"$OMC_B" < "$OUT/ollm_helix_gb10.om" > "$OUT/ollm-helix-gb10.B"
cmp -s "$OUT/ollm-helix-gb10.A" "$OUT/ollm-helix-gb10.B" || { echo "FAIL: ollm-helix-gb10 diverged across strands" >&2; exit 1; }
mv "$OUT/ollm-helix-gb10.A" "$OUT/ollm-helix-gb10"
rm -f "$OUT/ollm-helix-gb10.B"
chmod +x "$OUT/ollm-helix-gb10"
printf 'PASS ollm-helix-gb10 dual-strand identical (%s, %s bytes)\n' "$(sha "$OUT/ollm-helix-gb10")" "$(wc -c < "$OUT/ollm-helix-gb10" | tr -d ' ')"

# Confirm zero dynamic libraries on both ELFs
if command -v ldd >/dev/null 2>&1; then
  for bin in "$OUT/ollm" "$OUT/ollm-helix-gb10"; do
    out=$(ldd "$bin" 2>&1 || true)
    case "$out" in
      *"not a dynamic executable"*|*"statically linked"*) ;;
      *) echo "FAIL: $bin is not a static zero-CUDA ELF: $out" >&2; exit 1 ;;
    esac
  done
fi
