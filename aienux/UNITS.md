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

`aienux/units.tsv` lists 48 units (`NAME` followed by ordered `.om` parts, single spaces):

- 4 TCP units (`tcp_tcpd`, `tcp_corpus`, `tcp_link`, `tcp_peer`)
- 4 NVMe units (`nvme_main`, `nvme_probe`, `nvme_adminwrap`, `nvme_failstop`)
- 4 x86-64 kernel units (`x86_llama`, `x86_arithmetic`, `x86_system`, `x86_text`)
- 1 Llama-1B unit (`lm1b`)
- 1 platform unit (`platform_unit`)
- 3 tool units (`spark_image`, `imac_image`, `hwgates`)
- 31 Allen units (`allen_fw` for `target x86efi`, `allen_main`, `allen_provider`, `allen_stdio_overflow`, and 27 `allen_test_*` suites from `native/omega/allen/gate.sh`)

`aienux/units-gate.om` (`OMEGA-AIENUX-UNITS`) mirrors `gpu/units-gate.om`: it refuses any compiler whose SHA-256 differs from `seed/out/omc.sha256` (exit 69), composes each row in `aienux/units.tsv`, compiles it twice, and requires exit 0, empty stderr and identical output bytes, plus catches the `omc-plus-one` negative control. Every hardware row stays `NOT_RUN`.

This gate verifies deterministic compilation with `seed/out/omc`. It does not run QEMU, boot firmware, or execute the behavioral oracles that still live in Aienux as C, Rust, shell, or Python.

## Not here yet

Every non-Omega first-party file outside `evidence/` and `vendor/` at Aienux `1f12818d` stayed in Aienux and is indexed in `aienux/NOT-YET-OMEGA.tsv` (1,897 files):

- `c-asm-legacy` (618): frozen C/assembly kernel (`native/kernel/`), drivers (`native/disk/*.c`, `native/net/`), boot entry (`native/boot/`), ARGUS (`native/argus/`), Store (`native/store/`), capability ABI (`native/capability/`), and Makefiles.
- `rust-legacy` (307): older Rust kernel and tools under `crates/`.
- `script-harness` (229): shell, Python and JS gate/build harnesses.
- `gate-manifest` (25): Aienux gate manifests.
- `data-or-fixture` (344), `doc-or-asset` (277): fixtures, test vectors, docs, design assets and pins.
- `retired` (97): retired crumb metadata (DRA-97).

Rewriting the frozen C kernel (`native/kernel/`) in pure Omega into `aienux/kernel/` is the next step once `seed/omc/omc.om` gains the required bare-metal kernel primitives (system registers, barriers, exception vector table and `eret`, FR-8).
