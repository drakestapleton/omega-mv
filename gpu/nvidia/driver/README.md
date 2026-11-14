# gpu/nvidia/driver

Omega form of the decision logic still written in C in CUDApp `nvrm/` and `m16/` (CUDApp main
84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66), with the gate that checks it against that C.

Most of `nvrm/` and `m16/` was already in Omega before this directory: `gpu/nvidia/native/nvrm/`
(policy, VA allocator, struct packing, RM and UVM wire, the GB10 driver client `context.om`) and
`gpu/nvidia/om/engine/eng.om` (the M16 wait machine, lifecycle, visibility and requalify gates, the
release packet). This directory holds what was left of the decision logic. The device side (ioctl, mmap,
doorbell) and the C test programs of those directories are not rewritten here.

## Files

| File | Holds | C it replaces (CUDApp 84b524ca) |
|---|---|---|
| `card.om` | `drv_card`: which card the client opens; `drv_select` / `drv_marshal`: the class list handed to `amp_runtime`; `drv_retire`: the GPFIFO retired count | `nvrm/nvrm.c` `card_index`, `select_classes`, `nvrm_retire`, `nvrm_chan_retire` |
| `diag.om` | `/proc/meminfo` and `/proc/buddyinfo` readers; the two allocation-failure messages | `nvrm/nvrm.c` `meminfo_kb`, `buddy_free_blocks_ge`, `fail_alloc_context`, `fail_channel_no_memory` |
| `m16.om` | `/proc/self/maps` check; wait result and kind names; the marker wait (`drv_wait_ge`) | `m16/m16_requalify.c` `check_proc_maps`; `m16/m16_gpu_wait.c` `m16_gpu_wait_result_name`, `m16_gpu_wait_kind_name`; `m16/m16_native.c` `m16_native_wait_marker_ge` |
| `gate.om` | the gate program | none |
| `parts.txt` | the order the parts are joined in before `seed/out/omc` compiles them | none |
| `oracle-cases.tsv` | cases printed by the C oracle; `gate.om` documents the columns | none |

`parts.txt` starts with `gpu/nvidia/native/nvrm/counts.om` because it carries the one `om2` line and the
decimal readers, then `gpu/nvidia/om/encoder/amp_runtime.om`, which `drv_select` calls.

## The gate

`tests/gates/run.sh gpu-driver` (manifest `tests/gates/omega-gpu-driver.gate`) joins the parts, compiles
them with `seed/out/omc` (sha256 checked), and runs the gate on `oracle-cases.tsv`. The gate recomputes
every case with the Omega functions and compares the result with what the C printed. For the first case of
each kind it also runs the same case with the expected answer changed, and that must fail. The step
counts the cases and kinds from the table itself and requires exactly:

    OMEGA-GPU-DRIVER PASS cases=<cases in the table> controls=<kinds> caught=<kinds> hardware=NOT_RUN

Any mismatch prints `FAIL line N` and the gate exits 1.

## The oracle

The C oracle is kept outside this tree, because only Omega goes in it. It is a C file that copies the
listed function bodies from the CUDApp source, unchanged, runs them on generated inputs with a fixed
random seed, and prints `oracle-cases.tsv`. Its header names the CUDApp commit and the source files.
Each `/proc` read in the C goes to a scripted file, and each clock read to a scripted clock, so the run is
the same every time.

## Hardware tier: NOT_RUN

`drv_wait_ge` reads the marker word through an existing mapping (`mapget`) and sleeps 50 microseconds per
look, as the C does with `usleep(50)`. It compiles and its decisions
are checked against the C on a scripted clock. It has not been run against a GPU. The same holds for the
device side of the C (ioctl, mmap and doorbell code), whose Omega form is `gpu/nvidia/native/nvrm/context.om`.

## Limits

The C writes its messages into `char err[256]` and reads `/proc` lines with fixed `fgets` buffers. The
Omega has neither limit: messages are sized from what they hold, and files are read whole. Two limits
remain, and both refuse rather than cut:

- `counts.om`, which this directory reuses, walks at most 512 bytes of a line, so a `/proc` line longer
  than that is refused.
- The gate reads one table line into a 65536-byte array, so a longer line is refused by name. Omega array
  sizes are fixed when the program is compiled.
