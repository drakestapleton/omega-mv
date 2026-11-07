# Rule forbnd: for-counter bounds-check erasure (DRA-189)

An opt-in optimization in the seeded compiler `seed/omc/omc.om`, with a Lean proof over an explicit
model, an independent certificate checker, a gate with negative controls, a benchmark and a
trusted-computing-base statement. Nothing here changes a unit that does not ask for it: without the
lead word `bce`, omc writes the bytes 5f90edea writes (checked on 1334 corpus units).

## The cost it removes

omc checks every index into a sized OM-2 array at run time: `CMP Xi, #len` (or `CMP Xi, Xn`) and
`B.HS` to trap 3 (`elemaddr`). In a loop `for i ulong K` whose body indexes `a` with `i`, the check
runs once per element although `i < K <= len a` holds on every iteration. The static profile below
counts these sites in the corpus; the benchmark measures what they cost.

## The rule

Under the lead line `om2 bce` (or `om2 diag bce`), on AArch64, the check of an index is not emitted
when all of these hold:

1. the index is a register `i` that is the counter of an enclosing `for i ulong K` (or `u64`) loop;
2. `K` is a number (a literal, a const, or `len NAME` of a sized array or text), `K != 0`, and the
   loop is not `unroll`;
3. no line of the loop body starts with `i` (a nesting-aware scan from the `for` line to its `end`), so
   the body never assigns the counter;
4. the array is sized, of a number length `L` (a sized `view` / `edit` / `out` parameter, a `new`
   local or a global), not an unsized `*` array;
5. `K <= L`.

Every other index keeps its check: values, expressions, `i + 1`, a counter of another loop whose
premises fail, a counter after the body writes it, every index under `om2` without `bce`, and every
index on the x86 target (`xelem` emits all checks).

Why the counter is in range: omc's `for` keeps `i` in a register, starts it at 0, compares
`i < K` before each iteration and increments it at the latch. When the body does not write `i`, every
iteration runs with `0 <= i < K <= L`. An inlined call gets its own parameter registers (`inl_par`),
so a callee cannot write the caller's counter.

## Implementation map (omc.om)

| piece | where | what |
| --- | --- | --- |
| lead word | `cp_mode` | `bce` (packed 6644578) sets `bcem`; `bcex` and other words stay error 16 |
| loop premise | `bce_q`, `bce_scan`, `bce_word` | at a `for` line: `bcem` set, not irmode, ulong type, number count != 0, no `unroll`, body scan finds no line starting with the counter; then `bcek` = K, `bcew` = counter word |
| block record | `pushb` | a `for` block (kind 4) takes `bbce` = K (0 when the premise failed) and `bbcw` |
| erase decision | `bce_er`, called by `elemaddr` | index kind 1 (register), array kind 1..4 sized with layout 0 and length `ln != 0`; some open `for` block whose counter register is the index has `0 < bbce <= ln` |
| check emission | `elemaddr` | `if eq bce_er e k v ln 0` around the `CMP` / `B.HS` trap 3 |
| certificate | `bce_rec` | under `om2 diag bce`, one stderr line per erased check: `omc-check 1 erased line=N rule=forbnd kind=bounds ctr=C count=K arr=A len=L` |

`om2 diag bce` writes the same artifact bytes as `om2 bce` (checked on kemu); `diag` only adds the
records and the `omc-site` trap-site lines.

## What is proved (Lean 4, `lean/OmegaBce.lean`)

The model: 64-bit words (`BitVec 64`), registers, array memory with a length per array, expressions
with a checked or unchecked `get`, statements `assign`, `put`, `seq`, `ite`, `while` and
`forN r k g body` with omc's semantics: counter from 0, unsigned `i < k` at the head, a wrapping
`+1` latch, and the guard for early exit. A checked access with `i >= len a` (unsigned) ends the run
with trap 3; an unchecked one reads or writes without a check. `erase` is the rule: it walks the
program with the list of active counters `(r, K)` and drops the check of a `get` / `put` whose index is
`.reg r` for an active `(r, K)` with `K <= len a`; a loop becomes active only when `K != 0` and
`writes r body = false`.

- `erase_correct`: for every fuel, program, active list and state, if every active counter is below
  its bound (`Inv`) and the program writes none of them (`NoW`), the erased program has exactly the
  same outcome (end state, trap code, or fuel exhaustion) as the original.
- `bce_correct`: from the top level (no active counters), `exec (erase p) s = exec p s` for every
  `p` and `s`.
- Axioms (`lean_verify`): `bce_correct` and `erase_correct` depend on `propext` and `Quot.sound` only;
  no `sorry`, no `Classical.choice`, no `native_decide`.

Negative controls in the model (each is a theorem, checked by `decide`):

- `kgt_without_len_premise`: without `K <= len a`, the erasure of `for i 3` over a length-2 array
  turns a trap 3 into a normal end (`kgt_traps`, `kgt_rule_keeps`: the real rule keeps the trap);
- `written_without_scan`: without the body-write premise, a body that sets `i = i + 2` loses its trap;
- `idx_without_reg`: erasing any index expression, not only the counter register, loses a trap.

Mutating the rule in the model makes the unchanged proof fail (`lean/negctl.sh`): L1 (no length
premise) 2 errors, L2 (no body-write premise) 3 errors, L3 (any index) 4 errors; the original checks
with 0 errors and 0 warnings (`LEANNEG PASS 3 mutants rejected, original checks`).

The same file is committed in the lean-verify workspace as `LeanVerify/OmegaBce.lean` and builds with
`lake build`.

## What is not proved (the trusted computing base)

The proof is about the model, not about `omc.om` or the AArch64 code. Trusted, and checked only by
the tests and the certificate checker below:

1. **The model is omc's semantics.** That omc's `for` lowering is the model's `forN` (counter in a
   register from 0, unsigned compare with K at the head, increment at the latch, the counter not
   spilled and reloaded from writable memory) and that `CMP` / `B.HS` is the model's checked access.
   Not checked against the AArch64 ISA semantics.
2. **`bce_q`, `bce_scan` and `bce_er` compute the model's premises.** That "no line starts with the
   counter" is `writes r body = false` (omc has no other way to assign a register-held local: no
   address-of, no aliasing of scalar locals; inlined calls get copies), that the array length omc
   uses is the length the access is checked against, and that the block walk finds the loop that
   owns the counter register. The certificate checker re-derives these from the source text; it
   shares no code with omc, but it parses with the same reading of the language.
3. **The rest of the compiler and the seed chain**: the parser, register allocation, the encoder,
   the rung chain that builds omc from `seed/rung0` (`seed/omega-from-seed.sh`).
4. **Lean's kernel** and `propext`, `Quot.sound`; the `decide` negative controls run in the kernel.
5. **The host**: Linux, the kernel's process and memory model, the CPU.

Not covered at all: the x86 target (it keeps every check, `xelem`), `irmode` (IR output), unrolled
loops, unsized arrays, signed or `int` counters, counts that are not numbers. Memory safety of the
erased accesses follows from the proof only to the extent items 1 and 2 hold.

## Certificate checker (`bcecheck.om`)

`bcecheck SRC BCE.ERR BASE.ERR` reads the unit, the stderr of `om2 diag bce` and the stderr of
`om2 diag` of the same unit, and admits each `forbnd` record only when the source line has `get A C`
or `put A C`, the nearest enclosing loop is `for C ulong K` (or `u64`) with that number count and not
`unroll`, no body line starts with `C`, `A` has declared length `L` in that scope, `1 <= K <= L`,
and the run without bce has exactly one more trap site on that line per record (and in total
`sites(base) - sites(bce) = records`). It is seeded Omega built by the compiler under test; it uses
no code of omc. It is an independent re-derivation of the premises for every erasure omc claims,
and a check that no check was dropped without a record.

On the corpus (every checked-out unit whose lead is `om2` or `om2 diag`): the checker admits every
record omc writes (see the profile receipt). On kemu: `BCECHK PASS records=24 refused=0
sites_base=464 sites_bce=440`.

## Gate (`seed/host/check.sh`)

- `bce.cases` (59 cases, gate.om): run results of every fixture under `om2` and `om2 bce` (both must
  give the same exit), byte equality where the rule must not fire (`kept.om`), the stderr
  certificates (`cert/*.err`), the lead words, the x86 target, and the checker on 6 real certificates
  (`chk-ok-*`, admitted) and 15 forged ones (`chk-f-*`, refused: a wrong count, length or line, a
  dropped or truncated record, a written counter, K > len, a non-counter index, an unsized view, a
  text, a uint counter, a value count, K 0, an unrolled loop, and records checked against the bce run
  itself).
- `mutants.cases` (18 cases): 6 mutants of omc.om (`klen`: no K <= len; `scan`: no body scan; `reg`:
  any index; `depth`: the scan ignores nesting; `rec`: the record drops; `lead`: bce without the lead
  word) and 3 of bcecheck.om (`ck-body`, `ck-len`, `ck-sites`). Each mutant is killed by a fixture
  (exit or bytes change, or a forged certificate is admitted), and its `ctl-` twin shows the mutant
  still passes a case the change does not touch. Expected `OM2GATE FAIL cases=18 pass=9 fail=9`.

Fixtures: `sum`, `shapes`, `kept`, `diag`, `kgt`, `written`, `written-eq`, `written-nested`, `idx`;
exit values computed with Wolfram (listed in each fixture's notes).

## Benchmark (`bench/`)

`bench/run.sh OUT N` builds each workload under `om2` (A) and `om2 bce` (B) with the committed omc,
requires the same exit and stdout from both, then times N alternating runs of each with
`bench.om` (fork to waitpid, `monons`). Workloads: `mb-sum` (one erasable `get` per element),
`mb-axpy` (three erasable checks per element), `mb-ctl` (variable count: no erasure, the control),
`kemu` (the real SASS emulator `seed/kflow/kemu.om` on `sm121/resadd.c.bin radd 7`, which reports
`result=MATCH` in both arms), and compile time of kemu's source with and without `bce`.

Receipt (`receipt-core8.txt`, `receipt-core9.txt`: Spark GB10, Cortex-X925 core 8 and core 9 in two
runs, `nice -n 10`, N = 200 per arm, omc a0b21072, the committed bench.om, git head 7694ccba; medians
in ms, change B vs A; arithmetic by Wolfram):

| workload | A om2 (core 8) | B om2 bce (core 8) | change (core 8) | change (core 9) |
| --- | --- | --- | --- | --- |
| mb-sum | 24.747 | 21.285 | -13.99% | -14.02% |
| mb-axpy | 52.856 | 42.339 | -19.90% | -19.90% |
| mb-ctl (control) | 42.328 | 42.334 | +0.01% | +0.03% |
| kemu radd | 1.142 | 1.030 | -9.80% | -10.13% |

An earlier pair of runs of the same artifacts (bench.om before its exit-code guard was narrowed to
126 / 127) gave -14.01 / -14.02, -19.91 / -19.91, +0.02 / +0.02 and -10.75 / -10.20%.

Artifact sizes (bytes, A / B): mb-sum 388 / 356, mb-axpy 516 / 436, mb-ctl 420 / 408, kemu
36768 / 36420. Every workload's one-time initialization loop `for i ulong 4096` / `put a i ...` is
erased in B, mb-ctl's too; mb-ctl's timed loop (count in a variable) is not, so its B arm runs the
same timed code as A and its +0.01 to +0.03% is the noise floor of the method.

Allocations and bytes copied: not measured (NOT_RUN as a metric). The rule removes only
compare-and-branch instructions and allocates or copies nothing; the arms differ in those
instructions (the artifact sizes above), not in their arrays.

Compile time of kemu's source: 1.1126 ms without `bce`, 1.1261 ms with it on core 8 (+1.22%);
1.1087 / 1.1191 ms on core 9 (+0.94%) (pooled medians of both arms, each run includes process start).
Verification cost (`receipt-verify.txt`): `bcecheck` on kemu's 24 records 3.15 ms; the Lean check of
`OmegaBce.lean` with plain `lean` 2.06 s (median of 5 per arm). The proof is checked once per change of
the rule, not per compile; the checker runs once per certified build.

Without the proof: the erasure runs at the same speed with or without the Lean model (the proof costs
nothing at run time or compile time). What the proof removes is the trust in the rule's premises,
within the model. The Lean negative controls and the `klen`, `scan` and `reg` mutants show what an
unproved variant of the rule erases wrongly: each turns a trap 3 into a normal end.

## Static profile (`bench/profile.sh`, `bench/profile-receipt.txt`)

Every tracked `.om` whose OM-2 lead is `om2` or `om2 diag` (241 units on this branch), compiled with
`om2 diag` and `om2 diag bce`: 3797 trap sites, 60 erased (1.58%) in 24 units, 0 inconsistencies
(site arithmetic, byte identity where nothing is erased); the certificate checker passes on all 241
units and admits all 60 records. kemu alone: 24 of 464 sites (5.17%). The other sites are indexes the
rule does not cover (this receipt does not classify them by reason); the run-time share in a hot
loop is what the benchmark measures.

## Binding (what the evidence is about, by hash)

| object | sha256 |
| --- | --- |
| `seed/out/omc` (the compiler that implements the rule) | `a0b21072586bc8ce19b0ca14642b978a7a5a232f6f686ef72430e1206803049b` |
| `seed/omc/omc.om` (its source; fixpoint by `seed/omega-from-seed.sh`) | `256caefe0c4d55badac8ac2f22ef4e8bd8bc867f635267662902765b4c1db339` |
| `lean/OmegaBce.lean` (model, transformation, theorems) | `c4672908114e1e65aa4d8f49b8ac96cdd77559407001ea306f86a71c2d3e5d7c` |
| `bcecheck.om` (certificate checker) | `fa44170342af1275e548159a15a17573cb94d99fa5d5a2e48e3b52bcff495c98` |

Lean toolchain `leanprover/lean4:v4.35.0`. The file has no imports (core Lean only, no Mathlib); it
checks with plain `lean FILE`. The benchmark receipts carry their own omc, kemu.om, bench.om and git head hashes
(`meta.txt` lines). The proof is development-time only: nothing of Lean runs in omc or in a compiled
program, and a unit whose premises are not met keeps its checks (the rule falls back, it never
refuses).

## Reproduce

```sh
sh seed/omega-from-seed.sh                       # omc fixpoint a0b21072
sh seed/host/check.sh                            # includes the bce gate and mutants
flock -o POOL taskset -c CORE nice -n 10 sh seed/omc/om2/bce/bench/run.sh OUT 200
sh seed/omc/om2/bce/bench/profile.sh seed/out/omc OUT2
sh seed/omc/om2/bce/lean/negctl.sh LEAN_PROJECT OUT3   # a lake project on Lean v4.35.0
```

Agent: t_6ff77933 (Hermes worker, claude-opus-5-5, anthropic)
