# `protocol/uor-gpu` — Pure Seeded-Omega UOR / Prism GPU Extension

Extends the **UOR Foundation / Prism SDK** (`uor.foundation`) to verifiable, content-addressed GPU bundles implemented **100% in pure seeded Omega (`.om`)** compiled by `seed/out/omc`, with **pinned Lean 4 proofs** (`P2` default policy), **local trust anchors**, **authority-signed capability grants**, and **zero CUDApp**.

## Founding Doctrine Alignment & Honest Scope

1. **Identity from canonical bytes:** Every GPU bundle carries a `uor-addr` **SHA-256** canonical ID (`om/tls/sha2.om`) and a `.holo` **BLAKE3** bundle fingerprint (`protocol/uor-gpu/b3_uor.om`). No host path, driver handle, PCI slot, or central registry participates in identity.
2. **No central authority (local trust anchors):** Each verifier owns an offline `UORTRST1` trust anchors file containing its pinned `omc_sha256`, pinned `lean_proof_sha256`, capability authority Ed25519 public key, and 1..16 trusted bundle signer Ed25519 public keys (none may equal the authority key). Verification and admission run 100% offline.
3. **"Nothing raises a level except signing":**
   - `P0` (0): digest-verified only. Unsigned bundles (`signer_pubkey == 0`) MUST claim level `P0` and carry an all-zero signature slot; unsigned claims of `P1..P3` or smuggled signature bytes are refused.
   - `P1` (1): `P0` + valid RFC 8032 Ed25519 signature by a key in the verifier's local trust anchors.
   - `P2` (2, **default minimum**): `P1` + `lean_proof_sha256` matching the verifier's pinned Lean 4 proof digest (`proofs/UorGpuWorld.lean`).
   - `P3` (3): `P2` + non-zero `replay_sha256`, verified against the replay oracle by `prism-gpu replay`.
   - Verdicts (`prism/verdict/1`) report `policy_level` (the level actually checked), never the level claimed by the header. `prism-gpu inspect` reports unverified header claims (`claimed_level`, `has_signature`, `signer_pubkey`).
4. **Fail closed before GPU submission:** Any 1-byte tamper, trailing byte, empty payload, invalid launch geometry (`block_x` outside `1..1024`), untrusted signer, unpinned proof digest, unsigned/forged capability grant, zero generation, zero/expired lease, or missing `RX_RIGHT_EFFECT` right refuses admission.
5. **Honest scope limits (tracked follow-on work):**
   - **Single-source kernel emission & replay:** `emit_kernels.om` currently emits canonical SM121 (`vecadd` SASS + minimal QMD header) and SPIR-V fixtures, hashes domain tags for `source_sha256` / `mlbom_sha256`, and runs a `HOST_REFERENCE` CPU reference oracle for `P3` replay. End-to-end compilation from `om/gpu/bw_vecadd.om` + full QMD v5 + real kernel replay is tracked separately.
   - **Lean 4 proof boundary:** `proofs/UorGpuWorld.lean` machine-checks the algebraic `Nat` vecadd kernel model and the `UOR-GPU-1` policy/admission state machine (22 theorems, zero `sorry`, standard axioms only). It does not prove binary equivalence of emitted SM121 SASS or SPIR-V machine code.
   - **Offline capability revocation:** `prism-gpu admit` checks the authority Ed25519 signature, wall-clock lease expiry (`realns`), non-zero generation/lease, epoch, subject, resource, and `RX_RIGHT_EFFECT`. Live generation-based revocation requires the kernel/memfd `caproot` seqlock (`seed/authority/caproot.om`); offline admission relies on short authority-signed leases.
   - **Hardware status:** Physical GB10 silicon execution is `NOT_RUN`.

## Canonical `UOR-GPU-1` Bundle Header (384 bytes)

| Offset | Size | Field |
|---|---:|---|
| 0 | 8 | Magic `"UORGPU1\0"` |
| 8 | 4 | Version (`1` u32 LE) |
| 12 | 4 | Target ISA (`1=SM121`, `2=SPIRV` u32 LE) |
| 16 | 4 | Math contract (`1=IEEE754_RN`, `2=FTZ` u32 LE) |
| 20 | 4 | Claimed evidence level (`0=P0..3=P3` u32 LE) |
| 24 | 4 | Payload byte length (`u32 LE`, must be `> 0`) |
| 28 | 4 | Launch `block_x` (`u32 LE`, `1..1024`) |
| 32 | 32 | `omc_sha256` (pinned `seed/out/omc` digest) |
| 64 | 32 | `source_sha256` (source identity digest) |
| 96 | 32 | `payload_sha256` (SHA-256 of emitted payload bytes) |
| 128 | 32 | `lean_proof_sha256` (SHA-256 of verified `UorGpuWorld.lean`; pinned for `P2`/`P3`) |
| 160 | 32 | `replay_sha256` (SHA-256 of golden replay vector; checked for `P3`) |
| 192 | 32 | `mlbom_sha256` (ML-BOM digest, PrismPM `#310`) |
| 224 | 32 | `uor_id_sha256` (`SHA-256(header[0..223])`) |
| 256 | 32 | `holo_blake3` (`BLAKE3(header[0..255] || payload[0..payload_len))`) |
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
- `verify.om`: `UORTRST1` local trust anchors validator, `P0..P3` policy verifier, strict RFC 8032 Ed25519 verifier, replay checker, and `prism/verdict/1` + `prism/inspect/1` JSON emitters.
- `gate.om`: Pre-dispatch admission gate combining `verify.om` with authority-signed capability validation (`RX_RIGHT_EFFECT = 4`).
- `emit_kernels.om`: Canonical SM121 (`vecadd` SASS + QMD header) and SPIR-V fixtures, `HOST_REFERENCE` CPU oracle, and trust-anchor builder.
- `ed_sign.om`: Pure seeded OM-2 RFC 8032 Ed25519 key derivation and signing (producer side only; variable-time, never used on the verify path).
- `prism-gpu.om`: Pure seeded-Omega CLI plugin (`keygen|pubkey|trust|bundle|inspect|verify|replay|grant|admit`).
- `uor-gpu-gate.om`: Pure seeded-Omega host gate exercising RFC 8032 Ed25519 sign+verify vectors, SM121+SPIR-V, local trust anchors, authority-signed grants, and 24 negative controls.
- `proofs/UorGpuWorld.lean`: Machine-checked Lean 4 specification (22 theorems, zero `sorry`, standard axioms only).
