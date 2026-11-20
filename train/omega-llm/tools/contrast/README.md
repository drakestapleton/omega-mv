# Contrast training and example-checked Omega completions

This directory contains the seeded Omega tools and executable fixtures from the Spark contrast-training experiment. Each checkpoint gets the instruction and function signature. The example-checked chain compiles each candidate with a caller-supplied test and runs the program with `execpure`. It returns the first body that passes.

## Build and replay

On AArch64 Linux, grow the seeded compiler from the repository root. The replay requires GNU Make, Bash, jq and coreutils.

```sh
sh seed/omega-from-seed.sh
make -C train/omega-llm/tools/contrast replay
```

The build places executables in `build/omega-contrast`. The replay compiles the reference functions, grades the archived generations, checks selections against their recorded outcomes and reproduces the contrast corpus hash. It runs on the CPU. The measured GPU training and inference settings and model digests are in [run-01](run-01/README.md).

## Generate a function

From the repository root in an authorized exclusive Spark window, set `SAMPLER`, `MERGES`, `PARENT`, `CONTROL` and `TREATMENT` to absolute file paths. Use a new private directory for each invocation. The compiler, grader and live chain use scratch files in their working directory.

```sh
root=$PWD
fixture=$root/train/omega-llm/tools/contrast/run-01
cd "$(mktemp -d)"
jq -rj '.[0].prompt' "$fixture/fresh.json" > prompt.om
jq -rj '.[0].main' "$fixture/example.json" > example-main.om
spark-window run "$root/build/omega-contrast/with-example" prompt.om \
  "$root/seed/out/omc" "$SAMPLER" "$MERGES" example-main.om \
  "$PARENT" "$CONTROL" "$TREATMENT" > body.om
```

The supplied `main` returns 77 when its check passes and 83 when it fails. The chain tries the supplied checkpoints in order with seed 42, temperature zero and a 64-token generation limit. Standard output contains the accepted function body, and standard error identifies the checkpoint. Exit status 3 with empty output means every model failed. An example pass covers only the supplied input. The experiment used separate inputs to grade accepted functions.

## Repeat the training comparison

With absolute paths, set `TOOLS` to the build directory, `WTRAIN` to the seeded training harness, `OLD` to the previous corpus and `HELD` to the held-out language-model corpus. In a fresh private directory run the following commands. Each training invocation needs an authorized exclusive GPU window.

```sh
cp "$OLD" old.om
"$TOOLS/contrast" > contrast.om
"$TOOLS/mix"
spark-window run "$WTRAIN" gb10 "$SAMPLER" "$PARENT" "$MERGES" old.om "$HELD" control 800 350 4
spark-window run "$WTRAIN" gb10 "$SAMPLER" "$PARENT" "$MERGES" mixed.om "$HELD" treatment 800 350 4
"$TOOLS/mean" control/candidate.ck treatment/candidate.ck averaged.ck
```

The mixer is specific to this corpus format and experiment. It shuffles complete NUL-prefixed records with a fixed seed. The mean tool accepts two checksum-valid OLLMCK02 checkpoints with matching headers, averages every parameter and clears the optimizer moments and step. Give it a fresh output path, separate from both inputs. The [seeded training harness](../../README.md) documents the trainer arguments.
