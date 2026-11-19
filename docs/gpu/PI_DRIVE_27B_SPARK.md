# Driving Qwen3.8-27B-FP8 on DGX Spark GB10 from Raspberry Pi 5 (Pure Seeded Omega)

**Date:** 2026-11-19
**Status:** `PASS` (live end-to-end Pi → Spark 27B inference over encrypted SSH loopback tunnel + AArch64 `seed/out/omc` GB20B host test suite on Pi).
**Scope boundary (honesty check):** Today's live 27B run still uses Linux + `aien-serve-http` (`omega-qwen38` engine) on Spark, offloading all driving/client/compiler userspace to the Raspberry Pi 5 so Spark dedicates its unified memory to the 27B model. Bare-metal Aienux with zero Linux userspace on Spark remains `NOT_RUN` until the Aienux UEFI/PCIe/GB20B/SASS stack completes bring-up.

---

## 1. Live Measured Run: Pi 5 Pure-Omega Client → Spark GB10 27B

### Client (Raspberry Pi 5 `hub`, `aarch64 GNU/Linux`)
- **Source:** `seed/net/http.om` + `seed/net/notls.om` + `tools/pi-drive-27b/pi_drive.om`
- **Build command (native on Pi AArch64, zero C / Python / curl / libc):**
  ```bash
  { printf 'om2\n'; cat seed/net/http.om seed/net/notls.om tools/pi-drive-27b/pi_drive.om; } | ./seed/out/omc > pi_drive
  chmod +x pi_drive
  ```
- **Binary:** `68 KB` static AArch64 ELF (`ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked`)
- **Measured Pi footprint (`/usr/bin/time -v ~/pi-drive-27b/pi_drive < /dev/null`):**
  - **Max RSS:** `400 KB` (`0.4 MB`)
  - **CPU time:** `0.00 s` user / `0.00 s` system (`0%` CPU)
  - **End-to-end wall clock (`/health` + `/v1/chat/completions`):** `5.06 s`
  - **Exit status:** `0`

### Server (DGX Spark GB10, `121 GiB` unified LPDDR5x)
- **Binary:** `~/.local/state/aien-q36/bin-cc45f45e/aien-serve-http` (`SHA256SUMS` verified `OK`)
- **Model:** `~/models/specialist-transfer/qwen3.8-27b-fp8-017b9c7a` (`64` layers, `omega-qwen38` engine)
- **Launcher:** `tools/pi-drive-27b/run-spark-27b.sh` (loopback-only `127.0.0.1:18099`, `--max-context 131072`, `--max-tokens-cap 16384`, `--thinking off`, `CLAIM`/`RELEASE` on `BOARD.md`, guaranteed `EXIT` trap shutdown)
- **Measured Spark load & memory:**
  - **Engine load time:** `50.9 s` (`READY` in `49 s`)
  - **Context window:** `131,072` tokens (engine `attn256` ceiling)
  - **Weights resident:** `26.92 GB` | **KV cache:** `8.59 GB` | **Server RSS:** `38.55 GB` (`37,649,508 KiB`)
  - **Spark `MemAvailable` before load:** `109,923 MiB` (`107 GiB`)
  - **Spark `MemAvailable` with 27B + 128k KV loaded:** `71 GiB` free
- **Measured inference output:**
  - `/health`: `{"busy":false,"engine":"omega-qwen38","model":"qwen3.8-27b-fp8","status":"ok","uptime_s":11}`
  - Completion ID: `chatcmpl-18e97c6dcb707cbf0000` (`40` prompt tokens, `36` completion tokens, `76` total tokens, `finish_reason: "stop"`)
- **Post-run cleanup:** `aien-serve-http` stopped cleanly; `spark-window status` = `no window open`, `gb10 lock holders:` empty, `nvidia-smi` = 0 compute processes.

---

## 2. Pure-Omega GB20B Host Tests Verified on Pi AArch64 (`seed/out/omc`)

Compiled and executed natively on `hub` (`Linux hub 7.0.0-1023-raspi aarch64 GNU/Linux`) with pinned `seed/out/omc`:

| Suite | Verdict | Output |
|---|---|---|
| `logdec_trace` (`logdec.om` + `logdec_trace.om`) | **`PASS`** (`rc=0`) | `LOGDEC TEST PASS 12/12` |
| `bootfs_trace` (`bootfs.om` + `bootfs_trace.om`) | **`PASS`** (`rc=0`) | `BOOTFS TEST PASS 9/9` |
| `irqcc_trace` (`logdec.om` + `irqsim.om` + `irq.om` + `irqcc.om` + `irqcc_trace.om`) | **`PASS`** (`rc=0`) | `IRQCC TEST PASS 6/6` |
| `compute_trace` (13-unit GB20B compute bring-up stack) | **`PASS`** (`rc=0`) | `PASS compute_trace` |
| `chan_trace` (`dma/gmmu/mem/chan/sim` + `chan_trace.om`) | **`PASS`** (`rc=0`) | `rc=0` |

### OM-1 `omc` Fixes Applied During Native AArch64 Verification
- `gpu/driver/gsp/arena.om`: split compound `or` in Profile 2 size check (`arbuild`) to stay within OM-1's 16-register pool (`error 12`).
- `gpu/driver/gsp/logdec.om`: cast `uchar` to `ulong` and split `kind`/`loc` check in `lgtabparse` (`error 12`).
- `gpu/driver/gsp/compute.om`: split `get cbrblob` temp before `put rqpay` (`error 12`).
- `gpu/driver/tests/bootfs_trace.om` & `gpu/driver/tests/logdec_trace.om`: typed bare arithmetic literals with `ulong` (`error 11`).

---

## 3. Back-to-Back 3-Way Live Stress Benchmark (2026-11-19)

All three trials ran back-to-back on the exact same DGX Spark GB10 (`580.173.02`), same model (`qwen3.8-27b-fp8-017b9c7a`), and byte-identical `.om` codebase prompts (`pi_drive.om` bumped to `512 KiB` request buffer, still `68 KB` static ELF).

| Metric / Stage | Trial 1: Pi 5 (68 KB `.om`) → Spark Omega | Trial 2: Spark-Local → Spark Omega | Trial 3: CUDA + PyTorch (`torch 2.14.0+cu130`, `transformers 5.17.0`) |
|---|---:|---:|---:|
| **Model Load Time** | **`51.4 s`** (`READY 47 s`) | **`47 s`** | **`171.8 s`** (3.5× slower) |
| **Memory at Load** | `38.55 GB` RSS (incl. 128k KV; `71 GiB` free) | `38.55 GB` RSS (incl. 128k KV) | `29.47 GB` CUDA + `0.69 GiB` RSS (0 KV allocated) |
| **Client Footprint** | **`68 KB` ELF, `512–640 KB` RSS, `0.00 s` CPU** | Local Python process | Python + PyTorch + HF venv |
| **S1 (`45` in / `37` out)** | **`5.22 s`** (`8.05 tok/s` decode) | **`5.21 s`** (`8.04 tok/s` decode) | **CRASH** (`ImportError: finegrained-fp8 kernel unavailable`, 0 tok) |
| **S2 (`3,264` in / `128` out)** | **`31.99 s`** (`7.88 tok/s` decode) | **`31.54 s`** (`7.89 tok/s` decode) | Not reached (crashed on S1) |
| **S3 (`13,127` in / `64` out)** | **`72.72 s`** (`7.36 tok/s` decode) | **`72.36 s`** (`7.39 tok/s` decode) | Not reached |
| **S4 (`39,820` in / `32` out)** | **`215.68 s`** (`6.40 tok/s` decode) | **`214.43 s`** (`6.42 tok/s` decode) | Not reached |
| **S5 (~99K tok / 240 KB JSON)** | Hit `420 s` client timeout in prefill (no OOM/crash; `68 GiB` free) | — | — |

### Live GB10 Telemetry During Trial 1 (364 samples @ 2 s)
- **GPU Utilization:** max `96%`, active average `64.6%` (`362/364` active samples)
- **SM Clock:** `208 MHz` idle → **`2,502 MHz`** peak
- **Temperature:** `41°C` idle → **`74°C`** peak
- **Power Draw:** `4.73 W` idle → **`48.81 W`** peak
- **Spark `MemAvailable` after 40K+ token stress:** **`68 GiB`** still free (zero swap, zero OOM)
- **Pi 5 remote overhead vs. Spark-local:** **< 1%** (`+0.01 s` at 45 tok; `+1.25 s` / `+0.6%` at 40K tok).

---

## 4. Spark CPU + GPU Co-Execution: Live Benchmark & Pure-Omega Modules (2026-11-19)

### Live Spark Overlap & Warm-Prefix Reuse Benchmark (`bin-cc45f45e`)
Tested `AIEN_OMEGA_Q38_OVERLAP_AB=1`, `AIEN_OMEGA_Q38_BUF_CACHED=1`, `AIEN_OMEGA_GDN_STATE_CACHED=1`, `AIEN_OMEGA_DGRAPH_PREFETCH=1`, `--prefill-device-host on`:
- **Warm-prefix reuse (`S2_warm_3k`, `reuse Live(3392)`, 30 new tok):** prefill dropped from **`15,477 ms` → `502 ms` (`30.8× faster`)**, total wall `3.47 s`, decode `7.77 tok/s`.
- **Env overlap flags vs default:** cold prefill and decode were within ~1% of default (`7.95` vs `8.04 tok/s`, `15.48 s` vs `15.31 s` at 3.2K, `63.19 s` vs `63.69 s` at 13K), confirming `bin-cc45f45e` defaults are already optimal and that the largest CPU+GPU wins come from **prefix-pool reuse**, **L2-resident CPU speculative drafting**, and **mid-decode OM-1 grammar guarding**.

### Pure-Omega CPU Co-Execution Modules (Verified Live on Pi ARM64 `seed/out/omc`)
| Module | Size / Footprint | Live AArch64 Verdict | Purpose on Grace ARM64 Cores |
|---|---|---|---|
| `tools/pi-drive-27b/specdraft.om` + `specdraft_trace.om` | `12 KB` ELF, `400 KB` RSS, `0.00 s` | **`PASS`** (`SPECDRAFT TEST PASS 8/8`, `rc=0`) | L2-resident (`64.17 KiB` state, 0 DRAM contention) 4/3/2/1-gram prompt-lookup speculative drafter + exact verification/rollback (`1..8` tokens/step) |
| `tools/pi-drive-27b/omguard.om` + `omguard_trace.om` | `20 KB` ELF, `400 KB` RSS, `0.00 s` | **`PASS`** (`OMGUARD TEST PASS 8/8`, `rc=0`) | Incremental mid-decode OM-1 syntax/register guard (`0x`, `>6` params, `>16` locals / `error 12`, missing `bound`, unbalanced `end`) + 64-slot FNV-1a unified-RAM prefix-pool index with LRU eviction |


