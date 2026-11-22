# 4-Strand Architect–Builder RLVR Pipeline (`seed/helix/ollm_factory/`)

Pure seeded-Omega implementation of the **4-Strand Architect–Builder RLVR Plan** for a single DGX Spark (NVIDIA GB10), unifying:

- **Architect**: `q36-35b` (Zero-CUDA Qwen 3.6 35B-A3B, `~/.local/bin/q36-35b`), producing language-neutral algorithm plans and 3–5 concrete `ASSERT(in->out)` vectors (never raw OM-2 code) in a single cold-boot batch.
- **Multi-Strand Builder**: Frozen `loop_r3` core + 4 chained `14.17 MB` `OLLMSP01` specialist strands clipped via live `ollm spclip (MODE=1, S=4)`:
  1. **Strand 1 (`arith` / `branch` / `bits` / `digits`)**: Core arithmetic & control.
  2. **Strand 2 (`loop` / `fold` / `select` / `count` / `scan`)**: Iteration, state & aggregation.
  3. **Strand 3 (`rewrite`)**: Structural & symbolic transforms.
  4. **Strand 4 (`repair`)**: Compiler & logic repair (`broken + omc error / wrong output -> verified fix`).
- **Deterministic Judge**: `seed/out/omc` + execution oracle + `bench seen == 0` zero-leakage screen across all `165` frozen benchmark tasks.
- **Governance & Safety**: 4-Strand BFT Braid + Four-Wall RSI Gate (`REJECT_OVERFIT_KEEP_P1` on `held.tok` regression, minimum batch floor guard eliminating the `P2` 16-window overfitting failure mode, tamper controls `rc=60/61/62`, and Section 6 Post-Cycle Scaling Decision Rule).

## Pure-Omega Components

| File | Role |
|---|---|
| `architect_client.om` | Native Omega TCP batch client for `q36-35b` (`plan`, `requeue`, `selfcheck`); enforces zero raw-OM-2 leakage and `>= 3` `ASSERT(...)` checks; supports offline deterministic mode (`port=0`) for host CPU gates. |
| `strand4_attr.om` | 4-Strand Fault Attribution Engine (`attribute`), Dual-View `\0`-EOS trace extractor (`extract`), Minimum Batch-Floor + Four-Wall BFT Promotion Gate (`promote`), Section 6 Scaling Rule (`decide`), and full positive/negative `selfcheck`. |
| `architect-builder-cycle.sh` | 4-Stage batched cycle orchestrator (`--offline` for host CPU testing, `--live` for single GB10 cold-boot `q36-35b` + 4-strand `spclip` sweep). |
| `architect-builder-gate.sh` | Dual-strand AArch64 host verification gate (zero GPU required): compiles all tools identically across Strand A (`seed/out/omc`) and Strand B (`A_fast`), trains a compact 4-strand `OLLMSP01` ensemble, runs live 4-strand `spclip MODE=1 (S=4)` + tamper controls (`rc=60/61/62`), and executes an end-to-end offline cycle. |

## Verification (Spark AArch64 CPU, Zero GPU)

```sh
sh seed/helix/ollm_factory/architect-builder-gate.sh
```
