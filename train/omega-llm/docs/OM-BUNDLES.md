# `.om` Specialist Chains, DNA-Style Chain Clipping & Local `omc` Feedback Loop

Architecture, measured corpus inventory, chain-organized dataset/refusal-pair builder, and local compile-retry loop for turning Omega LLM (`ollm`) + `OLLMSP01` swappable specialist packs ([SPECIALISTS.md](SPECIALISTS.md)) into composable **DNA-style Specialist Chains** for native `.om` coding.

## 1. Three-Bottleneck Architecture

| Bottleneck vs Python | Native Omega Target | Mechanism |
|---|---|---|
| **1. Large active weights / slow decode** | Smaller active weights and higher decode throughput on GB10 | Freeze base layers (`0..base_L-1`) and attach thin `OLLMSP01` specialist links (`14.1 MB` per 1 added layer / `28.3 MB` per 2 added layers on v2 `D=384, F=1536`) instead of serving one monolithic general model. Grow vertical Merkle chains and clip sibling strands together on a shared trunk. |
| **2. Out-of-distribution `.om` overhead** | Zero `writing-omega` prompt warmup; target 0–1 compile retries instead of 2–4 | Train chain links directly on deduplicated first-party `.om` code plus live `omc` refusal-repair pairs spanning all 30 compiler error codes (`1..30`), using completion-only masking (`fcachem`) so loss is computed only on `.om` completions. |
| **3. Slow edit-check-fix loop** | Millisecond local `omc` feedback loop | Generate candidate `.om` via `ollm spsamp` / `spchainsamp` / `spclip` -> compile via stdin with local `omc` in single-digit milliseconds -> on refusal (`rc != 0`), inject exact `omc: line N: error K` stderr back into the retry prompt. Never execute refused output. |

## 2. DNA-Style Specialist Chains & Chain Clipping

Rather than stopping at flat single-layer bundles, `.om` specialists are organized as **Vertical Merkle Chains (Strands)** that clip together with sibling strands via **Hybridization (`spclip`)** and **Residual Ligation (`spstack` + optional ligase bridge)**.

### A. Vertical Merkle Chains (Strands)

```text
                    base.ck (L0..7, frozen)
                              │  base_hash_0
                              ▼
                    om-core.sp (L8..9)            [Link 1: core .om + 30-error omc refusals]
                              │  base_hash_1
                              ▼
                 aienux-kernel.sp (L10..11)       [Link 2: Aienux OS / EFI / MMU / drivers]
                        ╱            ╲  base_hash_2 (shared trunk)
                       ▼              ▼
          gb20b-mmio.sp (L12..13)   libos-rpc.sp (L12..13)
          [Strand A: GB20B/GSP/     [Strand B: LibosLog / RPC /
           SEC2/MMIO/CUDApp]         HTTP / JSON / wire IPC]
```

- **Cryptographic prefix pinning:** every `OLLMSP01` link stores `base_L` and `base_hash = FNV1a64(shapes, ow[0..fz))`. Link `i+1` refuses to attach (`rc=62`) unless the exact frozen prefix chain `0..i` is present and bit-identical beneath it.
- **Per-link `fcachem` training:** each link caches the frozen prefix's hidden states once (`ollm fcachem`) and trains only its own added layers (`L -> L+2`) via `growpro` + `trainfc` + `spext`.

### B. DNA-Style Chain Clipping (Multi-Strand Hybridization & Ligation)

1. **Shared-Trunk Multi-Helix Clipping (`spclip`, `S = 2..4` strands — double, triple, or quad helix):**
   - Two to four strands sharing a frozen trunk hash (e.g., **Double Helix** clipping `gb20b-mmio` ⊕ `libos-rpc` over `base -> om-core -> aienux-kernel`, or **Triple Helix** clipping `aienux-kernel` ⊕ `gb20b-mmio` ⊕ `libos-rpc` over `base -> om-core`) evaluate the **longest common shared prefix** across all `S` strands **once per token** (`H_trunk`), then evaluate each strand's divergent tail layers over `H_trunk`:
     - **`MODE=0` (Prior-Weighted Product-of-Experts):** normalized weights `alpha_s = w_s / sum(w)`, fused `sum_s alpha_s * log P_s`.
     - **`MODE=1` (Entropy-Gated Multi-Helix):** computes per-token Shannon entropy `H_s = -sum P_s log P_s` for each strand, sets `u_s = w_s / (H_s + 0.001)` and `alpha_s = u_s / sum(u)`, and fuses `sum_s alpha_s * log P_s` so whichever specialized strand is most certain on the current token (e.g., `aienux-kernel` on page-table flags, `gb20b-mmio` on MMIO register offsets, or `libos-rpc` on RPC framing) naturally dominates.
2. **Residual Ligation / Sticky-End Ligase:**
   - Clips Strand B sequentially after Strand A via `ollm spstack` (`L_out <= 16`, with per-pack `(Wo, W2)` residual scaling), optionally followed by a 1-layer `fcachem`-trained **ligase bridge pack** (`L_out -> L_out + 1`) trained on cross-domain examples (e.g., GSP RPC over GB20B MMIO queues) to align the ligated representation while keeping both strands bit-identically frozen.

## 3. Verification Status (`EXERCISED` vs `NOT_RUN`)

| Capability | Status | Platform / Evidence |
|---|---|---|
| Local `.om` corpus audit & SHA-256 deduplication | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_bundle_data.py audit` |
| Live `omc` refusal-repair pair generation (all 30 error codes `1..30`) | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), local `omc` (`sha256: 68a590c3…feb9c`), 38/38 pairs compiled & verified |
| Chain-organized zero-leakage splits + `ollm bpeenc` + `ollm fcachem` verification | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), all 4 chain links verified `leakage_hashes=0` and `FCACHE 2 256 384 8` |
| Local `omc` compile latency benchmark (20 runs per unit) | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_compile_loop.py bench --runs 20` |
| Local single-pack `ollm spsamp` + `omc` compile-retry harness | `EXERCISED` | Apple Silicon M2 (Darwin arm64 CPU), `tools/om_compile_loop.py selftest` (deterministic refusal->repair + live `omega-code_pro.sp` loop) |
| Full M2 CPU multi-link chain training (`om-core` -> `aienux-kernel` -> `gb20b-mmio` / `libos-rpc`) | `NOT_RUN` | Exact chain recipes specified below; only dataset splits + `fcachem` compatibility exercised here |
| Pure-Omega `spchainapp` / `spchaineval` / `spchainsamp` / `spclip` (`S=2..4`) execution on trained `.om` chains | `NOT_RUN` | Engine verbs implemented in parallel branch `feat/ollm-chain-clip`; `.om` chain weights not yet trained |
| Sticky-end ligase bridge pack training (`L -> L+1`) | `NOT_RUN` | Architectural recipe documented below |
| On-chip GB10 frozen-core specialist training & GB10 decode throughput | `NOT_RUN` | Frozen-core GPU training is not yet implemented in `native/omegallm/gpu/gg.om` (CPU-only via `trainf`/`trainfc`); full-chip `gtrainf`/`gtrainb` mutates base layers and requires an authorized `spark-window` |
| Aienux / GB20B live inference & hardware-in-the-loop coding | `NOT_RUN` | Requires authorized hardware window; no GPU or Aienux runtime touched |

## 4. Measured Local `.om` Corpus Inventory

Measured on Apple Silicon M2 CPU via `python3 tools/om_bundle_data.py audit`:

- **Total `.om` across all workspace directories:** `12,502` files, `5,870,743` LOC (`119,417,595` bytes; `6,960` duplicate files across git worktrees/clones).
- **Unique `.om` (SHA-256 deduplicated):** `5,542` files, `1,727,419` LOC (`35,730,214` bytes).
- **Clean positive `.om` (excluding intentional `errNN_*`, `mistake_*`, and mutant negative-control files):** `5,457` files, `1,726,006` LOC.

### Audit Breakdown by Domain Category (SHA-256 Deduplicated)

| Category | Unique Files | Unique LOC | Clean Positive Files | Clean Positive LOC | Chain Link |
|---|---:|---:|---:|---:|---|
| `om-core` | 4,023 | 1,173,226 | 3,944 | 1,172,390 | Link 1: `om-core.sp` (`L8..9`) |
| `ollm` (CPU/native trainer) | 156 | 80,744 | 156 | 80,744 | Link 1: `om-core.sp` (`L8..9`) |
| `aienux-kernel` (Aienux/EFI/MMU/drivers) | 249 | 102,658 | 243 | 102,081 | Link 2: `aienux-kernel.sp` (`L10..11`) |
| `gb20b-mmio` (Blackwell/GPU/CUDApp/GSP/SEC2/MMIO) | 907 | 276,096 | 907 | 276,096 | Link 3A: `gb20b-mmio.sp` (`L12..13`) |
| `libos-rpc` (LibosLog/RPC/HTTP/JSON/wire/net) | 207 | 94,695 | 207 | 94,695 | Link 3B: `libos-rpc.sp` (`L12..13`) |
| **Total** | **5,542** | **1,727,419** | **5,457** | **1,726,006** | — |

### Chain-Organized Dataset Splits & `fcachem` Compatibility Check (Apple Silicon M2 CPU)

`tools/om_bundle_data.py build --max-examples 400 --verify-fcachem --include-err24` verified deterministic SHA-256 hash splitting (`int(sha256[:8], 16) % 10 == 0` -> held-out), zero hash overlap, BPE encoding via `ollm bpeenc` + `merges4096.bin`, chain topology metadata in `manifest.json`, and live `OLLMFH01` cache creation:

| Chain Link | Parent Prefix | Layers | Strand | Train Files | Held Files | Leakage | Train Wins (`T=256`) | Held Wins (`T=256`) | `ollm fcachem` Check |
|---|---|---|---|---:|---:|---:|---:|---:|---|
| `om-core` | `base` (`L0..7`) | `8->10` | `trunk` | 3,656 | 395 | 0 | 218 | 34 | `FCACHE 2 256 384 8` |
| `aienux-kernel` | `om-core` (`L0..9`) | `10->12` | `trunk` | 202 | 29 | 0 | 194 | 38 | `FCACHE 2 256 384 8` |
| `gb20b-mmio` | `aienux-kernel` (`L0..11`) | `12->14` | `branch-a` | 775 | 93 | 0 | 197 | 40 | `FCACHE 2 256 384 8` |
| `libos-rpc` | `aienux-kernel` (`L0..11`) | `12->14` | `branch-b` | 181 | 26 | 0 | 200 | 45 | `FCACHE 2 256 384 8` |

## 5. Measured Local `omc` Compile Latency (Apple Silicon M2 CPU)

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

## 6. Exact Commands

### A. Audit Corpus, Verify 30-Error Refusals, and Build Chain-Organized Datasets

```sh
# 1. Audit local .om corpus (total + SHA-256 deduplicated)
python3 tools/om_bundle_data.py audit --workspace "$HOME/workspace"

# 2. Generate and live-verify all 30 omc refusal-repair pairs (errors 1..30)
python3 tools/om_bundle_data.py refusals \
  --omc "$HOME/.local/bin/omc" \
  --include-err24 \
  --out "$OUT/refusals.jsonl"

# 3. Build deterministic, zero-leakage .tok + .msk chain splits and verify fcachem
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

### B. Train Vertical Merkle Chains on M2 CPU (`growpro` + `fcachem` + `trainfc` + `spext`)

Each link pins the frozen prefix beneath it via `OLLMSP01` `base_hash`:

```sh
OLLM="$HOME/.local/bin/ollm"
BASE_CK="$HOME/workspace/aien-train-macbook/local-mac/omega-v2.ck"
MERGES="$HOME/workspace/aien-train-macbook/local-mac/merges4096.bin"
DATA="$OUT/bundles"

# --- Link 1: base (L0..7) -> om-core.sp (L8..9) ---
"$OLLM" fcachem "$BASE_CK" "$DATA/om-core_aligned.tok" "$DATA/om-core_aligned.msk" 160 "$OUT/om-core.hc"
"$OLLM" growpro "$BASE_CK" "$OUT/prefix_l10.ck" 10 400 3500
"$OLLM" trainfc "$OUT/prefix_l10.ck" "$OUT/om-core.hc" 400 50 8 1
"$OLLM" spext   "$BASE_CK" "$OUT/prefix_l10.ck" "$OUT/om-core.sp"

# --- Link 2: prefix_l10 (L0..9) -> aienux-kernel.sp (L10..11) ---
"$OLLM" fcachem "$OUT/prefix_l10.ck" "$DATA/aienux-kernel_aligned.tok" "$DATA/aienux-kernel_aligned.msk" 160 "$OUT/aienux-kernel.hc"
"$OLLM" growpro "$OUT/prefix_l10.ck" "$OUT/prefix_l12.ck" 12 400 3500
"$OLLM" trainfc "$OUT/prefix_l12.ck" "$OUT/aienux-kernel.hc" 400 50 10 1
"$OLLM" spext   "$OUT/prefix_l10.ck" "$OUT/prefix_l12.ck" "$OUT/aienux-kernel.sp"

# --- Link 3A (Strand A): prefix_l12 (L0..11) -> gb20b-mmio.sp (L12..13) ---
"$OLLM" fcachem "$OUT/prefix_l12.ck" "$DATA/gb20b-mmio_aligned.tok" "$DATA/gb20b-mmio_aligned.msk" 160 "$OUT/gb20b-mmio.hc"
"$OLLM" growpro "$OUT/prefix_l12.ck" "$OUT/gb20b_l14.ck" 14 400 3500
"$OLLM" trainfc "$OUT/gb20b_l14.ck" "$OUT/gb20b-mmio.hc" 400 50 12 1
"$OLLM" spext   "$OUT/prefix_l12.ck" "$OUT/gb20b_l14.ck" "$OUT/gb20b-mmio.sp"

# --- Link 3B (Strand B, sibling): prefix_l12 (L0..11) -> libos-rpc.sp (L12..13) ---
"$OLLM" fcachem "$OUT/prefix_l12.ck" "$DATA/libos-rpc_aligned.tok" "$DATA/libos-rpc_aligned.msk" 160 "$OUT/libos-rpc.hc"
"$OLLM" growpro "$OUT/prefix_l12.ck" "$OUT/libos_l14.ck" 14 400 3500
"$OLLM" trainfc "$OUT/libos_l14.ck" "$OUT/libos-rpc.hc" 400 50 12 1
"$OLLM" spext   "$OUT/prefix_l12.ck" "$OUT/libos_l14.ck" "$OUT/libos-rpc.sp"
```

### C. Compose & Clip Chains (`spchain*`, `spclip` `S=2..4`, and Sticky-End Ligation — `NOT_RUN` on `.om` chains yet)

```sh
# Single-strand in-memory chain eval & sample (3 links: L0..7 -> L8..9 -> L10..11 -> L12..13)
"$OLLM" spchaineval "$BASE_CK" "$DATA/gb20b-mmio_held.tok" 20 "$MERGES" \
  3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/gb20b-mmio.sp"

"$OLLM" spchainsamp "$BASE_CK" 64 200 "fn gsp_submit " 42 "$MERGES" \
  3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/gb20b-mmio.sp"

# Double-Helix DNA clip (S=2, MODE=1 entropy-gated):
# Shared trunk (base -> om-core -> aienux-kernel) runs ONCE; gb20b-mmio + libos-rpc fuse in parallel:
"$OLLM" spclip "$BASE_CK" 1 "fn gsp_rpc_send " 64 200 42 "$MERGES" 2 \
  500 3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/gb20b-mmio.sp" \
  500 3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/libos-rpc.sp"

# Triple-Helix DNA clip (S=3, MODE=1 entropy-gated):
# Shared trunk (base -> om-core) runs ONCE; aienux-kernel + gb20b-mmio + libos-rpc fuse in parallel:
"$OLLM" spclip "$BASE_CK" 1 "fn aienux_gsp_rpc " 64 200 42 "$MERGES" 3 \
  334 2 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" \
  333 3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/gb20b-mmio.sp" \
  333 3 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp" "$OUT/libos-rpc.sp"

# Residual ligation + optional 1-layer sticky-end ligase bridge (L14 -> L15):
"$OLLM" spchainapp "$BASE_CK" "$OUT/prefix_l12.ck" 2 "$OUT/om-core.sp" "$OUT/aienux-kernel.sp"
"$OLLM" spstack "$OUT/prefix_l12.ck" "$OUT/gb20b-mmio.sp" "$OUT/libos-rpc.sp" 1000 1000 "$OUT/ligated_l16.sp"
```

### D. Run the Local `ollm spsamp` + `omc` Feedback Loop on M2 CPU

```sh
# 20-run omc latency benchmark
python3 tools/om_compile_loop.py bench --runs 20

# End-to-end self-test (deterministic refusal->repair + live spsamp->omc retry)
python3 tools/om_compile_loop.py selftest

# Single-prompt compile-retry loop with any trained pack
python3 tools/om_compile_loop.py loop \
  --pack "$OUT/om-core.sp" \
  --prompt "note return sum of two ulong values\nfn add2 a ulong b ulong to ulong\n" \
  --max-retries 3 \
  --tokens 64 \
  --temp-milli 200
```

### E. GB10 GPU Path (`NOT_RUN` — Frozen-Core GPU Training Not Yet Implemented)

> Do **not** execute any GPU command without an explicitly authorized DGX Spark `spark-window`.

- **Current state in `native/omegallm/gpu/gg.om`:** `gtrainf CK TRAIN UNTIL EVERY` (4 args) is **full-chip FP32 training** — it updates all layers including `0..7` (so `spext` against the original `BASE_CK` refuses with `rc=62`).
- **Frozen-core specialist training is currently CPU-only** (`trainf` / `fcachem` + `trainfc` in `native/omegallm/spec.om`, which runs on both Darwin arm64 and Linux AArch64 host CPUs).
- **Next engineering step for on-chip GB10 chain training:** add frozen-layer masking (`FREEZE_LAYERS` skip in backward/Adam, matching CPU `ofzlay`/`ofreeze`) to `gpu/gg.om` and qualify with an exact CPU-vs-GPU gate before training `.om` chain links on GB10. Meanwhile, packs trained via CPU `trainfc` + `spext` can be applied into a checkpoint (`spchainapp`) for on-chip GB10 evaluation/serving (`geval` / `gsample` / `gserve`) once authorized.
