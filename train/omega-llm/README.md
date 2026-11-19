# train/omega-llm: Omega LLM

Omega LLM (`ollm`) is the own byte/BPE transformer of Sovereign Intelligence, written in seeded Omega (`.om`): training (`model.om`, `adam.om`, `ckpt.om`), BPE (`bpe.om`, `tok/`), frozen-core specialists (`spec.om`), sampling and serving (`cli.om`, `serve.om`), one platform unit per target, and GB10 kernels (`native/gpu/`).

Since 2026-11-19 this directory is the source of truth for Omega LLM `.om` code and docs. It came from `aien-train` main `f1bebdf3c5b0` with full history (`train/import/aien-train/`).

| Path | Was in aien-train |
| --- | --- |
| `native/` | `native/omegallm/` |
| `tests/` | `tests/omegallm/*.om` |
| `tools/` | `tools/omegallm/**/*.om` |
| `docs/` | `docs/omegallm/*.md` (contracts V1-V3 and BF16, specialists, bundles, WSP) |

Stays in aien-train (listed in `train/NOT-YET-OMEGA.tsv`): the shell/Python harness `tests/omegallm/` (`build.sh`, `oracle.py`, `pre-review.py`, ...), `evidence/OMEGALLM/` receipts, and the C++ llama.cpp UI bridge `tools/omegallm-ui/`. The docs here still cite those upstream paths and commits.

## Units

Built by `seed/out/omc` and gated by `train/units-gate.om` (`OMEGA-TRAIN-UNITS`), rows in `train/units.tsv`, composed as upstream `tests/omegallm/build.sh` does (`math data <pool> model adam ckpt bpe spec cli <plat> <post>`):

| Unit | Target line | Platform unit |
| --- | --- | --- |
| `ollm_aarch64` | `om2` | `lio.om` + `serve.om` |
| `ollm_x86linux` | `target x86linux` | `lio.om` + `noserve.om` |
| `ollm_x86efi` | `target x86efi` | `eio.om` + `noserve.om` |
| `ollm_a64efi` | `target a64efi` + `seed/a64efi/efirt.om` | `eio.om` + `noserve.om` |
| `ollm_darwin` | none (see below) | `mio.om` + `noserve.om` |

`ollm_darwin` is the Darwin `<plat>` slot. `seed/out/omc` has no `target a64macos` (error 25), so this row compiles the Darwin composition for the compiler's default Linux AArch64 target; a Darwin Mach-O build and every hardware row are `NOT_RUN` here. Host compilation proves reproducible building only; behaviour checks are still the upstream harness.

Other in-tree consumers: `core/sovereign-core/om/golden/ollm/` builds a pinned aien-train snapshot by its upstream paths; `gpu/nvidia/om/gemm-any/ollm.om` and `gpu/nvidia/om/kgen/attention_ollm.om` are GPU kernels shaped for Omega LLM.
