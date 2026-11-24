# Omega Online Compiler (`om-playground`)

Pure seeded-Omega (`om2`) HTTP server that compiles user-submitted `.om` programs with `seed/out/omc` and executes the resulting static AArch64 Linux ELF inside Omega's built-in `execpure` kernel sandbox.

## Architecture

- **Zero JavaScript:** Standard HTML `<form method="POST">` + CSS (`/omega/compile/play.css`), compatible with `interplane.io`'s `script-src 'none'; style-src 'self'` CSP.
- **Zero shared libraries:** Compiles to a single static AArch64 ELF (`ldd: not a dynamic executable`).
- **Compile sandbox:** `seed/out/omc` runs in a forked child with `RLIMIT_CPU=3s`, `RLIMIT_FSIZE=4 MiB`, `RLIMIT_AS=256 MiB`, and a 4-second wall-clock deadline.
- **Run sandbox (`execpure`):** Every compiled user binary executes under Omega's `execpure` syscall profile — Landlock ABI-3 (read+exec on the binary inode only), `PR_SET_NO_NEW_PRIVS`, seccomp-BPF (only `read(0)`, `write(1)`, `write(2)`, `exit`, `exit_group`, `execveat`), 7 `prlimit64` ceilings (0 child processes, 128 MiB AS, 8 MiB stack, 4 fds), plus a 2-second wall-clock timeout and 16 KiB stdout / 8 KiB stderr caps.

## Build and Run (64-bit Arm Linux)

```sh
seed/out/omc < apps/omega-playground/main.om > om-playground
chmod +x om-playground
./om-playground /path/to/seed/out/omc
```

Listens on `127.0.0.1:18490`.
