# OmegaLLM verifier and program selection on Spark CPU

The corrected CLI recovered all six additional historical passes and retained every previously passing task. The adaptive method remains experimental. The registered evaluation stopped before final scoring when the expression synthesizer exited 104. The completed diagnostic comparison used the frozen programs, inputs, references and checkpoint.

## Historical CLI replay

| Condition | Previous passes | Corrected verifier | With both new sketches | Previously passing tasks lost by final CLI |
|---|---:|---:|---:|---:|
| Prompt only | 78/165 | 78/165 | 78/165 | 0 |
| Eight supplied examples | 99/165 | 105/165 | 106/165 | 0 |

The verifier recovered `r-006`, `r-009`, `r-017`, `r-030`, `u-018` and `u-023` on the eight-example condition. Corrected verifier commit `e522d8a124b388473d4705ba524a46cf56f8476d`.

## Fresh tasks

Candidate selection with fixed examples returned six more correct programs than the corrected CLI. Adaptive questions added one further correct program and two additional wrong answers relative to fixed candidate selection. All four arms solved one branch task. [Side-by-side results for all 80 tasks](tasks.f83e8f2bad8bf28e8400315874ef95df8037a8a7572302abc9f2454bd7a31938.csv)

The freeze contains 20 tasks in each of four groups, arranged in five template families per group. Four variants of every family stay in the same split. All arms used eight Spark CPU workers. Selection times are seconds per task. Sum is cumulative across concurrent tasks and includes all recorded component failures.

| Arm | Correct | Wrong | Abstained | Engine errors | Wrong branches | Query maximum | Median seconds | Sum of seconds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Corrected CLI, fixed | 18 | 21 | 38 | 3 | 17 | 8 | 4.703 | 4085.7 |
| CLI with new sketches, fixed | 18 | 21 | 38 | 3 | 17 | 8 | 4.730 | 3783.7 |
| Candidate selection, fixed | 24 | 15 | 34 | 7 | 14 | 8 | 0.029 | 174.8 |
| Candidate selection, adaptive | 25 | 17 | 34 | 4 | 16 | 8 | 0.074 | 158.4 |

| Task group | Corrected CLI correct / wrong / abstain / error | Improved CLI | Fixed candidates | Adaptive candidates |
|---|---:|---:|---:|---:|
| branch | 1 / 17 / 0 / 2 | 1 / 17 / 0 / 2 | 1 / 14 / 0 / 5 | 1 / 16 / 0 / 3 |
| arithmetic | 14 / 3 / 2 / 1 | 14 / 3 / 2 / 1 | 18 / 0 / 0 / 2 | 19 / 0 / 0 / 1 |
| read | 1 / 1 / 18 / 0 | 1 / 1 / 18 / 0 | 1 / 1 / 18 / 0 | 1 / 1 / 18 / 0 |
| rewrite | 2 / 0 / 18 / 0 | 2 / 0 / 18 / 0 | 4 / 0 / 16 / 0 | 4 / 0 / 16 / 0 |

A separate instrumented run reproduced exit 104 at line 490 of the frozen expression synthesizer. At depth 2 it attempted to traverse nodes 35 through 4174, a span of 4140. The loop has a 4096-iteration bound. The diagnostic executable was kept outside all evaluation kits.

The six decisions sealed before interruption were preserved byte for byte. The diagnostic harness resumed the remaining rows with the same solver hashes. It reports component errors separately. Unsealed fixed-example calls may have been repeated during recovery. Query counts and elapsed times describe the retained invocations. The independent scorer opened final scoring labels only after every arm had sealed its decisions.

### Advancement criteria on the diagnostic data

- more correct passed.

- no more wrong passed.

- fewer wrong branches passed.

- within budget passed.

## Development rewrite ablations

The corrected CLI missed all four adjacent-item updates and all four first-item updates. Constant XOR accounted for two other misses and a prefix maximum for one. Across all 24 development rewrites, it returned 13 correct programs and abstained on 11.

| Enabled additions in the sketcher | Correct | Wrong | Abstained |
|---|---:|---:|---:|
| Neither | 6 | 0 | 18 |
| Scaled next item | 10 | 0 | 14 |
| Scaled original first item | 10 | 0 | 14 |
| Both | 14 | 0 | 10 |

These four measurements exercise the native sketcher with the same numeric examples. Each emitted program was run through the seeded compiler and sandbox on independent data. All eight array elements were checked, including inactive tails. Additional controls exercised empty arrays, repeated values, full and partial lengths, unsigned wraparound and a deliberately incorrect tail.

## Source and reproduction

Fixture freeze `fb907e730f18116a732d87713d9d59838c9ca48c`. Frozen experiment source `1ce0692933afcf402d883f05cd9c307f76c9254c`. Diagnostic error accounting `7146a4cd09993b733e2a7d29511faf973b9c767c`. The compiler rebuilt to its seed fixpoint. The model stayed at SHA-256 `08fc55505c8fa6a094e30807e616b64e4ea6d186cd4ef769ed877e469bcaac91` throughout.

The receipt contains the complete per-task programs, queries, routes, scoring verdicts, first counterexamples, timings and component hashes. The public replay requires the compiler and runner. Regenerating the full CLI arms also requires the pinned private checkpoints. [Per-task receipt](comparison.c309a3265517da40f20cf835897c3b7f66bbe0b5bfd50d6d3d1dd0fec0d95590.json) · [Reproduction commands](../../train/omega-llm/tools/combined/experiment/README.md)
