/* SPDX-License-Identifier: Apache-2.0
 * bridge/tensorfold-omega/include/tf_omega_plugin.h
 *
 * C ABI v2 declarations for the optional zero-touch TensorFold Omega plugin
 * (`--backend omega`). Signatures match `bridge/omega-bridge/src/native.om h`.
 *
 * Status codes:
 *   0       : OMEGA_OK (result and `out` buffers committed)
 *   1..14   : Omega runtime/contract trap (`9` = REQUIRES, e.g. raw_floor < 6)
 *   32      : OMEGA_BAD_ARG (null pointer, wrong fixed len, misaligned, or overlap)
 *   33      : OMEGA_REENTRY
 *   34      : OMEGA_BAD_RT
 *   35      : OMEGA_NO_STACK
 */
#ifndef TF_OMEGA_PLUGIN_H
#define TF_OMEGA_PLUGIN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OMEGA_OK          0u
#define OMEGA_TRAP_REQ    9u
#define OMEGA_BAD_ARG    32u
#define OMEGA_REENTRY    33u
#define OMEGA_BAD_RT     34u
#define OMEGA_NO_STACK   35u

#define TF_OMEGA_MAGIC         0x4f4d544630303032ULL /* "OMTF0002" */
#define TF_OMEGA_MIN_RAW_FLOOR 6ULL
#define TF_OMEGA_PRED_CAP      16u
#define TF_OMEGA_NONE          0xffffffffu
#define TF_SM121_FLAG_ANCHOR   (1ULL << 0)
#define TF_SM121_FLAG_FIX_ALU  (1ULL << 1)

/* Exact byte-traceable unit identity (`omega-ident 1 unit=tf_omega_unit abi=2 profile=OM-2 src=... omc=...`). */
const char *omega2_ident_tf_omega_unit(void);

/* 1. Zero-drift Live Arboris MoE co-activation observer.
 * cfg[4] = { n_exp, n_slots, top_k_pred, decay_at }.
 * Mutates ONLY caller-owned `o_table`; never alters logits or output tokens. */
uint32_t omega2_tf_arboris_observe(
    uint64_t *result,
    uint32_t *o_table, uint64_t o_table_len,
    const uint64_t *o_cfg, uint64_t o_cfg_len,
    uint64_t o_prev_eid,
    const uint32_t *o_cur_ids, uint64_t o_cur_ids_len
);

/* 2. Zero-drift Live Arboris MoE read-only next-layer expert predictor.
 * Writes up to min(cfg[2], 16) predicted expert IDs into `o_pred` (committed ONLY on status 0). */
uint32_t omega2_tf_arboris_predict(
    uint64_t *result,
    const uint32_t *o_table, uint64_t o_table_len,
    const uint64_t *o_cfg, uint64_t o_cfg_len,
    const uint32_t *o_cur_ids, uint64_t o_cur_ids_len,
    uint32_t *o_pred
);

/* 3. SM121 Blackwell scoreboard RAW stall-floor & basic-block pinning verifier.
 * Traps 9 (REQUIRES) if o_raw_floor < 6.
 * Returns *result = 0 (PASS), 1 (RAW stall underflow), 2 (BB pin escape),
 * 3 (BB non-monotonic), 4 (fixed-ALU floor underflow). */
uint32_t omega2_tf_sm121_check_stall(
    uint64_t *result,
    const uint64_t *o_insns, uint64_t o_insns_len,
    uint64_t o_n_insns,
    uint64_t o_raw_floor
);

/* 4. Standalone EGP3 single-cert structural rewrite verifier.
 * Returns *result = 0 (PASS) or 1..10 refusal code. */
uint32_t omega2_tf_egp3_check_cert(
    uint64_t *result,
    const uint8_t *o_cert, uint64_t o_cert_len
);

/* 5. Byte-traceable ABI v2 capability & minimum floor metadata (out ulong 6). */
uint32_t omega2_tf_omega_ident(
    uint64_t *result,
    uint64_t *o_meta
);

#ifdef __cplusplus
}
#endif
#endif /* TF_OMEGA_PLUGIN_H */
