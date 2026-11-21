"""GB10 component parity check for Inkling-2-Mini seeded Omega kernels.
Run inside an authorized Spark window:
    spark-window run python3 om/gpu/inkling2/check.py build/inkling2
"""
import ctypes as ct
import math
import os
import struct
import sys
from pathlib import Path

import numpy as np


class Device:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.lib = ct.CDLL("libcuda.so.1")
        self.ctx = ct.c_void_p()
        self.call("cuInit", 0)
        dev = ct.c_int()
        self.call("cuDeviceGet", ct.byref(dev), 0)
        self.call("cuCtxCreate_v2", ct.byref(self.ctx), 0, dev)

    def call(self, name, *args):
        ret = getattr(self.lib, name)(*args)
        if ret:
            error = ct.c_char_p()
            self.lib.cuGetErrorName(ret, ct.byref(error))
            raise RuntimeError(f"{name}: {error.value} ({ret})")

    def run(self, name, grid, block, tensors, output_count, scalars=()):
        module, fn = ct.c_void_p(), ct.c_void_p()
        args, arrays = [], []
        self.call("cuModuleLoad", ct.byref(module), os.fsencode(self.directory / (name + ".cubin")))
        try:
            self.call("cuModuleGetFunction", ct.byref(fn), module, name.encode())
            for array in tensors:
                if array is None:
                    args.append(ct.c_uint64(0))
                    arrays.append(None)
                    continue
                array = np.ascontiguousarray(array)
                ptr = ct.c_uint64()
                self.call("cuMemAlloc_v2", ct.byref(ptr), ct.c_size_t((array.nbytes + 3) & ~3))
                args.append(ptr)
                arrays.append(array)
                self.call("cuMemcpyHtoD_v2", ptr, ct.c_void_p(array.ctypes.data), ct.c_size_t(array.nbytes))
            params = args + [ct.c_uint32(i) for i in scalars]
            argv = (ct.c_void_p * len(params))(*(ct.addressof(i) for i in params))
            self.call("cuLaunchKernel", fn, *grid, block, 1, 1, 0, None, argv, None)
            self.call("cuCtxSynchronize")
            for ptr, arr in zip(args[-output_count:], arrays[-output_count:]):
                self.call("cuMemcpyDtoH_v2", ct.c_void_p(arr.ctypes.data), ptr, ct.c_size_t(arr.nbytes))
            return arrays[-output_count:]
        finally:
            for ptr in args:
                if ptr.value:
                    self.call("cuMemFree_v2", ptr)
            self.call("cuModuleUnload", module)


def f32_bits(v):
    return struct.unpack("<I", struct.pack("<f", float(v)))[0]


def bf16(x):
    x = np.asarray(x, dtype=np.float32)
    u = x.view(np.uint32)
    return ((u + 32767 + ((u >> 16) & 1)) & 0xFFFF0000).view(np.float32)


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


def tiles(n):
    return (n + 127) // 128


def check(device):
    rng = np.random.default_rng(2026)

    def normal(*shape):
        return rng.standard_normal(shape).astype(np.float32)

    def verify(name, grid, block, inputs, expected, scalars=(), atol=2e-4, rtol=2e-4):
        outputs = [np.full_like(ref, np.nan if ref.dtype.kind == "f" else 0xA5) for ref in expected]
        actual = device.run(name, grid, block, inputs + outputs, len(outputs), scalars)
        for ref, got in zip(expected, actual):
            np.testing.assert_allclose(got, ref, atol=atol, rtol=rtol, equal_nan=False)
        print(f"PASS {name}", flush=True)
        return actual

    lut = np.fromfile(device.directory / "decode.f32le", dtype="<f4")
    np.testing.assert_array_equal(lut.view(np.uint32), lookup().view(np.uint32))

    # 1. nvfp4_quant (block-16 E2M1, E4M3 scales, fouroversix_mae)
    n_blk = 17
    x_nv = normal(n_blk, 16) * 2.5
    x_nv[0] = 0.0
    outer = np.array([0.05], dtype=np.float32)
    ref_packed = np.zeros((n_blk, 8), dtype=np.uint8)
    ref_scales = np.zeros((n_blk,), dtype=np.uint8)
    ref_recon = np.zeros((n_blk, 16), dtype=np.float32)
    for b in range(n_blk):
        row = x_nv[b]
        amax = float(np.max(np.abs(row)))
        best = None
        for div in (6.0, 4.0):
            s_raw = amax / (div * float(outer[0])) if outer[0] > 0 else 0.0
            c = int(encode_table(np.array([s_raw], np.float32), lut[:127])[0])
            sc = float(lut[c]) * float(outer[0])
            inv = 1.0 / sc if sc > 0 else 0.0
            q = encode_table(row * inv, lut[256:264])
            rec = lut[256 + q.astype(int)] * sc
            mae = float(np.sum(np.abs(row - rec)))
            if best is None or mae < best[0]:
                best = (mae, c, q, rec)
        _, c, q, rec = best
        ref_scales[b] = c
        ref_packed[b] = q[0::2] | (q[1::2] << 4)
        ref_recon[b] = rec
    verify("nvfp4_quant", (tiles(n_blk), 1, 1), 128, [x_nv, lut, outer],
           [ref_packed, ref_scales, ref_recon], (n_blk,), atol=1e-4, rtol=1e-4)

    # 2. nvfp4_gemm
    m, n, k = 2, 136, 64
    qa = rng.integers(0, 16, (m, k), dtype=np.uint8)
    qw = rng.integers(0, 16, (n, k), dtype=np.uint8)
    pa = qa[:, 0::2] | (qa[:, 1::2] << 4)
    pw = qw[:, 0::2] | (qw[:, 1::2] << 4)
    sa = rng.integers(16, 80, (m, k // 16), dtype=np.uint8)
    sw = rng.integers(16, 80, (n, k // 16), dtype=np.uint8)
    alpha = np.array([0.0125], dtype=np.float32)
    af = lut[256 + qa.astype(int)] * np.repeat(lut[sa], 16, axis=1)
    wf = lut[256 + qw.astype(int)] * np.repeat(lut[sw], 16, axis=1)
    verify("nvfp4_gemm", (tiles(n), m, 1), 128, [pa, pw, sa, sw, alpha, lut],
           [(af @ wf.T) * alpha[0]], (k, n), atol=5e-4)

    # 3. mxfp8_quant & mxfp8_gemm (layers 20..23)
    x_mx = bf16(normal(9, 32) * 3.0)
    x_mx[0] = 0.0
    ratio = np.maximum(np.abs(x_mx).max(axis=1), 1e-4) / np.float32(448.0)
    exps = np.ceil(np.log2(ratio.astype(np.float64)))
    sc_u8 = (exps + 127).astype(np.uint8)
    sc_f = np.exp2(exps).astype(np.float32)
    q8 = encode_table(x_mx / sc_f[:, None], lut[:127])
    rec8 = bf16(lut[q8.astype(int)] * sc_f[:, None])
    verify("mxfp8_quant", (9, 1, 1), 16, [x_mx, lut], [q8, sc_u8, rec8], atol=0, rtol=0)

    a8 = rng.integers(16, 80, (2, 64), dtype=np.uint8) | (rng.integers(0, 2, (2, 64), dtype=np.uint8) << 7)
    w8 = rng.integers(0, 90, (133, 64), dtype=np.uint8)
    sa8 = rng.integers(125, 131, (2, 2), dtype=np.uint8)
    sw8 = rng.integers(125, 131, (5, 2), dtype=np.uint8)
    ref8 = (lut[a8] * np.repeat(np.exp2(sa8.astype(np.float32) - 127), 32, axis=1)) @ (
        lut[w8] * np.repeat(np.repeat(np.exp2(sw8.astype(np.float32) - 127), 32, axis=0)[:133], 32, axis=1)
    ).T
    verify("mxfp8_gemm", (tiles(133), 2, 1), 128, [a8, w8, sa8, sw8, lut], [ref8], (64, 133), atol=5e-4)

    # 4. dense, rms_stat, rms_apply, rms_unweighted
    da, dw = bf16(normal(2, 129)), bf16(normal(131, 129))
    verify("dense", (tiles(131), 2, 1), 128, [da, dw], [da @ dw.T], (129, 131), atol=5e-5)

    xr, gain = normal(3, 2304), normal(2304)
    xr[2] = 0.0
    inv = 1.0 / np.sqrt(np.mean(xr * xr, axis=1) + 1e-6).astype(np.float32)
    (stat,) = verify("rms_stat", (3, 1, 1), 1, [xr], [inv], (2304,), atol=5e-5)
    verify("rms_apply", (tiles(2304), 3, 1), 128, [xr, gain, stat], [xr * inv[:, None] * gain], (2304,), atol=5e-5)
    verify("rms_unweighted", (tiles(2304), 3, 1), 128, [xr, stat], [xr * inv[:, None]], (2304,), atol=5e-5)

    # 5. l2_clip (flags=0 K-clip, flags=1 scale-only, flags=2 tau-only, flags=3 Q-scaled+log_scale;
    #    pass NULL device pointers for disabled optional buffers to prove skipped LDG.E never dereferences them)
    xh = normal(2, 24, 128) * 5.0
    xh[0, 0] *= 0.01  # unclipped head (norm < thresh)
    sc_h = normal(24, 128)
    tau = np.array([1.0, 1.15], dtype=np.float32)
    thresh = 22.627416997969522
    norm_k = np.linalg.norm(xh, axis=-1, keepdims=True)
    ref_k = xh * np.minimum(1.0, thresh / (norm_k + 1e-6))
    verify("l2_clip", (24, 2, 1), 1, [xh, None, None], [ref_k], (24, 128, f32_bits(thresh), 0), atol=2e-4)
    xhs = xh * sc_h[None, :, :]
    norm_q = np.linalg.norm(xhs, axis=-1, keepdims=True)
    ref_s = xhs * np.minimum(1.0, thresh / (norm_q + 1e-6))
    verify("l2_clip", (24, 2, 1), 1, [xh, sc_h, None], [ref_s], (24, 128, f32_bits(thresh), 1), atol=2e-4)
    ref_t = ref_k * tau[:, None, None]
    verify("l2_clip", (24, 2, 1), 1, [xh, None, tau], [ref_t], (24, 128, f32_bits(thresh), 2), atol=2e-4)
    ref_q = ref_s * tau[:, None, None]
    verify("l2_clip", (24, 2, 1), 1, [xh, sc_h, tau], [ref_q], (24, 128, f32_bits(thresh), 3), atol=2e-4)

    # 6. sconv_static & sconv_dynamic (verify both output AND in-place state shift, plus non-7 hd_shift)
    B, D = 2, 2304
    xs = normal(B, D)
    st = normal(B, D, 3)
    ws = normal(D, 4)
    conv_ref = (st[:, :, 0] * ws[:, 0] + st[:, :, 1] * ws[:, 1] + st[:, :, 2] * ws[:, 2] + xs * ws[:, 3] + xs) / math.sqrt(5.0)
    st_expected = np.stack([st[:, :, 1], st[:, :, 2], xs], axis=-1).astype(np.float32)
    st_in = st.copy()
    out_buf = np.full_like(conv_ref, np.nan, dtype=np.float32)
    got_st_ws_out = device.run("sconv_static", (tiles(D), B, 1), 128, [xs, st_in, ws, out_buf], 3, (D,))
    np.testing.assert_allclose(got_st_ws_out[2], conv_ref.astype(np.float32), atol=5e-5, rtol=2e-4)
    np.testing.assert_allclose(got_st_ws_out[0], st_expected, atol=0, rtol=0)
    print("PASS sconv_static (out + state)", flush=True)

    for Dk, hd_shift in ((1024, 7), (1024, 6), (16, 0)):
        H_dyn = Dk >> hd_shift
        hd_dyn = 1 << hd_shift
        xk = normal(B, Dk)
        stk = normal(B, Dk, 3)
        sw_d = normal(4, Dk)
        dw_d = normal(B, H_dyn, 4)
        w_eff = sw_d.T.reshape(H_dyn, hd_dyn, 4)[None, :, :, :] + dw_d[:, :, None, :]
        win = np.stack([xk, stk[:, :, 2], stk[:, :, 1], stk[:, :, 0]], axis=-1).reshape(B, H_dyn, hd_dyn, 4)
        dyn_ref = ((win * w_eff).sum(-1).reshape(B, Dk) + xk) / 3.0
        stk_expected = np.stack([stk[:, :, 1], stk[:, :, 2], xk], axis=-1).astype(np.float32)
        stk_in = stk.copy()
        dyn_out = np.full_like(dyn_ref, np.nan, dtype=np.float32)
        got_dyn = device.run("sconv_dynamic", (tiles(Dk), B, 1), 128, [xk, stk_in, sw_d, dw_d, dyn_out], 4, (Dk, hd_shift))
        np.testing.assert_allclose(got_dyn[3], dyn_ref.astype(np.float32), atol=5e-5, rtol=2e-4)
        np.testing.assert_allclose(got_dyn[0], stk_expected, atol=0, rtol=0)
        print(f"PASS sconv_dynamic (hd_shift={hd_shift}, out + state)", flush=True)

    # 7. inkling_attn_scores & inkling_attn_mix (3:1 GQA, 24 Q / 8 KV, rel_bias, window, sink)
    H, Hkv, T, R, pos_q, window = 24, 8, 12, 16, 9, 6
    Q = normal(B, H, 128) * 0.25
    K = normal(B, Hkv, T, 128) * 0.25
    V = normal(B, Hkv, T, 128) * 0.25
    rel = normal(B, H, R) * 0.1
    sinks = normal(B, H) * 0.5
    K_rep = np.repeat(K, H // Hkv, axis=1)
    V_rep = np.repeat(V, H // Hkv, axis=1)
    sc_ref = np.einsum("bhd,bhtd->bht", Q, K_rep) / math.sqrt(128.0)
    for t in range(T):
        dist = pos_q - t
        if t > pos_q or (window > 0 and dist >= window):
            sc_ref[:, :, t] = -np.inf
        elif 0 <= dist < R:
            sc_ref[:, :, t] += rel[:, :, dist]
    (sc_got,) = verify("inkling_attn_scores", (T, H, B), 1, [Q, K, rel], [sc_ref.astype(np.float32)],
                       (H, Hkv, T, R, pos_q, window), atol=1e-4)
    # Also test full-attention (window=0) with dist >= R (rel-bias skip branch).
    R_small = 4
    rel_small = rel[:, :, :R_small].copy()
    sc_full = np.einsum("bhd,bhtd->bht", Q, K_rep) / math.sqrt(128.0)
    for t in range(T):
        dist = pos_q - t
        if t > pos_q:
            sc_full[:, :, t] = -np.inf
        elif 0 <= dist < R_small:
            sc_full[:, :, t] += rel_small[:, :, dist]
    verify("inkling_attn_scores", (T, H, B), 1, [Q, K, rel_small], [sc_full.astype(np.float32)],
           (H, Hkv, T, R_small, pos_q, 0), atol=1e-4)
    comb = np.concatenate([sc_ref, sinks[:, :, None]], axis=-1)
    mx = np.max(comb, axis=-1, keepdims=True)
    ex = np.exp(comb - mx)
    probs = (ex / np.sum(ex, axis=-1, keepdims=True))[:, :, :-1]
    mix_ref = np.einsum("bht,bhtd->bhd", probs, V_rep).astype(np.float32)
    verify("inkling_attn_mix", (H, B, 1), 128, [sc_got, V, sinks], [mix_ref], (H, Hkv, T), atol=2e-4)

    # 8. attn_gate
    ga, gg = normal(3072), normal(3072)
    verify("attn_gate", (tiles(3072), 1, 1), 128, [ga, gg], [(ga / (1.0 + np.exp(-gg))).astype(np.float32)], (3072,), atol=5e-5)

    # 9. route8 (128 experts, top-8, sigmoid + bias, renorm * 8.0, including exact tie-break)
    rl = normal(B, 128)
    rb = normal(128) * 0.2
    rl[1, :] = 0.0
    rb_tie = np.zeros(128, dtype=np.float32)
    rs = 1.0 / (1.0 + np.exp(-rl))
    rk = rs + rb[None, :]
    ref_ids = np.zeros((B, 8), dtype=np.uint32)
    ref_wts = np.zeros((B, 8), dtype=np.float32)
    for b in range(B):
        order = sorted(range(128), key=lambda i: (-float(rk[b, i]), i))[:8]
        ref_ids[b] = order
        raw = rs[b, order]
        ref_wts[b] = raw / (np.sum(raw) + 1e-20) * 8.0
    verify("route8", (B, 1, 1), 1, [rl, rb], [ref_ids, ref_wts], atol=2e-4)
    # Exact tie across all 128 experts: must pick experts 0..7 in ascending order with weight 1.0 each
    tie_l = np.zeros((1, 128), dtype=np.float32)
    tie_ids = np.arange(8, dtype=np.uint32)[None, :]
    tie_wts = np.ones((1, 8), dtype=np.float32)
    verify("route8", (1, 1, 1), 1, [tie_l, rb_tie], [tie_ids, tie_wts], atol=2e-4)

    # 10. softcap_swiglu (I=1152) & moe_combine8 (D=2304)
    I = 1152
    sg, su, swt = normal(B, I) * 6.0, normal(B, I) * 15.0, normal(B)
    sw_ref = (4.0 * np.tanh(sg / 4.0)) * (1.0 / (1.0 + np.exp(-sg))) * (25.0 * np.tanh(su / 25.0)) * swt[:, None]
    verify("softcap_swiglu", (tiles(I), B, 1), 128, [sg, su, swt], [sw_ref.astype(np.float32)], (I,), atol=2e-4)

    downs = normal(B, 8, D)
    verify("moe_combine8", (tiles(D), B, 1), 128, [downs], [downs.sum(axis=1).astype(np.float32)], (D,), atol=1e-4)

    # 11. attn_res (K=1, K=5, K=16 boundary cases, Q=3 queries, D=2304)
    for K_blk, Q_cnt in ((1, 1), (5, 3), (16, 4)):
        V_blk = normal(B, K_blk, D)
        V_blk /= np.sqrt(np.mean(V_blk * V_blk, axis=-1, keepdims=True) + 1e-6)
        Q_res = normal(Q_cnt, D) * 0.5
        s_res = np.einsum("qd,bkd->bqk", Q_res, V_blk) / math.sqrt(D)
        s_res -= np.max(s_res, axis=-1, keepdims=True)
        p_res = np.exp(s_res) / np.sum(np.exp(s_res), axis=-1, keepdims=True)
        ar_ref = np.einsum("bqk,bkd->bqd", p_res, V_blk).astype(np.float32)
        verify("attn_res", (Q_cnt, B, 1), 1, [V_blk, Q_res], [ar_ref], (K_blk, Q_cnt, D), atol=2e-4)

    # 12. msg_gate & logit_softcap
    mh, mm, mf, mmsg = normal(D), normal(D), normal(D), normal(D)
    mg_ref = (1.0 - np.tanh(mf)) * mh + np.tanh(mmsg) * mm
    verify("msg_gate", (tiles(D), 1, 1), 128, [mh, mm, mf, mmsg], [mg_ref.astype(np.float32)], (D,), atol=1e-4)

    xl = normal(512) * 40.0
    verify("logit_softcap", (tiles(512), 1, 1), 128, [xl], [(30.0 * np.tanh(xl / 30.0)).astype(np.float32)],
           (512, f32_bits(30.0)), atol=2e-4)

    # 13. bf16_pack & bf16_unpack
    xb = normal(300) * 10.0
    (packed_b,) = verify("bf16_pack", (tiles(300), 1, 1), 128, [xb],
                         [(bf16(xb).view(np.uint32) >> 16).astype(np.uint16)], (300,), atol=0, rtol=0)
    verify("bf16_unpack", (tiles(300), 1, 1), 128, [packed_b], [bf16(xb)], (300,), atol=0, rtol=0)

    print("ALL 22 INKLING-2-MINI SEEDED OMEGA KERNELS PASSED")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python3 check.py CUBIN_DIR")
    check(Device(sys.argv[1]))
