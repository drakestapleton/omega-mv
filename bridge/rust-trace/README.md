# bridge/rust-trace: Universal Byte-Traceable Rust FFI Hook

Connects `#![forbid(unsafe_code)]` Rust callers directly to compiled pure seeded-Omega (`OM-2`) function-mode units over `omega-bridge` ABI v2 (`omega2_*`), pinning 100% byte-level cryptographic traceability end-to-end:

```
Rust safe call site (`omega_trace::*`, #![forbid(unsafe_code)])
  -> `omega2_*` ABI v2 symbol (`bridge/omega-bridge/src/native.om`)
  -> `OMEGA2_IDENT` (runtime + compile-time verified `unit/src/omc`)
  -> `SEMANTIC_ID` / `OMPK` v1 semantic package (`om_lock_gen.om`)
  -> `EGP3` structural rewrite proof certificate (Rule 1: `add(mul(a,b), c) = fma(a,b,c)`)
  -> Lean 4 theorem source (`proof/TraceBridge.lean`, 0 sorry)
  -> pinned `omc` compiler SHA-256
  -> exact emitted AArch64 machine-code bytes (`sample_unit.bin`), ABI v2 bridge (`.c`), and ELF object (`.o`)
  -> `CHAIN_ROOT_SHA256` commitment in `OMEGA_TRACE.lock`
```

## Layout

- `om_lock_gen.om`: Pure seeded OM-2 streaming SHA-256 lock generator & fail-closed verifier (`emit-artifacts`, `generate`, `verify`).
- `sample_unit.om`: Pure seeded OM-2 function-mode unit exercising contracts (`requires`/`ensures`), division/overflow traps, slice bounds, loop bounds, narrowing casts, `edit ulong *`, and `out uchar 32` isolation.
- `proof/TraceBridge.lean`: Machine-checked Lean 4 soundness proof (`0 sorry`, standard axioms only).
- `crate/`: Public `#![forbid(unsafe_code)]` safe Rust crate (`omega-trace`, zero crates.io dependencies) with `build.rs` fail-closed lock verification, `OmegaTrap` (`0`, `1..14`, `32..36`, `100+`), `trace_manifest()`, and integration suite `tests/trace_parity.rs`.
- `crate/sys/`: Minimal auditable `-sys` crate (`omega-trace-sys`, zero crates.io dependencies) isolating the `omega-bridge` ABI v2 `extern "C"` declarations and fail-closed static archive linking.
- `gate_rust_trace.sh`: End-to-end verification gate executed on DGX Spark (Linux AArch64).

## Status & Lock-Drift Codes

| Code | `OmegaTrap` variant | Meaning |
| --- | --- | --- |
| `0` | `Ok(T)` | Normal return |
| `1..14` | `Overflow..Retired` | Omega runtime / contract trap (`requires=9`, `ensures=10`, `div0=2`, `bounds=3`, `loop_bound=4`, `cast=5`) |
| `32` | `InvalidOrAlias` | `OMEGA_BAD_ARG` (null pointer, wrong length, misaligned, or overlapping spans) |
| `33` | `Reentry` | `OMEGA_REENTRY` |
| `34..36` | `BadRuntime` / `NoStack` / `ContextBusy` | ABI v2 runtime errors |
| `100` | `LockDrift(MalformedLock)` | Lock missing, unreadable, malformed, or missing/duplicate key |
| `101` | `LockDrift(SourceDrift)` | 1-bit drift in `.om` source |
| `102` | `LockDrift(CompilerDrift)` | 1-bit drift in `omc` binary |
| `103` | `LockDrift(Egp3ProofDrift)` | Invalid `EGP3` format or 1-bit drift |
| `104` | `LockDrift(LeanProofDrift)` | 1-bit drift in Lean 4 proof source |
| `105` | `LockDrift(SemanticIdDrift)` | Invalid `OMPK` format/internal digest or 1-bit drift |
| `106` | `LockDrift(BinaryDrift)` | 1-bit drift in `.bin`, ABI v2 `.c`, or compiled `.o` |
| `107` | `LockDrift(IdentDrift)` | `OMEGA2_IDENT` mismatch |
| `108` | `LockDrift(ChainRootDrift)` | `CHAIN_ROOT_SHA256` lockfile tamper |

## Verification (DGX Spark)

```sh
sh bridge/rust-trace/gate_rust_trace.sh
```
