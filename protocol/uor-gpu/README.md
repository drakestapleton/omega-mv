# `protocol/uor-gpu` — Pure Seeded-Omega UOR / Prism GPU Extension

Extends the **UOR Foundation / Prism SDK** (`uor.foundation`) to verifiable, content-addressed GPU execution implemented **100% in pure seeded Omega (`.om`)** compiled by `seed/out/omc`, with **mandatory Lean 4 proofs** (`P2` default policy) and **zero CUDApp**.

## Founding Doctrine Alignment

1. **Identity from canonical bytes:** Every GPU artifact carries both a `uor-addr` **SHA-256** canonical ID (`om/tls/sha2.om`) and a `.holo` **BLAKE3** bundle fingerprint (`om/blake3/b3unit.om`). No host path, driver handle, PCI slot, or central registry participates in identity.
2. **No central authority:** Canonicalization, hashing, Lean 4 verification, seeded `omc` compilation, and pre-dispatch admission all run offline and locally.
3. **One model → Lean 4 proof + GPU artifact:** Lean 4 (`proofs/UorGpuWorld.lean`, zero `sorry`, standard axioms only) is **mandatory** under default `P2` policy.
4. **Fail closed before GPU submission:** Any 1-byte tamper in kernel payload, math contract, compiler pin, Lean proof digest, or `.holo` seal refuses admission before dispatch.

## World: `hologram:gpu/omega-om2@1`

- **Allowed targets:** `1 = SM121` (Blackwell via `om/gpu/bw_vecadd.om` + `om/gpu/bw_qmd.om`), `2 = SPIRV` (portable OpenCL SPIR-V via `gpu/spirv/emit.om`).
- **Math contracts:** `1 = IEEE754_RN`, `2 = IEEE754_FTZ`.
- **Evidence levels:**
  - `P0` (0): digest-verified only (refused by default policy)
  - `P1` (1): pinned `seed/out/omc` build record (refused by default policy)
  - `P2` (2, **default minimum**): `P1` + mandatory Lean 4 proof digest (`lean_proof_sha256 != 0`)
  - `P3` (3): `P2` + deterministic replay digest (`replay_sha256 != 0`; `HOST_ORACLE` on CPU/host, `SILICON_GB10` only from an authorized Spark GPU window)

## Canonical `UOR-GPU-1` Bundle Header (384 bytes)

| Offset | Size | Field |
|---|---:|---|
| 0 | 8 | Magic `"UORGPU1\0"` |
| 8 | 4 | Version (`1` u32 LE) |
| 12 | 4 | Target ISA (`1=SM121`, `2=SPIRV` u32 LE) |
| 16 | 4 | Math contract (`1=IEEE754_RN`, `2=FTZ` u32 LE) |
| 20 | 4 | Evidence level (`0=P0..3=P3` u32 LE) |
| 24 | 4 | Payload byte length (`u32 LE`) |
| 28 | 4 | Launch `block_x` (`u32 LE`) |
| 32 | 32 | `omc_sha256` (pinned `seed/out/omc` digest) |
| 64 | 32 | `source_sha256` (canonical `.om` source UOR address) |
| 96 | 32 | `payload_sha256` (emitted SM121 SASS+QMD or SPIR-V bytes UOR address) |
| 128 | 32 | `lean_proof_sha256` (SHA-256 of verified Lean 4 proof; mandatory for `P2`/`P3`) |
| 160 | 32 | `replay_sha256` (SHA-256 of golden replay vectors; mandatory for `P3`) |
| 192 | 32 | `mlbom_sha256` (ML-BOM weight/input slab digest, PrismPM `#310`) |
| 224 | 32 | `uor_id_sha256` (`SHA-256(header[0..223])`) |
| 256 | 32 | `holo_blake3` (`BLAKE3(header[0..255] || payload[0..payload_len))`) |
| 288 | 32 | `signer_pubkey` (RFC 8032 Ed25519 public key; all-zero = unsigned) |
| 320 | 64 | `attest_sig` (RFC 8032 Ed25519 signature over `header[224..287]`) |

## Units

- `canonical.om`: Canonical 384-byte `UOR-GPU-1` codec, `SHA-256` + `BLAKE3` sealer/checker.
- `verify.om`: Prism `P0..P3` policy verifier (default `minimum = P2` requiring Lean 4 proof), strict RFC 8032 Ed25519 verifier (`protocol/omnet/om/ed25519/ed25519.om`), replay checker, and `prism/verdict/1` + `prism/inspect/1` JSON emitters.
- `gate.om`: Pre-dispatch admission gate combining `verify.om` with capability validation (`RX_RIGHT_EFFECT = 4`).
- `emit_kernels.om`: Shared Blackwell SM121 (`vecadd` SASS + QMD) and SPIR-V kernel emitters, ML-BOM digest, and golden CPU replay oracle.
- `prism-gpu.om`: Full pure seeded-Omega CLI plugin (`prism-gpu bundle|inspect|verify|replay|admit`).
- `uor-gpu-gate.om`: Pure seeded-Omega host gate exercising SM121+QMD, SPIR-V, Ed25519 RFC 8032, golden replay, and 10 negative controls.
