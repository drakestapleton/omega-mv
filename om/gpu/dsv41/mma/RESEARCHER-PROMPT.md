Set up and independently reproduce the merged Omega DeepSeek-V4.1-Flash expert-kernel benchmark on my hardware. Do the setup and run the checks yourself. The result I want is a reproducible local build, a checkpoint-backed FP4 versus FP8 comparison, and a short report of what passed on my machine.

1. Identify the host you’ll use. The build targets AArch64 Linux and the GPU benchmark targets NVIDIA GB10 on DGX Spark, SM121a. If I have two Sparks, use one for this reproduction. Record the host architecture, OS, GPU, driver version, free disk space, and Python/NumPy versions. Follow the repository rules and my local GPU scheduling procedure. If a compatible GPU is unavailable, complete any supported build and artifact checks and mark the device benchmark BLOCKED_HARDWARE.

2. Clone https://interplane.io/projects/omega-mv/repo.git into a fresh directory. Check out public merge commit 42011f07ddb13241a8ac2360eee6e999f1e4bbfc and verify HEAD. Read AGENTS.md, om/gpu/dsv41/README.md, and om/gpu/dsv41/mma/README.md. From the repo root, run:
   sh seed/omega-from-seed.sh
   sh om/gpu/dsv41/build.sh build/dsv41
   Save the build logs and SHA-256 hashes of the outputs.

3. Locate the researcher bundle omega-dsv41-expert-a7d5b9db4.tar.gz in the files I supplied. Its SHA-256 must be 331d9360ef43db3bae63add7b6291fa0920c2512f0d966180e9cd384586045c3. If it is missing, ask me for that exact file and continue the repository checks. After verifying the archive, extract it into a fresh directory, verify build.sha256 there, and follow its README. Rebuild with:
   sh rebuild.sh ./omc ./final-kpack
   Compare the four production expert cubins from the merged build with their counterparts in the verified bundle. Preserve the archived logs and receipts separately from your own results.

4. For the measured expert replay, obtain only model-00003-of-00048.safetensors from deepseek-ai/DeepSeek-V4.1-Flash revision 314113f8a7dadb388215396ba5fbee2c610a04d6. Reuse a local copy if its SHA-256 matches e1281f85d0ce4a3dfb63d41926fc4a47fa71f36ba20992e3597e702ead49d4c9. Otherwise download that shard from the pinned revision and verify it. Keep the shard read-only. This replay needs neither the other 47 shards nor a second Spark.

5. In an authorized quiet GPU window, run the repository operator check from the repo root:
   python3 om/gpu/dsv41/check.py build/dsv41
   Then, from the extracted researcher bundle, set SHARD to the absolute path of the verified shard and run these sequentially:
   OPENBLAS_NUM_THREADS=2 python3 bench.py "$PWD" "$SHARD"
   OPENBLAS_NUM_THREADS=2 python3 bench-tile.py "$PWD" "$SHARD"
   Save stdout, stderr, exit status and raw timing samples for each run. The experiment uses layer 0, expert 0, real W1/W3/W2 weights, deterministic synthetic activations, and a route weight of 0.375. Evaluate shift-two FP4 against the exactly expanded FP8 control at M=1 and M=16 for the single-row kernel and M=16 for the tiled kernel. Shift-zero and shift-four are intentional negative controls. Report their outcomes separately.

6. Leave me the exact commands, local paths, source and shard hashes, device details, parity results, and median FP4 and FP8 latency for each matched shape. Calculate speedup as FP8 median divided by FP4 median. Identify what the timed interval includes and keep weight staging and readback outside it. Give each check a PASS, FAIL, NOT_RUN, or BLOCKED_HARDWARE verdict and preserve any failing output. Scope the conclusion to the measured expert workload. Full-model serving, token throughput, and dual-Spark RDMA each need separate experiments.
