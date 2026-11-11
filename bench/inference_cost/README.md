# Inference-Cost Benchmark: Tokens per Verified Program

This benchmark measures the metric from Drake Stapleton's Omega/encoder essay,
**verified programs produced per unit of inference cost**. It compares Omega, C, Python and Rust on the
same 20 held-out tasks.

A model writes one function per task. The harness compiles it, runs it on hidden inputs and compares
the output. Token counts come only from the `usage` object the endpoint reports; nothing is estimated.

Two arms run for every language:
- **plain**: the same two messages (system, user) are sent for up to K attempts.
- **feedback**: after a failed attempt, the conversation grows by the model's code (assistant) and a
  user message holding the compiler's diagnostic, or "wrong results (exit status N)". Omega candidates
  are compiled as `om2 diag` units, so the feedback carries both `omc: line N: error K` and the
  `omc-diag 1 code=... line=... col=...` record.

Each task stops at its first verified attempt.

## Run against a real model

The model server must be up first. This harness never starts one.

```sh
sh bench/inference_cost/driver.sh --run-model --endpoint http://127.0.0.1:18091 --model <model-id> \
    --langs om,c,py,rs --arms plain,feedback --attempts 3
```

- `--endpoint` is required and has no default; requests go to `<endpoint>/v1/chat/completions` with
  `"stream":false`.
- The other options and their defaults are `--temperature 0.2`, `--max-tokens 4096` and
  `--out build/inference_cost/run-<utc>-<pid>`.
- A missing endpoint, a curl failure, a non-200 status other than 503, or a body without `usage` (or
  with an `error` member) prints `NOT_RUN: ...` and exits 3. Logs written up to that point are kept.
- HTTP 503 means the endpoint is busy (the live server generates one reply at a time and answers a
  concurrent request with 503). The same request is sent again every `BENCH_BUSY_SLEEP_S` seconds
  (default 2) until another status comes back; once `BENCH_BUSY_WAIT_S` seconds (default 1800) have
  passed since its first send, the run is NOT_RUN exit 3 (`BENCH_BUSY_WAIT_S=0`: no retry). A 503
  carries no usage and adds no tokens; the attempt's wall time starts at the request that was answered.
- `--out` must be absent or an empty real directory, including hidden files. Symbolic links
  (including names with trailing slashes) and nonempty directories are refused with exit 2 before
  any run files change. An atomic, persistent `.inference-cost-owner/` marker allows exactly one
  invocation to claim the output; a post-claim emptiness check closes concurrent creation races.
  Completed, interrupted and already-claimed runs are never reused.
- `--langs` and `--arms` require nonempty comma-separated lists without empty elements.
- Bubblewrap is mandatory and fails closed: missing `bwrap` or unavailable namespaces give NOT_RUN
  exit 3, never unsandboxed compilation or execution. GNU `timeout`, system Python, C and Rust
  toolchains are required for the corresponding self-test paths.
- Every sandboxed compile and run has a kernel-enforced memory ceiling (see "Memory ceiling"). If it
  cannot be applied the driver gives NOT_RUN exit 3, never an unbounded run. `BENCH_MEM_MAX_BYTES`
  sets it (67108864 to 4294967296; anything else exits 2); the default is 536870912.

The run directory holds:

| file | content |
|---|---|
| `run.txt` | endpoint, requested model, `models_reported` (the ids the endpoint returned), options, omc sha256, `task_set_sha256`, `memory_max_bytes`, times |
| `calls.txt` | one line per HTTP call: task lang arm attempt http_code model prompt completion total http_ms |
| `busy.txt` | one line per attempt: task lang arm attempt, the 503 answers before it was answered, and the ms spent waiting |
| `memory.txt` | one line per attempt: task lang arm attempt, the peak bytes of the compile and of the run (`-` when not run), and `none`, `compile` or `run` for a kill by the memory ceiling |
| `attempts.txt` | the attempt wire, version 2, read by `scorer.om` |
| `summary.txt` | the scorer report |
| `<lang>/<arm>/<task>/conv/` | the messages sent |
| `<lang>/<arm>/<task>/a<N>/` | request.json, response.json, candidate, compiler and run output |

The driver prints one line per (lang, arm): verified/attempted tasks, attempts, first-attempt
verified, total tokens, tokens per verified program, verified per 1k tokens and verified per minute.

`task_set_sha256` names the exact tasks and prompts of a run: `(cd bench/inference_cost && find tasks
prompts -type f | LC_ALL=C sort | xargs sha256sum) | sha256sum`, first field. Runs with different
digests were given different tasks or prompts and are not comparable.

## Not run yet

- **No complete real-model run exists.** The first real run (2026-11-11, `qwen3.6-35b-a3b-fp8` on the
  local endpoint, this driver at `3ab566f8`) ended NOT_RUN when the endpoint stopped answering. Seven
  of its eight (language, arm) groups had finished and are filed as a partial result in benchmarks-mv
  (`rad:z2nYCN9XZAPjNohqT8bz46rcs9zvZ`, commit `1031e01a`, `evidence/inference-cost-qwen36-20261111/`).
  The three-run result and the frontier line are NOT_RUN (no authorized frontier endpoint).
- Wall time in the self-test is the fake model's latency plus local compile and run time. It says
  nothing about inference speed.

## Self-test and task check

```sh
sh bench/inference_cost/driver.sh --check-tasks   # every reference verifies, every mutant is rejected
sh bench/inference_cost/driver.sh --self-test     # also run by `make test-inference-cost`
```

`--self-test` performs these checks, in order:

1. **Build.** Checks the compiler pin: the sha256 of `seed/out/omc` must equal `seed/out/omc.sha256`,
   otherwise NOT_RUN exit 3. Then builds `scorer`, `chat` and `fake_model` into
   `build/inference_cost/bin`.
2. **Scorer rejections.** Both wire versions reject trailing rows, contradictory compile/verified
   flags, nonboolean flags, skipped/repeated attempts, and attempts after a task has verified.
   Interleaved task identities count once, separately in each language/arm group.
3. **Chat edge.** An error object, a body without usage, and a non-JSON body each give exit 4.
4. **`--check-tasks`.**
5. **Fake-model runs.** `fake_model` listens on an ephemeral 127.0.0.1 port, and every reply reports
   usage 111/37/148. Five runs, all over om, c, py and rs:

   | mode | arms, attempts | expected |
   |---|---|---|
   | `good` | plain, 1 | 20/20 per language, with exact token sums, no 503, and run.txt naming the task set |
   | `bad` | plain, 1 | every mutant compiles and none verifies |
   | `bad-then-good` | plain + feedback, 2 | feedback verifies all 20 on attempt 2 with both attempts' tokens summed; plain verifies 0 |
   | `refuse` | plain, 1 | compiles 0 and verifies 0, and no binary is ever run |
   | `busy` | plain, 1 | every request answers 503 once, then 200: 20/20 per language with the token sums of `good` |

   The task-set digest of a copy of `tasks/` and `prompts/` equals the driver's, and one added byte in
   `tasks/task01/expected.txt` or `prompts/system-om.txt` changes it.

6. **NOT_RUN paths.** An unreachable endpoint (the fake is killed first), an HTTP 404, a missing
   `--endpoint`, `busy` with `BENCH_BUSY_WAIT_S=0`, and the `down` fake (503 on every request) past
   `BENCH_BUSY_WAIT_S=1` each give exit 3; a nonnumeric `BENCH_BUSY_WAIT_S` gives exit 2.
7. **Adversarial boundaries.** Oracle-reading Python, host writes, C/Rust compile-time oracle reads,
   a TERM-ignoring process with a descendant, an unavailable sandbox, empty workloads, reused or
   symlinked output directories, and competing output claimants are permanent shell-driven controls
   in `audit.sh`; a namespace init that never exits is refused NOT_RUN by the teardown wait below.
   Good, bad, mixed-arm and
   compiler-refusal runs assert both the group and global PASS/FAIL strings, not only counters.
8. **Memory ceiling** (`audit.sh`, `memory_checks`). Per language, a correct task01 candidate that
   first writes every page of the ceiling plus 256 MiB is killed and scored wrong (`MEM_KILL=run`),
   and the same candidate at half the ceiling verifies. A mutant driver with the ceiling line
   removed lets the over-ceiling C candidate verify, so it fails that check. A `systemd-run` that
   runs the command outside a new scope, and one that cannot reach the user manager, each stop
   `--run-model` at the preflight (NOT_RUN exit 3, no run directory) and a compile at the sandbox
   (NOT_RUN exit 3); a `systemd-run` that fails once before any scope exists is retried and the
   reference verifies with the failure kept out of its stderr; `BENCH_MEM_MAX_BYTES` of 0, 67108863,
   4294967297 and `1G` exit 2. The `good`
   run's `memory.txt` shows compile and run peaks below the ceiling and no kill for every attempt.

## Handover rule

`handover.om` decides, from scoreboard results only and with no person in the loop, whether a
candidate model takes over one job (a language and an arm) from the incumbent model. **No real
handover has been decided yet**: every verdict so far comes from the TEST DATA in
`tests/handover/data/`, hand-edited copies of a fake-model self-test run.

```sh
{ printf 'om2\n'; cat om/tls/sha2.om; sed '/^fn main to int$/,$d' bench/inference_cost/scorer.om
  cat bench/inference_cost/handover.om; } | seed/out/omc > handover && chmod +x handover
./handover LANG ARM PERMFILE INCUMBENT_RUN CANDIDATE_RUN...
sh bench/inference_cost/tests/handover/run.sh   # also run by `make test-inference-cost` and `make test-handover`
```

The inputs are one incumbent run directory and the candidate run directories (each written by
`driver.sh --run-model`, holding `run.txt` and `attempts.txt`), the job, and a permanent-case list:
a file of task ids, separated by whitespace, that must never fail again (it may be empty).

The rule, in integer counts only:

1. **Comparable.** Every run names the incumbent's `task_set_sha256` and `omc_sha256` and has
   records for the job; every candidate run reports exactly one model and has the same
   `model_requested` and `models_reported` as the first candidate run. Otherwise the answer is
   REFUSED, never NO and never YES.
2. **Enough evidence.** At least 3 candidate runs, in distinct directories (compared by device and
   inode, so `a` and `./a/` are one directory) with distinct `started` times. Otherwise REFUSED.
3. **Not worse.** In every candidate run, the number of verified tasks for the job is at least the
   incumbent run's number. Equal counts pass.
4. **Permanent cases.** In every candidate run, every permanent case is verified for the job.
5. **Complete runs.** A run with a line starting `NOT_RUN` or `interrupted` in `run.txt`, a
   `NOT_RUN` file, no `finished` line, a leftover `rows.txt` (the driver stopped before writing
   `attempts.txt`), no `run.txt` or `attempts.txt`, or an `attempts.txt` that the scorer refuses
   (truncated or malformed, or version 1, which has no language or arm) makes the answer REFUSED.

REFUSED (rule 1, 2 or 5) wins over NO; the answer is NO when rule 3 or 4 fails, and YES otherwise.
The first output line is exactly `HANDOVER YES`, `HANDOVER NO` or `HANDOVER REFUSED`. One line per
rule follows with the counts that decided it (rules 3 and 4 say `NOT_EVALUATED` when the answer
is REFUSED), then `sha256 <hex> <path>` for the permanent-case list and for each run's `run.txt` and
`attempts.txt` in argument order, so the decision can be rechecked from the same files. Exit
status: 0 YES, 1 NO, 2 REFUSED, 3 usage (fewer than one candidate, an unknown language or arm, an
unreadable permanent-case list; nothing is printed on stdout).

The wire is read by `scorer.om`'s own functions and tables, unchanged: the build leaves out only
scorer.om's `fn main` (a unit has one main), and `handover.om` repeats that main's version-2 header
loop. The scorer stops the process with exit 2 on a malformed wire, so each `attempts.txt` is
first read in a forked child; the parent reads it again only after the child exited 0. Digests
come from `om/tls/sha2.om`. The files must not change while the program runs.

`tests/handover/run.sh` runs the known-verdict cases in `tests/handover/cases.txt` (every outcome
and rule; equal counts is YES; one run one task short is NO; a permanent case failed in one of
three runs is NO; two runs, duplicate start times, the same directory twice, mixed task-set
digests, another omc, another candidate model, a NOT_RUN marker, an interrupted run and a
truncated wire are REFUSED; usage errors exit 3), checks the printed digests against `sha256sum`,
and builds each mutant in `tests/handover/mutants.txt` from a temporary copy of `handover.om`
(`at least` made `more than`, every made any for rules 3 and 4, the comparability check removed,
the run-count check removed). It exits 1 if any case fails or any mutant passes every case.

## Files

| file | role |
|---|---|
| `driver.sh` | POSIX sh glue: assembles candidates, runs compilers and curl, writes records |
| `chat.om` | the only JSON code (composed with `seed/json/json.om` and `jsonw.om`). `chat req` turns the request wire into the OpenAI request body. `chat resp` reads a response: usage, model id, and the code block (after the last `</think>`, the first fenced block) on fd 3 |
| `fake_model.om` | an OpenAI-compatible fake on `seed/net/http.om`. Modes `good`, `bad`, `bad-then-good` (reference only when the conversation has 3 or more messages), `refuse`, `busy` (503 on every other request) and `down` (503 always). Uses headers `X-Bench-Task` and `X-Bench-Lang` |
| `scorer.om` | reads the attempt wire (v1 or v2) and writes the summary |
| `io.om` | stdin/stdout helpers appended after an Omega candidate |
| `audit.sh` | permanent F1-F8 adversarial self-test controls, sourced by the driver |
| `prompts/system-<lang>.txt` | system prompts; the Omega one is a compact language primer |
| `tasks/taskNN/` | `statement.txt`, `spec.txt`, `inputs.txt`, `expected.txt`, and `reference.<lang>` plus `mutant.<lang>` for om, c, py and rs |

## Candidate assembly and verification

The model writes only the function. The harness appends a stdin driver generated from `spec.txt`: it
reads `inputs.txt` and prints one decimal per case. A candidate is verified when:
- it compiles with exit 0;
- the run exits 0 within 10 s (TERM at 10 s, hard KILL after a further 1 s);
- its output equals the cases of `expected.txt` byte for byte.

A compiler refusal is never verified and its output is never run.

Both compilation and execution happen in separate bubblewrap sandboxes with all namespaces
unshared, no network, a cleared environment, no home/credentials or checkout mount, a fresh `/tmp`,
and read-only candidate and system runtime mounts. Compiler sandboxes additionally expose system
headers/tools; Rust exposes only the selected toolchain's compiler and libraries, not its home.
Inputs enter on stdin and compiler/runtime output leaves on stdout/stderr. The verifier and all
oracle files remain outside. Compilation has the same bounded deadline as execution. Setup failure
aborts the run. A trusted shell inside the fully configured sandbox closes all inherited caller
descriptors except stdin/stdout/stderr and its dedicated readiness descriptor. It emits a readiness
handshake, closes that descriptor, then executes candidate-controlled code. The host requires that
handshake for compilation and execution; bubblewrap namespace JSON alone is not readiness evidence
because it is emitted before mount setup. Permanent tests exercise late compiler/runtime mount
failures with real bubblewrap and assert NOT_RUN, descriptor closure, and denial of inherited host
file reads at both compile time and runtime. After each compile and each run the driver waits up to
5 s for the sandbox's namespace init (bubblewrap's `child-pid`) to be gone and gives NOT_RUN if it
is not: after a deadline kill the teardown finishes asynchronously (seen once in 15 tries with the
memory ceiling in place, gone 1 s later), and nothing may outlive its attempt.

**Memory ceiling.** Each compile and each run executes inside a transient cgroup scope, `systemd-run --user --scope -p
MemoryMax=<ceiling> -p MemorySwapMax=0 -p OOMPolicy=continue`, around bubblewrap. The kernel counts
every process of the scope (launcher, bubblewrap, compiler or candidate and all their children) and
OOM-kills inside the scope when the ceiling is reached, so a candidate cannot take memory from the
host or from the model server. The scope's first process reads back its own cgroup's `memory.max`
and `memory.swap.max` and runs nothing unless they are exactly the ceiling and 0; after the command
it writes `memory_peak_bytes` and `memory_oom_kills` beside bubblewrap's JSON on descriptor 4. A
compile with an OOM kill never counts as compiled, and a run with an OOM kill is a failed attempt
whatever it printed; both are recorded in `memory.txt`, and the feedback arm tells the model its
code (or the compiler) was killed for exceeding the ceiling. When `XDG_RUNTIME_DIR` is unset the
driver uses `/run/user/<uid>` to reach the user manager. A `systemd-run` that fails before its scope
started (seen once under load: "Failed to start transient scope unit: Transport endpoint is not
connected") has run nothing, so it is tried again, 5 times in all, 1 s apart, and only then reported
(NOT_RUN). Exercised with systemd 255 on Linux 7.0
(cgroup v2, memory controller delegated to the user manager).

The ceiling was set from measurement: `--check-tasks` was run four times with a 4 GiB ceiling (three
times with omc `1e628c80`, once with omc `2495bc25`) and the scope peak of every compile and run read
from `memory.peak`. The heaviest was the Rust compile of `task01/reference.rs`, 100696064 bytes
(about 96 MiB); the heaviest runs were 5775360 bytes (Python) and 2150400 bytes (Rust), and Omega
compiles stayed under 2.2 MB. The default ceiling, 536870912 bytes (512 MiB), is 5.33 times the
heaviest peak (416 MiB above it).

The host dependencies exercised here are bubblewrap 0.9.0 (Linux namespaces/mounts), GNU coreutils
`timeout` 9.4 (host deadline), Bash 5.2.21 (sandbox-only trusted launcher, mounted as `/usr/bin/sh`)
and systemd 255 `systemd-run --user --scope` (memory ceiling).
The driver itself remains POSIX sh. The launcher needs arbitrary numeric descriptor redirections,
which dash cannot perform above fd 9; it validates the kernel-provided numeric descriptors before
closing them. These are isolation/verification infrastructure, not Omega implementations. Their
Omega replacement would require a qualified namespace/mount, process-tree and descriptor supervisor;
no such replacement is claimed here.

| lang | assembled as | compile |
|---|---|---|
| om | `om2 diag`, candidate, `io.om`, generated `fn main` | pinned `seed/out/omc` |
| c | candidate, generated `main` | `cc -O2 -include stdint.h -include stdio.h -include stdlib.h ... -lm` |
| py | candidate, generated `_bench_main()` (the result must be an `int`) | `python3 -m py_compile`, run with `python3 -I` |
| rs | candidate, generated `fn main` | `rustc -O --edition 2021 -A warnings` |

For an Omega candidate, line 1 of the compiled unit is the added `om2 diag` line. A leading `om2...` line
written by the model is dropped.

## Wire formats (plain text, no JSON)

### Task specification (`spec.txt`)
```text
version 2
name <function_name>
param <name> <u32|i32|u64>      (one line per parameter, in order)
ret <u32|i32|u64>
```

### Hidden inputs and expected outputs
```text
version 1
cases <N>
<arguments for case 1, or its expected value>
...
```

### Chat request wire (`chat req`)
```text
version 1
model <id>
max_tokens <N>
temperature <JSON number>
messages <K>
msg <system|user|assistant> <NB>
<NB bytes>
...
```
A malformed wire exits 2; a writer refusal exits 3.

`chat resp` writes `version 1`, `model`, `prompt_tokens`, `completion_tokens`, `total_tokens` and
`code_bytes` lines. It exits 4 on a missing usage object, an error object, no choices, or a body that
is not JSON.

### Attempt records (`attempts.txt`)
Version 2:
```text
version 2
attempts <N>
<task_id> <lang> <arm> <attempt_num> <first_attempt> <compiled_rc> <verified_flag> <wall_ms> <prompt_tokens> <completion_tokens> <total_tokens>
```
- `lang` is one of `om c py rs`; `arm` is one of `plain feedback`.
- `wall_ms` runs from the request until verification ends (model latency plus compile and run).

Version 1 (still accepted) has no `lang` or `arm` column:
`<task_id> <attempt_num> <first_attempt> <compiled_rc> <verified_flag> <wall_ms> <prompt_tokens> <completion_tokens> <total_tokens>`.

Rejection rules:
- An unknown version exits 3.
- A line count different from `attempts <N>`, a non-numeric field, or an unknown lang or arm exits 2.
- Input of 983040 bytes or more exits 2.
- `first_attempt` and `verified_flag` must be 0 or 1; a nonzero `compiled_rc` cannot verify.
- Task identity is exact within each language/arm group. Attempts start at 1, advance by one,
  mark only attempt 1 as first, and stop on verification. Repeated task successes are invalid,
  not additional verified programs. The same rules apply to version 1.

### Summary (`summary.txt`)
A version-1 input gives the version-1 summary (`version 1`, `tasks_total` ... `status`).

A version-2 input gives one block per (lang, arm) present, in the order om, c, py, rs × plain,
feedback:
```text
version 2
groups <G>
group <lang> <arm>
tasks_total <N>
attempts_total <N>
compiled_count <N>
verified_count <N>
first_attempt_verified <N>
total_prompt_tokens <N>
total_completion_tokens <N>
total_tokens <N>
total_wall_ms <N>
total_wall_seconds <N>
tokens_per_verified <fixed3>|none
verified_per_1k_tokens <fixed3>
verified_per_minute <fixed3>
status PASS|FAIL
end
...
status PASS|FAIL
```
- A group's `status` is PASS when every task in it verified.
- Exit status: 0 when every group passes, 1 when any fails (a valid result for a model run), 2 for
  malformed input, 3 for an unknown version.

The rates:
- `tokens_per_verified` $= T_{\text{total\_tokens}} / V$
- `verified_per_1k_tokens` $= (V \times 1000) / T_{\text{total\_tokens}}$
- `verified_per_minute` $= (V \times 60) / T_{\text{total\_seconds}}$

## Tasks

| task | function | computes |
|---|---|---|
| `task01` | `clamp_add_u16` | saturated 16-bit addition |
| `task02` | `absdiff_i32` | exact $\lvert a - b\rvert$ as u64 |
| `task03` | `popcount_u32` | set bits |
| `task04` | `gcd_u32` | greatest common divisor |
| `task05` | `isqrt_u32` | $\lfloor\sqrt{x}\rfloor$ |
| `task06` | `collatz_steps_u32` | steps to 1 under $3n + 1$ |
| `task07` | `bitrev_u16` | 16-bit reversal |
| `task08` | `fibonacci_u32` | $F_n \bmod 2^{32}$ |
| `task09` | `factorial_u32` | $n! \bmod 2^{32}$ |
| `task10` | `is_prime_u32` | primality |
| `task11` | `parity_u32` | bit parity |
| `task12` | `clz_u32` | leading zero bits |
| `task13` | `ctz_u32` | trailing zero bits |
| `task14` | `power_mod_u32` | $a^b \bmod 2^{32}$ |
| `task15` | `min3_i32` | minimum of three |
| `task16` | `max3_i32` | maximum of three |
| `task17` | `sum_digits_u32` | sum of decimal digits |
| `task18` | `reverse_digits_u32` | reversed decimal digits |
| `task19` | `hamming_dist_u32` | Hamming distance |
| `task20` | `rot_left_u32` | 32-bit left rotation |

Each `statement.txt` is language-neutral; the per-language signature is added to the user prompt.

## Reusing the referee (DRA-122)

Training-data admission reuses the same assembly, hidden inputs, exact-output comparison and mandatory
bubblewrap compiler/runtime sandboxes as benchmark attempts. It does not trust an old attempt verdict.

```sh
sh bench/inference_cost/driver.sh --verify-candidate om task01 \
  "$PWD/bench/inference_cost/tasks/task01/reference.om" "$PWD/build/referee-new"
sh bench/inference_cost/driver.sh --task-set-sha256
seed/out/omc < bench/inference_cost/verify-test.om > build/verify-test
chmod +x build/verify-test
build/verify-test "$PWD" "$PWD/build/verify-test-new"
```

The referee interface takes exactly LANG TASK_ID CANDIDATE ABS_WORK. LANG is om/c/py/rs; TASK_ID
must be an existing taskNN identity, not a path. Both paths must be absolute and traversal-free,
with no symlink component; CANDIDATE must be a regular file and ABS_WORK absent or an empty real
directory. ABS_WORK is claimed atomically and never reused. Its eval/ child retains the assembled
source, compiler diagnostics, stdout and sandbox readiness receipts. No model is called.

Statuses are 0 verified now, 1 compiled/run result did not verify (including compiler refusal),
2 refused arguments/paths, and 3 NOT_RUN (pin, dependency or sandbox unavailable). The printed
COMP_RC/RUN_RC/VERIFIED line is evidence about this execution, not an old verdict. The digest mode
uses exactly task_set_sha256(), the same definition written into run.txt; it takes no arguments.

verify-test.om exercises all four languages, wrong results, compiler refusal, unknown language/task,
traversal, candidate symlink, relative candidate, reused work, wrong compiler and unavailable sandbox.
Its three source-removal mutants must be caught: accepting wrong results, accepting task traversal,
and skipping the preflight sandbox check. The existing --check-tasks and --self-test modes retain
their prior contracts and checks.

These modes are part of the existing shell driver, still awaiting migration. The seeded-Omega
namespace/mount, process-tree and descriptor supervisor successor is **not yet written**. The
first-party dataset admission/serialization tool lives in aien-train/tools/verified_examples;
it does not duplicate this sandbox or claim the shell dependency is Omega.
