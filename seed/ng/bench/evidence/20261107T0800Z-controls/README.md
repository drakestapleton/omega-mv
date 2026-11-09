# ngbench negative controls, 2026-11-07 08:00Z (lane ng-bench)

Status: EXERCISED on the Spark host (core 1, A725, `taskset -c 1`). Untimed: these rows check refusal
behaviour, not speed.

Harness: `seed/ng/ngbench.om` sha256 `19be4ff690a949fbdadb5e5fcb4e45faac668f259c9184b66ab1684f407e77b6`,
compiled by `seed/out/omc` (sha256 `5f90edea…f6df`, omega-mv 943d9555) to a binary with sha256
`1a67a09d7a03a04cb168e33086db40324bf80055e97156085c1e1872b3f47e07`.

Fixture per control: a scratch DIR with `bin/omc/{matmul,leafcall}` (omc builds of the frozen kernels),
`bin/gccO2/{matmul,leafcall}` (`gcc -O2 -static` builds of the C twins), `want/` copied from
`seed/ng/bench/kernels/want/`, and `manifest.sha256` written by `ngbench sum bin/*/*` inside DIR. Each control
then makes one change and runs the command in `<id>.cmd`. Files: `<id>.rows` stdout, `<id>.stderr`, `<id>.rc` exit.

| id | change to the fixture | expected | observed |
| --- | --- | --- | --- |
| nc0-clean | none, 2 blocks + 1 warm | exit 0, no R row | exit 0, 0 R rows |
| nc1-wrong-output | arm `omcbad` = omc build of `nc1-matmul_bad.om` (one constant 13 -> 14), listed in the manifest | timed, every omcbad run refused `output`, exit 1 | exit 1, 2 x `R output matmul omcbad` |
| nc2-swapped-labels | gcc binary placed under `omc`, omc binary under `gccO2`, manifest regenerated to agree | refused `label` before any timing, exit 1 | exit 1, `R label matmul omc` + `R label matmul gccO2`, 0 T rows |
| nc3-manifest-mismatch | binary replaced after the manifest was written | refused `manifest`, exit 1 | exit 1, `R manifest matmul omc` |
| nc4-unlisted | one binary's line removed from the manifest | refused `unlisted` | exit 1, `R unlisted leafcall gccO2` |
| nc5-missing | listed binary deleted | refused `missing` | exit 1, `R missing leafcall gccO2` |
| nc6-bad-want | `want/leafcall.sha256` not 64 hex digits | refused `nowant` | exit 1, `R nowant leafcall` |
| nc7-exit-status | omc arm replaced by `nc7-exit3.om` (exits 3), manifest regenerated | refused `status` per run | exit 1, 2 x `R status leafcall omc` |
| nc8a..e | unknown arm prefix `clang`; 0 blocks; no `--`; non-number WARM; no case | usage, exit 2 | exit 2 for all five |
| nc9-abba-3arms | third arm `gccO3n`, 2 blocks + 1 warm | each block palindromic, start arm rotates | blocks: omc gccO2 gccO3n gccO3n gccO2 omc / gccO2 gccO3n omc omc gccO3n gccO2 / gccO3n omc gccO2 gccO2 omc gccO3n |
| nc10-changed-midrun | 1.5 s into a 20-block run the gccO2 binary is replaced (new inode via `mv`) by the matmul binary | wrong-output rows refused, final hash recheck refuses `changed` | exit 1, 26 x `R output leafcall gccO2` (blocks 7..19), 1 x `R changed leafcall gccO2` |

Defect found and fixed while running these: `ngbench run` without `--` read an argument index past `argcnt`, which
traps 3 (OMEGESE.md: "argread ... An invalid index traps 3"), exit 103. The separator search now stops at
`argcnt` and the missing separator is a usage error (nc8c, exit 2).

`sum.ngbench` vs `sum.sha256sum`: `ngbench sum` and GNU `sha256sum` on the same seven files (empty, 64 bytes,
65 bytes, 200000 random bytes, both chacha binaries, omc) are byte-identical (`cmp` exit 0).
