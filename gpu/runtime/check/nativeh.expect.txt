/* Generated checked portable Omega declarations. Regenerate with om/units.sh.
 * Status: 0 done, 1..14 trap, 32 argument refused, 33 reentry.
 * Only a successful call writes result. Fixed views use the declared length.
 * Runtime-extent units pass the live count under the bridge runtime-views profile.
 * Implementation is Omega lowered by omega-bridge, not the native AArch64 ABI. */
#ifndef CUDAPP_PORTABLE_OMEGA_H
#define CUDAPP_PORTABLE_OMEGA_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define OMEGA_OK 0u
#define OMEGA_BAD_ARG 32u
#define OMEGA_REENTRY 33u
uint32_t omega_bw_enc_sm121(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_cubin_elf(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_mathlibs_ir(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_ampere_enc_sm86(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_amp_runtime(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_native_repack(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_native_quant(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_native_compose(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_bc_encode(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_native_cache(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_native_lease(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_native_slotrev(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
uint32_t omega_native_event(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
uint32_t omega_native_validate(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, const void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_native_key(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_native_codekey(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_native_templates(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
uint32_t omega_native_graph(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, const void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_native_context_lookup(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, const void *p2, uint64_t p2_n);
uint32_t omega_native_binding(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_moe_plan(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_moe_group(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_moe_ids32(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_moe_maps32(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_moe_segs32(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_moe_windows(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_moe_admit(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_native_mcpack(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_native_mcbind(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, uint64_t p4, void *p5, uint64_t p5_n);
uint32_t omega_native_mcblob(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3, const void *p4, uint64_t p4_n, uint64_t p5);
uint32_t omega_native_mccover(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
uint32_t omega_native_mcintent(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, const void *p4, uint64_t p4_n);
uint32_t omega_native_mcseal(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_native_mcreseal(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_native_mccode(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_native_mclaunch(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_native_mcdir(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_native_mcalloc(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_native_mcseries(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_native_qgshape(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_native_qgreading(uint64_t  *result, uint64_t p0, uint64_t p1);
uint32_t omega_native_qgworkspace(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_native_qgorder(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_native_attnmirplan(uint64_t  *result, const void *p0, uint64_t p0_n);
uint32_t omega_native_attnmirnext(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_q38_runtime(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_q38_emit(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_cg_qmma(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_qmma_patch(uint64_t  *result, uint64_t p0, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_qm_self(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_qm_host(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_cg_tgemm_spec(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
uint32_t omega_cg_tgemm(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_pf_copy(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_tern(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_tern_sched(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n, const void *p4, uint64_t p4_n);
uint32_t omega_cg_tern_policy(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_streams_words(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_numeric_ref(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_numeric_tile(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
uint32_t omega_artifact_policy(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
uint32_t omega_artifact_parse(uint64_t  *result, uint64_t p0, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_api_policy(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_cm_sort(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_cm_math(uint64_t  *result, uint64_t p0, uint64_t p1);
uint32_t omega_cm_fit(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_cm_stats(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_cm_features(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_cm_quantile(uint64_t  *result, uint64_t p0, uint64_t p1);
uint32_t omega_cm_decision(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_cm_prediction(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_cm_calibration(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_cm_blob(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_cm_digest(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_artifact_format(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_artifact_admit(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_artifact_elf(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_api_mm_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_api_at_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_api_ew_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_api_bf_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_api_da_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_api_rt_plan(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_ew_ir(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_attention_ir(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cmdlist_record(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cmdlist_plan(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_cmdlist_layout(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cmdlist_access(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
uint32_t omega_nvrm_wire_pack(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_nvrm_wire_reply(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_nvrm_heap_wire(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_uvm_wire(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_uvm_map_wire(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_struct(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_plat_policy(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_plat_rest(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_nvml_step(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_nvml_errstr(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_chip_admit(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_ra_run(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_ra_ir(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
uint32_t omega_ra_live(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_cg_matmul(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_cg_par(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_cg_i32(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_tens(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_loop(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_frag(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_block(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_vec(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_hz_chk(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_hz_dec(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_cg_bind(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_scan_ir(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_scan_plan(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, void *p5, uint64_t p5_n);
uint32_t omega_aiengpu(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_sm121_dis(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_cg_moe(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cg_moe2(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cg_moe_sched(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
uint32_t omega_cg_gdn(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_gdn_policy(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
uint32_t omega_cg_dec(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_gdn_admit(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_bw_qmd(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_eng(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_fr_text(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_dag_eval(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_dag_parse(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_dag_fmt(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_dag_res(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_dag_diff(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_own30b_prof(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_doctor(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_ampcorp(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_ampfam(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_artexp(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_cg_tc(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_gemm_any_ir(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_dnn_rows(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_dr_plan(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_gemm_host_drive(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_gemm_value(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_gemm_cfg(uint64_t  *result, const void *p0, uint64_t p0_n);
uint32_t omega_gemm_plan(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_gemm_span(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_tc_host(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
uint32_t omega_dnn_activations(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_da_plan(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_cg_attn(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_pattn(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_pfhost(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_pf_admit(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_nvrm_policy(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_decide(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_emit(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_scan(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
uint32_t omega_book(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_memreserve(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_cg_fields(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cg_replay(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_cg_life(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_cg_invar(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
uint32_t omega_cg_budget(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
uint32_t omega_cm_route(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_numeric_rest_run(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_numeric_patch(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_numeric_check(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
uint32_t omega_numeric_trace(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_numeric_reduce(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, uint64_t p3, uint64_t p4);
uint32_t omega_native_mhval(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_native_mhwalk(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_native_mhstep(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_native_mhmany(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_native_mhidx(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_native_mhfft(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, void *p5, uint64_t p5_n);
uint32_t omega_so_oracles(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_va(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_nvrm_alloc_scalar(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_counts(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_nvrm_alloc_push(uint64_t  *result, const void *p0, uint64_t p0_n);
uint32_t omega_dag_jstr(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
uint32_t omega_dis_words(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_chip_enum(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_attn_any(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_aa_plan(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_gemm_scalar(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_conv_ir(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_conv_plan(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_cg_attn256(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_pattn256(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_router(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_gemm(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_bf16(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_cg_qg(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_omsha(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, const void *p5, uint64_t p5_n);
uint32_t omega_omcanon(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_omcidcmp(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
uint32_t omega_omcidhex(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_omparse(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_omcver(uint64_t  *result, uint64_t p0);
uint32_t omega_omcheck(uint64_t  *result, uint64_t p0, uint64_t p1);
uint32_t omega_omobject(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_omgraph(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
uint32_t omega_ompay(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_omparam(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_omeffect(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
uint32_t omega_omeval(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_omvec(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_omvspec(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_omvpay(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1);
uint32_t omega_omfmt(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_omnum(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_omclip(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
uint32_t omega_omhost(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_cubmsg(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_mg_wire(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_mg_node(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_mg_batch(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_mg_lauch(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_mg_copy(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_mg_xfer(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_mg_final(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_mg_exp(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_mg_group(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_mg_addr(uint64_t  *result, const void *p0, uint64_t p0_n);
uint32_t omega_mg_finb(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
uint32_t omega_mg_win(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, uint64_t p4);
uint32_t omega_mg_layout(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_mg_aux(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_resident(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_resident_check(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2, uint64_t p3);
uint32_t omega_grmeta(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_grtable(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_hello(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_hplan(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_cubadmit(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, void *p3, uint64_t p3_n);
uint32_t omega_ampack(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ghscale(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_gemm_ex_plan(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_gemm_ex_row(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_gemm_ex_x3(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, const void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
uint32_t omega_gemm_ex_acc(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_gemm_ex_dot(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
uint32_t omega_gemm_ex_epi(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n, const void *p4, uint64_t p4_n, void *p5, uint64_t p5_n);
uint32_t omega_gemm_ex_fp8(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_apishp(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_apishk(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_apishl(uint64_t  *result, uint64_t p0, uint64_t p1, void *p2, uint64_t p2_n);
uint32_t omega_apishb(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_apishr(uint64_t  *result, const void *p0, uint64_t p0_n);
uint32_t omega_av_ewarg(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_av_fp8am(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_av_fp8en(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, void *p5, uint64_t p5_n);
uint32_t omega_av_fp8q(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_av_e4m3(uint64_t  *result, uint64_t p0);
uint32_t omega_av_fp8sc(uint64_t  *result, uint64_t p0);
uint32_t omega_av_gdnch(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
uint32_t omega_av_gdnsl(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_av_scan(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
uint32_t omega_ah_rest(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_bf16(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_widen(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_rope(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gdnsc(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gdnex(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gdnpt(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gdnut(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_fp8x(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_fp8xb(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ar_carry(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_bw_identity(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_bw_cpui(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_bw_cpuf16(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_bw_cpubf16(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_bw_shape(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_bw_name(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_av_pack(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
uint32_t omega_av_lay(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_copy(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_attnrope(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_fold(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_set(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_fill(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_fillf(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1, float p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_count(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_cntf(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, float p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_bfexp(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_bffin(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_any(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_comp(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_rpois(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_z64(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_bids(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_rows(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gtab(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_range(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_total(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_table(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_touch(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n, uint64_t p3);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_blks(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_rfit(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_gath(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_stage(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_reset(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_hmap(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_eff(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_best(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_max(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_av_ctx(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ds_round(uint64_t  *result, uint64_t p0);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ds_slot(uint64_t  *result, uint64_t p0, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ds_vecf(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ds_vecb(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_na_read(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_na_cubin(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_na_layout(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_na_ver(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_na_json(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_mm_dot(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n, void *p3, uint64_t p3_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_mm_err(uint64_t  *result, const void *p0, uint64_t p0_n, uint64_t p1, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_mm_init(uint64_t  *result, void *p0, uint64_t p0_n);
uint32_t omega_mm_next(uint64_t  *result, void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ah_plan(uint64_t  *result, void *p0, uint64_t p0_n, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_sc_check(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, uint64_t p2);
uint32_t omega_clock_ns(uint64_t  *result, uint64_t p0, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_ar_bf16(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arfill(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arcount(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arargs(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arargsx(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arpad(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_aridle(uint64_t  *result, const void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arroute(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arperm(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arwiden(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arnext(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arkey(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arnan(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arscale(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arfold(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arfoldh(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_aracc(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_armag(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artiles(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artg(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artile(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argroups(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arrun(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artern(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artrits(uint64_t  *result, const void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arrev(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arpfcopy(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arpfrat(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arsegok(uint64_t  *result, uint64_t p0, uint64_t p1, const void *p2, uint64_t p2_n, const void *p3, uint64_t p3_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arsegb(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, const void *p3, uint64_t p3_n, void *p4, uint64_t p4_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artspec(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arcalc(uint64_t  *result, void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arlaunch(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arcache(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, const void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artcsp(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artcperm(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_artcinfo(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argtile(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argspec(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_pfcount(uint64_t  *result, const void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arpfreg(uint64_t  *result, uint64_t p0, uint64_t p1);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argargs(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argseg(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arginfo(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arxnext(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argath32(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_argath16(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arslot(uint64_t  *result, void *p0, uint64_t p0_n, void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arsgate(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arcopy(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arsstats(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_arvictim(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_armstep(uint64_t  *result, void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n);
uint32_t omega_cg_pklen(uint64_t  *result, void *p0, uint64_t p0_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_cg_pkh(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_mrow(uint64_t  *result, const void *p0, uint64_t p0_n, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_gemm_ex_policy(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_fv_run(uint64_t *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_cg_em(uint64_t  *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, void *p4, uint64_t p4_n);
uint32_t omega_cg_reconv(uint64_t  *result, uint64_t p0, void *p1, uint64_t p1_n);
/* Omega Bridge runtime views: numeric extents are capacities; * is unsized. */
uint32_t omega_sentin(uint64_t  *result, const void *p0, uint64_t p0_n, void *p1, uint64_t p1_n);
uint32_t omega_amp_qmd(uint64_t  *result, uint64_t p0, const void *p1, uint64_t p1_n, void *p2, uint64_t p2_n);
uint32_t omega_native_revision(uint64_t *result, uint64_t p0);
uint32_t omega_native_epoch(uint64_t *result, uint64_t p0);
uint32_t omega_native_f16(uint64_t *result, uint64_t p0);
uint32_t omega_native_c5(uint64_t *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_leftovers(uint64_t *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4);
uint32_t omega_bw_scalar(uint64_t *result, uint64_t p0, uint64_t p1, uint64_t p2, uint64_t p3, uint64_t p4, uint64_t p5);
uint32_t omega_streams_xq(uint64_t *result, uint64_t p0, uint64_t p1);
#ifdef __cplusplus
}
#endif
#endif
