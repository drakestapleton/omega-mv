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
  four candidate fixtures in `tests/learning/benchmark/cand/`, five executor mutants in `mutants/`,
  `replay.sh` and the contract section in `docs/learning/benchmark-v1.md`.

## Compilers (born here, `compilers/`)

| omc | sha256 | origin |
|---|---|---|
| component pin | `191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9` | omega-bridge `0fc7d866` `tools/bootstrap.sh --offline` (seed0 → om4 → fixpoint), PASS |
| main seed | `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8` | `sh seed/omega-from-seed.sh` at main `1e3ecbba`, RC=0 |

## Results (`seed-6d1b1cf5/results.tsv`, `pin-191b776e/results.tsv`, raw stdout/stderr/exits beside them)

Command: `sh evidence/LEARNING-652/benchmark/L775-run298/replay.sh OMC OUTDIR` from the repository
root (`EXEC=0` for the component pin). Seed: 40 rows, fail 0. Pin: 35 rows, fail 0.

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

`run-test` = `core.om` + `run.om` + `run-test.om`, run from the output `bin/` directory with nine
arguments (oracle, observable, saturating, empty, spin, trap-div, flood, absent path, escape):
exit 0, `BENCHMARK_RUN_PASS`. Its own observation rows (`seed-6d1b1cf5/run-test.stdout`: status,
exit code, bytes, elapsed, `lobserve` result):

| Candidate | status | code | bytes | elapsed | result |
|---|---|---|---|---|---|
| observable | 0 | 0 | 128 | 21.9 ms | 0 correct |
| saturating | 0 | 0 | 128 | 52.3 ms | 7 wrong value |
| empty | 0 | 0 | 0 | 24.1 ms | 9 empty |
| spin (10^12 steps) | 4 | 0 | 0 | 500.7 ms | 4 timeout |
| trap-div | 0 | 102 | 0 | 1.8 ms | 8 trap mismatch |
| flood (4096 bytes) | 5 | 0 | 0 | 0.8 ms | 5 resource |
| absent path | 6 | 0 | 0 | 0 | 6 operational |
| escape (fork) | 0 | 0 | 0 | 1.5 ms | 9 (fork refused by the strict profile) |

Accounting over these eight real attempts: `lbegin 8 1` → 0, eight `lattempt` → 0, `lfinish` → 0,
attempts 8, pass@1 1, budgeted pass 1, energy-unknown 8. The same eight tasks with one never
attempted: `lfinish` → 30, completed flag 0. A first spin fixture used a bare `while true`; its
implicit loop bound trapped 104 after 1.5 ms (observed), so it was replaced with nested fixed loops.

| Mutant of run.om | exit | falsified check |
|---|---|---|
| `timeout-completed` (deadline reported as completed) | 47 | spin must be 4 |
| `no-deadline` (deadline never enforced) | 47 | spin must be 4 |
| `no-output-cap` (cap removed) | 49 | flood must be 5 |
| `missing-launched` (absent path launched) | 50 | absent path must be 6 |
| `no-isolation` (`execprog` for `execpure`) | 51 | escape must be 9, not exit 9 |

With the component pin `cand-escape` and `run-test` are refused with compiler error 3 (unknown name):
the process words postdate that pin. Nothing is launched.

## Limits

IMPLEMENTED + EXERCISED on the host. Not covered: candidate compilation inside the executor,
compiler/executable identity measurement (`LPin` is still caller-supplied in run-test), the signal
branch with a real signal, peak memory and energy measurement, protected split custody,
sample-size freeze, model/retrieval baselines. #653 and #652 stay open; #655..#658 are ordered
after #653 acceptance and were not started. Timings are single host runs, not benchmarks.
