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

[`hardware-gates-needs.tsv`](hardware-gates-needs.tsv) lists every gate id and what its PHYSICAL
receipt must show before that row can say PASS. The blocker and owner of each gate are field 7
of its PHYSICAL row in `hardware-gates.tsv`; this page does not repeat either. The gate
(`tools/hwgates/gate.sh`) refuses when the id sets of the two files differ, so a gate that has
no receipt yet cannot leave the inventory without a reviewed change to both files. To read
them side by side:
`join -t "$(printf '\t')" <(grep -v '^#' docs/hardware-gates-needs.tsv | sort) <(awk -F '\t' '$4=="PHYSICAL" {print $1 "\t" $7}' docs/hardware-gates.tsv | sort)`.

A receipt is never rewritten. When a later review finds that a committed receipt line claims
more than the register allows, a dated `CORRECTION-<date>.txt` beside the receipt names the line
(`CORRECTS HWGATE <id> <tier> <status>`) and says why. The gate refuses a receipt line whose
status differs from the register's row for that id and tier unless such a correction covers it.

The native Spark path still runs the GB10 through NVIDIA's `nvidia.ko`/`nvidia-uvm.ko`
580.173.02; none of the GPU gates replaces it.
