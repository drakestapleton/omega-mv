#!/bin/sh
# seed/helix/ollm_factory/build-synth-gb10.sh
# Build zero-CUDA pure seeded OM-2 SM121 Observational-Equivalence Synthesizer (`om_synth_gb10`)
# by composing train/omega-llm/native/gpu/{context,vector,launch}.om + om_synth_gb10.om.
# Usage:
#   sh seed/helix/ollm_factory/build-synth-gb10.sh OMC_A [OMC_B] OUT_BIN
set -eu
OMC_A=${1:?usage: build-synth-gb10.sh OMC_A [OMC_B] OUT_BIN}
if [ $# -ge 3 ]; then
  OMC_B=$2
  OUT_BIN=$3
else
  OMC_B=$1
  OUT_BIN=$2
fi

OUT_DIR=$(dirname "$OUT_BIN")
mkdir -p "$OUT_DIR"
SRC="$OUT_DIR/om_synth_gb10_combined.om"

cat si/directives/om2.om \
    train/omega-llm/native/gpu/context.om \
    train/omega-llm/native/gpu/vector.om \
    train/omega-llm/native/gpu/launch.om \
    seed/helix/ollm_factory/om_synth_gb10.om > "$SRC"

"$OMC_A" < "$SRC" > "${OUT_BIN}.A"
if [ "$OMC_A" != "$OMC_B" ]; then
  "$OMC_B" < "$SRC" > "${OUT_BIN}.B"
  cmp -s "${OUT_BIN}.A" "${OUT_BIN}.B" || { echo "FAIL: om_synth_gb10 diverged across strands" >&2; exit 1; }
  rm -f "${OUT_BIN}.B"
fi
mv "${OUT_BIN}.A" "$OUT_BIN"
chmod +x "$OUT_BIN"
rm -f "$SRC"

if command -v ldd >/dev/null 2>&1; then
  out=$(ldd "$OUT_BIN" 2>&1 || true)
  case "$out" in
    *"not a dynamic executable"*|*"statically linked"*) ;;
    *) echo "FAIL: $OUT_BIN is not a static zero-CUDA ELF: $out" >&2; exit 1 ;;
  esac
fi

printf 'PASS om_synth_gb10 static ELF (%s, %s bytes)\n' \
  "$(sha256sum "$OUT_BIN" | cut -d' ' -f1)" \
  "$(wc -c < "$OUT_BIN" | tr -d ' ')"
