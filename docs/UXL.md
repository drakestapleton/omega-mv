# UXL checks

One command, from a fresh clone. It prints each stage as it runs and writes `uxl-run-<host>-<UTC>.log`.

```sh
git clone https://interplane.io/drakestapleton/omega-mv.git && cd omega-mv && ./uxl-run.sh
```

PowerShell. If the default execution policy refuses the script, use the Bypass form.

```powershell
git clone https://interplane.io/drakestapleton/omega-mv.git; cd omega-mv; .\uxl-run.ps1
```

```powershell
git clone https://interplane.io/drakestapleton/omega-mv.git; cd omega-mv; powershell -ExecutionPolicy Bypass -File .\uxl-run.ps1
```

Same work, without the wrapper: `python3 tools/uxl/run_all.py` (Windows: `py tools\uxl\run_all.py`). Python 3.8 or newer, standard library only.

The run prints the OS, architecture, Python, `git core.autocrlf`, whether `qemu-aarch64` binfmt can run `seed/out/omc`, and whether an Intel GPU and OpenCL runtime are present. It does not require the GPU. Level 1 checks the published 65-file record under `tools/uxl/level1/` (path comparison uses `as_posix()`). Level 2 rebuilds the launcher and the 18 gfx942 kernels with `seed/out/omc` and compares them to `gpu/amd/card.tsv`. Those receipt hashes are the ones in the brief: `launch-x86` and `vadd` match Zenodo record 10.5281/zenodo.24237047. On x86 the arm64-only `trace.c` instruments are skipped, not passed. `omc` runs natively on arm64 Linux and through qemu-aarch64 binfmt on x86 Linux. Without that, Level 2 is skipped and the log says how to enable it. Intel OpenCL rows (`vadd`, `fsum16`, `gemm16`) and the RMSNorm SPIR-V plan run only when `gpu/spirv/intel-*.tsv` (or `gpu/spirv/check.sh`) is present and an Intel GPU and OpenCL runtime are detected. The evidence-archive stage downloads a tarball or `SHA256SUMS` from the Zenodo record when one is published, or checks `--evidence PATH`. A missing archive is a skip. The last table is PASS, FAIL, or SKIP per step. Skip is never a pass. The process exits 0 only when nothing failed.
