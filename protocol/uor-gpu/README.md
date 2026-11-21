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

## Canonical `UOR-GPU-1` Bundle Header (256 bytes)

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
| 96 | 32 | `payload_sha256` (emitted SM121/SPIR-V bytes UOR address) |
| 128 | 32 | `lean_proof_sha256` (SHA-256 of verified Lean 4 proof; mandatory for `P2`/`P3`) |
| 160 | 32 | `replay_sha256` (SHA-256 of golden replay vectors; mandatory for `P3`) |
| 192 | 32 | `uor_id_sha256` (`SHA-256(header[0..191])`) |
| 224 | 32 | `holo_blake3` (`BLAKE3(header[0..223] || payload[0..payload_len))`) |

## Units

- `canonical.om`: Canonical `UOR-GPU-1` codec, `SHA-256` + `BLAKE3` sealer/checker.
- `verify.om`: Prism `P0..P3` policy verifier (default `minimum = P2` requiring Lean 4 proof) and `prism/verdict/1` JSON emitter.
- `gate.om`: Pre-dispatch admission gate combining `verify.om` with capability validation (`RX_RIGHT_EFFECT = 4`).
- `prism-gpu.om`: Pure seeded-Omega CLI plugin (`prism-gpu verify|inspect <bundle.holo>`).
- `uor-gpu-gate.om`: Pure seeded-Omega host gate exercising SM121 + SPIR-V bundling, determinism, golden replay, and tamper/policy/capability negative controls.
