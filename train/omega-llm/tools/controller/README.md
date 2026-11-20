# Learned tool controller for seeded Omega coding

One small learned policy chooses the initial generation route and whether to retry. A second learned policy chooses whether to run another trusted caller example after a candidate passes the first one. A separate Omega LLM supplies all generated function bodies. The controller can return a verified-on-examples body or abstain.

On 80 fresh confirmation prompts, the augmented second-check policy returned the same 33 correct functions and 47 abstentions as always running a second example. Each made 129 model calls. The learned policy ran 29 second checks and the fixed policy ran 39. Median end-to-end request times were 141.6 and 141.1 ms, respectively, with a resident Spark GB10 reasoner. The learned policy's current decisions check scalar functions and skip array functions. The calibration set included 14 first-passing array candidates. The tests cover 20 semantic tasks with two wordings and two argument-name sets each.

## Build and replay

From this directory on AArch64 Linux, run the following commands. Set `OMC` to an absolute path to use another seeded compiler. The experiment used compiler SHA-256 `210c52566e782cf15ece6e478d45bfb67f1ad338f29e41546dad9b6c4f85b54c`. The build needs Bash, xxd and sha256sum. Replay also uses jq and base64.

```sh
./build.sh
./replay.sh
```

The default output directory is `build/omega-controller` at the repository root. Both commands accept an absolute `OUT` override. The build fits all three small checkpoints from the bundled calibration streams and verifies their SHA-256 digests. The CPU replay compiles reference functions against both public examples and the private checker, exercises policy decisions and regrades the bodies returned by all seven study arms.

## Run the controller

Use absolute paths. Run each request in a new private working directory. The trusted prompt file contains a `note` line followed by a seeded function signature. Tested signatures return `ulong` and take two unsigned scalars, or a fixed-size `view ulong` and a prefix length. The normalization route works on identifiers and assumes the instruction identifies arguments by position or meaning. Each trusted example file supplies a `main` that calls the generated function and returns 77 on agreement and 83 on failure. See [example](example/).

```sh
"$BIN/controller" "$PROMPT" "$OMC" "$SAMPLER" "$MERGES" "$FIRST_MAIN" "$REASONER" "$BIN/normalize" "$BIN/controller.ck" "$SECOND_MAIN" "$BIN/second-augmented.ck" learned >answer.om 2>actions.log
```

For cold generation, `SAMPLER` is the native `ollm-gb10` executable and `REASONER` is a compatible checkpoint. For resident inference, start the native server with `gserve PORT CHECKPOINT MERGES REQUEST_COUNT` in an authorized Spark window. Set `SAMPLER` to `$BIN/resident` and `REASONER` to a file with two newline-terminated lines, the loopback port and the exact model ID returned by the server. The adapter verifies that ID on every response. The experimental reasoner checkpoint SHA-256 was `079653f6d9f582f6bd9966a482760654c93981fcaa9d43d9c1d911fdc26a6af5`. Supply the reasoner and its BPE merges separately.

Choose `one`, `two` or `learned` for the final argument. Omitting all three trailing second-check arguments uses the original single-example interface. A generation uses seed 42, temperature zero and up to 64 completion tokens. Each request permits two model calls. Exit 0 returns a function body, exit 3 abstains, and other nonzero exits signal errors. Checks use the seeded compiler and restricted executor. This research harness takes trusted local inputs and runs in its own working directory.

## Calibration and results

The initial routing policy trains on five bytes per record (feature group, direct and normalized public grades, direct and normalized private calibration grades). The second-check trainer takes two bytes (candidate group, catch label). A catch is a first-passing candidate that fails both the second example and private calibration checks. The group records an array input, presence of a conditional, and a return of a single identifier. Sparse groups back off to input type and then pooled experience. The policy requests a second check at an observed catch frequency of at least one in twelve.

The [first panel](run-01/scores.json) used 56 distinct historical calibration candidates and found one incorrect return that escaped the learned policy. On the [confirmation panel](run-02/scores.json) the revised policy added 20 first-passing observations from all 100 target/program pairings for ten scalar behaviors. Both panels preserve the instructions, reference programs, caller and private checkers, final answers, per-prompt records and scores. Calibration weights were fixed before their respective panel was scored. The earlier learned checkpoint is built as `second.ck` and the augmented one as `second-augmented.ck`.
