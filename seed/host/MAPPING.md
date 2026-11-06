# Native mapped memory and checked device calls

This extends the existing native-host compiler. It supports the strict Omega
27B experiment's memory prerequisite. It does not yet implement a GPU launcher,
model execution, complete state rollback or a hardware performance comparison.
The seed compiler and added tests are handwritten Omega. The existing shell
bootstrap and test orchestration remain disclosed development tools.

| Expression | Result and contract |
| --- | --- |
| `devctl fd request A off n` | Signed Linux ioctl result. `fd` is int; `request` is a literal uint; `A` is writable bytes; offsets/counts are ulong. Exact encoded size, checked range. Accepts FIONREAD or encoded read/write NVRM F requests, matching the reviewed L605 device boundary. |
| `mapnew fd offset bytes access mode` | Positive long handle or negative Linux errno. fd is int, offset/bytes ulong, access/mode literal ints. Access 1 means read, 3 read/write. Modes 1/2 mean shared/private file; 33/34 shared/private anonymous. Anonymous mappings require fd -1 and offset zero. |
| `mapdrop handle` | Unmap the entire owned mapping. Zero on success or negative errno. Retires the slot on success; the next mapping gets a different generation. |
| `mapread handle offset A off n` | Copy n bytes from the mapping into writable byte array A. Return n as long. |
| `mapwrite handle offset A off n` | Copy n bytes from byte array A into a writable mapping. Return n as long. Read-only source views/text are accepted. |
| `devcall fd request H hoff 32 P poff n` | RM_ALLOC or RM_CONTROL only. Binds a checked writable parameter span in a private header, sets its length, and copies back non-pointer fields. Caller pointer bytes must be zero; header and parameter spans must not overlap. Parameter length is at most 16383. |
| `uvmctl fd command A off n` | Literal Linux UVM request from the explicit ABI580.173.02 allowlist, with its exact writable payload length. |
| `mapaddr handle` | The owned live mapping's base address as ulong, for driver address serialization. Does not permit access through an arbitrary integer address. Works on reservations. |
| `mapget handle offset width` | Aligned uint32 or uint64 load, returned as ulong; width is literal int4 or8. Exactly one load, bracketed by DSB SY on AArch64 or MFENCE on x86-64. Requires readable memory. |
| `mapset handle offset width value` | Aligned uint32 or uint64 store from ulong, returning long0; width is literal int4 or8. A uint32 store refuses truncation. Exactly one store, bracketed by DSB SY on AArch64 or MFENCE on x86-64. Requires writable memory. |
| `maphold address bytes` | Reserve an unused, page-aligned span with PROT_NONE and MAP_FIXED_NOREPLACE. Address is at least64KiB and the whole span is below1TiB. Return an owned handle or errno. A kernel that ignores NOREPLACE is detected by checking the returned address; an unexpected result is unmapped and returns -95. |
| `mapbind handle fd offset access` | Bind a shared file/device mapping to the entire owned reservation, with literal access1 or3. No existing data mapping may be replaced. Return long0 or errno. Failed bind with successful cleanup retires the handle. Function-mode double failure quarantines it for cleanup only (below). |
| `cpufence` | Statement, keyword 199: a standalone host CPU publication barrier, AArch64 `DSB SY`, x86-64 `MFENCE`. It orders ordinary stores, for example `mapwrite` or plain array stores, before a later `mapset` doorbell or flag. A `mapget`/`mapset` access already carries its own barriers. See OMEGESE §10, "Host CPU ordering words". Proof: `seed/host/cpufence.sh`. |
| `cpurelax` | Statement, keyword 200: spin-wait hint for a bounded `mapget` poll loop, AArch64 `YIELD`, x86-64 `PAUSE`. It gives no ordering. Proof: `seed/host/cpufence.sh`. |

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
