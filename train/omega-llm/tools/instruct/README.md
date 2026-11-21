# Instruction-and-function records

`instruct.om` writes training records for Omega LLM: an instruction and an Omega function that does what it says. The benchmark in [`../bench`](../bench/README.md) asks a model to turn an instruction into a function, and the repository's own source holds almost no such pairs. This tool makes them.

The instructions are composed from parts ("return twice a plus the larger of b and c"), and the function is built from the same parts, so it is correct by construction. A model can follow them only by learning what the parts mean.

## What it generates

Records come in the five shapes of the benchmark, with the same signatures and the same names (`a`, `b`, `c`, `n`).

| Shape | Kinds of record |
| --- | --- |
| One to three arguments | A value built from squares, multiples, sums, products, remainders, the larger, the smaller and the distance of values; `X when C, otherwise Y`; `1 when C, otherwise 0`; `X minus Y when X is at least Y, otherwise zero`; how many arguments pass a test |
| Array, read | How many items pass a test; sums and products of items, of their squares, or of a value made from the item and its index; the largest and the smallest; the first or last item that passes a test; comparisons with the item before |
| Array, changed in place | Replace each item, or every item that passes a test, with a value made from the item, its index, `n` or the first item; running sums, products and counts; add to or multiply the items |

Every instruction reads one way only. Each phrase carries a level (a name, a tight phrase, a closed phrase with an `and` in it, a loose phrase), and a part is only put where its level cannot be misread; the head of `instruct.om` lists the rules. A long expression moves to a temporary, so the functions stay within the compiler's registers.

The functions never trap: unsigned arithmetic wraps, every divisor is a constant above zero, and array indexes stay below `n`.

## Keeping the benchmark unseen

A generated function that returns the same results as a benchmark task on every one of the benchmark's shared inputs is that task under another wording. `instruct keep` drops every such record, so no kept record computes a benchmark behaviour. The parts of those behaviours still occur in other records; solving a benchmark task then means putting known parts together in a way the model has not been shown.

## Build and run

On AArch64 Linux, from the repository root:

```sh
seed/out/omc < train/omega-llm/tools/instruct/instruct.om > instruct && chmod +x instruct
seed/out/omc < train/omega-llm/tools/bench/bench.om > bench && chmod +x bench
d=train/omega-llm/tools/bench
./instruct tasks $d/tasks.om 1 2000 > gen-1.om              # 2,000 tasks from seed 1
mkdir work-1
./bench table gen-1.om seed/out/omc work-1 > gen-1.rows     # run every function on the shared inputs
./instruct keep gen-1.om gen-1.rows $d/expect.txt >> records.om
```

- `tasks BENCH_TASKS SEED COUNT` writes COUNT tasks in the form `bench.om` reads, with the shared inputs of BENCH_TASKS. The same SEED and COUNT give the same bytes.
- `bench table` compiles all functions of a file into one program, so keep a file to about 2,000 tasks and use one seed per file.
- `keep GEN ROWS EXPECT` writes the records and prints `KEEP tasks N kept K dropped D` on stderr.

A record is one NUL byte, `note INSTRUCTION`, `fn solve PARAMS`, the body and its closing `end`: the prompt form of the benchmark followed by the answer.

Exit codes: 0 done, 2 usage, 5 a record over 65,536 bytes, 6 GEN and ROWS do not fit, 70 I/O.

## What has been checked

On AArch64 Linux in a virtual machine, with `seed/out/omc` `708fdc0f…`, on 2026-11-21, over 50,000 generated tasks (seeds 1 to 25):

- Every generated function compiles and runs on all shared inputs without a trap (`bench table` exits 0 for all 25 files).
- `keep` dropped 3,016 tasks. An independent count of the rows that equal a benchmark row, made with `cut` and `grep`, is also 3,016.
- The dropped tasks cover 51 benchmark tasks. Listed beside the benchmark's own instructions they say the same thing ("return the square of the sum of the arguments" for `p-002`, "return how many of the first n items are equal to their own index" for `r-026`), which checks wording against behaviour with the benchmark's references as the oracle.
- `bench seen` finds no benchmark reference in the 46,984 kept records.
- 19,970 of the 50,000 instructions are distinct; the most frequent one is 0.35% of them.
- Controls: a ROWS file one row short or one row long is exit 6; an EXPECT with no matching row keeps everything.

Not checked by a machine: that every kept instruction describes its function. That rests on the construction and on the 51 behaviours above.

## Limits

- No loops with a data-dependent end, no digit work, no sorting or moving of items: the benchmark's `loop` and `digits` families and most of its `rewrite` family are outside what this tool can say.
- The wording is one style. A model trained on it may follow this style and no other.
