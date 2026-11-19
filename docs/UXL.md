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

The run prints the OS, architecture, Python, `git core.autocrlf`, whether `qemu-aarch64` binfmt can run `seed/out/omc`, and whether an Intel GPU and OpenCL runtime are present. It does not require the GPU. Level 1 checks the published 65-file record under `tools/uxl/level1/` (path comparison uses `as_posix()`). Level 2 rebuilds the launcher and the 18 gfx942 kernels with `seed/out/omc` and compares them to `gpu/amd/card.tsv`. Those receipt hashes are the ones in the brief: `launch-x86` and `vadd` match Zenodo record 10.5281/zenodo.24237047. On x86 the arm64-only `trace.c` instruments are skipped, not passed. `omc` is the pinned AArch64 binary `34d611ca0415eab1728d3234911d90e74af17ba9ab0c581d559f48274d7ca6d3`. It runs natively on arm64 Linux and through qemu-aarch64 binfmt on x86 Linux. Without that, Level 2 is skipped and the log says how to enable it.

The SPIR-V stage runs `OMC=seed/out/omc sh gpu/spirv/check.sh` (spirv-val, mutants, host conform) and streams each line. It skips only when `spirv-val` or `omc` cannot run, and the skip line says how to install `spirv-tools` or `qemu-user-static`. The RMSNorm stage reads `gpu/spirv/intel-rmsnorm.tsv` and runs every row. Exit 0 is PASS, exit 2 is NOT_RUN (prerequisite missing), anything else is FAIL. NOT_RUN is not a pass. The reference sha256 is `144c89820d5d005af741dfcace8f9882bae481d72f1745aef36b5014cbaadb46`. The Intel OpenCL stage (`vadd`, `fsum16`, `gemm16`) looks for `gpu/spirv/intel-opencl.tsv` and runs it the same way when it is present. That file is not in this checkout, and neither is a `gemm16` kernel; the stage says so and does not invent a result. Host conform for `vadd` and `fsum16` still runs inside `gpu/spirv/check.sh`.

The evidence stage fetches `https://zenodo.org/api/records/24237047`, downloads each file, and checks the checksum the API published. There is no evidence archive on that record. Offline, the stage skips and says why. The last table is PASS, FAIL, SKIP, NOT_RUN, or MISSING per step. Skip, NOT_RUN, and MISSING are never passes. The process exits 0 only when nothing failed. `--evidence URL` overrides the Zenodo API URL.
