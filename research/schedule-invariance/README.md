# Schedule-invariance experiment

Bounded experiment for section 8 of [Zenodo 23547813](https://doi.org/10.5281/zenodo.23547813).
Read [PROTOCOL.md](PROTOCOL.md) for acceptance criteria and limits.

From a clean clone, choose new output folders:

```
python3 research/schedule-invariance/build.py --out /tmp/si-build
python3 research/schedule-invariance/oracle.py --worker /tmp/si-build/worker --out /tmp/si-cpu
```

The build compiles all variants without opening the GPU. The second command runs
the CPU campaign and deliberate fault controls. `strace` must be installed and
allowed to trace children. Existing output folders are refused to preserve evidence.
The Python programs are independent experimental instruments; the actual realizers
are seeded Omega. `build.json` binds the source, compiler and executables.
Use build option `--canonical /path/to/omega-mv.git` to require current main's compiler.

With explicit GPU permission and an exclusive GPU window, add
`--gpu-worker /tmp/si-build/worker-gpu` to the oracle command and use another new
output folder. Actual GPU additions run through the existing native launcher.
Other arithmetic stays on CPU. GPU failure never selects a CPU substitute.
The launcher is synchronous; overlapping GPU dispatch remains untested.

`config.json` is frozen before execution. `runs.jsonl` saves graphs, schedules,
every request/response, actual placement and measured monotonic observation times.
`summary.json` records results and each negative control's specific rejection.
Clock and randomness controls retain actual Linux system-call traces.

A CPU PASS leaves the paper's GPU requirement untested. Results are bounded
conformance evidence, not universal proof or production FORGE/AEGIS qualification.
The experiment does not update the paper or Zenodo record.
