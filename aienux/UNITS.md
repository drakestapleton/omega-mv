# aienux/: Pure-Omega Aienux units (step 1)

Aienux is the operating system layer of Sovereign Intelligence (SI). Step 1 brought all 132 non-evidence pure-Omega (`.om`) files from canonical Aienux (`rad:z2Q6ob2gL6Qo5oUMpyehukayVF7mN`) main `1f12818d06ab0eb89cd592f83e13197477b36c07` into `omega-mv` with their Git history (22 commits). Command and maps: `aienux/import/step1-om/`.

| Aienux path | Here | Files | What |
| --- | --- | ---: | --- |
| `native/net/tcp/*.om` | `aienux/net/tcp/` | 5 | Native Ethernet/ARP/IPv4/TCP stack, guest driver, impairment relay, peer and corpus |
| `native/disk/**/*.om` | `aienux/disk/` | 6 | Native NVMe protocol engine, transport, CLI and tests |
| `native/omega/allen/**/*.om` | `aienux/allen/` | 109 | Bare-metal UEFI graphical UI (`surface`, `paint`, `font`, `look-*`, `scene*`, `efi-main`), bare-metal TCP/TLS/HTTP, runtime/memory/courier/application and `.om` test suites |
| `native/omega/platform/*.om` | `aienux/platform/` | 2 | Platform readback units |
| `native/kernel/x86/**/*.om` | `aienux/kernel/x86/` | 4 | Native x86-64 kernel model (`llama.om`) and tool units |
| `native/om/lm1b/*.om` | `aienux/lm1b/` | 3 | Seeded Llama-1B runner (`lm1b.om`, `lm1b.in.om`, `sha256.om`) |
| `tools/{spark-image,imac-image,hwgates}/*.om` | `aienux/tools/` | 3 | GPT/FAT32 UEFI image writers and hardware-gate register checker |

One additional 1-line Omega directive file, `aienux/allen/target-x86efi.om` (`target x86efi`), was added so the bare-metal UEFI firmware unit `allen_fw` composes directly through `aienux/units.tsv` with no shell wrapper.

## The units and their gate

`aienux/units.tsv` lists **112 units** (`NAME [@run|@qemu]` followed by ordered `.om` parts, single spaces; 42 behavioral self-test units are tagged `@run`):

- 48 core Aienux units (`tcp_*` 4, `nvme_*` 4, `x86_*` 4, `lm1b` 1, `platform_unit` 1, `spark_image`/`imac_image`/`hwgates` 3, `allen_fw` `target x86efi` + `allen_main` + `allen_provider` + `allen_stdio_overflow` + 27 `allen_test_*` = 31)
- 19 OS-layer sibling units from `rtl8127-omega` (`rtl8127_probe`, `rtl8127_driver`), `spark-supervisor` (`aien_supervise`, `aien_supervise_root`, `aien_watch`, `supervisor_tests_load`), and `spark-connector` (`connector_signer`, `connector_celldrv`, plus 11 standalone gate/runner units).
- 6 converted pure-Omega OS-layer units (9 `.om` files): `atlas_main`/`atlas_test` (`@run`, `aienux/atlas/`), `pi_register_main`/`pi_register_test` (`@run`, `aienux/pi-register/`), and `debugger_main`/`debugger_test` (`@run`, `aienux/debugger/`).
- 39 converted pure-Omega kernel/store/boot/driver/crate units (all `@run`):
  - Wave 1 (Capability & Store): `capability_test`, `contain_test`, `store_test`, `torn_slot_test`
  - Wave 2 (Boot & Kernel): `boot_test`, `kernel_core_test`, `kernel_hal_test`, `kernel_runtime_test`, `kernel_arm64_host_test`, `osc_launch_test`
  - Wave 3 (ARGUS, Disk, Net): `argus_test`, `argus_bridge_test`, `disk_test`, `net_core_test`
  - Wave 4 (Rust Crates — complete): `aegis_test`, `crate_anchor_test`, `crate_c1_tree_test`, `crate_cap_ffi_test`, `crate_evidence_test`, `crate_store_tool_test`, `crate_accel_test`, `crate_agent_state_test`, `crate_artifact_test`, `crate_artifact_tool_test`, `crate_cortex_test`, `crate_crypto_test`, `crate_explain_test`, `crate_fpu_probe_test`, `crate_infer_kernel_test`, `crate_design_tokens_test`, `crate_boot_test`, `crate_infer_test`, `crate_courier_test`, `crate_reflex_test`, `crate_reflex_kernel_test`, `crate_kernel_sec_continuity_test`, `crate_kernel_mm_iommu_test`, `crate_kernel_usb_xhci_test`, `crate_kernel_sys_test`

Remaining non-Omega files from the three OS sibling repos (64 files) are listed in `aienux/NOT-YET-OMEGA-EXTRAS.tsv`; their import records are under `aienux/import/{rtl8127-omega,spark-supervisor,spark-connector}/`.

`aienux/units-gate.om` (`OMEGA-AIENUX-UNITS`) mirrors `gpu/units-gate.om`: it refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69), composes each row in `aienux/units.tsv`, compiles it twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Units tagged `@run` are executed directly (`run=PASS` / `run=FAIL`, asserting exit 0, counted in `behavior_passed=N/M`). Units tagged `@qemu` are booted under `/usr/bin/qemu-system-aarch64` when present (`qemu=PASS` / `qemu=FAIL`) or reported `qemu=NOT_RUN` when QEMU is absent so host-only runs stay honest. Every hardware row stays `hardware=NOT_RUN`.

This gate verifies deterministic compilation with `seed/out/omc` and host behavioral self-tests for `@run` units (plus optional QEMU emulation for `@qemu` units); host and QEMU passes are never hardware qualification.

## Not here yet

Every non-Omega first-party file outside `evidence/` and `vendor/` at Aienux `1f12818d` stayed in Aienux and is indexed in `aienux/NOT-YET-OMEGA.tsv` (1,897 files):

- `c-asm-legacy` (618): frozen C/assembly kernel (`native/kernel/`), drivers (`native/disk/*.c`, `native/net/`), boot entry (`native/boot/`), ARGUS (`native/argus/`), Store (`native/store/`), capability ABI (`native/capability/`), and Makefiles.
- `rust-legacy` (307): older Rust kernel and tools under `crates/`.
- `script-harness` (229): shell, Python and JS gate/build harnesses.
- `gate-manifest` (25): Aienux gate manifests.
- `data-or-fixture` (344), `doc-or-asset` (277): fixtures, test vectors, docs, design assets and pins.
- `retired` (97): retired crumb metadata (DRA-97).

Rewriting the frozen C kernel (`native/kernel/`) in pure Omega into `aienux/kernel/` is the next step once `seed/omc/omc.om` gains the required bare-metal kernel primitives (system registers, barriers, exception vector table and `eret`, FR-8).
