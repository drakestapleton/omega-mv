/* omega_blackwell_codegen_tgemm.c: device-resident bf16 training GEMM (trainer lane E1, cut 1: NN, F32 overwrite).
 * Implementation lives in pure OM-2 (om/gpu/cg_tgemm.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_tgemm.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void tgemm_pack_spec(const OmegaTgemmSpec *s, uint64_t sp[10]) {
    sp[0] = s->k;
    sp[1] = s->n;
    sp[2] = s->rt;
    sp[3] = s->ct;
    sp[4] = s->warps;
    sp[5] = s->kc;
    sp[6] = s->aqn;
    sp[7] = s->layout;
    sp[8] = s->epi;
    sp[9] = (uint64_t)(int64_t)s->mutant;
}

int omega_tgemm_spec_ok(const OmegaTgemmSpec *s) {
    if (!s) return 0;
    uint64_t sp[10], ok = 0;
    tgemm_pack_spec(s, sp);
    if (omega2_cg_tgemm_spec_ok(&ok, sp, 10u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

uint32_t omega_tgemm_shared_bytes(const OmegaTgemmSpec *s) { return omega_tgemm_spec_ok(s) ? 2u * 16u * s->rt * s->kc * 2u : 0u; }
uint32_t omega_tgemm_span(const OmegaTgemmSpec *s) { return omega_tgemm_spec_ok(s) ? s->warps * 8u * s->ct : 0u; }
uint32_t omega_tgemm_bm(const OmegaTgemmSpec *s) { return omega_tgemm_spec_ok(s) ? 16u * s->rt : 0u; }

int omega_blackwell_codegen_tgemm_prog(const OmegaTgemmSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[10], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    tgemm_pack_spec(spec, sp);
    if (omega2_cg_tgemm_emit(&rc, sp, 10u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    if (omega_bw_ir_from_om(ins, meta, prog) != 0) return -1;
    if (prog->count > OMEGA_TGEMM_MAX_INSNS) { omega_bw_ir_init(prog); return -1; }
    uint32_t decl = omega_bw_gpr_declared(prog->regalloc.peak_gpr_usage);
    if (!omega_bw_gpr_declared_ok(decl, prog->regalloc.peak_gpr_usage) || decl > 128u) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return 0;
}
