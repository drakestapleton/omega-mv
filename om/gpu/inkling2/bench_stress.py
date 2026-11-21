"""Full GB10 speed & stress test for Inkling-2-Mini seeded Omega SM121 kernels + Arboris.

Run inside an exclusive Spark window after building cubins with sh om/gpu/inkling2/build.sh:
    spark-window run python3 om/gpu/inkling2/bench_stress.py /path/to/cubin_dir
"""
import ctypes as ct
import json
import math
import os
import struct
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

GB10_NOMINAL_BW_GBS = 273.0
GB10_MEASURED_BW_GBS = 236.9


def f32_bits(v):
    return struct.unpack("<I", struct.pack("<f", float(v)))[0]


def tiles(n):
    return (n + 127) // 128


class GpuEngine:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.lib = ct.CDLL("libcuda.so.1")
        self.ctx = ct.c_void_p()
        self.call("cuInit", 0)
        dev = ct.c_int()
        self.call("cuDeviceGet", ct.byref(dev), 0)
        self.call("cuCtxCreate_v2", ct.byref(self.ctx), 0, dev)
        self.modules = {}
        self.fns = {}
        self.ev_start = ct.c_void_p()
        self.ev_stop = ct.c_void_p()
        self.call("cuEventCreate", ct.byref(self.ev_start), 0)
        self.call("cuEventCreate", ct.byref(self.ev_stop), 0)

    def call(self, name, *args):
        ret = getattr(self.lib, name)(*args)
        if ret:
            err = ct.c_char_p()
            self.lib.cuGetErrorName(ret, ct.byref(err))
            raise RuntimeError(f"{name}: {err.value} ({ret})")

    def fn(self, name):
        if name not in self.fns:
            mod, fn = ct.c_void_p(), ct.c_void_p()
            self.call("cuModuleLoad", ct.byref(mod), os.fsencode(self.directory / (name + ".cubin")))
            self.call("cuModuleGetFunction", ct.byref(fn), mod, name.encode())
            self.modules[name] = mod
            self.fns[name] = fn
        return self.fns[name]

    def alloc(self, arr):
        arr = np.ascontiguousarray(arr)
        ptr = ct.c_uint64()
        self.call("cuMemAlloc_v2", ct.byref(ptr), ct.c_size_t((arr.nbytes + 3) & ~3))
        self.call("cuMemcpyHtoD_v2", ptr, ct.c_void_p(arr.ctypes.data), ct.c_size_t(arr.nbytes))
        return ptr, arr

    def alloc_empty(self, shape, dtype):
        arr = np.zeros(shape, dtype=dtype)
        return self.alloc(arr)

    def read(self, ptr, arr):
        self.call("cuMemcpyDtoH_v2", ct.c_void_p(arr.ctypes.data), ptr, ct.c_size_t(arr.nbytes))
        return arr

    def free(self, ptr):
        if ptr and ptr.value:
            self.call("cuMemFree_v2", ptr)

    def launch(self, name, grid, block, ptrs, scalars=()):
        fn = self.fn(name)
        params = [ct.c_uint64(0 if p is None else p.value) for p in ptrs] + [ct.c_uint32(int(s)) for s in scalars]
        argv = (ct.c_void_p * len(params))(*(ct.addressof(i) for i in params))
        self.call("cuLaunchKernel", fn, grid[0], grid[1], grid[2], block, 1, 1, 0, None, argv, None)

    def sync(self):
        self.call("cuCtxSynchronize")

    def time_kernel(self, name, grid, block, ptrs, scalars=(), warmup=3, iters=10):
        for _ in range(warmup):
            self.launch(name, grid, block, ptrs, scalars)
        self.sync()
        self.call("cuEventRecord", self.ev_start, None)
        for _ in range(iters):
            self.launch(name, grid, block, ptrs, scalars)
        self.call("cuEventRecord", self.ev_stop, None)
        self.call("cuEventSynchronize", self.ev_stop)
        ms = ct.c_float()
        self.call("cuEventElapsedTime", ct.byref(ms), self.ev_start, self.ev_stop)
        return ms.value / iters

    def close(self):
        for mod in self.modules.values():
            self.call("cuModuleUnload", mod)
        self.call("cuEventDestroy_v2", self.ev_start)
        self.call("cuEventDestroy_v2", self.ev_stop)
        self.call("cuCtxDestroy_v2", self.ctx)


def run_microbenchmarks(eng, lut_ptr):
    print("\n=== 1. PER-KERNEL MICROBENCHMARKS (EXACT INKLING-2-MINI SHAPES) ===", flush=True)
    rng = np.random.default_rng(2026)
    results = {}
    ptrs_to_free = []

    def mk(arr):
        p, a = eng.alloc(arr)
        ptrs_to_free.append(p)
        return p, a

    def record(label, ms, byte_count):
        bw = (byte_count / 1e9) / (ms / 1e3) if ms > 0 else 0.0
        pct = 100.0 * bw / GB10_MEASURED_BW_GBS
        results[label] = {"ms": round(ms, 4), "bytes": byte_count, "gb_s": round(bw, 2), "pct_236_9": round(pct, 2)}
        print(f"  {label:36s} {ms:8.3f} ms  | {bw:7.2f} GB/s ({pct:5.1f}% of 236.9 GB/s)", flush=True)

    # NVFP4 quant (2304 -> 144 blocks, 1152 -> 72 blocks)
    x2304_p, _ = mk(rng.standard_normal(2304).astype(np.float32))
    outer_p, _ = mk(np.array([0.05], dtype=np.float32))
    p_pack, _ = mk(np.zeros(144 * 8, dtype=np.uint8))
    p_sc, _ = mk(np.zeros(144, dtype=np.uint8))
    p_rec, _ = mk(np.zeros(2304, dtype=np.float32))
    ms = eng.time_kernel("nvfp4_quant", (tiles(144), 1, 1), 128,
                         [x2304_p, lut_ptr, outer_p, p_pack, p_sc, p_rec], (144,), warmup=3, iters=20)
    record("nvfp4_quant (D=2304, 144 blk)", ms, 2304 * 4 * 2 + 144 * 9)

    # NVFP4 GEMM w13 (M=1, N=2304, K=2304) and w2 (M=1, N=2304, K=1152)
    pa_p, _ = mk(rng.integers(0, 256, (1, 2304 // 2), dtype=np.uint8))
    pw13_p, _ = mk(rng.integers(0, 256, (2304, 2304 // 2), dtype=np.uint8))
    sa_p, _ = mk(rng.integers(16, 80, (1, 2304 // 16), dtype=np.uint8))
    sw13_p, _ = mk(rng.integers(16, 80, (2304, 2304 // 16), dtype=np.uint8))
    alpha_p, _ = mk(np.array([0.0125], dtype=np.float32))
    c2304_p, _ = mk(np.zeros(2304, dtype=np.float32))
    ms = eng.time_kernel("nvfp4_gemm", (tiles(2304), 1, 1), 128,
                         [pa_p, pw13_p, sa_p, sw13_p, alpha_p, lut_ptr, c2304_p], (2304, 2304), warmup=3, iters=10)
    record("nvfp4_gemm w13 (1x2304x2304)", ms, 2304 * 1152 + 2304 * 144 + 2304 * 4)

    pw2_p, _ = mk(rng.integers(0, 256, (2304, 1152 // 2), dtype=np.uint8))
    sw2_p, _ = mk(rng.integers(16, 80, (2304, 1152 // 16), dtype=np.uint8))
    ms = eng.time_kernel("nvfp4_gemm", (tiles(2304), 1, 1), 128,
                         [pa_p, pw2_p, sa_p, sw2_p, alpha_p, lut_ptr, c2304_p], (1152, 2304), warmup=3, iters=10)
    record("nvfp4_gemm w2  (1x2304x1152)", ms, 2304 * 576 + 2304 * 72 + 2304 * 4)

    # MXFP8 quant (D=2304 -> 72 groups) & MXFP8 GEMM w13 / w2 (layers 20..23)
    m8_pack, _ = mk(np.zeros(2304, dtype=np.uint8))
    m8_sc, _ = mk(np.zeros(72, dtype=np.uint8))
    ms = eng.time_kernel("mxfp8_quant", (72, 1, 1), 16, [x2304_p, lut_ptr, m8_pack, m8_sc, p_rec], (), warmup=3, iters=20)
    record("mxfp8_quant (D=2304, 72 grp)", ms, 2304 * 4 * 2 + 2304 + 72)

    a8_p, _ = mk(rng.integers(16, 80, (1, 2304), dtype=np.uint8))
    w8_13_p, _ = mk(rng.integers(16, 80, (2304, 2304), dtype=np.uint8))
    sa8_p, _ = mk(rng.integers(125, 131, (1, 72), dtype=np.uint8))
    sw8_13_p, _ = mk(rng.integers(125, 131, (72, 72), dtype=np.uint8))
    ms = eng.time_kernel("mxfp8_gemm", (tiles(2304), 1, 1), 128,
                         [a8_p, w8_13_p, sa8_p, sw8_13_p, lut_ptr, c2304_p], (2304, 2304), warmup=3, iters=10)
    record("mxfp8_gemm w13 (1x2304x2304)", ms, 2304 * 2304 + 72 * 72 + 2304 * 4)

    w8_2_p, _ = mk(rng.integers(16, 80, (2304, 1152), dtype=np.uint8))
    sw8_2_p, _ = mk(rng.integers(125, 131, (72, 36), dtype=np.uint8))
    ms = eng.time_kernel("mxfp8_gemm", (tiles(2304), 1, 1), 128,
                         [a8_p, w8_2_p, sa8_p, sw8_2_p, lut_ptr, c2304_p], (1152, 2304), warmup=3, iters=10)
    record("mxfp8_gemm w2  (1x2304x1152)", ms, 2304 * 1152 + 72 * 36 + 2304 * 4)

    # Dense projections (BF16 widened FP32)
    w_q_p, _ = mk(rng.standard_normal((3072, 2304)).astype(np.float32))
    out3072_p, _ = mk(np.zeros(3072, dtype=np.float32))
    ms = eng.time_kernel("dense", (tiles(3072), 1, 1), 128, [x2304_p, w_q_p, out3072_p], (2304, 3072), warmup=2, iters=8)
    record("dense wq_du/gate (3072x2304)", ms, 3072 * 2304 * 4 + (2304 + 3072) * 4)

    w_kv_p, _ = mk(rng.standard_normal((1024, 2304)).astype(np.float32))
    out1024_p, _ = mk(np.zeros(1024, dtype=np.float32))
    ms = eng.time_kernel("dense", (tiles(1024), 1, 1), 128, [x2304_p, w_kv_p, out1024_p], (2304, 1024), warmup=2, iters=10)
    record("dense wk_dv/wv_dv (1024x2304)", ms, 1024 * 2304 * 4 + (2304 + 1024) * 4)

    w_o_p, _ = mk(rng.standard_normal((2304, 3072)).astype(np.float32))
    ms = eng.time_kernel("dense", (tiles(2304), 1, 1), 128, [out3072_p, w_o_p, c2304_p], (3072, 2304), warmup=2, iters=8)
    record("dense wo_ud (2304x3072)", ms, 2304 * 3072 * 4 + (3072 + 2304) * 4)

    w_gate_p, _ = mk(rng.standard_normal((128, 2304)).astype(np.float32))
    out128_p, _ = mk(np.zeros(128, dtype=np.float32))
    ms = eng.time_kernel("dense", (tiles(128), 1, 1), 128, [x2304_p, w_gate_p, out128_p], (2304, 128), warmup=3, iters=20)
    record("dense mlp.gate (128x2304)", ms, 128 * 2304 * 4 + (2304 + 128) * 4)

    # Full 201024 vocab unembed (allocated once, 1.85 GB FP32)
    w_un_p, _ = mk(rng.standard_normal((201024, 2304)).astype(np.float32))
    logits_p, _ = mk(np.zeros(201024, dtype=np.float32))
    ms = eng.time_kernel("dense", (tiles(201024), 1, 1), 128, [x2304_p, w_un_p, logits_p], (2304, 201024), warmup=1, iters=3)
    record("dense unembed (201024x2304)", ms, 201024 * 2304 * 4 + (2304 + 201024) * 4)

    # Logit softcap (201024)
    logits_out_p, _ = mk(np.zeros(201024, dtype=np.float32))
    ms = eng.time_kernel("logit_softcap", (tiles(201024), 1, 1), 128,
                         [logits_p, logits_out_p], (201024, f32_bits(30.0)), warmup=3, iters=20)
    record("logit_softcap (201024, cap=30)", ms, 201024 * 8)

    # RMSNorm, L2 clip, sconv static & dynamic
    inv_p, _ = mk(np.zeros(1, dtype=np.float32))
    gain_p, _ = mk(np.ones(2304, dtype=np.float32))
    ms_s = eng.time_kernel("rms_stat", (1, 1, 1), 1, [x2304_p, inv_p], (2304,), warmup=3, iters=20)
    ms_a = eng.time_kernel("rms_apply", (tiles(2304), 1, 1), 128, [x2304_p, gain_p, inv_p, c2304_p], (2304,), warmup=3, iters=20)
    record("rms_stat+apply (D=2304)", ms_s + ms_a, 2304 * 12)

    q_p, _ = mk(rng.standard_normal((1, 24, 128)).astype(np.float32))
    q_sc_p, _ = mk(np.ones((24, 128), dtype=np.float32))
    tau_p, _ = mk(np.array([1.05], dtype=np.float32))
    q_out_p, _ = mk(np.zeros((1, 24, 128), dtype=np.float32))
    ms = eng.time_kernel("l2_clip", (24, 1, 1), 1, [q_p, q_sc_p, tau_p, q_out_p],
                         (24, 128, f32_bits(22.627417), 3), warmup=3, iters=20)
    record("l2_clip Q (24x128, scaled+log)", ms, 24 * 128 * 12)

    st2304_p, _ = mk(rng.standard_normal((1, 2304, 3)).astype(np.float32))
    wsc_p, _ = mk(rng.standard_normal((2304, 4)).astype(np.float32))
    ms = eng.time_kernel("sconv_static", (tiles(2304), 1, 1), 128, [x2304_p, st2304_p, wsc_p, c2304_p], (2304,), warmup=3, iters=20)
    record("sconv_static (D=2304, k=4)", ms, 2304 * (1 + 3 + 4 + 1 + 3) * 4)

    st1024_p, _ = mk(rng.standard_normal((1, 1024, 3)).astype(np.float32))
    swd_p, _ = mk(rng.standard_normal((4, 1024)).astype(np.float32))
    dwd_p, _ = mk(rng.standard_normal((1, 8, 4)).astype(np.float32))
    ms = eng.time_kernel("sconv_dynamic", (tiles(1024), 1, 1), 128,
                         [out1024_p, st1024_p, swd_p, dwd_p, out1024_p], (1024, 7), warmup=3, iters=20)
    record("sconv_dynamic (D=1024, 8h, k=4)", ms, 1024 * 12 * 4)

    # Attention: sliding T=1024 and full T=4096 / T=8192 (3:1 GQA, 24 Q / 8 KV, hd=128)
    for label, T, W in [("attn SWA (T=1024, W=1024)", 1024, 1024),
                        ("attn FULL (T=4096, W=0)", 4096, 0),
                        ("attn FULL (T=8192, W=0)", 8192, 0)]:
        K_p, _ = mk(rng.standard_normal((1, 8, T, 128)).astype(np.float32) * 0.1)
        V_p, _ = mk(rng.standard_normal((1, 8, T, 128)).astype(np.float32) * 0.1)
        rel_p, _ = mk(rng.standard_normal((1, 24, 1024)).astype(np.float32) * 0.05)
        sc_p, _ = mk(np.zeros((1, 24, T), dtype=np.float32))
        sink_p, _ = mk(rng.standard_normal((1, 24)).astype(np.float32))
        ms1 = eng.time_kernel("inkling_attn_scores", (T, 24, 1), 1,
                              [q_p, K_p, rel_p, sc_p], (24, 8, T, 1024, T - 1, W), warmup=2, iters=6)
        ms2 = eng.time_kernel("inkling_attn_mix", (24, 1, 1), 128,
                              [sc_p, V_p, sink_p, q_out_p], (24, 8, T), warmup=2, iters=6)
        kv_bytes = 2 * 8 * T * 128 * 4 + 24 * T * 8
        record(label, ms1 + ms2, kv_bytes)

    # Router, softcap SwiGLU, MoE combine, attn_res, msg_gate
    bias_p, _ = mk(rng.standard_normal(128).astype(np.float32) * 0.1)
    ids_p, _ = mk(np.zeros(8, dtype=np.uint32))
    wts_p, _ = mk(np.zeros(8, dtype=np.float32))
    ms = eng.time_kernel("route8", (1, 1, 1), 1, [out128_p, bias_p, ids_p, wts_p], (), warmup=3, iters=20)
    record("route8 (128 exp -> top-8)", ms, (128 * 2 + 16) * 4)

    g1152_p, _ = mk(rng.standard_normal(1152).astype(np.float32))
    u1152_p, _ = mk(rng.standard_normal(1152).astype(np.float32))
    o1152_p, _ = mk(np.zeros(1152, dtype=np.float32))
    ms = eng.time_kernel("softcap_swiglu", (tiles(1152), 1, 1), 128,
                         [g1152_p, u1152_p, tau_p, o1152_p], (1152,), warmup=3, iters=20)
    record("softcap_swiglu (I=1152)", ms, 1152 * 12)

    downs_p, _ = mk(rng.standard_normal((1, 8, 2304)).astype(np.float32))
    ms = eng.time_kernel("moe_combine8", (tiles(2304), 1, 1), 128, [downs_p, c2304_p], (2304,), warmup=3, iters=20)
    record("moe_combine8 (8x2304)", ms, 9 * 2304 * 4)

    vblk_p, _ = mk(rng.standard_normal((1, 6, 2304)).astype(np.float32))
    qres_p, _ = mk(rng.standard_normal((4, 2304)).astype(np.float32))
    ores_p, _ = mk(np.zeros((1, 4, 2304), dtype=np.float32))
    ms = eng.time_kernel("attn_res", (4, 1, 1), 1, [vblk_p, qres_p, ores_p], (6, 4, 2304), warmup=3, iters=20)
    record("attn_res (K=6, Q=4, D=2304)", ms, (6 + 4 + 4) * 2304 * 4)

    ms = eng.time_kernel("msg_gate", (tiles(2304), 1, 1), 128,
                         [x2304_p, x2304_p, x2304_p, x2304_p, c2304_p], (2304,), warmup=3, iters=20)
    record("msg_gate (D=2304)", ms, 5 * 2304 * 4)

    for p in ptrs_to_free:
        eng.free(p)
    return results


def run_sustained_48_layer_stress(eng, lut_ptr, n_tokens=16):
    print(f"\n=== 2. SUSTAINED 48-LOGICAL-LAYER PIPELINE STRESS ({n_tokens} TOKENS) ===", flush=True)
    rng = np.random.default_rng(777)
    ptrs = []

    def mk(arr):
        p, a = eng.alloc(arr)
        ptrs.append(p)
        return p, a

    D, H, Hkv, HD, I, T_swa, T_full = 2304, 24, 8, 128, 1152, 1024, 4096
    h_p, h_arr = mk(rng.standard_normal(D).astype(np.float32) * 0.2)
    h_norm_p, _ = mk(np.zeros(D, dtype=np.float32))
    inv_p, _ = mk(np.zeros(1, dtype=np.float32))
    gain_p, _ = mk(np.ones(D, dtype=np.float32))
    outer_p, _ = mk(np.array([0.05], dtype=np.float32))
    alpha_p, _ = mk(np.array([0.002], dtype=np.float32))

    # Shared device buffers sized for exact Inkling-2-Mini shapes
    wq_p, _ = mk(rng.standard_normal((3072, D)).astype(np.float32) * 0.02)
    wk_p, _ = mk(rng.standard_normal((1024, D)).astype(np.float32) * 0.02)
    wo_p, _ = mk(rng.standard_normal((D, 3072)).astype(np.float32) * 0.02)
    wgate_p, _ = mk(rng.standard_normal((128, D)).astype(np.float32) * 0.02)
    bias_p, _ = mk(rng.standard_normal(128).astype(np.float32) * 0.05)
    q_buf, _ = mk(np.zeros(3072, dtype=np.float32))
    g_buf, _ = mk(np.zeros(3072, dtype=np.float32))
    k_buf, _ = mk(np.zeros(1024, dtype=np.float32))
    v_buf, _ = mk(np.zeros(1024, dtype=np.float32))
    q_clip_p, _ = mk(np.zeros((1, H, HD), dtype=np.float32))
    q_sc_p, _ = mk(np.ones((H, HD), dtype=np.float32))
    tau_p, _ = mk(np.array([1.0], dtype=np.float32))

    st_attn, _ = mk(np.zeros((1, D, 3), dtype=np.float32))
    st_kv, _ = mk(np.zeros((1, 1024, 3), dtype=np.float32))
    w_sconv, _ = mk(rng.standard_normal((D, 4)).astype(np.float32) * 0.1)
    sw_dyn, _ = mk(rng.standard_normal((4, 1024)).astype(np.float32) * 0.1)
    dw_dyn, _ = mk(rng.standard_normal((1, 8, 4)).astype(np.float32) * 0.05)

    K_swa, _ = mk(rng.standard_normal((1, Hkv, T_swa, HD)).astype(np.float32) * 0.1)
    V_swa, _ = mk(rng.standard_normal((1, Hkv, T_swa, HD)).astype(np.float32) * 0.1)
    K_full, _ = mk(rng.standard_normal((1, Hkv, T_full, HD)).astype(np.float32) * 0.1)
    V_full, _ = mk(rng.standard_normal((1, Hkv, T_full, HD)).astype(np.float32) * 0.1)
    rel_p, _ = mk(rng.standard_normal((1, H, 1024)).astype(np.float32) * 0.05)
    sc_full, _ = mk(np.zeros((1, H, T_full), dtype=np.float32))
    sink_p, _ = mk(rng.standard_normal((1, H)).astype(np.float32) * 0.1)

    rl_p, _ = mk(np.zeros(128, dtype=np.float32))
    ids_p, _ = mk(np.zeros(8, dtype=np.uint32))
    wts_p, _ = mk(np.zeros(8, dtype=np.float32))

    # NVFP4 & MXFP8 expert buffers
    a4_pack, _ = mk(np.zeros(144 * 8, dtype=np.uint8))
    a4_sc, _ = mk(np.zeros(144, dtype=np.uint8))
    a4_rec, _ = mk(np.zeros(D, dtype=np.float32))
    w4_13, _ = mk(rng.integers(0, 256, (2 * I, D // 2), dtype=np.uint8))
    sw4_13, _ = mk(rng.integers(16, 64, (2 * I, D // 16), dtype=np.uint8))
    w4_2, _ = mk(rng.integers(0, 256, (D, I // 2), dtype=np.uint8))
    sw4_2, _ = mk(rng.integers(16, 64, (D, I // 16), dtype=np.uint8))

    a8_pack, _ = mk(np.zeros(D, dtype=np.uint8))
    a8_sc, _ = mk(np.zeros(D // 32, dtype=np.uint8))
    w8_13, _ = mk(rng.integers(16, 64, (2 * I, D), dtype=np.uint8))
    sw8_13, _ = mk(rng.integers(124, 128, ((2 * I) // 32, D // 32), dtype=np.uint8))
    w8_2, _ = mk(rng.integers(16, 64, (D, I), dtype=np.uint8))
    sw8_2, _ = mk(rng.integers(124, 128, (D // 32, I // 32), dtype=np.uint8))

    gu_p, _ = mk(np.zeros(2 * I, dtype=np.float32))
    act_p, _ = mk(np.zeros(I, dtype=np.float32))
    downs_p, _ = mk(np.zeros((1, 8, D), dtype=np.float32))
    vblk_p, _ = mk(rng.standard_normal((1, 6, D)).astype(np.float32) * 0.2)
    qres_p, _ = mk(rng.standard_normal((4, D)).astype(np.float32) * 0.1)
    ores_p, _ = mk(np.zeros((1, 4, D), dtype=np.float32))

    # Build the 48-logical-layer execution schedule:
    # Prelude 0..5, Looped core 6..17 x3 (36 visits), Coda 18..23
    logical_layers = list(range(0, 6)) + list(range(6, 18)) * 3 + list(range(18, 24))
    assert len(logical_layers) == 48
    full_layers = {5, 11, 17, 23}
    mxfp8_layers = {20, 21, 22, 23}

    tok_times_ms = []
    for tok in range(n_tokens):
        t0 = time.perf_counter()
        pos_q = 512 + tok
        for step_idx, layer in enumerate(logical_layers):
            is_full = layer in full_layers
            is_mxfp8 = layer in mxfp8_layers
            is_loop_msg = (step_idx >= 18 and step_idx < 42)  # passes 1 and 2 of looped core

            # AttnRes + input RMSNorm
            q_cnt = 3 if is_full else 1
            eng.launch("attn_res", (q_cnt, 1, 1), 1, [vblk_p, qres_p, ores_p], (6, q_cnt, D))
            if is_loop_msg:
                eng.launch("msg_gate", (tiles(D), 1, 1), 128, [h_p, ores_p, h_p, h_p, h_p], (D,))
            eng.launch("rms_stat", (1, 1, 1), 1, [h_p, inv_p], (D,))
            eng.launch("rms_apply", (tiles(D), 1, 1), 128, [h_p, gain_p, inv_p, h_norm_p], (D,))

            # Q/K/V/gate projections + sconv + L2 clip
            eng.launch("dense", (tiles(3072), 1, 1), 128, [h_norm_p, wq_p, q_buf], (D, 3072))
            eng.launch("dense", (tiles(3072), 1, 1), 128, [h_norm_p, wq_p, g_buf], (D, 3072))
            eng.launch("dense", (tiles(1024), 1, 1), 128, [h_norm_p, wk_p, k_buf], (D, 1024))
            eng.launch("dense", (tiles(1024), 1, 1), 128, [h_norm_p, wk_p, v_buf], (D, 1024))
            if is_full:
                eng.launch("sconv_dynamic", (tiles(1024), 1, 1), 128, [k_buf, st_kv, sw_dyn, dw_dyn, k_buf], (1024, 7))
                eng.launch("sconv_dynamic", (tiles(1024), 1, 1), 128, [v_buf, st_kv, sw_dyn, dw_dyn, v_buf], (1024, 7))
            else:
                eng.launch("sconv_static", (tiles(1024), 1, 1), 128, [k_buf, st_kv, w_sconv, k_buf], (1024,))
                eng.launch("sconv_static", (tiles(1024), 1, 1), 128, [v_buf, st_kv, w_sconv, v_buf], (1024,))

            eng.launch("l2_clip", (H, 1, 1), 1, [q_buf, q_sc_p, tau_p if is_full else None, q_clip_p],
                       (H, HD, f32_bits(22.627417), 3 if is_full else 1))
            eng.launch("l2_clip", (Hkv, 1, 1), 1, [k_buf, None, None, k_buf], (Hkv, HD, f32_bits(22.627417), 0))

            # Hybrid 3:1 GQA attention + output gate + o_proj + post-attn sconv
            T_cur = T_full if is_full else T_swa
            W_cur = 0 if is_full else 1024
            K_cur = K_full if is_full else K_swa
            V_cur = V_full if is_full else V_swa
            eng.launch("inkling_attn_scores", (T_cur, H, 1), 1, [q_clip_p, K_cur, rel_p, sc_full],
                       (H, Hkv, T_cur, 1024, pos_q, W_cur))
            eng.launch("inkling_attn_mix", (H, 1, 1), 128, [sc_full, V_cur, sink_p, q_clip_p], (H, Hkv, T_cur))
            eng.launch("attn_gate", (tiles(3072), 1, 1), 128, [q_clip_p, g_buf, q_buf], (3072,))
            eng.launch("dense", (tiles(D), 1, 1), 128, [q_buf, wo_p, h_p], (3072, D))
            eng.launch("sconv_static", (tiles(D), 1, 1), 128, [h_p, st_attn, w_sconv, h_p], (D,))

            # MLP norm + Router + 8 routed experts (NVFP4 layers 0..19, MXFP8 layers 20..23) + combine + sconv
            eng.launch("rms_stat", (1, 1, 1), 1, [h_p, inv_p], (D,))
            eng.launch("rms_apply", (tiles(D), 1, 1), 128, [h_p, gain_p, inv_p, h_norm_p], (D,))
            eng.launch("dense", (tiles(128), 1, 1), 128, [h_norm_p, wgate_p, rl_p], (D, 128))
            eng.launch("route8", (1, 1, 1), 1, [rl_p, bias_p, ids_p, wts_p], ())

            if not is_mxfp8:
                eng.launch("nvfp4_quant", (tiles(144), 1, 1), 128,
                           [h_norm_p, lut_ptr, outer_p, a4_pack, a4_sc, a4_rec], (144,))
                for _e in range(8):
                    eng.launch("nvfp4_gemm", (tiles(2 * I), 1, 1), 128,
                               [a4_pack, w4_13, a4_sc, sw4_13, alpha_p, lut_ptr, gu_p], (D, 2 * I))
                    eng.launch("softcap_swiglu", (tiles(I), 1, 1), 128, [gu_p, gu_p, wts_p, act_p], (I,))
                    eng.launch("nvfp4_quant", (tiles(72), 1, 1), 128,
                               [act_p, lut_ptr, outer_p, a4_pack, a4_sc, a4_rec], (72,))
                    eng.launch("nvfp4_gemm", (tiles(D), 1, 1), 128,
                               [a4_pack, w4_2, a4_sc, sw4_2, alpha_p, lut_ptr, downs_p], (I, D))
            else:
                eng.launch("mxfp8_quant", (72, 1, 1), 16, [h_norm_p, lut_ptr, a8_pack, a8_sc, a4_rec], ())
                for _e in range(8):
                    eng.launch("mxfp8_gemm", (tiles(2 * I), 1, 1), 128,
                               [a8_pack, w8_13, a8_sc, sw8_13, lut_ptr, gu_p], (D, 2 * I))
                    eng.launch("softcap_swiglu", (tiles(I), 1, 1), 128, [gu_p, gu_p, wts_p, act_p], (I,))
                    eng.launch("mxfp8_quant", (36, 1, 1), 16, [act_p, lut_ptr, a8_pack, a8_sc, a4_rec], ())
                    eng.launch("mxfp8_gemm", (tiles(D), 1, 1), 128,
                               [a8_pack, w8_2, a8_sc, sw8_2, lut_ptr, downs_p], (I, D))

            eng.launch("moe_combine8", (tiles(D), 1, 1), 128, [downs_p, h_p], (D,))
            eng.launch("sconv_static", (tiles(D), 1, 1), 128, [h_p, st_attn, w_sconv, h_p], (D,))

        eng.sync()
        dt_ms = (time.perf_counter() - t0) * 1e3
        tok_times_ms.append(dt_ms)
        eng.read(h_p, h_arr)
        if not np.all(np.isfinite(h_arr)):
            raise RuntimeError(f"Non-finite hidden state at token {tok}!")
        if tok in (0, 1, n_tokens - 1):
            print(f"  tok {tok:2d}/{n_tokens}: {dt_ms:7.2f} ms ({1000.0/dt_ms:5.2f} tok/s) | L2={np.linalg.norm(h_arr):.4f} finite=OK", flush=True)

    steady = tok_times_ms[2:] if len(tok_times_ms) > 2 else tok_times_ms
    med_ms = float(np.median(steady))
    p95_ms = float(np.percentile(steady, 95))
    print(f"  STEADY (48 logical layers, T_swa=1024, T_full=4096): median={med_ms:.2f} ms ({1000.0/med_ms:.2f} tok/s), p95={p95_ms:.2f} ms", flush=True)

    for p in ptrs:
        eng.free(p)
    return {"tokens": n_tokens, "median_ms": round(med_ms, 2), "p95_ms": round(p95_ms, 2), "tok_s": round(1000.0 / med_ms, 2)}


def run_adversarial_stress(eng, lut_ptr):
    print("\n=== 3. ADVERSARIAL NUMERICAL & BOUNDARY STRESS (LIVE GB10) ===", flush=True)
    ptrs = []

    def mk(arr):
        p, a = eng.alloc(arr)
        ptrs.append(p)
        return p, a

    # Extreme values: zeros, subnormals (1e-30), large (+-1e4)
    vals = np.zeros(16 * 4, dtype=np.float32)
    vals[16:32] = 1e-30
    vals[32:48] = np.linspace(-1e4, 1e4, 16, dtype=np.float32)
    vals[48:64] = np.array([0.0, -0.0, 0.25, -0.25, 4.0, -4.0, 6.0, -6.0] * 2, dtype=np.float32)
    v_p, _ = mk(vals)
    outer_p, _ = mk(np.array([1.0], dtype=np.float32))
    pk_p, pk_a = mk(np.zeros(4 * 8, dtype=np.uint8))
    sc_p, sc_a = mk(np.zeros(4, dtype=np.uint8))
    rc_p, rc_a = mk(np.zeros(64, dtype=np.float32))
    eng.launch("nvfp4_quant", (1, 1, 1), 128, [v_p, lut_ptr, outer_p, pk_p, sc_p, rc_p], (4,))
    eng.sync()
    eng.read(rc_p, rc_a)
    assert np.all(np.isfinite(rc_a)), "nvfp4_quant produced non-finite on extreme inputs!"
    assert np.all(rc_a[:16] == 0.0), "nvfp4_quant zero block drifted!"
    print("  PASS nvfp4_quant extreme stress (zero, 1e-30, +-1e4, signed zero)", flush=True)

    # Softcap SwiGLU & Logit softcap saturation at +-1e4
    o_p, o_a = mk(np.zeros(64, dtype=np.float32))
    w1_p, _ = mk(np.array([1.0], dtype=np.float32))
    eng.launch("softcap_swiglu", (1, 1, 1), 128, [v_p, v_p, w1_p, o_p], (64,))
    eng.sync()
    eng.read(o_p, o_a)
    assert np.all(np.isfinite(o_a)) and np.max(np.abs(o_a)) <= 100.01, "softcap_swiglu saturation failed!"
    eng.launch("logit_softcap", (1, 1, 1), 128, [v_p, o_p], (64, f32_bits(30.0)))
    eng.sync()
    eng.read(o_p, o_a)
    assert np.all(np.isfinite(o_a)) and np.max(np.abs(o_a)) <= 30.001, "logit_softcap saturation failed!"
    print("  PASS softcap_swiglu & logit_softcap extreme saturation (+-1e4 -> bounded)", flush=True)

    # Max K=16 attn_res stress
    rng = np.random.default_rng(99)
    vb_p, _ = mk(rng.standard_normal((1, 16, 2304)).astype(np.float32))
    qr_p, _ = mk(rng.standard_normal((4, 2304)).astype(np.float32))
    or_p, or_a = mk(np.zeros((1, 4, 2304), dtype=np.float32))
    eng.launch("attn_res", (4, 1, 1), 1, [vb_p, qr_p, or_p], (16, 4, 2304))
    eng.sync()
    eng.read(or_p, or_a)
    assert np.all(np.isfinite(or_a)), "attn_res K=16 produced non-finite!"
    print("  PASS attn_res max-block stress (K=16, Q=4, D=2304)", flush=True)

    for p in ptrs:
        eng.free(p)
    return {"extreme_stress": "PASS"}


def run_arboris_stress(directory):
    print("\n=== 4. ARBORIS SEEDED OMEGA PREFETCHER STRESS & THROUGHPUT ===", flush=True)
    check_bin = str(Path(directory) / "check-arboris")
    hints_bin = str(Path(directory) / "arboris-expert-hints")
    subprocess.run([check_bin], check=True)
    print("  PASS check-arboris (all L17->L6 wrap, L17->L18, and rejection regressions)", flush=True)

    # Benchmark 500 ARH1 frames through arboris-expert-hints (128 experts, budget k=8)
    rng = np.random.default_rng(42)
    scores = rng.uniform(0.01, 1.0, size=128).astype(np.float32)
    payload = bytearray(struct.pack("<III", 0x31485241, 128, 8))
    for i in range(128):
        payload += struct.pack("<II", i, f32_bits(scores[i]))
    frame = bytes(payload)

    n_frames = 200
    t0 = time.perf_counter()
    for _ in range(n_frames):
        res = subprocess.run([hints_bin], input=frame, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        assert len(res.stdout) == 64
    dt_ms = (time.perf_counter() - t0) * 1e3
    us_per_frame = (dt_ms * 1000.0) / n_frames
    print(f"  PASS arboris-expert-hints: {n_frames} frames in {dt_ms:.1f} ms ({us_per_frame:.1f} us/frame incl. fork/exec)", flush=True)
    return {"check_arboris": "PASS", "hints_cli_us_per_frame": round(us_per_frame, 1)}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python3 bench_stress.py CUBIN_DIR")
    cubin_dir = Path(sys.argv[1])
    lut = np.fromfile(cubin_dir / "decode.f32le", dtype="<f4")
    eng = GpuEngine(cubin_dir)
    try:
        lut_ptr, _ = eng.alloc(lut)
        micro = run_microbenchmarks(eng, lut_ptr)
        sustained = run_sustained_48_layer_stress(eng, lut_ptr, n_tokens=16)
        stress = run_adversarial_stress(eng, lut_ptr)
        arboris = run_arboris_stress(cubin_dir)
        eng.free(lut_ptr)
    finally:
        eng.close()

    summary = {"micro": micro, "sustained_48L": sustained, "stress": stress, "arboris": arboris}
    print("\n=== JSON SUMMARY ===")
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
