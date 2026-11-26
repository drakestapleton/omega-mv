# Omega 1.0 RM3 Paired Efficiency Benchmark Results

Status: **`MEASURED HOST AArch64`** (DGX Spark `spark-b87b`, NVIDIA GB10 Grace Cortex-X925 cores `5-9`, Linux `7.0.0-1019-nvidia` aarch64). Not `QUALIFIED` (held-out inputs and quiesced single-core formal intervals remain under `seed/ng/bench/PREREG.md`).

All timing and exact output equality checks were conducted by the pure seeded OM-2 interleaved paired A/B conductor (`seed/ng/rm3_bench/rm3_bench.om`) launched via `seed/ng/rm3_bench/run_rm3.sh` (`taskset -c 5-9`, `warm=2`, `reps=7`, rotated alternating paired order across all 4 arms). All 11 kernels in the full suite are reported below with zero cherry-picking.

## 1. Provenance & Hardware Identity

| Item | Value |
|---|---|
| Host | `spark-b87b` (DGX Spark, NVIDIA GB10 Grace, 20 cores: 10× Cortex-X925 + 10× Cortex-A725) |
| OS / Kernel | `Linux spark-b87b 7.0.0-1019-nvidia #19~24.04.2-Ubuntu SMP PREEMPT_DYNAMIC aarch64` |
| Pinned Cores | `taskset -c 5-9` (Cortex-X925 performance cluster) |
| Load Average | Start `9.30 9.35 9.67` → End `8.89 9.27 9.62` (shared host, non-quiesced; reported honestly) |
| Rounds | `warm=2` warm-up + `reps=7` measured rounds per kernel × 4 arms (`396/396` runs `ok=36 fail=0`) |
| `seed/out/omc` SHA-256 | `28fca13d44054e26f78c33d1753fd5c005d08e9144d95985c90bd75b60885072` |
| `ng` (`seed/ng/ng.units`) SHA-256 | `f94bd71669ee2c763c1697be4a47d9db51a8d6aabd2f196c2eee77b9c39405fb` |
| `gcc` Version & SHA-256 | `gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0` (`a20520ee21543f243d40636a9181a142c45ecd989de31ab86b99a8ea5ada870d`) |
| `bench/omc_efficiency/PROTOCOL.md` SHA-256 | `ae1d1b2ace22bd30993f2ac14965d0e5ec62d9d66ae4b4e9521a417e5c74033a` |
| `rm3_bench.om` SHA-256 | `3cbb0fba3332d9b80b09a54061d51a6ab6e4a5517ded503588bd793573c6fc40` |
| `rm3_bench` ELF SHA-256 | `8737d7d78b41cc7a865949276601f0825097e552890684cea08ba8aeb4b85436` |

## 2. Correctness & Fail-Closed Controls

- **Exact Output Equality (Preflight + Every Timed Run):** Every kernel arm (`omc`, `ng`, `gcc -O2 -static`, `gcc -O3 -static`) verified `exit == 0` and exact 64-hex stdout SHA-256 match against the Wolfram-derived referee `seed/ng/bench/kernels/want/<kernel>.sha256` BEFORE timing and on EVERY single timed run (`11/11` kernels, `396/396` runs `fail=0`).
- **Planted Wrong-Output Negative Control (`run_rm3.sh`):** 1-edit mutant printing `39088170\n` instead of `fib(38) = 39088169\n` was refused fail-closed before timing (`NEG_CONTROL_OK planted_wrong_output caught (rc=1)`, `R MISMATCH fib38 mutant`).
- **Standalone Pure-OM-2 Gate (`gate_rm3.om`):** `GATE_RM3 PASS kernels=2 arms=4 neg=5 fail=0` (positive 4-arm `fib38` + `matmul` plus 5 fail-closed negative controls: wrong output `rc=1`, corrupted want hash `rc=1`, trapping arm `trap 1` `rc=1`, missing binary `rc=1`, invalid CLI mode `rc=2`).

## 3. Wall-Clock Execution Time (11 Real Kernels, Interleaved Paired Median)

Ratios below `1.000` mean the first-named arm is faster. Note on semantics (`PROTOCOL.md` §2): `omc` and `ng` execute mandatory runtime bounds (`trap 3`) and loop-fuel (`trap 4`) checks; `gcc -O2` / `gcc -O3` execute unchecked C.

| Kernel | `omc` med (ms) | `ng` med (ms) | `gcc -O2` med (ms) | `gcc -O3` med (ms) | `ng / omc` | `ng / gcc -O2` | `ng / gcc -O3` | `omc / gcc -O2` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `arith` | 120.142 | 119.824 | 34.758 | 34.658 | **0.9974** | 3.4474 | 3.4574 | 3.4565 |
| `bcopy` | 270.189 | 213.228 | 8.878 | 135.537 | **0.7892** | 24.0177 | 1.5732 | 30.4336 |
| `branch` | 138.626 | 167.275 | 74.205 | 109.286 | 1.2067 | 2.2542 | 1.5306 | 1.8682 |
| `chacha` | 211.279 | 634.898 | 87.948 | 67.341 | 3.0050 | 7.2191 | 9.4282 | 2.4023 |
| `fib38` | 136.374 | 68.455 | 33.978 | 34.158 | **0.5020** | 2.0147 | 2.0041 | 4.0136 |
| `isort` | 77.859 | 77.886 | 39.257 | 52.165 | 1.0004 | 1.9840 | 1.4931 | 1.9833 |
| `leafcall` | 54.113 | 23.518 | 15.822 | 15.988 | **0.4346** | 1.4864 | 1.4710 | 3.4201 |
| `matmul` | 18.202 | 17.160 | 10.841 | 10.962 | **0.9427** | 1.5829 | 1.5655 | 1.6790 |
| `sha` | 193.146 | 379.983 | 131.774 | 131.859 | 1.9673 | 2.8836 | 2.8817 | 1.4657 |
| `sieve` | 244.631 | 230.525 | 117.638 | 96.611 | **0.9423** | 1.9596 | 2.3861 | 2.0795 |
| `sort` | 309.322 | 343.301 | 113.292 | 113.538 | 1.1098 | 3.0302 | 3.0237 | 2.7303 |
| **Geomean (all 11)** | — | — | — | — | **1.0173** | **3.0558** | **2.3349** | **3.0037** |
| *Diagnostic Geomean (9 non-`inline`/`unroll`)* | — | — | — | — | ***0.8383*** | *2.7954* | — | *3.3348* |

Raw `min..max` wall ms ranges across the 7 measured rounds (from `P` rows):
- `arith`: `omc` 120.000..141.744, `ng` 119.790..119.936, `gccO2` 34.164..34.941, `gccO3` 34.255..48.514
- `bcopy`: `omc` 269.870..273.100, `ng` 205.744..216.203, `gccO2` 8.813..9.070, `gccO3` 135.333..136.926
- `branch`: `omc` 137.977..139.201, `ng` 167.064..168.862, `gccO2` 74.045..75.796, `gccO3` 108.808..109.922
- `chacha`: `omc` 211.042..211.980, `ng` 632.411..635.531, `gccO2` 87.713..88.255, `gccO3` 67.206..67.384
- `fib38`: `omc` 136.217..136.649, `ng` 68.022..69.089, `gccO2` 33.902..34.096, `gccO3` 33.963..34.294
- `isort`: `omc` 77.736..78.355, `ng` 77.717..78.916, `gccO2` 39.119..50.251, `gccO3` 51.951..52.340
- `leafcall`: `omc` 53.961..54.856, `ng` 23.469..25.783, `gccO2` 15.774..16.049, `gccO3` 15.750..16.760
- `matmul`: `omc` 18.045..18.298, `ng` 16.993..17.282, `gccO2` 10.782..11.074, `gccO3` 10.908..12.985
- `sha`: `omc` 193.058..194.592, `ng` 379.876..385.555, `gccO2` 131.661..133.145, `gccO3` 131.763..133.191
- `sieve`: `omc` 244.096..245.770, `ng` 229.356..233.590, `gccO2` 116.155..119.352, `gccO3` 94.591..97.827
- `sort`: `omc` 308.937..310.929, `ng` 341.921..367.158, `gccO2` 113.114..113.780, `gccO3` 112.947..114.451

## 4. Compile Time (ms) & Binary / Code Size (bytes)

Compile times are medians of 3 `monons`-timed builds per kernel and arm (`ng` sums all 3 pipeline stages: `@ng front-ir` + `@ng opt` + `@ng a64`). Omega binaries are complete zero-libc static AArch64 ELFs; `gcc` reports both total static ELF bytes and `.text` bytes from `gcc -c` (libc excluded).

| Kernel | `omc` comp (ms) | `ng` comp (ms) | `gcc -O2` comp (ms) | `gcc -O3` comp (ms) | `omc` ELF (B) | `ng` ELF (B) | `gcc -O2` ELF (B) | `gcc -O2` `.text` (B) | `gcc -O3` `.text` (B) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `arith` | 0.609 | 2.208 | 51.002 | 62.159 | 1,144 | 1,088 | 639,736 | 418 | 418 |
| `bcopy` | 0.583 | 1.767 | 50.849 | 49.825 | 536 | 656 | 639,672 | 504 | 472 |
| `branch` | 0.553 | 1.739 | 53.618 | 53.855 | 1,208 | 1,136 | 639,712 | 390 | 426 |
| `chacha` | 1.778 | 7.049 | 72.339 | 76.071 | 18,588 | 17,220 | 639,672 | 1,368 | 1,460 |
| `fib38` | 0.404 | 1.372 | 71.839 | 81.716 | 1,180 | 1,032 | 639,768 | 1,418 | 1,618 |
| `isort` | 0.671 | 2.218 | 57.245 | 56.238 | 1,844 | 1,628 | 639,760 | 610 | 646 |
| `leafcall` | 0.362 | 1.710 | 37.347 | 52.096 | 1,200 | 1,088 | 639,784 | 410 | 410 |
| `matmul` | 0.659 | 1.673 | 54.605 | 57.966 | 1,676 | 1,648 | 639,840 | 710 | 722 |
| `sha` | 2.710 | 9.884 | 138.447 | 150.402 | 33,212 | 21,724 | 639,776 | 8,760 | 8,964 |
| `sieve` | 0.686 | 1.890 | 55.347 | 62.404 | 1,504 | 1,456 | 639,840 | 582 | 862 |
| `sort` | 0.579 | 1.839 | 51.993 | 51.307 | 1,448 | 1,728 | 639,776 | 417 | 437 |
| **Geomean** | **83.55× faster than `gcc -O2`** | **24.97× faster than `gcc -O2`** | 1.00× | — | — | **Smaller than `omc` on 9/11** | — | — | — |

## 5. Honest Engineering Takeaways

1. **Where `ng` (`@ng opt` + `@ng a64`) already beats `seed/out/omc` (6 of 11 kernels, plus 1 tie):**
   - Call-heavy kernels achieve large speedups: `leafcall` is **2.30× faster** (`0.4346×`, within **1.49×** of unchecked `gcc -O2`) and `fib38` is **1.99× faster** (`0.5020×`, **2.01×** of `gcc -O2`).
   - Loop optimization (`@ng opt`: PHI/BCE/LICM/ROT) already moves `bcopy` (**1.27× faster**), `sieve` (**1.06× faster**), `matmul` (**1.06× faster**, within **1.58×** of unchecked `gcc -O2`), and `arith` (**1.003×**) ahead of `omc`, with `isort` tied (`1.0004×`).
   - Across the 9 non-`inline`/`unroll` kernels, `ng` achieves a `0.8383×` geometric mean vs `omc` (16.2% faster).
2. **Where `ng` currently loses to `omc` (exact root causes):**
   - `chacha` (`3.005×` slower than `omc`) and `sha` (`1.967×` slower than `omc`) dominate the 11-kernel geometric mean (`1.0173×` overall). Both crypto kernels rely heavily on OM-2 `fn ... inline` and `for ... unroll` hints, which `seed/ng/src/front.om` currently lowers as non-inlined calls and rolled loops (`seed/ng/front/README.md`). Adding function inlining + counted-loop unrolling to `@ng opt` directly closes this gap.
   - `branch` (`1.207×`) and `sort` (`1.110×`) show remaining loop/branch codegen overhead in `a64.om` vs `omc`.
3. **Gap to `gcc -O2` / `gcc -O3`:**
   - Full 11-kernel geomean: `ng / gcc -O2 = 3.0558×` (`omc / gcc -O2 = 3.0037×`), `ng / gcc -O3 = 2.3349×` (`gcc -O3 / gcc -O2 = 1.3088×` due to `gcc -O3` regressions on `bcopy`, `branch`, and `isort`, reproducing `seed/ng/bench/BASELINE.md`).
   - `bcopy` (`24.02×` vs `gcc -O2`) is by far the single largest gap: scalar byte loop with runtime checks vs 128-bit NEON `ldp/stp` vector copy.
   - Compile time and standalone footprint are overwhelming Omega strengths: `omc` compiles **83.55× faster** and 3-stage `ng` compiles **24.97× faster** than `gcc -O2 -static`, emitting **0.6 KB–21.7 KB** zero-libc static ELFs vs **~640 KB** static glibc ELFs.

## 6. Reproducible Replay (DGX Spark)

```sh
# 1. Run full 11-kernel 4-arm paired A/B benchmark on Grace X925 cores 5-9:
sh seed/ng/rm3_bench/run_rm3.sh . /tmp/om_sw_rm3_run 2 7 5-9

# 2. Run pure-OM-2 fail-closed verification gate (4-arm fib38 + matmul + 5 negative controls):
(printf 'om2\n'; cat seed/ng/sha256.om seed/ng/rm3_bench/gate_rm3.om) | seed/out/omc > /tmp/om_sw_rm3_run/gate_rm3
chmod +x /tmp/om_sw_rm3_run/gate_rm3
/tmp/om_sw_rm3_run/gate_rm3 seed/out/omc /tmp/om_sw_rm3_run/ng /tmp/om_sw_rm3_run/rm3_bench /tmp/om_sw_rm3_run/gscr seed/ng/bench/kernels
```
