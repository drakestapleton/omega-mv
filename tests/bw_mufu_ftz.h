/* bw_mufu_ftz.h: the GB10 MUFU unit's flush-to-zero rule, shared by every host model of it (omega #462).
 *
 * MUFU (the SASS EX2 / RCP / RSQ unit) flushes a subnormal input and a subnormal result to a sign-preserving zero.
 * Chip-observed on GB10:
 *  - RCP result flush: the SwiGLU reciprocal 1 / (2^t + 1) for t in (126, 128) came back as +-0 on all 101 of 101
 *    differing elements (evidence OWN30B-L1G-PFGEMM-SWIGLU-FTZ-df9bd9c4, gpu_pfgemm_test host red test).
 *  - EX2 result flush: ex2(x) for x stepped by 1/8 from -151 came back as 0 on all 191 of 191 inputs whose IEEE result
 *    is subnormal (evidence/GPU-MUFU-FTZ-ebbb089a-20261116, gpu_elementwise_test ex2_ftz_probe).
 *  - RSQ input flush, with sign: rsq of each of the 8 subnormal inputs of both signs came back as +-inf, where IEEE
 *    gives a finite value (positive) or NaN (negative) (same evidence, rsq_ftz_probe).
 * Not chip-observed: the EX2 / RCP input flush and the sign of a flushed EX2 result (EX2 of a subnormal is 1 either way
 * and its result is never negative), and the RSQ result flush (rsq of any finite f32 is at least 2^-64, never
 * subnormal). The model applies the same rule to them, PTX ISA 9.7.3.13 (rcp) and 9.7.3.21 (ex2) "flushes subnormal
 * inputs and results to sign-preserving zero" for the .ftz form, which is what the bare MUFU we emit is (the non-ftz PTX
 * variants are ptxas sequences around MUFU; NVIDIA publishes no SASS semantics). Limit: the chip's MUFU is approximate
 * (RCP 1 ulp, EX2 2 ulp), the model flushes a correctly rounded IEEE result, so right at the subnormal boundary the two
 * can disagree 0 versus nonzero.
 *
 * Users: tests/bw_warp_sim.h, bw_warp_sim_k.h, bw_warp_sim_pa.h, bw_warp_sim_tc.h (MUFU cases), the attention test's own
 * per-thread simulator (gpu_attention_test.c) and the pfgemm / qgemm SwiGLU host references. omega_numeric.c has its own
 * ftz() on the library side. Self-contained (no simulator state) so any of them can include it, in any order. */
#ifndef BW_MUFU_FTZ_H
#define BW_MUFU_FTZ_H

#include <math.h>
#include <stdint.h>
#include <string.h>

/* A subnormal (exponent field 0, mantissa nonzero) becomes a zero of the same sign; zeros, normals, inf and NaN pass. */
static inline float ws_mufu_ftz(float f) {
    uint32_t u; memcpy(&u, &f, 4);
    if ((u & 0x7f800000u) == 0u) u &= 0x80000000u;
    memcpy(&f, &u, 4);
    return f;
}
/* The three MUFU functions the codegen emits: input flushed, IEEE f32 function, result flushed. */
static inline float ws_mufu_ex2(float x) { return ws_mufu_ftz(exp2f(ws_mufu_ftz(x))); }
static inline float ws_mufu_rcp(float x) { return ws_mufu_ftz(1.0f / ws_mufu_ftz(x)); }
static inline float ws_mufu_rsq(float x) { return ws_mufu_ftz(1.0f / sqrtf(ws_mufu_ftz(x))); }

#endif
