# Clean-Room GSP-RM RPC, Control & Registry Reference for GB20B Compute Bring-Up

> **Scope & Clean-Room Hygiene:** This document specifies wire formats, RPC function/event IDs, RM object class IDs, RM control command IDs, and registry table layouts needed for pure-Omega compute bring-up on NVIDIA GB10 (DGX Spark, verified silicon identity `GB20B`). It contains no copied third-party source code. Every constant and struct layout is cross-referenced to verified pure-Omega units in this repository (`gpu/driver/`, `gpu/nvidia/native/`) or explicitly labeled by provenance and verification state.

## Provenance & Status Vocabulary

| Label | Meaning |
| --- | --- |
| `IMPLEMENTED` | Wire codec or state machine exists in this repository at the named `.om` path. |
| `HOST_VERIFIED` | Codec/state machine exercised by host replay/simulator or layout-diff tests; **not** bare-metal silicon qualification. |
| `SILICON_VERIFIED` | Directly observed on live DGX Spark GB10 hardware (e.g., `BOOT_0`/`BOOT_42` or stock `nvidia.ko` RM path). |
| `GB20B_REQUIRED` | Verified delta required for Spark `GB20B` (`BOOT_42 = 0x1bba1000`, arch `0x1B`, impl `0xB`) vs. `GB10B` (`0x1A`). |
| `GB10B_LEGACY` | Present in current `gpu/driver/` units ported from `GB10B` assumptions; must be updated for `GB20B` silicon. |
| `PROPOSED` | Documented NVIDIA 580.173.02 ABI / bring-up candidate not yet wired into `gpu/driver/` or `NOT_RUN` on `GB20B` bare metal. |

**Target Silicon Identity (`SILICON_VERIFIED`):**
- PCI device: `10de:2e12` at `000f:01:00.0` (48 SMs, SM 12.1 / RM `SM_VERSION = 0x0a04` (`2564`), unified LPDDR5x memory, 24 MiB GPU L2).
- `NV_PMC_BOOT_0` (`0x000000`): `0x1bb000a1`
- `NV_PMC_BOOT_42` (`0x000a00`): `0x1bba1000` (architecture `0x1B`, implementation `0xB` = `GB20B`, **not** `GB10B` `0x1A`).
- Source-of-record ABI pin: NVIDIA `open-gpu-kernel-modules 580.173.02` (MIT).
- Current own-driver status: `HOST_VERIFIED` / `QEMU` (`hardware = NOT_RUN` for Stage B/C until a reviewed Window 0 cold boot).

---

## 1. GSP-RM Message Queue & RPC Wire Framing

Implemented in `gpu/driver/gsp/rpc.om`, `gpu/driver/gsp/transport.om`, and `gpu/driver/gsp/notify.om` (`IMPLEMENTED`, `HOST_VERIFIED`, non-CC single-client profile).

### 1.1 Queue Geometry & Header Layout

Two 256 KiB rings live in shared DMA memory (page-table radix page + 64 pages `cmdq` + 64 pages `statq` = 129 pages total, built in `gpu/driver/gsp/arena.om`):

| Constant | Omega Symbol | Decimal | Hex | Meaning |
| --- | --- | ---: | --- | --- |
| Queue size | `RQQSZ` | `262144` | `0x00040000` | 256 KiB per queue (`cmdq` or `statq`) |
| Slot size | `RQSLOT` | `4096` | `0x00001000` | 4 KiB per slot; slot 0 is the header page |
| Slot count | `RQCOUNT` | `63` | `0x0000003f` | 63 ring data slots (slots `1..63`) |
| Max message | `RQMAX` | `65536` | `0x00010000` | 64 KiB max total message span (`16` slots) |
| Header version | `RQVER` | `50331648` | `0x03000000` | `GSP_MSG_QUEUE_ELEMENT_VERSION` (`3 << 24`) |
| Header signature | `RQSIG` | `1129337430` | `0x43505256` | `'VPRC'` (`NV_VGPU_MSG_SIGNATURE_VALID`) |

Queue header page (slot 0, little-endian `u32` fields):

| Offset | Width | Field | Value / Notes |
| ---: | ---: | --- | --- |
| `0x00` | 4 | `version` | `0` |
| `0x04` | 4 | `size` | `262144` (`0x40000`) |
| `0x08` | 4 | `entrySize` | `4096` (`0x1000`) |
| `0x0C` | 4 | `entryCount` | `63` |
| `0x10` | 4 | `writePtr` | Producer slot index `0..62` (CPU writes `cmdq[0x10]`, GSP writes `statq[0x10]`) |
| `0x14` | 4 | `flags` | `1` (`SWAP_RX` layout) |
| `0x18` | 4 | `txHdrOff` | `32` (`0x20`, byte offset of `readPtr` in peer header) |
| `0x1C` | 4 | `rxHdrOff` | `4096` (`0x1000`, byte offset of slot 1) |
| `0x20` | 4 | `readPtr` | Consumer slot index `0..62` (CPU writes `cmdq[0x20]` for `statq` consumption; GSP writes `statq[0x20]` for `cmdq` consumption) |

### 1.2 Message Element & RPC Header Layout (`80 B` prefix)

All fields are little-endian. Multi-slot messages wrap modulo `63` starting at `writePtr` (or `readPtr`).

| Offset | Width | Field | Notes |
| ---: | ---: | --- | --- |
| `0x00..0x1F` | 32 | `authTag` / `aad` | Must be all `0` in non-CC profile (`rqvalid` refuses nonzero bytes with `-5`). |
| `0x20` (`32`) | 4 | `checkSum` | XOR-32 of every 4-byte little-endian word across `align8(80 + logical_payload_len)` bytes (computed with `checkSum = 0`). |
| `0x24` (`36`) | 4 | `seqNum` | Monotonic per-direction queue element sequence (`rqtx` / `rqrx`). |
| `0x28` (`40`) | 4 | `elemCount` | Number of 4 KiB slots: `ceil((80 + logical_payload_len) / 4096)`, in `1..16`. |
| `0x2C` (`44`) | 4 | `reserved` | Must be `0`. |
| `0x30` (`48`) | 4 | `header_version` | `0x03000000` (`RQVER`). |
| `0x34` (`52`) | 4 | `signature` | `0x43505256` (`RQSIG`, `'VPRC'`). |
| `0x38` (`56`) | 4 | `length` | `32 + logical_payload_len` (range `32..65488`). |
| `0x3C` (`60`) | 4 | `function` | RPC function ID or GSP->CPU event ID (Section 2). |
| `0x40` (`64`) | 4 | `rpc_result` | `0xFFFFFFFF` on send; `NV_STATUS` (`0` = OK) on reply. |
| `0x44` (`68`) | 4 | `rpc_result_private` | `0xFFFFFFFF` on send; private `NV_STATUS` on reply. |
| `0x48` (`72`) | 4 | `sequence` | Synchronous RPC correlation counter (`0` for async/pre-queued RPCs). |
| `0x4C` (`76`) | 4 | `cpuRmGfid` / `reserved` | Must be `0` in single-client non-CC profile. |
| `0x50` (`80`) | `p` | `payload[]` | RPC-specific payload bytes. |

**`GSP_RM_ALLOC` (`103`) Special Framing Rule:** `logical_payload_len` is fixed at `32` (covering the `rpc_gsp_rm_alloc` header only), while `physical_payload_len` is `32 + paramsSize` (appended inline params). Both `checkSum` and `rpc_message_header_v.length` (`64 = 32 + 32`) cover only the `32`-byte logical header (`gpu/driver/gsp/rpc.om:186`, `gpu/driver/gsp/boot.om:328`).

### 1.3 Queue Doorbell Notification

After copying payload slots and updating `cmdq[0x10]` (`writePtr`) with a full barrier (`DSB SY`), notify GSP by writing `0` (32-bit) to:

| Register | BAR0 Offset | Omega Symbol | Value | Provenance |
| --- | --- | --- | --- | --- |
| `NV_PGSP_QUEUE_HEAD(0)` | `0x00110C00` | `GPNOTIF` (`1117184`) | `0` | `IMPLEMENTED` (`gpu/driver/gsp/notify.om`, `kernel_gsp_tu102.c:343-355`) |

---

## 2. RPC Function & Event ID Catalog

Cross-checked against `gpu/driver/gsp/boot.om`, `gpu/driver/gsp/rpc.om`, `gpu/driver/gsp/dispatch.om`, `gpu/driver/chan/params.om`, and `gpu/driver/rm/dispatch.om`.

### 2.1 CPU -> GSP RPC Functions

| Function ID | Hex | Name (`rpc_global_enums.h`) | Mode | Payload Size | Omega Implementation | Status |
| ---: | --- | --- | --- | --- | --- | --- |
| `1` | `0x01` | `SET_GUEST_SYSTEM_INFO` | Sync | `792 B` (`v03_00`) | `boot.om` (`bguest`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `10` | `0x0A` | `FREE` | Sync | `16 B` | `boot.om` (`brmfree`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `54` | `0x36` | `SET_PAGE_DIRECTORY` | Sync | `48 B` (`v1E_05`) | `params.om` (`PARSETPD`, `pasetpd`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `65` | `0x41` | `GET_GSP_STATIC_INFO` | Sync | Caller-sized (zero-filled req) | `boot.om` (`bstatic`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `72` | `0x48` | `GSP_SET_SYSTEM_INFO` | Async (pre-queued) | `936 B` (`GspSystemInfo`) | `sysinfo.om`, `boot.om` (`bsys`), `arena.om` | `IMPLEMENTED`, `HOST_VERIFIED` |
| `73` | `0x49` | `SET_REGISTRY` | Async (pre-queued) | `8..65456 B` (`PACKED_REGISTRY_TABLE`) | `arena.om` (`arregok`), `boot.om` (`breg`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `76` | `0x4C` | `GSP_RM_CONTROL` | Sync | `40 B` header + `N` B params (`N <= 4096`) | `params.om` (`PARCTRL`), `boot.om` (`brmctrl`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `79` | `0x4F` | `UNSET_PAGE_DIRECTORY` | Sync | `16 B` (`v1E_05`) | `params.om` (`PARUNSPD`, `paunsetpd`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `103` | `0x67` | `GSP_RM_ALLOC` | Sync | `32 B` logical + `N` B params (`N <= 3984`) | `params.om` (`PARALLOC`), `boot.om` (`brmalloc`) | `IMPLEMENTED`, `HOST_VERIFIED` |

### 2.2 GSP -> CPU Asynchronous Events

| Event ID | Hex | Name | Payload Layout | Omega Implementation | Status |
| ---: | --- | --- | --- | --- | --- |
| `4097` | `0x1001` | `GSP_INIT_DONE` | Status in `rpc_result` (`0` = OK); `sequence = 0` | `boot.om` (`bpoll`, state `4 -> 5`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `4098` | `0x1002` | `GSP_RUN_CPU_SEQUENCER` | `rpc_run_cpu_sequencer_v17_00`: `bufferSizeDWord` (`+0x50`), `cmdIndex` (`+0x54`), `regSaveArea[8]` (`+0x58..0x77`), `cmdBuf[]` (`+0x78`). Opcodes `0..8`: `0=REG_WRITE(2)`, `1=REG_MODIFY(3)`, `2=REG_POLL(5)`, `3=DELAY_US(1)`, `4=REG_STORE(2)`, `5=CORE_RESET(0)`, `6=CORE_START(0)`, `7=CORE_WAIT_FOR_HALT(0)`, `8=CORE_RESUME(0)`. | `seq.om`, `dispatch.om`, `boot.om` (state `11`) | `IMPLEMENTED`, `HOST_VERIFIED` |

### 2.3 Mandatory Boot & Handshake Ordering (`gpu/driver/gsp/boot.om`)

1. **Pre-queue `RPC 72` (`GSP_SET_SYSTEM_INFO`, `936 B`)** into `cmdq` before SEC2 starts GSP-FMC.
2. **Pre-queue `RPC 73` (`SET_REGISTRY`)** into `cmdq` if any registry entries are present (omit if `0` bytes).
3. **Start GSP-FMC via SEC2 COTv2** (`GB20B_REQUIRED`: poll `NV_PMC_SCRATCH_RESET_PLUS_2` `0x5e0 == 0xFF`, send `868 B` COTv2 packet via SEC2 `QUEUE_HEAD/TAIL` `0x840c00/04` + `EMEMC` `0x840ac0`, consume reply from `NV_PSEC_MSGQ_HEAD/TAIL(0)` `0x840c80/84` writing `TAIL` before `HEAD`; see `gpu/driver/gsp/sec2.om`).
4. **Service `0x1002` (`GSP_RUN_CPU_SEQUENCER`)** events until **`0x1001` (`GSP_INIT_DONE`)** arrives.
5. **Send `RPC 1` (`SET_GUEST_SYSTEM_INFO`, `792 B`)** and wait for reply (`NV_STATUS = 0`). Mandatory **before** static info (`kernel_gsp.c:4261-4274`).
6. **Send `RPC 65` (`GET_GSP_STATIC_INFO`)** and wait for reply.
7. **Enter Ready state (`bstate = 9`)**: one-in-flight synchronous RM RPCs (`103`, `76`, `10`, `54`, `79`) are now permitted.

### 2.4 Core RM RPC Envelope Payloads

**`RPC 103` (`GSP_RM_ALLOC`)** (`gpu/driver/gsp/boot.om:319-337`, `151-173`):

| Payload Offset | Frame Offset | Width | Field | Notes |
| ---: | ---: | ---: | --- | --- |
| `0x00` | `0x50` (`80`) | 4 | `hClient` | Client handle (`NV01_ROOT`) |
| `0x04` | `0x54` (`84`) | 4 | `hParent` | Parent handle (`0` for `NV01_ROOT`) |
| `0x08` | `0x58` (`88`) | 4 | `hObject` | New object handle |
| `0x0C` | `0x5C` (`92`) | 4 | `hClass` | Class ID (Section 4) |
| `0x10` | `0x60` (`96`) | 4 | `status` | `0` on send; `NV_STATUS` on reply |
| `0x14` | `0x64` (`100`) | 4 | `paramsSize` | Byte length of inline params (`0..3984`) |
| `0x18` | `0x68` (`104`) | 4 | `flags` | `0` |
| `0x1C` | `0x6C` (`108`) | 4 | `reserved` | `0` |
| `0x20` | `0x70` (`112`) | `N` | `params[]` | Class-specific alloc struct (verbatim) |

**`RPC 76` (`GSP_RM_CONTROL`)** (`gpu/driver/gsp/boot.om:347-363`, `175-195`):

| Payload Offset | Frame Offset | Width | Field | Notes |
| ---: | ---: | ---: | --- | --- |
| `0x00` | `0x50` (`80`) | 4 | `hClient` | Client handle |
| `0x04` | `0x54` (`84`) | 4 | `hObject` | Target object handle |
| `0x08` | `0x58` (`88`) | 4 | `cmd` | RM control command ID (Section 4) |
| `0x0C` | `0x5C` (`92`) | 4 | `status` | `0` on send; `NV_STATUS` on reply |
| `0x10` | `0x60` (`96`) | 4 | `paramsSize` | Byte length of inline params (`0..4096`) |
| `0x14` | `0x64` (`100`) | 4 | `flags` | `0` (flat profile) |
| `0x18..0x27` | `0x68..0x77` | 16 | `reserved` / metadata | Must be `0` in flat profile |
| `0x28` | `0x78` (`120`) | `N` | `params[]` | Control-specific param struct (verbatim) |

**`RPC 10` (`FREE`)** (`gpu/driver/gsp/boot.om:372-382`, `197-207`):

| Payload Offset | Frame Offset | Width | Field | Notes |
| ---: | ---: | ---: | --- | --- |
| `0x00` | `0x50` (`80`) | 4 | `hClient` | Client handle |
| `0x04` | `0x54` (`84`) | 4 | `hParent` | `0` (GSP looks up parent by client+object) |
| `0x08` | `0x58` (`88`) | 4 | `hObject` | Object handle to free |
| `0x0C` | `0x5C` (`92`) | 4 | `status` | `0` on send; `NV_STATUS` on reply |

---

## 3. Registry Wire Format (`RPC 73`) & Compute Bring-Up Keys

### 3.1 Canonical `PACKED_REGISTRY_TABLE` Wire Format (`IMPLEMENTED`, `HOST_VERIFIED`)

Validated strictly by `arregok` in `gpu/driver/gsp/arena.om` (`L101-L166`) and `breg` in `gpu/driver/gsp/boot.om` (`L58-L76`).

**Header (`8 B`):**

| Offset | Width | Field | Constraints |
| ---: | ---: | --- | --- |
| `0x00` | 4 | `size` | Total table byte size (`8..65456`); must equal exact wire length |
| `0x04` | 4 | `numEntries` | Entry count (`1..32`; `0` bytes omits `RPC 73` completely) |

**Entry Table (`16 B` × `numEntries`, starting at offset `0x08`):**

| Entry Offset | Width | Field | Constraints |
| ---: | ---: | --- | --- |
| `+0x00` | 4 | `nameOffset` | Byte offset to NUL-terminated, non-empty ASCII key name |
| `+0x04` | 1 | `type` | `1` = `DWORD`, `2` = `BINARY`, `3` = `STRING` |
| `+0x05..0x07` | 3 | `reserved` | Must be `0, 0, 0` |
| `+0x08` | 4 | `data` | For `type = 1`: inline `u32` value. For `type = 2/3`: byte offset to value bytes |
| `+0x0C` | 4 | `length` | For `type = 1`: must be `4`. For `type = 2/3`: must be `> 0` and fit within `size` |

**Canonical Contiguity Invariant (`arena.om`):** Starting at `pos = 8 + 16 * numEntries`, for each entry `i = 0..numEntries-1`:
1. `entry[i].nameOffset == pos`, followed by non-empty NUL-terminated name bytes; advance `pos` past NUL.
2. If `type` is `2` or `3`, `entry[i].data == pos`, followed by `entry[i].length` opaque bytes; advance `pos += length`.
3. After the final entry, `pos == size` (no trailing slack or out-of-order blobs).

### 3.2 Registry Keys for Compute Bring-Up

> **Important:** In host replay (`gpu/driver/tests/rpc_trace.om`, `rmchan_trace.om`), `breg 0` (empty table, `RPC 73` omitted) is the verified baseline. On bare-metal `GB20B`, registry keys below are `PROPOSED` / `NOT_RUN` unless explicitly marked otherwise; none is required to be fabricated until Window 0 testing confirms whether GSP-RM defaults suffice.

| Key Name | Type | Candidate Value | Purpose in Headless Compute Bring-Up | Status |
| --- | --- | --- | --- | --- |
| *(omit `RPC 73`)* | — | `0 B` | Minimal bring-up baseline using GSP-RM compiled defaults | `IMPLEMENTED`, `HOST_VERIFIED` (`boot.om`, `arena.om`) |
| `EnableGpuFirmware` | `DWORD` (`1`) | `1` | Host-side `nvidia.ko` knob selecting GSP-RM firmware mode (not required inside GSP once FMC is booted, noted for parity) | `PROPOSED` (`580.173.02`) |
| `RMGspLogLevel` | `DWORD` (`1`) | `0`..`5` | Controls GSP-RM `LOGINIT`/`LOGRM` verbosity into the 7 LibosLog buffers mapped in `arena.om` | `PROPOSED` (`NOT_RUN` on GB20B) |
| `RmLogonRC` | `DWORD` (`1`) | `1` | Enables robust-channel / fault diagnostic logging to GSP log rings during channel bring-up | `PROPOSED` (`NOT_RUN` on GB20B) |
| `RMEnableDynamicPowerManagement` | `DWORD` (`1`) | `0` | Disables RTD3/GC6 dynamic power transitions during early Window 0 compute bring-up | `PROPOSED` (`NOT_RUN` on GB20B) |
| `RMPowerFeature2` | `DWORD` (`1`) | `0` | Power-feature override mask for deterministic clock/power bring-up | `PROPOSED` (`NOT_RUN` on GB20B) |
| `RMDisableDisplay` | `DWORD` (`1`) | `1` | Suppresses display engine initialization on headless compute-only bring-up | `PROPOSED` (`NOT_RUN` on GB20B) |

### 3.3 `GspSystemInfo` (`RPC 72`, `936 B`) Critical GB20B Fields

Full 72-field offset table lives in `gpu/driver/gsp/sysinfo.om`. Key fields that must come from live PCI/DMA state on Spark `GB20B`:

| Field | Offset | Width | Spark GB10 / GB20B Value / Source | Status |
| --- | ---: | ---: | --- | --- |
| `gpuPhysAddr` | `0` | 8 | BAR0 CPU physical address (live PCI assignment, e.g. `0x24000000`) | `IMPLEMENTED` (`sysinfo.om`) |
| `gpuPhysFbAddr` | `8` | 8 | `0` (unified memory; no discrete FB BAR) | `IMPLEMENTED` |
| `gpuPhysInstAddr` | `16` | 8 | `BAR0 + 0x700000` (live) | `IMPLEMENTED` |
| `nvDomainBusDeviceFunc` | `32` | 8 | `0x0000000f00000100` (`000f:01:00.0`) | `SILICON_VERIFIED` |
| `notifyOpSharedSurfacePhysAddr` | `48` | 8 | Driver IOVA of notify-op DMA page (live per boot) | `IMPLEMENTED` |
| `maxUserVa` | `72` | 8 | `0x0001000000000000` (48-bit arm64 `TASK_SIZE`) | `IMPLEMENTED` |
| `pciConfigMirrorBase` / `Size` | `80` / `84` | 4 / 4 | `0x92000` / `0x1000` | `IMPLEMENTED` |
| `PCIDeviceID` / `SubDeviceID` / `Rev` | `88` / `92` / `96` | 4 each | `0x2e1210de` / `0x10de` / `0xa1` | `SILICON_VERIFIED` |
| `oorArch` | `104` | 1 | `3` (`OOR_ARCH_AARCH64`) | `IMPLEMENTED` |
| `Chipset` | `120` | 4 | `0x106d` (`CS_NVIDIA_T254`, root port `0x22d1`) | `IMPLEMENTED` |
| `bFlrSupported` | `125` | 1 | Config `DevCap[28]`; note `PDB_PROP_GPU_TRIGGER_PCIE_FLR = NV_FALSE` on `GB20B` (sysfs FLR reboots SoC) | `SILICON_VERIFIED` |
| `sysTimerOffsetNs` | `848` | 8 | `OS_ns - PTIMER_ns` (live read immediately before send) | `IMPLEMENTED` |
| `hostPageSize` | `920` | 8 | `4096` | `IMPLEMENTED` |

---

## 4. Compute Bring-Up Stages: Classes, Control IDs & Wire Layouts

### Object Hierarchy (`gpu/driver/chan/rmchan.om`, `gpu/driver/rm/handles.om`)

```
NV01_ROOT (0x0000 / Linux ioctl 0x0041)
 └── NV01_DEVICE_0 (0x0080)
      ├── NV20_SUBDEVICE_0 (0x2080)
      │    └── VOLTA_USERMODE_A (0xc361) / HOPPER_USERMODE_A (0xc661)   [doorbell page]
      ├── FERMI_VASPACE_A (0x90f1)                                      [GPU VA space]
      ├── NV01_MEMORY_SYSTEM (0x003e) / NV01_MEMORY_LOCAL_USER (0x0040) [backing memory]
      ├── NV50_MEMORY_VIRTUAL (0x0070)                                  [virtual range]
      └── KEPLER_CHANNEL_GROUP_A (0xa06c)                               [TSG]
           ├── FERMI_CONTEXT_SHARE_A (0x9067)                           [subcontext]
           └── BLACKWELL_CHANNEL_GPFIFO_A (0xc96f) / _B (0xca6f)        [GPFIFO channel]*
                └── BLACKWELL_COMPUTE_B (0xcec0)                        [compute engine]
```
*\*Note on channel parent handle:* On the Linux RM ioctl path (`context.om:946`, `handles.om:39-40`), `BLACKWELL_CHANNEL_GPFIFO_A` is allocated with parent = `KEPLER_CHANNEL_GROUP_A` (`hTSG`). On the direct GSP-RM `rmchan.om` path (`rmchan.om:414`), `BLACKWELL_CHANNEL_GPFIFO_A` is allocated with parent = `NV01_DEVICE_0` (`hDev`) and `hPhysChannelGroup = hTSG` inside `NV_CHANNEL_ALLOC_PARAMS[0xF0]`.

---

### Stage 1: Device & Subdevice

#### Class IDs

| Class Name | Hex | Decimal | Parent | Param Struct & Size | Omega Symbol / Unit | Status |
| --- | --- | ---: | --- | --- | --- | --- |
| `NV01_ROOT` | `0x0000` | `0` | `0` | `NV0000_ALLOC_PARAMETERS` (`120 B`) | `PACROOT` (`params.om`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `NV01_ROOT_CLIENT` | `0x0041` | `65` | `0` | `0 B` on Linux RM ioctl (maps to `paroot` `120 B` on GSP wire) | `dispatch.om`, `context.om` | `IMPLEMENTED`, `SILICON_VERIFIED` (via `nvidia.ko`) |
| `NV01_DEVICE_0` | `0x0080` | `128` | `hClient` | `NV0080_ALLOC_PARAMETERS` (`56 B`) | `PACDEV` (`params.om`) | `IMPLEMENTED`, `HOST_VERIFIED` |
| `NV20_SUBDEVICE_0` | `0x2080` | `8320` | `hDevice` | `NV2080_ALLOC_PARAMETERS` (`4 B`) | `PACSUB` (`params.om`) | `IMPLEMENTED`, `HOST_VERIFIED` |

#### Parameter Layouts (`gpu/driver/chan/params.om`)

- **`NV0000_ALLOC_PARAMETERS` (`PASZROOT = 120 B`)**: `hClient` (`+0`, `u32`), `processID` (`+4`, `u32`), `processName[100]` (`+8`, NUL-padded ASCII, e.g. `"aien-ogd"`), `pOsPidInfo` (`+112`, `u64 = 0`).
- **`NV0080_ALLOC_PARAMETERS` (`PASZDEV = 56 B`)**: `deviceId` (`+0`, `u32`), `hClientShare` (`+4`, `u32`), `hTargetClient` (`+8`, `u32 = 0`), `hTargetDevice` (`+12`, `u32 = 0`), `flags` (`+16`, `u32`), `vaSpaceSize` (`+24`, `u64`, e.g. `1 TiB = 0x10000000000`), `vaStartInternal` (`+32`, `u64 = 0`), `vaLimitInternal` (`+40`, `u64 = 0`), `vaMode` (`+48`, `u32`).
- **`NV2080_ALLOC_PARAMETERS` (`PASZSUB = 4 B`)**: `subDeviceId` (`+0`, `u32 = 0`).

#### Control Command IDs (Device / Subdevice Discovery & Static GR Info)

| Control ID (Hex) | Decimal | Name | Target Object | Param Size | Route | Notes / Status |
| --- | ---: | --- | --- | ---: | --- | --- |
| `0x00000205` | `517` | `NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2` | `NV01_ROOT` | `32 B` | Host-local RM (`gpu_mgr.c`) | Maps `gpuId` (`+0`) -> `deviceInstance` (`+8`), `subDeviceInstance` (`+12`). `IMPLEMENTED` (`context.om:376`, `model.om:81`) |
| `0x00800201` | `8389121` | `NV0080_CTRL_CMD_GPU_GET_CLASSLIST` | `NV01_DEVICE_0` | `16 B` | Host-local RM (`device_ctrl.c`) | Enumerates supported RM classes. `IMPLEMENTED` (`dispatch.om:43`, `model.om:88`) |
| `0x00800292` | `8389266` | `NV0080_CTRL_CMD_GPU_GET_CLASSLIST_V2` | `NV01_DEVICE_0` | `804 B` | Linux RM ioctl | Returns `numClasses` (`+0`) + `classList[200]` (`+4`); verifies `0xcec0`, `0xc96f`/`0xca6f`, `0xc361`/`0xc661`. `IMPLEMENTED` (`context.om:398`) |
| `0x2080014a` | `545259850` | `NV2080_CTRL_CMD_GPU_GET_GID_INFO` | `NV20_SUBDEVICE_0` | `268 B` | Host-local RM (`gpu.c`) | `flags = 2` (SHA-1/binary), `length = 16` -> 16-byte GPU UUID at `+12`. `IMPLEMENTED` (`context.om:803`, `model.om:118`) |
| `0x20800a2a` | `545262122` | `NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_GET_INFO` | `NV20_SUBDEVICE_0` | `3712 B` | **GSP `RPC 76`** | `PACMGRI` (`params.om:35`). Zero request; reply is 8 engines × 58 entries × 8 B (`464 B`/engine). `SM_VERSION` is index `0xC` (byte offset `100` in engine 0). `IMPLEMENTED`, `HOST_VERIFIED` |
| `0x20801201` | `545264129` | `NV2080_CTRL_CMD_GR_GET_INFO` | `NV20_SUBDEVICE_0` | `32 B` | Host RM (backed by `0x20800a2a`) | Queries GR info list entry (e.g. index `12` = `SM_VERSION`). `IMPLEMENTED` (`model.om:102`) |
| `0x20801228` | `545264168` | `NV2080_CTRL_CMD_GR_GET_INFO_V2` | `NV20_SUBDEVICE_0` | `488 B` | Linux RM ioctl | Queries GR info v2; returns `0x0a04` (`2564`) on GB10. `IMPLEMENTED` (`context.om:431`) |

---

### Stage 2: Memory & Virtual Address Space

#### Class IDs

| Class Name | Hex | Decimal | Parent | Param Struct & Size | Notes / Status |
| --- | --- | ---: | --- | --- | --- |
| `FERMI_VASPACE_A` | `0x90f1` | `37105` | `hDevice` | `NV_VASPACE_ALLOCATION_PARAMETERS` (`56 B`) | `PACVAS` (`params.om:29`, `context.om:794`). `IMPLEMENTED`, `HOST_VERIFIED` |
| `NV01_MEMORY_SYSTEM` | `0x003e` | `62` | `hDevice` | `NV_MEMORY_ALLOCATION_PARAMS` (`128 B`) | Sysmem backing (unified pool on GB10). `IMPLEMENTED` (`context.om:664`, `dispatch.om:4`) |
| `NV01_MEMORY_LOCAL_USER` | `0x0040` | `64` | `hDevice` | `NV_MEMORY_ALLOCATION_PARAMS` (`128 B`) | Local memory class (host model in `dispatch.om:4`). `IMPLEMENTED` |
| `NV50_MEMORY_VIRTUAL` | `0x0070` | `112` | `hDevice` | `NV_MEMORY_VIRTUAL_ALLOCATION_PARAMS` (`24 B`) | Virtual range object for `NVOS46` DMA mapping (`context.om:784`). `IMPLEMENTED` |

#### Key Memory Parameter Layouts

- **`NV_VASPACE_ALLOCATION_PARAMETERS` (`PASZVAS = 56 B`, `params.om:130-143`)**: `index` (`+0`, `u32`), `flags` (`+4`, `u32`; `72` = `0x48` used in `rmchan.om:373` & `context.om:791`), `vaSize` (`+8`, `u64`), `vaStartInternal` (`+16`, `u64 = 0`), `vaLimitInternal` (`+24`, `u64 = 0`), `bigPageSize` (`+32`, `u32 = 65536`), `vaBase` (`+40`, `u64`), `pasid` (`+48`, `u32 = 0`).
- **`NV_MEMORY_ALLOCATION_PARAMS` (`128 B`, `context.om:651-664`, `struct.om` kind 10)**: `owner` (`+0`, `u32 = hClient`), `type` (`+4`, `u32`), `flags` (`+8`, `u32 = 0xC101` / `49409`), `attr` (`+24`, `u32 = 0x1A000000` / `436207616`), `attr2` (`+28`, `u32`: **`9` = GPU-uncached**, **`5` = GPU-cached**), `format` (`+32`, `u32 = 6`), `size` (`+64`, `u64`), `alignment` (`+72`, `u64 = 4096`), `limit` (`+88`, `u64 = size - 1`).

> **GB10 Unified-Memory Coherency Rule (`SILICON_VERIFIED`):** Host-polled completion markers, GPFIFO rings, USERD pages, and CPU-rewritten pushbuffers **must** be allocated **GPU-uncached** (`attr2 = 9` on RM; `GMHPOLL` uncached in `gpu/driver/chan/mem.om`). GPU-cached system memory is not coherent with CPU mappings on GB10. Compute-only data operands may remain GPU-cached (`attr2 = 5`) provided a GPU L2 flush executes before CPU readback (`launch.om:223-229`).

#### Page Directory GSP RPCs (`gpu/driver/chan/params.om`)

- **`RPC 54` (`PARSETPD`) — `rpc_set_page_directory_v1E_05` (`PASZSPD = 48 B`, `params.om:264-288`)**:
  - `+0`: `hClient` (`u32`)
  - `+4`: `hDevice` (`u32`)
  - `+8`: `pasid` (`u32`)
  - `+16`: `params.physAddress` (`u64`, root page directory PA)
  - `+24`: `params.numEntries` (`u32`)
  - `+28`: `params.flags` (`u32`: `APERTURE` bits `1:0` in `0..2` where `2 = SYSMEM_COHERENT`, `PRESERVE_PDES` bit `2`)
  - `+32`: `params.hVASpace` (`u32`)
  - `+36`: `params.chId` (`u32`)
  - `+40`: `params.subDeviceId` (`u32`)
  - `+44`: `params.pasid` (`u32`)
- **`RPC 79` (`PARUNSPD`) — `rpc_unset_page_directory_v1E_05` (`PASZUPD = 16 B`, `params.om:289-300`)**:
  - `+0`: `hClient` (`u32`), `+4`: `hDevice` (`u32`), `+8`: `params.hVASpace` (`u32`), `+12`: `params.subDeviceId` (`u32`).

#### Direct GMMU v3 TLB Invalidation Registers (`gpu/driver/chan/gmmu.om`, `IMPLEMENTED`, `HOST_VERIFIED`)

VF base `0x00B80000` (57-bit VA, 52-bit PA, aperture `2 = SYSMEM_COHERENT`, PDE PCF `2 = cached, no ATS`):

| Register | BAR0 Offset | Omega Symbol | Notes |
| --- | --- | --- | --- |
| `NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE_PDB` | `0x00B830A0` | `MMRPDB` (`12071072`) | Low PDB PA + aperture `2` |
| `NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE_UPPER_PDB` | `0x00B830A4` | `MMRUPR` (`12071076`) | High PDB PA |
| `NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE` | `0x00B830B0` | `MMRINV` (`12071088`) | Trigger bit `31` (`0x80000000`), `ALL_VA` bit `0` (`0x1`) |

---

### Stage 3: Channel & Scheduling

#### Class IDs

| Class Name | Hex | Decimal | Parent | Param Struct & Size | Notes / Status |
| --- | --- | ---: | --- | --- | --- |
| `KEPLER_CHANNEL_GROUP_A` | `0xa06c` | `41068` | `hDevice` | `NV_CHANNEL_GROUP_ALLOCATION_PARAMETERS` (`20 B`) | `PACTSG` (`params.om:30`). `IMPLEMENTED`, `HOST_VERIFIED` |
| `FERMI_CONTEXT_SHARE_A` | `0x9067` | `36967` | `hTSG` | `NV_CTXSHARE_ALLOCATION_PARAMETERS` (`12 B`) | `PACCTX` (`params.om:31`). `IMPLEMENTED`, `HOST_VERIFIED` |
| `BLACKWELL_CHANNEL_GPFIFO_A` | `0xc96f` | `51567` | `hDevice` (GSP) / `hTSG` (Linux RM) | `NV_CHANNEL_ALLOC_PARAMS` (`368 B`) | `PACGPF` (`params.om:32`, `context.om:946`). `IMPLEMENTED`, `HOST_VERIFIED` |
| `BLACKWELL_CHANNEL_GPFIFO_B` | `0xca6f` | `51823` | `hDevice` / `hTSG` | `NV_CHANNEL_ALLOC_PARAMS` (`368 B`) | `GB20B_REQUIRED` (`gb20b-gsp-boot.md` §1); check `CLASSLIST` on live GB20B |

#### Parameter Layouts (`gpu/driver/chan/params.om`)

- **`NV_CHANNEL_GROUP_ALLOCATION_PARAMETERS` (`PASZTSG = 20 B`, `params.om:144-156`)**: `hObjectError` (`+0`, `u32`), `hObjectEccError` (`+4`, `u32`), `hVASpace` (`+8`, `u32`), `engineType` (`+12`, `u32`: `1` = `NV2080_ENGINE_TYPE_GRAPHICS`), `bIsCallingContextVgpuPlugin` (`+16`, `u8 = 0`).
- **`NV_CTXSHARE_ALLOCATION_PARAMETERS` (`PASZCTX = 12 B`, `params.om:157-167`)**: `hVASpace` (`+0`, `u32`), `flags` (`+4`, `u32`: `1` = `NV_CTXSHARE_ALLOCATION_FLAGS_SUBCONTEXT_ASYNC`), `subctxId` (`+8`, `u32`).
- **`NV_CHANNEL_ALLOC_PARAMS` (`PASZCHAN = 368 B`, `params.om:186-236`)**:
  - `+0x00` (`0`): `hObjectError` (`u32`)
  - `+0x04` (`4`): `hObjectBuffer` (`u32`; `0` on GSP direct path, `hFifoMem` on Linux RM)
  - `+0x08` (`8`): `gpFifoOffset` (`u64` — **GPU VA**, not backing PA; `mem_utils_gm107.c:1232`)
  - `+0x10` (`16`): `gpFifoEntries` (`u32`, power of 2 in `2..65536`)
  - `+0x14` (`20`): `flags` (`u32` — **GSP-client rewrite** `kernel_channel.c:2814-2821`: `(flags & 0xFFC000FF) | (1 << 21) | ((chid % 8) << 8) | (((chid / 8) & 0x1FF) << 12)`)
  - `+0x18` (`24`): `hContextShare` (`u32`)
  - `+0x1C` (`28`): `hVASpace` (`u32`)
  - `+0x20` (`32`): `hUserdMemory[0]` (`u32`; `[1..7]` zero)
  - `+0x40` (`64`): `userdOffset[0]` (`u64`; `[1..7]` zero)
  - `+0x80` (`128`): `engineType` (`u32`: `1` = `NV2080_ENGINE_TYPE_GRAPHICS`)
  - `+0x88` (`136`): `subDeviceId` (`u32`)
  - `+0x8C` (`140`): `hObjectEccError` (`u32`)
  - `+0x90..0xEF` (`144..239`): Four `NV_MEMORY_DESC_PARAMS` (`24 B` each: `base u64`, `size u64`, `addressSpace u32`, `cacheAttrib u32`):
    - `+144`: `instanceMem` (`4096 B`, `addressSpace = 2` SYSMEM)
    - `+168`: `userdMem` (`512 B`, `addressSpace = 2` SYSMEM)
    - `+192`: `ramfcMem` (`512 B`, `addressSpace = 2` SYSMEM, aliases `instanceMem` base)
    - `+216`: `mthdbufMem`
  - `+0xF0` (`240`): `hPhysChannelGroup` (`u32`)
  - `+0xF4` (`244`): `internalFlags` (`u32`: `PRIVILEGE[1:0] | ERROR_NOTIFIER_TYPE[3:2] | ECC_ERROR_NOTIFIER_TYPE[5:4]`)
  - `+0xF8` (`248`): `errorNotifierMem` (`24 B` `NV_MEMORY_DESC_PARAMS`)
  - `+0x110` (`272`): `eccErrorNotifierMem` (`24 B` `NV_MEMORY_DESC_PARAMS`)
  - `+0x128` (`296`): `ProcessID` (`u32`), `+0x12C` (`300`): `SubProcessID` (`u32`)

#### Channel Backing Structures (`gpu/driver/chan/chan.om`, `complete.om`)

- **Instance Block (`CHINSZ = 4096 B`)**: RAMIN page directory base at byte offset `0x200` (`512`, word 128): low dword `(pdb & 0xFFFFF000) | (1 << 11) | 2` (`BIG_PAGE_SIZE_64K | SYSMEM_COHERENT`), high dword `pdb >> 32`.
- **USERD (`CHUDSZ = 512 B`, `Nvc96fControl`)**: `GPPut` (`u32`) at offset **`0x8C` (`140`)**. Blackwell USERD has **no `GPGet`** (`0x90..0x1FF` is ignored); completion must be tracked via hardware semaphores in host-visible GPU-uncached memory.

#### Channel Schedule Control (`RPC 76`)

| Control ID (Hex) | Decimal | Name | Target Object | Param Size | Layout | Status |
| --- | ---: | --- | --- | ---: | --- | --- |
| `0xa06c0101` | `2691432705` | `NVA06C_CTRL_CMD_GPFIFO_SCHEDULE` | `KEPLER_CHANNEL_GROUP_A` | `3 B` | `bEnable` (`+0`, `u8`), `bSkipSubmit` (`+1`, `u8`), `bSkipEnable` (`+2`, `u8`) | `IMPLEMENTED`, `HOST_VERIFIED` (`PACMSCH`, `params.om:238`, `rmchan.om:239`) |

#### Teardown Ordering (`gpu/driver/chan/rmchan.om:13-15`)

1. `NVA06C_CTRL_CMD_GPFIFO_SCHEDULE` (`bEnable = 0`) to disable TSG.
2. Drain in-flight work via bounded completion semaphore poll (`cmdrain`); on timeout, quarantine DMA backing without freeing.
3. `RPC 10` (`FREE`) in strict reverse dependency order: `BLACKWELL_COMPUTE_B` -> `BLACKWELL_CHANNEL_GPFIFO_*` -> `FERMI_CONTEXT_SHARE_A` -> `KEPLER_CHANNEL_GROUP_A` -> `FERMI_VASPACE_A` -> `NV20_SUBDEVICE_0` -> `NV01_DEVICE_0` -> `NV01_ROOT`.

---

### Stage 4: Compute Object & Pushbuffer Submission

#### Class ID

| Class Name | Hex | Decimal | Parent | Param Struct & Size | Notes / Status |
| --- | --- | ---: | --- | --- | --- |
| `BLACKWELL_COMPUTE_B` | `0xcec0` | `52928` | `hChannel` | `0 B` (empty params) | `PACCMP` (`params.om:33`, `context.om:954`). Retry on `NV_ERR_NO_MEMORY` (`81` = `0x51`) during bring-up if prior client teardown is still draining. `IMPLEMENTED`, `SILICON_VERIFIED` (via `nvidia.ko`) |

#### Pushbuffer Method Framing (`gpu/driver/chan/chan.om`, `complete.om`, `gpu/nvidia/native/blackwell/launch.om`)

- **Method header (`INC_METHOD`)**: `(2 << 28) | ((count & 0xFFF) << 16) | ((subc & 0x7) << 13) | (method_byte_offset >> 2)`
- **Key Blackwell compute & host methods observed in `launch.om` and `complete.om` (`IMPLEMENTED`):**
  - Subchannel `1` (compute class `0xcec0`):
    - `0x0184` (count `1`): binds/selects compute class `0xcec0` (`gbsetup`, `launch.om:150`).
    - `0x0180` / `0x0188` / `0x01B0`: inline-to-memory DMA upload for driver constant buffer and QMD (`gbdma`, `launch.om:169-178`).
    - `0x0318` (`792`, count `98`): inline 384-byte (96-dword) QMD launch packet (`gbinline`, `launch.om:179-190`).
  - Subchannel `0` (GPFIFO host class):
    - `0x0028` (`40`, count `4`): GPU L2 cache flush before CPU readback (`launch.om:224-228`).
    - `0x005C..0x006C` (`92..108`, count `5`, method index `23`): Host semaphore release/acquire (`complete.om:41-92`): `SEMAPHORE_ADDR_LO`, `SEMAPHORE_ADDR_HI`, `PAYLOAD_LO`, `PAYLOAD_HI`, `EXECUTE` (`1` = release, `0` = acquire; `0x100001` = release with WFI in `launch.om:197`).

---

### Stage 5: Kick / Doorbell

#### Usermode Classes & Work Submit Token Control

| Type | ID (Hex) | Decimal | Name | Parent / Target | Param Size | Notes / Status |
| --- | --- | ---: | --- | --- | ---: | --- |
| Class | `0xc361` | `50017` | `VOLTA_USERMODE_A` | `hSubDevice` | `0 B` | Usermode doorbell BAR page (`64 KiB` mmap). `IMPLEMENTED` (`context.om:900`, `dispatch.om:10`) |
| Class | `0xc661` | `50785` | `HOPPER_USERMODE_A` | `hSubDevice` | `0 B` | Hopper/Blackwell usermode doorbell BAR page. `IMPLEMENTED` (`dispatch.om:10`, `card.om:120`) |
| Control | `0xc36f0108` | `3278831880` | `NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN` | `hChannel` | `4 B` | Returns `u32 workSubmitToken` at `+0` (init request with `0xFFFFFFFF`). `IMPLEMENTED` (`context.om:972`, `dispatch.om:56`) |

#### Work Submit Token Encoding — Critical `GB10B` vs. `GB20B` Delta

| Target | Formula | Bit Semantics | Provenance |
| --- | --- | --- | --- |
| `GB10B` (`GB10B_LEGACY`) | `((runlist & 0x7F) << 16) \| (chId & 0xFFF)` | Bit 22 active-low (`gpu/driver/chan/chan.om:75-77`) | `IMPLEMENTED` (`chan.om`, `GB10B_LEGACY`) |
| **`GB20B` (`GB20B_REQUIRED`)** | **`0x40000000 \| ((runlist & 0x7F) << 16) \| (chId & 0xFFF)`** | **Bit 30 `RUNLIST_DOORBELL_ENABLE` active-high** (`kfifoGenerateWorkSubmitTokenHal_GB202`, `gb202/dev_vm.h:30-32`, `kernel_fifo_gb202.c:73-76`); `runlist <= 127`, `chId <= 4095` | `GB20B_REQUIRED` (`gb20b-gsp-boot.md` §1) |

#### GPFIFO Entry & Doorbell Kick Sequence

1. **GPFIFO Entry (`64-bit` LE at `gpfifo_base + (put % entries) * 8`)**:
   - `entry = (va & ~3ULL) | ((uint64)(words & 0x1FFFFF) << 42) | (1ULL << 41)`
   - Constraints: `va < (1ULL << 40)` (`1 TiB`), `va` 4-byte aligned, `1 <= words <= 0x1FFFFF`, bit `41` (`LEVEL`) set (`chan.om:86-88`, `context.om:1048`).
2. **Advance `GPPut`**:
   - Write `(put + 1) % entries` (`u32` LE) to USERD offset **`0x8C` (`140`)** (`chan.om:260`, `context.om:1055`).
3. **Barrier & Ring Doorbell**:
   - Execute memory barrier (`DSB SY`) so GP entry and USERD `GPPut` are visible before doorbell.
   - Write 32-bit `workSubmitToken` to:
     - **Direct BAR0 (own-driver / VFIO):** `0x00BB0090` (`CHDBELL = 12255376`, VF base `0xB80000 + 0x30090`, `chan.om:50`).
     - **Mapped Usermode Page (`VOLTA_USERMODE_A` / `HOPPER_USERMODE_A`):** offset `0x90` (`144`, `context.om:1056`).

---

## 5. Pure-Omega Driver Milestone Alignment & Open Gaps

To progress `gpu/driver/` from `HOST_VERIFIED` `GB10B` replay to `GB20B` bare-metal compute bring-up:

1. **Channel class & doorbell token (`GB20B_REQUIRED`)**: `gpu/driver/chan/params.om` currently hardcodes `PACGPF = 0xc96f` (`BLACKWELL_CHANNEL_GPFIFO_A`) and `gpu/driver/chan/chan.om` `chtoken` omits bit 30 (`0x40000000`). Add `GB20B` selection for `0xca6f` (`BLACKWELL_CHANNEL_GPFIFO_B`) and `0x40000000 | (rl << 16) | chid`, or retrieve the token via `NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN` (`0xc36f0108`) over `RPC 76`.
2. **Compute object wiring in `rmchan.om`**: `PACCMP = 0xcec0` (`BLACKWELL_COMPUTE_B`) is defined in `params.om`, but `rmchan.om` stops after channel scheduling (`RMSACTV`) and does not yet allocate/free `0xcec0` as a child of `rmhchan`.
3. **Page directory RPC wiring**: `pasetpd` (`RPC 54`) and `paunsetpd` (`RPC 79`) are implemented in `params.om` but not yet wired into `gsp/boot.om` (`brmalloc`/`brmctrl`/`brmfree` only cover `103`, `76`, `10`).
4. **Registry table population**: `arena.om` and `boot.om` enforce canonical `PACKED_REGISTRY_TABLE` validation for `RPC 73`; Window 0 bring-up should start with empty registry (`breg 0`) and add `RMGspLogLevel`/`RMDisableDisplay` only if bare-metal GSP logs indicate a requirement.
5. **Hardware qualification**: All `gpu/driver/` GSP/channel milestones remain `HOST_VERIFIED` (`hardware = NOT_RUN`) until a reviewed Window 0 cold boot on the Spark produces a content-addressed receipt under `evidence/`.
