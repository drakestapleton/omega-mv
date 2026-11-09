# Native mapped memory and checked device calls

This extends the existing native-host compiler. It supports the strict Omega
27B experiment's memory prerequisite. It does not yet implement a GPU launcher,
model execution, complete state rollback or a hardware performance comparison.
The seed compiler and added tests are handwritten Omega. The existing shell
bootstrap and test orchestration remain disclosed development tools.

| Expression | Result and contract |
| --- | --- |
| `devctl fd request A off n` | Signed Linux ioctl result. `fd` is int; `request` is a literal uint; `A` is writable bytes; offsets/counts are ulong. Exact encoded size, checked range. Accepts FIONREAD, the existing encoded read/write NVRM F requests, or the five exact aien-gpu ABI1 A requests below. |
| `mapnew fd offset bytes access mode` | Positive long handle or negative Linux errno. fd is int, offset/bytes ulong, access/mode literal ints. Access 1 means read, 3 read/write. Modes 1/2 mean shared/private file; 33/34 shared/private anonymous. Anonymous mappings require fd -1 and offset zero. |
| `mapdrop handle` | Unmap the entire owned mapping. Zero on success or negative errno. Retires the slot on success; the next mapping gets a different generation. |
| `mapread handle offset A off n` | Copy n bytes from the mapping into writable byte array A. Return n as long. |
| `mapwrite handle offset A off n` | Copy n bytes from byte array A into a writable mapping. Return n as long. Read-only source views/text are accepted. |
| `devcall fd request H hoff 32 P poff n` | RM_ALLOC or RM_CONTROL only. Binds a checked writable parameter span in a private header, sets its length, and copies back non-pointer fields. Caller pointer bytes must be zero; header and parameter spans must not overlap. Parameter length is at most 1048576 bytes (1 MiB); larger lengths trap 3 (exit 103). |
| `uvmctl fd command A off n` | Literal Linux UVM request from the explicit ABI580.173.02 allowlist, with its exact writable payload length. |
| `vfioctl fd request A off n` | Literal VFIO request from the allowlist below, with its exact byte count. Signed Linux ioctl result. `fd` is int; `request` a literal uint; `A` uchar bytes. |
| `vfiomap fd A off 32` | Read-only shared mapping of one VFIO region. `A off 32` is the `vfio_region_info` returned by `DEVICE_GET_REGION_INFO`; its flags must contain READ and MMAP, and the compiler maps exactly its size at its offset. Returns a mapping handle or negative errno. `mapset`/`mapwrite` through the handle trap. |
| `vfiomapw fd A off 32` | As `vfiomap`, but the region flags must contain READ, WRITE and MMAP and the mapping is shared read/write, so `mapget`/`mapset` drive device registers (one aligned access each, DSB SY on both sides). |
| `eventfd initial` | `initial` is uint. Creates Linux eventfd2 with CLOEXEC and NONBLOCK, no semaphore mode; returns long fd or negative errno. Use existing `read`/`write` with exactly eight bytes, `waitio`/`pollfds` for readiness, and `fclose` for close. |
| `vfioirq fd request A off n` | `fd` is int acquired by successful `vfioctl GROUP_GET_DEVICE_FD`; request is literal uint15213 (GET_IRQ_INFO) or15214 (SET_IRQS). A is writable uchar bytes, offsets/counts ulong. Checks exact caller-supplied argsz and the bounded IRQ contract below. Returns signed Linux ioctl result. |
| `mapaddr handle` | The owned live mapping's base address as ulong, for driver address serialization. Does not permit access through an arbitrary integer address. Works on reservations. |
| `mapget handle offset width` | Aligned uint32 or uint64 load, returned as ulong; width is literal int4 or8. Exactly one load, bracketed by DSB SY on AArch64 or MFENCE on x86-64. Requires readable memory. |
| `mapset handle offset width value` | Aligned uint32 or uint64 store from ulong, returning long0; width is literal int4 or8. A uint32 store refuses truncation. Exactly one store, bracketed by DSB SY on AArch64 or MFENCE on x86-64. Requires writable memory. |
| `maphold address bytes` | Reserve an unused, page-aligned span with PROT_NONE and MAP_FIXED_NOREPLACE. Address is at least64KiB and the whole span is below1TiB. Return an owned handle or errno. A kernel that ignores NOREPLACE is detected by checking the returned address; an unexpected result is unmapped and returns -95. |
| `mapbind handle fd offset access` | Bind a shared file/device mapping to the entire owned reservation, with literal access1 or3. No existing data mapping may be replaced. Return long0 or errno. Failed bind with successful cleanup retires the handle. Function-mode double failure quarantines it for cleanup only (below). |
| `cpufence` | Statement, keyword 199: a standalone host CPU publication barrier, AArch64 `DSB SY`, x86-64 `MFENCE`. It orders ordinary stores, for example `mapwrite` or plain array stores, before a later `mapset` doorbell or flag. A `mapget`/`mapset` access already carries its own barriers. See OMEGESE §10, "Host CPU ordering words". Proof: `seed/host/cpufence.sh`. |
| `cpurelax` | Statement, keyword 200: spin-wait hint for a bounded `mapget` poll loop, AArch64 `YIELD`, x86-64 `PAUSE`. It gives no ordering. Proof: `seed/host/cpufence.sh`. |

### Draft aien-gpu ABI1 ioctl admission

**Trust-surface extension: Drake must approve this contract before merge.** The
shared AArch64/x86-Linux `devctl` allowlist additionally admits exactly:

| Request | Full Linux number | Direction | Writable payload bytes |
| --- | --- | --- | --- |
| `AGPU_IOCTL_INFO` | `0x80704110` (`2154840336`) | READ | 112 |
| `AGPU_IOCTL_MEM_ALLOC` | `0xc0304121` (`3224387873`) | READ/WRITE | 48 |
| `AGPU_IOCTL_MEM_FREE` | `0xc0184122` (`3222815010`) | READ/WRITE | 24 |
| `AGPU_IOCTL_CHAN_CREATE` | `0xc0484123` (`3225960739`) | READ/WRITE | 72 |
| `AGPU_IOCTL_CHAN_DESTROY` | `0xc0184124` (`3222815012`) | READ/WRITE | 24 |

Source: `aien-dev/aien-gpu`, the ABI1 UAPI imported in CUDApp at
`third_party/aien-gpu-abi1/aien_gpu_uapi.h`, last changed by
`200015e6011d3c517803968fcccab52554c671be`, file SHA-256
`1071e2a1338d258a654dc96f8c6d637db0e06fb4c47329cd73dc69fdf443eda7`.
Linux `asm-generic/ioctl.h` defines direction at bit30, type at bit8,
number at bit0 and size at bit16. READ=2 and WRITE=1. The aligned struct
layouts and `_IOC` encoding are recomputed through Wolfram; the exact
queries, results, UAPI pin and refusal matrix are recorded in
`aien-ioctl-matrix.json`.

Equality is over the **whole request**, not its type/number alone. Nonliteral
requests, changed encoded sizes/directions/types, neighbours, `BOOT`,
`ARENA_READ` and `RM_INIT` remain compiler error9 unless independently admitted
by the unchanged FIONREAD/NVRM boundary. Even an admitted request traps3 when
the writable view count is shorter or longer than its exact encoded size.
An exact-length call reaches ioctl and returns the signed Linux result.
The driver and caller still validate device identity, ABI version, reserved
fields, flags, handles, address values and state. Admission is not a payload
validator or authorization to open a GPU.

CPU-only qualification is the handwritten Omega `aien-ioctl.om`: five exact
requests, shorter/longer views, thirty encoded refusals and nonliteral
refusals; native AArch64 execution, x86-Linux execution under QEMU, and
AArch64 function-mode admission/refusal. Every executed ioctl uses fd-1,
so no driver or device is opened. Native AArch64 expects EBADF (-9).
QEMU 8.2.2 intercepts these unknown x86 requests before checking fd and
returns ENOTTY (-25); the fixture requires that exact emulated result,
not an EBADF/ENOTTY alternative. Its trace must show the five exact request
numbers, no ioctl on short/long refusal, and an ioctl after the x86 guard
mutant. This qualifies emitted admission and length guards, not x86 kernel
or driver admission. Native x86, hardware and real driver integration are
NOT_RUN. Four compiler mutants widen or narrow the allowlist or remove either
backend's exact-length guard. A mutation counts as killed only at its intended
admission or short-length assertion, never for an unrelated child/compiler failure.


### Function and program mapping contexts

`cpufence` and `cpurelax` are accepted in every function unit. An OM-2 function unit
(first line `om2`, no `fn main`) may also use `devctl`, `mapnew`, `mapdrop`, `mapread`,
`mapwrite`, `devcall`, `uvmctl`, `mapaddr`, `mapget`, `mapset`, `maphold` and `mapbind`.
These words are supported on AArch64 Linux and `target x86linux`; they remain
error9 in OM-1 function units and other targets (gate
`seed/omc/om2/fnhost/fnhost.cases`). A handle is a long; `mapaddr` exposes only its
owned live address, not general integer-pointer access.

**Program mode remains unchanged:** its private raw128-slot table uses32-byte
slots (address, length, generation, access) and eight low handle bits for slot+1.
The129th live mapping returns-24 without calling mmap.

**Function-mode context ABI (draft, Drake approval required before merge):**
entry31 of the caller's runtime table (`LDR` from `[x7,#248]` on AArch64;
`MOV` from `[r14+248]` on x86-64) is a data pointer
to four u64 header words: capacity, generation base, generation limit, zero-reserved;
then capacity32-byte slots. Capacity is1..4098. Handles use13 low bits for slot+1
and50 generation bits; each slot starts at the caller's generation base and is
incremented only on successful allocation, never beyond the header's limit.
Slot exhaustion returns-24 without mmap. A caller must initialize the table,
keep it alive and serialize accesses. Missing/invalid pointers are not checked
stub calls and can fault; entry31 must really point at this format.

The bridge gives each explicit context a distinct nonreused24-bit ID and26-bit
per-slot generations: base=`id<<26`, limit=`((id+1)<<26)-1`. This prevents a
foreign-context handle from aliasing a local generation. Default contextID1 has
128 slots. Explicit contexts admit4098:4096 C NVRM allocation mappings, one
usermode mapping and one transient slot. GPU channel VA bookkeeping uses no
CPU mmap reservation. WolframLanguageEvaluator:
`{4096+1+1,2^13-1,2^26-1,2^24-1,2^50-1,32+4098*32}`
-> `{4098,8191,67108863,16777215,1125899906842623,131168}`.
The last value is the table byte size. Context creation/destruction and read-only
dispatch-table publication are the bridge compatibility ABI, not new Omega words.
The caller quiesces all users/waiters before destruction, which refuses live
slots; it also serializes whole multi-call transactions in a context.

`mapbind` replaces only the whole live PROT_NONE reservation in this selected
table. Before cleanup, function mode changes access to4 (quarantined): bind,
read and write are refused but `mapaddr` and `mapdrop` retain ownership for
cleanup. If cleanup munmap fails, trap3 leaves that quarantined owner live and
the bridge returns nonzero status with outputs unchanged. Destroy must return36
until a later `mapdrop` succeeds. If cleanup succeeds, the slot is fully retired
and the original mmap errno is returned normally. Linux may leave a gap after
MAP_FIXED failure: reservation preservation is not promised in either case.
No external munmap/mremap/fixed replacement may interfere with owned ranges.
This format supersedes the unmerged raw128-slot function-mode draft in#1040;
mixing those compiler/runtime formats is unsupported and the bridge rejects a
mapping unit with an incompatible compiler fingerprint. Program-mode tables
and handles are not changed by this context extension.
Mappings are between 1 byte and 64 GiB each. This bounds each extent, not the
total physical memory the OS permits. Closing a file descriptor does not close
its mapping. Close the mapping explicitly before reclaiming its backing object.

Invalid/stale handles, range overflow, writes through read-only mappings, zero
or oversized extents, inaccessible reservations, misaligned word access and
malformed anonymous arguments trap with exit 103.
An array's normal bounds and mutability checks still apply. Empty copies are
allowed at the exact end of both spans, through a valid handle. Slot generation
never wraps: exhausted generations are retired permanently. File offset alignment
and device mapping permission errors come from Linux. Fixed-address binding is
limited to entire owned reservations. There is no executable map, arbitrary
syscall or access through an arbitrary integer address in this extension.

These are process-local resource handles, not an authority or sandbox boundary.
Fork inherits independent tables and Linux's ordinary shared/private map behavior;
the new process must manage its copies. A successful file mapping does not verify
the file's contents, prevent truncation, guarantee residency, or suppress Linux
mapping faults. The owner must keep mapped files/device objects valid for the
mapping's full lifetime. The model runner must freeze and verify weight identities.

Device calls use checked byte spans. `devcall` supplies one scoped parameter
pointer in a private32-byte NVOS21/NVOS54 header. It never copies that pointer
back. This work does not qualify arbitrary device commands.
The parameter cap is the default `RMAPI_PARAM_COPY_MAX_PARAMS_SIZE` in
[`param_copy.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/20e4e6e1/src/nvidia/inc/kernel/rmapi/param_copy.h#L63).
WolframLanguageEvaluator: `2^20` -> `1048576` bytes.
The runtime passes the already checked caller span directly; only the private
32-byte header is allocated on the stack, independent of parameter length.
Large callers can use image-backed `global` arrays without a stack allocation.
This does not change `devctl`: its payload size remains encoded in the ioctl request.
GPU submission and mapped-device coherency require their separate existing
runtime qualifications. Tests here open ordinary files, anonymous memory and
pipes; compiler host tests do not open a GPU device or alter a running model.

The UVM allowlist is INITIALIZE805306369/16bytes, MM_INITIALIZE75/8,
REGISTER_GPU37/40, UNREGISTER_GPU38/20, REGISTER_GPU_VASPACE25/32,
UNREGISTER_GPU_VASPACE26/20, REGISTER_CHANNEL27/56, UNREGISTER_CHANNEL28/28,
MAP_EXTERNAL_ALLOCATION33/9264, FREE34/24 and CREATE_EXTERNAL_RANGE73/24.
Only the Linux ABI from the pinned NVIDIA580.173.02 headers is covered.
Independent GCC header-layout and GNU assembler instruction oracles were used
while developing the runtime. They are not linked into the compiler or products.

The VFIO allowlist (`_IO(';', 100+k)`, Linux `include/uapi/linux/vfio.h`) is
GET_API_VERSION15204/0, CHECK_EXTENSION15205/4, SET_IOMMU15206/4 (value must be
TYPE1v2 = 3), GROUP_GET_STATUS15207/8, GROUP_SET_CONTAINER15208/4,
GROUP_GET_DEVICE_FD15210 (nonempty device name without zero bytes, copied with a
terminator to private stack memory), DEVICE_GET_INFO15211/24,
DEVICE_GET_REGION_INFO15212/32, IOMMU_MAP_DMA15217/32 and IOMMU_UNMAP_DMA15218/24
(both checked as described under DMA below). DEVICE_RESET15215 is refused: W0 is approved
without a device reset, so Omega code cannot request one. For spans of 8 bytes or
more the compiler writes `argsz = n` before the call, so the kernel copies at most
n bytes back. CHECK_EXTENSION and SET_IOMMU pass the 4-byte value read from the
span. Every other request, a non-literal request, a non-uchar span or library
mode is refused at compile time; a wrong count, a bad SET_IOMMU value or an empty
device name traps 3 at run time. IRQ requests use the separate `vfioirq` word
below; reset and migration remain excluded. Note that closing a vfio-pci device
fd lets Linux reset the function (FLR) or, when every reset method is disabled,
the bus (SBR); the allowlist cannot prevent that kernel behaviour.

### Typed IRQ and eventfd extension

The original profile extended compiler base
`397e67040fb74853c6814097fe02ae4e1ebd6f66` (the historical driver pin).
Current-main integration assigns `vfioctl`228, `vfiomap`229,
`vfiomapw`230, `eventfd`231 and `vfioirq`232, preserving the existing
efi/qty/peername/fma words. It emits AArch64 Linux syscalls directly.
These additions are program-mode only; hosted x86 VFIO and function-mode
VFIO are not implemented. Neither hardware IRQ delivery nor a driver-pin
compatibility claim follows from host qualification.

`vfioirq GET_IRQ_INFO` requires exactly16 bytes and an argsz field equal to16.
The caller supplies flags/index/count bytes; Linux validates the IRQ index and
reports capabilities. No capability chain beyond the fixed header is admitted.
`SET_IRQS` accepts only these exact forms (all fields are Linux little-endian):

| flags | count and payload |
| --- | --- |
| DATA_EVENTFD \| ACTION_TRIGGER =36 | count1..64; n =20+4*count, argsz=n. Each signed32 payload fd is a live eventfd created by `eventfd`, or -1 to deassign that vector. |
| DATA_NONE \| ACTION_TRIGGER =33 | count0, start0, argsz=n=20; disables the selected IRQ index. |
| DATA_NONE \| ACTION_MASK =9 or ACTION_UNMASK =17 | count1..64, argsz=n=20; no payload. The driver must first check GET_IRQ_INFO's MASKABLE capability; Linux enforces the device's masking support. The compiler does not invent that capability. |

For every SET form, start+count must fit uint32. Index selection and actual
device vector bounds remain kernel checks. Other flags, mismatched argsz,
oversized counts and malformed payload sizes trap3 (exit103) before ioctl.
Unlike older `vfioctl` records, `vfioirq` validates argsz rather than overwriting it.
There is no DATA_BOOL, userspace trigger-without-eventfd, arbitrary ioctl or
arbitrary syscall escape hatch.

A separate private128-slot descriptor-kind table is keyed by the complete int
fd, not indexed by its numeric magnitude. GET_DEVICE_FD and eventfd reserve a
slot *before* their acquisition syscall; table exhaustion returns -24 without
acquiring or closing a resource. Only successful acquisitions get a kind tag.
`fclose` retires its tag before calling Linux, even when close returns an error.
A successful `dupfd` (dup3) retires the destination tag; failed duplication leaves
it unchanged. Duplication does not propagate tags. Helpers compiled before the
first acquisition use the same table. Fork inherits the table; exec creates a
new program table, and new eventfds have CLOEXEC.

These are current-descriptor kind checks, not generation handles or an isolation
boundary. Kernel fd-number reuse can make a stale integer name a newly acquired
resource. Do not retain stale descriptors. Successful GET_DEVICE_FD is trusted
under Linux's VFIO group-fd contract, not an authentication proof for arbitrary
inherited descriptors or a malicious kernel. A raw/inherited device or eventfd
is not admitted by `vfioirq`. Closing an eventfd does not explicitly deassign
its VFIO IRQ registration: the driver must deassign/disable before closing the
eventfd and device, then observe its normal channel quiescence contract.

NONBLOCK prevents an empty eventfd read from blocking indefinitely; EAGAIN is
returned unchanged. CLOEXEC prevents incidental eventfd inheritance across exec.
Readiness, eventfd write/read success and the host fixture are not GPU completion
or physical interrupt-delivery evidence. Kernel errors remain signed errno.

Run `taskset -c 10-14 nice -n 10 sh seed/host/irq.sh` after the seed fixpoint.
The GCC UAPI layout oracle compares C and Omega serialized records byte for byte.
The ptrace fixture executes real ioctls against a memfd (ENOTTY); only the
GROUP_GET_DEVICE_FD return is replaced to exercise the admitted-kind path.
It checks actual syscall arguments and errno, descriptor invalidation, high
numeric fds and capacity before acquisition. It never opens a VFIO/NVIDIA device.
QEMU user-mode checks a VFIO-less refusal and translated eventfd behavior; it
is not system-emulator VFIO delivery or hardware qualification. Compiler mutants
must compile and execute and then be killed by the independent runtime oracle.
Real VFIO IRQ delivery is NOT_RUN until Drake authorizes a hardware window.


DMA: IOMMU_MAP_DMA15217/32 (`struct vfio_iommu_type1_dma_map`, vfio.h) never
takes an address from Omega code. The caller writes an Omega mapping handle into
the vaddr field (bytes 8..15) and the IOVA into bytes 16..23. The compiler checks
the handle exactly as `mapget` does (live slot, matching generation), requires a
read/write mapping and flags exactly READ|WRITE (3), then stores the mapping's own
base address into vaddr and its whole length into size before the call; any
failed check traps 3. So only a whole live mapping that the program owns can be
handed to the IOMMU, and the IOVA is the only free choice. IOMMU_UNMAP_DMA15218/24
requires flags 0 (no dirty bitmap, no ALL, no VADDR). Request numbers are shared by
`_IO(';', 113/114)` with VFIO_DEVICE_PCI_HOT_RESET and VFIO_DEVICE_QUERY_GFX_PLANE on a
device fd: hot reset refuses any non-zero flags with EINVAL (Linux
drivers/vfio/pci/vfio_pci_core.c, `vfio_pci_ioctl_pci_hot_reset`, `hdr.flags` check),
and MAP_DMA always passes flags 3; vfio-pci does not implement QUERY_GFX_PLANE.
Unmapping or dropping an Omega mapping while it is DMA-mapped leaves the pages pinned
by the kernel until the container is closed; the driver must unmap before dropping.
`vfiomap` refuses a size of zero and region flags
without READ|MMAP; it never requests PROT_WRITE. `vfiomapw` additionally requires
WRITE and is the only VFIO word that maps device memory writable. Host tests use an
invalid fd and a memfd stand-in; the device path is exercised only in the QEMU bench
of aien-dev/omega-gpu-driver, not on hardware.

Kernel constants/layouts are from Linux asm-generic/unistd.h, mman-common.h and
linux/mman.h. AArch64 encodings use seed/rung2/table.s2. The device request rule
comes from the reviewed L605 src/device/omc.om, source 0dee699. Existing host
source is f0499f415571bdd7496b6de391096915e78f7556. These device words are on
main: `hdevctl` is defined in seed/omc/omc.om (verified at main e5b32567).

## Hosted x86-64 Linux lowering

Hosted and program-mode x86 calls share the existing emitter. Mapping uses Linux
`mmap` syscall9 and `munmap` syscall11; `devctl`, `devcall` and `uvmctl` use
`ioctl` syscall16. The argument registers are RDI, RSI, RDX, R10, R8 and R9;
RAX carries the signed result. No libc syscall wrapper is linked. Mapping flags
are unchanged: MAP_SHARED/PRIVATE with the existing anonymous options,
PROT_NONE|MAP_FIXED_NOREPLACE for `maphold`, and MAP_SHARED|MAP_FIXED for
`mapbind`. Copies (`mapread`/`mapwrite`) are byte copies, not ordered MMIO;
`mapaddr` only exports a checked owned address.

The hosted admission set is the same as AArch64: the mapping/ioctl words above,
`fclose`, `fopen`, `fstat`, `stat`, `lstat`, `getuid`, `geteuid`, `getgid`,
`getegid`, `monons`, `realns` and `sleepns`, plus the existing basic input/output.
There is no new generic syscall or arbitrary-address operation.

`mapget` and `mapset` each emit exactly one aligned load or store between two
MFENCE instructions. `cpufence` emits MFENCE and `cpurelax` PAUSE. Do not replace
these fences with a compiler barrier based on ordinary write-back TSO: mapped
device memory can be write-combining and weakly ordered. Intel SDM volume2B,
order253667-093US, September2026, **MFENCE**, page4-15, guarantees that preceding
loads and stores become globally visible before later loads or stores, and
explicitly discusses weakly ordered memory types. **SFENCE** orders stores but
not loads; MFENCE is the deliberately conservative common barrier for both
operations. Source: [Intel SDM volume2B](https://cdrdv2.intel.com/v1/dl/getContent/671241).
The compiler emits instructions in order without a host-language optimizer;
there is no separate C compiler-barrier substitution. CPU ordering does not prove
PCIe completion, GPU coherency or hardware suitability.

The x86 emitter leaves R12 (native nonlocal return anchor), R14 (runtime table)
and R15 (stack floor) untouched. RBX anchors the saved slot snapshot; R13 scratch
is restored before returning. The ordinary program-mode initial argument stack
in R13 is therefore preserved too.

The hosted compiler cases pin both targets' emitted bytes. Wrong-mmap-syscall and
missing-MFENCE compiler mutants must fail those byte checks; this is instruction
structure evidence, not a claim that QEMU reproduces WC reordering. The bridge
adds memfd/ioctl/C differential runtime fixtures under the x86 QEMU oracle.

The draft ABI1 hosted-x86 superset stacks the #1046 lowerers and fixtures on
#1047's exact five-request allowlist. Its seed0-born compiler fingerprint is
`c5ac9979232afd0d750e1d5088af69692032997136f761e585a25aa9a1cfc87e`.
This is a new profile, not an in-place replacement of the frozen AArch64
`b8f8f137...`, previous hosted-x86 `cf4fcbbb...` or pure-x86 `be8c5130...`
profiles. The bridge selects the new hosted-x86 fingerprint explicitly.
Program mode retains its128-slot contract; function-mode context layout and
ownership are unchanged. Drake must approve the draft compiler/bridge
contracts before merge. Native x86, driver/GPU behavior and WC timing remain
NOT_RUN unless separately qualified.

The current-main landing rebuild of #1050 preserves every stack head, including
#1046's original commits, and produces compiler fingerprint
`96eda108a064e419a6cda9112d3bf56ab64f2265fb04f8bb62c08a0786569763`.
The full native-host qualification and `tests/gates/run.sh om-units` pass with
that compiler on Linux AArch64 under a device-hidden bwrap sandbox. This updates
active compiler-consumer pins, not frozen bridge profiles or hardware evidence.

The subsequent #1045 VFIO integration births compiler
`b1d9cff6d765d85159e14d8346ed946704e32e9ca39554fb22a7c3f23fe0cca3`
from source
`5419943aad39c6205bb673c1ddb1be874b1877163cc2f143c07a742cf347456c`.
Its508 source functions fit the unchanged512-function om4 seed;
single-caller helper consolidation, not a seed-capacity change, provides the
space. Descriptor-kind bookkeeping is restricted to program mode, retaining
the existing function-mode host-word byte contracts. The full native-host
gate passes under the device-hidden sandbox, including the IRQ runtime
oracle and compiler mutants. This is host qualification, not hardware IRQ
delivery or authorization to repin a downstream driver's compiler.

The x86efi anchor fix (branch `hive/omega-mv-x86efi-semhash`) births compiler
`5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df`
from source
`2c0fc44bdd607f9e84315e15c7c7ea263a5f0b6d83aa3f446fa6ed975e8ef34c`.
Since #1050, `xhbegin` anchors the slot snapshot in RBX, but `xefival` still
loaded the firmware ARG into RBX before reading the A and N slots and returned
through an unset R14, so every `efi` operation faulted. `xefival` now saves the
caller's R14 at snapshot offset 152, carries the anchor in firmware-preserved
R14 across the call, loads ARG last and restores R13 and R14 from the snapshot
tail. `tests/x86efi/run.sh` under QEMU/OVMF goes from 4/25 to 25/25; this is
emulated, not hardware evidence.

The execenv 233 host word (branch `hive/execprog-env`) births compiler
`cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a`
from source
`062c9649af6a1d499b911e5b2f39b5419d7b75047616fe59fbcdc25f7b7b5b73`.
`execenv A off n B off m` is `execprog` with a private environment packet B,
decoded by a second `hpack`/`xhpack` pass; no function was added (508 of 512).
Every one of the 1357 tracked `.om` files compiles to the same bytes, exit
status and diagnostics under `5f90edea` and `cfd96b48`, so no existing unit's
emission changes. Gate: `seed/host/execenv/execenv.cases`.

x86 types `fma` operands before its error 9 (branch `fix/x86-fma-order`,
OMEGESE.md 9.9) births compiler
`0f2de85153b07656f4b992d101272987fe6ed1eee471ef70b132a37f5ba6b02f`
from source
`7d8026837cfcafe53222228f076e4dab58279ae78a4b008440e6262f5b3c91ab`.
No host word changes and no function was added (508 of 512). Each of the 1485
tracked `.om` files was compiled alone for AArch64 and for `target x86linux`
under `cfd96b48` and `0f2de851`: 2962 of the 2970 compiles give the same bytes,
exit status and diagnostics; the other 8 are the x86 compiles of the ill-typed
`seed/omc/tests/float/neg_fma_*` refusals, error 9 before and now the AArch64
error 7 or 11. Gate: `seed/omc/gate8.sh` (`refuse_x86`).

The prlimit 235 host word (branch `seed/prlimit-host-word`, PROPOSED pending
review; first born as `3c2817a5` on rad main `da8b7e66`, then merged with rad
main `408c76b7`) births compiler
`6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`
from source
`7995e0e31bb3abcf9905fbb6257d56613b2dc67dd22be56f7396151fa84e7189`.
`prlimit pid res A off n` is Linux `prlimit64`: AArch64 syscall 261 (`hprlim`,
x0 pid, x1 res, x2 new, x3 old) and x86-64 syscall 302 (`xhprlim`, rdi pid,
rsi res, rdx new, r10 old). `n` 16 passes new = NULL and old = &A[off]; `n` 32
passes new = &A[off] and old = &A[off+16]; any other `n` sets -22 and skips the
SVC/`syscall`. Two functions were added (510 of 512). Each of the 1496 tracked
`.om` files was compiled alone for AArch64 and for `target x86linux` under
`0f2de851` and `6d1b1cf5`: 2980 of the 2992 compiles give the same bytes, exit
status and diagnostics; the other 12 are the AArch64 and x86 compiles of the six
`seed/host/prlimit/` sources, which use the new word (error 3 before). Gate:
`seed/host/prlimit/prlimit.cases`.

The execenv packet caps and the setprio 234, setaff 237 and execkeep 238 host
words (branch `hive/t_3e396ac5-execenv-cap` on rad main `1e3ecbba`, PROPOSED
pending review; keyword 236 is left to the open `realset` patch) birth compiler
`d791dfd2af2d507dbb2f956ed6bbaacb963960c0d15fea12202fa629eaf893d7`
from source
`c844796167aa3347320da87be69a3cf4dc59e01ea7bb5e33e662084f13395da4`.
`execenv` (both packets) now admits 1..1024 records and up to 131072 bytes
(stack 0x48000: argv strings at SP, argv pointers at SP+0x20000, env strings at
SP+0x24000, env pointers at SP+0x44000; x86 the same layout); `execprog` and
`execpure` keep 64 records and 4096 bytes and emit the same bytes as before.
`execkeep A off n B off m fd` is `execenv` that keeps descriptor `fd`: `fd` < 3
traps 3 before any close, then close_range(3, fd-1, UNSHARE) (skipped for fd 3)
and close_range(fd+1, ~0U, UNSHARE); either failure returns its errno without
executing. `setprio which who prio` is Linux setpriority (AArch64 140, x86-64
141); `setaff pid A off n` is Linux sched_setaffinity (`hsetaff`, AArch64 122;
`xhsetaff`, x86-64 203), slice checked first, then n 1..1024 (trap 3). Two
functions were added (512 in all; om4 holds 4096). Each of the 1651 tracked `.om` files was
compiled alone for AArch64 and for `target x86linux` under `6d1b1cf5` and
`d791dfd2`: 3266 of the 3302 compiles give the same bytes, exit status and
diagnostics; the other 36 are the 32 compiles of the 16 new
`seed/host/{setprio,setaff,execkeep}/` sources (error 3 before) and the 4
compiles of `seed/host/execenv/{execenv,oracle}.om`, whose `execenv` code
changed. The 52 other tracked sources that use `execprog` or `execpure` are
byte-identical. Gates: `seed/host/{execenv,setprio,setaff,execkeep}/*.cases`
(x86linux through qemu-x86_64 user emulation; native x86 NOT_RUN).

The utimens 239 host word (same branch, PROPOSED pending review) births compiler
`9c57c9dd02c43dee907788804694bd3bd16cd7026f9cbad1a8da2e4a2009dbd0`
from source
`fbfa6088dfd2a9d086ca9d96f66a818ebcfa588f5b368540e0b19592516df6ef`.
`utimens A off n as ans ms mns flags` is Linux utimensat(AT_FDCWD, path,
{{as, ans}, {ms, mns}}, flags) (`hutimens`, AArch64 88: the path is copied by
`hpathcp`/`hcopy`, the two timespecs are stored with two STPs in a 32-byte stack
area, x2 = SP, x3 = flags; `xhutimens`, x86-64 280: rsi = path, the timespecs at
RSP, rdx = RSP, rdi = -100, r10 = flags). The path slice is checked (trap 3);
n above 4095 or an embedded zero traps 3; `UTIME_NOW`, `UTIME_OMIT` and flags pass
through. Two functions were added (514 in all). Each of the 1659 tracked `.om`
files was compiled alone for AArch64 and for `target x86linux` under `d791dfd2`
and `9c57c9dd`: 3306 of the 3318 compiles give the same bytes, exit status and
diagnostics; the other 12 are the AArch64 and x86 compiles of the six
`seed/host/utimens/` sources, which use the new word (error 3 before). Gate:
`seed/host/utimens/utimens.cases` (x86linux through qemu-x86_64 user emulation;
native x86 NOT_RUN).

The execx 240, sigmask 241 and sigfd 242 host words (same branch, PROPOSED
pending review) birth compiler
`3a9bd7e1325c952b5667c6ff1f82c4808b32372bd8e6aa7f39fb7ffb3c3934aa`
from source
`1e9b1d22f7d195d7f8df2999d50fca548b43541da12bb70eb9852f6eb1e7c10d`.
`execx A off n B off m K off k` shares the `execenv`/`execkeep` path: the keep
slice is checked (trap 3), k above 64 traps 3, both packets are packed with the
execenv limits and an argv packet of one record traps 3, all before any close;
then `close_range(lo, d-1, CLOSE_RANGE_UNSHARE)` over each gap between kept
descriptors from 3 (skipped when empty) and `close_range(lo, ~0U, ...)` after
the last, then execve with the first record as the path and argv from the
second record. `sigmask how A off n` (`hsig`, AArch64 135; `xhsig`, x86-64 14)
is rt_sigprocmask(how, set, NULL, 8); `sigfd A off n` (AArch64 74, x86-64 289)
is signalfd4(-1, set, 8, SFD_NONBLOCK|SFD_CLOEXEC = 526336). Both check the
slice (trap 3) and n = 8 (else trap 3). Two functions were added (516 in all).
Each of the 1676 tracked `.om` files was compiled alone for AArch64 and for
`target x86linux` under `9c57c9dd` and `3a9bd7e1`: 3326 of the 3352 compiles
give the same bytes, exit status and diagnostics; the other 26 are the AArch64
and x86 compiles of the 13 new `seed/host/{execx,sigfd}/` sources that use the
new words (error 3 before). The `execenv`, `execkeep`, `execprog` and `execpure`
sources are byte-identical. Gates: `seed/host/execx/execx.cases` and
`seed/host/sigfd/sigfd.cases` (x86linux through qemu-x86_64 user emulation;
native x86 NOT_RUN).
