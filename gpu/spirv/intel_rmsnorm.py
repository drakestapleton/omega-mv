# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the rmsnorm SPIR-V module and require the host reference bit for bit.

Usage: python3 gpu/spirv/intel_rmsnorm.py <prerequisite>

prerequisite is one of: opencl-intel, opencl-pocl, levelzero, omega.
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

NROWS = 65536
ROW = 16
NOUT = NROWS * ROW
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


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def run_omc(root, src, out):
    omc = os.environ.get("OMC", os.path.join(root, "seed", "out", "omc"))
    if sys.platform != "linux":
        sys.stdout.write(
            "NOT_RUN rmsnorm: cannot execute %s (non-Linux host %s). %s\n"
            % (omc, sys.platform, OMC_INSTALL)
        )
        return "noexec"
    with open(src, "rb") as f:
        data = f.read()
    try:
        r = subprocess.run([omc], input=data, stdout=subprocess.PIPE)
    except OSError as exc:
        sys.stdout.write(
            "NOT_RUN rmsnorm: cannot execute %s (%s). %s\n" % (omc, exc, OMC_INSTALL)
        )
        return "noexec"
    if r.returncode != 0 or not r.stdout:
        sys.stderr.write("intel_rmsnorm: omc failed on %s\n" % src)
        return False
    with open(out, "wb") as f:
        f.write(r.stdout)
    os.chmod(out, 0o755)
    return True


def build_module(root, tmp, env):
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
    spv = os.path.join(tmp, "rmsnorm.%s.spv" % env)
    xbin = os.path.join(tmp, "x.bin")
    wbin = os.path.join(tmp, "w.bin")
    ref = os.path.join(tmp, "ref.bin")
    r = subprocess.run([emit, "rmsnorm", env], stdout=subprocess.PIPE)
    if r.returncode != 0 or len(r.stdout) < 20:
        sys.stderr.write("intel_rmsnorm: emit rmsnorm %s failed\n" % env)
        return None
    with open(spv, "wb") as f:
        f.write(r.stdout)
    r = subprocess.run([conform, "in", "rmsnorm", xbin, wbin])
    if r.returncode != 0:
        sys.stderr.write("intel_rmsnorm: conform in failed\n")
        return None
    r = subprocess.run([conform, "ref", "rmsnorm", ref])
    if r.returncode != 0:
        sys.stderr.write("intel_rmsnorm: conform ref failed\n")
        return None
    with open(xbin, "rb") as f:
        x = f.read()
    with open(wbin, "rb") as f:
        w = f.read()
    with open(ref, "rb") as f:
        want = f.read()
    with open(spv, "rb") as f:
        module = f.read()
    if len(x) != NOUT * 4 or len(w) != ROW * 4 or len(want) != NOUT * 4:
        sys.stderr.write("intel_rmsnorm: unexpected input size\n")
        return None
    return module, x, w, want


def finish(got, want, prereq):
    wrong = 0
    first = None
    for i in range(0, len(want), 4):
        if got[i : i + 4] != want[i : i + 4]:
            if first is None:
                first = i // 4
            wrong += 1
    digest = hashlib.sha256(got).hexdigest()
    if wrong:
        sys.stdout.write(
            "FAIL rmsnorm %s wrong=%d first=%d sha256=%s\n" % (prereq, wrong, first, digest)
        )
        return 1
    sys.stdout.write(
        "PASS rmsnorm %s n=%d wrong=0 sha256=%s\n" % (prereq, NOUT, digest)
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


def opencl_run(prereq, module, x, w):
    lib = load_lib(["libOpenCL.so.1", "OpenCL", "OpenCL.dll"])
    if lib is None:
        sys.stdout.write("NOT_RUN rmsnorm %s: OpenCL ICD not loaded\n" % prereq)
        return 2

    u32 = ctypes.c_uint32
    i32 = ctypes.c_int32
    vp = ctypes.c_void_p
    sz = ctypes.c_size_t
    clGetPlatformIDs = bind(lib, "clGetPlatformIDs", i32, [u32, ctypes.POINTER(vp), ctypes.POINTER(u32)])
    clGetPlatformInfo = bind(lib, "clGetPlatformInfo", i32, [vp, u32, sz, vp, ctypes.POINTER(sz)])
    clGetDeviceIDs = bind(lib, "clGetDeviceIDs", i32, [vp, ctypes.c_uint64, u32, ctypes.POINTER(vp), ctypes.POINTER(u32)])
    clGetDeviceInfo = bind(lib, "clGetDeviceInfo", i32, [vp, u32, sz, vp, ctypes.POINTER(sz)])

    def check(rc, what):
        if rc != 0:
            raise RuntimeError("%s returned %d" % (what, rc))

    nplat = u32(0)
    # -1001 is CL_PLATFORM_NOT_FOUND_KHR: the loader is installed and no vendor platform is.
    rc = clGetPlatformIDs(0, None, ctypes.byref(nplat))
    if rc == -1001 or (rc == 0 and nplat.value == 0):
        sys.stdout.write("NOT_RUN rmsnorm %s: no OpenCL platform\n" % prereq)
        return 2
    check(rc, "clGetPlatformIDs")
    Platform = ctypes.c_void_p * nplat.value
    plats = Platform()
    check(clGetPlatformIDs(nplat, ctypes.cast(plats, ctypes.POINTER(vp)), None), "clGetPlatformIDs")

    def info(fn, handle, kind):
        size = sz(0)
        check(fn(handle, kind, 0, None, ctypes.byref(size)), "info size")
        buf = ctypes.create_string_buffer(size.value + 1)
        check(fn(handle, kind, size, ctypes.cast(buf, vp), None), "info")
        return buf.value.decode("utf-8", "replace").rstrip("\x00")

    CL_PLATFORM_NAME = 0x0902
    CL_DEVICE_TYPE = 0x1000
    CL_DEVICE_NAME = 0x102B
    CL_DEVICE_VENDOR = 0x102C
    want_gpu = prereq == "opencl-intel"
    dtype = 4 if want_gpu else 2
    chosen = None
    plat_name = ""
    dev_name = ""
    for p in plats:
        name = info(clGetPlatformInfo, p, CL_PLATFORM_NAME)
        ndev = u32(0)
        if clGetDeviceIDs(p, dtype, 0, None, ctypes.byref(ndev)) != 0 or ndev.value == 0:
            continue
        Devs = vp * ndev.value
        devs = Devs()
        if clGetDeviceIDs(p, dtype, ndev, ctypes.cast(devs, ctypes.POINTER(vp)), None) != 0:
            continue
        for d in devs:
            vendor = info(clGetDeviceInfo, d, CL_DEVICE_VENDOR)
            dname = info(clGetDeviceInfo, d, CL_DEVICE_NAME)
            if want_gpu and "Intel" in vendor and "pocl" not in name.lower():
                chosen = (p, d)
                plat_name, dev_name = name, dname
                break
            if prereq == "opencl-pocl" and (
                "pocl" in name.lower() or "Portable Computing Language" in name
            ):
                chosen = (p, d)
                plat_name, dev_name = name, dname
                break
        if chosen:
            break
    if chosen is None:
        sys.stdout.write("NOT_RUN rmsnorm %s: device not present\n" % prereq)
        return 2
    sys.stderr.write("intel_rmsnorm: platform=%s device=%s\n" % (plat_name, dev_name))

    err = i32(0)
    clCreateContext = bind(
        lib, "clCreateContext", vp, [vp, u32, ctypes.POINTER(vp), vp, vp, ctypes.POINTER(i32)]
    )
    one = vp(chosen[1])
    ctx = clCreateContext(None, 1, ctypes.byref(one), None, None, ctypes.byref(err))
    if err.value != 0 or not ctx:
        sys.stdout.write("FAIL rmsnorm %s: clCreateContext %d\n" % (prereq, err.value))
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
        sys.stdout.write("FAIL rmsnorm %s: command queue %d\n" % (prereq, err.value))
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
            sys.stdout.write("NOT_RUN rmsnorm %s: runtime has no SPIR-V IL entry\n" % prereq)
            return 2
        create_il = ctypes.CFUNCTYPE(vp, vp, vp, sz, ctypes.POINTER(i32))(addr)
        err.value = 0
        prog = create_il(ctx, ctypes.cast(il, vp), len(module), ctypes.byref(err))
    if err.value != 0 or not prog:
        sys.stdout.write("FAIL rmsnorm %s: clCreateProgramWithIL %d\n" % (prereq, err.value))
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
        sys.stdout.write("FAIL rmsnorm %s: clBuildProgram %d\n" % (prereq, build))
        return 1
    clCreateKernel = bind(lib, "clCreateKernel", vp, [vp, ctypes.c_char_p, ctypes.POINTER(i32)])
    kern = clCreateKernel(prog, b"rmsnorm", ctypes.byref(err))
    if err.value != 0 or not kern:
        sys.stdout.write("FAIL rmsnorm %s: clCreateKernel %d\n" % (prereq, err.value))
        return 1

    clCreateBuffer = bind(lib, "clCreateBuffer", vp, [vp, ctypes.c_uint64, sz, vp, ctypes.POINTER(i32)])

    def buf(flags, data):
        host = ctypes.create_string_buffer(data)
        m = clCreateBuffer(ctx, flags | 32, len(data), ctypes.cast(host, vp), ctypes.byref(err))
        if err.value != 0 or not m:
            raise RuntimeError("clCreateBuffer %d" % err.value)
        return m

    try:
        bx = buf(4, x)
        bw = buf(4, w)
        by = buf(2, b"\xff" * (NOUT * 4))
    except RuntimeError as e:
        sys.stdout.write("FAIL rmsnorm %s: %s\n" % (prereq, e))
        return 1

    clSetKernelArg = bind(lib, "clSetKernelArg", i32, [vp, u32, sz, vp])

    def set_mem(i, m):
        p = vp(m)
        return clSetKernelArg(kern, i, ctypes.sizeof(vp), ctypes.byref(p))

    if set_mem(0, bx) or set_mem(1, bw) or set_mem(2, by):
        sys.stdout.write("FAIL rmsnorm %s: clSetKernelArg pointer\n" % prereq)
        return 1
    nrows = u32(NROWS)
    if clSetKernelArg(kern, 3, 4, ctypes.cast(ctypes.byref(nrows), vp)) != 0:
        sys.stdout.write("FAIL rmsnorm %s: clSetKernelArg n\n" % prereq)
        return 1
    clEnqueueNDRangeKernel = bind(
        lib,
        "clEnqueueNDRangeKernel",
        i32,
        [vp, vp, u32, ctypes.POINTER(sz), ctypes.POINTER(sz), ctypes.POINTER(sz), u32, vp, vp],
    )
    gsize = sz(NROWS)
    rc = clEnqueueNDRangeKernel(q, kern, 1, None, ctypes.byref(gsize), None, 0, None, None)
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm %s: enqueue %d\n" % (prereq, rc))
        return 1
    clEnqueueReadBuffer = bind(
        lib, "clEnqueueReadBuffer", i32, [vp, vp, u32, sz, sz, vp, u32, vp, vp]
    )
    out = ctypes.create_string_buffer(NOUT * 4)
    rc = clEnqueueReadBuffer(q, by, 1, 0, NOUT * 4, ctypes.cast(out, vp), 0, None, None)
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm %s: read %d\n" % (prereq, rc))
        return 1
    return out.raw


def levelzero_run(module, x, w, want):
    lib = load_lib(["libze_loader.so.1", "ze_loader", "ze_loader.dll"])
    if lib is None:
        sys.stdout.write("NOT_RUN rmsnorm levelzero: Level Zero loader not present\n")
        return 2
    u32 = ctypes.c_uint32
    vp = ctypes.c_void_p
    sz = ctypes.c_size_t

    def bind(name, rest, args):
        fn = getattr(lib, name, None)
        if fn is None:
            return None
        fn.restype = rest
        fn.argtypes = args
        return fn

    zeInit = bind("zeInit", u32, [u32])
    zeDriverGet = bind("zeDriverGet", u32, [ctypes.POINTER(u32), vp])
    zeDeviceGet = bind("zeDeviceGet", u32, [vp, ctypes.POINTER(u32), vp])
    if not all([zeInit, zeDriverGet, zeDeviceGet]):
        sys.stdout.write("NOT_RUN rmsnorm levelzero: loader is missing core entry points\n")
        return 2
    rc = zeInit(1)
    if rc != 0:
        sys.stdout.write("NOT_RUN rmsnorm levelzero: zeInit %s\n" % rc)
        return 2
    nd = u32(0)
    if zeDriverGet(ctypes.byref(nd), None) != 0 or nd.value == 0:
        sys.stdout.write("NOT_RUN rmsnorm levelzero: no driver\n")
        return 2
    drivers = (vp * nd.value)()
    if zeDriverGet(ctypes.byref(nd), ctypes.cast(drivers, vp)) != 0:
        sys.stdout.write("NOT_RUN rmsnorm levelzero: zeDriverGet failed\n")
        return 2

    class DevProps(ctypes.Structure):
        _fields_ = [
            ("stype", u32), ("pNext", vp), ("type", u32), ("vendorId", u32), ("deviceId", u32),
            ("flags", u32), ("subdeviceId", u32), ("coreClockRate", u32), ("maxMemAllocSize", ctypes.c_uint64),
            ("maxHardwareContexts", u32), ("maxCommandQueuePriority", u32), ("numThreadsPerEU", u32),
            ("physicalEUSimdWidth", u32), ("numEUsPerSubslice", u32), ("numSubslicesPerSlice", u32),
            ("numSlices", u32), ("timerResolution", ctypes.c_uint64), ("timestampValidBits", u32),
            ("kernelTimestampValidBits", u32), ("uuid", ctypes.c_uint8 * 16), ("name", ctypes.c_char * 256),
        ]

    class GroupProps(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("flags", u32), ("maxMemoryFillPatternSize", sz), ("numQueues", u32)]

    zeDeviceGetProperties = bind("zeDeviceGetProperties", u32, [vp, ctypes.POINTER(DevProps)])
    zeCommandQueueGroupGet = bind("zeDeviceGetCommandQueueGroupProperties", u32, [vp, ctypes.POINTER(u32), vp])
    chosen = None
    for drv in drivers:
        n = u32(0)
        if zeDeviceGet(drv, ctypes.byref(n), None) != 0 or n.value == 0:
            continue
        devs = (vp * n.value)()
        zeDeviceGet(drv, ctypes.byref(n), ctypes.cast(devs, vp))
        for d in devs:
            props = DevProps()
            props.stype = 3
            if zeDeviceGetProperties(d, ctypes.byref(props)) != 0 or props.type != 1:
                continue
            ng = u32(0)
            zeCommandQueueGroupGet(d, ctypes.byref(ng), None)
            if ng.value == 0:
                continue
            groups = (GroupProps * ng.value)()
            for g in groups:
                g.stype = 6
            zeCommandQueueGroupGet(d, ctypes.byref(ng), ctypes.cast(groups, vp))
            ordinal = None
            for i, g in enumerate(groups):
                if g.flags & 1:
                    ordinal = i
                    break
            if ordinal is None:
                continue
            rank = 1 if props.vendorId == 0x8086 else 0
            if chosen is None or rank > chosen[0]:
                chosen = (rank, drv, d, ordinal, props.name.decode("utf-8", "replace"), props.vendorId)
    if chosen is None:
        sys.stdout.write("NOT_RUN rmsnorm levelzero: no GPU compute device\n")
        return 2
    _, drv, device, ordinal, dname, vendor = chosen
    sys.stderr.write("intel_rmsnorm: levelzero device=%s vendor=%#x\n" % (dname, vendor))

    class CtxDesc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("flags", u32)]

    class QueueDesc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("ordinal", u32), ("index", u32), ("flags", u32), ("mode", u32), ("priority", u32)]

    class ListDesc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("ordinal", u32), ("flags", u32)]

    class DevAlloc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("flags", u32)]

    class ModDesc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("format", u32), ("inputSize", sz), ("pInputModule", vp), ("pBuildFlags", ctypes.c_char_p), ("pConstants", vp)]

    class KernDesc(ctypes.Structure):
        _fields_ = [("stype", u32), ("pNext", vp), ("flags", u32), ("pKernelName", ctypes.c_char_p)]

    class Groups(ctypes.Structure):
        _fields_ = [("x", u32), ("y", u32), ("z", u32)]

    zeContextCreate = bind("zeContextCreate", u32, [vp, ctypes.POINTER(CtxDesc), ctypes.POINTER(vp)])
    zeCommandQueueCreate = bind("zeCommandQueueCreate", u32, [vp, vp, ctypes.POINTER(QueueDesc), ctypes.POINTER(vp)])
    zeCommandListCreate = bind("zeCommandListCreate", u32, [vp, vp, ctypes.POINTER(ListDesc), ctypes.POINTER(vp)])
    zeMemAllocDevice = bind("zeMemAllocDevice", u32, [vp, ctypes.POINTER(DevAlloc), sz, sz, vp, ctypes.POINTER(vp)])
    zeModuleCreate = bind("zeModuleCreate", u32, [vp, vp, ctypes.POINTER(ModDesc), ctypes.POINTER(vp), ctypes.POINTER(vp)])
    zeKernelCreate = bind("zeKernelCreate", u32, [vp, ctypes.POINTER(KernDesc), ctypes.POINTER(vp)])
    zeKernelSetGroupSize = bind("zeKernelSetGroupSize", u32, [vp, u32, u32, u32])
    zeKernelSetArgumentValue = bind("zeKernelSetArgumentValue", u32, [vp, u32, sz, vp])
    zeAppendCopy = bind("zeCommandListAppendMemoryCopy", u32, [vp, vp, vp, sz, vp, u32, vp])
    zeAppendLaunch = bind("zeCommandListAppendLaunchKernel", u32, [vp, vp, ctypes.POINTER(Groups), vp, u32, vp])
    zeClose = bind("zeCommandListClose", u32, [vp])
    zeExecute = bind("zeCommandQueueExecuteCommandLists", u32, [vp, u32, ctypes.POINTER(vp), vp])
    zeSync = bind("zeCommandQueueSynchronize", u32, [vp, ctypes.c_uint64])
    needed = [zeContextCreate, zeCommandQueueCreate, zeCommandListCreate, zeMemAllocDevice, zeModuleCreate, zeKernelCreate, zeKernelSetGroupSize, zeKernelSetArgumentValue, zeAppendCopy, zeAppendLaunch, zeClose, zeExecute, zeSync]
    if not all(needed):
        sys.stdout.write("FAIL rmsnorm levelzero: loader is missing a dispatch entry\n")
        return 1

    ctx = vp()
    cd = CtxDesc(0xD, None, 0)
    rc = zeContextCreate(drv, ctypes.byref(cd), ctypes.byref(ctx))
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: zeContextCreate %s\n" % rc)
        return 1
    qd = QueueDesc(0xE, None, ordinal, 0, 0, 1, 0)
    queue = vp()
    rc = zeCommandQueueCreate(ctx, device, ctypes.byref(qd), ctypes.byref(queue))
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: queue %s\n" % rc)
        return 1
    ld = ListDesc(0xF, None, ordinal, 0)
    clist = vp()
    rc = zeCommandListCreate(ctx, device, ctypes.byref(ld), ctypes.byref(clist))
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: command list %s\n" % rc)
        return 1
    il = ctypes.create_string_buffer(module)
    md = ModDesc(0x1B, None, 0, len(module), ctypes.cast(il, vp), b"", None)
    mod = vp()
    blog = vp()
    rc = zeModuleCreate(ctx, device, ctypes.byref(md), ctypes.byref(mod), ctypes.byref(blog))
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: zeModuleCreate %s\n" % rc)
        return 1
    kd = KernDesc(0x1D, None, 0, b"rmsnorm")
    kern = vp()
    rc = zeKernelCreate(mod, ctypes.byref(kd), ctypes.byref(kern))
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: zeKernelCreate %s\n" % rc)
        return 1
    rc = zeKernelSetGroupSize(kern, 64, 1, 1)
    if rc != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: group size %s\n" % rc)
        return 1

    def alloc(n):
        p = vp()
        ad = DevAlloc(0x15, None, 0)
        rc = zeMemAllocDevice(ctx, ctypes.byref(ad), n, 64, device, ctypes.byref(p))
        if rc != 0 or not p:
            raise RuntimeError("alloc %s" % rc)
        return p

    try:
        bx = alloc(len(x))
        bw = alloc(len(w))
        by = alloc(len(want))
    except RuntimeError as e:
        sys.stdout.write("FAIL rmsnorm levelzero: %s\n" % e)
        return 1
    srcx = ctypes.create_string_buffer(x)
    srcw = ctypes.create_string_buffer(w)
    if zeAppendCopy(clist, bx, ctypes.cast(srcx, vp), len(x), None, 0, None) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: copy x\n")
        return 1
    if zeAppendCopy(clist, bw, ctypes.cast(srcw, vp), len(w), None, 0, None) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: copy w\n")
        return 1
    for i, p in enumerate((bx, bw, by)):
        slot = vp(p)
        if zeKernelSetArgumentValue(kern, i, ctypes.sizeof(vp), ctypes.byref(slot)) != 0:
            sys.stdout.write("FAIL rmsnorm levelzero: arg %d\n" % i)
            return 1
    nrows = u32(NROWS)
    if zeKernelSetArgumentValue(kern, 3, 4, ctypes.byref(nrows)) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: arg n\n")
        return 1
    groups = Groups(NROWS // 64, 1, 1)
    if zeAppendLaunch(clist, kern, ctypes.byref(groups), None, 0, None) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: launch\n")
        return 1
    dst = ctypes.create_string_buffer(len(want))
    if zeAppendCopy(clist, ctypes.cast(dst, vp), by, len(want), None, 0, None) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: copy back\n")
        return 1
    if zeClose(clist) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: close\n")
        return 1
    if zeExecute(queue, 1, ctypes.byref(clist), None) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: execute\n")
        return 1
    if zeSync(queue, 0xFFFFFFFFFFFFFFFF) != 0:
        sys.stdout.write("FAIL rmsnorm levelzero: sync\n")
        return 1
    return finish(dst.raw, want, "levelzero")



def omega_run(root, tmp, module, x, w, want):
    runner = os.path.join(tmp, "run")
    got = run_omc(root, os.path.join(root, "gpu", "spirv", "run.om"), runner)
    if got == "noexec":
        return 2
    if not got:
        sys.stdout.write("FAIL rmsnorm omega: omc failed on gpu/spirv/run.om\n")
        return 1
    spv = os.path.join(tmp, "rmsnorm.omega.spv")
    with open(spv, "wb") as f:
        f.write(module)
    xpath = os.path.join(tmp, "om_x.bin")
    wpath = os.path.join(tmp, "om_w.bin")
    out_path = os.path.join(tmp, "om_y.bin")
    with open(xpath, "wb") as f:
        f.write(x)
    with open(wpath, "wb") as f:
        f.write(w)
    r = subprocess.run([runner, spv, str(NROWS), str(NOUT), out_path, xpath, wpath])
    if r.returncode != 0:
        sys.stdout.write("FAIL rmsnorm omega: run.om exit %d\n" % r.returncode)
        return 1
    with open(out_path, "rb") as f:
        raw = f.read()
    if len(raw) != len(want):
        sys.stdout.write("FAIL rmsnorm omega: unexpected output size %d\n" % len(raw))
        return 1
    return finish(raw, want, "omega")


def main(argv):
    if len(argv) != 2 or argv[1] not in ("opencl-intel", "opencl-pocl", "levelzero", "omega"):
        sys.stderr.write(
            "usage: python3 gpu/spirv/intel_rmsnorm.py opencl-intel|opencl-pocl|levelzero|omega\n"
        )
        return 2
    prereq = argv[1]
    root = repo_root()
    env = "vk" if prereq == "omega" else "cl"
    tmp = tempfile.mkdtemp(prefix="rmsnorm-")
    built = build_module(root, tmp, env)
    if built == "noexec":
        return 2
    if built is None:
        return 1
    module, x, w, want = built
    if prereq in ("opencl-intel", "opencl-pocl"):
        got = opencl_run(prereq, module, x, w)
        if isinstance(got, int):
            return got
        return finish(got, want, prereq)
    if prereq == "levelzero":
        return levelzero_run(module, x, w, want)
    return omega_run(root, tmp, module, x, w, want)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
