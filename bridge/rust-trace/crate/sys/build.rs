#![forbid(unsafe_code)]
//! Fail-closed build script for `omega-trace-sys`.
//! Invokes the pure seeded-Omega `om_lock_gen verify` verifier before archiving
//! and linking the verified ABI v2 native object (`libomega_native.a`).

use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn resolve_work_dir(manifest_dir: &Path) -> PathBuf {
    if let Ok(p) = env::var("OMEGA_TRACE_WORK_DIR") {
        let pb = PathBuf::from(p);
        if pb.is_absolute() {
            return pb;
        }
        return manifest_dir.join(pb);
    }
    manifest_dir.join("../../work")
}

fn resolve_file(env_key: &str, fallback: PathBuf) -> PathBuf {
    if let Ok(v) = env::var(env_key) {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    fallback
}

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let rust_trace_dir = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("crate/sys must sit inside bridge/rust-trace/crate/sys")
        .to_path_buf();
    let repo_root = rust_trace_dir
        .parent()
        .and_then(|p| p.parent())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| rust_trace_dir.clone());

    let work_dir = resolve_work_dir(&manifest_dir);
    let verifier = resolve_file("OMEGA_TRACE_VERIFIER", work_dir.join("om_lock_gen"));
    let lock_file = resolve_file("OMEGA_TRACE_LOCK", work_dir.join("OMEGA_TRACE.lock"));
    let src_om = resolve_file("OMEGA_TRACE_SRC_OM", rust_trace_dir.join("sample_unit.om"));
    let omc_bin = resolve_file("OMEGA_OMC", repo_root.join("seed/out/omc"));
    let egp3_cert = resolve_file("OMEGA_TRACE_EGP3", work_dir.join("sample_unit.egp3"));
    let lean_src = resolve_file(
        "OMEGA_TRACE_LEAN",
        rust_trace_dir.join("proof/TraceBridge.lean"),
    );
    let ompk_pkg = resolve_file("OMEGA_TRACE_OMPK", work_dir.join("sample_unit.ompk"));
    let unit_bin = resolve_file("OMEGA_TRACE_UNIT_BIN", work_dir.join("sample_unit.bin"));
    let native_c = resolve_file(
        "OMEGA_TRACE_NATIVE_C",
        work_dir.join("omega_trace_native.c"),
    );
    let unit_obj = resolve_file(
        "OMEGA_TRACE_UNIT_OBJ",
        work_dir.join("omega_trace_native.o"),
    );

    for env_key in [
        "OMEGA_TRACE_WORK_DIR",
        "OMEGA_TRACE_VERIFIER",
        "OMEGA_TRACE_LOCK",
        "OMEGA_TRACE_SRC_OM",
        "OMEGA_OMC",
        "OMEGA_TRACE_EGP3",
        "OMEGA_TRACE_LEAN",
        "OMEGA_TRACE_OMPK",
        "OMEGA_TRACE_UNIT_BIN",
        "OMEGA_TRACE_NATIVE_C",
        "OMEGA_TRACE_UNIT_OBJ",
    ] {
        println!("cargo:rerun-if-env-changed={env_key}");
    }

    for dep in [
        &verifier, &lock_file, &src_om, &omc_bin, &egp3_cert, &lean_src, &ompk_pkg, &unit_bin,
        &native_c, &unit_obj,
    ] {
        println!("cargo:rerun-if-changed={}", dep.display());
    }

    let output = Command::new(&verifier)
        .arg("verify")
        .arg(&lock_file)
        .arg(&src_om)
        .arg(&omc_bin)
        .arg(&egp3_cert)
        .arg(&lean_src)
        .arg(&ompk_pkg)
        .arg(&unit_bin)
        .arg(&native_c)
        .arg(&unit_obj)
        .output()
        .unwrap_or_else(|e| {
            panic!(
                "FAIL-CLOSED: cannot execute pure-Omega lock verifier `{}`: {e}",
                verifier.display()
            )
        });

    if !output.status.success() {
        let code = output.status.code().unwrap_or(-1);
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!(
            "FAIL-CLOSED: pure-Omega lock verification refused build (exit {code}): {}",
            stderr.trim()
        );
    }

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let archive_path = out_dir.join("libomega_native.a");
    if archive_path.exists() {
        std::fs::remove_file(&archive_path).expect("remove stale libomega_native.a");
    }

    let ar_status = Command::new("ar")
        .arg("rcsD")
        .arg(&archive_path)
        .arg(&unit_obj)
        .status()
        .expect("invoke ar rcsD");
    if !ar_status.success() {
        panic!("ar rcsD failed archiving verified Omega object {}", unit_obj.display());
    }

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=omega_native");
}
