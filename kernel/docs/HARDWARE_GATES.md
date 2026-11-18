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

[`tools/hwgates/hwgates.om`](../tools/hwgates/hwgates.om) (seeded Omega, built with omega-mv's
[`seed/out/omc`](../../seed/out/omc.sha256)) enforces these as rules R1..R10, refuses an
empty register (R8), the deletion of a gate whose receipt still names it (R9) and a gate id with
anything but upper-case letters, digits, `-`, `_` or `.` (R10, so two ids never differ by case
alone), and prints `HWGATES PASS rows=… gates=… physical=… physical_pass=… physical_not_pass=…`.
The checker has no size cap: the register, receipts and row tables are run-time pools grown to the
input. The gate (`tests/gates/run.sh kernel-hw-gates` from the omega-mv root, which runs
`kernel/tests/gates/run.sh hw-gates` and so `tools/hwgates/gate.sh`) runs the checker on the
register, its fixtures (a good fixture must print its exact count line, one of them with an
accepted PHYSICAL PASS), mutants and planted-bad copies, compares the register's count line with
counts taken from the register itself, and runs the shell checks the checker cannot do: receipt
files, inventory, receipt claims, withdrawn lines, unchanged receipts, source commits, a run far
past the old 1024-row and 524288-byte tables, and a size alarm when the real register passes what
that run proves. The comments in `gate.sh` name each check. Without the pinned compiler it exits 3
(NOT_RUN), never 0.

A source `aienux@<commit>` names the aienux commit the row was written against. The fold into
omega-mv rewrote aienux history, so the gate looks the commit up in
[`import/commit-map`](../import/commit-map) and requires the rewritten commit to be in this
repository; a commit the map does not know, or maps to zeros, fails. Rows keep their aienux hashes.

To add a physical PASS: run the attended procedure under its own authorization, commit the raw
receipt under `evidence/` with the `HWGATE <id> PHYSICAL PASS` line plus source commit, image
digest, machine identity and commands, then change the row. The gate refuses the row change
without that file.

## Where the statuses are

[`hardware-gates.tsv`](hardware-gates.tsv) is the only place a status is written; this page does
not repeat them. Each PASS or FAIL row there names its receipt, and the receipt holds the exact
commands and logs (the 2026-11-07 host and QEMU run is
[`evidence/HWGATES-20261107/RECEIPT.txt`](../evidence/HWGATES-20261107/RECEIPT.txt), with the raw
logs beside it; as [`CORRECTION-20261118.txt`](../evidence/HWGATES-20261107/CORRECTION-20261118.txt)
beside it records, its per-script omega-gpu-driver counts have no tracked log behind them and its
second omega-gpu-driver compiler is missing from the run's input record).
To read the register as a table: `column -t -s "$(printf '\t')" docs/hardware-gates.tsv`.

## What a physical receipt needs

[`hardware-gates-needs.tsv`](hardware-gates-needs.tsv) lists every gate id and what its PHYSICAL
receipt must show before that row can say PASS. The blocker and owner of each gate are field 7
of its PHYSICAL row in `hardware-gates.tsv`; this page does not repeat either. The gate
(`tools/hwgates/gate.sh`) refuses when the id sets of the two files differ, so a gate that has
no receipt yet cannot leave the inventory without a reviewed change to both files. To read
them side by side:
`join -t "$(printf '\t')" <(grep -v '^#' docs/hardware-gates-needs.tsv | sort) <(awk -F '\t' '$4=="PHYSICAL" {print $1 "\t" $7}' docs/hardware-gates.tsv | sort)`.

A receipt is never rewritten, and the gate holds it: every tracked file in the folder of a cited
receipt or of a file with `HWGATE` lines, and `import/commit-map`, must have exactly the content of
the commit that first added it, so a line appended or edited, committed or not, fails (a shallow
clone fails too, because the adding commit cannot be found). When a later review finds that a
committed receipt line claims more than it shows, a dated `CORRECTION-<date>.txt` beside the
receipt names the line (`CORRECTS HWGATE <id> <tier> <status>`) and says why. That withdraws the
line: it no longer backs a PASS or FAIL row, and the gate refuses a row resting on it. The gate
also refuses a receipt line whose status differs from the register's row for that id and tier
unless such a correction covers it.

The native Spark path still runs the GB10 through NVIDIA's `nvidia.ko`/`nvidia-uvm.ko`
580.173.02; none of the GPU gates replaces it.
