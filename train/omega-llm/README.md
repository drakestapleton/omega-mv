# train/omega-llm: Omega LLM

Omega LLM (`ollm`) is the own byte/BPE transformer of Sovereign Intelligence, written in seeded Omega (`.om`): training (`model.om`, `adam.om`, `ckpt.om`), BPE (`bpe.om`, `tok/`), frozen-core specialists (`spec.om`), sampling and serving (`cli.om`, `serve.om`), one platform unit per target, and GB10 kernels (`native/gpu/`).

Since 2026-11-19 this directory is the source of truth for Omega LLM `.om` code and docs. It came from `aien-train` main `f1bebdf3c5b0` with full history (`train/import/aien-train/`).

| Path | Was in aien-train |
| --- | --- |
| `native/` | `native/omegallm/` |
| `tests/` | `tests/omegallm/*.om` |
| `tools/` | `tools/omegallm/**/*.om` |
| `docs/` | `docs/omegallm/*.md` (contracts V1-V3 and BF16, specialists, bundles, WSP) |

The Python corpus builder and compile feedback loop live in `tools/omega-llm/` at the omega-mv repository root.

Stays in aien-train (listed in `train/NOT-YET-OMEGA.tsv`): the shell/Python harness `tests/omegallm/` (`build.sh`, `oracle.py`, `pre-review.py`, ...), `evidence/OMEGALLM/` receipts, and the C++ llama.cpp UI bridge `tools/omegallm-ui/`. The docs here still cite those upstream paths and commits. Unless a citation names a different commit, upstream paths refer to aien-train `f1bebdf3c5b08ec624005e5bc39d0427a87f9537`; they are not local omega-mv paths.

## Training from source text

The seeded `wtrain` harness fine-tunes an existing checkpoint on a training text file and evaluates both checkpoints on the same held-out text. For a coding run, supply Omega source or instruction-and-function records. Keep the evaluation corpus separate before starting the run. The trainer uses full-token loss.

Build on AArch64 Linux from the repository root with the seeded compiler. The first source supplies the existing Omega driver library.

```sh
driver=train/omega-llm/tools/wdrive
{ sed "s/^fn main to int$/fn wbmain to int/" "$driver/wbuild.om"; cat "$driver/wtrain.om"; } | seed/out/omc > wtrain && chmod +x wtrain
```

Pass an Omega LLM executable, base checkpoint, tokenizer merges, training file, held-out file, new output directory, step count, learning rate in millionths and number of held-out windows. Byte checkpoints use `-` for the merges argument. BPE checkpoints use the native `bpeenc` command with the vocabulary size from the base checkpoint. Each corpus must supply at least one context window plus the next token. The held-out file must cover the requested number of windows.

```sh
./wtrain cpu ./ollm base.ck merges.bin training.om held-out.om run-01 100 250 3
spark-window run ./wtrain gb10 ./ollm-gb10 base.ck merges.bin training.om held-out.om run-02 100 250 3
```

The GPU invocation runs inside an authorized exclusive Spark window. The harness creates a private directory, writes the token streams and `candidate.ck` there, and records native tokenizer, optimizer and evaluator output in `run.log`. An existing output directory is refused. A failed run retains its partial files. A successful run ends with `TRAINING_COMPLETE` after the final evaluation. The E lines report held-out language-model loss. Coding accuracy requires separate execution tests.

The [contrast-training experiment and example-checked coding chain](tools/contrast/README.md) include a CPU replay of generated functions against their expected outputs.

## Units

Built by `seed/out/omc` and gated by `train/units-gate.om` (`OMEGA-TRAIN-UNITS`), rows in `train/units.tsv`, composed as upstream `tests/omegallm/build.sh` does (`math data <pool> model adam ckpt bpe spec cli <plat> <post>`); `build.sh` has no Darwin target, so the `ollm_darwin` row follows upstream `tests/omegallm/ollm_metrics_bench.py` (`darwin-arm64`):

| Unit | Target line | Platform unit |
| --- | --- | --- |
| `ollm_aarch64` | `om2` | `lio.om` + `serve.om` |
| `ollm_x86linux` | `target x86linux` | `lio.om` + `noserve.om` |
| `ollm_x86efi` | `target x86efi` | `eio.om` + `noserve.om` |
| `ollm_a64efi` | `target a64efi` + `seed/a64efi/efirt.om` | `eio.om` + `noserve.om` |
| `ollm_darwin` | none (see below) | `mio.om` + `noserve.om` |

`ollm_darwin` is the Darwin `<plat>` slot. `seed/out/omc` has no `target a64macos` (error 25), so this row compiles the Darwin composition for the compiler's default Linux AArch64 target; a Darwin Mach-O build and every hardware row are `NOT_RUN` here. Host compilation proves reproducible building only; behaviour checks are still the upstream harness.

Other in-tree consumers: `core/sovereign-core/om/golden/ollm/` builds a pinned aien-train snapshot by its upstream paths; `gpu/nvidia/om/gemm-any/ollm.om` and `gpu/nvidia/om/kgen/attention_ollm.om` are GPU kernels shaped for Omega LLM.

## Follow-ups

`tools/wpatch/wpbuild.om` has been ported to `omega-mv` paths (`/train/omega-llm/native/`, `/train/omega-llm/tools/`, including `spec.om`), `train/import/aien-train/paths.txt` excludes the migrated `omegallm/` folders, and `train/units-gate.om` fails if any `train/aien-train/{native,tests,tools,docs}/omegallm` directory reappears. End-to-end behavioural runs of the tools from an `omega-mv` checkout and Darwin Mach-O / hardware target builds remain `NOT_RUN`.
