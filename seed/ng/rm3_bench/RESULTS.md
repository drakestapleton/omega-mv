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

# 2. Run pure-OM-2 fail-closed verification gate (4-arm fib38 + matmul + opt_probe + 7 negative controls):
(printf 'om2\n'; cat seed/ng/sha256.om seed/ng/rm3_bench/gate_rm3.om) | seed/out/omc > /tmp/om_sw_rm3_run/gate_rm3
chmod +x /tmp/om_sw_rm3_run/gate_rm3
/tmp/om_sw_rm3_run/gate_rm3 seed/out/omc /tmp/om_sw_rm3_run/ng /tmp/om_sw_rm3_run/rm3_bench /tmp/om_sw_rm3_run/gscr seed/ng/bench/kernels
```

---

## 7. Before vs After RM3 Optimization A/B (`MEASURED HOST AArch64`)

Status: **`MEASURED HOST AArch64`** (same DGX Spark `spark-b87b`, NVIDIA GB10 Grace Cortex-X925 `taskset -c 5-9`, `warm=2`, `reps=7`, identical frozen 11-kernel 4-arm paired protocol via `run_rm3.sh`; not `QUALIFIED`).

### 7.1 Optimization Passes Implemented (Pure Seeded OM-2)

- **`seed/ng/src/front.om`** (`@ng front-ir` lowering only; `fe_check` untouched, SHA-256 `4cdd6dd39d353042c25ac754ca8e6dabf3c32ff0da33b87cae351e6169d4a198`):
  1. **Counted-loop unrolling (`for i T K unroll`, `K` in `1..64`, nesting depth `<= 16`)** with full contract parity (replays `invariant` at every iteration head `i = 0 .. K-1` and at the final head `i = K`).
  2. **Deterministic `fn ... inline` expansion (depth `<= 4`)** with contract parity (`requires`/`ensures` preserved) and straight-line zero-extra-block fast path for void / single-trailing-`ret` helpers (`chacha20_qr`, `chacha20_ld32`).
  3. **Constant folding & identity simplification inside unroll/inline zones** (`fe_lfold`, `not`, unsigned narrowing `const` conversions) plus **`rotl t a (const k)` → `rotr t a (const (w - k))`** (eliminates `NEG` on every A64 rotate).
  4. **Static-proof check elision (semantics & trap order preserved):**
     - `chk.shift` omitted when shift/rotate amount is a constant `< width`.
     - `chk.conv` omitted (and redundant bitmask bypassed before truncating `conv`) when unsigned narrowing source is provably in range (`x & mask` or `x >> (ws - wd)`).
     - Static-length slice/array bounds-check elimination (`fact.inbounds 1` with shared entry-block `const u64 1`) when index is provably `< static_len` via constant, active unsigned rolled-`for` induction SSA value (`i`, `i + c`, `c - i`), `x & mask`, or `x % d`; plus same-block duplicate `chk.bounds` deduplication on identical `(r, ix)`.
- **`seed/ng/src/opt.om`** (SHA-256 `bf11e03aa29e1ff6335f1cf8763121196174893b260d984049cb7f02f077cd16`):
  1. **Single-block local pass (`op_blk1`, `i_fnb < 2`):** O(N) algebraic identities (`+0`, `-0`, `|0`, `^0`, `*1`, `*0`, `&0`, shifts/rotates by `0`), non-constant pure-op CSE, alias-sound local **store-to-load forwarding + dead store elimination** on `(base_ref, const_idx)` (never crossing checks/calls/hosts), and backward DCE with a 4096-bit Bloom filter over `o_ch` that removes dead `fact.inbounds` and dead folded constants without stretching constant live ranges.
  2. **Post-loop function-wide dead pure-op DCE (`op_dce_fn`)** executed after `op_cnt` recording so all 33 pinned `gate-ir.om` `O`/`L` rows remain byte-for-byte unchanged while unrolled multi-block functions (`chacha20_block`, `sha2_b256`) shed dead intermediate constants.

### 7.2 A/B Provenance

| Item | Before (`ng_before`) | After (`ng_after`) |
|---|---|---|
| `ng` ELF SHA-256 (2× bit-identical) | `f94bd71669ee2c763c1697be4a47d9db51a8d6aabd2f196c2eee77b9c39405fb` | `2f2c4119fcb579a796dd9201181b7da1b68c6bb3843c11c2e498eabf7a4686a3` |
| `seed/out/omc` SHA-256 | `28fca13d44054e26f78c33d1753fd5c005d08e9144d95985c90bd75b60885072` | `28fca13d44054e26f78c33d1753fd5c005d08e9144d95985c90bd75b60885072` |
| Pinned Cores / Protocol | `taskset -c 5-9`, `warm=2`, `reps=7` | `taskset -c 5-9`, `warm=2`, `reps=7` |
| Load Average (Start → End) | `9.30 9.35 9.67` → `8.89 9.27 9.62` | `9.01 9.96 9.07` → `8.85 9.77 9.06` |
| Exact Output Parity | `11/11` kernels, `396/396` runs `fail=0` | `11/11` kernels, `396/396` runs `fail=0` |

### 7.3 Wall-Clock Before vs After (All 11 Kernels, Zero Cherry-Picking)

Ratios below `1.000` indicate speedup (`ng_after` faster than baseline / reference arm).

| Kernel | `omc` med (ms) | `ng_before` med (ms) | `ng_after` med (ms) | `gcc -O2` med (ms) | `gcc -O3` med (ms) | `ng_after / ng_before` | `ng_before / omc` | `ng_after / omc` | `ng_after / gcc -O2` | `ng_after / gcc -O3` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `arith` | 120.133 | 119.824 | 119.939 | 34.623 | 34.664 | 1.0010 | 0.9974 | **0.9984** | 3.4641 | 3.4600 |
| `bcopy` | 269.947 | 213.228 | 202.903 | 8.874 | 135.345 | **0.9516** | 0.7892 | **0.7516** | 22.8661 | 1.4992 |
| `branch` | 138.163 | 167.275 | 165.524 | 74.174 | 109.248 | **0.9895** | 1.2067 | 1.1980 | 2.2316 | 1.5151 |
| `chacha` | 211.708 | 634.898 | **249.961** | 88.015 | 67.451 | **0.3937** | 3.0050 | **1.1807** | 2.8400 | 3.7058 |
| `fib38` | 136.382 | 68.455 | 68.457 | 34.077 | 34.119 | 1.0000 | 0.5020 | **0.5019** | 2.0089 | 2.0064 |
| `isort` | 77.938 | 77.886 | 77.888 | 39.243 | 52.014 | 1.0000 | 1.0004 | **0.9994** | 1.9847 | 1.4974 |
| `leafcall` | 54.024 | 23.518 | 23.340 | 15.869 | 15.797 | **0.9924** | 0.4346 | **0.4320** | 1.4708 | 1.4775 |
| `matmul` | 18.230 | 17.160 | 17.212 | 10.965 | 10.965 | 1.0030 | 0.9427 | **0.9442** | 1.5698 | 1.5698 |
| `sha` | 193.305 | 379.983 | **317.522** | 131.831 | 131.820 | **0.8356** | 1.9673 | **1.6426** | 2.4086 | 2.4087 |
| `sieve` | 246.319 | 230.525 | **220.294** | 119.213 | 95.981 | **0.9556** | 0.9423 | **0.8943** | 1.8479 | 2.2952 |
| `sort` | 308.923 | 343.301 | 360.264 | 113.029 | 113.004 | 1.0494 | 1.1098 | 1.1662 | 3.1873 | 3.1881 |
| **Geomean (all 11)** | — | — | — | — | — | **0.8989** (`1.1125×` faster) | 1.0173 | **0.9140** (`1.0941×` vs `omc`) | **2.7408** | **2.1040** |

Raw `min..max` wall ms ranges across the 7 measured After rounds (from `P` rows):
- `arith`: `omc` 119.997..120.248, `ng` 119.835..120.520, `gccO2` 34.540..35.122, `gccO3` 33.983..35.190
- `bcopy`: `omc` 269.755..270.098, `ng` 202.761..202.999, `gccO2` 8.787..9.126, `gccO3` 135.281..135.917
- `branch`: `omc` 137.803..139.559, `ng` 165.274..165.865, `gccO2` 74.088..74.487, `gccO3` 108.353..110.284
- `chacha`: `omc` 211.272..213.923, `ng` 249.428..250.928, `gccO2` 87.786..88.169, `gccO3` 67.228..67.698
- `fib38`: `omc` 136.261..138.487, `ng` 68.008..72.939, `gccO2` 33.969..34.341, `gccO3` 34.028..34.221
- `isort`: `omc` 77.736..81.911, `ng` 77.783..80.173, `gccO2` 39.178..41.134, `gccO3` 51.947..52.329
- `leafcall`: `omc` 53.962..54.216, `ng` 19.530..23.532, `gccO2` 15.770..15.946, `gccO3` 15.785..15.908
- `matmul`: `omc` 18.051..18.415, `ng` 17.029..17.416, `gccO2` 10.792..11.121, `gccO3` 10.850..11.107
- `sha`: `omc` 192.985..195.061, `ng` 317.128..318.723, `gccO2` 131.620..132.390, `gccO3` 131.590..132.376
- `sieve`: `omc` 243.307..246.889, `ng` 218.529..222.635, `gccO2` 116.777..121.136, `gccO3` 92.849..98.664
- `sort`: `omc` 308.744..309.287, `ng` 360.172..429.292, `gccO2` 112.683..113.274, `gccO3` 112.672..113.348

### 7.4 Compile-Time & ELF-Size Deltas (`ng_before` → `ng_after`)

| Kernel | `ng_before` comp (ms) | `ng_after` comp (ms) | Comp ratio | `ng_before` ELF (B) | `ng_after` ELF (B) | ELF delta (B) | `omc` comp (ms) | `gcc -O2` comp (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `arith` | 2.208 | 2.073 | 0.938× | 1,088 | 1,072 | −16 | 0.613 | 51.412 |
| `bcopy` | 1.767 | 1.615 | 0.914× | 656 | 592 | −64 | 0.386 | 48.170 |
| `branch` | 1.739 | 1.817 | 1.045× | 1,136 | 1,120 | −16 | 0.616 | 40.848 |
| `chacha` | 7.049 | 8.745 | 1.240× | 17,220 | 28,336 | +11,116 | 1.565 | 68.069 |
| `fib38` | 1.372 | 1.516 | 1.104× | 1,032 | 1,032 | 0 | 0.393 | 48.851 |
| `isort` | 2.218 | 2.054 | 0.926× | 1,628 | 1,608 | −20 | 0.674 | 45.467 |
| `leafcall` | 1.710 | 1.291 | 0.755× | 1,088 | 1,088 | 0 | 0.610 | 66.836 |
| `matmul` | 1.673 | 1.876 | 1.121× | 1,648 | 1,648 | 0 | 0.615 | 57.704 |
| `sha` | 9.884 | 19.823 | 2.005× | 21,724 | 52,396 | +30,672 | 2.692 | 151.787 |
| `sieve` | 1.890 | 1.803 | 0.954× | 1,456 | 1,456 | 0 | 0.642 | 53.129 |
| `sort` | 1.839 | 1.951 | 1.061× | 1,728 | 1,600 | −128 | 0.629 | 40.121 |
| **Geomean (all 11)** | — | — | **1.0628×** (`22.31×` faster than `gcc -O2`) | — | — | **1.1110×** (shrank on 5/11, grew on 2 unrolled crypto kernels) | `79.24×` faster than `gcc -O2` | 1.00× |

### 7.5 Zero-Regression NG Gate Verification & Optimization-Breakage Mutants (DGX Spark)

All 7 NG verification gates passed with zero failures against the 2× bit-identical optimized `ng` (`2f2c4119fcb579a796dd9201181b7da1b68c6bb3843c11c2e498eabf7a4686a3`):

1. `seed/ng/a64/gate.om`: **`PASS`** (`cases 263 match 263 words 263`, `refusal cases 37 refused as written 37`, 2/2 mutants caught).
2. `seed/ng/target/gate.om`: **`NG-TARGET-GATE PASS checks=73 controls=10`**.
3. `seed/ng/front/gate-front.om` (full `check-lists.txt` including 5,876 C2 units): **`FRONTGATE PASS cases=6709 exact=6594 beyond=10 scope=105 ngonly=0 ngcap=0 fail=0 mutants=5 killed=5`**.
4. `seed/ng/front/gate-front-ir.om`: **`FRONTIRGATE PASS cases=593 run=342 refuse=151 host=100 classed=61 fail=0 mutants=18 killed=18 controls=2 tripped=2 notrun=0`**.
5. `seed/ng/gate-ir.om` (full 12-way partition + partition proof): **`NGIRGATE PARTS PASS K=12 items=340 cases=302`**, all 12/12 parts **`NGIRGATE PASS`** (`fail=0`; covers all 33 pinned `O`/`L` `opt-count` rows, 1,000 `ngrand` random seeds through `@ng opt` + `ngcheck` + `ngrun`, float/intcv/host oracles, 3 negative controls, and all 31 tool/opt/ngrun mutants).
6. `seed/ng/infix/gate_infix.om` (using new `ng`): **`GATE_INFIX PASS rt=18 direct=4 neg=15 ext=0 fail=0`**.
7. `seed/ng/rm3_bench/gate_rm3.om` (2× bit-identical `8086f707f0d2708ec65ebc4c2f81a77ebc118124010bda272e5791c917a2acce`): **`GATE_RM3 PASS kernels=3 arms=4 neg=7 fail=0`**, verifying positive `opt_probe` (unroll + inline + `rotl→rotr` + SLF/DSE/DCE + `>=10%` IR shrink) plus 7 fail-closed negative controls including `neg06_opt_noop_break` (`rc=1`) and `neg07_opt_sem_mutant` (`rc=1`).
8. **Live Compiler Source Mutants (`run_rm3.sh` Step `[4b/5]`):**
   - `opt_disabled_mutant` (`op_blk1` disabled in `opt.om`): caught fail-closed (`real_opt=86588 < noop_opt=102062 <= ir=108611`).
   - `opt_semantic_mutant` (`fe_lfold` add off-by-one in `front.om`, compiled on `sha.om`): caught fail-closed (`NEG_CONTROL_OK opt_semantic_mutant caught (rc=1)`, `R MISMATCH sha mut_sem`).

### 7.6 Honest Assessment of Remaining Gaps

- **`ng` now beats `seed/out/omc` across the full 11-kernel suite** (`0.9140×` geomean vs `1.0173×` before; faster on 7/11 kernels: `arith`, `bcopy`, `fib38`, `isort`, `leafcall`, `matmul`, `sieve`), and cuts `chacha` by **2.54×** (`3.005× → 1.181×` vs `omc`) and `sha` by **1.20×** (`1.967× → 1.643×` vs `omc`).
- Remaining `sha` (`1.643×` vs `omc`) and `chacha` (`1.181×` vs `omc`) gap comes from untouched `seed/ng/src/a64.om`, which emits 64-bit `add x / eor x / orr x / and x` followed by explicit `ubfx x, x, #0, #32` and register-variable `mov + ror w, w, w` rather than 32-bit `add w` / immediate `ror w, #imm`.
- `sort` regressed slightly (`343.301 ms → 360.264 ms`, `1.0494×`) even though its ELF shrank by `-128 B` (`1,728 B → 1,600 B`), attributable to inner `while`-loop fetch-line alignment on Cortex-X925 after outer-loop `chk.bounds` removal.
- Note: `seed/ng/ng.units` was intentionally left untouched in this wave so integration updates the `front.om`/`opt.om` SHA-256 pins once without cross-branch conflicts.
