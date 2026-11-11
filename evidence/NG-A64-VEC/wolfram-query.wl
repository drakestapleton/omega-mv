Module[{
  hex32, rdn, r3,
  encWords, expectedWords, encMatch,
  f32Val, f32Bits, f64Val, f64Bits,
  fma32Exact1, fma32Unfused1, fma32Exact2, fma32Unfused2,
  fma64Exact1, fma64Unfused1, fma64Exact2, fma64Unfused2,
  nsF32Omc, nsV4F32, nsF64Omc, nsV2F64,
  medF32Omc, medV4F32, medF64Omc, medV2F64,
  minF32Omc, minV4F32, minF64Omc, minV2F64,
  opsPerTrial = 40960000, flopsPerTrial = 81920000, ghz = 39/10
},
  hex32[w_] := IntegerString[BitAnd[w, 2^32 - 1], 16, 8];
  rdn[base_, d_, n_] := BitOr[base, d, BitShiftLeft[n, 5]];
  r3[base_, d_, n_, m_] := BitOr[base, d, BitShiftLeft[n, 5], BitShiftLeft[m, 16]];

  (* 1. Arm DDI 0487 C7.2 packed 128-bit SIMD encodings *)
  encWords = <|
    "strq_q0_sp_0"     -> hex32[BitOr[16^^3d800000, 0, BitShiftLeft[31, 5], BitShiftLeft[0, 10]]],
    "ldrq_q3_sp_2"     -> hex32[BitOr[16^^3dc00000, 3, BitShiftLeft[31, 5], BitShiftLeft[2, 10]]],
    "ldrqr_q5_x1_x2"   -> hex32[BitOr[16^^3ce06800, 5, BitShiftLeft[1, 5], BitShiftLeft[2, 16]]],
    "orr16b_v4_v9_v9"  -> hex32[r3[16^^4ea01c00, 4, 9, 9]],
    "dupv4s_v2_v7"     -> hex32[rdn[16^^4e040400, 2, 7]],
    "dupv2d_v6_v1"     -> hex32[rdn[16^^4e080400, 6, 1]],
    "dups_s3_v8_lane3" -> hex32[BitOr[rdn[16^^5e040400, 3, 8], BitShiftLeft[3, 19]]],
    "dupd_d5_v2_lane1" -> hex32[BitOr[rdn[16^^5e080400, 5, 2], BitShiftLeft[1, 20]]],
    "fadd4s_v0_v1_v2"  -> hex32[r3[16^^4e20d400, 0, 1, 2]],
    "fadd2d_v3_v4_v5"  -> hex32[r3[16^^4e60d400, 3, 4, 5]],
    "fsub4s_v6_v7_v8"  -> hex32[r3[16^^4ea0d400, 6, 7, 8]],
    "fsub2d_v9_v10_v11"-> hex32[r3[16^^4ee0d400, 9, 10, 11]],
    "fmul4s_v12_v13_v14"-> hex32[r3[16^^6e20dc00, 12, 13, 14]],
    "fmul2d_v15_v16_v17"-> hex32[r3[16^^6e60dc00, 15, 16, 17]],
    "fmla4s_v18_v19_v20"-> hex32[r3[16^^4e20cc00, 18, 19, 20]],
    "fmla2d_v21_v22_v23"-> hex32[r3[16^^4e60cc00, 21, 22, 23]]
  |>;

  expectedWords = <|
    "strq_q0_sp_0"     -> "3d8003e0",
    "ldrq_q3_sp_2"     -> "3dc00be3",
    "ldrqr_q5_x1_x2"   -> "3ce26825",
    "orr16b_v4_v9_v9"  -> "4ea91d24",
    "dupv4s_v2_v7"     -> "4e0404e2",
    "dupv2d_v6_v1"     -> "4e080426",
    "dups_s3_v8_lane3" -> "5e1c0503",
    "dupd_d5_v2_lane1" -> "5e180445",
    "fadd4s_v0_v1_v2"  -> "4e22d420",
    "fadd2d_v3_v4_v5"  -> "4e65d483",
    "fsub4s_v6_v7_v8"  -> "4ea8d4e6",
    "fsub2d_v9_v10_v11"-> "4eebd549",
    "fmul4s_v12_v13_v14"-> "6e2eddac",
    "fmul2d_v15_v16_v17"-> "6e71de0f",
    "fmla4s_v18_v19_v20"-> "4e34ce72",
    "fmla2d_v21_v22_v23"-> "4e77ced5"
  |>;
  encMatch = (encWords === expectedWords);

  (* 2. Exact IEEE-754 single-rounding FMA lane verification vs unfused mul+add *)
  f32Val[u_] := Module[{s = BitGet[u, 31], e = BitAnd[BitShiftRight[u, 23], 255], m = BitAnd[u, 2^23 - 1]},
    (-1)^s * If[e == 0, m * 2^-149, (2^23 + m) * 2^(e - 150)]
  ];
  f32Bits[x_?NumericQ] := First[ImportString[ExportString[N[x, 50], "Real32", ByteOrdering -> -1], "UnsignedInteger32", ByteOrdering -> -1]];

  f64Val[u_] := Module[{s = BitGet[u, 63], e = BitAnd[BitShiftRight[u, 52], 2047], m = BitAnd[u, 2^52 - 1]},
    (-1)^s * If[e == 0, m * 2^-1074, (2^52 + m) * 2^(e - 1075)]
  ];
  f64Bits[x_?NumericQ] := First[ImportString[ExportString[N[x, 80], "Real64", ByteOrdering -> -1], "UnsignedInteger64", ByteOrdering -> -1]];

  (* v4f32 lane 0: (1 + 2^-23)*(1 - 2^-23) - 1 = -2^-46? Wait: 0x3f800001 = 1+2^-23, 0x3f7ffffe = 1-2^-23 -> (1+2^-23)(1-2^-23) - 1 = -2^-46 -> hex! *)
  fma32Exact1   = IntegerString[f32Bits[f32Val[16^^3f800001] * f32Val[16^^3f7ffffe] + f32Val[16^^bf800000]], 16, 8];
  fma32Unfused1 = IntegerString[f32Bits[f32Val[f32Bits[f32Val[16^^3f800001] * f32Val[16^^3f7ffffe]]] + f32Val[16^^bf800000]], 16, 8];

  fma32Exact2   = IntegerString[f32Bits[f32Val[16^^3f800001] * f32Val[16^^33800000] + f32Val[16^^3f800000]], 16, 8];
  fma32Unfused2 = IntegerString[f32Bits[f32Val[f32Bits[f32Val[16^^3f800001] * f32Val[16^^33800000]]] + f32Val[16^^3f800000]], 16, 8];

  fma64Exact1   = IntegerString[f64Bits[f64Val[16^^3ff0000000000001] * f64Val[16^^3feffffffffffffe] + f64Val[16^^bff0000000000000]], 16, 16];
  fma64Unfused1 = IntegerString[f64Bits[f64Val[f64Bits[f64Val[16^^3ff0000000000001] * f64Val[16^^3feffffffffffffe]]] + f64Val[16^^bff0000000000000]], 16, 16];

  fma64Exact2   = IntegerString[f64Bits[f64Val[16^^3ff0000000000001] * f64Val[16^^3ff0000000000001] + f64Val[16^^bff0000000000002]], 16, 16];
  fma64Unfused2 = IntegerString[f64Bits[f64Val[f64Bits[f64Val[16^^3ff0000000000001] * f64Val[16^^3ff0000000000001]]] + f64Val[16^^bff0000000000002]], 16, 16];

  (* 3. Cortex-X925 measured speedup and throughput *)
  nsF32Omc = {23870052, 23794820, 23299439, 23338512, 23301407};
  nsV4F32  = {7585465, 6914418, 6797249, 6932482, 6806833};
  nsF64Omc = {23833604, 22990748, 22971068, 23003500, 22918923};
  nsV2F64  = {14088439, 13636195, 13673235, 13655539, 13632899};

  medF32Omc = Median[nsF32Omc]; medV4F32 = Median[nsV4F32];
  medF64Omc = Median[nsF64Omc]; medV2F64 = Median[nsV2F64];
  minF32Omc = Min[nsF32Omc];    minV4F32 = Min[nsV4F32];
  minF64Omc = Min[nsF64Omc];    minV2F64 = Min[nsV2F64];

  <|
    "encodings_all_16_match" -> encMatch,
    "encodings" -> encWords,
    "fma32_case1_fused_vs_unfused" -> {fma32Exact1, fma32Unfused1},
    "fma32_case2_fused_vs_unfused" -> {fma32Exact2, fma32Unfused2},
    "fma64_case1_fused_vs_unfused" -> {fma64Exact1, fma64Unfused1},
    "fma64_case2_fused_vs_unfused" -> {fma64Exact2, fma64Unfused2},
    "f32_median_ns" -> {medF32Omc, medV4F32},
    "f32_median_speedup" -> N[medF32Omc / medV4F32, 6],
    "f32_min_speedup" -> N[minF32Omc / minV4F32, 6],
    "v4f32_gflops_median" -> N[flopsPerTrial / medV4F32, 6],
    "f32_omc_gflops_median" -> N[flopsPerTrial / medF32Omc, 6],
    "v4f32_cycles_per_elem_fma_3p9ghz" -> N[(medV4F32 * ghz) / opsPerTrial, 6],
    "f64_median_ns" -> {medF64Omc, medV2F64},
    "f64_median_speedup" -> N[medF64Omc / medV2F64, 6],
    "f64_min_speedup" -> N[minF64Omc / minV2F64, 6],
    "v2f64_gflops_median" -> N[flopsPerTrial / medV2F64, 6],
    "f64_omc_gflops_median" -> N[flopsPerTrial / medF64Omc, 6],
    "v2f64_cycles_per_elem_fma_3p9ghz" -> N[(medV2F64 * ghz) / opsPerTrial, 6]
  |>
]
