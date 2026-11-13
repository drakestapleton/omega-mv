# Grow a trained Omega LLM

`ollm grow` adds trainable residual layers to an existing checkpoint. It keeps the
learned embeddings, original layers and final normalization gain byte for byte.
This is a capacity operation. A larger checkpoint is not evidence of better
reasoning, coding, conversation or held-out quality.

```sh
ollm grow INPUT.ck OUTPUT.ck LAYERS TOTAL LRMICRO
```

`LAYERS` is the new total depth, strictly greater than the input depth. All other
shape fields, the seed, gradient-block count and CK01/CK02 format are preserved.
The existing model geometry and memory-pool checks apply. `TOTAL` is a positive
training-step count accepted by `tune`; `LRMICRO` must be positive. The command
prints `G OLD_LAYERS NEW_LAYERS PARAMETERS`.

The output starts at step zero with zero Adam moments and the specified learning
rate and schedule, just as a fresh fine-tune does. Retaining moments while changing
the model is intentionally not supported. Use the same tokenizer as the input.
`train` consumes the ordinary output checkpoint. The GPU trainers use the same
checkpoint format, but growth followed by GPU training has not been exercised.
This change tests host training only.

On Linux, the normal checkpoint writer saves OUTPUT.ck through OUTPUT.ck.tmp. As with
`tune`, an existing output is replaced. Use a distinct output in a private working
directory and preserve the input. Do not target a served checkpoint or a path
another process is writing. Checkpoints derived from private data remain private.

## Initialization and storage

The own `oinit` initializer supplies the new layers' gains and input projections.
Their attention output projection (`Wo`) and feed-forward output projection
(`W2`) are then zeroed. Thus their residual contributions start at zero, while
the input projections are populated so that these branches can learn. Old layers
are restored without scaling. The final gain moves after the added layers.

The existing gradient cold store holds a snapshot of the input weights. Growth
increases the parameter count, so the new Adam region begins beyond this snapshot.
No new parameter-sized allocation, checkpoint format or inference kernel is added.
The existing parameter and activation banks handle the enlarged model. Added
layers still cost inference work before they learn; this is not a speed feature.

Non-finite source weights are refused with exit 54. Other checkpoint failures
retain their existing exit codes. A non-increasing or unsupported depth, invalid
schedule or zero learning rate returns 12; malformed arguments return 2. Invalid
requests do not call the checkpoint writer. Finite weights alone do not guarantee
that every possible input has finite intermediate activations; preservation is
checked on measured inputs, not asserted for arbitrary floating-point states.

## Verification

```sh
python3 tests/omegallm/grow-gate.py compilers.json /private/growth-gate --core 4
```

The release gate discovers the targets from `build.sh`, requires a local JSON
object mapping every target name to its pinned compiler path, builds every target,
and then runs the host growth checks. Keep the a64efi compiler with its existing
`../a64efi/efirt.om` companion. Missing compilers or a failed target stop the gate.
Compiling the GPU and EFI targets is not a claim of running growth on them.

The external Python instrument reuses the repository's independent checkpoint,
initialization and forward/backward oracle. It tests both checkpoint versions,
all preserved tensors, deterministic growth, sampled-token and held-out-loss
preservation, gradients and actual updates in new branches, training-resume
identity, repeated growth to the current depth boundary, invalid inputs and
non-finite weights. It repeats the checks using the reduced-bank variant built by
`build.sh`, and
checks preservation and non-finite refusals beyond the first snapshot chunk.
Native `eval` comparisons check the printed micro-nat and micro-bits-per-byte values, not
bitwise internal losses; the independent oracle also compares its unrounded
losses. The bitwise preservation claim applies to the saved learned tensors.
Compiled negative controls must be caught: nonzero attention/FFN outputs,
missing old weights, lost final gain, stale optimizer state, lost signed-zero bits,
dead new inputs and a truncated snapshot. Preservation compares packed tensor bytes
and includes a negative-zero source weight.
Python is not a product dependency.

Before promoting any grown checkpoint, train it and compare it with its source
on preregistered held-out tasks, including code and unanswered-question cases.
Preservation and trainability checks do not substitute for that quality test.
