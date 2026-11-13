# KFD rebase onto df19e881

Intent: retain the checked KFD words on current compiler work, rebuild the seeded compiler, and exercise the complete preceding CPU acceptance set without pushing or using a GPU.

## Records

- `build/final-source-head` identifies the exact source head exercised by the fresh clone. `build/final-compiler-identities.sha256` records compiler/source identities; `build/compiler-main.sha256` records the main compiler used as a negative control.
- `build/conflicts.md` records every replay conflict and resolution. The old repin commit was excluded. `build/original-commits.tsv` and `build/rebased-commits.tsv` record the source/replayed commits.
- `build/main-gate-pin-sources.txt` and `build/main-pin-consumers.txt` are the main-derived pin inventory. No historical receipt was repinned.
- `initial/exits.tsv` and `initial/logs/` preserve the failed/interrupted first attempt and the successful subsequent reseed/repin. They are not replaced by the final results.
- `fresh/exits.tsv` gives every final command, start/end time and exit code; `fresh/logs/` contains its output. `fresh/run.sh` is the executed command driver. `fresh/kfd-results.json` contains the KFD case receipts. `SHA256SUMS` covers the recorded files.

## Integration corrections

The initial seed birth refused stale diagnostic identity. Regenerating the diagnostic source before the seed procedure resolved that refusal. The first full gate attempt then exposed two concrete integration defects: KFD's mutation matcher did not admit the new diagnostic annotation pair between a function declaration and its statement, and four KFD failures lacked main's source-bound diagnostic IDs. The matcher now admits only that exact annotation pair while still requiring one full semantic seam; the compiler has unique IDs for those failures. Existing IDs and refusals are retained, not weakened. The final KFD suite reports `KFD_CPU 355 checks 0 failures; hardware NOT_RUN`.

Seed command, for each birth recorded in `initial/exits.tsv`: `sh seed/omega-from-seed.sh`. Repin command (the ellipses in the original TSV stand for these exact environment values):

```
env REPIN_WHAT='omc KFD words rebased with current diagnostic and module compiler work' REPIN_LANDING='Add checked KFD ioctl' REPIN_MAIN=df19e881 python3 evidence/kfd/20261113-rebase-c4e5e963/tools/repin3.py
```

## Interruption and fresh-clone rerun

The first `make-compiler` invocation ended with SIGTERM, exit143, at 03:31:15Z. This coincided with an omp harness restart from18.19.0 to18.20.0 and a session abort observed by the parent; the Spark itself did not reboot. The sending process is not recorded. The command had timeout0, so this record does not attribute the signal to an assistant timeout or a pool holder. `initial/interruption.txt` and `initial/interruption-record.jsonl` retain the provenance. No interrupted result is labeled PASS.

The complete final set ran from a new `git clone --no-hardlinks --branch amdserve/kfd-word-r2` at `../omega-mv-r2-gate`, not a resumed build. Only the explicit bridge export, ttsim oracle, command driver, main compiler and negative-control source were supplied. `fresh/start-status.txt` records the source state. Invocation:

```
flock -n ~/handoffs/hive/queen/pool-16-18.lock taskset -c 16-18 nice -n 10 bash build/kfd-r2/run.sh
```

Every named final gate exited0. The negative-control program, stored here as `neg2.om.txt` (ran as `build/kfd-r2/neg2.om`), compiled with the new compiler (exit0), while main rejected it with `omc: line 3: error 3` (exit3). Rejection, rather than a particular historical error number, is the expected negative result. Neither negative-control binary was run against a device. The stored copy has a `.txt` suffix because `seed/omc/gate-pools.sh` section 11 compiles every tracked `*.om` with the historical pre-pools compiler as its control, which refuses `kfdctl`; a tracked `.om` copy makes that gate fail.

## Boundaries

This is host/emulator qualification, not GPU qualification. Logs explicitly retain device KFD NOT_RUN cases, GB10-only numerical skips, the x86-only EFI file case, Trainium/Inferentia hardware NOT_RUN, StableHLO native float cases not supported by this pin, unvendored Wycheproof data, and absent sibling omega-mcp/cortex/interplane-forge checkouts. A gate exit0 does not turn those subcases into PASS. No GPU, live service, push, merge or deployment was performed.

The parent subsequently requested a further rebase onto the new Radicle main. This directory remains the immutable record of the df19e881-based run; it is not evidence for a later source head.
