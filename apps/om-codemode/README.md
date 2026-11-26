# `om-codemode`: Sub-Millisecond Pure-Omega Pure-Compute Sandbox

`om-codemode` compiles untrusted Omega (`.om`) compute snippets with a SHA-256-pinned seeded `omc` compiler and runs them inside Omega's kernel-enforced `execpure` sandbox — with zero libc, zero Docker/container daemon, zero Python/Node runtime, and sub-millisecond sandbox execution.

## 60-Second Quickstart (Linux AArch64)

```sh
# 1. Build om-codemode from pure seeded OM-2 (single static ELF, zero dependencies)
seed/out/omc < apps/om-codemode/codemode.om > /tmp/om-codemode
chmod +x /tmp/om-codemode

# 2. Write a pure-compute snippet
cat > /tmp/fib10.om << 'EOF'
om2
text msg "fib(10)=55\n"
fn main to int
  a = ulong 0
  b = ulong 1
  for i ulong 10 bound 10
    c = add a b
    a = b
    b = c
  end
  if ne a 55
    ret 1
  end
  x = write 1 msg 0 len msg
  ret 0
end
EOF

# 3. Compile + run in kernel-enforced execpure with SHA-256 compiler pin verification
/tmp/om-codemode run /tmp/fib10.om \
  --omc seed/out/omc \
  --pin-file seed/out/omc.sha256 \
  --timeout-ms 1000
```

You can also pipe a snippet on stdin using `-`:

```sh
/tmp/om-codemode run - --omc seed/out/omc --pin-file seed/out/omc.sha256 < /tmp/fib10.om
```

## Deterministic Structured Receipt

Every run emits a structured, line-oriented receipt followed by redacted stdout/stderr blocks:

```text
CODEMODE_RECEIPT v=1 status=OK sandbox=execpure_aarch64 omc_sha256=<64-hex> snippet_sha256=<64-hex> bin_bytes=<N> compile_us=<N> run_us=<N> exit_code=0 redacted=0 x64_bpf_arch=0xc000003e x64_bpf_insns=27 x64_bpf_sha256=<64-hex>
STDOUT_BEGIN len=11
fib(10)=55
STDOUT_END
STDERR_BEGIN len=0

STDERR_END
```

### Exit Codes

| Exit Code | Receipt `status` | Meaning |
| --- | --- | --- |
| `0` | `OK` | Compiled and ran cleanly in `execpure` with exit 0 |
| `1..30` | `COMPILE_ERROR` | Refused by `omc` with its exact compiler error code (never executed) |
| `69` | `REFUSED` | Fail-closed refusal (missing/mismatched `omc` SHA-256 pin or bad input) |
| `101..114` | `TRAP` | Omega runtime trap `1..14` (e.g., `104` = loop bound exceeded, `108` = `trap 8`) |
| `124` | `TIMEOUT` | Killed by supervisor with `SIGKILL` after `--timeout-ms` wall deadline |
| `128+sig` | `SIGNAL_KILLED` | Terminated by kernel signal `sig` |

## Security Boundaries

1. **Compiler Pin Lock (Fail-Closed):** Streams the `omc` binary through an embedded FIPS 180-4 SHA-256 hasher before spawning anything. Even a 1-bit drift refuses with exit `69`.
2. **Kernel `execpure` Confinement (Linux AArch64):**
   - **Landlock ABI-3:** restricts filesystem access exclusively to read/execute of the single pinned ELF inode (descriptor 3). `fopen("/etc/passwd")` is denied by the kernel (`-EPERM`).
   - **seccomp-BPF stdio-only filter:** allows only `read(0)`, `write(1|2)`, `exit`, `exit_group`, and `execveat(3, AT_EMPTY_PATH)`. Network (`socket`/`connect`) and process creation (`fork`) are blocked by the kernel (`-EPERM`).
   - **7 `prlimit64` ceilings:** `RLIMIT_CPU=1..2s`, `RLIMIT_FSIZE=1MiB`, `RLIMIT_STACK=8MiB`, `RLIMIT_CORE=0`, `RLIMIT_NPROC=0`, `RLIMIT_NOFILE=4`, `RLIMIT_AS=128MiB`.
   - **Supervisor wall-clock timeout:** enforces `--timeout-ms` (default `1000 ms`, configurable `10..10000 ms`) via `pollfds` + `monons` + `killpid(SIGKILL)`.
3. **Output Credential Redaction:** Automatically redacts `Bearer `, `sk-`, `ghp_`, `AKIA`, and `xoxb-` tokens to `[REDACTED]` across both captured stdout and stderr before returning to the caller.
4. **Embedded `x86linux` Cross-Target Seccomp-BPF Policy:** Inspect the verified 27-instruction (216-byte) `AUDIT_ARCH_X86_64` (`0xc000003e`) filter (`read=0`, `write=1`, `exit=60`, `exit_group=231`, `execveat=322`, `SECCOMP_RET_KILL_PROCESS` default) at any time:

```sh
/tmp/om-codemode x64-bpf-spec
```

## Verification Gate

Build and run the pure-Omega verification gate (4 positive suites + 8 fail-closed negative controls):

```sh
seed/out/omc < apps/om-codemode/codemode.om > /tmp/om-codemode && chmod +x /tmp/om-codemode
seed/out/omc < apps/om-codemode/gate_codemode.om > /tmp/gate_codemode && chmod +x /tmp/gate_codemode
/tmp/gate_codemode /tmp/om-codemode seed/out/omc seed/out/omc.sha256
```

## Evidence Status

- **Linux AArch64 (`execpure` live kernel sandbox):** `HOST_VERIFIED` on DGX Spark AArch64 (`gate_codemode`: 12/12 tests, 8/8 negative controls caught).
- **Linux x86-64 (`AUDIT_ARCH_X86_64` BPF spec):** `HOST_VERIFIED` via pure-Omega cBPF VM (`6/6` allowed syscalls, `9/9` disallowed syscalls killed); physical x86-64 kernel `execpure` lowering remains `NOT_RUN` until `omc.om` `x86linux` consumes the embedded BPF policy.
