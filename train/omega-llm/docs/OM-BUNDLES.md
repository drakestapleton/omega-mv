# `.om` Specialist Bundles & Local `omc` Feedback Loop

Architecture, measured corpus inventory, dataset/refusal-pair builder, and local compile-retry loop for turning Omega LLM (`ollm`) + `OLLMSP01` swappable specialist bundles ([SPECIALISTS.md](SPECIALISTS.md)) into a fast, native `.om` coding engine.

## 1. Three-Bottleneck Architecture

| Bottleneck vs Python | Native Omega Target | Mechanism |
|---|---|---|
| **1. Large active weights / slow decode** | Smaller active weights and higher decode throughput on GB10 | Freeze base layers (`0..base_L-1`) and attach thin `OLLMSP01` domain bundles (`14.1 MB` per 1 added layer / `28.3 MB` per 2 added layers on v2 `D=384, F=1536`) instead of serving one monolithic general model. Compose domains via `spmerge`, `spstack`, or shared-base `spens`. |
| **2. Out-of-distribution `.om` overhead** | Zero `writing-omega` prompt warmup; target 0–1 compile retries instead of 2–4 | Train domain bundles directly on deduplicated first-party `.om` code plus live `omc` refusal-repair pairs spanning all 30 compiler error codes (`1..30`), using completion-only masking (`fcachem`) so loss is computed only on `.om` completions. |
| **3. Slow edit-check-fix loop** | Millisecond local `omc` feedback loop | Generate candidate `.om` via `ollm spsamp` -> compile via stdin with local `omc` in single-digit milliseconds -> on refusal (`rc != 0`), inject exact `omc: line N: error K` stderr back into the retry prompt. Never execute refused output. |

## 2. Verification Status (`EXERCISED` vs `NOT_RUN`)

| Capability | Status | Platform / Evidence |
|---|---|---|
| Local `.om` corpus audit & SHA-256 deduplication | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_bundle_data.py audit` |
| Live `omc` refusal-repair pair generation (all 30 error codes `1..30`) | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), local `omc` (`sha256: 68a590c3…feb9c`), 38/38 pairs compiled & verified |
| Deterministic zero-leakage bundle splits + `ollm bpeenc` + `ollm fcachem` verification | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), all 4 bundles verified `leakage_hashes=0` and `FCACHE 2 256 384 8` |
| Local `omc` compile latency benchmark (20 runs per unit) | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_compile_loop.py bench --runs 20` |
| Local `ollm spsamp` + `omc` compile-retry harness | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_compile_loop.py selftest` (deterministic refusal->repair + live `omega-code_pro.sp` loop) |
| Full M2 CPU training of all 4 `.om` domain bundles (`om-core.sp`, `gb20b-mmio.sp`, `aienux-kernel.sp`, `libos-rpc.sp`) | `NOT_RUN` | Training commands specified below; only dataset build + `fcachem` compatibility exercised here |
| GB10 GPU training (`gtrainf` / `gtrainb`) & GB10 decode throughput | `NOT_RUN` | Requires authorized DGX Spark `spark-window` |
| Aienux / GB20B live inference & hardware-in-the-loop coding | `NOT_RUN` | Requires authorized hardware window; no GPU or Aienux runtime touched |

## 3. Measured Local `.om` Corpus Inventory

Measured on Apple Silicon M2 CPU via `python3 tools/om_bundle_data.py audit`:

- **Total `.om` across all workspace directories:** `12,502` files, `5,870,743` LOC (`119,417,595` bytes; `6,960` duplicate files across git worktrees/clones).
- **Unique `.om` (SHA-256 deduplicated):** `5,542` files, `1,727,419` LOC (`35,730,214` bytes).
- **Clean positive `.om` (excluding intentional `errNN_*`, `mistake_*`, and mutant negative-control files):** `5,457` files, `1,726,006` LOC.

### Audit Breakdown by Domain Category (SHA-256 Deduplicated)

| Category | Unique Files | Unique LOC | Clean Positive Files | Clean Positive LOC | Target Bundle |
|---|---:|---:|---:|---:|---|
| `om-core` | 4,023 | 1,173,226 | 3,944 | 1,172,390 | `om-core.sp` |
| `ollm` (CPU/native trainer) | 156 | 80,744 | 156 | 80,744 | `om-core.sp` |
| `gb20b-mmio` (Blackwell/GPU/CUDApp/GSP/SEC2/MMIO) | 907 | 276,096 | 907 | 276,096 | `gb20b-mmio.sp` |
| `aienux-kernel` (Aienux/EFI/MMU/drivers) | 249 | 102,658 | 243 | 102,081 | `aienux-kernel.sp` |
| `libos-rpc` (LibosLog/RPC/HTTP/JSON/wire/net) | 207 | 94,695 | 207 | 94,695 | `libos-rpc.sp` |
| **Total** | **5,542** | **1,727,419** | **5,457** | **1,726,006** | — |

### Specialist Bundle Layout & Composition

| Bundle Pack | Scope | Composition Role |
|---|---|---|
| `om-core.sp` | Core `.om` syntax/stdlib/OLLM CPU + 38 live-verified `omc` refusal-repair pairs (errors `1..30`) | Shared language foundation |
| `gb20b-mmio.sp` | GB20B / Blackwell GPU kernels, GSP/SEC2, MMIO, `devctl`/`vfioctl`/`mapget`/`mapset` | Hardware/GPU domain specialist |
| `aienux-kernel.sp` | Aienux OS, ARM64/x86 UEFI (`target a64efi`/`x86efi`), MMU/boot, bare-metal drivers | OS/kernel domain specialist |
| `libos-rpc.sp` | LibosLog, RPC, HTTP/JSON/TLS wire codecs, `serve.om`, IPC | Wire/protocol domain specialist |

Bundles are composed on top of a frozen base checkpoint (`BASE.ck`) without mutating base weights:
- **Same-depth weight fusion (`spmerge`):** merge `om-core.sp` + one or more domain packs via Linear Soup (`MODE=0`), Task Arithmetic (`MODE=1`), or TIES (`MODE=2`).
- **Vertical stacking (`spstack`):** stack `om-core.sp` layers below a domain pack (`L_out <= 16`) with residual scaling.
- **Parallel Product-of-Experts (`spens`):** run frozen base `0..base_L-1` once per step and fuse `om-core.sp` + domain pack log-probabilities in parallel.

### Dataset & `fcachem` Compatibility Smoke Check (Apple Silicon M2 CPU)

`tools/om_bundle_data.py build --max-examples 400 --verify-fcachem --include-err24` verified deterministic SHA-256 hash splitting (`int(sha256[:8], 16) % 10 == 0` -> held-out), zero hash overlap, BPE encoding via `ollm bpeenc` + `merges4096.bin`, and live `OLLMFH01` cache creation:

| Bundle | Train Files | Held Files | Leakage Hashes | Train Windows (`T=256`) | Held Windows (`T=256`) | `ollm fcachem` Verification |
|---|---:|---:|---:|---:|---:|---|
| `om-core` | 3,656 | 395 | 0 | 218 | 34 | `FCACHE 2 256 384 8` |
| `gb20b-mmio` | 775 | 93 | 0 | 197 | 40 | `FCACHE 2 256 384 8` |
| `aienux-kernel` | 202 | 29 | 0 | 194 | 38 | `FCACHE 2 256 384 8` |
| `libos-rpc` | 181 | 26 | 0 | 200 | 45 | `FCACHE 2 256 384 8` |

## 4. Measured Local `omc` Compile Latency (Apple Silicon M2 CPU)

Measured via `python3 tools/om_compile_loop.py bench --runs 20` against local Darwin ARM64 `omc` (`sha256: 68a590c37dfb1ec37a183f0032e02db1570db299266f574f65556edfc70feb9c`):

| Unit | LOC | Runs | Min (ms) | Median (ms) | P95 (ms) | Max (ms) | Output Binary (bytes) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `small_6loc` | 6 | 20 | 4.477 | 5.359 | 6.764 | 6.764 | 248 |
| `hello.om` | 9 | 20 | 4.069 | 4.914 | 6.992 | 6.992 | 396 |
| `om2_tour.om` | 43 | 20 | 4.077 | 4.875 | 6.810 | 6.810 | 716 |
| `medium_67loc` | 67 | 20 | 4.258 | 5.989 | 80.564 | 80.564 | 960 |
| `large_564loc` | 565 | 20 | 5.541 | 7.267 | 11.661 | 11.661 | 6,020 |
| `ollm-darwin.om` (full OLLM) | 6,423 | 20 | 32.116 | 36.044 | 126.225 | 126.225 | 214,816 |

Typical single-function and module-sized `.om` edits (`6–565` LOC) compile in **4.9–7.3 ms median** on M2 CPU, and the entire 6,423-LOC `ollm` binary compiles in **36.0 ms median**.

### Local Compile-Retry Harness Self-Test (Apple Silicon M2 CPU)

`python3 tools/om_compile_loop.py selftest` exercised both:
1. **Deterministic refusal -> repair:** `x = 5` refused by `omc` (`rc=11`, `omc: line 2: error 11`) in `5.947 ms`; repaired `x = int 5` compiled cleanly (`rc=0`, `212` bytes) in `4.831 ms`.
2. **Live `ollm spsamp` + `omc` retry loop (`omega-code_pro.sp` on `omega-v2.ck`):** 3 attempts (`3.95–5.57 s` CPU `spsamp` + `5.80–6.86 ms` `omc` check per attempt), capturing real `omc` refusals (`error 16` -> `error 4`) and feeding them back into each retry prompt.

## 5. Exact Commands

### A. Audit Corpus, Verify 30-Error Refusals, and Build Bundle Datasets

```sh
# 1. Audit local .om corpus (total + SHA-256 deduplicated)
python3 tools/om_bundle_data.py audit --workspace "$HOME/workspace"

# 2. Generate and live-verify all 30 omc refusal-repair pairs (errors 1..30)
python3 tools/om_bundle_data.py refusals \
  --omc "$HOME/.local/bin/omc" \
  --include-err24 \
  --out "$OUT/refusals.jsonl"

# 3. Build deterministic, zero-leakage .tok + .msk bundle datasets and verify fcachem
python3 tools/om_bundle_data.py build \
  --workspace "$HOME/workspace" \
  --omc "$HOME/.local/bin/omc" \
  --ollm "$HOME/.local/bin/ollm" \
  --merges "$HOME/workspace/aien-train-macbook/local-mac/merges4096.bin" \
  --base-ck "$HOME/workspace/aien-train-macbook/local-mac/omega-v2.ck" \
  --out-dir "$OUT/bundles" \
  --verify-fcachem \
  --include-err24
```

### B. Train Each `.om` Specialist Bundle on M2 CPU (`growpro` + `fcachem` + `trainfc` + `spext`)

Run for each `BUNDLE` in `om-core`, `gb20b-mmio`, `aienux-kernel`, `libos-rpc`:

```sh
OLLM="$HOME/.local/bin/ollm"
BASE_CK="$HOME/workspace/aien-train-macbook/local-mac/omega-v2.ck"
MERGES="$HOME/workspace/aien-train-macbook/local-mac/merges4096.bin"
DATA="$OUT/bundles"

for BUNDLE in om-core gb20b-mmio aienux-kernel libos-rpc; do
  # 1. Precompute masked frozen-base hidden cache (OLLMFH01)
  "$OLLM" fcachem "$BASE_CK" "$DATA/${BUNDLE}_aligned.tok" "$DATA/${BUNDLE}_aligned.msk" 160 "$OUT/${BUNDLE}.hc"

  # 2. LLaMA-Pro block-expansion growth (8 -> 10 layers, bit-identical step-0 base)
  "$OLLM" growpro "$BASE_CK" "$OUT/${BUNDLE}_l10.ck" 10 400 3500

  # 3. Train unfrozen specialist layers (8..9) from cached hidden states
  "$OLLM" trainfc "$OUT/${BUNDLE}_l10.ck" "$OUT/${BUNDLE}.hc" 400 50 8 1

  # 4. Extract OLLMSP01 specialist pack (verifies frozen base bit-identical)
  "$OLLM" spext "$BASE_CK" "$OUT/${BUNDLE}_l10.ck" "$OUT/${BUNDLE}.sp"

  # 5. Verify held-out eval directly from pack
  "$OLLM" speval "$BASE_CK" "$OUT/${BUNDLE}.sp" "$DATA/${BUNDLE}_held.tok" 20 "$MERGES"
done

# Optional composition (example: om-core + gb20b-mmio)
"$OLLM" spmerge "$BASE_CK" 2 "$OUT/om-gb20b-ties.sp" 500 "$OUT/om-core.sp" 500 "$OUT/gb20b-mmio.sp"
"$OLLM" spstack "$BASE_CK" "$OUT/om-core.sp" "$OUT/gb20b-mmio.sp" 1000 1000 "$OUT/om-gb20b-stack.sp"
```

### C. Run the Local `ollm spsamp` + `omc` Feedback Loop on M2 CPU

```sh
# 20-run omc latency benchmark
python3 tools/om_compile_loop.py bench --runs 20

# End-to-end self-test (deterministic refusal->repair + live spsamp->omc retry)
python3 tools/om_compile_loop.py selftest

# Interactive / single-prompt compile-retry loop with any trained bundle
python3 tools/om_compile_loop.py loop \
  --pack "$OUT/om-core.sp" \
  --prompt "note return sum of two ulong values\nfn add2 a ulong b ulong to ulong\n" \
  --max-retries 3 \
  --tokens 64 \
  --temp-milli 200
```

### D. Train on GB10 GPU (`NOT_RUN` — Requires Authorized `spark-window`)

> Do **not** execute without an explicitly authorized DGX Spark hardware window.

```sh
# Inside an authorized spark-window on DGX Spark (GB10), using ollm-gb10 built with TARGET=gb10:
# 1. Grow base checkpoint on host or Spark (e.g. L=8 -> 10 via growpro)
./ollm-gb10 growpro "$BASE_CK" "$WORK/${BUNDLE}_l10.ck" 10 2000 3000

# 2. Frozen-core GPU specialist training (gtrainf freezes layers 0..7 on-chip)
./ollm-gb10 gtrainf "$WORK/${BUNDLE}_l10.ck" "$DATA/${BUNDLE}_aligned.tok" 2000 100 8

# 3. Extract portable OLLMSP01 pack & verify on held-out split
./ollm-gb10 spext "$BASE_CK" "$WORK/${BUNDLE}_l10.ck" "$OUT/${BUNDLE}.sp"
./ollm-gb10 speval "$BASE_CK" "$OUT/${BUNDLE}.sp" "$DATA/${BUNDLE}_held.tok" 20 "$MERGES"
```
