# gpu/nvidia/driver

One slice of the CUDApp merge, not the move of a directory: new Omega for part of the decision logic still
written in C in CUDApp `nvrm/` and `m16/` (CUDApp main 84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66), with the
gate that checks it against that C.

Much of `nvrm/` and `m16/` was already in Omega before this directory: `gpu/nvidia/native/nvrm/`
(policy, VA allocator, struct packing, RM and UVM wire, the GB10 driver client `context.om`) and
`gpu/nvidia/om/engine/eng.om` (the M16 wait machine, lifecycle, visibility and requalify gates, the
release packet). This directory adds the pieces listed below. `coverage.tsv` names, for every C function
of `nvrm/` and `m16/`, where its logic lives now; the section "Still C" says what is left.

## Files

| File | Holds | Checked by the gate against the C |
|---|---|---|
| `card.om` | `drv_card`, `drv_bdf`: which card the client opens. `drv_marshal`: the class-presence words `select_classes` hands to the Ampere policy. `drv_select`: `drv_marshal` plus the call to `amp_runtime`. `drv_retire`: the GPFIFO retire window | `drv_card` against `card_index`; `drv_marshal` against the words `select_classes` builds; `drv_retire` against `nvrm_retire`. `drv_select` is compiled and not run |
| `diag.om` | `/proc/meminfo` and `/proc/buddyinfo` readers; the two allocation-failure messages | against `meminfo_kb`, `buddy_free_blocks_ge`, `fail_alloc_context`, `fail_channel_no_memory` (the text `fail` stores) |
| `m16.om` | `/proc/self/maps` check; wait result and kind names; `drv_wdur`, `drv_wend`, `drv_wstep` (deadline and one look of the marker wait); `drv_wait_ge`, the marker wait on a mapping; `drv_enqok`, the count bound of `m16_native_enqueue_methods`; `drv_slot`, the slot search of `m16_native_alloc_memory` | `drv_maps` against `check_proc_maps` (the 0/1 answers; its -1 when the file cannot be opened is left to the caller); the names against `m16_gpu_wait_result_name`, `m16_gpu_wait_kind_name`; the wait decisions against `m16_native_wait_marker_ge` on a scripted clock; `drv_enqok` and `drv_slot` against those two functions |
| `nvrm.om` | `drv_chan`, the channel guard of `nvrm_chan_put` and `nvrm_chan_retire`; `drv_span`, `drv_lrow`, `drv_copy`, the checks of `copy_live`, `nvrm_copy_to` and `nvrm_copy_from`; `drv_vramok`, the SM86 check of `nvrm_alloc_vram`; `drv_asize`, `drv_livefull`, the size and table checks of `alloc_with_cacheability`; `drv_vinfo`, the answer of `nvrm_vram_info` | each against that C: `nvrm_chan_put`, `nvrm_chan_retire` (with `drv_retire`), the copy result and message, the allocation refusal and rounded size, the VRAM answer and message |
| `gate.om` | the gate program. It also checks eng.om's existing `fcls` against the C branch of `m16_gpu_wait_failure_class` | none |
| `parts.txt` | the order the parts are joined in before `seed/out/omc` compiles them | none |
| `oracle-cases.tsv` | cases printed by the C oracle; `gate.om` documents the columns | none |
| `coverage.tsv` | every C function of CUDApp `nvrm/` and `m16/` at 84b524ca, and where its logic lives: an Omega path, device shell, test program, or still C. Generated (see "The oracle"); count it with the command in its header | none |

`parts.txt` starts with `gpu/nvidia/native/nvrm/counts.om` because it carries the one `om2` line and the
decimal readers, then `gpu/nvidia/om/encoder/amp_runtime.om`, which `drv_select` calls, and
`gpu/nvidia/om/engine/fixture_rest.om` and `eng.om`, for `fcls`.

The message texts stay with the C `fail`, which formats them into the client; the gate compares which
message the C chose (a code per message) with the code the Omega returns.

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
| `extract.sh` | `9873d843e811e5c0a3d48cc3b2186f896543a2deffdd51ae58e0e612393d4f6f` | copies the C function bodies, and the types and context they need, by line number from a CUDApp checkout, refusing any commit but 84b524ca |
| `extract.inc` | `5ff7fe0d6e9cd040a4986cf381537e2790814ef05bd3419314ed2228594fd697` | the function bodies `extract.sh` printed |
| `extract-types.inc` | `6f51e82cbed2538ab9391de6888feeb1fc516fd567bfe18de303de931f9b0caf` | the client types `extract.sh` printed |
| `extract-ctx.inc` | `eb1f783b3af3be2e9941967d94f901ba3556d3cbce123ab96de7a87194424779` | the context declarations `extract.sh` printed |
| `oracle.c` | `4c13d245ccf2b65902083a830d3aff65509f20539df09143a1d83892236ad52b` | runs those bodies on generated inputs with a fixed random seed and prints `oracle-cases.tsv` |
| `controls.sh` | `969ca2c34e92b55232858504a7408165655bc018a17f767f318f5c8d791bb8ff` | table and source mutations; each must make the gate fail |
| `cfuncs.awk` | `bd79d95ecd1a89f51591dba27a871e1e3bdff2143a2ac4f49ac49fdce5b07c9c` | lists every C function definition of the given files |
| `coverage.sh` | `6010e0683fb5911ae23fae7ae09349ea7685ef5af830000856c0e79afea9accf` | prints `coverage.tsv` from `cfuncs.awk` and `coverage-map.tsv`; fails on an unmapped function, an unused map row, or an Omega path missing from the tree |
| `coverage-map.tsv` | `3147d5b3869fe91ddd96bae25d566f29fdc66f3f90718eaf471b2fd5d76c57a4` | where each function's logic lives, written once by hand |

`oracle.c` compiles the kept original C branches, not CUDApp's default build: it sets
`CUDAPP_MIGRATION_PENDING_C_NVRM_ALLOC=1`, `CUDAPP_MIGRATION_PENDING_C_ENGINE_FIXTURE_REST=1`,
`CUDAPP_MIGRATION_PENDING_C_NVRM=1` and `CUDAPP_MIGRATION_PENDING_C_NVRM_STRUCT=1`, and makes `CARD_GET` a
direct member read. In CUDApp's default build `meminfo_kb`, `buddy_free_blocks_ge`, the fixture text, the
card read and the request structs already go through Omega; the checks this gate compares are the same in
both branches. `omega_ampere_policy` is replaced by a stub that records the words `select_classes` built,
and `nv_ioctl` by one that returns the case's code and heap fields. Each `/proc` read goes to a scripted
file and each clock read to a scripted clock, so the run is the same every time. Rebuild, from a directory
holding these files and a CUDApp checkout at 84b524ca in `../cudapp-ref`:

    bash extract.sh && R=../cudapp-ref/third_party/nvidia-open-580.173.02; gcc -O1 -Wall -Wno-unused-function -I. -I$R/kernel-open/common/inc -I$R/src/common/sdk/nvidia/inc -I$R/src/nvidia/arch/nvalloc/unix/include -o oracle oracle.c && ./oracle > cases.tsv

`cases.tsv` must equal `oracle-cases.tsv`. `controls.sh <scratch-dir>` runs from the root of an omega-mv
checkout and prints `CONTROLS CAUGHT all` when every mutation fails the gate. From the root of an omega-mv
checkout, `bash coverage.sh ../cudapp-ref . > gpu/nvidia/driver/coverage.tsv` regenerates the table, which
must come out unchanged.

## Hardware tier: NOT_RUN

`drv_wait_ge` reads the marker word through an existing mapping (`mapget`) and sleeps 50 microseconds per
look, as the C does with `usleep(50)`. It compiles; it has not been run against a GPU.

## Still C

Not rewritten here, and not checked by this gate (`coverage.tsv` lists each function by name):

- the device side of `nvrm/nvrm.c`, `nvrm/native_client.h`, `nvrm/cpu_barrier.h` and `m16/m16_native.c`
  (ioctl, mmap, doorbell, barrier, clock, byte copies), marked `device shell`. Omega code for a
  single-channel client exists in `gpu/nvidia/native/nvrm/context.om`, `transport.om` and
  `gpu/nvidia/native/streams/submit.om`; it is not compared with this C;
- the rows marked `still C: decision logic, not yet ported`: the open, channel, free and close sequences
  with their unwinds and teardown order, the ready guards and check order of `nvrm_enqueue` and
  `nvrm_chan_submit`, `quarantine_allocation`, the slot lookup of `m16_native_free_memory`, and the
  allocate, map and unwind sequence of `alloc_with_cacheability` (its size and table checks are in
  `nvrm.om`);
- the null-pointer refusal at the top of `m16_native_wait_marker_ge` (`!marker` returns -1).
  `drv_wait_ge` takes a mapping handle and an offset, not a pointer, so that check belongs to whoever
  makes the mapping; nothing in Omega makes it yet;
- the C wait machine branch `wait_core`, whose Omega form is `eng.om`; this gate checks only `fcls`;
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
