"""GB10 numerical parity AND high-speed 48-layer benchmark (eager + single-submit CUDA Graph)
for Inkling-2-Mini high-speed seeded Omega SM121 kernels.

Run inside an exclusive Spark window after building with sh om/gpu/inkling2/build.sh:
    spark-window run python3 om/gpu/inkling2/check_fast.py /path/to/cubin_dir
"""
import ctypes as ct
import json
import math
import os
import struct
import sys
import time
from pathlib import Path

import numpy as np

GB10_MEASURED_BW_GBS = 236.9
GB10_NOMINAL_BW_GBS = 273.0


def f32_bits(v):
    return struct.unpack("<I", struct.pack("<f", float(v)))[0]


def bf16_f32(x):
    x = np.asarray(x, dtype=np.float32)
    u = x.view(np.uint32)
    return ((u + 32767 + ((u >> 16) & 1)) & 0xFFFF0000).view(np.float32)


def f32_to_bf16_u16(x):
    return (bf16_f32(x).view(np.uint32) >> 16).astype(np.uint16)


def rand_bf16_u16(rng, shape):
    # Strictly finite small BF16 values (~ +/- [0.004, 0.031]), zero NaN/Inf, fast to generate.
    mag = rng.integers(0x3a80, 0x3d00, shape, dtype=np.uint16)
    sgn = (rng.integers(0, 2, shape, dtype=np.uint16) << 15).astype(np.uint16)
    return (mag | sgn).astype(np.uint16)


def tiles(n, t=128):
    return (n + t - 1) // t


def lookup():
    values = []
    for code in range(256):
        exp, frac = (code >> 3) & 15, code & 7
        mag = frac / 512 if exp == 0 else (1 + frac / 8) * 2 ** (exp - 7)
        if exp == 15 and frac == 7:
            mag = np.nan
        values.append(-mag if code & 128 else mag)
    fp4 = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]
    return np.array(values + fp4 + [-v for v in fp4], np.float32)


def encode_table(values, table):
    mag = np.abs(values).astype(np.float64)
    mids = (table[:-1] + table[1:]).astype(np.float64) / 2
    code = np.searchsorted(mids, mag, side="left")
    tie = (code < len(mids)) & (mag == mids[np.minimum(code, len(mids) - 1)])
    return (code + (tie & (code % 2 == 1)) + np.signbit(values) * (128 if len(table) == 127 else 8)).astype(np.uint8)


class FastGpu:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.lib = ct.CDLL("libcuda.so.1")
        self.ctx = ct.c_void_p()
        self.call("cuInit", 0)
        self.dev = ct.c_int()
        self.call("cuDeviceGet", ct.byref(self.dev), 0)
        for attempt in range(4):
            ret = self.lib.cuDevicePrimaryCtxRetain(ct.byref(self.ctx), self.dev)
            if ret == 0:
                break
            if ret == 2 and attempt < 3:
                time.sleep(1.5)
                continue
            self.call("cuDevicePrimaryCtxRetain", ct.byref(self.ctx), self.dev)
        self.call("cuCtxSetCurrent", self.ctx)
        self.stream = ct.c_void_p()
        self.call("cuStreamCreate", ct.byref(self.stream), 0)
        self.modules = {}
        self.fns = {}
        self.smem = {}
        klist = Path(__file__).parent / "kernels_fast.list"
        if klist.exists():
            for line in klist.read_text().splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    self.smem[parts[1]] = int(parts[3])
        self.ev0 = ct.c_void_p()
        self.ev1 = ct.c_void_p()
        self.call("cuEventCreate", ct.byref(self.ev0), 0)
        self.call("cuEventCreate", ct.byref(self.ev1), 0)

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
        self.call("cuMemAlloc_v2", ct.byref(ptr), ct.c_size_t(max(4, (arr.nbytes + 15) & ~15)))
        self.call("cuMemcpyHtoD_v2", ptr, ct.c_void_p(arr.ctypes.data), ct.c_size_t(arr.nbytes))
        return ptr, arr

    def read(self, ptr, arr):
        self.call("cuMemcpyDtoH_v2", ct.c_void_p(arr.ctypes.data), ptr, ct.c_size_t(arr.nbytes))
        return arr

    def free(self, ptr):
        if ptr and ptr.value:
            self.call("cuMemFree_v2", ptr)

    def launch(self, name, grid, block, ptrs, scalars=(), stream=None):
        fn = self.fn(name)
        params = [ct.c_uint64(0 if p is None else p.value) for p in ptrs] + [ct.c_uint32(int(s)) for s in scalars]
        argv = (ct.c_void_p * len(params))(*(ct.addressof(i) for i in params))
        st = self.stream if stream is None else stream
        sh = self.smem.get(name, 0)
        self.call("cuLaunchKernel", fn, grid[0], grid[1], grid[2], block, 1, 1, sh, st, argv, None)

    def sync(self):
        self.call("cuStreamSynchronize", self.stream)

    def time_kernel(self, name, grid, block, ptrs, scalars=(), warmup=5, iters=30):
        for _ in range(warmup):
            self.launch(name, grid, block, ptrs, scalars)
        self.sync()
        self.call("cuEventRecord", self.ev0, self.stream)
        for _ in range(iters):
            self.launch(name, grid, block, ptrs, scalars)
        self.call("cuEventRecord", self.ev1, self.stream)
        self.call("cuEventSynchronize", self.ev1)
        ms = ct.c_float()
        self.call("cuEventElapsedTime", ct.byref(ms), self.ev0, self.ev1)
        return ms.value / iters

    def close(self):
        for mod in self.modules.values():
            self.call("cuModuleUnload", mod)
        self.call("cuEventDestroy_v2", self.ev0)
        self.call("cuEventDestroy_v2", self.ev1)
        self.call("cuStreamDestroy_v2", self.stream)
        self.call("cuDevicePrimaryCtxRelease_v2", self.dev)


def verify_all_fast_kernels(gpu, lut, lut_p):
    print("=== 1. STRICT PARITY CHECK FOR ALL 18 FAST SEEDED-OMEGA KERNELS ===", flush=True)
    rng = np.random.default_rng(1337)
    ptrs = []

    def mk(arr):
        p, a = gpu.alloc(arr)
        ptrs.append(p)
        return p, a

    def normal(*shape):
        return rng.standard_normal(shape).astype(np.float32)

    # 1. bf16_gemv_fast (non-multiple-of-32 N=2311, K=2304)
    N, K = 2311, 2304
    W_f = bf16_f32(normal(N, K) * 0.1)
    W_u16 = f32_to_bf16_u16(W_f)
    x = normal(K)
    wp, _ = mk(W_u16)
    xp, _ = mk(x)
    yp, y = mk(np.full(N, np.nan, dtype=np.float32))
    gpu.launch("bf16_gemv_fast", (tiles(N, 32), 1, 1), 256, [wp, xp, yp], (K, N))
    gpu.sync()
    gpu.read(yp, y)
    np.testing.assert_allclose(y, W_f @ x, atol=5e-4, rtol=5e-4)
    print("  PASS bf16_gemv_fast (N=2311, K=2304)", flush=True)

    # 2. nvfp4_gemv_grouped8_fast (both broadcast x_stride=0 w13 K=2304 and per-expert x_stride=1152 w2 K=1152)
    E = 16
    ids = np.array([3, 11, 0, 7, 15, 2, 9, 4], dtype=np.uint32)
    ids_p, _ = mk(ids)
    alpha_w = rng.uniform(0.01, 0.2, E).astype(np.float32)
    aw_p, _ = mk(alpha_w)
    for label, N4, K4, x_stride in [("w13", 2304, 2304, 0), ("w2", 2304, 1152, 1152)]:
        x_rec = normal(1 if x_stride == 0 else 8, K4) * 0.5
        qw = rng.integers(0, 16, (E, N4, K4), dtype=np.uint8)
        pw = qw[:, :, 0::2] | (qw[:, :, 1::2] << 4)
        sw = rng.integers(16, 80, (E, N4, K4 // 16), dtype=np.uint8)
        xr_p, _ = mk(x_rec)
        pw_p, _ = mk(pw)
        sw_p, _ = mk(sw)
        c_p, c_out = mk(np.full((8, N4), np.nan, dtype=np.float32))
        gpu.launch("nvfp4_gemv_grouped8_fast", (tiles(N4, 32), 8, 1), 256,
                   [xr_p, pw_p, sw_p, ids_p, aw_p, lut_p, c_p], (K4, N4, x_stride))
        gpu.sync()
        gpu.read(c_p, c_out)
        ref = np.zeros((8, N4), dtype=np.float32)
        for g in range(8):
            eid = int(ids[g])
            xv = x_rec[0 if x_stride == 0 else g]
            wf = lut[256 + qw[eid].astype(int)] * np.repeat(lut[sw[eid]], 16, axis=1)
            ref[g] = (wf @ xv) * alpha_w[eid]
        np.testing.assert_allclose(c_out, ref, atol=2e-3, rtol=2e-3)
        print(f"  PASS nvfp4_gemv_grouped8_fast {label} (8x{N4}x{K4}, x_stride={x_stride})", flush=True)

    # 3. mxfp8_gemv_grouped8_fast (both w13 K=2304 and w2 K=1152)
    for label, N8, K8, x_stride in [("w13", 2304, 2304, 0), ("w2", 2304, 1152, 1152)]:
        x_rec = normal(1 if x_stride == 0 else 8, K8) * 0.5
        w8 = rng.integers(0, 88, (E, N8, K8), dtype=np.uint8) | (rng.integers(0, 2, (E, N8, K8), dtype=np.uint8) << 7)
        sw8 = rng.integers(124, 130, (E, (N8 + 31) // 32, K8 // 32), dtype=np.uint8)
        xr_p, _ = mk(x_rec)
        w8_p, _ = mk(w8)
        sw8_p, _ = mk(sw8)
        c_p, c_out = mk(np.full((8, N8), np.nan, dtype=np.float32))
        gpu.launch("mxfp8_gemv_grouped8_fast", (tiles(N8, 32), 8, 1), 256,
                   [xr_p, w8_p, sw8_p, ids_p, lut_p, c_p], (K8, N8, x_stride))
        gpu.sync()
        gpu.read(c_p, c_out)
        ref = np.zeros((8, N8), dtype=np.float32)
        for g in range(8):
            eid = int(ids[g])
            xv = x_rec[0 if x_stride == 0 else g]
            sc = np.repeat(np.repeat(np.exp2(sw8[eid].astype(np.float32) - 127), 32, axis=0)[:N8], 32, axis=1)
            ref[g] = (lut[w8[eid]] * sc) @ xv
        np.testing.assert_allclose(c_out, ref, atol=2e-3, rtol=2e-3)
        print(f"  PASS mxfp8_gemv_grouped8_fast {label} (8x{N8}x{K8}, x_stride={x_stride})", flush=True)

    # 4. inkling_attn_flash_bf16 (SWA W=16 + FULL W=0, 3:1 GQA 24Q/8KV, rel_bias, sinks)
    B, H, Hkv, T, R, pos_q = 2, 24, 8, 40, 12, 35
    Q = normal(B, H, 128) * 0.25
    Kf = bf16_f32(normal(B, Hkv, T, 128) * 0.25)
    Vf = bf16_f32(normal(B, Hkv, T, 128) * 0.25)
    rel = normal(B, H, R) * 0.1
    sinks = normal(B, H) * 0.5
    qp, _ = mk(Q)
    kp, _ = mk(f32_to_bf16_u16(Kf))
    vp, _ = mk(f32_to_bf16_u16(Vf))
    rp, _ = mk(rel)
    sp, _ = mk(sinks)
    for label, W in [("SWA W=16", 16), ("FULL W=0", 0)]:
        op, out = mk(np.full((B, H, 128), np.nan, dtype=np.float32))
        gpu.launch("inkling_attn_flash_bf16", (H, B, 1), 256, [qp, kp, vp, rp, sp, op], (H, Hkv, T, R, pos_q, W))
        gpu.sync()
        gpu.read(op, out)
        K_rep = np.repeat(Kf, H // Hkv, axis=1)
        V_rep = np.repeat(Vf, H // Hkv, axis=1)
        sc = np.einsum("bhd,bhtd->bht", Q, K_rep) / math.sqrt(128.0)
        for t in range(T):
            dist = pos_q - t
            if t > pos_q or (W > 0 and dist >= W):
                sc[:, :, t] = -np.inf
            elif 0 <= dist < R:
                sc[:, :, t] += rel[:, :, dist]
        comb = np.concatenate([sc, sinks[:, :, None]], axis=-1)
        mx = np.max(comb, axis=-1, keepdims=True)
        ex = np.exp(comb - mx)
        probs = (ex / np.sum(ex, axis=-1, keepdims=True))[:, :, :-1]
        ref = np.einsum("bht,bhtd->bhd", probs, V_rep).astype(np.float32)
        np.testing.assert_allclose(out, ref, atol=3e-4, rtol=3e-4)
        print(f"  PASS inkling_attn_flash_bf16 ({label}, 3:1 GQA, BF16 KV)", flush=True)

    # 5. attn_res_fast (K=6, Q=3, D=2304 and K=16, Q=4, D=2304)
    for K_blk, Q_cnt in [(6, 3), (16, 4)]:
        Vb = normal(2, K_blk, 2304)
        Vb /= np.sqrt(np.mean(Vb * Vb, axis=-1, keepdims=True) + 1e-6)
        Qr = normal(Q_cnt, 2304) * 0.5
        vbp, _ = mk(Vb)
        qrp, _ = mk(Qr)
        orp, or_out = mk(np.full((2, Q_cnt, 2304), np.nan, dtype=np.float32))
        gpu.launch("attn_res_fast", (Q_cnt, 2, 1), 256, [vbp, qrp, orp], (K_blk, Q_cnt, 2304))
        gpu.sync()
        gpu.read(orp, or_out)
        s = np.einsum("qd,bkd->bqk", Qr, Vb) / math.sqrt(2304.0)
        s -= np.max(s, axis=-1, keepdims=True)
        p = np.exp(s) / np.sum(np.exp(s), axis=-1, keepdims=True)
        ref = np.einsum("bqk,bkd->bqd", p, Vb).astype(np.float32)
        np.testing.assert_allclose(or_out, ref, atol=3e-4, rtol=3e-4)
        print(f"  PASS attn_res_fast (K={K_blk}, Q={Q_cnt}, D=2304)", flush=True)

    # 6. rms_norm_fast (weighted + NULL-gain unweighted)
    xr = normal(3, 2304)
    xr[2] = 0.0
    gn = normal(2304)
    xrp, _ = mk(xr)
    gnp, _ = mk(gn)
    inv = 1.0 / np.sqrt(np.mean(xr * xr, axis=1, keepdims=True) + 1e-6).astype(np.float32)
    op1, o1 = mk(np.full_like(xr, np.nan))
    gpu.launch("rms_norm_fast", (3, 1, 1), 256, [xrp, gnp, op1], (2304,))
    gpu.sync()
    gpu.read(op1, o1)
    np.testing.assert_allclose(o1, xr * inv * gn, atol=1e-4, rtol=1e-4)
    op2, o2 = mk(np.full_like(xr, np.nan))
    gpu.launch("rms_norm_fast", (3, 1, 1), 256, [xrp, None, op2], (2304,))
    gpu.sync()
    gpu.read(op2, o2)
    np.testing.assert_allclose(o2, xr * inv, atol=1e-4, rtol=1e-4)
    print("  PASS rms_norm_fast (weighted + NULL unweighted)", flush=True)

    # 7. router_fast (128 experts, BF16 gate[128,2304] + sigmoid + bias + top-8 * 8.0)
    xrt = normal(2, 2304) * 0.5
    Wg_f = bf16_f32(normal(128, 2304) * 0.1)
    Wg_u16 = f32_to_bf16_u16(Wg_f)
    rb = normal(128) * 0.2
    xrtp, _ = mk(xrt)
    wgp, _ = mk(Wg_u16)
    rbp, _ = mk(rb)
    idp, id_out = mk(np.zeros((2, 8), dtype=np.uint32))
    wtp, wt_out = mk(np.full((2, 8), np.nan, dtype=np.float32))
    gpu.launch("router_fast", (2, 1, 1), 256, [xrtp, wgp, rbp, idp, wtp], ())
    gpu.sync()
    gpu.read(idp, id_out)
    gpu.read(wtp, wt_out)
    logits_r = xrt @ Wg_f.T
    scores_r = 1.0 / (1.0 + np.exp(-logits_r))
    keys_r = scores_r + rb[None, :]
    for b in range(2):
        order = sorted(range(128), key=lambda i: (-float(keys_r[b, i]), i))[:8]
        raw = scores_r[b, order]
        np.testing.assert_array_equal(id_out[b], order)
        np.testing.assert_allclose(wt_out[b], raw / (np.sum(raw) + 1e-20) * 8.0, atol=3e-4, rtol=3e-4)
    print("  PASS router_fast (fused BF16 gate[128,2304] + sigmoid + bias + top-8)", flush=True)

    # 8. l2_clip_fast (NULL optional pointers for flags=0, 1, 2, 3)
    xh = normal(2, 24, 128) * 5.0
    sc_h = normal(24, 128)
    tau = np.array([1.0, 1.15], dtype=np.float32)
    thresh = 22.627416997969522
    xhp, _ = mk(xh)
    schp, _ = mk(sc_h)
    taup, _ = mk(tau)
    for fl, p_s, p_t in [(0, None, None), (1, schp, None), (2, None, taup), (3, schp, taup)]:
        op, out = mk(np.full_like(xh, np.nan))
        gpu.launch("l2_clip_fast", (24, 2, 1), 32, [xhp, p_s, p_t, op], (24, 128, f32_bits(thresh), fl))
        gpu.sync()
        gpu.read(op, out)
        x_eff = xh * sc_h[None, :, :] if (fl & 1) else xh
        nrm = np.linalg.norm(x_eff, axis=-1, keepdims=True)
        ref = x_eff * np.minimum(1.0, thresh / (nrm + 1e-6))
        if fl & 2:
            ref = ref * tau[:, None, None]
        np.testing.assert_allclose(out, ref, atol=3e-4, rtol=3e-4)
    print("  PASS l2_clip_fast (flags 0,1,2,3 incl. NULL disabled pointers)", flush=True)

    # 9. nvfp4_quant_fast & mxfp8_quant_fast
    xnv = normal(17, 16) * 2.5
    xnv[0] = 0.0
    out_sc = np.array([0.05], dtype=np.float32)
    xnvp, _ = mk(xnv)
    osp, _ = mk(out_sc)
    pkp, pk = mk(np.zeros((17, 8), dtype=np.uint8))
    scp, sc = mk(np.zeros(17, dtype=np.uint8))
    rcp, rc = mk(np.zeros((17, 16), dtype=np.float32))
    gpu.launch("nvfp4_quant_fast", (1, 1, 1), 128, [xnvp, lut_p, osp, pkp, scp, rcp], (17,))
    gpu.sync()
    gpu.read(rcp, rc)
    assert np.all(rc[0] == 0.0) and np.all(np.isfinite(rc))
    print("  PASS nvfp4_quant_fast (SMEM LUT)", flush=True)

    xmx = bf16_f32(normal(9, 32) * 3.0)
    xmx[0] = 0.0
    xmxp, _ = mk(xmx)
    pk8p, pk8 = mk(np.zeros((9, 32), dtype=np.uint8))
    sc8p, sc8 = mk(np.zeros(9, dtype=np.uint8))
    rc8p, rc8 = mk(np.zeros((9, 32), dtype=np.float32))
    gpu.launch("mxfp8_quant_fast", (1, 1, 1), 128, [xmxp, lut_p, pk8p, sc8p, rc8p], (9,))
    gpu.sync()
    gpu.read(pk8p, pk8)
    gpu.read(sc8p, sc8)
    gpu.read(rc8p, rc8)
    ratio = np.maximum(np.abs(xmx).max(axis=1), 1e-4) / np.float32(448.0)
    exps = np.ceil(np.log2(ratio.astype(np.float64)))
    ref_sc8 = (exps + 127).astype(np.uint8)
    ref_q8 = encode_table(xmx / np.exp2(exps).astype(np.float32)[:, None], lut[:127])
    np.testing.assert_array_equal(sc8, ref_sc8)
    np.testing.assert_array_equal(pk8, ref_q8)
    print("  PASS mxfp8_quant_fast (SMEM LUT, bit-exact)", flush=True)

    # 10. softcap_swiglu8_fast & glue_sconv_fast
    gu8 = normal(8, 2304) * 6.0
    w8s = normal(8)
    gup, _ = mk(gu8)
    w8sp, _ = mk(w8s)
    o8p, o8 = mk(np.full((8, 1152), np.nan, dtype=np.float32))
    gpu.launch("softcap_swiglu8_fast", (tiles(1152), 8, 1), 128, [gup, w8sp, o8p, None], (1152,))
    gpu.sync()
    gpu.read(o8p, o8)
    g_part, u_part = gu8[:, :1152], gu8[:, 1152:]
    ref_sw = (4.0 * np.tanh(g_part / 4.0)) * (1.0 / (1.0 + np.exp(-g_part))) * (25.0 * np.tanh(u_part / 25.0)) * w8s[:, None]
    np.testing.assert_allclose(o8, ref_sw, atol=2e-4, rtol=2e-4)
    print("  PASS softcap_swiglu8_fast (8x1152 1-launch)", flush=True)

    xs = normal(2, 2304)
    st = normal(2, 2304, 3)
    ws = normal(2304, 4)
    xsp, _ = mk(xs)
    stp, st_out = mk(st.copy())
    wsp, _ = mk(ws)
    osp, os_out = mk(np.full_like(xs, np.nan))
    gpu.launch("glue_sconv_fast", (tiles(2304), 2, 1), 128, [xsp, stp, wsp, osp], (2304,))
    gpu.sync()
    gpu.read(osp, os_out)
    gpu.read(stp, st_out)
    ref_sc = (st[:, :, 0] * ws[:, 0] + st[:, :, 1] * ws[:, 1] + st[:, :, 2] * ws[:, 2] + xs * ws[:, 3] + xs) / math.sqrt(5.0)
    np.testing.assert_allclose(os_out, ref_sc, atol=1e-4, rtol=1e-4)
    np.testing.assert_allclose(st_out, np.stack([st[:, :, 1], st[:, :, 2], xs], axis=-1), atol=0, rtol=0)
    print("  PASS glue_sconv_fast (out + state)", flush=True)

    # 13. router_top8_fast (4-CTA bf16_gemv_fast + 1-warp parallel router_top8_fast)
    lg_p, _ = mk(np.zeros((2, 128), dtype=np.float32))
    for b in range(2):
        xp_b = ct.c_uint64(xrtp.value + b * 2304 * 4)
        lp_b = ct.c_uint64(lg_p.value + b * 128 * 4)
        gpu.launch("bf16_gemv_fast", (tiles(128, 32), 1, 1), 256, [wgp, xp_b, lp_b], (2304, 128))
    idp2, id_out2 = mk(np.zeros((2, 8), dtype=np.uint32))
    wtp2, wt_out2 = mk(np.full((2, 8), np.nan, dtype=np.float32))
    gpu.launch("router_top8_fast", (2, 1, 1), 32, [lg_p, rbp, idp2, wtp2], ())
    gpu.sync()
    gpu.read(idp2, id_out2)
    gpu.read(wtp2, wt_out2)
    for b in range(2):
        order = sorted(range(128), key=lambda i: (-float(keys_r[b, i]), i))[:8]
        raw = scores_r[b, order]
        np.testing.assert_array_equal(id_out2[b], order)
        np.testing.assert_allclose(wt_out2[b], raw / (np.sum(raw) + 1e-20) * 8.0, atol=3e-4, rtol=3e-4)
    print("  PASS router_top8_fast (4-CTA bf16_gemv_fast + 1-warp SHFL.BFLY top-8)", flush=True)

    # 14 & 15. inkling_attn_flash_split_bf16 + inkling_attn_reduce_bf16 (S=2 SWA ungated & S=4 FULL fused attn_gate)
    gate_a = normal(B, H, 128) * 0.5
    gate_ap, _ = mk(gate_a)
    for label, W, S_val, use_gate in [("SWA W=16 S=2", 16, 2, False), ("FULL W=0 S=4 + fused attn_gate", 0, 4, True)]:
        pml_p, _ = mk(np.zeros((B, H, S_val, 2), dtype=np.float32))
        po_p, _ = mk(np.zeros((B, H, S_val, 128), dtype=np.float32))
        op_s, out_s = mk(np.full((B, H, 128), np.nan, dtype=np.float32))
        gpu.launch("inkling_attn_flash_split_bf16", (H, S_val, B), 256,
                   [qp, kp, vp, rp, pml_p, po_p], (H, Hkv, T, R, pos_q, W, S_val))
        gpu.launch("inkling_attn_reduce_bf16", (H, B, 1), 32,
                   [pml_p, po_p, sp, gate_ap if use_gate else None, op_s], (H, S_val))
        gpu.sync()
        gpu.read(op_s, out_s)
        K_rep = np.repeat(Kf, H // Hkv, axis=1)
        V_rep = np.repeat(Vf, H // Hkv, axis=1)
        sc = np.einsum("bhd,bhtd->bht", Q, K_rep) / math.sqrt(128.0)
        for t in range(T):
            dist = pos_q - t
            if t > pos_q or (W > 0 and dist >= W):
                sc[:, :, t] = -np.inf
            elif 0 <= dist < R:
                sc[:, :, t] += rel[:, :, dist]
        comb = np.concatenate([sc, sinks[:, :, None]], axis=-1)
        mx = np.max(comb, axis=-1, keepdims=True)
        ex = np.exp(comb - mx)
        probs = (ex / np.sum(ex, axis=-1, keepdims=True))[:, :, :-1]
        ref_s = np.einsum("bht,bhtd->bhd", probs, V_rep).astype(np.float32)
        if use_gate:
            ref_s = (ref_s * (1.0 / (1.0 + np.exp(-gate_a)))).astype(np.float32)
        np.testing.assert_allclose(out_s, ref_s, atol=3e-4, rtol=3e-4)
        print(f"  PASS inkling_attn_flash_split_bf16 + reduce ({label})", flush=True)

    # 16. moe_combine8_sconv_fast (fused 8-expert sum + static sconv + state update)
    dn8 = normal(2, 8, 2304) * 0.25
    dn8p, _ = mk(dn8)
    stp2, st_out2 = mk(st.copy())
    osp2, os_out2 = mk(np.full((2, 2304), np.nan, dtype=np.float32))
    gpu.launch("moe_combine8_sconv_fast", (tiles(2304), 2, 1), 128, [dn8p, stp2, wsp, osp2], (2304,))
    gpu.sync()
    gpu.read(osp2, os_out2)
    gpu.read(stp2, st_out2)
    xs8 = dn8.sum(axis=1)
    ref_mc = (st[:, :, 0] * ws[:, 0] + st[:, :, 1] * ws[:, 1] + st[:, :, 2] * ws[:, 2] + xs8 * ws[:, 3] + xs8) / math.sqrt(5.0)
    np.testing.assert_allclose(os_out2, ref_mc, atol=2e-4, rtol=2e-4)
    np.testing.assert_allclose(st_out2, np.stack([st[:, :, 1], st[:, :, 2], xs8], axis=-1), atol=2e-4, rtol=2e-4)
    print("  PASS moe_combine8_sconv_fast (fused combine + sconv + state)", flush=True)

    # 17. sconv_rmsnorm_fast (fused static sconv + state + weighted RMSNorm, D=2304 register-resident)
    stp3, st_out3 = mk(st.copy())
    h_o3, ho3 = mk(np.full((2, 2304), np.nan, dtype=np.float32))
    hn_o3, hno3 = mk(np.full((2, 2304), np.nan, dtype=np.float32))
    gpu.launch("sconv_rmsnorm_fast", (2, 1, 1), 256, [xsp, stp3, wsp, gnp, h_o3, hn_o3], ())
    gpu.sync()
    gpu.read(h_o3, ho3)
    gpu.read(hn_o3, hno3)
    gpu.read(stp3, st_out3)
    np.testing.assert_allclose(ho3, ref_sc, atol=1e-4, rtol=1e-4)
    inv_sc = 1.0 / np.sqrt(np.mean(ref_sc * ref_sc, axis=1, keepdims=True) + 1e-6).astype(np.float32)
    np.testing.assert_allclose(hno3, ref_sc * inv_sc * gn[None, :], atol=2e-4, rtol=2e-4)
    np.testing.assert_allclose(st_out3, np.stack([st[:, :, 1], st[:, :, 2], xs], axis=-1), atol=0, rtol=0)
    print("  PASS sconv_rmsnorm_fast (fused sconv + state + RMSNorm, D=2304)", flush=True)

    # 18. swiglu8_nvfp4_quant_fast (fused 8-expert softcapped SwiGLU + fouroversix_mae NVFP4 quant)
    pk_f, pk_fo = mk(np.zeros((8 * 72, 8), dtype=np.uint8))
    sc_f, sc_fo = mk(np.zeros(8 * 72, dtype=np.uint8))
    rc_f, rc_fo = mk(np.full((8 * 72, 16), np.nan, dtype=np.float32))
    gpu.launch("swiglu8_nvfp4_quant_fast", (1, 8, 1), 128, [gup, w8sp, lut_p, osp, pk_f, sc_f, rc_f], (1152,))
    gpu.sync()
    gpu.read(pk_f, pk_fo)
    gpu.read(sc_f, sc_fo)
    gpu.read(rc_f, rc_fo)
    # Compare against separate softcap_swiglu8_fast + nvfp4_quant_fast!
    pk_r, pk_ro = mk(np.zeros((8 * 72, 8), dtype=np.uint8))
    sc_r, sc_ro = mk(np.zeros(8 * 72, dtype=np.uint8))
    rc_r, rc_ro = mk(np.full((8 * 72, 16), np.nan, dtype=np.float32))
    gpu.launch("nvfp4_quant_fast", (tiles(8 * 72), 1, 1), 128, [o8p, lut_p, osp, pk_r, sc_r, rc_r], (8 * 72,))
    gpu.sync()
    gpu.read(pk_r, pk_ro)
    gpu.read(sc_r, sc_ro)
    gpu.read(rc_r, rc_ro)
    np.testing.assert_array_equal(sc_fo, sc_ro)
    np.testing.assert_array_equal(pk_fo, pk_ro)
    np.testing.assert_allclose(rc_fo, rc_ro, atol=1e-5, rtol=1e-5)
    print("  PASS swiglu8_nvfp4_quant_fast (bit-exact vs softcap_swiglu8 + nvfp4_quant)", flush=True)

    for p in ptrs:
        gpu.free(p)
    print("ALL 18 FAST SEEDED-OMEGA KERNELS PASSED PARITY!", flush=True)


def run_fast_benchmarks(gpu, lut_p):
    print("\n=== 2. FAST KERNEL MICROBENCHMARKS (VS 236.9 GB/s GB10 CEILING) ===", flush=True)
    rng = np.random.default_rng(2026)
    ptrs = []
    res = {}

    def mk(arr):
        p, a = gpu.alloc(arr)
        ptrs.append(p)
        return p, a

    def rec(label, ms, nbytes):
        bw = (nbytes / 1e9) / (ms / 1e3) if ms > 0 else 0.0
        pct = 100.0 * bw / GB10_MEASURED_BW_GBS
        res[label] = {"ms": round(ms, 4), "gb_s": round(bw, 2), "pct_236_9": round(pct, 1)}
        print(f"  {label:40s} {ms:7.3f} ms | {bw:7.2f} GB/s ({pct:5.1f}% of 236.9)", flush=True)

    x2304, _ = mk(rng.standard_normal(2304).astype(np.float32))
    x3072, _ = mk(rng.standard_normal(3072).astype(np.float32))
    y8192, _ = mk(np.zeros(8192, dtype=np.float32))
    y2304, _ = mk(np.zeros(2304, dtype=np.float32))

    # Fused BF16 q|gate|k|v [8192, 2304]
    w_qkv, _ = mk(rand_bf16_u16(rng, (8192, 2304)))
    ms = gpu.time_kernel("bf16_gemv_fast", (tiles(8192, 32), 1, 1), 256, [w_qkv, x2304, y8192], (2304, 8192))
    rec("bf16_gemv_fast q|gate|k|v (8192x2304)", ms, 8192 * 2304 * 2 + (2304 + 8192) * 4)

    # BF16 wo_ud [2304, 3072]
    w_o, _ = mk(rand_bf16_u16(rng, (2304, 3072)))
    ms = gpu.time_kernel("bf16_gemv_fast", (tiles(2304, 32), 1, 1), 256, [w_o, x3072, y2304], (3072, 2304))
    rec("bf16_gemv_fast wo_ud (2304x3072)", ms, 2304 * 3072 * 2 + (3072 + 2304) * 4)

    # BF16 full unembed [201024, 2304] (926 MB!)
    w_un, _ = mk(rand_bf16_u16(rng, (201024, 2304)))
    y_un, _ = mk(np.zeros(201024, dtype=np.float32))
    ms = gpu.time_kernel("bf16_gemv_fast", (tiles(201024, 32), 1, 1), 256, [w_un, x2304, y_un], (2304, 201024), warmup=2, iters=6)
    rec("bf16_gemv_fast unembed (201024x2304)", ms, 201024 * 2304 * 2 + (2304 + 201024) * 4)

    # Grouped 8-expert NVFP4 w13 & w2
    ids_p, _ = mk(np.arange(8, dtype=np.uint32))
    aw_p, _ = mk(np.full(16, 0.05, dtype=np.float32))
    w4_13, _ = mk(rng.integers(0, 256, (16, 2304, 1152), dtype=np.uint8))
    sw4_13, _ = mk(rng.integers(16, 80, (16, 2304, 144), dtype=np.uint8))
    c8_2304, _ = mk(np.zeros((8, 2304), dtype=np.float32))
    ms = gpu.time_kernel("nvfp4_gemv_grouped8_fast", (tiles(2304, 32), 8, 1), 256,
                         [x2304, w4_13, sw4_13, ids_p, aw_p, lut_p, c8_2304], (2304, 2304, 0))
    rec("nvfp4_gemv_grouped8 w13 (8x2304x2304)", ms, 8 * (2304 * 1152 + 2304 * 144 + 2304 * 4))

    x8_1152, _ = mk(rng.standard_normal((8, 1152)).astype(np.float32))
    w4_2, _ = mk(rng.integers(0, 256, (16, 2304, 576), dtype=np.uint8))
    sw4_2, _ = mk(rng.integers(16, 80, (16, 2304, 72), dtype=np.uint8))
    ms = gpu.time_kernel("nvfp4_gemv_grouped8_fast", (tiles(2304, 32), 8, 1), 256,
                         [x8_1152, w4_2, sw4_2, ids_p, aw_p, lut_p, c8_2304], (1152, 2304, 1152))
    rec("nvfp4_gemv_grouped8 w2  (8x2304x1152)", ms, 8 * (2304 * 576 + 2304 * 72 + 2304 * 4))

    # Grouped 8-expert MXFP8 w13 & w2
    w8_13, _ = mk(rng.integers(16, 80, (16, 2304, 2304), dtype=np.uint8))
    sw8_13, _ = mk(rng.integers(125, 130, (16, 72, 72), dtype=np.uint8))
    ms = gpu.time_kernel("mxfp8_gemv_grouped8_fast", (tiles(2304, 32), 8, 1), 256,
                         [x2304, w8_13, sw8_13, ids_p, lut_p, c8_2304], (2304, 2304, 0))
    rec("mxfp8_gemv_grouped8 w13 (8x2304x2304)", ms, 8 * (2304 * 2304 + 72 * 72 + 2304 * 4))

    w8_2, _ = mk(rng.integers(16, 80, (16, 2304, 1152), dtype=np.uint8))
    sw8_2, _ = mk(rng.integers(125, 130, (16, 72, 36), dtype=np.uint8))
    ms = gpu.time_kernel("mxfp8_gemv_grouped8_fast", (tiles(2304, 32), 8, 1), 256,
                         [x8_1152, w8_2, sw8_2, ids_p, lut_p, c8_2304], (1152, 2304, 1152))
    rec("mxfp8_gemv_grouped8 w2  (8x2304x1152)", ms, 8 * (2304 * 1152 + 72 * 36 + 2304 * 4))

    # Fused BF16 Flash-Decode Attention (3:1 GQA)
    qp, _ = mk(rng.standard_normal((1, 24, 128)).astype(np.float32))
    relp, _ = mk(rng.standard_normal((1, 24, 1024)).astype(np.float32))
    sinkp, _ = mk(rng.standard_normal((1, 24)).astype(np.float32))
    op, _ = mk(np.zeros((1, 24, 128), dtype=np.float32))
    for label, T, W in [("attn_flash_bf16 SWA  (T=1024, W=1024)", 1024, 1024),
                        ("attn_flash_bf16 FULL (T=4096, W=0)", 4096, 0),
                        ("attn_flash_bf16 FULL (T=8192, W=0)", 8192, 0)]:
        kp, _ = mk(rand_bf16_u16(rng, (1, 8, T, 128)))
        vp, _ = mk(rand_bf16_u16(rng, (1, 8, T, 128)))
        ms = gpu.time_kernel("inkling_attn_flash_bf16", (24, 1, 1), 256,
                             [qp, kp, vp, relp, sinkp, op], (24, 8, T, 1024, T - 1, W), warmup=3, iters=15)
        rec(label, ms, 2 * 8 * T * 128 * 2 + 24 * min(T, 1024) * 4)

    # Split-K BF16 Flash-Decode Attention (3:1 GQA, bar0 K + bar2 V async overlap)
    pml_b, _ = mk(np.zeros((1, 24, 8, 2), dtype=np.float32))
    po_b, _ = mk(np.zeros((1, 24, 8, 128), dtype=np.float32))
    for label, T, W, S_val in [("attn_split_bf16 SWA  (T=1024, S=2)", 1024, 1024, 2),
                               ("attn_split_bf16 FULL (T=4096, S=4)", 4096, 0, 4),
                               ("attn_split_bf16 FULL (T=8192, S=8)", 8192, 0, 8)]:
        kp, _ = mk(rand_bf16_u16(rng, (1, 8, T, 128)))
        vp, _ = mk(rand_bf16_u16(rng, (1, 8, T, 128)))
        for _ in range(3):
            gpu.launch("inkling_attn_flash_split_bf16", (24, S_val, 1), 256,
                       [qp, kp, vp, relp, pml_b, po_b], (24, 8, T, 1024, T - 1, W, S_val))
            gpu.launch("inkling_attn_reduce_bf16", (24, 1, 1), 32, [pml_b, po_b, sinkp, qp, op], (24, S_val))
        gpu.sync()
        gpu.call("cuEventRecord", gpu.ev0, gpu.stream)
        for _ in range(15):
            gpu.launch("inkling_attn_flash_split_bf16", (24, S_val, 1), 256,
                       [qp, kp, vp, relp, pml_b, po_b], (24, 8, T, 1024, T - 1, W, S_val))
            gpu.launch("inkling_attn_reduce_bf16", (24, 1, 1), 32, [pml_b, po_b, sinkp, qp, op], (24, S_val))
        gpu.call("cuEventRecord", gpu.ev1, gpu.stream)
        gpu.call("cuEventSynchronize", gpu.ev1)
        ms_s = ct.c_float()
        gpu.call("cuEventElapsedTime", ct.byref(ms_s), gpu.ev0, gpu.ev1)
        rec(label, ms_s.value / 15.0, 2 * 8 * T * 128 * 2 + 24 * min(T, 1024) * 4)

    # Fast Glue: attn_res_fast, rms_norm_fast, router_fast, router_top8_fast, l2_clip_fast, softcap_swiglu8_fast, quantizers
    vbp, _ = mk(rng.standard_normal((1, 6, 2304)).astype(np.float32))
    qrp, _ = mk(rng.standard_normal((4, 2304)).astype(np.float32))
    orp, _ = mk(np.zeros((1, 4, 2304), dtype=np.float32))
    ms = gpu.time_kernel("attn_res_fast", (4, 1, 1), 256, [vbp, qrp, orp], (6, 4, 2304))
    rec("attn_res_fast LDG128 (K=6, Q=4, D=2304)", ms, (6 + 4 + 4) * 2304 * 4)

    gnp, _ = mk(np.ones(2304, dtype=np.float32))
    ms = gpu.time_kernel("rms_norm_fast", (1, 1, 1), 256, [x2304, gnp, y2304], (2304,))
    rec("rms_norm_fast (D=2304, fused)", ms, 3 * 2304 * 4)

    wgp, _ = mk(rand_bf16_u16(rng, (128, 2304)))
    rbp, _ = mk(rng.standard_normal(128).astype(np.float32))
    wtp, _ = mk(np.zeros(8, dtype=np.float32))
    lgp, _ = mk(np.zeros(128, dtype=np.float32))
    ms = gpu.time_kernel("router_fast", (1, 1, 1), 256, [x2304, wgp, rbp, ids_p, wtp], ())
    rec("router_fast (1-CTA BF16 128x2304)", ms, 128 * 2304 * 2 + 2304 * 4)
    for _ in range(5):
        gpu.launch("bf16_gemv_fast", (4, 1, 1), 256, [wgp, x2304, lgp], (2304, 128))
        gpu.launch("router_top8_fast", (1, 1, 1), 32, [lgp, rbp, ids_p, wtp], ())
    gpu.sync()
    gpu.call("cuEventRecord", gpu.ev0, gpu.stream)
    for _ in range(30):
        gpu.launch("bf16_gemv_fast", (4, 1, 1), 256, [wgp, x2304, lgp], (2304, 128))
        gpu.launch("router_top8_fast", (1, 1, 1), 32, [lgp, rbp, ids_p, wtp], ())
    gpu.call("cuEventRecord", gpu.ev1, gpu.stream)
    gpu.call("cuEventSynchronize", gpu.ev1)
    ms_r = ct.c_float()
    gpu.call("cuEventElapsedTime", ct.byref(ms_r), gpu.ev0, gpu.ev1)
    rec("bf16_gemv(4-CTA) + router_top8_fast", ms_r.value / 30.0, 128 * 2304 * 2 + 2304 * 4)

    stp_m, _ = mk(np.zeros((1, 2304, 3), dtype=np.float32))
    wsc_m, _ = mk(np.ones((2304, 4), dtype=np.float32) * 0.1)
    ms = gpu.time_kernel("moe_combine8_sconv_fast", (tiles(2304), 1, 1), 128, [c8_2304, stp_m, wsc_m, y2304], (2304,))
    rec("moe_combine8_sconv_fast (fused 8x2304)", ms, 16 * 2304 * 4)
    ms = gpu.time_kernel("sconv_rmsnorm_fast", (1, 1, 1), 256, [x2304, stp_m, wsc_m, gnp, y2304, y2304], ())
    rec("sconv_rmsnorm_fast (fused D=2304)", ms, 11 * 2304 * 4)

    ms = gpu.time_kernel("l2_clip_fast", (24, 1, 1), 32, [qp, None, None, op], (24, 128, f32_bits(22.627417), 0))
    rec("l2_clip_fast (24x128, 1-warp)", ms, 2 * 24 * 128 * 4)

    ms = gpu.time_kernel("softcap_swiglu8_fast", (tiles(1152), 8, 1), 128, [c8_2304, wtp, x8_1152, None], (1152,))
    rec("softcap_swiglu8_fast (8x1152)", ms, 8 * 3 * 1152 * 4)

    osp, _ = mk(np.array([0.05], dtype=np.float32))
    qpk, _ = mk(np.zeros(576 * 8, dtype=np.uint8))
    qsc, _ = mk(np.zeros(576, dtype=np.uint8))
    qrc, _ = mk(np.zeros(576 * 16, dtype=np.float32))
    ms = gpu.time_kernel("nvfp4_quant_fast", (tiles(144), 1, 1), 128, [x2304, lut_p, osp, qpk, qsc, qrc], (144,))
    rec("nvfp4_quant_fast (144 blks, D=2304)", ms, 2304 * 8 + 144 * 9)
    ms = gpu.time_kernel("nvfp4_quant_fast", (tiles(576), 1, 1), 128, [x8_1152, lut_p, osp, qpk, qsc, qrc], (576,))
    rec("nvfp4_quant_fast (576 blks, 8x1152)", ms, 8 * 1152 * 8 + 576 * 9)
    ms = gpu.time_kernel("swiglu8_nvfp4_quant_fast", (1, 8, 1), 128, [c8_2304, wtp, lut_p, osp, qpk, qsc, qrc], (1152,))
    rec("swiglu8_nvfp4_quant_fast (fused 8x1152)", ms, 8 * 2304 * 4 + 8 * 1152 * 4 + 576 * 9)
    ms = gpu.time_kernel("mxfp8_quant_fast", (tiles(288), 1, 1), 128, [x8_1152, lut_p, qpk, qsc, qrc], (288,))
    rec("mxfp8_quant_fast (288 grps, 8x1152)", ms, 8 * 1152 * 9)
    ms = gpu.time_kernel("moe_combine8", (tiles(2304), 1, 1), 128, [c8_2304, y2304], (2304,))
    rec("moe_combine8 (baseline, 8x2304)", ms, 9 * 2304 * 4)
    ms = gpu.time_kernel("attn_gate", (tiles(3072), 1, 1), 128, [x3072, x3072, y8192], (3072,))
    rec("attn_gate (baseline, 3072)", ms, 3 * 3072 * 4)
    ms = gpu.time_kernel("logit_softcap", (tiles(201024), 1, 1), 128, [y_un, y_un], (201024, f32_bits(30.0)))
    rec("logit_softcap (baseline, 201024)", ms, 2 * 201024 * 4)

    for p in ptrs:
        gpu.free(p)
    return res


def run_fast_48_layer_pipeline(gpu, lut_p, n_tokens=32):
    print(f"\n=== 3. FULL 48-LOGICAL-LAYER FAST PIPELINE (EAGER + SINGLE-SUBMIT CUDA GRAPH, {n_tokens} TOKENS) ===", flush=True)
    rng = np.random.default_rng(2026)
    ptrs = []

    def mk(arr):
        p, a = gpu.alloc(arr)
        ptrs.append(p)
        return p, a

    D, H, Hkv, HD, I, T_swa, T_full = 2304, 24, 8, 128, 1152, 1024, 4096
    h_p, h_arr = mk(rng.standard_normal(D).astype(np.float32) * 0.1)
    hn_p, _ = mk(np.zeros(D, dtype=np.float32))
    gn_p, _ = mk(np.ones(D, dtype=np.float32))
    outer_p, _ = mk(np.array([0.05], dtype=np.float32))
    aw_p, _ = mk(np.full(128, 0.002, dtype=np.float32))

    # Realistic distinct-weight allocation with ALL 128 experts across 4 banks (~3.3 GB > 135x GB10's 24 MiB L2 cache)!
    N_BANKS = 4
    w_qkv = [mk(rand_bf16_u16(rng, (8192, D)))[0] for _ in range(N_BANKS)]
    w_o = [mk(rand_bf16_u16(rng, (D, 3072)))[0] for _ in range(N_BANKS)]
    w_gate = [mk(rand_bf16_u16(rng, (128, D)))[0] for _ in range(N_BANKS)]
    w4_13 = [mk(rng.integers(0, 256, (128, 2 * I, D // 2), dtype=np.uint8))[0] for _ in range(N_BANKS)]
    sw4_13 = [mk(rng.integers(16, 64, (128, 2 * I, D // 16), dtype=np.uint8))[0] for _ in range(N_BANKS)]
    w4_2 = [mk(rng.integers(0, 256, (128, D, I // 2), dtype=np.uint8))[0] for _ in range(N_BANKS)]
    sw4_2 = [mk(rng.integers(16, 64, (128, D, I // 16), dtype=np.uint8))[0] for _ in range(N_BANKS)]
    w8_13, _ = mk(rng.integers(16, 64, (128, 2 * I, D), dtype=np.uint8))
    sw8_13, _ = mk(rng.integers(124, 128, (128, (2 * I) // 32, D // 32), dtype=np.uint8))
    w8_2, _ = mk(rng.integers(16, 64, (128, D, I), dtype=np.uint8))
    sw8_2, _ = mk(rng.integers(124, 128, (128, D // 32, I // 32), dtype=np.uint8))
    w_unembed, _ = mk(rand_bf16_u16(rng, (201024, D)))
    logits_p, _ = mk(np.zeros(201024, dtype=np.float32))
    rlogits_p, _ = mk(np.zeros(128, dtype=np.float32))
    pml_p, _ = mk(np.zeros((1, H, 4, 2), dtype=np.float32))
    po_p, _ = mk(np.zeros((1, H, 4, HD), dtype=np.float32))

    # Activations, KV (BF16), conv states, router, experts
    qkv_buf, _ = mk(np.zeros(8192, dtype=np.float32))
    q_clip, _ = mk(np.zeros((1, H, HD), dtype=np.float32))
    q_sc, _ = mk(np.ones((H, HD), dtype=np.float32))
    tau_p, _ = mk(np.array([1.0], dtype=np.float32))
    st_d, _ = mk(np.zeros((1, D, 3), dtype=np.float32))
    st_kv, _ = mk(np.zeros((1, 1024, 3), dtype=np.float32))
    w_sc, _ = mk(rng.standard_normal((D, 4)).astype(np.float32) * 0.1)
    sw_d, _ = mk(rng.standard_normal((4, 1024)).astype(np.float32) * 0.1)
    dw_d, _ = mk(rng.standard_normal((1, 8, 4)).astype(np.float32) * 0.05)

    K_swa, _ = mk(rand_bf16_u16(rng, (1, Hkv, T_swa, HD)))
    V_swa, _ = mk(rand_bf16_u16(rng, (1, Hkv, T_swa, HD)))
    K_full, _ = mk(rand_bf16_u16(rng, (1, Hkv, T_full, HD)))
    V_full, _ = mk(rand_bf16_u16(rng, (1, Hkv, T_full, HD)))
    rel_p, _ = mk(rng.standard_normal((1, H, 1024)).astype(np.float32) * 0.05)
    sink_p, _ = mk(rng.standard_normal((1, H)).astype(np.float32) * 0.1)

    bias_p, _ = mk(rng.standard_normal(128).astype(np.float32) * 0.05)
    ids_p, _ = mk(np.arange(8, dtype=np.uint32))
    wts_p, _ = mk(np.full(8, 1.0, dtype=np.float32))
    a4_pk, _ = mk(np.zeros(576 * 8, dtype=np.uint8))
    a4_sc, _ = mk(np.zeros(576, dtype=np.uint8))
    a4_rc, _ = mk(np.zeros(8 * I, dtype=np.float32))
    a8_pk, _ = mk(np.zeros(8 * I, dtype=np.uint8))
    a8_sc, _ = mk(np.zeros(288, dtype=np.uint8))
    gu8_p, _ = mk(np.zeros((8, 2 * I), dtype=np.float32))
    act8_p, _ = mk(np.zeros((8, I), dtype=np.float32))
    downs_p, _ = mk(np.zeros((1, 8, D), dtype=np.float32))
    vblk_p, _ = mk(rng.standard_normal((1, 6, D)).astype(np.float32) * 0.2)
    qres_p, _ = mk(rng.standard_normal((4, D)).astype(np.float32) * 0.1)
    ores_p, _ = mk(np.zeros((1, 4, D), dtype=np.float32))

    # Sub-slice pointers inside qkv_buf [0..3071 Q | 3072..6143 gate | 6144..7167 K | 7168..8191 V]
    p_q = qkv_buf
    p_g = ct.c_uint64(qkv_buf.value + 3072 * 4)
    p_k = ct.c_uint64(qkv_buf.value + 6144 * 4)
    p_v = ct.c_uint64(qkv_buf.value + 7168 * 4)

    logical_layers = list(range(0, 6)) + list(range(6, 18)) * 3 + list(range(18, 24))
    full_layers = {5, 11, 17, 23}
    mxfp8_layers = {20, 21, 22, 23}

    def enqueue_token(include_unembed=True):
        pos_q = 1000
        for step_idx, layer in enumerate(logical_layers):
            bk = step_idx % N_BANKS
            is_full = layer in full_layers
            is_mxfp8 = layer in mxfp8_layers
            is_loop_msg = (18 <= step_idx < 42)

            q_cnt = 3 if is_full else 1
            gpu.launch("attn_res_fast", (q_cnt, 1, 1), 256, [vblk_p, qres_p, ores_p], (6, q_cnt, D))
            if is_loop_msg:
                gpu.launch("msg_gate", (tiles(D), 1, 1), 128, [h_p, ores_p, h_p, h_p, h_p], (D,))
            gpu.launch("rms_norm_fast", (1, 1, 1), 256, [h_p, gn_p, hn_p], (D,))

            # 1 fused BF16 launch for Q | gate | K | V (8192 x 2304)
            gpu.launch("bf16_gemv_fast", (tiles(8192, 32), 1, 1), 256, [w_qkv[bk], hn_p, qkv_buf], (D, 8192))
            if is_full:
                gpu.launch("sconv_dynamic", (tiles(1024), 1, 1), 128, [p_k, st_kv, sw_d, dw_d, p_k], (1024, 7))
                gpu.launch("sconv_dynamic", (tiles(1024), 1, 1), 128, [p_v, st_kv, sw_d, dw_d, p_v], (1024, 7))
            else:
                gpu.launch("glue_sconv_fast", (tiles(1024), 1, 1), 128, [p_k, st_kv, w_sc, p_k], (1024,))
                gpu.launch("glue_sconv_fast", (tiles(1024), 1, 1), 128, [p_v, st_kv, w_sc, p_v], (1024,))
            gpu.launch("l2_clip_fast", (H, 1, 1), 32, [p_q, q_sc, tau_p if is_full else None, q_clip],
                       (H, HD, f32_bits(22.627417), 3 if is_full else 1))
            gpu.launch("l2_clip_fast", (Hkv, 1, 1), 32, [p_k, None, None, p_k], (Hkv, HD, f32_bits(22.627417), 0))

            # Split-K BF16 flash-decode + fused reduce+attn_gate (eliminates attn_gate launch!)
            T_cur = T_full if is_full else T_swa
            W_cur = 0 if is_full else 1024
            S_cur = 4 if is_full else 2
            gpu.launch("inkling_attn_flash_split_bf16", (H, S_cur, 1), 256,
                       [q_clip, K_full if is_full else K_swa, V_full if is_full else V_swa, rel_p, pml_p, po_p],
                       (H, Hkv, T_cur, 1024, pos_q, W_cur, S_cur))
            gpu.launch("inkling_attn_reduce_bf16", (H, 1, 1), 32, [pml_p, po_p, sink_p, p_g, p_q], (H, S_cur))
            gpu.launch("bf16_gemv_fast", (tiles(D, 32), 1, 1), 256, [w_o[bk], p_q, h_p], (3072, D))
            # Fused O-sconv + MLP RMSNorm (register-resident D=2304, eliminates rms_norm_fast launch!)
            gpu.launch("sconv_rmsnorm_fast", (1, 1, 1), 256, [h_p, st_d, w_sc, gn_p, h_p, hn_p], ())

            # 4-CTA BF16 router + 1-warp parallel top-8 + Grouped 8-expert MoE (LDG.E.64) + fused SwiGLU-quant + fused combine-sconv
            gpu.launch("bf16_gemv_fast", (tiles(128, 32), 1, 1), 256, [w_gate[bk], hn_p, rlogits_p], (D, 128))
            gpu.launch("router_top8_fast", (1, 1, 1), 32, [rlogits_p, bias_p, ids_p, wts_p], ())
            if not is_mxfp8:
                gpu.launch("nvfp4_quant_fast", (tiles(144), 1, 1), 128,
                           [hn_p, lut_p, outer_p, a4_pk, a4_sc, a4_rc], (144,))
                gpu.launch("nvfp4_gemv_grouped8_fast", (tiles(2 * I, 32), 8, 1), 256,
                           [a4_rc, w4_13[bk], sw4_13[bk], ids_p, aw_p, lut_p, gu8_p], (D, 2 * I, 0))
                gpu.launch("swiglu8_nvfp4_quant_fast", (1, 8, 1), 128,
                           [gu8_p, wts_p, lut_p, outer_p, a4_pk, a4_sc, a4_rc], (I,))
                gpu.launch("nvfp4_gemv_grouped8_fast", (tiles(D, 32), 8, 1), 256,
                           [a4_rc, w4_2[bk], sw4_2[bk], ids_p, aw_p, lut_p, downs_p], (I, D, I))
            else:
                gpu.launch("mxfp8_quant_fast", (tiles(72), 1, 1), 128, [hn_p, lut_p, a8_pk, a8_sc, a4_rc], (72,))
                gpu.launch("mxfp8_gemv_grouped8_fast", (tiles(2 * I, 32), 8, 1), 256,
                           [a4_rc, w8_13, sw8_13, ids_p, lut_p, gu8_p], (D, 2 * I, 0))
                gpu.launch("softcap_swiglu8_fast", (tiles(I), 8, 1), 128, [gu8_p, wts_p, act8_p, None], (I,))
                gpu.launch("mxfp8_quant_fast", (tiles(8 * 36), 1, 1), 128, [act8_p, lut_p, a8_pk, a8_sc, a4_rc], (8 * 36,))
                gpu.launch("mxfp8_gemv_grouped8_fast", (tiles(D, 32), 8, 1), 256,
                           [a4_rc, w8_2, sw8_2, ids_p, lut_p, downs_p], (I, D, I))
            gpu.launch("moe_combine8_sconv_fast", (tiles(D), 1, 1), 128, [downs_p, st_d, w_sc, h_p], (D,))

        if include_unembed:
            gpu.launch("rms_norm_fast", (1, 1, 1), 256, [h_p, gn_p, hn_p], (D,))
            gpu.launch("bf16_gemv_fast", (tiles(201024, 32), 1, 1), 256, [w_unembed, hn_p, logits_p], (D, 201024))
            gpu.launch("logit_softcap", (tiles(201024), 1, 1), 128, [logits_p, logits_p], (201024, f32_bits(30.0)))

    # A) Eager mode (48 layers, no unembed for apples-to-apples vs baseline 384.55 ms; and with unembed)
    eager_times = []
    for tok in range(8):
        t0 = time.perf_counter()
        enqueue_token(include_unembed=False)
        gpu.sync()
        eager_times.append((time.perf_counter() - t0) * 1e3)
    eager_med = float(np.median(eager_times[2:]))
    print(f"  EAGER (48 layers, no unembed):       median={eager_med:.2f} ms ({1000.0/eager_med:.2f} tok/s)", flush=True)

    # B) Single-Submit CUDA Graph (48 layers, no unembed AND full + 201k unembed!)
    out_stats = {"eager_48L_ms": round(eager_med, 2), "eager_48L_tok_s": round(1000.0 / eager_med, 2)}
    for tag, inc_un in [("graph_48L_no_unembed", False), ("graph_48L_full_201k_unembed", True)]:
        graph = ct.c_void_p()
        gexec = ct.c_void_p()
        gpu.call("cuStreamBeginCapture_v2", gpu.stream, 0)
        enqueue_token(include_unembed=inc_un)
        gpu.call("cuStreamEndCapture", gpu.stream, ct.byref(graph))
        gpu.call("cuGraphInstantiateWithFlags", ct.byref(gexec), graph, ct.c_uint64(0))
        # Warmup
        for _ in range(3):
            gpu.call("cuGraphLaunch", gexec, gpu.stream)
        gpu.sync()
        # Timed run (n_tokens consecutive tokens!)
        times = []
        for _ in range(n_tokens):
            gpu.call("cuEventRecord", gpu.ev0, gpu.stream)
            gpu.call("cuGraphLaunch", gexec, gpu.stream)
            gpu.call("cuEventRecord", gpu.ev1, gpu.stream)
            gpu.call("cuEventSynchronize", gpu.ev1)
            ms = ct.c_float()
            gpu.call("cuEventElapsedTime", ct.byref(ms), gpu.ev0, gpu.ev1)
            times.append(ms.value)
        gpu.read(h_p, h_arr)
        assert np.all(np.isfinite(h_arr)), f"Non-finite state after {tag}!"
        med = float(np.median(times))
        p95 = float(np.percentile(times, 95))
        tok_s = 1000.0 / med
        out_stats[tag] = {"median_ms": round(med, 2), "p95_ms": round(p95, 2), "tok_s": round(tok_s, 2)}
        print(f"  SINGLE-SUBMIT {tag:28s}: median={med:6.2f} ms ({tok_s:6.2f} tok/s), p95={p95:6.2f} ms | finite=OK", flush=True)
        gpu.call("cuGraphExecDestroy", gexec)
        gpu.call("cuGraphDestroy", graph)

    for p in ptrs:
        gpu.free(p)
    return out_stats


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python3 check_fast.py CUBIN_DIR")
    cubin_dir = Path(sys.argv[1])
    lut = np.fromfile(cubin_dir / "decode.f32le", dtype="<f4")
    gpu = FastGpu(cubin_dir)
    try:
        lut_p, _ = gpu.alloc(lut)
        verify_all_fast_kernels(gpu, lut, lut_p)
        micro = run_fast_benchmarks(gpu, lut_p)
        pipe = run_fast_48_layer_pipeline(gpu, lut_p, n_tokens=32)
        gpu.free(lut_p)
    finally:
        gpu.close()
    print("\n=== FAST JSON SUMMARY ===")
    print(json.dumps({"micro": micro, "pipeline": pipe}, indent=2), flush=True)


if __name__ == "__main__":
    main()
