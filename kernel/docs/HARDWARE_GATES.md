# Hardware gates: what ran where, and what has no physical receipt

This page explains the hardware-gate register [`hardware-gates.tsv`](hardware-gates.tsv), which lists
every Aienux and GB10 GPU-driver capability that touches hardware, the host and QEMU gates that
cover it, and its physical status. It is the answer to "has this run on the machine?": a row says PASS
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

[`tools/hwgates/hwgates.om`](../tools/hwgates/hwgates.om) (seeded Omega, built with the compiler
named in [`tools/hwgates/PIN`](../tools/hwgates/PIN)) enforces these as rules R1..R9, refuses an
empty register (R8) and the deletion of a gate whose receipt still names it (R9), and prints
`HWGATES PASS rows=… gates=… physical=… physical_pass=… physical_not_pass=…`. The local Spark gate
`AIENOS-HW-GATES` (`tests/gates/run.sh hw-gates`, which runs `tools/hwgates/gate.sh`) checks the
register, the fixtures in `tools/hwgates/fixtures/` (one good, the rest each breaking one rule), the
checker's compiling behavior mutants, that every cited receipt is a tracked regular file under
`evidence/`, that the register and receipts stay under three quarters of the checker's tables, and
planted-bad copies of the register. Without the pinned compiler it exits 3 (NOT_RUN), never 0.

To add a physical PASS: run the attended procedure under its own authorization, commit the raw
receipt under `evidence/` with the `HWGATE <id> PHYSICAL PASS` line plus source commit, image
digest, machine identity and commands, then change the row. The gate refuses the row change
without that file.

## Where the statuses are

[`hardware-gates.tsv`](hardware-gates.tsv) is the only place a status is written; this page does
not repeat them. Each PASS or FAIL row there names its receipt, and the receipt holds the exact
commands and logs (the 2026-11-07 host and QEMU run is
[`evidence/HWGATES-20261107/RECEIPT.txt`](../evidence/HWGATES-20261107/RECEIPT.txt), with the raw
logs beside it). To read it as a table: `column -t -s "$(printf '\t')" docs/hardware-gates.tsv`.

## What a physical receipt needs

What each gate needs before its PHYSICAL row can say PASS:

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
580.173.02; none of the GPU gates replaces it.
