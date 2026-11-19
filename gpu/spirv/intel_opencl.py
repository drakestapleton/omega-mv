# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run a vadd, fsum16, or gemm16 SPIR-V module and require the host reference bit for bit.

Usage: python3 gpu/spirv/intel_opencl.py <kernel> <prerequisite>

kernel is vadd, fsum16, or gemm16.
prerequisite is opencl-intel or vulkan.
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
# Same sentence as tools/uxl/run_all.py qemu_install_line().
OMC_INSTALL = (
    "omc is the pinned AArch64 binary sha256 "
    "34d611ca0415eab1728d3234911d90e74af17ba9ab0c581d559f48274d7ca6d3. "
    "On x86 Linux install qemu-user-static and binfmt-support, mount binfmt_misc, "
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


def vulkan_run(kernel, module, inputs, want):
    lib = load_lib(["libvulkan.so.1", "vulkan", "vulkan-1.dll"])
    if lib is None:
        sys.stdout.write("NOT_RUN %s vulkan: Vulkan loader not present\n" % kernel)
        return 2
    u32 = ctypes.c_uint32
    u64 = ctypes.c_uint64
    vp = ctypes.c_void_p
    sz = ctypes.c_size_t
    nb = len(inputs) + 1

    def load(getaddr, inst, name, rest, args):
        getaddr.restype = vp
        getaddr.argtypes = [vp, ctypes.c_char_p]
        addr = getaddr(inst, name)
        if not addr:
            return None
        return ctypes.CFUNCTYPE(rest, *args)(addr)

    vkGetInstanceProcAddr = lib.vkGetInstanceProcAddr
    vkCreateInstance = load(vkGetInstanceProcAddr, None, b"vkCreateInstance", u32, [vp, vp, ctypes.POINTER(vp)])
    if vkCreateInstance is None:
        sys.stdout.write("NOT_RUN %s vulkan: vkCreateInstance missing\n" % kernel)
        return 2

    class App(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("pApplicationName", ctypes.c_char_p),
            ("applicationVersion", u32), ("pEngineName", ctypes.c_char_p),
            ("engineVersion", u32), ("apiVersion", u32),
        ]

    class InstInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("pApplicationInfo", vp),
            ("enabledLayerCount", u32), ("ppEnabledLayerNames", vp),
            ("enabledExtensionCount", u32), ("ppEnabledExtensionNames", vp),
        ]

    app = App(0, None, kernel.encode("ascii"), 1, b"omega", 1, 0x00401000)
    info = InstInfo(1, None, 0, ctypes.cast(ctypes.byref(app), vp), 0, None, 0, None)
    inst = vp()
    rc = vkCreateInstance(ctypes.byref(info), None, ctypes.byref(inst))
    if rc != 0:
        sys.stdout.write("NOT_RUN %s vulkan: vkCreateInstance %s\n" % (kernel, rc))
        return 2
    enumdev = load(vkGetInstanceProcAddr, inst, b"vkEnumeratePhysicalDevices", u32, [vp, ctypes.POINTER(u32), vp])
    props_fn = load(vkGetInstanceProcAddr, inst, b"vkGetPhysicalDeviceProperties", None, [vp, vp])
    qprops = load(
        vkGetInstanceProcAddr, inst, b"vkGetPhysicalDeviceQueueFamilyProperties", None, [vp, ctypes.POINTER(u32), vp]
    )
    createdev = load(vkGetInstanceProcAddr, inst, b"vkCreateDevice", u32, [vp, vp, vp, ctypes.POINTER(vp)])
    if not all([enumdev, props_fn, qprops, createdev]):
        sys.stdout.write("NOT_RUN %s vulkan: instance procs missing\n" % kernel)
        return 2
    ndev = u32(0)
    enumdev(inst, ctypes.byref(ndev), None)
    if ndev.value == 0:
        sys.stdout.write("NOT_RUN %s vulkan: no physical device\n" % kernel)
        return 2
    devs = (vp * ndev.value)()
    enumdev(inst, ctypes.byref(ndev), ctypes.cast(devs, vp))
    best = None
    for d in devs:
        blob = ctypes.create_string_buffer(4096)
        props_fn(d, blob)
        vendor, _device, dtype = ctypes.cast(blob, ctypes.POINTER(u32))[2:5]
        name = blob.raw[20:276].split(b"\x00", 1)[0].decode("utf-8", "replace")
        nq = u32(0)
        qprops(d, ctypes.byref(nq), None)
        fam = ctypes.create_string_buffer(24 * nq.value)
        qprops(d, ctypes.byref(nq), fam)
        family = None
        for i in range(nq.value):
            flags = ctypes.cast(fam, ctypes.POINTER(u32))[i * 6]
            if flags & 2:
                family = i
                break
        if family is None:
            continue
        rank = 2
        if dtype == 4:
            rank = 0
        elif vendor == 0x8086:
            rank = 4
        elif dtype in (1, 2, 3):
            rank = 3
        cand = (rank, d, family, name, vendor)
        if best is None or cand[0] > best[0]:
            best = cand
    if best is None:
        sys.stdout.write("NOT_RUN %s vulkan: no compute queue\n" % kernel)
        return 2
    _, phys, family, name, vendor = best
    sys.stderr.write("intel_opencl: vulkan device=%s vendor=%#x\n" % (name, vendor))

    class QInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("queueFamilyIndex", u32),
            ("queueCount", u32), ("pQueuePriorities", vp),
        ]

    class DevInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("queueCreateInfoCount", u32),
            ("pQueueCreateInfos", vp), ("enabledLayerCount", u32), ("ppEnabledLayerNames", vp),
            ("enabledExtensionCount", u32), ("ppEnabledExtensionNames", vp), ("pEnabledFeatures", vp),
        ]

    prio = ctypes.c_float(1.0)
    qi = QInfo(2, None, 0, family, 1, ctypes.cast(ctypes.byref(prio), vp))
    di = DevInfo(3, None, 0, 1, ctypes.cast(ctypes.byref(qi), vp), 0, None, 0, None, None)
    dev = vp()
    rc = createdev(phys, ctypes.byref(di), None, ctypes.byref(dev))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: vkCreateDevice %s\n" % (kernel, rc))
        return 1
    getdev = load(vkGetInstanceProcAddr, inst, b"vkGetDeviceProcAddr", vp, [vp, ctypes.c_char_p])

    def dfn(n, rest, args):
        addr = getdev(dev, n)
        if not addr:
            raise RuntimeError(n.decode())
        return ctypes.CFUNCTYPE(rest, *args)(addr)

    try:
        getq = dfn(b"vkGetDeviceQueue", None, [vp, u32, u32, ctypes.POINTER(vp)])
        mkshader = dfn(b"vkCreateShaderModule", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        mkdsl = dfn(b"vkCreateDescriptorSetLayout", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        mkpl = dfn(b"vkCreatePipelineLayout", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        mkpipe = dfn(b"vkCreateComputePipelines", u32, [vp, vp, u32, vp, vp, ctypes.POINTER(vp)])
        mkpool = dfn(b"vkCreateDescriptorPool", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        allocds = dfn(b"vkAllocateDescriptorSets", u32, [vp, vp, ctypes.POINTER(vp)])
        update = dfn(b"vkUpdateDescriptorSets", None, [vp, u32, vp, u32, vp])
        mkbuf = dfn(b"vkCreateBuffer", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        reqfn = dfn(b"vkGetBufferMemoryRequirements", None, [vp, vp, vp])
        memprops = load(vkGetInstanceProcAddr, inst, b"vkGetPhysicalDeviceMemoryProperties", None, [vp, vp])
        allocmem = dfn(b"vkAllocateMemory", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        bindmem = dfn(b"vkBindBufferMemory", u32, [vp, vp, vp, u64])
        mapmem = dfn(b"vkMapMemory", u32, [vp, vp, u64, u64, u32, ctypes.POINTER(vp)])
        unmap = dfn(b"vkUnmapMemory", None, [vp, vp])
        mkcp = dfn(b"vkCreateCommandPool", u32, [vp, vp, vp, ctypes.POINTER(vp)])
        alloccb = dfn(b"vkAllocateCommandBuffers", u32, [vp, vp, ctypes.POINTER(vp)])
        begin = dfn(b"vkBeginCommandBuffer", u32, [vp, vp])
        bindpipe = dfn(b"vkCmdBindPipeline", None, [vp, u32, vp])
        bindds = dfn(b"vkCmdBindDescriptorSets", None, [vp, u32, vp, u32, u32, ctypes.POINTER(vp), u32, vp])
        dispatch = dfn(b"vkCmdDispatch", None, [vp, u32, u32, u32])
        end = dfn(b"vkEndCommandBuffer", u32, [vp])
        submit = dfn(b"vkQueueSubmit", u32, [vp, u32, vp, vp])
        wait = dfn(b"vkQueueWaitIdle", u32, [vp])
    except RuntimeError as e:
        sys.stdout.write("FAIL %s vulkan: missing %s\n" % (kernel, e))
        return 1

    class ShaderInfo(ctypes.Structure):
        _fields_ = [("sType", u32), ("pNext", vp), ("flags", u32), ("codeSize", sz), ("pCode", vp)]

    class Bind(ctypes.Structure):
        _fields_ = [
            ("binding", u32), ("descriptorType", u32), ("descriptorCount", u32),
            ("stageFlags", u32), ("pImmutableSamplers", vp),
        ]

    class DSLInfo(ctypes.Structure):
        _fields_ = [("sType", u32), ("pNext", vp), ("flags", u32), ("bindingCount", u32), ("pBindings", vp)]

    class PLInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("setLayoutCount", u32),
            ("pSetLayouts", vp), ("pushConstantRangeCount", u32), ("pPushConstantRanges", vp),
        ]

    class Stage(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("stage", u32),
            ("module", vp), ("pName", ctypes.c_char_p), ("pSpecializationInfo", vp),
        ]

    class PipeInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("stage", Stage),
            ("layout", vp), ("basePipelineHandle", vp), ("basePipelineIndex", ctypes.c_int32),
        ]

    class PoolSize(ctypes.Structure):
        _fields_ = [("type", u32), ("descriptorCount", u32)]

    class PoolInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("maxSets", u32),
            ("poolSizeCount", u32), ("pPoolSizes", vp),
        ]

    class AllocInfo(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("descriptorPool", vp),
            ("descriptorSetCount", u32), ("pSetLayouts", vp),
        ]

    class BufInfo(ctypes.Structure):
        _fields_ = [("buffer", vp), ("offset", u64), ("range", u64)]

    class Write(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("dstSet", vp), ("dstBinding", u32),
            ("dstArrayElement", u32), ("descriptorCount", u32), ("descriptorType", u32),
            ("pImageInfo", vp), ("pBufferInfo", vp), ("pTexelBufferView", vp),
        ]

    class BufCreate(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("flags", u32), ("size", u64), ("usage", u32),
            ("sharingMode", u32), ("queueFamilyIndexCount", u32), ("pQueueFamilyIndices", vp),
        ]

    class MemReq(ctypes.Structure):
        _fields_ = [("size", u64), ("alignment", u64), ("memoryTypeBits", u32)]

    class MemAlloc(ctypes.Structure):
        _fields_ = [("sType", u32), ("pNext", vp), ("allocationSize", u64), ("memoryTypeIndex", u32)]

    class PoolCreate(ctypes.Structure):
        _fields_ = [("sType", u32), ("pNext", vp), ("flags", u32), ("queueFamilyIndex", u32)]

    class CbAlloc(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("commandPool", vp), ("level", u32), ("commandBufferCount", u32),
        ]

    class BeginInfo(ctypes.Structure):
        _fields_ = [("sType", u32), ("pNext", vp), ("flags", u32), ("pInheritanceInfo", vp)]

    class Submit(ctypes.Structure):
        _fields_ = [
            ("sType", u32), ("pNext", vp), ("waitSemaphoreCount", u32), ("pWaitSemaphores", vp),
            ("pWaitDstStageMask", vp), ("commandBufferCount", u32), ("pCommandBuffers", vp),
            ("signalSemaphoreCount", u32), ("pSignalSemaphores", vp),
        ]

    code = (ctypes.c_uint32 * (len(module) // 4)).from_buffer_copy(module)
    shinfo = ShaderInfo(16, None, 0, len(module), ctypes.cast(code, vp))
    shader = vp()
    rc = mkshader(dev, ctypes.byref(shinfo), None, ctypes.byref(shader))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: shader module %s\n" % (kernel, rc))
        return 1
    binds = (Bind * nb)(*[Bind(i, 7, 1, 0x20, None) for i in range(nb)])
    dslinfo = DSLInfo(32, None, 0, nb, ctypes.cast(binds, vp))
    dsl = vp()
    rc = mkdsl(dev, ctypes.byref(dslinfo), None, ctypes.byref(dsl))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: descriptor layout %s\n" % (kernel, rc))
        return 1
    plinfo = PLInfo(30, None, 0, 1, ctypes.cast(ctypes.byref(dsl), vp), 0, None)
    layout = vp()
    rc = mkpl(dev, ctypes.byref(plinfo), None, ctypes.byref(layout))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: pipeline layout %s\n" % (kernel, rc))
        return 1
    stage = Stage(18, None, 0, 0x20, shader, kernel.encode("ascii"), None)
    pinfo = PipeInfo(29, None, 0, stage, layout, None, -1)
    pipe = vp()
    rc = mkpipe(dev, None, 1, ctypes.byref(pinfo), None, ctypes.byref(pipe))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: pipeline %s\n" % (kernel, rc))
        return 1

    memblob = ctypes.create_string_buffer(4096)
    memprops(phys, memblob)
    ntypes = ctypes.cast(memblob, ctypes.POINTER(u32))[0]
    types = ctypes.cast(ctypes.addressof(memblob) + 4, ctypes.POINTER(u32))

    def make_buf(data):
        bc = BufCreate(12, None, 0, len(data), 0x20, 0, 0, None)
        buf = vp()
        rc = mkbuf(dev, ctypes.byref(bc), None, ctypes.byref(buf))
        if rc != 0:
            raise RuntimeError("buffer %s" % rc)
        req = MemReq()
        reqfn(dev, buf, ctypes.byref(req))
        idx = None
        for i in range(min(ntypes, 32)):
            flags = types[i * 2]
            if (req.memoryTypeBits & (1 << i)) and (flags & 6) == 6:
                idx = i
                break
        if idx is None:
            raise RuntimeError("no host-visible memory")
        ma = MemAlloc(5, None, req.size, idx)
        mem = vp()
        rc = allocmem(dev, ctypes.byref(ma), None, ctypes.byref(mem))
        if rc != 0:
            raise RuntimeError("alloc %s" % rc)
        rc = bindmem(dev, buf, mem, 0)
        if rc != 0:
            raise RuntimeError("bind %s" % rc)
        ptr = vp()
        rc = mapmem(dev, mem, 0, req.size, 0, ctypes.byref(ptr))
        if rc != 0:
            raise RuntimeError("map %s" % rc)
        ctypes.memmove(ptr, data, len(data))
        unmap(dev, mem)
        return buf, mem

    try:
        buffers = []
        for data in inputs:
            buffers.append(make_buf(data))
        buffers.append(make_buf(b"\xff" * len(want)))
    except RuntimeError as e:
        sys.stdout.write("FAIL %s vulkan: %s\n" % (kernel, e))
        return 1

    psz = PoolSize(7, nb)
    poolinfo = PoolInfo(33, None, 0, 1, 1, ctypes.cast(ctypes.byref(psz), vp))
    pool = vp()
    rc = mkpool(dev, ctypes.byref(poolinfo), None, ctypes.byref(pool))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: descriptor pool %s\n" % (kernel, rc))
        return 1
    ai = AllocInfo(34, None, pool, 1, ctypes.cast(ctypes.byref(dsl), vp))
    dset = vp()
    rc = allocds(dev, ctypes.byref(ai), ctypes.byref(dset))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: allocate set %s\n" % (kernel, rc))
        return 1
    payloads = list(inputs) + [want]
    binfos = (BufInfo * nb)()
    writes = (Write * nb)()
    for i in range(nb):
        binfos[i] = BufInfo(buffers[i][0], 0, len(payloads[i]))
        writes[i] = Write(
            35, None, dset, i, 0, 1, 7, None, ctypes.cast(ctypes.byref(binfos[i]), vp), None
        )
    update(dev, nb, ctypes.cast(writes, vp), 0, None)

    cpinfo = PoolCreate(39, None, 2, family)
    cpool = vp()
    rc = mkcp(dev, ctypes.byref(cpinfo), None, ctypes.byref(cpool))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: command pool %s\n" % (kernel, rc))
        return 1
    cbinfo = CbAlloc(40, None, cpool, 0, 1)
    cb = vp()
    rc = alloccb(dev, ctypes.byref(cbinfo), ctypes.byref(cb))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: command buffer %s\n" % (kernel, rc))
        return 1
    binfo = BeginInfo(42, None, 0, None)
    rc = begin(cb, ctypes.byref(binfo))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: begin %s\n" % (kernel, rc))
        return 1
    bindpipe(cb, 1, pipe)
    bindds(cb, 1, layout, 0, 1, ctypes.byref(dset), 0, None)
    dispatch(cb, (len(want) // 4) // 64, 1, 1)
    rc = end(cb)
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: end %s\n" % (kernel, rc))
        return 1
    queue = vp()
    getq(dev, family, 0, ctypes.byref(queue))
    sub = Submit(4, None, 0, None, None, 1, ctypes.cast(ctypes.byref(cb), vp), 0, None)
    rc = submit(queue, 1, ctypes.byref(sub), None)
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: submit %s\n" % (kernel, rc))
        return 1
    rc = wait(queue)
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: wait %s\n" % (kernel, rc))
        return 1
    ptr = vp()
    outmem = buffers[-1][1]
    rc = mapmem(dev, outmem, 0, len(want), 0, ctypes.byref(ptr))
    if rc != 0:
        sys.stdout.write("FAIL %s vulkan: remap %s\n" % (kernel, rc))
        return 1
    got = ctypes.string_at(ptr, len(want))
    unmap(dev, outmem)
    return finish(got, want, kernel, "vulkan")


def main(argv):
    if len(argv) != 3 or argv[1] not in KERNELS or argv[2] not in ("opencl-intel", "vulkan"):
        sys.stderr.write(
            "usage: python3 gpu/spirv/intel_opencl.py vadd|fsum16|gemm16 opencl-intel|vulkan\n"
        )
        return 2
    kernel = argv[1]
    prereq = argv[2]
    root = repo_root()
    env = "vk" if prereq == "vulkan" else "cl"
    tmp = tempfile.mkdtemp(prefix="opencl-")
    built = build_module(root, tmp, kernel, env)
    if built == "noexec":
        return 2
    if built is None:
        return 1
    module, inputs, want = built
    if prereq == "vulkan":
        return vulkan_run(kernel, module, inputs, want)
    return opencl_run(kernel, prereq, module, inputs, want)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
