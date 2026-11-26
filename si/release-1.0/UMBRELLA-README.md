# Sovereign Intelligence 1.0

> **Sovereign, not super:** intelligence you own, run on hardware you own, and can check yourself.

---

## Why Omega NG Exists: Never Take an Agent's Word for It

We get it — canonical prefix Omega isn't easy for humans to read. You shouldn't have to take an agent's word for what it wrote. **Omega NG** gives humans a clean, readable, Lean 4–verified infix language attached directly to canonical Omega **bit for bit** — identical ΩIR, identical `SEMANTIC_ID`, and identical verified binary output, down to the last instruction byte.

---

## The Sovereign Intelligent Agent Manifesto

- **Individual, never collective:** A Sovereign Intelligent Agent is not "AI," not a "bot," and not a collective mind. It is a **verifiable, bit-for-bit, locally controlled, human-owned tool** on a **solo, individual level** — not conscious itself, but an **extension of an individual human's consciousness and humanity**, just as cars, phones, and houses become extensions of the person who owns them.
- **Individual consciousness, open interconnection:** There is no collective "human consciousness" — only **individual consciousness**: each person's own unique, individually crafted consciousness, interconnected with others through communication, interaction, daily life, and now the internet. **AienOS / Sovereign Intelligence** is the local, bit-for-bit verifiable extension of the **individual**; **Interplane** is the open, verifiable **interconnection** between sovereign individuals — never a centralized collective.
- **No two Sovereign Intelligent Agents are alike:** Because every Sovereign Intelligent Agent extends a unique human, no two are the same. **That is why Omega Helix exists** — your own DNA, from your own scratch. Everyone trains their own agent (`OLLMSP01` specialist strands, `spclip` DNA editing, local Studio) from the scratch they choose — shaped by who they are, what they need, and who they want to be.
- **Absolute individual autonomy:** Complete individual choice over morals, values, and how your agent thinks. Zero outside authority, platform, or third party can ever override or decide that for an individual human.
- **Human computing heritage:** Sovereign Intelligence honors the decade-by-decade craft from von Neumann and bare machine code through the pioneers of Unix, C, and compilers — keeping humans firmly at the center of computing culture, never relegated to spectators of black-box services.

---

## Architecture at a Glance

Sovereign Intelligence 1.0 is grown deterministically from a **408-byte hand-written seed** (`seed0 -> hex1 -> asm2 -> om4 -> omc`). Every forward component compiles with pinned `seed/out/omc`, runs offline with zero telemetry, and ships reproducible verification gates rather than marketing claims.

```text
  408-byte seed0.hex ──► hex1 ──► asm2 ──► om4 ──► seed/out/omc (2x bit-identical fixpoint)
                                                        │
      ┌─────────────────────┬───────────────────────────┼──────────────────────────┐
      ▼                     ▼                           ▼                          ▼
  Core Language       FFI & Serving               GPU & Evolution            Bare-Metal OS
  ─────────────       ─────────────               ───────────────            ─────────────
  • OM-1.0 & Omega NG • ABI v2 (omega2_*)         • Pure-Omega SM121 SASS    • Aienux SPARK.EFI
  • RM2 contracts     • C/C++/Rust/Zig/Py/Go      • Zero-CUDA Blackwell QMD  • target a64efi PE32+
  • RM4 runtime pools • FR-7 shlib.om + dlvsym    • Helix BFT / MonkCheck    • 20-core SMP + SMMUv3
  • RM6 modlink DAG   • om-route (OpenAI+Claude)  • OLLMSP01 DNA + spclip    • RO NVMe + RTL8127
```

- **Pure Omega forward path:** Zero C/Python on forward production paths, zero third-party GPU toolkits, zero analytics or phone-home traffic.
- **Zero signing-fee gatekeepers:** macOS installs via Homebrew or SHA-256-verified Terminal quarantine-clear + ad-hoc `codesign`; Windows runs static `x86linux` ELF inside WSL 2 (or the in-browser zero-JS online compiler).

> **Release status (honest):** **Big-Bang 1.0 HOLD.** `si/release-1.0/si_release_gate.om` refuses to stamp `1.0-READY` (`REFUSED 1.0-HOLD`) until all 10 repositories in `si/release-1.0/MANIFEST-1.0.tsv` carry matching 40-hex commit SHAs, unified `omc` SHA-256 pins, zero unwaived blockers, and the attended physical DGX Spark boot ceremony (`DRA-938`) is recorded under `evidence/`.

---

## Omega 1.0 Milestone Readiness Matrix (RM1–RM11 & Platform Layers)

Every row carries an explicit, honest evidence class (`HOST_VERIFIED`, `EXERCISED_EMULATED`, `HOST_THERMAL_LIVE`, `PHYSICAL_SILICON=NOT_RUN`, `BLOCKED_OPERATOR`). Host and QEMU passes are **never** reported as physical silicon qualification.

| Milestone / Layer | Owner Path | Evidence Class | Status & Honest Scope |
|---|---|---|---|
| **RM1** Ground truth & gate coverage | `seed/qualification/om2/`, `tests/gates/` | `HOST_VERIFIED` / `BLOCKED_OPERATOR` | OM-2 spec, fixtures, mutants & `#775` closed on host; wiring new gates into `tests/gates/` requires Spark operator run. |
| **RM2** Executable contracts | `seed/omc/omc.om`, `docs/one_layer/OMEGESE.md` §12 | `HOST_VERIFIED` | Native `requires` (trap `9`), `ensures` & `invariant` (trap `10`), `om2 release` erasure, constant-true proofs, error `30`. |
| **RM3** Measured efficiency | `bench/omc_efficiency/`, `seed/helix/` | `HOST_VERIFIED` / `PHYSICAL_SILICON=NOT_RUN` | Paired host efficiency baselines & Antibody `#17a–#17d` SM121 scheduling verified on host; exclusive GB10 silicon timing window pending. |
| **RM4** Memory model (Runtime pools) | `docs/RUNTIME-POOLS.md`, `seed/omc/gate-pools.sh` | `HOST_VERIFIED` | Decision 24 kept (no `free`); explicit `global T *`, `enlarge`, `len` with checked bounds and overflow refusal. |
| **RM5** Strings & text | `seed/text/` | `HOST_VERIFIED` | Pure-Omega compare, search, split, decimal/hex integer parse/format, and strict UTF-8 validation. |
| **RM6** Modules & separate compilation | `seed/modules/rm6/modlink.om` | `HOST_VERIFIED` | Digest-addressed module linker (`gate_rm6` 12/12 tests, 7/7 controls, 3/3 mutants caught, bit-identical to single-unit builds). |
| **RM7** `omega-bridge` ABI v2 FFI | `bridge/abi-v2-spec/` | `HOST_VERIFIED` | Normative `ABI-V2-SPEC.md`; all 6 languages (C, C++, Rust `#![forbid(unsafe_code)]`, Zig, Python, Go) + C-BTI; statuses `0`, `1..14`, `32`, live `SIGUSR1` `33`; FR-7 `shlib.om` `ET_DYN` + `OMEGA_ABI_2.0` `dlvsym`. |
| **RM8** Diagnostics & error codes | `seed/omc/error-codes.reg`, `seed/omc/sites/` | `HOST_VERIFIED` | Complete code registry (`1..30`), site coverage floor enforcement, and structured `OMC_DIAG=1` wave. |
| **RM9** Targets | `seed/omc/`, `seed/wasm/`, `seed/spirv/`, `seed/stablehlo/`, `tests/a64efi/` | `HOST_VERIFIED` / `EXERCISED_EMULATED` / `PHYSICAL_SILICON=NOT_RUN` | Linux AArch64/x86_64/Wasm/SPIR-V/StableHLO exercised on host; `target a64efi` passes 35/35 under QEMU/EDK2 (`file11` `x86efi`-only `NOT_RUN`); physical GB10 chip gate `BLOCKED_OPERATOR`. |
| **RM10** Compiler trust & DDC | `seed/ddc/`, `seed/omega-from-seed.sh` | `HOST_VERIFIED` | 3-path Diverse Double Compilation (`om4`/`ng_a64`/`ng_opt_split`) converges bit-identically on `seed/out/omc` + live Trusting-Trust trojan caught. |
| **RM11** Stability guarantee | `docs/OM-1.0-PROFILE.md`, `seed/conformance/` | `HOST_VERIFIED` | Frozen `OM-1.0` profile with explicit C1/C2/C3/C4 compatibility promise and automated 1.x conformance gate. |
| **Local Serving & Thermal Router** | `apps/om-route/` | `HOST_THERMAL_LIVE` | Pure OM-2 dual OpenAI (`/v1/chat/completions`) + Anthropic (`/v1/messages`) router with live DGX Spark thermal admission (`gate_om_route` 10/10 checks, 6/6 controls). |
| **Bare-Metal Aienux (`SPARK.EFI`)** | `aienux/spark/`, `si/release-1.0/aienux_boot_audit.md` | `EXERCISED_EMULATED` / `PHYSICAL_SILICON=NOT_RUN` | 20-core QEMU/EDK2 E2E (`SMP_ONLINE 20/20`, SMMUv3 mode-1, RO NVMe+GPT+ext4+`OMFWBND1` SHA-256 + negative controls) PASS; physical Spark cold-boot (`DRA-938`) awaits Drake at console. |

---

## Standalone Community Repositories

Exported deterministically with SHA-256 provenance (`UPSTREAM_PIN.tsv`) and the 60-Second Omega Rosetta Card by `si/release-1.0/export_standalone.om` from `si/release-1.0/STANDALONE-REPOS.tsv`:

| Repository | Canonical `omega-mv` Source | Layout Mode | Entry Point | Purpose |
|---|---|---|---|---|
| `omega-gpu-driver` | `gpu/driver` | `pure-om` | `gpu/driver/ogd.om` | Zero-CUDA pure-Omega Blackwell GB10/GB20B GSP and compute channel driver |
| `omega-sm121-sass` | `om/gpu`, `seed/sm121` | `pure-om` | `om/gpu/bw_qmd.om` | Pure-Omega SM121 Blackwell SASS codegen, QMD packer, register allocator, and scheduler |
| `omega-ng-egraph` | `seed/ng` | `pure-om` | `seed/ng/src/main.om` | Pure-Omega NG compiler, Omega-IR equality-saturation e-graph optimizer, and EGP3 checker |
| `omega-wattd` | `apps/omega-wattd` | `pure-om-optional` | `apps/omega-wattd/wattd_main.om` | Pure-Omega thermal and power control barrier daemon (WattCBF) for DGX Spark |
| `rtl8127-omega` | `aienux/net/rtl8127` | `pure-om` | `aienux/net/rtl8127/om/rtl8127/rtl8127.om` | Pure-Omega bare-metal Realtek RTL8127 10GbE NIC driver and OMTK wire transport |
| `tensorfold-omega` | `bridge/omega-bridge/src` | `zig-abi-v2-optional` | `bridge/omega-bridge/src/native.om` | Optional Zig ABI v2 (`omega2_*`) plugin layout bridging pure-Omega kernels into TensorFold |

For sharing and exchanging custom `OLLMSP01` Helix specialist strands between sovereign individuals, see the **Interplane Helix Chain Hub** (`https://interplane.io/omega/helix/#chain-hub`).

---

## Quickstart by Platform

Never pipe remote scripts directly into a shell. Always verify `SHA256SUMS.txt` fail-closed before installing or executing any binary.

### 1. Linux AArch64 & DGX Spark GB10 (Primary)
```sh
# Bootstrap the compiler from the 408-byte seed (zero C on this path)
sh seed/omega-from-seed.sh
sha256sum -c seed/out/omc.sha256

# Preview topology & profile plan without modifying the filesystem
sh si/release-1.0/install-si-1.0.sh --profile full --dry-run

# Verify a downloaded release bundle fail-closed before installing
sh si/release-1.0/install-si-1.0.sh --verify-bundle ./si-1.0-bundle --install --prefix "$HOME/.local"
```

### 2. Linux x86_64
```sh
sh si/release-1.0/install-si-1.0.sh --profile core --dry-run
sh si/release-1.0/install-si-1.0.sh --verify-bundle ./si-1.0-x86linux-bundle --install --prefix "$HOME/.local"
```

### 3. macOS Apple Silicon (`arm64`)
Lead with Homebrew (zero notarization gatekeeping):
```sh
brew tap drakestapleton/omega https://interplane.io/drakestapleton/homebrew-omega.git
brew install drakestapleton/omega/omc
```
Or verify a Terminal bundle with `install-si-1.0.sh` (clears `com.apple.quarantine` and runs ad-hoc `codesign -s - -f` **only after** SHA-256 verification succeeds):
```sh
sh si/release-1.0/install-si-1.0.sh --verify-bundle ./si-1.0-macos-arm64 --install --prefix "$HOME/.local"
```

### 4. Windows 10/11 (WSL 2 + Online Compiler)
No native Windows `.exe` is shipped. Inside **WSL 2** (`x86_64`), verify and install the static `x86linux` ELF bundle:
```sh
sh si/release-1.0/install-si-1.0.sh --verify-bundle ./si-1.0-x86linux-bundle --install --prefix "$HOME/.local"
```
For zero-install browser compilation under Omega's kernel sandbox (`execpure`), use `https://interplane.io/omega/compile/`.

---

## Exact Verification Commands

Run these on a Linux AArch64 host (DGX Spark) to verify every claim directly:

```sh
# 1. Seed bootstrap & 2x self-rebuild fixpoint
sh seed/omega-from-seed.sh

# 2. SI 1.0 release gate, standalone exporter & negative controls (pure OM-2)
seed/out/omc < si/release-1.0/gate_si_1_0.om > /tmp/gate_si_1_0 && chmod +x /tmp/gate_si_1_0
/tmp/gate_si_1_0 seed/out/omc . /tmp/om_gate_si

# 3. SI 1.0 installer topology, bundle-verify & policy gate (pure OM-2)
seed/out/omc < si/release-1.0/gate_installer.om > /tmp/gate_installer && chmod +x /tmp/gate_installer
/tmp/gate_installer seed/out/omc . /tmp/om_gate_inst

# 4. RM7 ABI v2 6-language + C-BTI + FR-7 dlopen/dlvsym qualification
sh bridge/abi-v2-spec/gate_abi_v2.sh

# 5. Live 1.0 readiness ledger verdict (refuses 1.0-HOLD until all 10 repos are green)
seed/out/omc < si/release-1.0/si_release_gate.om > /tmp/si_release_gate && chmod +x /tmp/si_release_gate
/tmp/si_release_gate si/release-1.0/MANIFEST-1.0.tsv seed/out/omc.sha256

# 6. QEMU/EDK2 AArch64 UEFI suite (emulated; zero physical UEFI/SPI touches)
sh tests/a64efi/run.sh seed/out/omc
```

For Drake's attended physical DGX Spark bare-metal boot ceremony (`DRA-938`), see [PHYSICAL-BOOT-RUNBOOK.md](PHYSICAL-BOOT-RUNBOOK.md).
