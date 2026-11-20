# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run a vadd, fsum16, or gemm16 SPIR-V module and require the host reference bit for bit.

Usage: python3 gpu/spirv/intel_opencl.py <kernel> <prerequisite>

kernel is vadd, fsum16, or gemm16.
prerequisite is opencl-intel or omega.
Exit 0 prints PASS and means every output byte matched conform.om.
Exit 2 is NOT_RUN: the prerequisite device is missing, or omc cannot execute
(Exec format error, missing qemu, or a non-Linux host).
Exit 1 is a mismatch or a failure after omc has actually run.
No shell is involved. omc is taken from OMC or seed/out/omc, relative to the repo root.
"""

import ctypes
import hashlib
import os
import subprocess
import sys
import tempfile

N = 1048576
NROWS = 65536
def pinned_omc_sha():
    path = os.path.join(os.path.dirname(__file__), "..", "..", "seed", "out", "omc.sha256")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().split()[0]
    except OSError:
        return "b6129ed51e07dd8ef7f33e78fdff99d6c4d914e3bccdaf8b344043b95017d4f2"


# Same idea as tools/uxl/run_all.py: the pin is seed/out/omc.sha256.
OMC_INSTALL = (
    "omc is the pinned AArch64 binary sha256 "
    + pinned_omc_sha()
    + ". On x86 Linux install qemu-user-static and binfmt-support, mount binfmt_misc, "
    "and register /usr/lib/binfmt.d/qemu-aarch64.conf so the kernel runs qemu-aarch64. "
    "On Windows, use WSL with that binfmt setup."
)

# nout is the global size and the OpenCL `n` argument. fsum16 reads 16 inputs per output.
KERNELS = {
    "vadd": {"nout": N, "inputs": 2},
    "fsum16": {"nout": NROWS, "inputs": 1},
    "gemm16": {"nout": N, "inputs": 2},
}


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def run_omc(root, src, out):
    omc = os.environ.get("OMC", os.path.join(root, "seed", "out", "omc"))
    if sys.platform != "linux":
        sys.stdout.write(
            "NOT_RUN opencl: cannot execute %s (non-Linux host %s). %s\n"
            % (omc, sys.platform, OMC_INSTALL)
        )
        return "noexec"
    with open(src, "rb") as f:
        data = f.read()
    try:
        r = subprocess.run([omc], input=data, stdout=subprocess.PIPE)
    except OSError as exc:
        sys.stdout.write(
            "NOT_RUN opencl: cannot execute %s (%s). %s\n" % (omc, exc, OMC_INSTALL)
        )
        return "noexec"
    if r.returncode != 0 or not r.stdout:
        sys.stderr.write("intel_opencl: omc failed on %s\n" % src)
        return False
    with open(out, "wb") as f:
        f.write(r.stdout)
    os.chmod(out, 0o755)
    return True


def build_module(root, tmp, kernel, env):
    spec = KERNELS[kernel]
    emit = os.path.join(tmp, "emit")
    conform = os.path.join(tmp, "conform")
    for src, dest in (
        (os.path.join(root, "gpu", "spirv", "emit.om"), emit),
        (os.path.join(root, "gpu", "spirv", "conform.om"), conform),
    ):
        got = run_omc(root, src, dest)
        if got == "noexec":
            return "noexec"
        if not got:
            return None
    spv = os.path.join(tmp, "%s.%s.spv" % (kernel, env))
    r = subprocess.run([emit, kernel, env], stdout=subprocess.PIPE)
    if r.returncode != 0 or len(r.stdout) < 20:
        sys.stderr.write("intel_opencl: emit %s %s failed\n" % (kernel, env))
        return None
    with open(spv, "wb") as f:
        f.write(r.stdout)
    names = []
    for i in range(spec["inputs"]):
        names.append(os.path.join(tmp, "in%d.bin" % i))
    ref = os.path.join(tmp, "ref.bin")
    r = subprocess.run([conform, "in", kernel] + names)
    if r.returncode != 0:
        sys.stderr.write("intel_opencl: conform in %s failed\n" % kernel)
        return None
    r = subprocess.run([conform, "ref", kernel, ref])
    if r.returncode != 0:
        sys.stderr.write("intel_opencl: conform ref %s failed\n" % kernel)
        return None
    inputs = []
    for name in names:
        with open(name, "rb") as f:
            inputs.append(f.read())
    with open(ref, "rb") as f:
        want = f.read()
    with open(spv, "rb") as f:
        module = f.read()
    if len(want) != spec["nout"] * 4:
        sys.stderr.write("intel_opencl: unexpected reference size\n")
        return None
    return module, inputs, want


def finish(got, want, kernel, prereq):
    wrong = 0
    first = None
    nout = len(want) // 4
    for i in range(0, len(want), 4):
        if got[i : i + 4] != want[i : i + 4]:
            if first is None:
                first = i // 4
            wrong += 1
    digest = hashlib.sha256(got).hexdigest()
    if wrong:
        sys.stdout.write(
            "FAIL %s %s wrong=%d first=%d sha256=%s\n"
            % (kernel, prereq, wrong, first, digest)
        )
        return 1
    sys.stdout.write(
        "PASS %s %s n=%d wrong=0 sha256=%s\n" % (kernel, prereq, nout, digest)
    )
    return 0


def load_lib(names):
    for name in names:
        try:
            return ctypes.CDLL(name)
        except OSError:
            continue
    return None


def bind(lib, name, restype, argtypes):
    fn = getattr(lib, name)
    fn.restype = restype
    fn.argtypes = argtypes
    return fn


def opencl_run(kernel, prereq, module, inputs, want):
    lib = load_lib(["libOpenCL.so.1", "OpenCL", "OpenCL.dll"])
    if lib is None:
        sys.stdout.write("NOT_RUN %s %s: OpenCL ICD not loaded\n" % (kernel, prereq))
        return 2

    u32 = ctypes.c_uint32
    i32 = ctypes.c_int32
    vp = ctypes.c_void_p
    sz = ctypes.c_size_t
    clGetPlatformIDs = bind(lib, "clGetPlatformIDs", i32, [u32, ctypes.POINTER(vp), ctypes.POINTER(u32)])
    clGetPlatformInfo = bind(lib, "clGetPlatformInfo", i32, [vp, u32, sz, vp, ctypes.POINTER(sz)])
    clGetDeviceIDs = bind(
        lib, "clGetDeviceIDs", i32, [vp, ctypes.c_uint64, u32, ctypes.POINTER(vp), ctypes.POINTER(u32)]
    )
    clGetDeviceInfo = bind(lib, "clGetDeviceInfo", i32, [vp, u32, sz, vp, ctypes.POINTER(sz)])

    def check(rc, what):
        if rc != 0:
            raise RuntimeError("%s returned %d" % (what, rc))

    nplat = u32(0)
    rc = clGetPlatformIDs(0, None, ctypes.byref(nplat))
    if rc == -1001 or (rc == 0 and nplat.value == 0):
        sys.stdout.write("NOT_RUN %s %s: no OpenCL platform\n" % (kernel, prereq))
        return 2
    check(rc, "clGetPlatformIDs")
    plats = (vp * nplat.value)()
    check(clGetPlatformIDs(nplat, ctypes.cast(plats, ctypes.POINTER(vp)), None), "clGetPlatformIDs")

    def info(fn, handle, kind):
        size = sz(0)
        check(fn(handle, kind, 0, None, ctypes.byref(size)), "info size")
        buf = ctypes.create_string_buffer(size.value + 1)
        check(fn(handle, kind, size, ctypes.cast(buf, vp), None), "info")
        return buf.value.decode("utf-8", "replace").rstrip("\x00")

    chosen = None
    plat_name = ""
    dev_name = ""
    for p in plats:
        name = info(clGetPlatformInfo, p, 0x0902)
        ndev = u32(0)
        if clGetDeviceIDs(p, 4, 0, None, ctypes.byref(ndev)) != 0 or ndev.value == 0:
            continue
        devs = (vp * ndev.value)()
        if clGetDeviceIDs(p, 4, ndev, ctypes.cast(devs, ctypes.POINTER(vp)), None) != 0:
            continue
        for d in devs:
            vendor = info(clGetDeviceInfo, d, 0x102C)
            dname = info(clGetDeviceInfo, d, 0x102B)
            if "Intel" in vendor and "pocl" not in name.lower():
                chosen = (p, d)
                plat_name, dev_name = name, dname
                break
        if chosen:
            break
    if chosen is None:
        sys.stdout.write("NOT_RUN %s %s: device not present\n" % (kernel, prereq))
        return 2
    sys.stderr.write("intel_opencl: platform=%s device=%s\n" % (plat_name, dev_name))

    err = i32(0)
    clCreateContext = bind(
        lib, "clCreateContext", vp, [vp, u32, ctypes.POINTER(vp), vp, vp, ctypes.POINTER(i32)]
    )
    one = vp(chosen[1])
    ctx = clCreateContext(None, 1, ctypes.byref(one), None, None, ctypes.byref(err))
    if err.value != 0 or not ctx:
        sys.stdout.write("FAIL %s %s: clCreateContext %d\n" % (kernel, prereq, err.value))
        return 1
    clCreateCommandQueue = bind(
        lib, "clCreateCommandQueue", vp, [vp, vp, ctypes.c_uint64, ctypes.POINTER(i32)]
    )
    q = clCreateCommandQueue(ctx, chosen[1], 0, ctypes.byref(err))
    if err.value != 0 or not q:
        clCreateCommandQueueWithProperties = bind(
            lib,
            "clCreateCommandQueueWithProperties",
            vp,
            [vp, vp, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(i32)],
        )
        q = clCreateCommandQueueWithProperties(ctx, chosen[1], None, ctypes.byref(err))
    if not q:
        sys.stdout.write("FAIL %s %s: command queue %d\n" % (kernel, prereq, err.value))
        return 1

    clGetExtensionFunctionAddressForPlatform = bind(
        lib, "clGetExtensionFunctionAddressForPlatform", vp, [vp, ctypes.c_char_p]
    )
    direct = getattr(lib, "clCreateProgramWithIL", None)
    il = ctypes.create_string_buffer(module)
    prog = None
    if direct is not None:
        direct.restype = vp
        direct.argtypes = [vp, vp, sz, ctypes.POINTER(i32)]
        err.value = 0
        prog = direct(ctx, ctypes.cast(il, vp), len(module), ctypes.byref(err))
    if not prog:
        addr = clGetExtensionFunctionAddressForPlatform(chosen[0], b"clCreateProgramWithIL")
        if not addr:
            addr = clGetExtensionFunctionAddressForPlatform(chosen[0], b"clCreateProgramWithILKHR")
        if not addr:
            sys.stdout.write("NOT_RUN %s %s: runtime has no SPIR-V IL entry\n" % (kernel, prereq))
            return 2
        create_il = ctypes.CFUNCTYPE(vp, vp, vp, sz, ctypes.POINTER(i32))(addr)
        err.value = 0
        prog = create_il(ctx, ctypes.cast(il, vp), len(module), ctypes.byref(err))
    if err.value != 0 or not prog:
        sys.stdout.write("FAIL %s %s: clCreateProgramWithIL %d\n" % (kernel, prereq, err.value))
        return 1
    clBuildProgram = bind(lib, "clBuildProgram", i32, [vp, u32, ctypes.POINTER(vp), ctypes.c_char_p, vp, vp])
    dev1 = vp(chosen[1])
    build = clBuildProgram(prog, 1, ctypes.byref(dev1), b"", None, None)
    if build != 0:
        clGetProgramBuildInfo = bind(
            lib, "clGetProgramBuildInfo", i32, [vp, vp, u32, sz, vp, ctypes.POINTER(sz)]
        )
        logn = sz(0)
        clGetProgramBuildInfo(prog, chosen[1], 0x1183, 0, None, ctypes.byref(logn))
        log = ctypes.create_string_buffer(max(logn.value, 1))
        clGetProgramBuildInfo(prog, chosen[1], 0x1183, logn, ctypes.cast(log, vp), None)
        sys.stderr.write(log.value.decode("utf-8", "replace") + "\n")
        sys.stdout.write("FAIL %s %s: clBuildProgram %d\n" % (kernel, prereq, build))
        return 1
    clCreateKernel = bind(lib, "clCreateKernel", vp, [vp, ctypes.c_char_p, ctypes.POINTER(i32)])
    kern = clCreateKernel(prog, kernel.encode("ascii"), ctypes.byref(err))
    if err.value != 0 or not kern:
        sys.stdout.write("FAIL %s %s: clCreateKernel %d\n" % (kernel, prereq, err.value))
        return 1

    clCreateBuffer = bind(lib, "clCreateBuffer", vp, [vp, ctypes.c_uint64, sz, vp, ctypes.POINTER(i32)])

    def buf(flags, data):
        host = ctypes.create_string_buffer(data)
        m = clCreateBuffer(ctx, flags | 32, len(data), ctypes.cast(host, vp), ctypes.byref(err))
        if err.value != 0 or not m:
            raise RuntimeError("clCreateBuffer %d" % err.value)
        return m

    try:
        mems = [buf(4, data) for data in inputs]
        mems.append(buf(2, b"\xff" * len(want)))
    except RuntimeError as e:
        sys.stdout.write("FAIL %s %s: %s\n" % (kernel, prereq, e))
        return 1

    clSetKernelArg = bind(lib, "clSetKernelArg", i32, [vp, u32, sz, vp])

    def set_mem(i, m):
        p = vp(m)
        return clSetKernelArg(kern, i, ctypes.sizeof(vp), ctypes.byref(p))

    for i, m in enumerate(mems):
        if set_mem(i, m):
            sys.stdout.write("FAIL %s %s: clSetKernelArg pointer\n" % (kernel, prereq))
            return 1
    nout = u32(len(want) // 4)
    if clSetKernelArg(kern, len(mems), 4, ctypes.cast(ctypes.byref(nout), vp)) != 0:
        sys.stdout.write("FAIL %s %s: clSetKernelArg n\n" % (kernel, prereq))
        return 1
    clEnqueueNDRangeKernel = bind(
        lib,
        "clEnqueueNDRangeKernel",
        i32,
        [vp, vp, u32, ctypes.POINTER(sz), ctypes.POINTER(sz), ctypes.POINTER(sz), u32, vp, vp],
    )
    gsize = sz(len(want) // 4)
    rc = clEnqueueNDRangeKernel(q, kern, 1, None, ctypes.byref(gsize), None, 0, None, None)
    if rc != 0:
        sys.stdout.write("FAIL %s %s: enqueue %d\n" % (kernel, prereq, rc))
        return 1
    clEnqueueReadBuffer = bind(
        lib, "clEnqueueReadBuffer", i32, [vp, vp, u32, sz, sz, vp, u32, vp, vp]
    )
    out = ctypes.create_string_buffer(len(want))
    rc = clEnqueueReadBuffer(q, mems[-1], 1, 0, len(want), ctypes.cast(out, vp), 0, None, None)
    if rc != 0:
        sys.stdout.write("FAIL %s %s: read %d\n" % (kernel, prereq, rc))
        return 1
    return finish(out.raw, want, kernel, prereq)



def omega_run(root, tmp, kernel, module, inputs, want):
    runner = os.path.join(tmp, "run")
    got = run_omc(root, os.path.join(root, "gpu", "spirv", "run.om"), runner)
    if got == "noexec":
        return 2
    if not got:
        sys.stdout.write("FAIL %s omega: omc failed on gpu/spirv/run.om\n" % kernel)
        return 1
    spv = os.path.join(tmp, "%s.omega.spv" % kernel)
    with open(spv, "wb") as f:
        f.write(module)
    in_paths = []
    for i, data in enumerate(inputs):
        ip = os.path.join(tmp, "om_in%d.bin" % i)
        with open(ip, "wb") as f:
            f.write(data)
        in_paths.append(ip)
    out_path = os.path.join(tmp, "om_out.bin")
    nout = len(want) // 4
    cmd = [runner, spv, str(nout), str(nout), out_path] + in_paths
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.stdout.write("FAIL %s omega: run.om exit %d\n" % (kernel, r.returncode))
        return 1
    with open(out_path, "rb") as f:
        raw = f.read()
    if len(raw) != len(want):
        sys.stdout.write("FAIL %s omega: unexpected output size %d\n" % (kernel, len(raw)))
        return 1
    return finish(raw, want, kernel, "omega")


def main(argv):
    if len(argv) != 3 or argv[1] not in KERNELS or argv[2] not in ("opencl-intel", "omega"):
        sys.stderr.write(
            "usage: python3 gpu/spirv/intel_opencl.py vadd|fsum16|gemm16 opencl-intel|omega\n"
        )
        return 2
    kernel = argv[1]
    prereq = argv[2]
    root = repo_root()
    env = "vk" if prereq == "omega" else "cl"
    tmp = tempfile.mkdtemp(prefix="opencl-")
    built = build_module(root, tmp, kernel, env)
    if built == "noexec":
        return 2
    if built is None:
        return 1
    module, inputs, want = built
    if prereq == "omega":
        return omega_run(root, tmp, kernel, module, inputs, want)
    return opencl_run(kernel, prereq, module, inputs, want)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
