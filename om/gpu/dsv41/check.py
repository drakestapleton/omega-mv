"""GB10 component parity check. Run with spark-window run python3 check.py CUBIN_DIR."""
import ctypes as ct
import os
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
                self.call("cuMemFree_v2", ptr)
            self.call("cuModuleUnload", module)


def bf16(x):
    x = np.asarray(x, dtype=np.float32)
    u = x.view(np.uint32)
    return ((u + 32767 + ((u >> 16) & 1)) & 0xffff0000).view(np.float32)


def lookup():
    values = []
    for code in range(256):
        exp, frac = (code >> 3) & 15, code & 7
        mag = frac / 512 if exp == 0 else (1 + frac / 8) * 2**(exp - 7)
        if exp == 15 and frac == 7:
            mag = np.nan
        values.append(-mag if code & 128 else mag)
    fp4 = [0., .5, 1, 1.5, 2, 3, 4, 6]
    return np.array(values + fp4 + [-v for v in fp4], np.float32)


def check(device):
    rng = np.random.default_rng(411)
    def normal(*shape):
        return rng.standard_normal(shape).astype(np.float32)

    def verify(name, grid, block, inputs, expected, scalars=(), atol=2e-5, rtol=2e-5):
        outputs = [np.full_like(ref, np.nan if ref.dtype.kind == "f" else 0xa5) for ref in expected]
        actual = device.run(name, grid, block, inputs + outputs, len(outputs), scalars)
        for ref, got in zip(expected, actual):
            np.testing.assert_allclose(got, ref, atol=atol, rtol=rtol, equal_nan=False)
        print(f"PASS {name}", flush=True)
        return actual

    b, d = 3, 5120
    x = normal(b, 4, d)
    pre, post, mat = normal(b, 4), normal(b, 4), normal(b, 4, 4)
    (mixed,) = verify("hc_pre", (40, b, 1), 128, [x, pre], [np.einsum("bid,bi->bd", x, pre)])
    verify("hc_post", (40, b, 1), 128, [mixed, x, post, mat],
           [mixed[:, None, :] * post[:, :, None] + np.einsum("bid,bij->bjd", x, mat)])
    raw, scale, bias = normal(b, 24), normal(3), normal(24)
    logits = raw * np.repeat(scale, [4, 4, 16]) + bias
    sigmoid = 1 / (1 + np.exp(-logits[:, :8]))
    mat = logits[:, 8:].reshape(b, 4, 4)
    mat = np.exp(mat - mat.max(axis=2, keepdims=True))
    mat = mat / mat.sum(axis=2, keepdims=True) + 1e-6
    mat /= mat.sum(axis=1, keepdims=True) + 1e-6
    for _ in range(19):
        mat /= mat.sum(axis=2, keepdims=True) + 1e-6
        mat /= mat.sum(axis=1, keepdims=True) + 1e-6
    verify("hc_sinkhorn", (b, 1, 1), 1, [raw, scale, bias],
           [sigmoid[:, :4] + 1e-6, sigmoid[:, 4:] * 2, mat])
    gate, up, weight = normal(b, 2304) * 12, normal(b, 2304) * 12, normal(b)
    limited = np.minimum(10, gate)
    verify("expert_act", (18, b, 1), 128, [gate, up, weight],
           [limited / (1 + np.exp(-limited)) * np.clip(up, -10, 10) * weight[:, None]])

    lut = np.fromfile(device.directory / "decode.f32le", dtype="<f4")
    np.testing.assert_array_equal(lut.view(np.uint32), lookup().view(np.uint32))
    def encode(values, table):
        mag = np.abs(values).astype(np.float64)
        mids = (table[:-1] + table[1:]).astype(np.float64) / 2
        code = np.searchsorted(mids, mag, side="left")
        tie = (code < len(mids)) & (mag == mids[np.minimum(code, len(mids)-1)])
        return (code + (tie & (code % 2 == 1)) + np.signbit(values) * (128 if len(table)==127 else 8)).astype(np.uint8)

    for name, group in [("quant_fp8", 32), ("quant_fp4", 32), ("quant_kv", 16)]:
        fp4 = name != "quant_fp8"
        values = bf16(normal(13, group) * 3)
        values[0] = 0
        values[1, :8] = [-0., .25, .75, 1.25, 1.75, 2.5, 3.5, 5.]
        values[1, 8:] = 6
        values[2] *= 2**-14
        maxval = 6 if fp4 else 448
        floor = 6*2**-9 if name == "quant_kv" else (6*2**-126 if fp4 else 1e-4)
        ratio = np.maximum(np.abs(values).max(axis=1), floor) / np.float32(maxval)
        if name == "quant_kv":
            scale_codes = encode(ratio, lut[:127])
            scales = lut[scale_codes]
        else:
            exponents = np.ceil(np.log2(ratio.astype(np.float64)))
            scale_codes = (exponents + 127).astype(np.uint8)
            scales = np.exp2(exponents).astype(np.float32)
        codes = encode(values / scales[:, None], lut[256:264] if fp4 else lut[:127])
        dequant = bf16(lut[codes.astype(int) + (256 if fp4 else 0)] * scales[:, None])
        packed = codes[:, ::2] | (codes[:, 1::2] << 4) if fp4 else codes
        verify(name, (len(values), 1, 1), group//2, [values, lut],
               [packed, scale_codes, dequant], atol=0, rtol=0)

    m, n, k = 2, 133, 64
    a = rng.integers(16, 80, (m, k), dtype=np.uint8) | (rng.integers(0, 2, (m, k), dtype=np.uint8) << 7)
    sa = rng.integers(125, 131, (m, k//32), dtype=np.uint8)
    for packed in (False, True):
        sw = rng.integers(125, 131, (n if packed else (n+31)//32, k//32), dtype=np.uint8)
        w = rng.integers(0, 16 if packed else 90, (n, k), dtype=np.uint8)
        weights = lut[256 + w.astype(int)] if packed else lut[w]
        storage = w[:, ::2] | (w[:, 1::2] << 4) if packed else w
        asc = np.repeat(np.exp2(sa.astype(np.float32) - 127), 32, axis=1)
        wsc = np.repeat(np.exp2(sw.astype(np.float32) - 127), 32, axis=1)
        if not packed:
            wsc = np.repeat(wsc, 32, axis=0)[:n]
        ref = (lut[a] * asc) @ (weights * wsc).T
        verify("fp4_gemm" if packed else "fp8_gemm", ((n+127)//128, m, 1), 128,
               [a, storage, sa, sw, lut], [ref], (k, n), atol=5e-4)

    # Dense projection, normalization and the compressed latent's two-token pooling.
    a, w = bf16(normal(3, 129)), bf16(normal(131, 129))
    verify("dense", (2, 3, 1), 128, [a, w], [a @ w.T], (129, 131), atol=3e-5)
    a, gain = bf16(normal(3, 5120)), normal(5120)
    a[2] = 0
    inv = 1 / np.sqrt(np.mean(a*a, axis=1) + 1e-20)
    (stat,) = verify("rms_stat", (3, 1, 1), 1, [a], [inv], (5120,))
    verify("rms_apply", (40, 3, 1), 128, [a, gain, stat], [a * inv[:,None] * gain], (5120,))
    # rotary_tail mutates its first parameter, whose untouched prefix also needs checking.
    for sign in (1., -1.):
        angles = normal(3, 32)
        freq = np.stack([np.cos(angles),np.sin(angles)], axis=-1)
        xs = normal(3, 2, 128)
        expected = xs.copy()
        tail = xs[..., -64:].reshape(3, 2, 32, 2)
        out = expected[..., -64:].reshape(tail.shape)
        cos, sin = freq[:,None,:,0], freq[:,None,:,1] * sign
        out[...,0] = tail[...,0]*cos - tail[...,1]*sin
        out[...,1] = tail[...,0]*sin + tail[...,1]*cos
        got, _ = device.run("rotary_tail", (2,3,1), 32, [xs, freq], 2,
                            (128, 2, np.float32(sign).view(np.uint32)))
        np.testing.assert_allclose(got, expected, atol=1e-6, rtol=1e-6)
    print("PASS rotary_tail", flush=True)
    vals, gates = normal(3,2,512), normal(3,2,512)*35
    coeff = np.exp(gates - gates.max(axis=1, keepdims=True))
    verify("compress_pair", (4,3,1), 128, [vals,gates],
           [(vals * coeff / coeff.sum(axis=1,keepdims=True)).sum(axis=1)])
    logits, bias = normal(3,384)*4, normal(384)*6
    logits[0,:] = -15
    raw = np.sqrt(np.logaddexp(0., logits))
    selected = np.argsort(-(raw + bias), axis=1, kind="stable")[:,:6].astype(np.int32)
    selected_w = np.take_along_axis(raw, selected, axis=1)
    verify("route6", (3,1,1), 1, [logits,bias],
           [selected, selected_w * 1.5 / (selected_w.sum(axis=1, keepdims=True)+1e-20)])
    code = rng.integers(0, 110, (7,256),dtype=np.uint8)
    scale = rng.integers(124,131,(7,8),dtype=np.uint8)
    shard = 180000000
    ids = np.array([shard-1,shard,shard+6,shard+7,shard+2],np.int32)
    ref = np.zeros((len(ids),256),np.float32)
    decoded = lut[code] * np.repeat(np.exp2(scale.astype(np.float32)-127),32,axis=1)
    for i,j in enumerate(ids-shard):
        if 0 <= j < len(code):
            ref[i] = decoded[j]
    verify("engram_rows",(len(ids),1,1),256,[ids,code,scale,lut],[ref],(shard,7))

    values = normal(129)
    values[:6] = np.array([0., -0., 1.00390625, 1.01171875, -1.00390625, -1.01171875])
    rounded = bf16(values)
    packed = (rounded.view(np.uint32)>>16).astype(np.uint16)
    (packed_gpu,) = verify("bf16_pack",(2,1,1),128,[values],[packed],(129,),atol=0,rtol=0)
    verify("bf16_unpack",(2,1,1),128,[packed_gpu],[rounded],(129,),atol=0,rtol=0)
    b,h,t = 3,4,19
    query, keys = bf16(normal(b,h,128)), bf16(normal(b,t,128))
    weights = bf16(normal(b,h) / np.sqrt(128*32))
    lens = np.array([19,10,0],np.uint32)
    keep = np.ones((b,3),np.int32)
    keep[0,1] = 0
    dots = bf16(np.einsum("bhd,btd->bht",query,keys))
    score = bf16(bf16(np.maximum(dots,0) * weights[:,:,None]).sum(axis=1))
    mask = (np.arange(t) < lens[:,None]) & (keep[:,np.arange(t)//8] != 0)
    score = np.where(mask,score,-np.inf)
    verify("index_scores",(1,b,1),128,[query,keys,weights,lens,keep],[score],(h,t))
    blocks = np.full((b,3),-np.inf,np.float32)
    for row in range(b):
        for col in range(3):
            blocks[row,col] = score[row,col*8:(col+1)*8].max()
        if lens[row]:
            blocks[row,(int(lens[row])-1)//8] = np.inf
    verify("candidate_blocks",(3,b,1),1,[score,lens],[blocks],(t,))
    score[0,:5] = 8  # cutoff crosses a tie
    score[1,:9] = -np.inf
    for scores, k, offset in [(score,3,128),(blocks,2,0)]:
        ids = np.full((b,k),-1,np.int32)
        mask = np.zeros_like(scores,dtype=np.int32)
        for row, entries in enumerate(scores):
            ids_sorted = np.argsort(-entries,kind="stable")[:k]
            chosen = np.sort(ids_sorted[entries[ids_sorted] > -np.inf])
            ids[row,:len(chosen)] = chosen+offset
            mask[row,chosen] = 1
        verify("top_positions",(b,1,1),1,[scores],[ids,mask],(scores.shape[1],k,offset))
    residual, keys, gain = bf16(normal(b,4,5120)), bf16(normal(b,4,5120)), normal(4,5120)
    valid = np.array([1,0,1],np.int32)
    rstd = 1/np.sqrt(np.mean(residual**2,axis=2)+1e-20) / np.sqrt(np.mean(keys**2,axis=2)+1e-20)
    dot = np.sum(residual*gain*keys,axis=2) * rstd / np.sqrt(5120)
    gate = np.where(valid[:,None],1/(1+np.exp(-np.copysign(np.sqrt(np.maximum(np.abs(dot),1e-6)),dot))),0).astype(np.float32)
    (gate_gpu,) = verify("engram_gate",(4,b,1),1,[residual,keys,gain,valid],[gate])
    v = bf16(normal(b,5120))
    ref = bf16(residual + gate_gpu[:,:,None]*v[:,None,:])
    verify("engram_add",(40,4,b),128,[residual,v,gate_gpu],[ref],atol=1e-6,rtol=0.008)

    table = bf16(normal(7,5120))
    ids = np.array([9,10,15,17],np.int32)
    rows = np.zeros((4,4,5120),np.float32)
    rows[1],rows[2] = table[0],table[5]
    verify("token_embed",(40,len(ids),1),128,[ids,(table.view(np.uint32)>>16).astype(np.uint16)],[rows],(10,7),atol=0,rtol=0)
    experts, shared = bf16(normal(3,6,5120)), bf16(normal(3,5120))
    verify("moe_sum",(40,3,1),128,[experts,shared],[bf16(experts.sum(axis=1)+shared)],atol=0,rtol=0)
    pos = np.array([1,127,260],np.uint32)
    kv, cache = normal(3,512), normal(3,128,512)
    expected_cache = cache.copy()
    expected_cache[np.arange(3),pos % 128] = kv
    expected_slots = (pos[:,None]+1+np.arange(128)) % 128
    expected_slots = np.where(expected_slots > pos[:,None], -1, expected_slots).astype(np.int32)
    got_cache, got_slots = device.run("window_step",(4,3,1),128,[kv,pos,cache,np.full((3,128),-2,np.int32)],2)
    np.testing.assert_array_equal(got_cache,expected_cache)
    np.testing.assert_array_equal(got_slots,expected_slots)
    print("PASS window_step",flush=True)

    h, t, s = 3, 7, 71
    q, kv = bf16(normal(b, h, 512)), bf16(normal(b, t, 512))
    idx = rng.integers(-1, t, (b, s), dtype=np.int32)
    idx[0, :64] = -1
    idx[1] = -1
    sink = np.array([-1, .5, 2], np.float32)
    values = kv[np.arange(b)[:, None], np.maximum(idx, 0)]
    scores = np.einsum("bhd,bsd->bhs", q, values) / np.float32(np.sqrt(512))
    scores = np.where(idx[:, None, :] < 0, -np.inf, scores)
    (scores_gpu,) = verify("sparse_scores", (s, h, b), 1, [q, kv, idx], [scores], (h, t, s))
    peak = np.full((b,h), -1e30, np.float32)
    denom = np.zeros_like(peak)
    numerator = np.zeros((b,h,512), np.float32)
    for first in range(0, s, 64):
        tile = scores[:, :, first:first+64]
        new_peak = np.maximum(peak, tile.max(axis=2))
        correction = np.exp(peak - new_peak)
        p = np.exp(tile - new_peak[:, :, None])
        denom = denom * correction + p.sum(axis=2)
        numerator = numerator * correction[:, :, None] + np.einsum("bhs,bsd->bhd", bf16(p), values[:, first:first+64])
        peak = new_peak
    with np.errstate(over="ignore"):
        denom += np.exp(sink - peak)
    ref = numerator / denom[:, :, None]
    verify("sparse_mix", (4, h, b), 128, [scores_gpu, kv, idx, sink], [ref], (h, t, s))

    # One routed expert at checkpoint widths. Each independently packed W row has two
    # nonzero weights, allowing exact expected projections without a second GPU stack.
    def quantize_vector(x):
        packed = np.empty(x.shape, np.uint8)
        scales = np.empty((x.size//32,), np.uint8)
        reconstructed = np.empty_like(x)
        return device.run("quant_fp8", (scales.size,1,1), 16,
                          [x,lut,packed,scales,reconstructed],3)

    def project_vector(packed, scales, recon, rows, offset):
        cols = packed.size
        idx = np.arange(rows,dtype=np.int32)
        i = (idx*17+offset) % cols
        j = (i+31) % cols
        mat = np.zeros((rows,cols//2),np.uint8)
        mat[idx,i//2] |= (np.uint8(2) << ((i%2)*4)).astype(np.uint8)   # +1.0
        mat[idx,j//2] |= (np.uint8(9) << ((j%2)*4)).astype(np.uint8)   # -0.5
        ws = np.full((rows,cols//32),127,np.uint8)
        (got,) = device.run("fp4_gemm",((rows+127)//128,1,1),128,
                            [packed,mat,scales,ws,lut,np.full(rows,np.nan,np.float32)],1,(cols,rows))
        np.testing.assert_array_equal(got, recon[i] - .5*recon[j])
        return bf16(got)

    packed, scales, recon = quantize_vector(bf16(normal(5120)))
    gate = project_vector(packed,scales,recon,2304,9)
    up = project_vector(packed,scales,recon,2304,42)
    weight = np.array([.375],np.float32)
    mid_ref = np.minimum(gate,10) / (1+np.exp(-np.minimum(gate,10))) * np.clip(up,-10,10) * weight
    (mid,) = device.run("expert_act",(18,1,1),128,[gate,up,weight,np.full_like(gate,np.nan)],1)
    np.testing.assert_allclose(mid,mid_ref,atol=2e-6,rtol=2e-6)
    packed, scales, recon = quantize_vector(bf16(mid))
    project_vector(packed,scales,recon,5120,91)
    print("PASS routed expert chain 5120 -> 2304 -> 5120 (synthetic weights)",flush=True)


if __name__ == "__main__":
    if not os.environ.get("SPARK_WINDOW"):
        sys.exit("Run inside the authorized GB10 correctness window")
    device = Device(sys.argv[1])
    try:
        check(device)
    finally:
        device.call("cuCtxDestroy_v2", device.ctx)
