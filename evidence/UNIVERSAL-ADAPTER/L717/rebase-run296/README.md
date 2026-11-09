# L717 rebase replay, run 296 (2026-11-09)

Branch `hive/t_e8204709-buffers-L717`: the five reviewed commits of Radicle `ua/buffers-L717`
(`d588b890`, functional source `e30355ee`, L735 review: no findings) cherry-picked onto omega-mv
main `1e3ecbba`. `git patch-id --stable` of the rebased diff equals the original (`d88acfec`), so the
reviewed source is byte-identical. One test line was added (below). No compiler, seed, GPU, platform
ABI or L689 streaming file changed.

## Compilers

| omc | sha256 | origin |
|---|---|---|
| seed-born | `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8` | `sh seed/omega-from-seed.sh` at `1e3ecbba`, RC=0 |
| module pin | `191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9` | README pin of this module |

Every program was built with the README recipe (`cat buffers.om <tests> | omc`), checked as
AArch64 `EXEC` with no `INTERP`, and executed on the Spark host (queen pool lock 12-13).
Raw per-program rows (compile rc, size, type, machine, run rc, binary sha256) are in
`results-seed-omc-6d1b1cf5.tsv` and `results-pinned-omc-191b776e.tsv`.

## Candidate (both compilers identical outcome)

| program | run exit | expected |
|---|---|---|
| suite (`test_globals.om` + `test_buffers.om`) | 0 | 0 |
| rights-regression | 0, prints PASS | 0 |
| read-regression | 0, prints PASS | 0 |
| exit-wrap-control (deliberately failing suite) | 1 | 1 (0 would be a framework defect) |

Asserted actual counters in the suite: bytes copied `ubstat 1` = 3, then 19 after a 40-byte transfer
cancelled at its first 16-byte checkpoint (3 + 16, suffix of 24 bytes left at sentinel 238);
accepted copies `ubstat 2` = 1, then 2; owned bytes `ubstat 3` = 4096 with the pool full and 0 after
release; peak owned bytes `ubstat 4` = 4096 and still 4096 after all frees plus a 1-byte allocation.

Host process measurement (seed build, `/usr/bin/time -f %M`): suite, rights and read each max RSS
192 KiB; the RW load segment reserves 0x801250 bytes (suite), so module storage (4096-byte pool plus
descriptor tables) is static. Single run, host only; no latency, throughput or GPU claim.

## Mutants of the current source (`mutants/*.om`, 14/14 killed with both compilers)

A mutant is killed when any of suite, rights or read exits nonzero.

| mutant | change | killed by (exit) |
|---|---|---|
| stale-no-generation | `ubcheck` drops generation equality | suite 1 |
| stale-no-bump | `ubfree` keeps the generation | suite 1 |
| alias-removed | `ubcpr` drops `s == d` refusal | suite 1 |
| backpressure-reuse-live | `ubnew` ignores `ubused`, reallocates live slots | suite 1, rights 1, read 1 |
| backpressure-refusal-leaks | `ubnew` charges owned bytes before finding a slot | suite 1, rights 4, read 1 |
| cancel-ignored | `ubcpr` ignores cancelled descriptors | suite 1 |
| cancel-rights | scheduled cancellation without source WRITE | rights 1 |
| cancel-late | checkpoint cancellation keeps copying | suite 1 |
| bytes-estimated | bytes counted as requested `n`, not copied | suite 1 |
| peak-not-tracked | peak never updated | suite 1 |
| peak-tracks-current | peak overwritten by current owned bytes | suite 1 |
| read-range-ok | `ubread` accepts out-of-range offsets | read 1 |
| read-publish-on-refusal | `ubread` writes `ubvalue` on a bad handle | read 1 |
| free-keeps-bytes | `ubfree` leaves owned bytes charged | suite 1, rights 4, read 1 |

## Test gap found and closed

`peak-tracks-current` survived the reviewed suite: with the original `test_buffers.om` both the
mutant and the candidate exited 0 (seed omc), because peak was only asserted while the pool was full.
Added to `test_buffers.om` after the post-retirement 1-byte allocation:
`check ubstat 4 4096` (peak is a high-water mark). The candidate still exits 0 and the mutant now
exits 1.

## Status

IMPLEMENTED + EXERCISED (Spark AArch64 host). Not MERGED until the Radicle desk merges this patch.
Same-application cross-adapter integration, GPU residency and hardware qualification: NOT_RUN.
