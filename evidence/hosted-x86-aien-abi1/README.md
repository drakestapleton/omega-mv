# Hosted-x86 ABI1 superset: CPU qualification

Source tested: `c6c30fe3e62f4ba5496ef7225f72ecd9c62c6300`, stacked on #1047 `dbedb2ca`. The hosted-x86 source/fixtures are from #1046 `cecac742` and `b44e5d88`; its frozen compiler and historical receipts were not imported or edited.

Compiler SHA256: `c5ac9979232afd0d750e1d5088af69692032997136f761e585a25aa9a1cfc87e`.

All commands ran under `taskset -c 10-14 nice -n 10` in this worktree. Home-directory prefixes in copied logs are normalized to `~`. The host log was reconstructed from explicit raw reader ranges with LF separators because an unranged raw read paginates at300 lines; all872 source lines are recorded. No result or byte-comparison line is otherwise changed.

| Command | rc | Observed final/result line | Verdict |
| --- | --- | --- | --- |
| frozen #1047 `seed/out/omc < seed/omc/om2/fnhost/x86-dev.om` | 9 | compiler error9 | PASS negative control: old compiler refuses hosted-x86 device fixture |
| `sh seed/omega-from-seed.sh` | 0 | `PASS assign exit 7`; fixpoint line names c5ac9979 | PASS seed0 birth and compiler fixpoint |
| `make -j5 build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2` | 0 | unchanged verification oracles built | PASS |
| `sh seed/host/check.sh` | 0 | `PASS native-host qualification; seeded build, C tools are comparison oracles only` | PASS host |

The host gate reports function-mode host words:21 cases and12 compiler mutants; exact ABI1 ioctl matrix:four mutants killed. Deliberate mutant runs print their attributed FAIL diagnostics before the aggregate PASS; they are not suppressed. The existing optional Wycheproof file is NOT_RUN (not vendored). GCC oracle is Ubuntu13.3.0. The compiler matrix uses system QEMU8.2.2 for its explicitly EMULATED program checks; its ENOTTY result is not a kernel/driver admission claim.

AArch64 remains the separate b8f8f137 profile. Pure-x86 remains be8c5130. Program-mode mapping capacity remains128; function-mode context ownership, generations, quarantine and capacity4098 are unchanged.

IMPLEMENTED and host EXERCISED only. Physical x86, WC timing, NVIDIA driver and GPU/chip qualification: NOT_RUN. No live service or device was opened. Not MERGED or DEPLOYED. Drake must approve the draft compiler/bridge contract before merge.
