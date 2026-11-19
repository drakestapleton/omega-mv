#!/bin/sh
# Host-only bit-exact sm_121 SASS parity check:
# Pure-.om pipeline (cg_dec -> bw_alloc -> bw_enc_sm121) vs libomega_gpu.a C oracle
# (src/omega_blackwell_codegen_dec.c + src/omega_blackwell_codegen.c -DCUDAPP_MIGRATION_PENDING_C_ENCODER).
# Zero Spark GPU usage, zero CUDA, zero NVRM.
set -eu

OMC="${OMC:-/Users/drakestapleton/.local/bin/omc}"
if [ ! -x "$OMC" ]; then
    OMC="./seed/out/omc"
fi
TMP="${TMPDIR:-/tmp}/q38-sass-parity-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    { printf 'target a64macos\n'
      cat gpu/nvidia/om/codegen/cg_dec_emit.om \
          gpu/nvidia/om/codegen/cg_dec.om \
          gpu/driver/tests/q38_sass_emit.om; } | "$OMC" > "$TMP/om_emit"
    { printf 'target a64macos\n'
      cat gpu/nvidia/om/components/bw_alloc.om \
          gpu/nvidia/om/encoder/bw_enc_sm121.om \
          gpu/driver/tests/q38_sass_encode.om; } | "$OMC" > "$TMP/om_enc"
else
    cat gpu/nvidia/om/codegen/cg_dec_emit.om \
        gpu/nvidia/om/codegen/cg_dec.om \
        gpu/driver/tests/q38_sass_emit.om | "$OMC" > "$TMP/om_emit"
    cat gpu/nvidia/om/components/bw_alloc.om \
        gpu/nvidia/om/encoder/bw_enc_sm121.om \
        gpu/driver/tests/q38_sass_encode.om | "$OMC" > "$TMP/om_enc"
fi
chmod +x "$TMP/om_emit" "$TMP/om_enc"
"$TMP/om_emit" | "$TMP/om_enc" > "$TMP/om.bin"

cat > "$TMP/c_oracle.c" <<'EOF'
#include "omega_blackwell_codegen.h"
#include "omega_blackwell_codegen_dec.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Unused symbols referenced by non-called functions in omega_blackwell_codegen.c */
int omega_blackwell_bind_matmul_realization(const OmegaMatMulSpec *s, const OmegaBlackwellKernel *k, OmegaBlackwellRealizationIdentity *id) { (void)s; (void)k; (void)id; return -1; }
int omega_blackwell_codegen_matmul(const OmegaMatMulSpec *s, OmegaBlackwellKernel *k) { (void)s; (void)k; return -1; }
void omega_blackwell_kernel_free(OmegaBlackwellKernel *k) { (void)k; }
int omega_matmul_spec_init(OmegaMatMulSpec *s, uint32_t m, uint32_t k, uint32_t n, OmegaMatMulPrecision p) { (void)s; (void)m; (void)k; (void)n; (void)p; return -1; }
void sha256_hash(const void *d, size_t n, uint8_t out[32]) { (void)d; (void)n; for (int i = 0; i < 32; i++) out[i] = 0; }

static void emit_one(const OmegaDecSpec *s) {
    BlackwellIRProgram *p = calloc(1, sizeof *p);
    if (!p || omega_blackwell_codegen_dec_prog(s, p) != 0) { fprintf(stderr, "codegen fail\n"); exit(1); }
    uint8_t buf[16384];
    size_t nb = 0;
    if (omega_bw_encode_program(p, buf, sizeof buf, &nb) != 0 || nb == 0) { fprintf(stderr, "encode fail\n"); exit(2); }
    uint32_t len = (uint32_t)nb;
    if (fwrite(&len, 4, 1, stdout) != 1 || fwrite(buf, 1, nb, stdout) != nb) { fprintf(stderr, "write fail\n"); exit(3); }
    free(p);
}

int main(void) {
    const OmegaDecSpec specs[7] = {
        { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_NORM, .width = 5120 },
        { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM, .width = 5120 },
        { .kind = OMEGA_DEC_SWIGLU, .width = 17408 },
        { .kind = OMEGA_DEC_GATHER, .width = 14336, .stride = 14336 },
        { .kind = OMEGA_DEC_GATE },
        { .kind = OMEGA_DEC_ARGMAX, .mode = 0 },
        { .kind = OMEGA_DEC_ARGMAX, .mode = 1 },
    };
    for (int i = 0; i < 7; i++) emit_one(&specs[i]);
    return 0;
}
EOF

cc -O2 -Isrc -DCUDAPP_MIGRATION_PENDING_C_ENCODER \
    "$TMP/c_oracle.c" \
    src/omega_blackwell_codegen.c \
    src/omega_blackwell_codegen_dec.c \
    -o "$TMP/c_oracle"
"$TMP/c_oracle" > "$TMP/c.bin"

cmp "$TMP/om.bin" "$TMP/c.bin"
OM_SHA="$(shasum -a 256 "$TMP/om.bin" | awk '{print $1}')"
C_SHA="$(shasum -a 256 "$TMP/c.bin" | awk '{print $1}')"
BYTES="$(wc -c < "$TMP/om.bin" | tr -d ' ')"
echo "PASS q38_sass_parity: 7/7 Qwen3.8-27B sm_121 kernels bit-exact (${BYTES} bytes, sha256=${OM_SHA})"
if [ "$OM_SHA" != "$C_SHA" ]; then
    echo "FAIL sha256 mismatch" >&2
    exit 1
fi
