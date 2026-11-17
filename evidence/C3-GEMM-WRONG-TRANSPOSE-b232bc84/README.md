# C3 GEMM: wrong-transpose negative control (DRA-485)

DRA-485 asks that a wrong-transpose mutant fail. Mutant 4 does this. The driver
(`omega_gpu_gemm_drive`) packs A with the strides of the other layout, so a
row-major A is read as column-major, and the other way round. Every element it
reads stays inside A. The kernels do not change.

| Log | What it checks | Result |
|---|---|---|
| 01-host-only | the earlier host checks, plus codegen and encode with mutant 4 for every tile shape and both types | PASS, 166 checks |
| 02-sim | the earlier simulator checks, plus mutant 4 caught both ways (A row-major and A column-major), BF16 and FP8 | PASS, 188 checks; mutant 4 makes 4,095 of 4,095 outputs wrong |
| 03-sim-mutant4-disabled | the control of the control: with mutant 4 turned into a no-op (tree not clean, stated in the log) the four new red checks fail | FAIL, 4 of 188, as expected |
| chip | 208 shapes (26 per type and layout, 1 to 8192), the red checks with mutant 4, speed against 115.36 TFLOPS (BF16) and 237.52 TFLOPS (FP8) | NOT_RUN: needs a GB10 window |

Where it ran: x86_64, `aarch64-linux-gnu-gcc` 13.3, `qemu-aarch64` user mode,
physics-mv at `physics.lock` (048e5f5e). This is a host and emulator result.
It is not hardware qualification.

Known limit of the chip tier, as written: shapes over 2^27 multiply-adds are
compared on 4,096 sampled elements plus the last row and column, not in full.

Chip command, under the GB10 lock in an authorized window: `build/gpu_gemm_test` with no flag.
