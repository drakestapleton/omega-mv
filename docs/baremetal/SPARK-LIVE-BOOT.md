# DGX Spark Bare-Metal Live-Boot Operator Runbook (`SPARK.EFI`)

**Status:**
- **Host / QEMU / Staging Tooling:** `HOST_VERIFIED` (Phase 2 Slices A–F approved; staging scripts syntax + dry-run + refusal-tested).
- **Spark Silicon Live Boot:** `NOT_RUN` / `BLOCKED_HARDWARE` (requires an attended Window 0 with physical console + UART `0x16A00000` access).

> **Hard Safety Rules (Read Before Proceeding)**
> 1. **Never warm-reboot after `nvidia.ko` has been loaded.** GB20B GSP-FMC (`sec2.om`) requires a **full cold power-cycle** (`sudo poweroff` + AC disconnect for 10 s). Never issue a PCIe FLR on `000f:01:00.0`.
> 2. **Never modify `BootOrder` or `Boot0001` (`ubuntu`).** Stage only `\EFI\AIENOS\SPARK.EFI` via **one-shot `BootNext`**, so any power-cycle or PSCI `SYSTEM_RESET` (`0x84000009`) automatically returns to Ubuntu Linux.
> 3. **Zero NVMe writes & zero partition changes.** `nvme0n1p2` fills flush to the backup GPT (`8,001,573,518`). `SPARK.EFI` uses strictly read-only NVMe (`Admin 0x06/0x05/0x01`, `I/O Read 0x02` only) and read-only `ext4_ro.om` over `nvme0n1p2`.
> 4. **Zero firmware bytes in git or `HANDOFFS/`.** All `fwprep` / `pack_bundle` artifacts live in a local `0700` directory only.
> 5. **Thermal / Power Gate (Window 0).** DGX Spark hard-cuts power at ~88–92 W (`nvidia-gb10` Trap #14). Verify EC fan spin and GSP thermal/DPM telemetry in Window 0 before any sustained inference (never run with `CBKDPM=0`/`CBKPW2=0`).

---

## (a) Build `SPARK.EFI`

Build the unified bare-metal PE32+ ARM64 image (`target a64efi`, zero Linux syscalls, zero embedded firmware bytes, no 184 MiB static host-sim `.bss`):

```sh
sh aienux/spark/build_spark_efi.sh
```

Default output path: `build/spark/SPARK.EFI` (or `aienux/spark/out/SPARK.EFI`).
Verify PE32+ ARM64 header (`0xaa64`, PE32+ `0x020b`, EFI Application subsystem `10`, `SizeOfImage <= 64 MiB`) and record its SHA-256 via `preflight.sh` in step (c).

---

## (b) Pack `GspFwBundle` (`OMFWBND1`) Offline into a Local `0700` Path

Never commit `gsp_ga10x.bin`, extracted bindata blobs, or `spark-bundle.img` to git or `HANDOFFS/`.

### 1. Build `fwprep` and `pack_bundle` on Spark (AArch64 Linux)

```sh
# Build pure-Omega fwprep (OM-1)
cat gpu/driver/gsp/sha2.om gpu/driver/gsp/inflate.om \
    gpu/driver/gsp/fw.om gpu/driver/gsp/bindata.om \
    gpu/driver/fwprep.om | ./seed/out/omc > /tmp/fwprep
chmod +x /tmp/fwprep

# Build pure-Omega OMFWBND1 packer
cat aienux/disk/sha256_bare.om aienux/disk/pack_bundle.om | ./seed/out/omc > /tmp/pack_bundle
chmod +x /tmp/pack_bundle
```

### 2. Extract GB20B `580.173.02` Bindata & Pack `OMFWBND1` into a `0700` Directory

`gpu/driver/fwprep.om` writes the 5 GB20B bindata blobs (`bl.img` `212,992 B`, `fmc.img` `212,296 B`, `fmc.hash` `48 B`, `fmc.pubkey` `384 B`, `fmc.sig` `384 B`) plus the text manifest `fw.gb20b.manifest` (which records `bl_desc` fields including `app_version`). On Spark (`nvme0n1p2`), create a root/operator-only `0700` staging directory and pack `gsp_ga10x.bin` (`75,012,080 B`) + the 5 extracted binary blobs (and optional `fw.gb20b.manifest` as kind `7`):

```sh
FW_WORK="$HOME/.local/state/aienos-fw-580.173.02"
install -d -m 0700 "$FW_WORK"

# Extract the 5 GB20B bindata blobs + fw.gb20b.manifest from pinned open-gpu-kernel-modules-580.173.02
/tmp/fwprep \
  /lib/firmware/nvidia/580.173.02/gsp_ga10x.bin \
  "$OGKM_580_173_02_DIR" \
  "$FW_WORK" \
  gb20b

# Read app_version recorded by fwprep in fw.gb20b.manifest
APP_VER=$(awk '/^bl_desc / { for (i=1;i<=NF;i++) if ($i ~ /^app_version=/) { sub(/^app_version=/,"",$i); print $i; exit } }' "$FW_WORK/fw.gb20b.manifest")
echo "fwprep app_version=${APP_VER:?missing app_version in fw.gb20b.manifest}"

# Pack 4 KiB-aligned OMFWBND1 bundle with per-entry SHA-256 TOC
sudo install -d -m 0700 /aienos
/tmp/pack_bundle "$FW_WORK/spark-bundle.img" "$APP_VER" \
  1 /lib/firmware/nvidia/580.173.02/gsp_ga10x.bin \
  2 "$FW_WORK/bl.img" \
  3 "$FW_WORK/fmc.img" \
  4 "$FW_WORK/fmc.hash" \
  5 "$FW_WORK/fmc.pubkey" \
  6 "$FW_WORK/fmc.sig" \
  7 "$FW_WORK/fw.gb20b.manifest"

sudo install -m 0600 "$FW_WORK/spark-bundle.img" /aienos/spark-bundle.img
sha256sum /aienos/spark-bundle.img
rm -f /tmp/fwprep /tmp/pack_bundle
```

`ext4_ro.om` reads `/aienos/spark-bundle.img` directly from `nvme0n1p2` using read-only ext4 extent walks and verifies every entry's SHA-256 fail-closed before passing the bundle to `fw_bm.om`.

---

## (c) Run Strictly Read-Only Preflight (`preflight.sh --check-spark`)

`tools/spark-boot/preflight.sh` performs **zero writes** to disk, ESP, NVRAM, or `/dev/nvidia*`:

```sh
tools/spark-boot/preflight.sh --spark-efi build/spark/SPARK.EFI --check-spark
```

What it verifies:
1. Local `SPARK.EFI`: valid PE32+ ARM64 (`0xaa64`, `0x020b`, EFI Application `10`, `SizeOfImage <= 64 MiB`), prints size + SHA-256.
2. Pi 5 `pi_drive_omtk`: verifies existing AArch64 ELF64 binary (or compile-checks `aienux/net/wire/omtk.om` + `tools/pi-drive-27b/pi_drive_omtk.om` in an ephemeral temp dir; pass `--build-pi-drive` to emit `build/spark/pi_drive_omtk`).
3. Spark UEFI NVRAM: `Boot0001` (`ubuntu`, `\EFI\ubuntu\shimaa64.efi`) intact and `BootOrder` starts with `0001`.
4. Spark ESP (`/boot/efi`): free space `>= 64 MiB` and `/boot/efi/EFI/ubuntu/shimaa64.efi` present.
5. Spark `nvme0n1p2` ext4: `4096 B` blocks, `extent` enabled, and **none** of `ext4_ro.om`'s unsupported incompat features (`compression`, `meta_bg`, `inline_data`, `encrypt`).
6. Spark firmware & weights: `/lib/firmware/nvidia/580.173.02/gsp_ga10x.bin` (`75,012,080 B`) and `~/models/specialist-transfer/qwen3.8-27b-fp8-*` (`~28.77 GiB`).
7. Spark RTL8127 NIC: `0007:01:00.0` (`r8127`, e.g. `enP7s7` `UP`, IPv4 `192.168.1.108/24`).
8. Read-only `/dev/nvidia*` idle check (via `/proc/[0-9]*/fd/*` symlinks — never opens `/dev/nvidia*`).

Do not proceed until `VERDICT: PASS`.

---

## (d) Stage `\EFI\AIENOS\SPARK.EFI` + One-Shot `BootNext`

`tools/spark-boot/stage_bootnext.sh` is **dry-run by default** and refuses to modify anything unless **both** `--apply` and `--i-am-at-the-console` are explicitly passed.

### 1. Dry-run first (zero changes)

```sh
tools/spark-boot/stage_bootnext.sh --spark-efi build/spark/SPARK.EFI --dry-run
```

### 2. Apply staging (at physical Spark console + UART)

```sh
tools/spark-boot/stage_bootnext.sh \
  --spark-efi build/spark/SPARK.EFI \
  --apply \
  --i-am-at-the-console
```

Safety checks enforced automatically:
- Re-validates local `SPARK.EFI` PE32+ ARM64 header & SHA-256.
- Refuses if any process holds `/dev/nvidia*` open (override only with `--force-while-gpu-busy`).
- Copies atomically to `/boot/efi/EFI/AIENOS/SPARK.EFI` and verifies remote SHA-256 (Ubuntu's `\EFI\ubuntu\shimaa64.efi` and GRUB are never touched).
- Creates/reuses the UEFI entry for `\EFI\AIENOS\SPARK.EFI` via `efibootmgr --create-only` (leaving `BootOrder` untouched) and sets **one-shot `BootNext` ONLY**.
- Re-reads `efibootmgr -v` and verifies `BootOrder` and `Boot0001` are byte-identical to pre-staging (automatically restores `BootOrder` and clears `BootNext` if any discrepancy is detected).
- **Never reboots automatically.**

---

## (e) Cold Power-Cycle (NEVER Warm-Reboot After `nvidia.ko`)

> **CRITICAL:** Do **NOT** run `sudo reboot` after Linux `nvidia.ko` has been loaded. GB20B's SEC2/GSP-FMC cold-boot path requires clean silicon power-on reset; warm-booting after `nvidia.ko` leaves GPU/GSP state dirty and can hang or fault GSP init.

1. Attach the serial console to Spark UART `0x16A00000` (`115200 8N1`).
2. Cleanly shut down Ubuntu:
   ```sh
   ssh spark 'sudo poweroff'
   ```
3. Wait until the power LED is completely off, **disconnect AC power for 10 seconds**, then reconnect AC and power Spark back on.
4. UEFI consumes the one-shot `BootNext` and launches `\EFI\AIENOS\SPARK.EFI`.

---

## (f) UART `0x16A00000` Expected Boot Log & Window 0 Thermal Check

Watch the `0x16A00000` serial log for the six sequential stage markers:

| Stage | Expected UART Marker & Key Milestones |
|---|---|
| **1/6** | `[SPARK 1/6]` — `ExitBootServices`, ACPI (XSDT/MADT/FADT/MCFG/IORT), EL2→EL1h (`HCR_EL2.E2H=0` + `ISB`, `CNTVOFF_EL2=0`), `MAIR=0x440004FF` + pre-carved 512 MiB Normal-NC DMA pool, GICv3 + ITS (`GICV3_OK`, `ITS_OK`), 20-core PSCI SMP (`SMP_ONLINE 20/20`). |
| **2/6** | `[SPARK 2/6]` — PCIe MCFG segs 4/7/15 probe (`Device-nGnRnE` XN), unused PCIe `CMD.BME=0` quiesce, SMMUv3 A/B/C fail-closed (`GBPA.ABORT`, per-stream disjoint Normal-NC DMA: SID `0x50100` NVMe, `0x80100` RTL8127, `0x100` GB20B + 3 mandatory RMRs; SMMUv3 C aborted), GB20B BAR0 (`0x24000000`) `BOOT_0`/`BOOT_42` probe, `iqmode=2` polling + CrashCat armed. |
| **3/6** | `[SPARK 3/6]` — Read-only NVMe (`0x62100000`, `MDTS <= 128 KiB`, `I/O Read 0x02` only) + GPT + `ext4_ro.om` load & SHA-256 verification of `/aienos/spark-bundle.img` (`OMFWBND1`) and `qwen3.8-27b-fp8` weights; RTL8127 (`0x6e900000`) `PHYSTAT` link-up check. |
| **4/6** | `[SPARK 4/6]` — Cold-boot GB20B GSP-FMC (`sec2.om` + `seqcore.om` opcodes `5..8` + `sccfg`) → `GSP_INIT_DONE` → `RPC 54/79` (`SET_PAGE_DIRECTORY`) → live `0xca6f`/`0xcec0` compute channel + bit-30 doorbell `0x00BB0090` + 2 MiB GMMU mappings (disjoint GPU VA map: LPDDR5x `0x00_8000_0000..0x3F_FFFF_FFFF`, shared `0x70_0000_0000`, local `0x72_0000_0000`). |
| **5/6** | `[SPARK 5/6]` — Pure-`.om` `sm_121` SASS codegen + `DC CIVAC` + `DSB SY` + `q38_run.om` init + `q38_reset_kv(0)` GPU-side zero + L2 flush. |
| **6/6** | `[SPARK 6/6]` — Zero-userspace `wire_loop.om` (`OMTK v1`) listening on RTL8127 TCP port `18100`. |

**Fail-Closed Post-EBS Behavior:** If any hardware probe, SHA-256 check, SMMU `CMD_SYNC`, GSP timeout, or CrashCat HALT triggers after `ExitBootServices()`, the `post_ebs` trap guard logs the exact stage, error code, and `ESR`/`ELR`/`FAR` to UART `0x16A00000` and halts (or invokes PSCI `SYSTEM_RESET`) without ever calling dead UEFI Boot Services.

### Window 0 EC Fan & Thermal Gate (Mandatory Before Sustained Inference)
- Immediately after `[SPARK 4/6]` (`GSP_INIT_DONE`), verify audible/tachometer **EC fan spin** and confirm GSP thermal/DPM telemetry is active (no `CBKDPM=0`/`CBKPW2=0` override).
- Run a single `ping` + `reset 0` + 1-token `infer` first while watching package power and exhaust temperature. If fan speed fails to ramp or thermal telemetry is absent, **abort immediately** (power-cycle back to Ubuntu) to avoid the ~88–92 W hard power cut.

---

## (g) Drive Inference from Raspberry Pi 5 (`pi_drive_omtk`)

### 1. Build `pi_drive_omtk` on Raspberry Pi 5 (AArch64 Linux, zero C/Python/JSON)

```sh
{ printf 'om2\n'; cat aienux/net/wire/omtk.om tools/pi-drive-27b/pi_drive_omtk.om; } | ./seed/out/omc > pi_drive_omtk
chmod +x pi_drive_omtk
```

*(Alternatively, run `tools/spark-boot/preflight.sh --build-pi-drive` on an AArch64 host and `scp build/spark/pi_drive_omtk` to the Pi 5.)*

### 2. Exercise `OMTK v1` over RTL8127 (`192.168.1.108:18100`)

```sh
SPARK_IP=192.168.1.108
SPARK_PORT=18100

# 1. Health & state probe (expects: PONG state=... kv=0 max_ctx=131072 gpu_err=0)
./pi_drive_omtk "$SPARK_IP" "$SPARK_PORT" ping

# 2. Reset KV cache / GDN state (keep_pos=0; triggers GPU zero + L2 flush)
./pi_drive_omtk "$SPARK_IP" "$SPARK_PORT" reset 0

# 3. Run token-ID prefill + greedy decode:
#    infer <max_tokens> <eos_id> <tok0> [tok1 ...]
./pi_drive_omtk "$SPARK_IP" "$SPARK_PORT" infer 32 151645 9707 11 1265
```

Expected output lines:
- `PONG state=0 kv=0 max_ctx=131072 gpu_err=0`
- `DONE kv=0 reason=4` (after `reset 0`)
- `TOKEN <id>` per generated token, ending with `DONE kv=<pos> reason=<0|1|2>` (or `ERR code=<code> detail=<n>` on any fail-closed refusal).

---

## (h) Instant Ubuntu Fallback & Cleanup

Because `stage_bootnext.sh` sets **one-shot `BootNext` only** and leaves `BootOrder` (`0001,...`) and `Boot0001` (`ubuntu`) untouched:

- **Immediate return to Ubuntu:** Press the power button / cold power-cycle (or let `SPARK.EFI` invoke PSCI `SYSTEM_RESET`). UEFI automatically boots `Boot0001` (`ubuntu`, `\EFI\ubuntu\shimaa64.efi`).
- **Cancel a pending `BootNext` before powering off:**
  ```sh
  ssh spark 'sudo efibootmgr -N'
  ```
- **Optional full cleanup after testing (once back in Ubuntu):**
  ```sh
  ssh spark '
    sudo efibootmgr -N || true
    sudo rm -f /boot/efi/EFI/AIENOS/SPARK.EFI
    # Optional: remove the BootXXXX entry for \EFI\AIENOS\SPARK.EFI (never touch Boot0001!)
    BOOTNUM=$(efibootmgr -v | awk "/^Boot[0-9A-Fa-f]{4}/ && index(\$0, \"\\\\EFI\\\\AIENOS\\\\SPARK.EFI\")>0 {print substr(\$1,5,4); exit}")
    [ -n "$BOOTNUM" ] && [ "$BOOTNUM" != "0001" ] && sudo efibootmgr -b "$BOOTNUM" -B
    efibootmgr -v
  '
  ```

---

## Post-Boot Optimization Plan (Phase 4 — Strictly After Window 0 First-Boot & Token Parity)

Do **not** mix these optimizations into Window 0 bring-up. Land and benchmark them only after bare-metal first-boot, EC fan/thermal verification, and bit-exact Qwen3.8-27B token parity pass:

1. **Projection Overlap & Barrier Tuning (`gpu/driver/gsp/q38_run.om`):**
   - Port `OVERLAP_AB` (overlap independent projections) and configurable barrier modes (`WFI` vs `WFI+CBICALL`) in `q38_run.om`.
   - Measure per-stage latency directly via GPU `PTIMER` stamps.
2. **GPU-Side Embedding Gather & Multi-Token Pushbuffer Batching (`N=4..8`):**
   - Move embedding gather onto the GPU and batch `N=4..8` greedy `OMTK v1` decode tokens per pushbuffer submission to eliminate per-token C3 `L2_FLUSH_DIRTY` + semaphore host round-trips, while preserving prompt `EOS` and `CANCEL` responsiveness.
3. **Long-Context `attn256` Optimization (`32k–128k`):**
   - Optimize long-context KV scan / reduction paths in `cg_attn256.om` across `32k–128k` contexts.
4. **Explicit Skips (Do Not Implement for Dense 27B):**
   - **Weight L2 caching:** thrashes GB10's 24 MiB L2 cache on 27B streaming weights.
   - **`o_proj` prefetch:** 30B-only optimization; skip for 27B.
   - **Range-syncing:** already reduced to a single `dsb sy` no-op on bare-metal ARM64.
   - **`AIEN_OMEGA_FP8_GROUPED_WAVE=1`:** 35B MoE grouped-expert path only; not applicable to dense Qwen3.8-27B.
