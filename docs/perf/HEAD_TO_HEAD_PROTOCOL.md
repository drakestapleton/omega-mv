# Head-to-head protocol: Omega against llama.cpp on the same Spark

Bar P0 of `docs/OMEGA.md` ("measure them ourselves"). This is the protocol for a run; it is not a
result. Status of every row: NOT_RUN. Nothing here has been executed on the GB10: the two harness
scripts in `tools/h2h/` are checked on a host against a scripted stand-in for `nvidia-smi`
(`sh tools/h2h/selftest.sh`), which says their logic is right and nothing about what the GB10 driver
accepts.

The run needs the GB10 on the DGX Spark, an authorized GPU window and root for the clock lock. One
engine at a time, never killed mid-run.

## 1. What is compared

Two engines, one machine, one window, one model checkpoint, one prompt set given as token ids, one
output length, greedy decoding. Two rates per row: prompt processing (pp, prompt tokens per second)
and generation (tg, generated tokens per second), each with its own token count and wall time, never
blended.

A row is published as **same work** only when `tools/h2h/parity_check.sh` says `SAME_WORK` for the
two sides' declarations (section 6). Any other row is labelled with both sides' formats in the row
itself and is not called a same-precision comparison.

## 2. Machine state

- Chip exclusive and quiet: no other GPU client, load average and top processes recorded.
- Recorded before and after every round: GPU clock, power draw, temperature, performance state
  (`clock-lock.txt`), plus the CPU-side state the existing harness records.
- The window, the two engines' build commits and the binary hashes go in the receipt.

## 3. Clocks are locked, not only logged

Logging the clock tells us afterwards that rounds drifted. Locking it stops the drift. Every timed
round of both engines runs inside one lock:

```bash
tools/h2h/clock_lock.sh run max <out> -- <the timed rounds of both engines>
```

which is `nvidia-smi -lgc <mhz>,<mhz>` before, `nvidia-smi -rgc` after (also on INT, TERM and HUP),
with the clock read back after the lock and again after the rounds. `max` takes the driver's
`clocks.max.graphics`; a number in MHz pins that instead. The same target is used for both engines
and is written in the receipt.

| What happens | Exit | Meaning |
| --- | --- | --- |
| Lock accepted, clock read back at the target, still there afterwards | command's status | timings count |
| `-lgc` refused, or the clock cannot be read back, or it reads something else | 3 | `BLOCKED_HARDWARE`: no timed round starts |
| Clock left the target during the rounds | 4 | rounds recorded as drifted; not a timing |

Open point, to settle in the first window before anything is timed: whether the GB10's driver
accepts `-lgc` at all. It is a unified-memory SoC and `nvidia-smi` reports several fields as not
available on it. If the lock is refused there, the head-to-head is `BLOCKED_HARDWARE` under this
protocol. Falling back to "log and hope" would need a written amendment that says so in the table
(rows labelled *clock floating*, with the per-round clock trace beside them), not a silent downgrade.

CPU side: the X925 clock preflight of `tools/r15_machine_state.sh` runs first; a core that cannot
hold its clock blocks the run the same way.

## 4. Precision is named end to end

Matching tensor values in the checkpoint is necessary and not sufficient: the engines must also
compute at the same precision. Each side declares, and the receipt carries:

| Field | Omega side | llama.cpp side |
| --- | --- | --- |
| `source_checkpoint_sha256` | the HF safetensors set it loads | the HF safetensors set the GGUF was converted from (must be the same set) |
| `weights_format`, `weights_sha256` | safetensors, per-file hashes | GGUF, file hash, plus the `convert_hf_to_gguf.py` / `llama-quantize` commit and command |
| `weights_dtype` | what the kernels read (for example `f16`, `bf16`, `fp8-e4m3`) | the GGUF file type (for example `f16`, `q8_0`, `q4_k_m`) |
| `activation_dtype` | compute precision of the forward pass | same |
| `kv_cache_dtype` | dtype of the stored K and V (and DeltaNet state where the model has it) | `--cache-type-k` / `--cache-type-v` as launched (`f16` unless set) |

Rules:

- Nothing is left at "default": the launch command names the value and the declaration repeats it.
- **Same-precision row.** Both sides at the same `weights_dtype`, `activation_dtype` and
  `kv_cache_dtype`. The only format both engines can be asked for without conversion loss is 16-bit
  float weights with a 16-bit KV cache (an F16 GGUF made with `--outtype f16`, no `llama-quantize`
  step). This is the row that answers "which engine is faster at the same work".
- **Format rows.** Omega FP8 (E4M3 float) against GGUF `Q8_0` (8-bit integer blocks with a scale),
  and Omega 4-bit against `Q4_K_M`, are different encodings with different arithmetic even at the
  same bit width. They are worth measuring because they are what each engine ships, but they are
  labelled with both formats, for example "FP8 E4M3 | Q8_0", and `parity_check.sh` will say
  `DIFFERENT_WORK` for them. Each such row also needs an output-quality figure on both sides (same
  prompts, greedy, agreement with the 16-bit reference tokens), since a faster format that changes
  the answers is not a win.
- A KV cache at a different dtype from the other side (for example an FP8 KV cache against F16) makes
  the row a format row, whatever the weights are.
- No Q4_K_M against F16, in either direction, in any table.

## 5. Tokenization is the same on both sides

- One tokenizer: the checkpoint's `tokenizer.json`, hash in the receipt. The GGUF's vocabulary must
  come from that file.
- The chat template is applied once, by the harness, with the checkpoint's own template. Both
  engines receive the finished prompt, never a message list: llama.cpp through `/completion` (not
  `/v1/chat/completions`, which would apply the GGUF's template a second time).
- BOS is declared (`bos=none` for the Qwen family, whose tokenizer adds none) and the GGUF's
  `add_bos_token` must agree. No engine adds one on its own.
- Prompts are fixed as token-id lists made once with that tokenizer, and both engines are fed the
  ids. As a check that the tokenizers really agree, llama.cpp's `/tokenize` of each prompt text must
  return exactly those ids; one mismatch stops the run.
- Per prompt, the prompt-token count each engine reports having processed must equal the length of
  the id list, with prompt caching off (`cache_prompt: false`) so every round reads the whole prompt.
  The list of counts is hashed into `prompt_token_counts_sha256`; unequal counts mean the pp figures
  are not comparable and the row is not published.
- Output length is fixed (`output_tokens`), end-of-sequence does not shorten a round (a round that
  stops early is rerun on a prompt that does not), sampler is greedy on both sides, context size is
  the same.

## 6. Declarations and the parity check

Each side writes a `key=value` file with the fields of sections 4 and 5 (`engine`, `engine_commit`,
`weights_format`, `weights_sha256`, `source_checkpoint_sha256`, `weights_dtype`, `activation_dtype`,
`kv_cache_dtype`, `tokenizer_sha256`, `bos`, `chat_template_applied_by`, `prompt_set_sha256`,
`prompt_token_counts_sha256`, `output_tokens`, `sampler`, `context_tokens`).

```bash
tools/h2h/parity_check.sh omega.decl llamacpp.decl
```

Exit 0 `SAME_WORK`; 1 `DIFFERENT_WORK` (a format row, labelled as such); 3 a field is missing or is
`default`/`unknown` (no row). Its output goes in the receipt next to the numbers.

## 7. Rounds

- One untimed warm-up round per engine per configuration, then five timed rounds. Engines alternate
  (A B A B ...) inside the one clock lock so slow thermal change falls on both.
- Reported per row: every round's value, the median, the mean and the sample standard deviation.
  With five rounds the standard deviation is still a rough figure and is described that way.
- Cross-check, llama.cpp side only: `llama-bench -r 5` with the same GGUF, `-p` and `-n` at the
  row's prompt and output lengths. `llama-bench` times synthetic token sequences, not our prompts,
  so it checks that the server-path rate is in the right place; it is not the row's figure. A
  server-path median outside the `llama-bench` mean by more than its spread is explained before
  anything is published.

## 8. What is published

The table, every round, both declarations, the parity output, `clock-lock.txt`, the launch commands
and the logs, as a content-addressed receipt naming the exact commits, labelled measured-by-us.
Host checks of the harness are never reported as a hardware result.

## 9. Host check of the harness

```bash
sh tools/h2h/selftest.sh
```

33 checks: a held lock, target from the driver's maximum, command status passed through, release
after failure and after TERM, a refused lock, an unreadable clock, a lock that is accepted but not
held, drift during the run, and the parity verdicts (same work, Q4_K_M against F16, KV-cache dtype,
unequal prompt-token counts, `default` as a non-value, a missing field).
