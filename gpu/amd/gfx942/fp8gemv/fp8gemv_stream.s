// fp8gemv_stream, gfx942. Same words as fp8gemv_stream.isa.
.text
s_load_dwordx4 s[4:7], s[0:1], 0x0
s_load_dwordx4 s[8:11], s[0:1], 0x10
s_load_dwordx4 s[12:15], s[0:1], 0x20
s_load_dwordx4 s[16:19], s[0:1], 0x30
s_waitcnt lgkmcnt(0)
v_and_b32_e32 v0, 0x3ff, v0
s_and_b32 s22, s19, 1
s_cmp_eq_u32 s22, 0
s_cbranch_scc1 linear
s_and_b32 s22, s2, 7
s_lshr_b32 s23, s2, 3
s_add_u32 s24, s17, 7
s_lshr_b32 s24, s24, 3
s_mul_i32 s20, s22, s24
s_add_u32 s20, s20, s23
s_branch haverow
linear:
s_mov_b32 s20, s2
haverow:
s_cmp_ge_u32 s20, s17
s_cbranch_scc1 done
v_mov_b32_e32 v4, 0
s_mov_b32 s21, 0
s_mov_b32 s31, 0x400
v_lshlrev_b32_e32 v2, 4, v0
v_lshlrev_b32_e32 v3, 6, v0
pairs:
s_add_u32 s22, s31, s31
s_add_u32 s22, s21, s22
s_cmp_gt_u32 s22, s18
s_cbranch_scc1 single
s_mul_i32 s22, s20, s18
s_mul_hi_u32 s23, s20, s18
s_add_u32 s22, s22, s21
s_addc_u32 s23, s23, 0
s_add_u32 s22, s4, s22
s_addc_u32 s23, s5, s23
global_load_dwordx4 v[8:11], v2, s[22:23] nt
s_lshl_b32 s24, s21, 2
s_lshr_b32 s25, s21, 30
s_add_u32 s24, s6, s24
s_addc_u32 s25, s7, s25
global_load_dwordx4 v[16:19], v3, s[24:25]
global_load_dwordx4 v[20:23], v3, s[24:25] offset:16
global_load_dwordx4 v[24:27], v3, s[24:25] offset:32
global_load_dwordx4 v[28:31], v3, s[24:25] offset:48
s_add_u32 s30, s21, s31
s_mul_i32 s22, s20, s18
s_mul_hi_u32 s23, s20, s18
s_add_u32 s22, s22, s30
s_addc_u32 s23, s23, 0
s_add_u32 s22, s4, s22
s_addc_u32 s23, s5, s23
global_load_dwordx4 v[32:35], v2, s[22:23] nt
s_lshl_b32 s24, s30, 2
s_lshr_b32 s25, s30, 30
s_add_u32 s24, s6, s24
s_addc_u32 s25, s7, s25
global_load_dwordx4 v[36:39], v3, s[24:25]
global_load_dwordx4 v[40:43], v3, s[24:25] offset:16
global_load_dwordx4 v[44:47], v3, s[24:25] offset:32
global_load_dwordx4 v[48:51], v3, s[24:25] offset:48
s_waitcnt vmcnt(5)
v_cvt_pk_f32_fp8_e32 v[6:7], v8
v_fma_f32 v4, v6, v16, v4
v_fma_f32 v4, v7, v17, v4
v_lshrrev_b32_e32 v1, 16, v8
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v18, v4
v_fma_f32 v4, v7, v19, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v9
v_fma_f32 v4, v6, v20, v4
v_fma_f32 v4, v7, v21, v4
v_lshrrev_b32_e32 v1, 16, v9
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v22, v4
v_fma_f32 v4, v7, v23, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v10
v_fma_f32 v4, v6, v24, v4
v_fma_f32 v4, v7, v25, v4
v_lshrrev_b32_e32 v1, 16, v10
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v26, v4
v_fma_f32 v4, v7, v27, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v11
v_fma_f32 v4, v6, v28, v4
v_fma_f32 v4, v7, v29, v4
v_lshrrev_b32_e32 v1, 16, v11
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v30, v4
v_fma_f32 v4, v7, v31, v4
s_waitcnt vmcnt(0)
v_cvt_pk_f32_fp8_e32 v[6:7], v32
v_fma_f32 v4, v6, v36, v4
v_fma_f32 v4, v7, v37, v4
v_lshrrev_b32_e32 v1, 16, v32
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v38, v4
v_fma_f32 v4, v7, v39, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v33
v_fma_f32 v4, v6, v40, v4
v_fma_f32 v4, v7, v41, v4
v_lshrrev_b32_e32 v1, 16, v33
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v42, v4
v_fma_f32 v4, v7, v43, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v34
v_fma_f32 v4, v6, v44, v4
v_fma_f32 v4, v7, v45, v4
v_lshrrev_b32_e32 v1, 16, v34
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v46, v4
v_fma_f32 v4, v7, v47, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v35
v_fma_f32 v4, v6, v48, v4
v_fma_f32 v4, v7, v49, v4
v_lshrrev_b32_e32 v1, 16, v35
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v50, v4
v_fma_f32 v4, v7, v51, v4
s_add_u32 s21, s21, s31
s_add_u32 s21, s21, s31
s_branch pairs
single:
s_add_u32 s22, s21, s31
s_cmp_gt_u32 s22, s18
s_cbranch_scc1 tail
s_mul_i32 s22, s20, s18
s_mul_hi_u32 s23, s20, s18
s_add_u32 s22, s22, s21
s_addc_u32 s23, s23, 0
s_add_u32 s22, s4, s22
s_addc_u32 s23, s5, s23
global_load_dwordx4 v[8:11], v2, s[22:23] nt
s_lshl_b32 s24, s21, 2
s_lshr_b32 s25, s21, 30
s_add_u32 s24, s6, s24
s_addc_u32 s25, s7, s25
global_load_dwordx4 v[16:19], v3, s[24:25]
global_load_dwordx4 v[20:23], v3, s[24:25] offset:16
global_load_dwordx4 v[24:27], v3, s[24:25] offset:32
global_load_dwordx4 v[28:31], v3, s[24:25] offset:48
s_waitcnt vmcnt(0)
v_cvt_pk_f32_fp8_e32 v[6:7], v8
v_fma_f32 v4, v6, v16, v4
v_fma_f32 v4, v7, v17, v4
v_lshrrev_b32_e32 v1, 16, v8
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v18, v4
v_fma_f32 v4, v7, v19, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v9
v_fma_f32 v4, v6, v20, v4
v_fma_f32 v4, v7, v21, v4
v_lshrrev_b32_e32 v1, 16, v9
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v22, v4
v_fma_f32 v4, v7, v23, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v10
v_fma_f32 v4, v6, v24, v4
v_fma_f32 v4, v7, v25, v4
v_lshrrev_b32_e32 v1, 16, v10
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v26, v4
v_fma_f32 v4, v7, v27, v4
v_cvt_pk_f32_fp8_e32 v[6:7], v11
v_fma_f32 v4, v6, v28, v4
v_fma_f32 v4, v7, v29, v4
v_lshrrev_b32_e32 v1, 16, v11
v_cvt_pk_f32_fp8_e32 v[6:7], v1
v_fma_f32 v4, v6, v30, v4
v_fma_f32 v4, v7, v31, v4
s_add_u32 s21, s21, s31
tail:
s_mov_b32 s28, 0
tloop:
s_cmp_eq_u32 s28, 16
s_cbranch_scc1 reduce
v_add_u32_e32 v1, s21, v2
v_add_u32_e32 v1, s28, v1
v_cmp_lt_u32_e64 vcc, v1, s18
s_and_saveexec_b64 s[26:27], vcc
s_mul_i32 s22, s20, s18
s_mul_hi_u32 s23, s20, s18
s_add_u32 s22, s4, s22
s_addc_u32 s23, s5, s23
v_add_co_u32_e32 v8, vcc, s22, v1
v_mov_b32_e32 v12, 0
v_mov_b32_e32 v13, s23
v_addc_co_u32_e32 v9, vcc, v13, v12, vcc
global_load_ubyte v10, v[8:9], off nt
v_lshlrev_b32_e32 v8, 2, v1
v_lshrrev_b32_e32 v9, 30, v1
v_add_co_u32_e32 v8, vcc, s6, v8
v_mov_b32_e32 v13, s7
v_mov_b32_e32 v12, 0
v_addc_co_u32_e32 v9, vcc, v13, v9, vcc
global_load_dword v11, v[8:9], off
s_waitcnt vmcnt(0)
v_cvt_pk_f32_fp8_e32 v[6:7], v10
v_fma_f32 v4, v6, v11, v4
s_mov_b64 exec, s[26:27]
s_add_u32 s28, s28, 1
s_branch tloop
reduce:
v_add_f32_dpp v4, v4, v4 row_shr:8 row_mask:0xf bank_mask:0xf
v_add_f32_dpp v4, v4, v4 row_shr:4 row_mask:0xf bank_mask:0xf
v_add_f32_dpp v4, v4, v4 row_shr:2 row_mask:0xf bank_mask:0xf
v_add_f32_dpp v4, v4, v4 row_shr:1 row_mask:0xf bank_mask:0xf
v_readlane_b32 s28, v4, 15
v_readlane_b32 s29, v4, 31
v_readlane_b32 s30, v4, 47
v_readlane_b32 s31, v4, 63
v_mov_b32_e32 v5, s28
v_mov_b32_e32 v6, s29
v_add_f32_e32 v5, v5, v6
v_mov_b32_e32 v6, s30
v_mov_b32_e32 v7, s31
v_add_f32_e32 v6, v6, v7
v_add_f32_e32 v4, v5, v6
s_lshl_b32 s22, s20, 2
s_add_u32 s22, s8, s22
s_addc_u32 s23, s9, 0
v_mov_b32_e32 v8, s22
v_mov_b32_e32 v9, s23
global_load_dword v5, v[8:9], off
s_waitcnt vmcnt(0)
v_mul_f32_e32 v4, v4, v5
s_and_b32 s22, s19, 2
s_cmp_eq_u32 s22, 0
s_cbranch_scc1 nofuse
s_lshl_b32 s22, s20, 2
s_add_u32 s22, s12, s22
s_addc_u32 s23, s13, 0
v_mov_b32_e32 v8, s22
v_mov_b32_e32 v9, s23
global_load_dword v5, v[8:9], off
s_lshl_b32 s22, s20, 2
s_add_u32 s22, s14, s22
s_addc_u32 s23, s15, 0
v_mov_b32_e32 v8, s22
v_mov_b32_e32 v9, s23
global_load_dword v6, v[8:9], off
s_waitcnt vmcnt(0)
v_add_f32_e32 v4, v4, v5
v_mul_f32_e32 v4, s16, v4
v_mul_f32_e32 v4, v4, v6
nofuse:
s_and_b32 s22, s19, 4
s_cmp_eq_u32 s22, 0
s_cbranch_scc1 store32
v_lshrrev_b32_e32 v5, 16, v4
v_and_b32_e32 v6, 1, v5
v_add_u32_e32 v6, 0x7fff, v6
v_add_u32_e32 v6, v4, v6
v_lshrrev_b32_e32 v5, 16, v6
v_cmp_eq_u32_e64 vcc, v0, 0
s_and_saveexec_b64 s[26:27], vcc
s_lshl_b32 s22, s20, 1
s_add_u32 s22, s10, s22
s_addc_u32 s23, s11, 0
v_mov_b32_e32 v8, s22
v_mov_b32_e32 v9, s23
global_store_short v[8:9], v5, off
s_mov_b64 exec, s[26:27]
s_branch done
store32:
v_cmp_eq_u32_e64 vcc, v0, 0
s_and_saveexec_b64 s[26:27], vcc
s_lshl_b32 s22, s20, 2
s_add_u32 s22, s10, s22
s_addc_u32 s23, s11, 0
v_mov_b32_e32 v8, s22
v_mov_b32_e32 v9, s23
global_store_dword v[8:9], v4, off
s_mov_b64 exec, s[26:27]
done:
s_endpgm
