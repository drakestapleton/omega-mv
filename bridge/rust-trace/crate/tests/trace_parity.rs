#![forbid(unsafe_code)]
//! Integration tests proving:
//!   (a) Bit-exact Rust <-> Omega parity across all exported ABI v2 symbols
//!   (b) Real Omega traps (1..14) + ABI v2 invalid/alias (32) + out-buffer isolation
//!       surface cleanly as `Err(OmegaTrap::...)` with zero UB/crash
//!   (c) 1-bit tamper in source, compiler, EGP3 proof, Lean 4 proof, OMPK/SEMANTIC_ID,
//!       compiled machine code/object, or lockfile causes fail-closed refusal (`100+`).

use omega_trace::{
    probe_abi_aliased_arg, probe_abi_null_arg, runtime_omega2_ident, trace_checked_div,
    trace_contract_scale, trace_digest_out, trace_dot_u64, trace_fma_acc, trace_loop_probe,
    trace_manifest, trace_narrow_u8, trace_slice_get, trace_transform_inplace, verify_lock_chain,
    verify_runtime_ident, LockDriftKind, OmegaTrap, TraceChainPaths,
};
use std::fs;
use std::path::{Path, PathBuf};

fn is_lower_hex64(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

fn ref_digest_out(src: &[u8]) -> [u8; 32] {
    let mut s0: u64 = 0x6a09e667f3bcc908;
    let mut s1: u64 = 0xbb67ae8584caa73b;
    let mut s2: u64 = 0x3c6ef372fe94f82b;
    let mut s3: u64 = 0xa54ff53a5f1d36f1;
    for (i, &byte) in src.iter().enumerate() {
        let b = byte as u64;
        s0 = s0
            .wrapping_add(b)
            .rotate_right(7)
            ^ b.wrapping_add(1).wrapping_mul(0x9e3779b97f4a7c15);
        s1 = (s1 ^ s0)
            .rotate_left(11)
            .wrapping_add((i as u64).wrapping_add(1).wrapping_mul(0xbf58476d1ce4e5b9));
        s2 = s2
            .wrapping_add(s1)
            .rotate_right(17)
            ^ b.wrapping_add(3).wrapping_mul(0x94d049bb133111eb);
        s3 = (s3 ^ s2).rotate_left(23).wrapping_add(s0);
    }
    let mut out = [0u8; 32];
    out[0..8].copy_from_slice(&s0.to_le_bytes());
    out[8..16].copy_from_slice(&s1.to_le_bytes());
    out[16..24].copy_from_slice(&s2.to_le_bytes());
    out[24..32].copy_from_slice(&s3.to_le_bytes());
    out
}

#[test]
fn test_trace_manifest_completeness_and_runtime_ident() {
    let m = trace_manifest();
    assert_eq!(m.format, "OMEGA_TRACE_LOCK_V1");
    assert_eq!(m.unit_name, "sample_unit");
    assert_eq!(m.abi_version, 2);
    assert_eq!(m.profile, "OM-2");
    assert!(is_lower_hex64(m.source_om_sha256));
    assert!(is_lower_hex64(m.omc_sha256));
    assert!(is_lower_hex64(m.egp3_sha256));
    assert!(is_lower_hex64(m.lean_proof_sha256));
    assert!(is_lower_hex64(m.semantic_id));
    assert!(is_lower_hex64(m.ompk_sha256));
    assert!(is_lower_hex64(m.unit_bin_sha256));
    assert!(m.unit_bin_bytes > 0);
    assert!(is_lower_hex64(m.native_c_sha256));
    assert!(is_lower_hex64(m.unit_obj_sha256));
    assert!(is_lower_hex64(m.chain_root_sha256));

    // SEMANTIC_ID binds directly to canonical source payload inside OMPK.
    assert_eq!(m.semantic_id, m.source_om_sha256);

    // OMEGA2_IDENT in lock and inside linked native binary match byte-for-byte.
    let expected_ident = format!(
        "omega-ident 1 unit={} abi=2 profile=OM-2 src={} omc={}",
        m.unit_name, m.source_om_sha256, m.omc_sha256
    );
    assert_eq!(m.omega2_ident, expected_ident);
    assert_eq!(runtime_omega2_ident(), expected_ident);
    assert_eq!(verify_runtime_ident(), Ok(()));

    // Every exposed safe Rust call site maps cleanly to an `omega2_` symbol + SEMANTIC_ID.
    assert_eq!(m.symbols.len(), 9);
    for sym in m.symbols {
        assert!(sym.rust_fn.starts_with("omega_trace::"));
        assert!(sym.omega2_symbol.starts_with("omega2_"));
        assert_eq!(sym.unit_name, m.unit_name);
        assert_eq!(sym.semantic_id, m.semantic_id);
    }

    // Re-running pure-Omega lock verifier against live paths succeeds.
    let msg = verify_lock_chain(&TraceChainPaths::default_from_build())
        .expect("verified build chain must pass live om_lock_gen verify");
    assert!(msg.starts_with("OMEGA_TRACE_VERIFY PASS unit=sample_unit chain_root="));
    assert!(msg.ends_with(m.chain_root_sha256));
}

#[test]
fn test_bit_exact_rust_omega_parity() {
    // 1. trace_fma_acc (wrapping 64-bit FMA, mirrors EGP3 Rule 1 + TraceBridge.lean)
    let fma_cases = [
        (0u64, 0u64, 0u64),
        (7, 13, 19),
        (u64::MAX, 1, 1),
        (u64::MAX, u64::MAX, u64::MAX),
        (0x1234_5678_9abc_def0, 0xfedc_ba98_7654_3211, 0xdead_beef_cafe_babe),
    ];
    for (a, b, c) in fma_cases {
        let expected = a.wrapping_mul(b).wrapping_add(c);
        assert_eq!(trace_fma_acc(a, b, c), Ok(expected));
    }

    // 2. trace_checked_div (signed i64 division toward zero)
    let div_cases = [
        (0i64, 1i64),
        (42, 7),
        (-42, 7),
        (42, -7),
        (-42, -7),
        (-17, 5),
        (i64::MIN, 2),
        (i64::MAX, -1),
    ];
    for (num, den) in div_cases {
        assert_eq!(trace_checked_div(num, den), Ok(num / den));
    }

    // 3. trace_contract_scale (valid preconditions & non-wrapping postcondition)
    assert_eq!(trace_contract_scale(0, 1), Ok(0));
    assert_eq!(trace_contract_scale(12345, 1), Ok(12345));
    assert_eq!(trace_contract_scale(12345, 1024), Ok(12345 * 1024));

    // 4. trace_slice_get
    let arr = [10u64, 20, 30, 0xfeed_face_cafebeef];
    for (i, &val) in arr.iter().enumerate() {
        assert_eq!(trace_slice_get(&arr, i as u64), Ok(val));
    }

    // 5. trace_dot_u64 (empty + multi-element with wrapping)
    assert_eq!(trace_dot_u64(&[], &[]), Ok(0));
    let a: Vec<u64> = (0..128)
        .map(|i| (i as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15))
        .collect();
    let b: Vec<u64> = (0..128)
        .map(|i| (i as u64).wrapping_add(3).wrapping_mul(0xbf58_476d_1ce4_e5b9))
        .collect();
    let expected_dot = a
        .iter()
        .zip(b.iter())
        .fold(0u64, |acc, (&x, &y)| acc.wrapping_add(x.wrapping_mul(y)));
    assert_eq!(trace_dot_u64(&a, &b), Ok(expected_dot));

    // 6. trace_transform_inplace (empty + mutable slice update + XOR checksum)
    let mut empty: [u64; 0] = [];
    assert_eq!(trace_transform_inplace(&mut empty, 5, 7), Ok(0));

    let mut om_buf = vec![0u64, 1, 2, 17, u64::MAX, 0x0123_4567_89ab_cdef];
    let mut rust_buf = om_buf.clone();
    let scale = 0x1000_0000_0000_0003u64;
    let bias = 0x5555_aaaa_1111_9999u64;
    let mut rust_chk = 0u64;
    for slot in &mut rust_buf {
        *slot = slot.wrapping_mul(scale).wrapping_add(bias);
        rust_chk ^= *slot;
    }
    let om_chk = trace_transform_inplace(&mut om_buf, scale, bias).expect("inplace ok");
    assert_eq!(om_chk, rust_chk);
    assert_eq!(om_buf, rust_buf);

    // 7. trace_loop_probe (strictly within bound 16)
    for n in [0u64, 1, 7, 15] {
        assert_eq!(trace_loop_probe(n), Ok(n));
    }

    // 8. trace_narrow_u8
    for x in [0u64, 1, 127, 255] {
        assert_eq!(trace_narrow_u8(x), Ok(x as u8));
    }

    // 9. trace_digest_out (bit-exact 32-byte out buffer parity)
    for payload in [
        b"A".as_slice(),
        b"omega-bridge ABI v2 byte-traceable FFI".as_slice(),
        &(0u8..=255).collect::<Vec<u8>>()[..],
    ] {
        let mut got = [0u8; 32];
        let n = trace_digest_out(payload, &mut got).expect("digest ok");
        assert_eq!(n, payload.len() as u64);
        assert_eq!(got, ref_digest_out(payload));
    }
}

#[test]
fn test_omega_traps_and_abi_errors_surface_safely() {
    // Trap 1: OVERFLOW (i64::MIN / -1)
    assert_eq!(trace_checked_div(i64::MIN, -1), Err(OmegaTrap::Overflow));

    // Trap 2: DIV0
    assert_eq!(trace_checked_div(42, 0), Err(OmegaTrap::DivByZero));
    assert_eq!(trace_checked_div(0, 0), Err(OmegaTrap::DivByZero));

    // Trap 3: BOUNDS
    assert_eq!(trace_slice_get(&[1, 2, 3], 3), Err(OmegaTrap::Bounds));
    assert_eq!(trace_slice_get(&[1, 2, 3], u64::MAX), Err(OmegaTrap::Bounds));
    assert_eq!(trace_slice_get(&[], 0), Err(OmegaTrap::Bounds));

    // Trap 4: LOOP_BOUND
    assert_eq!(trace_loop_probe(20), Err(OmegaTrap::LoopBound));

    // Trap 5: CAST
    assert_eq!(trace_narrow_u8(256), Err(OmegaTrap::Cast));
    assert_eq!(trace_narrow_u8(u64::MAX), Err(OmegaTrap::Cast));

    // Trap 9: REQUIRES (OM-2 precondition)
    assert_eq!(trace_contract_scale(10, 0), Err(OmegaTrap::Requires));
    assert_eq!(trace_contract_scale(10, 1025), Err(OmegaTrap::Requires));
    assert_eq!(trace_dot_u64(&[1, 2], &[1]), Err(OmegaTrap::Requires));

    // Trap 10: ENSURES (OM-2 postcondition violated on wrapping overflow: u64::MAX * 2 < u64::MAX)
    assert_eq!(trace_contract_scale(u64::MAX, 2), Err(OmegaTrap::Ensures));

    // ABI v2 out-buffer isolation: caller buffer MUST remain byte-identical after a trap!
    let mut sentinel = [0xA5u8; 32];
    assert_eq!(trace_digest_out(&[], &mut sentinel), Err(OmegaTrap::Requires));
    assert_eq!(sentinel, [0xA5u8; 32]);

    // Status 32: OMEGA_BAD_ARG (null pointer & aliased result/edit span)
    assert_eq!(probe_abi_null_arg(), Err(OmegaTrap::InvalidOrAlias));
    assert_eq!(probe_abi_aliased_arg(), Err(OmegaTrap::InvalidOrAlias));

    // Verify ABI status mapping covers every status code (0, 1..=14, 32..=36, 100..=108).
    assert_eq!(OmegaTrap::from_status(0), Ok(()));
    for code in 1..=14 {
        let err = OmegaTrap::from_status(code).unwrap_err();
        assert_eq!(err.status_code(), code);
    }
    assert_eq!(OmegaTrap::from_status(32), Err(OmegaTrap::InvalidOrAlias));
    assert_eq!(OmegaTrap::from_status(33), Err(OmegaTrap::Reentry));
    assert_eq!(OmegaTrap::from_status(34), Err(OmegaTrap::BadRuntime));
    assert_eq!(OmegaTrap::from_status(35), Err(OmegaTrap::NoStack));
    assert_eq!(OmegaTrap::from_status(36), Err(OmegaTrap::ContextBusy));
    for code in 100..=108 {
        let err = OmegaTrap::from_status(code).unwrap_err();
        assert_eq!(err.status_code(), code);
        assert!(matches!(err, OmegaTrap::LockDrift(_)));
    }

    // Recovery after traps: subsequent normal calls work cleanly (ombr_active cleared, stack intact).
    assert_eq!(trace_fma_acc(11, 13, 17), Ok(160));
    assert_eq!(trace_checked_div(100, 4), Ok(25));
}

fn clone_chain_to(dir: &Path, src: &TraceChainPaths) -> TraceChainPaths {
    fs::create_dir_all(dir).expect("create temp tamper dir");
    let copy_one = |p: &Path, name: &str| -> PathBuf {
        let dst = dir.join(name);
        fs::copy(p, &dst).unwrap_or_else(|e| panic!("copy {} -> {}: {e}", p.display(), dst.display()));
        dst
    };
    TraceChainPaths {
        verifier: src.verifier.clone(),
        lock_file: copy_one(&src.lock_file, "OMEGA_TRACE.lock"),
        src_om: copy_one(&src.src_om, "sample_unit.om"),
        omc_bin: copy_one(&src.omc_bin, "omc"),
        egp3_cert: copy_one(&src.egp3_cert, "sample_unit.egp3"),
        lean_src: copy_one(&src.lean_src, "TraceBridge.lean"),
        ompk_pkg: copy_one(&src.ompk_pkg, "sample_unit.ompk"),
        unit_bin: copy_one(&src.unit_bin, "sample_unit.bin"),
        native_c: copy_one(&src.native_c, "omega_trace_native.c"),
        unit_obj: copy_one(&src.unit_obj, "omega_trace_native.o"),
    }
}

fn flip_one_bit(path: &Path, byte_offset: usize) {
    let mut data = fs::read(path).expect("read tamper target");
    assert!(byte_offset < data.len());
    data[byte_offset] ^= 0x01;
    fs::write(path, data).expect("write tampered target");
}

#[test]
fn test_one_bit_tamper_in_every_chain_link_fails_closed() {
    let base = TraceChainPaths::default_from_build();
    let root = std::env::temp_dir().join(format!("omega_trace_tamper_{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);

    // Baseline intact copy passes.
    let intact = clone_chain_to(&root.join("intact"), &base);
    assert!(verify_lock_chain(&intact).is_ok());

    // 1. 1-bit flip in .om source -> SourceDrift (101)
    let c_src = clone_chain_to(&root.join("t_src"), &base);
    flip_one_bit(&c_src.src_om, 12);
    assert_eq!(
        verify_lock_chain(&c_src),
        Err(OmegaTrap::LockDrift(LockDriftKind::SourceDrift))
    );

    // 2. 1-bit flip in omc compiler binary -> CompilerDrift (102)
    let c_omc = clone_chain_to(&root.join("t_omc"), &base);
    flip_one_bit(&c_omc.omc_bin, 64);
    assert_eq!(
        verify_lock_chain(&c_omc),
        Err(OmegaTrap::LockDrift(LockDriftKind::CompilerDrift))
    );

    // 3. 1-bit flip in EGP3 proof certificate -> Egp3ProofDrift (103)
    let c_egp3 = clone_chain_to(&root.join("t_egp3"), &base);
    flip_one_bit(&c_egp3.egp3_cert, 40);
    assert_eq!(
        verify_lock_chain(&c_egp3),
        Err(OmegaTrap::LockDrift(LockDriftKind::Egp3ProofDrift))
    );

    // 4. 1-bit flip in Lean 4 proof source -> LeanProofDrift (104)
    let c_lean = clone_chain_to(&root.join("t_lean"), &base);
    flip_one_bit(&c_lean.lean_src, 32);
    assert_eq!(
        verify_lock_chain(&c_lean),
        Err(OmegaTrap::LockDrift(LockDriftKind::LeanProofDrift))
    );

    // 5. 1-bit flip in OMPK semantic package -> SemanticIdDrift (105)
    let c_ompk = clone_chain_to(&root.join("t_ompk"), &base);
    flip_one_bit(&c_ompk.ompk_pkg, 140);
    assert_eq!(
        verify_lock_chain(&c_ompk),
        Err(OmegaTrap::LockDrift(LockDriftKind::SemanticIdDrift))
    );

    // 6. 1-bit flip in raw emitted machine code (.bin) -> BinaryDrift (106)
    let c_bin = clone_chain_to(&root.join("t_bin"), &base);
    flip_one_bit(&c_bin.unit_bin, 16);
    assert_eq!(
        verify_lock_chain(&c_bin),
        Err(OmegaTrap::LockDrift(LockDriftKind::BinaryDrift))
    );

    // 7. 1-bit flip in generated ABI v2 C bridge -> BinaryDrift (106)
    let c_natc = clone_chain_to(&root.join("t_natc"), &base);
    flip_one_bit(&c_natc.native_c, 64);
    assert_eq!(
        verify_lock_chain(&c_natc),
        Err(OmegaTrap::LockDrift(LockDriftKind::BinaryDrift))
    );

    // 8. 1-bit flip in compiled ELF object (.o) -> BinaryDrift (106)
    let c_obj = clone_chain_to(&root.join("t_obj"), &base);
    flip_one_bit(&c_obj.unit_obj, 64);
    assert_eq!(
        verify_lock_chain(&c_obj),
        Err(OmegaTrap::LockDrift(LockDriftKind::BinaryDrift))
    );

    // 9. Valid-hex edit inside OMEGA_TRACE.lock -> ChainRootDrift (108)
    let c_lock = clone_chain_to(&root.join("t_lock"), &base);
    let mut lock_txt = fs::read_to_string(&c_lock.lock_file).expect("read lock");
    let marker = "EGP3_SHA256=";
    let pos = lock_txt.find(marker).expect("EGP3_SHA256 marker") + marker.len();
    let replacement = if lock_txt.as_bytes()[pos] == b'0' { "1" } else { "0" };
    lock_txt.replace_range(pos..pos + 1, replacement);
    fs::write(&c_lock.lock_file, lock_txt).expect("write tampered lock");
    assert_eq!(
        verify_lock_chain(&c_lock),
        Err(OmegaTrap::LockDrift(LockDriftKind::ChainRootDrift))
    );

    // 10. Truncated/malformed lockfile -> MalformedLock (100)
    let c_mal = clone_chain_to(&root.join("t_mal"), &base);
    fs::write(&c_mal.lock_file, "FORMAT=OMEGA_TRACE_LOCK_V1\n").expect("write malformed lock");
    assert_eq!(
        verify_lock_chain(&c_mal),
        Err(OmegaTrap::LockDrift(LockDriftKind::MalformedLock))
    );

    let _ = fs::remove_dir_all(&root);
}
