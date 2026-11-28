# `seed/helix/ddc_mesh/`: Live Cross-Host Physical Byzantine Diverse Double-Compiling (`DDC-3HOST`)

> **Verify the compiler on three completely different machines, on three operating systems, before trusting any binary.**

In 1984, Ken Thompson's Turing Award lecture *"Reflections on Trusting Trust"* showed that reading clean source code isn't enough: a compromised compiler binary can silently inject a backdoor whenever it compiles a target program — and re-inject itself whenever it compiles a new compiler.

David Wheeler's **Diverse Double-Compiling (DDC)** breaks that self-referential loop by compiling with independent compilers. **`DDC-3HOST`** takes DDC physical and cryptographic across **three separate real machines** in pure seeded Omega (`.om`) with zero C, zero GCC, zero Python, zero Rust, and zero third-party crypto:

| Traditional Single-Host Build | `DDC-3HOST` Across Three Physical Machines |
|---|---|
| Trust one compiler on one OS and hope its binary isn't rigged | Run the same pure-OM-2 source on **Apple Silicon (`macOS Darwin`)**, **DGX Spark (`Grace Linux`)**, and **Raspberry Pi 5 (`Cortex-A76 Linux`)** |
| Compare build logs by eye or trust unsigned hashes | Every host emits an **RFC 8032 Ed25519 signed 352-byte `OMRC0001` receipt** binding source, cross-compiled ELF, native Mach-O/ELF, and live execution digest |
| A single compromised host or reused key can forge consensus | **3-of-3 Byzantine quorum aggregator** rejects any `2-of-3` Ken Thompson divergence, 1-bit Ed25519 tamper, wrong domain tag, or duplicate-key Sybil spoof |

**Honest Verification Scope:**
- **Physical 3-Host CPU Convergence (`HOST-VERIFIED`):** Built, signed, executed, and quorum-verified natively on **Apple M2 (macOS 26.6.2)**, **NVIDIA DGX Spark Grace X925/A725 (Ubuntu 24.04.5)**, and **Raspberry Pi 5 Cortex-A76 (`hub`, Ubuntu 26.04.1)**.
- **Physical GB10 GPU (`NOT_RUN`):** `hw_writes=0`; zero `/dev/nvidia*` opens and zero UEFI/NVRAM/SPI/USB/ESP touches.

---

## Files

| File | Prefix | Role |
|---|---|---|
| [`ddc_mesh.om`](ddc_mesh.om) | `dm_` / `DM_` | Pure seeded OM-2 cross-host DDC engine (`emit-payload`, `attest`, `verify-receipt`, `verify-quorum`, `inspect`, `selftest`). Compiles cleanly from the same source on `target a64macos` (MacBook) and `aarch64` Linux (Spark & Pi 5). |
| [`gate_ddc_mesh.om`](gate_ddc_mesh.om) | `gd_` / `GD_` | Standalone pure-OM verification gate: 2x deterministic rebuilds (Linux ELF & `a64macos` Mach-O), live payload execution, 3-host Ed25519 quorum pass, a real patched self-recompiled `trojan_omc` compiler mutant (`exit=109`), and 12 additional negative controls (`checks=6`, `neg_controls=13`). |
| [`../../evidence/WAVE3-DDC-MESH-20261127/RECEIPT.txt`](../../evidence/WAVE3-DDC-MESH-20261127/RECEIPT.txt) | — | Exact hashes, sizes, and live outputs from MacBook, DGX Spark, and Raspberry Pi 5 `hub`. |

---

## `OMRC0001` Convergence Receipt Wire Layout (352 Bytes, Little-Endian)

| Offset | Size | Field | Verification Rule (Fail-Closed) |
|---|---:|---|---|
| `[0..8)` | 8 B | `magic` | Exact `"OMRC0001"`, else `exit 102` (`MALFORMED_OMRC0001`) |
| `[8..32)` | 24 B | `domain_tag` | Exact `"OMEGA-DDC3-RECEIPT-V1"` + 3 NUL bytes, else `exit 103` (`WRONG_DOMAIN_TAG`) |
| `[32..36)` | 4 B | `version` | `u32 LE == 1`, else `exit 102` |
| `[36..40)` | 4 B | `host_role_id` | `1` (MacBook), `2` (DGX Spark), or `3` (Pi 5 `hub`); quorum requires `{1, 2, 3}` mask `7`, else `exit 107` |
| `[40..48)` | 8 B | `epoch` | `u64 LE >= 1`, else `exit 102` |
| `[48..56)` | 8 B | `compiled_bytes` | `u64 LE > 0` (native binary byte count), else `exit 102` |
| `[56..64)` | 8 B | `exec_exit_code` | `u64 LE` native execution return status (`53` for canonical payload), else `exit 110` on quorum split |
| `[64..96)` | 32 B | `platform_abi_sha256` | `SHA-256(abi_tag)`, non-zero and pairwise distinct across all 3 hosts (`exit 107`) |
| `[96..128)` | 32 B | `source_sha256` | `SHA-256(payload.om)`, must match `3/3` (`exit 108`) |
| `[128..160)` | 32 B | `compiled_sha256` | `SHA-256(native_binary)` (Mach-O on Darwin, ELF64 on Grace/Pi 5) |
| `[160..192)` | 32 B | `exec_digest` | `SHA-256(native_stdout)`, must match `3/3` (`exit 110`) |
| `[192..224)` | 32 B | `cross_elf_sha256` | `SHA-256(canonical_aarch64_elf)`, must match `3/3` (`exit 109` on Ken Thompson compiler divergence) |
| `[224..256)` | 32 B | `semantic_digest` | `SHA-256("OMEGA-DDC3-SEMANTIC-V1\0" \|\| source_sha256 \|\| exec_digest \|\| u64_le(exec_exit_code) \|\| cross_elf_sha256)`, recomputed & checked (`exit 105` / `111`) |
| `[256..288)` | 32 B | `node_pubkey` | RFC 8032 Ed25519 public key `A`, non-zero & pairwise distinct across all 3 hosts (`exit 106` Sybil guard) |
| `[288..352)` | 64 B | `ed25519_sig` | RFC 8032 strict (`mode=0`) Ed25519 signature over `[0..288)`, else `exit 104` (`ED25519_SIG_INVALID`) |

Any file whose length is not **exact `352` bytes** (including `351 B` truncated or `353 B` with a trailing byte) is refused with `exit 102`.

---

## Live 3-Host Convergence Results (2026-11-27)

| Artifact / Check | MacBook M2 (`a64macos` Darwin) | DGX Spark (`aarch64` Grace Linux) | Pi 5 `hub` (`aarch64` Cortex-A76 Linux) |
|---|---|---|---|
| Compiler (`omc`) | `~/.local/bin/omc` (`68a590c3...`) | `seed/out/omc` (`85b84c6d...`) | `seed/out/omc` (`85b84c6d...`, self-rebuilt fixpoint OK) |
| `ddc_mesh` Linux ELF (`71,696 B`) | `504b4cf7...` | `504b4cf7...` | `504b4cf7...` |
| `ddc_mesh` Mach-O (`99,232 B` pre-`codesign`) | `9332a902...` (`116,816 B` signed: `6de16a9a...`) | `9332a902...` | `9332a902...` (via `target a64macos`) |
| `payload.om` (`2,008 B`) | `20a2ce9c...` | `20a2ce9c...` | `20a2ce9c...` |
| `payload` ELF64 (`2,220 B`) | `87793042...` | `87793042...` | `87793042...` |
| `payload` Mach-O (`33,184 B` pre-`codesign`) | `b66c92ae...` (`51,136 B` signed: `8fb74050...`) | `b66c92ae...` | `b66c92ae...` |
| Native Execution (`121 B`, `exit=53`) | `1e6e6986...` (`DDC_PAYLOAD_OK`) | `1e6e6986...` (`DDC_PAYLOAD_OK`) | `1e6e6986...` (`DDC_PAYLOAD_OK`) |
| `OMRC0001` Receipt (`352 B`) | `376b03d9...` (`pk=7adebeab...`) | `d6027809...` (`pk=96c3056a...`) | `f7d217ba...` (`pk=d1dea8b2...`) |
| `verify-quorum` (3-of-3 live) | `DDC_QUORUM PASS` (`exit 0`) | `DDC_QUORUM PASS` (`exit 0`) | `DDC_QUORUM PASS` (`exit 0`) |
| `trojan_omc` Live Reject (`2-of-3`) | `exit 109` (`dissent_role_mask=2`) | `exit 109` (`dissent_role_mask=2`) | `exit 109` (`dissent_role_mask=2`) |

---

## Build & Reproduce

### 1. Build & Run Verification Gate on DGX Spark (or Pi 5 inside `/tmp/ddc-mesh-*`)

```sh
cat si/directives/om2.om seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om \
    protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om \
    seed/helix/ddc_mesh/ddc_mesh.om | seed/out/omc > /tmp/ddc_mesh
chmod +x /tmp/ddc_mesh

cat si/directives/om2.om seed/ng/sha256.om seed/helix/ddc_mesh/gate_ddc_mesh.om | seed/out/omc > /tmp/gate_ddc_mesh
chmod +x /tmp/gate_ddc_mesh

/tmp/gate_ddc_mesh seed/out/omc . /tmp/ddc-mesh-gate
```

### 2. Build & Attest Natively on MacBook Apple Silicon (`target a64macos`)

```sh
{ printf 'target a64macos\n'; cat si/directives/om2.om seed/ng/sha256.om \
    protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om \
    protocol/uor-gpu/ed_sign.om seed/helix/ddc_mesh/ddc_mesh.om; } | ~/.local/bin/omc > /tmp/ddc_mesh_mac
chmod +x /tmp/ddc_mesh_mac && codesign --force --sign - /tmp/ddc_mesh_mac

/tmp/ddc_mesh_mac selftest
/tmp/ddc_mesh_mac emit-payload /tmp/payload.om
/tmp/ddc_mesh_mac emit-payload /tmp/payload_mac.om --macos
~/.local/bin/omc < /tmp/payload_mac.om > /tmp/p_mac
~/.local/bin/omc < /tmp/payload.om > /tmp/p_elf
chmod +x /tmp/p_mac && codesign --force --sign - /tmp/p_mac
/tmp/p_mac > /tmp/mac_exec.out; echo "exit=$?"
/tmp/ddc_mesh_mac attest --role 1 --abi a64macos-apple-m2-darwin \
    --source /tmp/payload.om --compiled /tmp/p_mac --cross-elf /tmp/p_elf \
    --exec-out /tmp/mac_exec.out --exec-rc 53 --out /tmp/r1_mac.rcpt
```
