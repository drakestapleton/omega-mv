# gpu/nvidia/driver: what the device side needs

`client.om` decides every driver command of the client's setup and teardown; it sends none. Each command is
a `dx_` effect. On the host gate `fx.om` answers the effects from a script and records them, and
`seqgate.om` compares the record with the C oracle (`README.md`, "The sequence gate"). No device part that
answers the effects with real ioctls exists yet, and nothing here has run on a GPU: the hardware tier is
NOT_RUN.

This file says, for each effect and for each C function still marked `device shell` in `coverage.tsv`,
what it needs from the machine, and which part of it the host can check.

## The effects of client.om

The existing Omega GB10 client `gpu/nvidia/native/nvrm/context.om` already sends most of these commands
for its single-channel client: `nvalc` (RM_ALLOC), `nvctrl` (RM_CONTROL), `nvfree` (RM_FREE),
`nvcpumap` (map an RM object into the process), `nvdrop`, and the UVM calls of `nvstart` and `nvchan`.
The request bytes are `struct.om`, `wire.om`, `wire_pack.om`, `uvm_wire.om` and `uvm_map_wire.om`.

| Effect | Command on the device | Needs from the machine | Host-checkable part, and where |
|---|---|---|---|
| `dx_admit_open` | admission of a new client | the process's admission state | the decision is the caller's (`nvrm_open` ordering, `client.om`) |
| `dx_slot`, `dx_recycle` | take and give back a per-client VA slot | an atomic slot counter shared between clients | slot successor `alloc_scalar.om` (mode 0), cover `policy.om` nvrm_vcover |
| `dx_fopen`, `dx_fclose` | open and close `/dev/nvidiactl` and `/dev/nvidia-uvm` | the device nodes | which nodes, in which order, and when to close: `client.om` |
| `dx_opendev` | open `/dev/nvidiaN` and register the fd with the control fd | the device node; NV_ESC_REGISTER_FD | `client.om` (minor from the card table, `card.om`) |
| `dx_alloc`, `dx_free` | NV_ESC_RM_ALLOC, NV_ESC_RM_FREE | the RM; request bytes `wire_pack.om` | handles, classes, parents and request fields: `client.om` |
| `dx_ctrl` | NV_ESC_RM_CONTROL | the RM | command numbers and fields: `client.om` |
| `dx_uvm`, `dx_uvmraw` | UVM ioctls (INITIALIZE, MM_INITIALIZE, REGISTER_GPU, REGISTER_GPU_VASPACE, REGISTER_CHANNEL and their unregisters) | `/dev/nvidia-uvm` | which call, with which fields, in which order: `client.om`; bytes `uvm_wire.om` |
| `dx_ioctl` | NV_ESC_CARD_INFO on the control fd | the driver's card table | the card choice `card.om` drv_card |
| `dx_cardidx`, `dx_admit_card`, `dx_cardget` | read the card table answer | the CARD_INFO answer | `card.om` |
| `dx_nsget` | read one field of the last RM answer | the answer bytes | field layout `struct.om` |
| `dx_select` | pick the target SM, the discrete flag and the compute, GPFIFO and usermode classes from the RM's class list | the class list the RM returned | `card.om` drv_select (gated) |
| `dx_map` | NV_ESC_RM_MAP_MEMORY plus mmap of the device node at a fixed address | the RM and the kernel's mmap | flags, target and size: `client.om` |
| `dx_reserve`, `dx_drop` | reserve and release the CPU range (mmap PROT_NONE, munmap) | the kernel | sizes and order: `client.om` |
| `dx_transfer`, `dx_finish` | hand a mapping to the client's mapping context, and close the context | `context.om` mapping state | `context.om` |
| `dx_vatake`, `dx_varel` | take and release GPU VA inside the slot | the slot range | `alloc.om` (the release refusal faults the client: `client.om` cn_varel) |
| `dx_uvmmap`, `dx_uvmfree`, `dx_dmaunmap` | UVM_CREATE_EXTERNAL_RANGE, UVM_MAP_EXTERNAL_ALLOCATION, UVM_FREE, the RM DMA unmap | `/dev/nvidia-uvm`, the RM | which to undo after a partial map: `client.om` cn_alloc and cn_free |
| `dx_validate` | check an Ampere pushbuffer before it is published | a CPU mapping of the pushbuffer | `alloc_push.om` with the `amp_runtime` policy |
| `dx_publish` | write one GP entry and GPPut through the ring mapping | the mapped ring and USERD | `policy.om` nvrm_gpentry; slot and put arithmetic `client.om` |
| `dx_doorbell` | write the work-submit token to the usermode doorbell | the mapped usermode page | when a refusal faults the client: `client.om` cn_ring |
| `dx_sleep` | wait before a retried compute-object allocation | a clock | the retry decision `policy.om` nvrm_retry |
| `dx_zero` | zero a new allocation through its CPU mapping | the CPU mapping | size: `client.om` |
| `dx_errno` | the last system error number | the kernel's answer | none |

## C functions still marked device shell

`coverage.tsv` has 29 such rows. Each one is the machine side of an effect above, a clock or barrier
instruction, or a wrapper with no decision of its own.

| C function | Needs from the machine | Host-checkable part |
|---|---|---|
| `nvrm.c omega_gpu_live_marker` | the context.om mapping token of a live allocation | the lookup itself is `context.om` |
| `nvrm.c fail` | writes the message text into the client | which message: the code `client.om` returns (`ER` events, gated); the text is not compared |
| `nvrm.c nv_ioctl` | the ioctl system call | none |
| `nvrm.c rm_alloc`, `rm_free`, `rm_control`, `dma_unmap_checked` | the RM ioctls | request bytes `wire_pack.om`; when each is sent `client.om` |
| `nvrm.c uvm_free_checked` | the UVM_FREE ioctl | when it is sent `client.om` |
| `nvrm.c uvm` | the UVM ioctls | bytes `uvm_wire.om`; when each is sent `client.om` |
| `nvrm.c open_dev_fd` | open and NV_ESC_REGISTER_FD | `client.om` (dx_opendev) |
| `nvrm.c map_to_cpu` | RM_MAP_MEMORY and mmap at a fixed address | flags and size `client.om` (dx_map) |
| `nvrm.c uvm_map` | the UVM range and map ioctls | which to undo on a refusal, through the answer code: `client.om` cn_alloc |
| `nvrm.c nvrm_userd_gpput` | the address of GPPut inside the ring mapping | the offset is `userd` in the client state |
| `cpu_barrier.h nvrm_cpu_barrier`, `nvrm_cpu_relax` | the barrier and yield instructions | none |
| `native_client.h nvrm_native_ok` | status and result of a context call | none |
| `native_client.h nvrm_file_open`, `nvrm_file_close`, `nvrm_rm_ioctl`, `nvrm_uvm_ioctl`, `nvrm_cpu_reserve`, `nvrm_cpu_map`, `nvrm_cpu_drop` | open, close, ioctl, mmap and munmap through the context | the context state machine `context.om` |
| `nvrm_policy.h nvrm_om_call` | calls the Omega policy unit from C | the policy `policy.om` (gated elsewhere) |
| `m16_gpu_wait.c real_now_ns`, `m16_native.c now_ns` | the monotonic clock | the deadline arithmetic `m16.om` drv_wdur, drv_wend (gated) |
| `m16_gpu_wait.c real_barrier`, `real_relax` | barrier and yield instructions | none |
| `m16_native.c m16_native_submit_methods` | copies the caller's method words into the mapped pushbuffer | the count bound `m16.om` drv_enqok (gated), then nvrm_enqueue and nvrm_ring, which are `client.om` cn_enqueue and cn_ring (gated) |

## To run it on the GPU

A device part would implement each `dx_` name of `fx.om` with the commands above, composed with
`client.om` in place of `fx.om`, and would be checked first against the same sequences, then on the
chip under the current GPU window procedure. That is the hardware tier, and it has not been run.
