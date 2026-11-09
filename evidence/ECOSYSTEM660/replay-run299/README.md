# Ecosystem660 profile replay, 2026-11-09 (L786 recovery, run 299)

This directory re-executes the three profiles in `seed/qualification/ecosystem660/`
from their pinned revisions on the Spark AArch64 host (CPU pool 12-14, `quiet-build`).
The parent commit is the original qualification commit `a7c68b4e` applied unchanged
to main `1e3ecbba` (stable patch-id `f25311cc`). No compiler source, seed rung or
existing evidence was changed. The dropped original commit `3b3a6739` only
refreshed retired `.crumb` metadata.

| Profile | Command (from a clean detached worktree at the pinned revision) | Result |
| --- | --- | --- |
| baseline, omega-bridge `0fc7d866` | `sh tools/bootstrap.sh` | `PASS source-only seed bootstrap and compiler fixpoint`, rc 0, omc `191b776e…` |
| definitions, omega-mv `43f86be2` | `sh seed/omega-from-seed.sh`; `sh seed/omc/gate6.sh` | birth RC=0; `PASS gate6 26 cases`; `seed/out/omc` `bcf3abc7…`, worktree clean |
| definitions export oracle | `request.om` modes 0..12 through the profile compiler, responses into `check.om` | `947 0`, exit 0 |
| definitions compiler mutants | `mutate.om` raw mode byte 0/1/2 + exact `omc.om`; compile each, same requests and checker | exit 1 with 446, 14 and 223 failed assertions |
| host, omega-mv `f0499f41` | `sh seed/host/check.sh` | 24 PASS lines, rc 0, omc fixpoint `e5d60db8…` |

All binary hashes equal `profiles.json`. All counts equal the original receipts in
this directory's parent. A compiler refusal was never counted as a detected mutant.

What this does not establish: integration of the definition export or host
extensions into the main compiler (Omega660/665, compiler owner), diverse double
compilation (Omega650), any numeric, tensor, device or model qualification,
consumer cutover or retirement. Those gates stay open.
