//! Minimal, isolated raw FFI boundary for `omega-bridge` ABI v2 (`omega2_*`).
//!
//! All public API code lives in the `#![forbid(unsafe_code)]` `omega-trace` crate.
//! This `-sys` crate isolates ONLY the ABI v2 `extern "C"` declarations matching
//! `bridge/omega-bridge/src/native.om` (`rust` output) and safe slice/pointer shims.

use core::ffi::CStr;

pub const OMEGA_OK: u32 = 0;
pub const OMEGA_BAD_ARG: u32 = 32;
pub const OMEGA_REENTRY: u32 = 33;
pub const OMEGA_BAD_RT: u32 = 34;
pub const OMEGA_NO_STACK: u32 = 35;
pub const OMEGA_CONTEXT_BUSY: u32 = 36;

// Signatures match `bridge/omega-bridge/src/native.om rust` byte-for-byte.
// Linked statically from `$OUT_DIR/libomega_native.a` by `sys/build.rs` ONLY
// after `om_lock_gen verify` passes fail-closed.
#[link(name = "omega_native", kind = "static")]
unsafe extern "C" {
    // export fn trace_fma_acc a ulong b ulong c ulong to ulong
    fn omega2_trace_fma_acc(result: *mut u64, o_a: u64, o_b: u64, o_c: u64) -> u32;
    // export fn trace_checked_div num long den long to long
    fn omega2_trace_checked_div(result: *mut u64, o_num: u64, o_den: u64) -> u32;
    // export fn trace_contract_scale x ulong k ulong to ulong
    fn omega2_trace_contract_scale(result: *mut u64, o_x: u64, o_k: u64) -> u32;
    // export fn trace_slice_get buf view ulong * idx ulong to ulong
    fn omega2_trace_slice_get(
        result: *mut u64,
        o_buf: *const u64,
        o_buf_len: u64,
        o_idx: u64,
    ) -> u32;
    // export fn trace_dot_u64 a view ulong * b view ulong * to ulong
    fn omega2_trace_dot_u64(
        result: *mut u64,
        o_a: *const u64,
        o_a_len: u64,
        o_b: *const u64,
        o_b_len: u64,
    ) -> u32;
    // export fn trace_transform_inplace dst edit ulong * scale ulong bias ulong to ulong
    fn omega2_trace_transform_inplace(
        result: *mut u64,
        o_dst: *mut u64,
        o_dst_len: u64,
        o_scale: u64,
        o_bias: u64,
    ) -> u32;
    // export fn trace_loop_probe n ulong to ulong
    fn omega2_trace_loop_probe(result: *mut u64, o_n: u64) -> u32;
    // export fn trace_narrow_u8 x ulong to ulong
    fn omega2_trace_narrow_u8(result: *mut u64, o_x: u64) -> u32;
    // export fn trace_digest_out src view uchar * digest out uchar 32 to ulong
    fn omega2_trace_digest_out(
        result: *mut u64,
        o_src: *const u8,
        o_src_len: u64,
        o_digest: *mut u8,
    ) -> u32;
    fn omega2_ident_sample_unit() -> *const core::ffi::c_char;
}

/// Returns the static ASCII identity string embedded inside the linked ABI v2 object.
pub fn ident_sample_unit() -> &'static str {
    // SAFETY: `omega2_ident_sample_unit` returns a pointer to a static NUL-terminated
    // ASCII C string (`static const char ombr2_ident_sample_unit[]`) emitted by native.om.
    unsafe {
        let ptr = omega2_ident_sample_unit();
        if ptr.is_null() {
            return "";
        }
        CStr::from_ptr(ptr).to_str().unwrap_or("")
    }
}

pub fn call_trace_fma_acc(a: u64, b: u64, c: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `out` is a valid aligned `u64`; pure scalar ABI v2 call.
    let status = unsafe { omega2_trace_fma_acc(&mut out, a, b, c) };
    (status, out)
}

pub fn call_trace_checked_div(num: i64, den: i64) -> (u32, i64) {
    let mut out = 0u64;
    // SAFETY: ABI v2 passes signed `long` as two's-complement `u64` bits.
    let status = unsafe { omega2_trace_checked_div(&mut out, num as u64, den as u64) };
    (status, out as i64)
}

pub fn call_trace_contract_scale(x: u64, k: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `out` is a valid aligned `u64`; pure scalar ABI v2 call.
    let status = unsafe { omega2_trace_contract_scale(&mut out, x, k) };
    (status, out)
}

pub fn call_trace_slice_get(buf: &[u64], idx: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `buf` is valid for `buf.len()` `u64` reads and aligned to 8 bytes.
    // For empty slices `buf.len() == 0`, ABI v2 `ombr2_view` never dereferences `o_buf`.
    let status = unsafe { omega2_trace_slice_get(&mut out, buf.as_ptr(), buf.len() as u64, idx) };
    (status, out)
}

pub fn call_trace_dot_u64(a: &[u64], b: &[u64]) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `a` and `b` are valid read-only `u64` slices disjoint from `out`.
    let status = unsafe {
        omega2_trace_dot_u64(
            &mut out,
            a.as_ptr(),
            a.len() as u64,
            b.as_ptr(),
            b.len() as u64,
        )
    };
    (status, out)
}

pub fn call_trace_transform_inplace(dst: &mut [u64], scale: u64, bias: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `dst` is exclusively borrowed and disjoint from stack-local `out`.
    let status = unsafe {
        omega2_trace_transform_inplace(&mut out, dst.as_mut_ptr(), dst.len() as u64, scale, bias)
    };
    (status, out)
}

pub fn call_trace_loop_probe(n: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `out` is a valid aligned `u64`; pure scalar ABI v2 call.
    let status = unsafe { omega2_trace_loop_probe(&mut out, n) };
    (status, out)
}

pub fn call_trace_narrow_u8(x: u64) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `out` is a valid aligned `u64`; pure scalar ABI v2 call.
    let status = unsafe { omega2_trace_narrow_u8(&mut out, x) };
    (status, out)
}

pub fn call_trace_digest_out(src: &[u8], digest: &mut [u8; 32]) -> (u32, u64) {
    let mut out = 0u64;
    // SAFETY: `src` is valid for `src.len()` reads; `digest` is a 32-byte writable out buffer
    // copied by ABI v2 `ombr2_run` ONLY when status == OMEGA_OK.
    let status = unsafe {
        omega2_trace_digest_out(&mut out, src.as_ptr(), src.len() as u64, digest.as_mut_ptr())
    };
    (status, out)
}

/// Safe defensive probe exercising ABI v2 null-pointer refusal (`OMEGA_BAD_ARG == 32`).
pub fn probe_abi_null_arg() -> u32 {
    let mut out = 0u64;
    // SAFETY: ABI v2 `ombr2_view` checks `!p` when `n > 0` and returns `OMEGA_BAD_ARG` (32)
    // before ever dereferencing the pointer or entering Omega machine code.
    unsafe { omega2_trace_slice_get(&mut out, core::ptr::null(), 4, 0) }
}

/// Safe defensive probe exercising ABI v2 edit/result alias refusal (`OMEGA_BAD_ARG == 32`).
pub fn probe_abi_aliased_arg() -> u32 {
    let mut buf = [1u64, 2, 3, 4];
    let ptr = buf.as_mut_ptr();
    // SAFETY: Passing `ptr` as both `result` and `o_dst` triggers `ombr2_overlap` in the
    // ABI v2 wrapper, returning `OMEGA_BAD_ARG` (32) without entering Omega machine code
    // or mutating `buf`.
    unsafe { omega2_trace_transform_inplace(ptr, ptr, buf.len() as u64, 2, 1) }
}
