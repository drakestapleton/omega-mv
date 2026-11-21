#!/usr/bin/env python3
"""Independent CPU reference verifier for DeepSeek-V4.1-Flash Layer 0 (pos=0)."""
import json
import struct
import sys
import numpy as np


def read_safetensors_header(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        return json.loads(f.read(n)), 8 + n


def load_tensor(path, header, base, name):
    info = header[name]
    b0, b1 = info["data_offsets"]
    dt = info["dtype"]
    sh = info["shape"]
    with open(path, "rb") as f:
        f.seek(base + b0)
        raw = f.read(b1 - b0)
    if dt == "F32":
        return np.frombuffer(raw, dtype="<f4").reshape(sh).copy()
    if dt == "BF16":
        u16 = np.frombuffer(raw, dtype="<u2").reshape(sh)
        return (u16.astype(np.uint32) << 16).view(np.float32).copy()
    if dt in ("F8_E4M3", "F8_E8M0", "I8", "U8"):
        return np.frombuffer(raw, dtype=np.uint8).reshape(sh).copy()
    raise ValueError(f"Unsupported dtype {dt} for {name}")


def bf16(x):
    x = np.asarray(x, dtype=np.float32)
    u = x.view(np.uint32)
    return ((u + 32767 + ((u >> 16) & 1)) & 0xFFFF0000).view(np.float32)


def make_lut():
    vals = []
    for code in range(256):
        exp, frac = (code >> 3) & 15, code & 7
        mag = frac / 512.0 if exp == 0 else (1.0 + frac / 8.0) * (2.0 ** (exp - 7))
        if exp == 15 and frac == 7:
            mag = np.nan
        vals.append(-mag if code & 128 else mag)
    fp4 = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]
    return np.array(vals + fp4 + [-v for v in fp4], dtype=np.float32)


LUT = make_lut()


def quant_fp8_recon(x):
    v = x.reshape(-1, 32).astype(np.float32)
    ratio = np.maximum(np.abs(v).max(axis=1), 1e-4) / np.float32(448.0)
    exps = np.ceil(np.log2(ratio.astype(np.float64)))
    scales = np.exp2(exps).astype(np.float32)
    tbl = LUT[:127]
    mids = (tbl[:-1] + tbl[1:]).astype(np.float64) / 2.0
    q = v / scales[:, None]
    mag = np.abs(q).astype(np.float64)
    code = np.searchsorted(mids, mag, side="left")
    tie = (code < len(mids)) & (mag == mids[np.minimum(code, len(mids) - 1)])
    code = (code + (tie & (code % 2 == 1)) + np.signbit(q) * 128).astype(np.uint8)
    recon = bf16(LUT[code] * scales[:, None])
    return recon.reshape(x.shape)


def dequant_fp8(w, s):
    n, k = w.shape
    sc = np.exp2(s.astype(np.float32) - 127.0)
    sc = np.repeat(np.repeat(sc, 32, axis=0)[:n], 32, axis=1)[:, :k]
    return LUT[w] * sc


def dequant_fp4(w_packed, s):
    n, half_k = w_packed.shape
    lo = w_packed & 0x0F
    hi = (w_packed >> 4) & 0x0F
    w = np.empty((n, half_k * 2), dtype=np.uint8)
    w[:, 0::2] = lo
    w[:, 1::2] = hi
    sc = np.repeat(np.exp2(s.astype(np.float32) - 127.0), 32, axis=1)
    return LUT[256 + w.astype(np.int32)] * sc


def fp8_linear(x, w, s):
    xq = quant_fp8_recon(x)
    wf = dequant_fp8(w, s)
    return bf16(xq @ wf.T)


def fp4_linear(x, w, s):
    xq = quant_fp8_recon(x)
    wf = dequant_fp4(w, s)
    return bf16(xq @ wf.T)


def rms_norm(x, gain, eps=1e-20):
    x = x.astype(np.float32)
    inv = np.float32(1.0) / np.sqrt(np.mean(x * x) + np.float32(eps))
    return bf16(x * inv * gain)


def hc_mixes(x, hc_fn, hc_scale, hc_base):
    flat = x.reshape(-1).astype(np.float32)
    inv = np.float32(1.0) / np.sqrt(np.mean(flat * flat) + np.float32(1e-20))
    raw = (flat @ hc_fn.T) * inv
    logits = raw * np.repeat(hc_scale, [4, 4, 16]) + hc_base
    sig = 1.0 / (1.0 + np.exp(-logits[:8]))
    mat = logits[8:].reshape(4, 4)
    mat = np.exp(mat - mat.max(axis=1, keepdims=True))
    mat = mat / mat.sum(axis=1, keepdims=True) + 1e-6
    mat = mat / (mat.sum(axis=0, keepdims=True) + 1e-6)
    for _ in range(19):
        mat = mat / (mat.sum(axis=1, keepdims=True) + 1e-6)
        mat = mat / (mat.sum(axis=0, keepdims=True) + 1e-6)
    return (sig[:4] + 1e-6).astype(np.float32), (sig[4:] * 2.0).astype(np.float32), mat.astype(np.float32)


def main():
    ckpt, tok_id, gpu_bin = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    s2 = f"{ckpt}/model-00002-of-00048.safetensors"
    s3 = f"{ckpt}/model-00003-of-00048.safetensors"
    h2, b2 = read_safetensors_header(s2)
    h3, b3 = read_safetensors_header(s3)
    L = lambda name: load_tensor(s3, h3, b3, f"layers.0.{name}")

    # Token embedding (row tok_id)
    einfo = h2["embed.weight"]
    with open(s2, "rb") as f:
        f.seek(b2 + einfo["data_offsets"][0] + tok_id * 5120 * 2)
        emb = (np.frombuffer(f.read(5120 * 2), dtype="<u2").astype(np.uint32) << 16).view(np.float32)
    res = np.repeat(emb[None, :], 4, axis=0)
    pre_mix = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float32)

    # Attention HC
    attn_pre, attn_post, attn_comb = hc_mixes(res, L("hc_attn_fn"), L("hc_attn_scale"), L("hc_attn_base"))
    x = bf16(np.einsum("id,i->d", res, pre_mix))
    x = rms_norm(x, L("attn_norm.weight"))

    # Attention (pos=0 -> RoPE is identity!)
    qr = rms_norm(fp8_linear(x, L("attn.wq_a.weight"), L("attn.wq_a.scale")), L("attn.q_norm.weight"))
    q = fp8_linear(qr, L("attn.wq_b.weight"), L("attn.wq_b.scale")).reshape(64, 512)
    kv = quant_fp8_recon(rms_norm(fp8_linear(x, L("attn.wkv.weight"), L("attn.wkv.scale")), L("attn.kv_norm.weight")))

    # Single-position sparse attention with sink
    scores = (q @ kv) / np.float32(np.sqrt(512.0))
    sink = L("attn.attn_sink")
    peak = scores
    p = np.ones_like(scores, dtype=np.float32)
    denom = p + np.exp(sink - peak)
    o = (bf16(p)[:, None] * kv[None, :]) / denom[:, None]
    o = bf16(o)

    # Grouped wo_a + wo_b
    woa_w = L("attn.wo_a.weight").reshape(8, 1024, 4096)
    woa_s = L("attn.wo_a.scale").reshape(8, 32, 128)
    og = o.reshape(8, 4096)
    woa_out = np.concatenate([fp8_linear(og[g], woa_w[g], woa_s[g]) for g in range(8)])
    attn_out = fp8_linear(woa_out, L("attn.wo_b.weight"), L("attn.wo_b.scale"))
    res = bf16(attn_post[:, None] * attn_out[None, :] + np.einsum("id,ij->jd", res, attn_comb))

    # FFN HC + Router
    ffn_pre, ffn_post, ffn_comb = hc_mixes(res, L("hc_ffn_fn"), L("hc_ffn_scale"), L("hc_ffn_base"))
    x = bf16(np.einsum("id,i->d", res, attn_pre))
    x = rms_norm(x, L("ffn_norm.weight"))

    logits = x @ L("ffn.gate.weight").T
    raw = np.sqrt(np.logaddexp(np.float32(0.0), logits))
    bias = L("ffn.gate.bias")
    sel = np.argsort(-(raw + bias), kind="stable")[:6].astype(np.int32)
    sw = raw[sel]
    sw = sw * np.float32(1.5) / (sw.sum() + np.float32(1e-20))

    # Shared expert
    sh_g = fp8_linear(x, L("ffn.shared_experts.w1.weight"), L("ffn.shared_experts.w1.scale"))
    sh_u = fp8_linear(x, L("ffn.shared_experts.w3.weight"), L("ffn.shared_experts.w3.scale"))
    gl = np.minimum(np.float32(10.0), sh_g)
    sh_act = bf16(gl / (1.0 + np.exp(-gl)) * np.clip(sh_u, -10.0, 10.0))
    sh_out = fp8_linear(sh_act, L("ffn.shared_experts.w2.weight"), L("ffn.shared_experts.w2.scale"))

    # 6 Routed experts
    routed_sum = np.zeros(5120, dtype=np.float32)
    for k in range(6):
        e = int(sel[k])
        eg = fp4_linear(x, L(f"ffn.experts.{e}.w1.weight"), L(f"ffn.experts.{e}.w1.scale"))
        eu = fp4_linear(x, L(f"ffn.experts.{e}.w3.weight"), L(f"ffn.experts.{e}.w3.scale"))
        gl = np.minimum(np.float32(10.0), eg)
        ea = bf16(gl / (1.0 + np.exp(-gl)) * np.clip(eu, -10.0, 10.0) * sw[k])
        routed_sum += fp4_linear(ea, L(f"ffn.experts.{e}.w2.weight"), L(f"ffn.experts.{e}.w2.scale"))
    moe_out = bf16(routed_sum + sh_out)
    res_out = bf16(ffn_post[:, None] * moe_out[None, :] + np.einsum("id,ij->jd", res, ffn_comb))

    # Load GPU dump
    raw_gpu = open(gpu_bin, "rb").read()
    assert len(raw_gpu) == 81920 + 16 + 24 + 24, f"Unexpected dump size {len(raw_gpu)}"
    g_res = np.frombuffer(raw_gpu[:81920], dtype="<f4").reshape(4, 5120)
    g_pm = np.frombuffer(raw_gpu[81920:81936], dtype="<f4")
    g_ids = np.frombuffer(raw_gpu[81936:81960], dtype="<i4")
    g_wts = np.frombuffer(raw_gpu[81960:81984], dtype="<f4")

    print("CPU routed IDs:", sel.tolist())
    print("GPU routed IDs:", g_ids.tolist())
    print("CPU weights:   ", [round(float(v), 6) for v in sw])
    print("GPU weights:   ", [round(float(v), 6) for v in g_wts])
    print("pre_mix max abs diff:", float(np.max(np.abs(ffn_pre - g_pm))))
    res_diff = np.abs(res_out - g_res)
    cos = float(np.dot(res_out.ravel(), g_res.ravel()) / (np.linalg.norm(res_out) * np.linalg.norm(g_res)))
    print(f"residual max_abs={float(res_diff.max()):.6g} mean_abs={float(res_diff.mean()):.6g} cos={cos:.8f}")
    assert np.array_equal(sel, g_ids), "Routed expert IDs mismatch!"
    assert np.allclose(sw, g_wts, atol=1e-4, rtol=1e-4), "Router weights mismatch!"
    assert np.allclose(ffn_pre, g_pm, atol=1e-4, rtol=1e-4), "pre_mix mismatch!"
    assert cos > 0.9999, f"Residual cosine too low: {cos}"
    print("GATE2_LAYER0_PARITY_PASS")


if __name__ == "__main__":
    main()
