# Combined OmegaLLM coding solver

On AArch64 Linux, run `build.sh NEW_KIT` from this directory. The build uses the repository seed compiler and builds the formalizer, sketcher, synthesizer and native router. Install the CPU Helix sampler as `NEW_KIT/ollm`, its merge table as `merges.bin`, and its round 6 checkpoint as `r6.ck`. Keep private weights in your own kit. Run `test.sh NEW_KIT` to exercise the routing with synthetic neural outputs and the real compiler and symbolic engines.

```sh
printf 'note return the argument rounded down to a multiple of 14\nfn solve a ulong to ulong\n' > prompt
printf '41 28\n70 70\n13 0\n' > examples
NEW_KIT/solve prompt examples
```

The solver prints the function body to standard output and the selected component to standard error. A prompt contains one instruction starting with `note ` and one of the five `fn solve` signatures in the Omega coding benchmark. The prompt limit is 4,095 bytes.

With only a prompt, the formalizer translates the instruction into sample inputs and outputs. The sketcher and expression synthesizer try those samples in order. If both abstain, the solver returns one greedy round 6 sample, with seed 42 and a 128-token limit. This mode returns a proposal.

With examples, the solver checks every proposal against every supplied row. After trying the English instruction, it also synthesizes from up to eight supplied rows. A candidate that fits eight rows must still pass the rest. If synthesis falls short, the solver tries round 6, optional round 3, the optional unlooped base, a private trace candidate and optional round 11. It then tries four fixed draws from each installed round 3 Arboris specialist. Each proposed body must contain a single complete function body in the supported arithmetic subset. The seeded compiler builds the example checker and the existing benchmark runner executes it under `execpure`. The first passing body wins. Exit 1 and empty output mean all available candidates were exhausted. Passing supplied examples only establishes agreement on those inputs.

The optional kit names are `r3.ck`, `base.ck`, `trace.ck`, `r11.ck` and `S1_arith.sp`, `S2_fold.sp`, `S3_rewrite.sp`, `S4_repair.sp`. Each checkpoint must use the installed sampler and merge table. The four specialists use the corresponding round 3 base. Only install finished checkpoints.

## Numeric examples

Supply 1 to 64 lines of unsigned 64-bit integers in canonical decimal. Each scalar row lists the one, two or three arguments followed by the expected result. An array row lists the active length (0 to 8), all eight input elements and the expected result. For an in-place rewrite, give all eight expected elements after the eight inputs. Caller examples are the only behavioral results given to the router. Keep independent evaluation inputs and outputs outside the kit.

## Reproduce the prompt-only comparison

On the Spark CPU, the combined solver passed 78 of the 165 frozen coding tasks. Round 6 alone passed 7. The respective scores after excluding six training-corpus matches were 73 and 5 out of 159. The per-task routes, verdicts and component hashes are in `evidence/OMEGALLM-COMBINED-20261123/` at the repository root. This historical task set has informed solver development.

Run from the repository root with `KIT` set to the absolute path of the configured kit. The benchmark writes its compiler scratch files in the scoring directory. Give the scoring command the round 6 training text as a final argument to reproduce the overlap-filtered score.

```sh
set -eu
d=$(mktemp -d)
b=$PWD/train/omega-llm/tools/bench
"$KIT/omc" < "$b/bench.om" > "$d/bench"
chmod +x "$d/bench"
mkdir "$d/prompts" "$d/answers"
"$d/bench" prompts "$b/tasks.om" "$d/prompts"
for p in "$d/prompts"/prompt-*; do
    id=${p##*/prompt-}
    "$KIT/solve" "$p" > "$d/answers/answer-$id"
done
"$d/bench" score "$b/tasks.om" "$b/expect.txt" "$KIT/omc" "$d/answers"
```

## Checked verifier and eight-query experiment

The checked verifier recognizes parameters, assigned locals and loop variables.
Renamed locals go through the same arithmetic instructions, seeded compiler and
`execpure` checks. On Spark, the correction raised the checked historical score
from 99 to 105 out of 165. Two additional array rewrite patterns raised it to
106. Prompt-only retained all 78 passes.

Adaptive questioning is available in the test harness. The normal CLI still takes
a prompt and optional examples. The frozen comparison records programs, timings,
engine failures and every charged query. [Comparison report](../../../../evidence/OMEGALLM-SELECTION-20261123/REPORT.md) · [Reproduction commands](experiment/README.md)

The repaired expression synthesizer completed all four methods on the same 80 tasks with zero component errors. The candidate selector solved 26 using fixed inputs and 26 using adaptive inputs. [Traversal fix and rerun](../../../../evidence/OMEGALLM-FRONTIER-20261123/REPORT.md)
