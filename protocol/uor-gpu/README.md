# `protocol/uor-gpu` — Pure Seeded-Omega UOR / Prism GPU Extension

Extends the **UOR Foundation / Prism SDK** (`uor.foundation`) to verifiable, content-addressed GPU bundles implemented **100% in pure seeded Omega (`.om`)** compiled by `seed/out/omc`, with **pinned Lean 4 proofs** (`P2` default policy), **local trust anchors**, **authority-signed capability grants**, **single-source kernel compilation**, **full Blackwell QMD v5**, **real kernel VM replay**, and **zero CUDApp**.

## Founding Doctrine Alignment & Honest Scope

1. **Identity from canonical bytes:** Every GPU bundle carries a `uor-addr` **SHA-256** canonical ID (`om/tls/sha2.om`) and a `.holo` **BLAKE3** bundle fingerprint (`protocol/uor-gpu/b3_uor.om`). No host path, driver handle, PCI slot, or central registry participates in identity.
2. **Single-source kernel emission & full QMD v5 (zero duplicated fixtures):**
   - `SM121` payloads (**896 bytes**: 512B Blackwell SM121 SASS + 384B / 96-word full QMD v05.00 descriptor) are compiled directly at bundle time from `om/gpu/bw_vecadd.om` and `om/gpu/bw_qmd.om` by the SHA-256-verified `seed/out/omc` binary. `source_sha256` is `SHA-256(bytes(om/gpu/bw_vecadd.om) || bytes(om/gpu/bw_qmd.om))`, and the emitted 512B SASS matches `OMEGA_BW_VECADD_EXPECTED_SHA256` (`39f3dfdfc529a75a8274a27900acf4e7382b7f280a211e0412c51609f44b62a1`).
   - `SPIRV` payloads are compiled directly from `gpu/spirv/emit.om` (`vadd cl`, OpenCL Kernel SPIR-V 1.0) by the SHA-256-verified `seed/out/omc` binary. `source_sha256` is `SHA-256(bytes(gpu/spirv/emit.om))`.
   - `mlbom_sha256` hashes the structured manifest (`mlbom:v2:<isa>:<dtype>:8:`) concatenated with the exact 64-byte golden input slab (`A[0..8) || B[0..8)`).
3. **Real kernel replay (`payload_vm.om`):**
   - `verify` and `admit` enforce full target payload structural invariants before dispatch: all 6 Blackwell QMD v05.00 SKEDCHECK05 invariants (`version == 5`, `qtype == 2`, `q[37] == 0`, `q[17] != 0`, `prefetch == 0xa`, `cb0_valid`) plus `q[34].threads_x == hdr.block_x` and `gpr_count >= 16` for `SM121`; SPIR-V 1.0 OpenCL header, framing, capabilities, memory model, and entry point for `SPIRV`.
   - `prism-gpu replay` decodes and executes the **actual machine-code bytes inside `payload`** in pure seeded OM-2 (an SM121 SASS interpreter for `SM121` and a SPIR-V 1.0 binary VM for `SPIRV`) across 8 in-bounds plus 4 out-of-bounds threads/work-items with canary-guarded output buffers, checking that execution completes without fault/OOB and that `SHA-256(output)` matches both `hdr.replay_sha256` and the world's golden vecadd vector digest.
4. **No central authority (local trust anchors):** Each verifier owns an offline `UORTRST1` trust anchors file containing its pinned `omc_sha256`, pinned `lean_proof_sha256`, capability authority Ed25519 public key, and 1..16 trusted bundle signer Ed25519 public keys (none may equal the authority key). Verification and admission run 100% offline.
5. **"Nothing raises a level except signing":**
   - `P0` (0): digests + target payload structure verified. Unsigned bundles (`signer_pubkey == 0`) MUST claim level `P0` and carry an all-zero signature slot; unsigned claims of `P1..P3` or smuggled signature bytes are refused.
   - `P1` (1): `P0` + valid RFC 8032 Ed25519 signature by a key in the verifier's local trust anchors.
   - `P2` (2, **default minimum**): `P1` + `lean_proof_sha256` matching the verifier's pinned Lean 4 proof digest (`proofs/UorGpuWorld.lean`).
   - `P3` (3): `P2` + non-zero `replay_sha256`, verified by executing the actual kernel payload bytes via `prism-gpu replay`.
   - Verdicts (`prism/verdict/1`) report `policy_level` (the level actually checked), never the level claimed by the header. `prism-gpu inspect` reports unverified header claims (`claimed_level`, `has_signature`, `signer_pubkey`).
6. **Fail closed before GPU submission:** Any 1-byte tamper, trailing byte, empty payload, invalid launch geometry (`block_x` outside `1..1024`), invalid QMD v5 / SPIR-V structure, QMD `threads_x != block_x`, SASS/SPIR-V execution fault or OOB store or wrong arithmetic, untrusted signer, unpinned proof digest, unsigned/forged capability grant, zero generation, zero/expired lease, or missing `RX_RIGHT_EFFECT` right refuses admission.
7. **Honest remaining boundaries:**
   - **Lean 4 proof boundary:** `proofs/UorGpuWorld.lean` (SHA-256 `4242bcf69741fc3064f67083694e0e09f969eb4cc9ed4369d96154dc02a7238a`, 78 theorems, core Lean 4 only, zero `sorry`, zero `native_decide`, standard axioms only) machine-checks seven theorem families aligned with both recent AIEN Lean 4 proofs (`AienGpuGb20b`, `AienReceipt`, `AienCap`, `NgA64Vec`, `CodebookProof`, `TicketLock`, `Ledger`, `BtWaveProofs`) and the current UOR Foundation / Prism group (`uor-framework`, `LexLean`, `PrismPM`, `uor-comms`, `mnist`): (1) wire-layout contiguity, disjointness & tiling (`384B`, `104B`, `128B`, `896B`); (2) bit-exact `BitVec` pack/unpack round-trips, injectivity & pairwise opcode disjointness for LE32, QMD v5 words 34/35/36, and SM121 SASS `w0`; (3) multi-thread bounded `runVecadd` & guard-canary preservation; (4) two-stage SHA-256/BLAKE3 tamper evidence under explicit collision resistance; (5) Blackwell QMD v5 SKEDCHECK05, trust-anchor authority/signer privilege separation, reason-coded `evalPolicy`/`evalAdmit` equivalence, monotonicity, and unsigned-bundle P0 cap; (6) inductive `Step`/`Reachable`/`SafeInv` pre-dispatch lifecycle reachability; and (7) Prism-group alignment (`Z/(2^32)Z` ring critical identity `-~~~x = x + 1` & involutions, `mnist`-style `vecadd_satisfies_contract`, `LexLeanBoot.ContentId` domain-separated framing, `uor-comms` `ReasonProofs` forward/converse refusal characterization, and `PrismPM` `Foundation.Proof.V1.Statement` axiom-policy & replay gate), with load-bearing negative controls in each section. It does not prove hardware-level equivalence between the SM121 SASS VM and physical GB10 silicon.
   - **Offline capability revocation:** `prism-gpu admit` checks the authority Ed25519 signature, wall-clock lease expiry (`realns`), non-zero generation/lease, epoch, subject, resource, and `RX_RIGHT_EFFECT`. Live generation-based revocation requires the kernel/memfd `caproot` seqlock (`seed/authority/caproot.om`); offline admission relies on short authority-signed leases.
   - **Hardware status:** Real kernel replay runs in pure seeded-Omega host VMs (`HOST_TESTED` / `EMULATED`); physical GB10 silicon execution is `NOT_RUN`.

## Canonical `UOR-GPU-1` Bundle Header (384 bytes)

| Offset | Size | Field |
|---|---:|---|
| 0 | 8 | Magic `"UORGPU1\0"` |
| 8 | 4 | Version (`1` u32 LE) |
| 12 | 4 | Target ISA (`1=SM121`, `2=SPIRV` u32 LE) |
| 16 | 4 | Math contract (`1=IEEE754_RN`, `2=FTZ` u32 LE) |
| 20 | 4 | Claimed evidence level (`0=P0..3=P3` u32 LE) |
| 24 | 4 | Payload byte length (`u32 LE`, must be `> 0`; exact `896` for SM121) |
| 28 | 4 | Launch `block_x` (`u32 LE`, `1..1024`; must equal QMD word 34 `threads_x` for SM121) |
| 32 | 32 | `omc_sha256` (pinned `seed/out/omc` digest) |
| 64 | 32 | `source_sha256` (`SHA-256(bw_vecadd.om \|\| bw_qmd.om)` for SM121; `SHA-256(gpu/spirv/emit.om)` for SPIR-V) |
| 96 | 32 | `payload_sha256` (SHA-256 of emitted payload bytes) |
| 128 | 32 | `lean_proof_sha256` (SHA-256 of verified `UorGpuWorld.lean`; pinned for `P2`/`P3`) |
| 160 | 32 | `replay_sha256` (SHA-256 of kernel VM replay output vector; checked for `P3`) |
| 192 | 32 | `mlbom_sha256` (SHA-256 of structured ML-BOM manifest + golden input slab, PrismPM `#310`) |
| 224 | 32 | `uor_id_sha256` (`SHA-256(header[0..223])`) |
| 256 | 32 | `holo_blake3` (`BLAKE3(header[0..255] \|\| payload[0..payload_len))`) |
| 288 | 32 | `signer_pubkey` (RFC 8032 Ed25519 public key; all-zero = unsigned) |
| 320 | 64 | `attest_sig` (RFC 8032 Ed25519 signature over `header[224..287]`) |

## Local Trust Anchors (`UORTRST1`, 136..616 bytes)

| Offset | Size | Field |
|---|---:|---|
| 0 | 8 | Magic `"UORTRST1"` |
| 8 | 32 | `omc_sha256` pin (non-zero) |
| 40 | 32 | `lean_proof_sha256` pin (non-zero) |
| 72 | 32 | `authority_pubkey` (Ed25519 capability authority; all-zero disables admission) |
| 104 | `32 * k` | `1..16` trusted bundle signer Ed25519 public keys (each non-zero and `!= authority_pubkey`) |

## Authority-Signed Capability Grant (128 bytes)

- `[0..64)`: `8 x u64 LE` (`state`, `generation`, `epoch`, `lease_expiry_sec`, `subject`, `resource`, `rights`, `reserved`).
- `[64..128)`: RFC 8032 Ed25519 signature over `[0..64)` by `authority_pubkey`.

## CLI (`prism-gpu`)

Run `bundle` from the `omega-mv` repository root (with pinned `seed/out/omc`, `om/gpu/bw_vecadd.om`, `om/gpu/bw_qmd.om`, and `gpu/spirv/emit.om`). All verification, replay, and admission commands run 100% offline from any directory.

```text
prism-gpu keygen out.seed
prism-gpu pubkey in.seed out.pub
prism-gpu trust out.trust authority.pub signer.pub
prism-gpu bundle sm121|spirv out.holo signer.seed
prism-gpu inspect file.holo
prism-gpu verify file.holo anchors.trust
prism-gpu replay file.holo anchors.trust
prism-gpu grant record64.bin authority.seed out.grant
prism-gpu admit file.holo anchors.trust file.grant
```

## Units

- `b3_uor.om`: Namespaced BLAKE3 unit composed alongside `om/tls/sha2.om`.
- `canonical.om`: Canonical 384-byte `UOR-GPU-1` codec, `SHA-256` + `BLAKE3` sealer/checker.
- `payload_vm.om`: Full Blackwell QMD v05.00 SKEDCHECK05 validator, pure seeded OM-2 SM121 SASS binary interpreter, SPIR-V 1.0 OpenCL Kernel validator, and SPIR-V binary VM for real kernel replay.
- `verify.om`: `UORTRST1` local trust anchors validator, `P0..P3` policy verifier, strict RFC 8032 Ed25519 verifier, real replay checker, and `prism/verdict/1` + `prism/inspect/1` JSON emitters.
- `gate.om`: Pre-dispatch admission gate combining `verify.om` with authority-signed capability validation (`RX_RIGHT_EFFECT = 4`).
- `emit_kernels.om`: Single-source `seed/out/omc` compiler driver (`om/gpu/bw_vecadd.om` + `om/gpu/bw_qmd.om` -> 896B SM121 SASS+QMD v5; `gpu/spirv/emit.om` -> SPIR-V 1.0 OpenCL), streaming compiler-pin check, real source/ML-BOM hashing, and trust-anchor builder.
- `ed_sign.om`: Pure seeded OM-2 RFC 8032 Ed25519 key derivation and signing (producer side only; variable-time, never used on the verify path).
- `prism-gpu.om`: Pure seeded-Omega CLI plugin (`keygen|pubkey|trust|bundle|inspect|verify|replay|grant|admit`).
- `uor-gpu-gate.om`: Pure seeded-Omega host gate exercising RFC 8032 Ed25519 sign+verify vectors, single-source `omc` compilation of SM121+QMD v5 and SPIR-V, real kernel VM replay, local trust anchors, authority-signed grants, and 33 negative controls.
- `proofs/UorGpuWorld.lean`: Machine-checked Lean 4 specification (78 theorems, core Lean 4 only, zero `sorry`, zero `native_decide`, standard axioms only, aligned with recent AIEN Lean 4 theorem classes and UOR Foundation / Prism group proofs).
