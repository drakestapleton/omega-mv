# L775 run 298: rebase onto main and native executor (2026-11-09)

Card t_33621d1e (L775 recovery, bay 5). Host: Spark, Linux 7.0.0-1019-nvidia aarch64,
queen pool lock 16-18 (`flock -o ~/handoffs/hive/queen/pool-16-18.lock taskset -c 16-18 nice -n 19`).
No GPU, model, tokenizer, network or protected data.

## What moved

- Radicle `learning/652-lead-L775` (`dd28ebc0`, functional source `84d03c55`, L781 review no findings)
  and `learning/652-corpus-L776` (`1a14972c`, admission `d8d14c47`, L781/L782 reviews no findings)
  were cherry-picked onto omega-mv main `1e3ecbba`. Every non-crumb path is byte-identical to the
  branch tips (400 files, all additive). Generated `.crumb` changes were dropped: crumbs are retired
  (DRA-97) and main keeps its own `.crumb` files; `dd28ebc0` (crumb-only) became empty and was skipped.
- New in this run: `src/learning/benchmark/run.om` (native executor), `tests/learning/benchmark/run-test.om`,
  seven candidate fixtures in `tests/learning/benchmark/cand/`, thirteen executor mutants in `mutants/`,
  `replay.sh` and the contract section in `docs/learning/benchmark-v1.md`.

## Compilers (born here, `compilers/`)

| omc | sha256 | origin |
|---|---|---|
| component pin | `191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9` | omega-bridge `0fc7d866` `tools/bootstrap.sh --offline` (seed0 → om4 → fixpoint), PASS |
| main seed | `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8` | `sh seed/omega-from-seed.sh` at main `1e3ecbba`, RC=0 |

## Results (`seed-6d1b1cf5/results.tsv`, `pin-191b776e/results.tsv`, raw stdout/stderr/exits beside them)

Command: `sh evidence/LEARNING-652/benchmark/L775-run298/replay.sh OMC OUTDIR` from the repository
root (`EXEC=0` for the component pin). Seed: 51 rows, fail 0. Pin: 38 rows, fail 0.

| Group | Both compilers |
|---|---|
| `core-test` (core.om) | exit 0, `BENCHMARK_CORE_PASS` 185 checks |
| bypass mutants `mutant-pins`, `mutant-scope` | compile 0, exit 120 and 48 |
| profile probes | traps 101/102/103/104/105/107; refusals: compiler 7 (mixed types), 3 (float) |
| L776 public fixtures | 6 programs exit 0; saturating-add exit 105; observable-saturating exit 0 (wrong bytes); literal overflow compiler 8 |
| `observe-pair` on actual oracle bytes | good 0, wrong value 7, empty 40, truncated 41, extra byte 42 |
| L776 admission | production 0, provenance bypass 83, source-identity bypass 93, L782 reviewer probe 0 |

With the component pin every rebuilt executable recorded at `resume-20261023/source-artifacts.sha256`
is byte-identical (core-test `e9f0335f`, observe-pair `6d3ab408`, oracle `49ddca9f`, observable
`3120b239`, saturating `40312438`, mutant-pins `b4458a85`, mutant-scope `6dedfcc1`), and admission
production is `4c43fcd5`, the ELF the L782 disposition recorded.

### Native executor (main seed omc only)

`run-test` = `core.om` + `run.om` + `run-test.om`, run from the output `bin/` directory with
fourteen arguments and stdin from the non-empty `good.bin`: exit 0, `BENCHMARK_RUN_PASS`. Its own
observation rows (`seed-6d1b1cf5/run-test.stdout`: argv index, status, exit code, bytes, elapsed ns,
`lobserve` result):

| argv | Candidate | status | code | bytes | elapsed | result |
|---|---|---|---|---|---|---|
| 2 | observable | 0 | 0 | 128 | 1.4 ms | 0 correct |
| 3 | saturating | 0 | 0 | 128 | 1.4 ms | 7 wrong value |
| 4 | empty | 0 | 0 | 0 | 1.4 ms | 9 empty |
| 5 | spin (10^12 steps), deadline 0.5 s | 4 | 0 | 0 | 500.4 ms | 4 timeout |
| 6 | trap-div | 0 | 102 | 0 | 1.3 ms | 8 trap mismatch |
| 7 | flood (4096 bytes) | 5 | 0 | 0 | 0.5 ms | 5 resource |
| 8 | absent path | 6 | 0 | 0 | 0 | 6 operational |
| 9 | escape (fork) | 0 | 0 | 0 | 1.4 ms | 9 (fork refused by the strict profile) |
| 10 | exactly 256 bytes | 0 | 0 | 256 | 1.3 ms | 7 (allowed, wrong length) |
| 11 | oracle bytes in two writes | 0 | 0 | 128 | 4.0 ms | 0 correct |
| 12 | stdin reader | 0 | 0 | 0 | 1.2 ms | 9 (saw end of file, not `good.bin`) |
| 13 | non-executable file (`cand-empty.om`) | 6 | 0 | 0 | 1.3 ms | 6 (launch nonce) |
| 14 | directory `.` | 6 | 0 | 0 | 1.3 ms | 6 (launch nonce) |
| 5 | spin, deadline 3 s | 5 | 24 | 0 | 1107.2 ms | 5 (SIGXCPU from the profile) |

Accounting over the thirteen 0.5 s attempts: `lbegin 13 1` → 0, thirteen `lattempt` → 0,
`lfinish` → 0, attempts 13, pass@1 2, budgeted pass 2, energy-unknown 13. The same tasks with one
never attempted: `lfinish` → 30, completed flag 0. The timeout row must be charged more than the
0.5 s deadline and less than 0.9 s. A first spin fixture used a bare `while true`; its implicit loop
bound trapped 104 after 1.5 ms (observed), so it was replaced with nested fixed loops. A second
seed replay gave identical exits and binaries (only timing-bearing stdout differs).

Mutants (`mutants/`, each one changed or inserted line of `run.om` plus a leading `note`):

| Mutant | exit | falsified check |
|---|---|---|
| `timeout-completed` (deadline reported as completed) | 47 | spin must be 4 |
| `no-deadline` (deadline never enforced) | 47 | spin must be 4 |
| `status-byte0` (exit code read from the signal byte) | 48 | trap-div must keep code 102 |
| `no-output-cap` (cap removed) | 49 | flood must be 5 |
| `cap-257` (257 bytes accepted) | 49 | flood must be 5 |
| `no-isolation` (`execprog` for `execpure`) | 51 | escape must be 9, not exit 9 |
| `cap-255` (256 bytes refused) | 52 | 256 bytes must complete (7) |
| `first-read-eof` (first chunk taken as the end) | 53 | split write must assemble (0) |
| `stdin-inherited` (supervisor stdin passed on) | 54 | stdin reader must see end of file (9) |
| `nonce-ignored` (launch nonce never recognised) | 55 | non-executable must be 6 |
| `no-kill` (signal 0 instead of SIGKILL) | 58 | timeout must end before 0.9 s |
| `signal-completed` (signal reported as completed) | 59 | SIGXCPU spin must be 5 |
| `missing-launched` (absent path launched) | 0 | equivalent: the nonce still reports 6 |

With the component pin `cand-escape` and `run-test` are refused with compiler error 3 (unknown name):
the process words postdate that pin. Nothing is launched.

### Review

Independent reviewer L775RunReview (first round, at `6378a0ca`) reproduced every row and the
cherry-pick identity, and asked for changes: a launch refused inside the child was scored as a
completed exit 122 (fixed with the launch nonce), the kill was not proven (CPU limit masked it; fixed
with the 0.9 s bound and the `no-kill` mutant), a reaped pid could be signalled (fixed: kill only
while unreaped), and four mutants survived (now fixtures and killed mutants above).

## Limits

IMPLEMENTED + EXERCISED on the host. Not covered: candidate compilation inside the executor,
compiler/executable identity measurement (`LPin` is still caller-supplied in run-test), a
seccomp-kill (SIGSYS) fixture, peak memory and energy measurement (peak is the declared 128 MiB
ceiling), protected split custody, sample-size freeze, model/retrieval baselines. #653 and #652
stay open; #655..#658 are ordered after #653 acceptance and were not started. Timings are single
host runs, not benchmarks.
