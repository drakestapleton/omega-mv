# Hardware gates: what ran where, and what has no physical receipt

This page and its machine-readable twin [`hardware-gates.tsv`](hardware-gates.tsv) list every
Aienux and GB10 GPU-driver capability that touches hardware, the host and QEMU gates that cover
it, and its physical status. It is the answer to "has this run on the machine?": a row says PASS
only when a receipt file in this repository holds the matching `HWGATE` line. Everything else is
NOT_RUN or MISSING_IMPLEMENTATION, and stays so until a separately authorized attended run
produces its own receipt.

This page grants no hardware, boot, staging, service or firmware authority. Physical driver
qualification is scoped separately (Linear DRA-174 over DRA-149..153); native boot campaigns use
[`campaigns/B7B-PHYSICAL-BOOT-PREP.md`](campaigns/B7B-PHYSICAL-BOOT-PREP.md) and
[`campaigns/SPARK-BOOT-INPUT-20261028.md`](campaigns/SPARK-BOOT-INPUT-20261028.md), and both need
the TRUST-1 owner ceremony first.

## The rule and its check

- Statuses: `PASS`, `FAIL` (observations) and `NOT_RUN`, `BLOCKED_HARDWARE`, `BLOCKED_OPERATOR`,
  `MISSING_IMPLEMENTATION` (no observation). Tiers: `HOST`, `QEMU`, `PHYSICAL`. QEMU is never
  PHYSICAL, and a host run on a machine that has the device is still HOST.
- Every gate id has exactly one `PHYSICAL` row, so a missing physical result is written down
  instead of left out.
- A PASS or FAIL row names a receipt under `evidence/` that contains the exact line
  `HWGATE <id> <tier> <status>`. No receipt, no claim.

[`tools/hwgates/hwgates.om`](../tools/hwgates/hwgates.om) (seeded Omega, omc sha256
`bcfa5828…0f6`, omega-mv `397e6704`, the compiler `native/disk` already pins) enforces these as
rules R1..R7 and prints `HWGATES PASS rows=… gates=… physical=… physical_pass=… physical_not_pass=…`.
The local Spark gate `AIENOS-HW-GATES` (`tests/gates/run.sh hw-gates`, which runs
`tools/hwgates/gate.sh`) checks the register, 15 fixtures (one good, 14 each breaking one rule),
three compiling behavior mutants of the checker (claim accepted without a receipt, physical row
optional, any receipt line of the right length accepted) and two planted-bad copies of the
register (a physical NOT_RUN turned PASS without a receipt; all physical rows deleted). Without the
pinned compiler it exits 3 (NOT_RUN), never 0.

To add a physical PASS: run the attended procedure under its own authorization, commit the raw
receipt under `evidence/` with the `HWGATE <id> PHYSICAL PASS` line plus source commit, image
digest, machine identity and commands, then change the row. The gate refuses the row change
without that file.

## Gates (2026-11-07, host and QEMU rerun at aienux main `2fc62070`)

Receipt for every PASS below: [`evidence/HWGATES-20261107/RECEIPT.txt`](../evidence/HWGATES-20261107/RECEIPT.txt),
with the raw logs beside it. Commands ran on the DGX Spark host CPU (cores 10-11, `nice -n 10`),
QEMU 8.2.2 TCG; nothing touched the GB10, its driver, a USB medium, BootNext or a service.

| Gate id | What | HOST | QEMU | PHYSICAL |
|---|---|---|---|---|
| AX-SMMU-P07 | SMMU stream ownership: all-SID probe, event readout, out-of-window DMA fault (#469) | PASS: `make -C native/kernel test sanitize` (`test_smmu` 274 checks), 7 IORT and 5 L2 mutants killed (incl. `DROP_EVENT`) | PASS: `qemu_ck_b7b_probe_test.sh` self-test, plain, `--positive`, `--events` (real out-of-window NVMe DMA has the matching decoded event; live queue drained) | NOT_RUN |
| AX-DMA-RETAIN | stream stays confined and owned when the SMMU abort fails (#470, RTL path #471) | PASS: `stage-test stage-sanitize` `CK_STAGE_HOST: PASS checks=942 failures=0`; reverting the fix fails (`devices.c` 8 failures, `rtl8127_bind.c` 5) | MISSING_IMPLEMENTATION: no QEMU injection of a failed abort; net/xHCI failure branches have no host test either (#470) | NOT_RUN |
| AX-NVME-OMEGA | bounded read-only NVMe protocol in seeded Omega (#472) | PASS: `omega_nvme_test.sh` 37 host cases, 7 guard-removal mutants killed; a different compiler is refused (exit 2) | PASS: 10 disposable-QEMU cases | MISSING_IMPLEMENTATION: no native VFIO/kernel adapter |
| AX-NVME-C | C NVMe driver suite `native/disk` (AIENOS-NATIVE-DISK) | PASS: `AIENOS_DISK_NATIVE`, `_SANITIZE`, `_MUTANTS` 46/46 | (M4_NVME rows: [`native/kernel/GATES.md`](../native/kernel/GATES.md)) | NOT_RUN |
| AX-RO-MEDIUM | read-only core boot medium `tools/spark-image/spark-image.om` (#461) | PASS: GPT/FAT32 image from omc `c99eda24…`, `sgdisk -v`, `fsck.vfat -n`, extracted EFI byte-equal, repeat run byte-identical, missing EFI exits 2 | PASS: GPT and a second NVMe both `readonly=on`, `report_kind: final`, QEMU exit 0; trace: 40 reads, 9 flushes, 0 writes, 0 write-zeroes | NOT_RUN: image here is non-staging, not boot-admissible |
| AX-BOOT-INPUT | storage-free Spark input candidate `CK_SPARK_INPUT=1` (#471) | PASS: RTL failed-release retention in the stage fixture (row AX-DMA-RETAIN) | NOT_RUN in this register: exercised 2026-10-28 at `180618ae`, receipts outside the tree | NOT_RUN |
| AX-SB01-ANCHOR | authenticated monotonic boot-generation anchor (#457) | MISSING_IMPLEMENTATION (slot tool selftest 155/0 covers only #456's control-record refusal) | | MISSING_IMPLEMENTATION |
| AX-SB05-MEDIA | owner-signed standalone recovery medium (#458) | PASS: `test_recovery_media_security.sh` `RECOVERY_SECURITY: PASS` (throwaway keys) | | NOT_RUN: owner signing key, shim/MOK enrollment, attended boot |
| AX-GSP-C | in-tree GB10 GSP firmware/COT/boot-args/RPC encoders and simulators (#441) | PASS: `CK_GSP_*` selftests, `test_gsp_mmio` 67, `test_gpu_sim` 244 (`CK_GSP_BINDATA_PIN` printed NOT_RUN: local NVIDIA source cache lacks the GB10B bindata files) | | NOT_RUN |
| OGD-HOST-SUITE | omega-gpu-driver `tests/run.sh` at main `1ac3589c` | PASS: `OMEGA GPU DRIVER HOST TESTS PASS (37 gates)` with the pinned aienux `a108b114` and NVIDIA `20e4e6e19` oracles | | NOT_RUN |
| OGD-W0 | W0 identity read and composed `ogd` launcher (omega-gpu-driver) | PASS: `ogd_host.sh` native and QEMU-user, 7 physical-mode refusals each, 6 mutants | | NOT_RUN: BOOT_42 unread on GB10 |
| OGD-GSP-COT | GB10B COT header fix and GB20B COTv2 host candidate (omega-gpu-driver#6) | PASS: `sec2_host.sh` 15 cases, `mutants-sec2.sh` | | NOT_RUN |
| OGD-STOP | safe GPU stop and memory ownership (DRA-149) | PASS: `irqlease_host` 117 cases + 12 mutants, `dma_host` 23 + 11 mutants, `boot_dma` | | MISSING_IMPLEMENTATION: physical device stop returns -95 |
| OGD-RPC | real GPU request and reply (DRA-150) | PASS: `transport_host` 10 mutants, `window_sim` 170 checks, `mutants-window` 20/20 | | NOT_RUN |
| OGD-COMPUTE | first small GPU calculation (DRA-151) | | | NOT_RUN |
| OGD-FAULT | GPU memory fault recovery (DRA-152) | PASS: `uvm_diff` (503 lines, independent walk), `mutants-uvm` 5 killed | | NOT_RUN |
| CUDAPP-UTIL | truthful GPU utilization (DRA-153, CUDApp #286/#298 drafts) | | | NOT_RUN |

## Missing physical receipts

Every row above has physical status NOT_RUN or MISSING_IMPLEMENTATION. What each needs:

| Gate id | Physical receipt needed | Blocker and owner |
|---|---|---|
| AX-SMMU-P07 | B7B probe on the Spark: all-SID readout of the three SMMUv3 instances, a confined device fault with matching SID/address | TRUST-1 owner ceremony (no `CK_OWNER_PUBKEYS`/`CK_MACHINE_ID`, so `CK_HARDWARE_STAGING` refuses); attended window; DRA-25 |
| AX-DMA-RETAIN | a failed physical abort that keeps the stream confined (needs a fault-injection path on hardware) | no hardware injection exists; with AX-SMMU-P07 |
| AX-NVME-OMEGA | the Omega protocol driving a real NVMe read-only | native VFIO/kernel adapter (absent); attended window |
| AX-NVME-C | native NVMe read on the Spark | TRUST-1, attended window |
| AX-RO-MEDIUM | attended USB boot of the staging-built medium, display record of `report_kind: final` | TRUST-1 staging build; Main owns the medium and live-service stop/restore |
| AX-BOOT-INPUT | physical xHCI/HID input, RTL8127 link/TX, UDP report | TRUST-1; `SPARK-BOOT-INPUT-20261028.md` |
| AX-SB01-ANCHOR | TPM NV anchor read and checked every boot on the machine | owner chooses anchor and policy (#457, #32) |
| AX-SB05-MEDIA | signed medium booted under the enrolled owner key, tampered medium refused | owner key custody and enrollment (#458) |
| AX-GSP-C, OGD-* | GB10 identity read, GSP boot, request/reply, first compute, fault recovery | DRA-149..152 under DRA-174; Drake's authorization and a queen-scheduled exclusive spark-window lease |
| CUDAPP-UTIL | live `--rm` read checked against raw RM data | DRA-153; read-only spark-window lease |

The native Spark path still runs the GB10 through NVIDIA's `nvidia.ko`/`nvidia-uvm.ko`
580.173.02; none of the GPU rows above replaces it.
