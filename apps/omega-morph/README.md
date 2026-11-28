# `apps/omega-morph`: Poly-Silicon Chameleon Executables (`OMMP01`)

> **One signed, hardware-independent executable that morphs on arrival to run across CPUs, GPUs, WebAssembly, and SPIR-V — verified before a single byte of machine code is emitted.**

Think of an `OMMP01` file like **one signed architectural blueprint + safety passport** instead of nine separate pre-compiled binaries. Normally, shipping a program to an NVIDIA Grace server, a MacBook, an x86-64 desktop, a RISC-V chip, a browser (WebAssembly), and a GPU requires compiling and signing separate binaries up front — and any new chip added later forces a compiler rebuild. With `omega-morph`, you pack **one** `921`-byte `.ommp` file once, sign it with RFC 8032 Ed25519, and any receiving machine checks the signature, the math proof (`EGP3`), the thermal power cap (`WattCBF < 80 W`), and its local `chips.tsv` hardware table at runtime before morphing into native code for that silicon.

| Traditional Multi-Target Build | `OMMP01` Poly-Silicon Chameleon (`omega-morph`) |
|---|---|
| Ship 9 separate binaries; hardcode target limits inside compiler | Ship **1 signed `921 B` `.ommp` file** (`ΩIR v2` + `SEMANTIC_ID` + `EGP3` + `WattCBF` + `OM-3`) |
| Adding a new 2035 chip requires rebuilding & redistributing compiler | Append a row to `chips.tsv` at runtime — **zero recompile**; over-limit targets refuse `exit 72` |
| Trust binary blindly on arrival or rely on OS dynamic linker | Fail-closed Ed25519 + SHA-256 + `SEMANTIC_ID` + `vc3_verify` (`EGP3`) + `OM-3` + `WattCBF` checks **before emit** |

**What Is NOT Run / Claimed Here:**
- **Physical GB10 GPU kernel execution (`sm121`): `NOT_RUN`** (`hw_writes=0`; zero `/dev/nvidia*` opens). SM121 SASS (`512 B`) and its `200 B` `HXP1` certificate are built by `bw_enc_sm121.om` and structurally verified by `monk_check.om` (`MONK PASS`).
- **Physical x86-64 and RISC-V silicon execution:** `ELF BUILT + EMULATED` on DGX Spark via `/usr/bin/qemu-x86_64` and `/usr/bin/qemu-riscv64`.
- **Zero C / Python / Rust / GCC:** 100% pure seeded OM-2 (`.om`) compiled with pinned `seed/out/omc`.

---

## Files

| File | Prefix | Role |
|---|---|---|
| [`ommp_morph.om`](ommp_morph.om) | `om_` / `OM_` | Pure-OM-2 `OMMP01` container packer, fail-closed verifier (`Ed25519` + `SHA-256` + `ΩIR v2` + `SEMANTIC_ID` + `EGP3` + `OM-3` + `WattCBF`), `chips.tsv` + `TargetDesc` + spill-aware `regalloc.om` contract checker, and 8-backend chameleon morpher (`pack`, `verify`, `morph`, `inspect`, `selftest`). Compiles identically on Spark Linux AArch64 and MacBook `target a64macos`. |
| [`gate_morph.om`](gate_morph.om) | `gm_` / `GM_` | End-to-end Spark verification gate (`37` checks, `14` killed negative controls): 2x deterministic build, `ngcheck` validation of `ΩIR v2`, `gate_egp3` validation of `EGP3`, all 8+1 (`future-chip-2035`) targets, and all red-team tamper/overload/contract refusals. |

---

## `OMMP01` Wire Format (`224 B` Header + `ΩIR v2` + `EGP3`)

| Byte Offset | Size | Field | Verification Check (Fail-Closed) |
|---|---|---|---|
| `[0..5]` | 6 B | `magic` | Exact `"OMMP01"`, else `exit 60` (`OM_ERR_FORMAT`) |
| `[6..7]` | 2 B | `version` | `u16` LE `== 1`, else `exit 60` |
| `[8..11]` | 4 B | `flags` | Exact `7` (`OM3_ZERO_PTR \| OM3_NO_KSLAB \| PURE_EXACT`), else `exit 65` |
| `[12..15]` | 4 B | `om3_tag` | Exact `"OM31"` (`825445711` LE), else `exit 65` (`OM_ERR_OM3`) |
| `[16..19]` | 4 B | `watt_power_mw` | `0 < watt_power_mw < 80000` (`< 80 W`), passes `wc_cbf_filter`, else `exit 66` |
| `[20..23]` | 4 B | `watt_tceil_mc` | `0 < watt_tceil_mc <= 90000` (`WattCBF` policy valid), else `exit 66` |
| `[24..55]` | 32 B | `TargetDesc` reqs | `req_smem` (`u64`), `req_regs` (`u32`), `req_l2_kb` (`u32`), `req_mma` (`u64`), `req_feat` (`u64`) -> `ctCheckRecipe` (`exit 72`) |
| `[56..63]` | 8 B | `oir_len`, `egp3_len` | `224 + oir_len + egp3_len == file_len` (Antibody 9: zero trailing bytes, else `exit 60`) |
| `[64..95]` | 32 B | `semantic_id` | Must match `SHA-256("omega.ng.sem.fn.v2:" \|\| oir_v2)`, else `exit 63` (`OM_ERR_SEM_ID`) |
| `[96..127]` | 32 B | `container_sha256` | `SHA-256(hdr[0..96) \|\| payload[224..end))`, else `exit 62` (`OM_ERR_SHA256`) |
| `[128..159]` | 32 B | `ed25519_pubkey` | RFC 8032 Ed25519 public key `A` |
| `[160..223]` | 64 B | `ed25519_sig` | RFC 8032 strict (`mode=0`) Ed25519 over `hdr[0..128)`, else `exit 61` (`OM_ERR_ED25519`) |
| `[224..224+oir_len)` | `285 B` | `ΩIR v2` payload | Genuine `OSC1IR` v10 (`omega.ng.ir.v2`) `@pure @exact @power(...)` module accepted by `ngcheck` |
| `[224+oir_len..end)` | `412 B` | `EGP3` proof bundle | Genuine `EGP3` structural e-graph proof verified by zero-shared-code `egp3_checker.om` (`vc3_verify`) |

---

## Verified Target Matrix (Single `921 B` `OMMP01` Container, `kfn(7,5,3) = (7 + 5) * 3 = 36`)

| # | `chips.tsv` Target | Backend | Artifact / Check | Result | Status Badge |
|---|---|---|---|---|---|
| 1 | `grace-x925` | `arm64-linux` | `148 B` static ELF64 (`EM_AARCH64=183`), 2x deterministic, native Spark CPU | `exit 36` | `HOST-VERIFIED` |
| 1b | `arm-linux-a64` | `arm64-linux` | `148 B` static ELF64 morphed & run live on Raspberry Pi 5 (`hub` `aarch64`) | `exit 36` | `HOST-VERIFIED` |
| 2 | `apple-m` | `apple-m` | `32808 B` PIE ARM64 Mach-O (`0xfeedfacf`), `codesign -s - -f`, live MacBook | `exit 36` | `HOST-VERIFIED` |
| 3 | `intel-x64` | `x64-linux` | `167 B` static ELF64 (`EM_X86_64=62`), 2x deterministic, `qemu-x86_64` | `exit 36` | `ELF BUILT + EMULATED` |
| 4 | `rv64-rvv` | `rv64-elf` | `148 B` static ELF64 (`EM_RISCV=243`), 2x deterministic, `qemu-riscv64` | `exit 36` | `ELF BUILT + EMULATED` |
| 5 | `wasm-universal` | `wasm` | `60 B` `OSC1IR v1` -> `seed/wasm/irwasm.om` (`116 B`), `node` (Spark + MacBook) | `36n` | `HOST-VERIFIED` |
| 6 | `spirv-vulkan` | `spirv` | `vkspirv` (`1872 B` `spirv-val vulkan1.3`) + `792 B` GLCompute (`val.om` + `run.om`) | `[36,90,18,450]` | `HOST-VERIFIED` |
| 7 | `intel-xe2` | `intel-xe` | `112 B` 128-bit Xe2/Xe3 EU ISA -> `gpu/intel/xe/isa.om check` + zero-SWSB kill | `exit 0` (`mut=1`) | `ISA-VALIDATED` |
| 8 | `sm121` | `sm121` | `512 B` SASS (`bw_enc_sm121.om`) + `200 B` `HXP1` -> `monk_check.om` + 2 mutants | `MONK PASS` (`NOT_RUN` GPU) | `MONK-VERIFIED` |
| 9 | `future-chip-2035` | `intel-xe` | Appended to temp `chips.tsv` at runtime (zero recompile): `smem=200k` PASS, `smem=300k` refused | `exit 0` / `exit 72` | `ISA-VALIDATED` |

---

## Build & Run

### 1. DGX Spark (Linux AArch64, pinned `omc` SHA-256 `85b84c6d...`)

```sh
git -C ~/git/omega-mv.git show main:seed/out/omc > /tmp/omc-pin && chmod +x /tmp/omc-pin

cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    seed/ng/target/target_desc.om seed/ng/target/chips_tsv.om seed/ng/target/regalloc.om \
    seed/ng/target/isel.om seed/ng/target/sm121_pe.om om/encoder/bw_enc_sm121.om \
    seed/ng/verify/egp3_checker.om apps/omega-morph/ommp_morph.om | /tmp/omc-pin > /tmp/ommp_morph
chmod +x /tmp/ommp_morph

cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
    protocol/omnet/om/ed25519/ed25519.om apps/omega-morph/gate_morph.om | /tmp/omc-pin > /tmp/gate_morph
chmod +x /tmp/gate_morph

/tmp/ommp_morph selftest --chips seed/ng/target/chips.tsv
/tmp/gate_morph /tmp/ommp_morph <TOOLS_DIR> <SCRATCH_DIR> seed/ng/target/chips.tsv
```

### 2. MacBook Apple Silicon (`target a64macos`, `~/.local/bin/omc`)

```sh
{ printf 'target a64macos\n'; cat si/directives/om2.om apps/omega-wattd/watt_sense.om apps/omega-wattd/watt_cbf.om \
    seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    seed/ng/target/target_desc.om seed/ng/target/chips_tsv.om seed/ng/target/regalloc.om \
    seed/ng/target/isel.om seed/ng/target/sm121_pe.om om/encoder/bw_enc_sm121.om \
    seed/ng/verify/egp3_checker.om apps/omega-morph/ommp_morph.om; } | ~/.local/bin/omc > /tmp/ommp_morph
chmod +x /tmp/ommp_morph && codesign --force --sign - /tmp/ommp_morph

/tmp/ommp_morph selftest --chips seed/ng/target/chips.tsv
/tmp/ommp_morph pack --out /tmp/k.ommp
/tmp/ommp_morph morph --in /tmp/k.ommp --chips seed/ng/target/chips.tsv --target apple-m --out /tmp/k_mac
chmod +x /tmp/k_mac && codesign --force --sign - /tmp/k_mac && /tmp/k_mac; echo "exit=$?"
```
