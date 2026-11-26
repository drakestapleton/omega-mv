#![forbid(unsafe_code)]
//! Universal Byte-Traceable Safe Rust FFI Hook over `omega-bridge` ABI v2.
//!
//! Every call site traces cryptographically from:
//!   Rust safe function -> `omega2_<export>` symbol -> `SEMANTIC_ID`/`OMPK` ->
//!   `EGP3` proof cert -> Lean 4 proof source (`TraceBridge.lean`) ->
//!   pinned `omc` compiler SHA-256 -> exact emitted AArch64 machine-code bytes & object.

use std::fmt;
use std::path::PathBuf;
use std::process::Command;

mod manifest_gen {
    include!(concat!(env!("OUT_DIR"), "/trace_manifest_gen.rs"));
}

/// Specific failure class when `om_lock_gen verify` or runtime identity verification
/// detects a 1-bit drift in the cryptographic traceability chain (status `100+`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockDriftKind {
    /// Status `100`: Lockfile missing, unreadable, malformed, or duplicate/missing key.
    MalformedLock,
    /// Status `101`: `.om` source file SHA-256 drifted from lock.
    SourceDrift,
    /// Status `102`: `omc` compiler binary SHA-256 drifted from lock.
    CompilerDrift,
    /// Status `103`: `EGP3` proof certificate format invalid or SHA-256 drifted.
    Egp3ProofDrift,
    /// Status `104`: Lean 4 proof source SHA-256 drifted from lock.
    LeanProofDrift,
    /// Status `105`: `SEMANTIC_ID` or `OMPK` package format/digest drifted from lock.
    SemanticIdDrift,
    /// Status `106`: Emitted machine-code `.bin`, ABI v2 `.c`, or compiled `.o` drifted.
    BinaryDrift,
    /// Status `107`: Linked binary's `omega2_ident_*` differs from locked `OMEGA2_IDENT`.
    IdentDrift,
    /// Status `108`: `CHAIN_ROOT_SHA256` commitment failed (lockfile tampered).
    ChainRootDrift,
    /// Status `109+`: Other lock drift status code.
    Other(u32),
}

impl LockDriftKind {
    pub const fn status_code(self) -> u32 {
        match self {
            Self::MalformedLock => 100,
            Self::SourceDrift => 101,
            Self::CompilerDrift => 102,
            Self::Egp3ProofDrift => 103,
            Self::LeanProofDrift => 104,
            Self::SemanticIdDrift => 105,
            Self::BinaryDrift => 106,
            Self::IdentDrift => 107,
            Self::ChainRootDrift => 108,
            Self::Other(code) => code,
        }
    }

    pub const fn from_code(code: u32) -> Self {
        match code {
            100 => Self::MalformedLock,
            101 => Self::SourceDrift,
            102 => Self::CompilerDrift,
            103 => Self::Egp3ProofDrift,
            104 => Self::LeanProofDrift,
            105 => Self::SemanticIdDrift,
            106 => Self::BinaryDrift,
            107 => Self::IdentDrift,
            108 => Self::ChainRootDrift,
            other => Self::Other(other),
        }
    }
}

/// Complete typed error mapping for `omega-bridge` ABI v2 + fail-closed lock verification.
///
/// Status codes match `docs/NATIVE-ABI.md` and `bridge/omega-bridge/src/native.om`:
/// - `0`: OK (represented by `Ok(T)`)
/// - `1..=14`: Omega runtime/contract traps
/// - `32`: `OMEGA_BAD_ARG` (null pointer, wrong fixed length, misaligned, or aliased spans)
/// - `33`: `OMEGA_REENTRY` (reentrant entry on same thread)
/// - `34`: `OMEGA_BAD_RT` (invalid runtime entry / internal runtime failure)
/// - `35`: `OMEGA_NO_STACK` (failed to map thread Omega stack)
/// - `36`: `OMEGA_CONTEXT_BUSY` (context busy)
/// - `100+`: Fail-closed trace lock / identity drift
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OmegaTrap {
    /// Trap 1: Signed arithmetic overflow (`add`/`sub`/`mul`/`neg`/`div`/`shl`).
    Overflow,
    /// Trap 2: Division or remainder by zero.
    DivByZero,
    /// Trap 3: Array/slice index or host slice out of bounds.
    Bounds,
    /// Trap 4: `while` or `for` exceeded its static/explicit loop bound.
    LoopBound,
    /// Trap 5: Checked integer conversion out of target type range.
    Cast,
    /// Trap 6: Stack exhaustion (OOM).
    Oom,
    /// Trap 7: Shift or rotate amount outside `0..width-1`.
    Shift,
    /// Trap 8: Runtime invariant failure.
    Runtime,
    /// Trap 9: OM-2 `requires` precondition failed.
    Requires,
    /// Trap 10: OM-2 `ensures` / `invariant` / `holds` postcondition failed.
    Ensures,
    /// Trap 11: Arena capacity exceeded.
    ArenaFull,
    /// Trap 12: Stale generation handle.
    Stale,
    /// Trap 13: Pool full.
    PoolFull,
    /// Trap 14: Retired pool slot.
    Retired,
    /// Status 32 (`OMEGA_BAD_ARG`): Null pointer, misaligned, bad fixed length, or overlapping spans.
    InvalidOrAlias,
    /// Status 33 (`OMEGA_REENTRY`): Reentrant call into Omega ABI v2 wrapper.
    Reentry,
    /// Status 34 (`OMEGA_BAD_RT`): Invalid runtime table entry.
    BadRuntime,
    /// Status 35 (`OMEGA_NO_STACK`): Thread Omega stack allocation failed.
    NoStack,
    /// Status 36 (`OMEGA_CONTEXT_BUSY`): Context busy.
    ContextBusy,
    /// Status `100+`: Fail-closed cryptographic trace lock or runtime identity drift.
    LockDrift(LockDriftKind),
    /// Any other unrecognized nonzero ABI status code.
    Unknown(u32),
}

impl OmegaTrap {
    /// Converts a raw ABI v2 / verifier status code into `Result<(), OmegaTrap>`.
    pub const fn from_status(status: u32) -> Result<(), Self> {
        match status {
            0 => Ok(()),
            1 => Err(Self::Overflow),
            2 => Err(Self::DivByZero),
            3 => Err(Self::Bounds),
            4 => Err(Self::LoopBound),
            5 => Err(Self::Cast),
            6 => Err(Self::Oom),
            7 => Err(Self::Shift),
            8 => Err(Self::Runtime),
            9 => Err(Self::Requires),
            10 => Err(Self::Ensures),
            11 => Err(Self::ArenaFull),
            12 => Err(Self::Stale),
            13 => Err(Self::PoolFull),
            14 => Err(Self::Retired),
            32 => Err(Self::InvalidOrAlias),
            33 => Err(Self::Reentry),
            34 => Err(Self::BadRuntime),
            35 => Err(Self::NoStack),
            36 => Err(Self::ContextBusy),
            100.. => Err(Self::LockDrift(LockDriftKind::from_code(status))),
            other => Err(Self::Unknown(other)),
        }
    }

    /// Returns the numeric ABI v2 / verifier status code for this error.
    pub const fn status_code(self) -> u32 {
        match self {
            Self::Overflow => 1,
            Self::DivByZero => 2,
            Self::Bounds => 3,
            Self::LoopBound => 4,
            Self::Cast => 5,
            Self::Oom => 6,
            Self::Shift => 7,
            Self::Runtime => 8,
            Self::Requires => 9,
            Self::Ensures => 10,
            Self::ArenaFull => 11,
            Self::Stale => 12,
            Self::PoolFull => 13,
            Self::Retired => 14,
            Self::InvalidOrAlias => 32,
            Self::Reentry => 33,
            Self::BadRuntime => 34,
            Self::NoStack => 35,
            Self::ContextBusy => 36,
            Self::LockDrift(kind) => kind.status_code(),
            Self::Unknown(code) => code,
        }
    }
}

impl fmt::Display for OmegaTrap {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?} (status={})", self.status_code())
    }
}

impl std::error::Error for OmegaTrap {}

/// Per-symbol cryptographic trace entry mapping a safe Rust function to its exact
/// `omega2_*` ABI v2 symbol, OM-2 export signature, unit name, and `SEMANTIC_ID`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SymbolTrace {
    pub rust_fn: &'static str,
    pub omega2_symbol: &'static str,
    pub om_export: &'static str,
    pub unit_name: &'static str,
    pub semantic_id: &'static str,
}

/// Complete byte-level cryptographic provenance chain pinned at build time by `om_lock_gen`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TraceManifest {
    pub format: &'static str,
    pub unit_name: &'static str,
    pub abi_version: u32,
    pub profile: &'static str,
    pub omega2_ident: &'static str,
    pub source_om_sha256: &'static str,
    pub omc_sha256: &'static str,
    pub egp3_sha256: &'static str,
    pub lean_proof_sha256: &'static str,
    pub semantic_id: &'static str,
    pub ompk_sha256: &'static str,
    pub unit_bin_sha256: &'static str,
    pub unit_bin_bytes: u64,
    pub native_c_sha256: &'static str,
    pub unit_obj_sha256: &'static str,
    pub chain_root_sha256: &'static str,
    pub symbols: &'static [SymbolTrace],
}

const SYMBOL_TRACES: &[SymbolTrace] = &[
    SymbolTrace {
        rust_fn: "omega_trace::trace_fma_acc",
        omega2_symbol: "omega2_trace_fma_acc",
        om_export: "export fn trace_fma_acc a ulong b ulong c ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_checked_div",
        omega2_symbol: "omega2_trace_checked_div",
        om_export: "export fn trace_checked_div num long den long to long",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_contract_scale",
        omega2_symbol: "omega2_trace_contract_scale",
        om_export: "export fn trace_contract_scale x ulong k ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_slice_get",
        omega2_symbol: "omega2_trace_slice_get",
        om_export: "export fn trace_slice_get buf view ulong * idx ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_dot_u64",
        omega2_symbol: "omega2_trace_dot_u64",
        om_export: "export fn trace_dot_u64 a view ulong * b view ulong * to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_transform_inplace",
        omega2_symbol: "omega2_trace_transform_inplace",
        om_export: "export fn trace_transform_inplace dst edit ulong * scale ulong bias ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_loop_probe",
        omega2_symbol: "omega2_trace_loop_probe",
        om_export: "export fn trace_loop_probe n ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_narrow_u8",
        omega2_symbol: "omega2_trace_narrow_u8",
        om_export: "export fn trace_narrow_u8 x ulong to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
    SymbolTrace {
        rust_fn: "omega_trace::trace_digest_out",
        omega2_symbol: "omega2_trace_digest_out",
        om_export: "export fn trace_digest_out src view uchar * digest out uchar 32 to ulong",
        unit_name: manifest_gen::VERIFIED_UNIT_NAME,
        semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    },
];

static MANIFEST: TraceManifest = TraceManifest {
    format: manifest_gen::VERIFIED_FORMAT,
    unit_name: manifest_gen::VERIFIED_UNIT_NAME,
    abi_version: manifest_gen::VERIFIED_ABI_VERSION,
    profile: manifest_gen::VERIFIED_PROFILE,
    omega2_ident: manifest_gen::VERIFIED_OMEGA2_IDENT,
    source_om_sha256: manifest_gen::VERIFIED_SOURCE_OM_SHA256,
    omc_sha256: manifest_gen::VERIFIED_OMC_SHA256,
    egp3_sha256: manifest_gen::VERIFIED_EGP3_SHA256,
    lean_proof_sha256: manifest_gen::VERIFIED_LEAN_PROOF_SHA256,
    semantic_id: manifest_gen::VERIFIED_SEMANTIC_ID,
    ompk_sha256: manifest_gen::VERIFIED_OMPK_SHA256,
    unit_bin_sha256: manifest_gen::VERIFIED_UNIT_BIN_SHA256,
    unit_bin_bytes: manifest_gen::VERIFIED_UNIT_BIN_BYTES,
    native_c_sha256: manifest_gen::VERIFIED_NATIVE_C_SHA256,
    unit_obj_sha256: manifest_gen::VERIFIED_UNIT_OBJ_SHA256,
    chain_root_sha256: manifest_gen::VERIFIED_CHAIN_ROOT_SHA256,
    symbols: SYMBOL_TRACES,
};

/// Returns the full compile-time-verified byte-level SHA-256 chain from Rust call site
/// through `omega2_*` symbol, `SEMANTIC_ID`/`OMPK`, `EGP3`, Lean 4 proof, `omc`, and binary.
pub fn trace_manifest() -> &'static TraceManifest {
    &MANIFEST
}

/// Returns the live identity string returned by `omega2_ident_sample_unit()` inside the
/// linked native Omega binary.
pub fn runtime_omega2_ident() -> &'static str {
    omega_trace_sys::ident_sample_unit()
}

/// Verifies at runtime that the linked native binary's `omega2_ident_sample_unit()`
/// matches the compile-time-verified `OMEGA_TRACE.lock` identity byte-for-byte.
pub fn verify_runtime_ident() -> Result<(), OmegaTrap> {
    if runtime_omega2_ident() == MANIFEST.omega2_ident {
        Ok(())
    } else {
        Err(OmegaTrap::LockDrift(LockDriftKind::IdentDrift))
    }
}

/// Concrete filesystem paths for invoking the pure-Omega `om_lock_gen verify` gate at runtime.
#[derive(Debug, Clone)]
pub struct TraceChainPaths {
    pub verifier: PathBuf,
    pub lock_file: PathBuf,
    pub src_om: PathBuf,
    pub omc_bin: PathBuf,
    pub egp3_cert: PathBuf,
    pub lean_src: PathBuf,
    pub ompk_pkg: PathBuf,
    pub unit_bin: PathBuf,
    pub native_c: PathBuf,
    pub unit_obj: PathBuf,
}

impl TraceChainPaths {
    /// Returns the exact artifact paths that passed `build.rs` verification.
    pub fn default_from_build() -> Self {
        Self {
            verifier: PathBuf::from(manifest_gen::DEFAULT_VERIFIER_PATH),
            lock_file: PathBuf::from(manifest_gen::DEFAULT_LOCK_PATH),
            src_om: PathBuf::from(manifest_gen::DEFAULT_SRC_OM_PATH),
            omc_bin: PathBuf::from(manifest_gen::DEFAULT_OMC_PATH),
            egp3_cert: PathBuf::from(manifest_gen::DEFAULT_EGP3_PATH),
            lean_src: PathBuf::from(manifest_gen::DEFAULT_LEAN_PATH),
            ompk_pkg: PathBuf::from(manifest_gen::DEFAULT_OMPK_PATH),
            unit_bin: PathBuf::from(manifest_gen::DEFAULT_UNIT_BIN_PATH),
            native_c: PathBuf::from(manifest_gen::DEFAULT_NATIVE_C_PATH),
            unit_obj: PathBuf::from(manifest_gen::DEFAULT_UNIT_OBJ_PATH),
        }
    }
}

/// Runs the pure seeded-Omega `om_lock_gen verify` verifier fail-closed on `paths`.
/// Any 1-bit drift in any artifact returns `Err(OmegaTrap::LockDrift(...))` (status `100+`).
pub fn verify_lock_chain(paths: &TraceChainPaths) -> Result<String, OmegaTrap> {
    let output = Command::new(&paths.verifier)
        .arg("verify")
        .arg(&paths.lock_file)
        .arg(&paths.src_om)
        .arg(&paths.omc_bin)
        .arg(&paths.egp3_cert)
        .arg(&paths.lean_src)
        .arg(&paths.ompk_pkg)
        .arg(&paths.unit_bin)
        .arg(&paths.native_c)
        .arg(&paths.unit_obj)
        .output()
        .map_err(|_| OmegaTrap::LockDrift(LockDriftKind::MalformedLock))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        let code = output.status.code().unwrap_or(100) as u32;
        if code >= 100 {
            Err(OmegaTrap::LockDrift(LockDriftKind::from_code(code)))
        } else {
            Err(OmegaTrap::LockDrift(LockDriftKind::MalformedLock))
        }
    }
}

/// Calls `omega2_trace_fma_acc(a, b, c)` -> wrapping `a * b + c`.
pub fn trace_fma_acc(a: u64, b: u64, c: u64) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_fma_acc(a, b, c);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_checked_div(num, den)` -> signed division (Trap 2 on `den==0`, Trap 1 on `i64::MIN / -1`).
pub fn trace_checked_div(num: i64, den: i64) -> Result<i64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_checked_div(num, den);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_contract_scale(x, k)` -> `x * k` guarded by OM-2 `requires` (Trap 9) and `ensures` (Trap 10).
pub fn trace_contract_scale(x: u64, k: u64) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_contract_scale(x, k);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_slice_get(buf, idx)` -> `buf[idx]` (Trap 3 on `idx >= buf.len()`).
pub fn trace_slice_get(buf: &[u64], idx: u64) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_slice_get(buf, idx);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_dot_u64(a, b)` -> wrapping dot product (Trap 9 if `a.len() != b.len()`).
pub fn trace_dot_u64(a: &[u64], b: &[u64]) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_dot_u64(a, b);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_transform_inplace(dst, scale, bias)` -> updates `dst` in-place, returns XOR checksum.
pub fn trace_transform_inplace(dst: &mut [u64], scale: u64, bias: u64) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_transform_inplace(dst, scale, bias);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_loop_probe(n)` -> runs up to `bound 16` (Trap 4 when `n` exceeds bound).
pub fn trace_loop_probe(n: u64) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_loop_probe(n);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Calls `omega2_trace_narrow_u8(x)` -> checked narrowing cast (Trap 5 when `x > 255`).
pub fn trace_narrow_u8(x: u64) -> Result<u8, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_narrow_u8(x);
    OmegaTrap::from_status(status).map(|()| val as u8)
}

/// Calls `omega2_trace_digest_out(src, digest)` -> writes 32-byte folded tag to `digest` ONLY on status 0 (Trap 9 if `src.is_empty()`).
pub fn trace_digest_out(src: &[u8], digest: &mut [u8; 32]) -> Result<u64, OmegaTrap> {
    verify_runtime_ident()?;
    let (status, val) = omega_trace_sys::call_trace_digest_out(src, digest);
    OmegaTrap::from_status(status).map(|()| val)
}

/// Probes ABI v2 null-buffer rejection -> returns `Err(OmegaTrap::InvalidOrAlias)` (status `32`).
pub fn probe_abi_null_arg() -> Result<(), OmegaTrap> {
    verify_runtime_ident()?;
    OmegaTrap::from_status(omega_trace_sys::probe_abi_null_arg())
}

/// Probes ABI v2 overlapping edit/result alias rejection -> returns `Err(OmegaTrap::InvalidOrAlias)` (status `32`).
pub fn probe_abi_aliased_arg() -> Result<(), OmegaTrap> {
    verify_runtime_ident()?;
    OmegaTrap::from_status(omega_trace_sys::probe_abi_aliased_arg())
}
