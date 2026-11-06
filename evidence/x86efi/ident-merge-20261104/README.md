# #1022 receipts taken after the feat/x86efi-main merges (2026-11-04)

The committed `evidence/x86efi/ident-bounds-20261104/run-sh.txt` was taken on the `623ab451` tree. `tests/x86efi/run.sh` changed afterwards in the merges of `19ee7e99` and `d3d1b1bc`. These two files are the author's logs from the later tree, committed so the claim does not rest on scratch files. They are copies of `/tmp/fi55/runsh2.txt` and `/tmp/fi55/fixpoint2.txt`, not reruns.

| File | Taken (host local time, UTC−6) | Tree | Result |
|---|---|---|---|
| `fixpoint.txt` | 2026-11-04 07:22:55 | `9bf67eff` | `sh seed/omega-from-seed.sh`: `PASS omc fixpoint 3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194`, `RC=0` |
| `run-sh.txt` | 2026-11-04 07:36:03 | `9bf67eff` | `sh tests/x86efi/run.sh`: `SUMMARY pass=23 fail=0 not_run=0`, `RC_EXIT=0` (EMULATED: QEMU q35 + OVMF) |

`git diff --quiet 9bf67eff cf9fbda1 -- tests/x86efi seed/out/omc` returns 0: the tests and the committed omc on the PR head are byte-equal to the tree these logs came from. `run.sh` starts each guest under `timeout` (run.sh:45) and judges it from its serial log; the `qemu-system-x86_64: terminating on signal 15 ... (timeout)` lines are that limit stopping a guest.
