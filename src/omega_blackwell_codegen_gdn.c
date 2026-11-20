/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * omega_blackwell_codegen_gdn.c: thin C ABI wrapper over the pure OM-2
 * Gated DeltaNet emitter in om/gpu/cg_gdn.om.
 */
#include "omega_blackwell_codegen_gdn.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"

int omega_gdn_shape(const OmegaGdnSpec *spec, OmegaGdnShape *s) {
    if (!spec || !s) return -1;
    uint32_t r = spec->ratio ? spec->ratio : 3u;
    if (r < 1u || r > 3u) return -1;
    s->r = r;
    s->vh = OMEGA_GDN_KEY_HEADS * r;
    s->vdim = s->vh * OMEGA_GDN_HEAD_DIM;
    s->conv = 2u * OMEGA_GDN_KEY_HEADS * OMEGA_GDN_HEAD_DIM + s->vdim;
    s->par_scal = s->conv * OMEGA_GDN_TAPS * 4u;
    s->par_norm = s->par_scal + s->vh * 8u;
    s->par_bytes = s->par_norm + OMEGA_GDN_HEAD_DIM * 4u;
    s->tail_bytes = s->vh * OMEGA_GDN_TAIL_HEAD_BYTES;
    s->state_bytes = spec->state_bf16 ? s->vh * (OMEGA_GDN_STATE_HEAD_BYTES / 2u) : s->vh * OMEGA_GDN_STATE_HEAD_BYTES;
    s->post_grid_y = s->vh / 8u;
    return 0;
}

static int gdn_emit_kind(uint64_t kind, const OmegaGdnSpec *spec, BlackwellIRProgram *prog, uint32_t gpr_limit) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    static uint64_t ins[8192], meta[512];
    uint64_t sp[8] = {
        kind,
        (uint64_t)(uint32_t)spec->mutant,
        (uint64_t)(uint32_t)spec->copy,
        (uint64_t)spec->ratio,
        (uint64_t)spec->state_bf16,
        0, 0, 0
    };
    uint64_t rc = 1;
    if (omega2_cg_gdn_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om_limit(ins, meta, prog, gpr_limit);
}

int omega_blackwell_codegen_gdn_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(0u, spec, prog, 0u);
}

int omega_gdn_prog_stats(const OmegaGdnSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_gdn_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}

int omega_blackwell_codegen_gdn_copy_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(1u, spec, prog, 0u);
}

int omega_blackwell_codegen_gdn_prep_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(2u, spec, prog, 0u);
}

int omega_blackwell_codegen_gdn_scan_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(3u, spec, prog, 0u);
}

int omega_blackwell_codegen_gdn_post_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(4u, spec, prog, 0u);
}

int omega_gdn_pf_prog_stats(unsigned kind, const OmegaGdnSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    int rc = kind == 0 ? omega_blackwell_codegen_gdn_prep_prog(spec, &prog)
           : kind == 1 ? omega_blackwell_codegen_gdn_scan_prog(spec, &prog)
           : kind == 2 ? omega_blackwell_codegen_gdn_post_prog(spec, &prog) : -1;
    if (rc != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}

int omega_blackwell_codegen_gdn_multi_prog(const OmegaGdnSpec *spec, BlackwellIRProgram *prog) {
    return gdn_emit_kind(5u, spec, prog, BW_PHYS_GPR_HW_LIMIT);
}

int omega_gdn_multi_prog_stats(const OmegaGdnSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_gdn_multi_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
