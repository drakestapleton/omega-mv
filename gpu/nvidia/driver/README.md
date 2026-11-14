# gpu/nvidia/driver

One slice of the CUDApp merge, not the move of a directory: new Omega for part of the decision logic still
written in C in CUDApp `nvrm/` and `m16/` (CUDApp main 84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66), with the
gate that checks it against that C.

Much of `nvrm/` and `m16/` was already in Omega before this directory: `gpu/nvidia/native/nvrm/`
(policy, VA allocator, struct packing, RM and UVM wire, the GB10 driver client `context.om`) and
`gpu/nvidia/om/engine/eng.om` (the M16 wait machine, lifecycle, visibility and requalify gates, the
release packet). This directory adds the pieces listed below. The section "Still C" lists what is not
rewritten here.

## Files

| File | Holds | Checked by the gate against the C |
|---|---|---|
| `card.om` | `drv_card`, `drv_bdf`: which card the client opens. `drv_marshal`: the class-presence words `select_classes` hands to the Ampere policy. `drv_select`: `drv_marshal` plus the call to `amp_runtime`. `drv_retire`: the GPFIFO retire window | `drv_card` against `card_index`; `drv_marshal` against the words `select_classes` builds; `drv_retire` against `nvrm_retire`. `drv_select` is compiled and not run |
| `diag.om` | `/proc/meminfo` and `/proc/buddyinfo` readers; the two allocation-failure messages | against `meminfo_kb`, `buddy_free_blocks_ge`, `fail_alloc_context`, `fail_channel_no_memory` (the text `fail` stores) |
| `m16.om` | `/proc/self/maps` check; wait result and kind names; `drv_wdur`, `drv_wend`, `drv_wstep` (deadline and one look of the marker wait); `drv_wait_ge`, the marker wait on a mapping | `drv_maps` against `check_proc_maps` (the 0/1 answers; its -1 when the file cannot be opened is left to the caller); the names against `m16_gpu_wait_result_name`, `m16_gpu_wait_kind_name`; the wait decisions against `m16_native_wait_marker_ge` on a scripted clock |
| `gate.om` | the gate program | none |
| `parts.txt` | the order the parts are joined in before `seed/out/omc` compiles them | none |
| `oracle-cases.tsv` | cases printed by the C oracle; `gate.om` documents the columns | none |

`parts.txt` starts with `gpu/nvidia/native/nvrm/counts.om` because it carries the one `om2` line and the
decimal readers, then `gpu/nvidia/om/encoder/amp_runtime.om`, which `drv_select` calls.

`nvrm_chan_retire` applies the same window as `nvrm_retire` to an extra channel, after its own guard
(`ch == 0 || ch > n_extra` returns). The gate runs only `nvrm_retire`; the guard has no Omega form here.

## The gate

`tests/gates/run.sh gpu-driver` (manifest `tests/gates/omega-gpu-driver.gate`) joins the parts, compiles
them with `seed/out/omc` (sha256 checked), and runs the gate on `oracle-cases.tsv`. The gate recomputes
every case with the Omega functions and compares the result with what the C printed. For the first case of
each kind it also runs the same case with the expected answer changed, and that must fail; this shows the
comparison is not empty, not that the Omega logic is tested. The step counts the cases and kinds from the
table itself and requires exactly:

    OMEGA-GPU-DRIVER PASS cases=<cases in the table> controls=<kinds> caught=<kinds> hardware=NOT_RUN

Any mismatch prints `FAIL line N` and the gate exits 1.

For the marker wait, the gate runs the loop of `drv_wait_ge` with the scripted clock in place of `monons`
and the case's marker in place of `mapget`. Each look is `drv_wstep`, the function `drv_wait_ge` itself
calls, so the decisions (reached, look again, the last look after the deadline) are the checked ones. The
clock reads, the marker read and the sleep inside `drv_wait_ge` are not run by any gate.

The source and table mutations that show the gate catches broken Omega are not in this tree (they are a
shell script). See "The oracle".

## The oracle

The C oracle is kept outside the repository by the lane that wrote this directory, because only Omega goes
in it. Its files are identified by sha256:

| File | sha256 | Does |
|---|---|---|
| `extract.sh` | `e15f4b704f503266f5c14022a58abf817a5553ef07d5e1aec40e3926e9dcfa49` | copies the C function bodies by line number from a CUDApp checkout, refusing any commit but 84b524ca |
| `extract.inc` | `d430e25765cb76e75a66a2cd2fd222079fc104e76e9662de5117427d2a17b343` | what `extract.sh` printed |
| `oracle.c` | `57e327bb931ab7665dd165ecdff6ee560dc73f308ac19962fa7a362f68260bda` | runs those bodies on generated inputs with a fixed random seed and prints `oracle-cases.tsv` |
| `controls.sh` | `d50492b7f9492b79dacd87c32f396efc5369b5dd4c0c27f9fdfa6339f1e09e19` | table and source mutations; each must make the gate fail |

`oracle.c` compiles the kept original C branches, not CUDApp's default build: it sets
`CUDAPP_MIGRATION_PENDING_C_NVRM_ALLOC=1` and `CUDAPP_MIGRATION_PENDING_C_ENGINE_FIXTURE_REST=1`, and makes
`CARD_GET` a direct member read. In CUDApp's default build `meminfo_kb`, `buddy_free_blocks_ge`, the
fixture text and the card read already go through Omega. `omega_ampere_policy` is replaced by a stub that
records the words `select_classes` built. Each `/proc` read goes to a scripted file and each clock read to a
scripted clock, so the run is the same every time. Rebuild, from a directory holding these files and a
CUDApp checkout at 84b524ca in `../cudapp-ref`:

    bash extract.sh && R=../cudapp-ref/third_party/nvidia-open-580.173.02; gcc -O1 -Wall -Wno-unused-function -I. -I$R/kernel-open/common/inc -I$R/src/common/sdk/nvidia/inc -o oracle oracle.c && ./oracle > cases.tsv

`cases.tsv` must equal `oracle-cases.tsv`. `controls.sh <scratch-dir>` runs from the root of an omega-mv
checkout and prints `CONTROLS CAUGHT all` when every mutation fails the gate.

## Hardware tier: NOT_RUN

`drv_wait_ge` reads the marker word through an existing mapping (`mapget`) and sleeps 50 microseconds per
look, as the C does with `usleep(50)`. It compiles; it has not been run against a GPU.

## Still C

Not rewritten here, and not checked by this gate:

- the device side of `nvrm/nvrm.c`, `nvrm/native_client.h`, `nvrm/cpu_barrier.h` and `m16/m16_native.c`
  (ioctl, mmap, doorbell, barrier). Omega code for a single-channel client exists in
  `gpu/nvidia/native/nvrm/context.om`, `transport.om` and `gpu/nvidia/native/streams/submit.om`; it is not
  compared with this C;
- decisions inside those device functions: the count bound in `m16_native_enqueue_methods`, the slot
  search in `m16_native_alloc_memory`, `nvrm_chan_put`, the range checks in `copy_live`, the size checks in
  `alloc_with_cacheability`, the SM86 check in `nvrm_alloc_vram`, the `nvrm_chan_retire` guard, the C
  branch of `m16_gpu_wait_failure_class` (its Omega branch is `eng.om`), and the null-pointer refusal at
  the top of `m16_native_wait_marker_ge` (`!marker` returns -1). `drv_wait_ge` takes a mapping handle and
  an offset, not a pointer, so that check belongs to whoever makes the mapping; nothing in Omega makes it yet;
- the C test programs of `nvrm/` and `m16/` and the seccomp fixture `nvrm/native_ioctl_fixture.h`.

## Limits

The C writes its messages into `char err[256]` and reads `/proc` lines with fixed `fgets` buffers. The
Omega has neither limit: messages are sized from what they hold, and files are read whole. So a message
the C would cut at 255 bytes, or a `libcuda.so` line the C would split across two reads, is handled
differently; no case in the table reaches either. Two limits remain, and both refuse rather than cut:

- `counts.om`, which this directory reuses, walks at most 512 bytes of a line, so a `/proc` line longer
  than that is refused.
- The gate reads one table line into a 65536-byte array, so a longer line is refused by name. Omega array
  sizes are fixed when the program is compiled.
