# OM-1 C2 delta chain at omega-mv main 1e3ecbba (omc 6d1b1cf5): 29 undeclared rows

HOST_TESTED, Linux AArch64, CPU only (pool-0-2, pool-16-18, pool-19). No GPU, no GitHub. Card t_2d8ccba8, L1041, bay 15.
Base: omega-mv rad main `1e3ecbba779ee84e2de70ec231e83533a9c61f45`. Pinned compiler `seed/out/omc` sha256
`6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8` (rebuilt from seed: `sh seed/omega-from-seed.sh`, stage1 = stage2 = stage3).

## Result

- Frozen `manifest-c2.txt` gives 5835/5876 at main. Its 41 failures equal the union of the rows declared by the five deltas
  (`frozen-failures-41.txt`; `diff` of the two sorted sets is empty).
- New delta `seed/qualification/om2/manifest-c2-hostwords.txt` declares 29 rows (the 29 rows that matched no earlier delta, six of
  which fail their earlier delta again). It is layered after the four earlier deltas: for a row declared twice the latest delta wins.
- With the layered contract, omc 6d1b1cf5 passes every C2 manifest (`logs/layered-c2-6d1b1cf5.log`): frozen 5876/5876,
  capacity 3/3, batch2 3/3, fpvreg 8/8, closerange 4/4, hostwords 29/29. The committed manifests are not edited; `scripts/layer.sh` builds
  the layered copies in a scratch directory. The conductor is `seed/qualification/om2/gate.om` built by the same compiler (sha256 49914d72...).
- Negative control for the delta: omc be8c5130 (main 474197e4) on the same layered manifests fails hostwords 0/29, frozen 5847/5876
  (29 failures), batch2 1/3, closerange 0/4 (`logs/layered-c2-negative-be8c5130.log`).

## Attribution (bisect over born compilers)

`scripts/sweep1.sh COMMIT` extracts the commit's tree, runs `seed/omega-from-seed.sh`, compiles the 29 row sources (`scripts/extract.sh`,
slices of `c2/corpus.pack`) and records exit and sha256 per row. It ran over every one of the 31 omc.om commits after 474197e4 plus
474197e4 itself (`commits.txt`; `bisect.tsv`). 29 of 31 are born; `68b5eb3c` and `b4ac702c` (merges of #1045 into the #1050 stack) stop in om4 with
error 14 and are ignored. A second sweep over the 25 first-parent main commits shows the main pins: `62775d2a` (6478d690f, 2026-10-29) emits
the pre-delta bytes, `5f90edea` (ad578eb45, 2026-11-06) and every later main pin (0f2de851, 6d1b1cf5) emit the delta bytes for all 29 rows.

| Cause | Commit | Rows | Effect |
|---|---|---|---|
| 1 | `78122a72a` #1045, bounded typed VFIO IRQ and eventfd words (omc 734bf4f3; main line from `2de46b77`, omc b1d9cff6) | 28 | fclose retires the descriptor from a process-local descriptor-kind table (128 x 16 bytes at 0x10800000, kinds 1 and 2): a 31-instruction, 124-byte scan per fclose site, data segment 0x800000 -> 0x800800. Programs grow by 124..816 bytes. |
| 2 | `e9b635875` #1048 for #1042, devcall parameter cap raised to 1048576 bytes (omc 390629fd) | c2-00008 | different cap constants, same size. |

At 78122a72 itself 24 of the 28 rows already have the final bytes; the four closerange rows differ because that branch predates #970.
The same attribution was reached independently in `~/handoffs/hive-breathe/L1032.md` (merge 2de46b77, omc b1d9cff6).

## Behaviour check (old = omc be8c5130, new = omc 6d1b1cf5; same source, same inputs)

- 26 rows, including c2-00025 and c2-00029 (c2-00008 is the 27th and is discussed below): `scripts/difftest.sh`, fresh directories; exit, stdout, stderr and the file listing left behind are
  identical (`logs/behaviour-host-rows.tsv`). c2-00025 gets the compiler under test as argv[1]; c2-00029 gets ./exec-child built from args.om by the
  compiler under test; c2-00026 runs with no argument and with `tcp`.
- c2-00128 (gate669.om) and c2-05721 (om2 gate.om), from a 725ca8397 tree: `scripts/difftrees.sh`. gate669 exits 0 with identical stdout and stderr
  ("GATE669 PASS"); the gate over selftest controls, emit, fail, pass exits 3 1 1 0 with identical verdict output (`logs/behaviour-tree-rows.tsv`).
- c2-00008 (devcall.om, the acb3f15 fixture) is the one row whose behaviour changed: old exits 0, new exits 80. Cause 2 is a declared contract change
  (docs/one_layer/OMEGESE.md section 10: parameter span at most 1048576 bytes inclusive), not a defect. The fixture's child k=4 requires a 16384-byte span
  to trap; with the loop cut to k < 4 the new binary exits 0, with k < 5 it exits 80. Every born compiler before e9b635875 gives 0, every one from it gives
  80. The current fixture passes under 6d1b1cf5 (`logs/host-gate-6d1b1cf5.out`, 46 lines, rc=0), and fails at the devcall step under be8c5130
  (`logs/host-gate-be8c5130-HEAD-fixtures.out`), as intended by #1042. Reverting the cap would reopen #1042.
- Negative control: the c2-00014 source with `ret 0` changed to `ret 9` exits 9 under 6d1b1cf5; unmodified it exits 0 under both (`logs/negative-control.log`).

## Code change

`seed/omc/qualify-x86.py` `current_c2_contract()` now lists `manifest-c2-hostwords.txt` and lets the latest declaration win (it returned the first
match, so rows declared by batch2 or closerange would have kept their stale values). `docs/X86-LINUX.md` names the new delta. No compiler change.
The x86 receipts under `seed/qualification/x86-linux/` are historical and not regenerated.

## Not done

- No compiler fix: no row's behaviour changed except by the declared #1042 cap.
- x86 qualification (`qualify-x86.py`) was not rerun with the new list; it needs the x86 oracle environment.
- Guide: `omega-harness` section 3 (C2 delta manifests note, "Main has four") should list `-hostwords.txt` and the latest-wins layering; the guide
  repository is protected and this task excludes harness changes, so the text is recorded here for the owner.
