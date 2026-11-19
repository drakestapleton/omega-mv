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
