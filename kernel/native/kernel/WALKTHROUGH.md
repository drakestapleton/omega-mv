# Walkthrough: one C-kernel boot, from firmware to a capability-checked message

This walkthrough follows one boot of the AIENOS C kernel under QEMU. It goes from the UEFI entry point through memory setup, interrupts and scheduling to one IPC exchange that the kernel checks against capabilities. Along the way it gives the exact commands to reproduce the result yourself and the lines you should see.

**Scope.** Everything here is the aarch64 QEMU path, and **QEMU is not hardware: a PASS qualifies nothing physical** ([`scripts/qemu_ck_boot_test.sh:21`](../../scripts/qemu_ck_boot_test.sh#L21)). Raspberry Pi 5, iMac and DGX Spark runs have their own records (see the [README](../../README.md#current-state-2026-10-19)), and the older Rust kernel in `crates/` is a separate implementation. Line numbers refer to commit `3be8290b`.

The C kernel is **frozen** (ADR 0039, Drake 2026-10-24): it takes bug fixes only while Aienux is rewritten in Omega ([README.md](../../README.md#current-state-2026-10-19), [native/kernel/README.md](README.md)). This page describes what exists. It is not a plan.

## 1. Why this kernel exists and how it was built

**The problem.** AIENOS needs a kernel it owns, small and deterministic, to replace Linux on the DGX Spark. The model must never be the kernel, and the agent must never be the root of trust ([README.md](../../README.md)). The first native kernel was written in Rust. The project rule is "Rust is scaffolding, Omega is the destination, and C or assembly stay only where hardware, boot, ABI or measurement needs them" (aien-architecture ADR 0024, quoted in [README.md](../../README.md#rules-this-code-follows)).

**How the C kernel was built.** It was ported from the Rust kernel decision by decision, and each port is checked against the same QEMU log patterns as the Rust original:

- The core boot (EL2→EL1, MMU, GICv3, timer) landed as aienos #194, `34c6053` ([`tests/.crumb`](tests/.crumb)).
- "M3 isolation port: tasks, preempt, EL0 lockout, fault isolation, IPC w/ narrowable caps; single core" landed as aienos #201, `0d0efa5` ([`tests/.crumb`](tests/.crumb)).
- The source says it in so many words: the scheduler makes the "Same decisions as scheduler.rs, step for step" ([`core/sched.c:17`](core/sched.c#L17)), and IPC carries the "caps.rs and ipc.rs logic, step for step" ([`core/ipc.c:17`](core/ipc.c#L17)).
- [GATES.md](GATES.md) lists every Rust check pattern next to the C gate that must reproduce it. The M3 rows 16–20 are all `IDENTICAL`.

**One approach that failed.** Multi-threaded QEMU TCG hung in 1 of 40 boots. Single-threaded TCG completed 120 of 120 soak boots, so the gate pins `-accel tcg,thread=single` ([`scripts/qemu_ck_boot_test.sh:87-88`](../../scripts/qemu_ck_boot_test.sh#L87), issue #61).

**Limits to keep in mind.**
- Scheduling is cooperative inside one kernel thread. The timer only preempts during the M3 preemption check.
- The MADT placement row only computes a placement. "no secondary core is started" ([GATES.md row 19](GATES.md)).
- W^X on aarch64 comes from per-region page attributes. The kernel README says of its W^X work: "W^X is not process isolation: everything here still runs in ring 0 in one address space" ([README.md § 2017 iMac image](README.md#2017-imac-image-aienos-kernel-0-x86_64)).

## 2. Boot: firmware → `_start` → `efi_main` → `ck_kernel_entry`

1. The UEFI firmware loads the PE image and calls `_start` ([`native/boot/efi_entry.S:10`](../boot/efi_entry.S#L10)); the entry is declared in [`native/boot/image.ld:15`](../boot/image.ld#L15).
   - On QEMU `virtualization=on` this runs at EL2, still on the firmware's stack and page tables.
   - `_start` applies its own `R_AARCH64_RELATIVE` relocations (lines 11–31), zeroes `.bss` (lines 35–42) and calls `efi_main` (line 44).
2. `efi_main` ([`native/boot/efi_main.c:109`](../boot/efi_main.c#L109)) does three things:
   - reads the exception level;
   - finds the serial console from SPCR;
   - calls `ExitBootServices`, with a retry, before handing over to `ck_kernel_entry(h)` (line 232).

   After `ExitBootServices` the firmware is gone; the handoff block `h` carries the memory map and ACPI pointers ([docs/BOOT_HANDOFF_CONTRACT.md](../../docs/BOOT_HANDOFF_CONTRACT.md)).
3. `ck_kernel_entry` ([`core/kmain.c:362`](core/kmain.c#L362)) runs these steps in order:
   - installs the vector table (`ck_vectors_el2` or `ck_vectors`);
   - validates the handoff with `ck_handoff_check` and panics if it is bad;
   - initialises PSCI;
   - builds the kernel's own memory map with `ck_mm_build` (§3);
   - drops to EL1h through `ck_enter_el1` ([`arch/vectors.S:175-224`](arch/vectors.S#L175)): `ttbr0_el1` and `sctlr_el1` are loaded, `spsr_el2 = 0x3c5`, then `eret`.

   The EL2→EL1h decision is [ADR 0009](../../docs/adr/0009-el2-bootstrap-to-el1h-kernel-transition.md).
4. `ck_el1_main` ([`core/kmain.c:145`](core/kmain.c#L145)) runs the rest in a fixed order:
   1. MMU report and guard-page self-test.
   2. GIC from the ACPI MADT, and a 200 ms timer window.
   3. `kernel: alive`.
   4. CPU features and entropy.
   5. SMP, FPU and inference probes.
   6. **`ck_m3_run`**: threads, EL0, preemption, IPC (line 307).
   7. Device, security and store stages.
   8. The final report and a PSCI reset.

   [native/kernel/README.md § Boot sequence](README.md#boot-sequence) has the longer version.

## 3. Memory: the kernel's own page tables

`ck_mm_build` ([`mm/mmu.c:146`](mm/mmu.c#L146)) starts the frame allocator from the EFI memory map ([`mm/frames.c`](mm/frames.c): `ck_frames_from_efi`, `ck_frames_alloc`). It then maps everything with split permissions ([`mm/mmu.c:17-31`](mm/mmu.c#L17), [`:188-192`](mm/mmu.c#L188)):

- kernel text RX;
- rodata RO+XN;
- data and bss RW+XN;
- a 256 KiB stack with an unmapped guard page below it;
- a 64 MiB heap with a guard page on each side;
- an 8 MiB non-cacheable DMA pool;
- MMIO as Device-nGnRE, XN.

Page-table edits go through `ck_pt_map` and `ck_pt_unmap` ([`mm/pt.c:125`](mm/pt.c#L125)). The boot log proves the switch from live registers (`mmu_switch: … switched=yes`). It also proves that a guard-page touch faults and the fault is contained (`guard_page: ok fault=contained`). [README.md § Memory map](README.md#memory-map-the-kernel-builds) has the full map.

## 4. Interrupts: vectors, GICv3, the timer tick

- The vector table `ck_vectors` ([`arch/vectors.S:19-21`](arch/vectors.S#L19)) saves a frame and sends sync exceptions to `ck_exception` and IRQs to `ck_irq_dispatch`. The IRQ path resumes **whatever frame the dispatcher returns** (`mov sp, x0`, line 84), and that is what makes preemption possible.
- `ck_irq_dispatch` ([`arch/exception.c:91-108`](arch/exception.c#L91)) acknowledges the interrupt at the GIC ([`arch/gic.c`](arch/gic.c): `ck_gic_init`, `ck_gic_ack`, `ck_gic_eoi`). For the EL1 physical timer, INTID 30, it calls `ck_timer_tick` before EOI. If a `ck_tick_switch` hook is installed, it returns the hook's frame.
- `ck_timer_tick` ([`arch/timer.c:64`](arch/timer.c#L64)) re-arms `cntp_cval_el0` 10 ms ahead and counts the tick. Nothing more happens on a tick unless a scheduler hook is installed.

## 5. Scheduling: cooperative switch, timer preemption in the M3 check

- Tasks and run queues: `struct ck_task` and `struct ck_sched` ([`core/sched.h:41-48`](core/sched.h#L41)). `ck_sched_tick` ([`core/sched.c:156`](core/sched.c#L156)) picks the next task.
- The context switch, `ck_ctx_switch` ([`arch/m3.S:19`](arch/m3.S#L19)), saves x19–x30 and sp.
- Cooperative path, `yield_now` in [`core/m3.c:68-83`](core/m3.c#L68): `ck_sched_tick` followed by `ck_ctx_switch`. Two threads must print `ABABABABAB` (`threads: ok`).
- Preemptive path: the M3 check installs `ck_tick_switch = preempt_tick` ([`core/m3.c:217`](core/m3.c#L217)). Two busy tasks that never yield must both make progress, and the timer must switch between them (`preempt: ok … switches=N`).

## 6. Isolation and IPC: one concrete message exchange

The kernel gives each principal a **capability table**. A handle is an index plus a generation (per-resource generations: [ADR 0019](../../docs/adr/0019-per-resource-capability-generation.md)). Every IPC call goes through one gate:

- `ck_cap_lookup` ([`core/ipc.c:73-84`](core/ipc.c#L73)) returns `CK_CAP_INVALID` for a stale or forged handle and `CK_CAP_MISSING_RIGHTS` when `(rights & required) != required`.
- `gated` ([`core/ipc.c:262-269`](core/ipc.c#L262)) also checks that the handle names the right resource.
- `ck_ipc_send` needs `CK_R_WRITE` on the channel ([`:271-279`](core/ipc.c#L271)) and `ck_ipc_recv` needs `CK_R_READ` ([`:281-289`](core/ipc.c#L281)).

`ck_ipc_reset` ([`:245-260`](core/ipc.c#L245)) sets up the exchange:
- principal **A** gets WRITE on the channel, plus READ, WRITE, DERIVE and REVOKE on an object;
- principal **B** gets only READ on the channel.

The boot check `check_ipc` ([`core/m3.c:582-631`](core/m3.c#L582)) runs two EL0 programs. Their system calls arrive in `dispatch_ipc` ([`core/m3.c:460-548`](core/m3.c#L460)):

1. **A sends** a typed message (syscall 3). `ck_ipc_send` passes the WRITE check, and the message enters the channel.
2. **A delegates** a narrowed copy of its object capability to B (syscall 5, `ck_ipc_delegate`): read only.
3. **B receives** (syscall 4). `ck_ipc_recv` passes the READ check, and the kernel compares kind, payload and object against what A sent: `message=delivered`.
4. **B tries to write** through the read-only child (syscall 7). `ck_ipc_object_write` returns `CK_IPC_MISSING_RIGHTS`, and B gets `DENIED` back: `rights=attenuated`. **This is the refusal case.**
5. **B forges** a handle. The lookup fails, and B gets `DENIED`: `forged=denied`.
6. **The kernel revokes** A's object capability (`ck_ipc_revoke`). B runs again, and its derived handle no longer resolves: `revoked=denied`.

All six must hold, and all three programs must exit 0, before the boot prints `ipc: ok`.

The same rules are unit-tested on the host in [`tests/test_ipc.c`](tests/test_ipc.c):
- accepted send and receive at lines 189–191;
- receive with a send-only handle and send with a receive-only handle → `CK_IPC_MISSING_RIGHTS` (lines 169–170);
- wrong resource, stale generation and empty channel (lines 171–174);
- write through the read-only child (line 193).

The capability ABI as a whole: [docs/CAPABILITY_ABI.md](../../docs/CAPABILITY_ABI.md), [docs/CAPABILITY_AUTHORITY_RESOURCE.md](../../docs/CAPABILITY_AUTHORITY_RESOURCE.md).

## 7. Reproduce it

**Requirements.** An offline build that downloads no model and needs no hardware.
- Linux with gcc, binutils, make and bash.
- `qemu-system-aarch64` and the AAVMF firmware (Ubuntu: `qemu-system-arm qemu-efi-aarch64`). The script uses `/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd` unless `AAVMF_CODE` is set. A missing tool or firmware prints `NOT_RUN` and exits 2.
- On a host that is not AArch64, the kernel Makefile uses `aarch64-linux-gnu-` cross tools.

```bash
git clone https://github.com/aien-dev/aienux.git && cd aienux
git checkout 3be8290b317427791b12ae1416f055e5e696712d   # the revision this page was checked at

# (a) host unit test of the IPC rules, about 1 s
make -s -C native/kernel OUT=$PWD/target/teach $PWD/target/teach/host/test_ipc
./target/teach/host/test_ipc                # -> test_ipc: PASS (75 checks), exit 0

# (b) boot the kernel in QEMU and check the log, about 10 s
bash scripts/qemu_ck_boot_test.sh           # -> ... AIENOS_CK_M3: PASS / AIENOS_CK_M1: PASS, exit 0
AIENOS_QEMU_VERBOSE=1 bash scripts/qemu_ck_boot_test.sh   # also prints the serial console

# (c) a safe refusal: a CPU without FEAT_RNG must fail closed
AIENOS_QEMU_CPU=neoverse-n1 bash scripts/qemu_ck_boot_test.sh   # -> AIENOS_CK_M1: FAIL, exit 1
```

**Expected serial lines from (b).** These come from a run at `3be8290b`. Counts, ticks and switch numbers vary from run to run.

```text
mmu: enabled
mmu_switch: firmware=EL2 firmware_mmu=on firmware_ttbr0=0x47fff000 aienos_root=0x40000000 ttbr0_el1=0x40000000 switched=yes
guard_page: ok fault=contained (stack=0x40010000 heap_lo=0x48000000 heap_hi=0x4c001000) [C kernel addition, not in the Rust kernel]
gic: v3
timer_irq: 19 ticks in 200 ms
kernel: alive
kernel_el: EL1h
entropy: rndr feat_rng=yes probe_words=2 retries=0 stuck_test=ok
threads: ok interleave=ABABABABAB
el0: ok write=granted forged=denied fault=contained exit=0
preempt: ok a=18223732 b=11915947 switches=4
placement: worker0=class0/core0 worker1=class0/core1
ipc: ok message=delivered cap=delegated rights=attenuated forged=denied revoked=denied
```

Each line is matched by a `PASS  <description>` row of the script (the patterns are in [`scripts/lib_ck_m1_checks.sh`](../../scripts/lib_ck_m1_checks.sh)), for example `PASS  typed IPC with attenuated revocable delegation`.

**Expected refusal from (c).**

```text
entropy: unavailable reason=absent (ID_AA64ISAR0_EL1.RNDR=0, no FEAT_RNG); security consumers refuse, fail closed
```

followed by `FAIL  no kernel entropy refusal (C kernel addition)` and `AIENOS_CK_M1: FAIL`. The QEMU process exits 0. The gate fails because the kernel refused, as it should, to hand out entropy it does not have.

**What each result establishes.**

| Result | Establishes | Does not establish |
|---|---|---|
| (a) `test_ipc: PASS` | `core/ipc.c` gives the accepted and refused results above, compiled for the host | anything about EL0, the MMU or interrupts |
| (b) `AIENOS_CK_M3: PASS` | under QEMU `virt`, `-cpu max`, single-threaded TCG, this image boots, isolates EL0, preempts and enforces capabilities on IPC | real hardware behaviour, multi-core scheduling, timing |
| (c) `AIENOS_CK_M1: FAIL` | the kernel fails closed when the CPU lacks a hardware random source | that any real CPU lacks or has FEAT_RNG |

The full emulator suite is `bash scripts/ck_gates.sh`. It refuses a dirty tree and writes a receipt to `evidence/`. Upstream components used here: QEMU, and the AAVMF build of TianoCore EDK II UEFI firmware, both as Ubuntu packages, plus GNU gcc and binutils.
