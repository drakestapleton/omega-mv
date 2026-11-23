# Reproduce the selection experiment on AArch64 Linux

Use the repository seed compiler, Python 3.11+ for the outside judge, and the CPU
sampler and model files named in the combined solver README. The model files are
private. The published per-task responses can be audited without them.

For the traversal repair and rerun, use source
`a5ec28b33a5950bbd98fa30f19945cb47f9932a9`. Both kits use the repaired
expression synthesizer. The baseline alone uses the sketcher from the verifier
fix. After building the two kits, install the identical sampler, merge table
and private checkpoints listed in the combined solver README in each kit. The public audit below needs none of these
model assets.

From the repository root, set `BASE` and `IMPROVED` to two new absolute kit paths.

```sh
set -eu
E=train/omega-llm/tools/combined/experiment
sh seed/omega-from-seed.sh
train/omega-llm/tools/combined/build.sh "$BASE"
train/omega-llm/tools/combined/build.sh "$IMPROVED"
git show e522d8a124b388473d4705ba524a46cf56f8476d:seed/helix/ollm_factory/om_sketch.om > "$BASE/old-sketch.om"
"$BASE/omc" < "$BASE/old-sketch.om" > "$BASE/om_sketch"
"$E/build.sh" "$BASE"
"$E/build.sh" "$IMPROVED"
# Install the private model assets in both kits for the CLI runs below.
python3 "$E/fixture.py"
(cd "$E" && python3 -m unittest test_selection)
python3 "$E/measure.py" dev dev-before --kit "$BASE" --rewrite-only --jobs 5
python3 "$E/ablate.py" "$IMPROVED" dev-sketches
python3 "$E/measure.py" eval fresh --kit "$BASE" --improved "$IMPROVED" --jobs 8
python3 "$E/summarize.py" fresh
```

The output directories must be new. All four arms seal their programs before the
judge opens final scoring labels. Compare `baseline` to `improved_cli` for the
sketch change, `improved_cli` to `fixed` for candidate selection, and `fixed` to
`adaptive` for query selection. Both selectors use symbolic candidates. The CLI
can also attempt the frozen neural fallback. The `seconds` field times selection,
including queries and compilation. Final scoring is timed separately. Sum of task
seconds is cumulative elapsed selection time across workers.

The sketcher recognizes optional experiment spec lines `skip N` (skip N matching
sketches) and `rewrites MASK` (bit 0 enables the scaled next-item update, bit 1
the scaled first-item update). Normal invocations select the first match and enable
both new patterns after the existing library. The proposed scale is drawn from the
spec constants or from an exact ratio in an observed update. Every emitted program
must satisfy all supplied rows, including all eight array cells.

`fixed` and `adaptive` enumerate both engines in a deterministic order. In addition
to later sketch matches, the harness varies constant order, projects answered
examples and permutes scalar arguments to produce alternative expression programs.
It checks every proposal against all observed answers before admission. Programs
that fail on unlabeled probes yield an undefined prediction. No reference is queried
to generate proposals. See `protocol.md` for scoring and advancement rules.

## Recorded interruption and diagnostic continuation

The first registered run, before the traversal repair, stopped before final scoring. The expression synthesizer exited
104 on the fixed task `eval-equal-offset-4` and the production CLI returned 70.
The receipt includes the public numeric spec. Passing it to
`om_synth solve INPUT_SPEC OUTPUT_FUNCTION` reproduces the component failure.
For that historical comparison, use the two kits recorded in the [interruption report](../../../../../evidence/OMEGALLM-SELECTION-20261123/REPORT.md), including the preceding synthesizer. First let the registered command stop.
Keep the output directory, then run:

```sh
python3 "$E/measure.py" eval fresh --kit "$BASE" --improved "$IMPROVED" --jobs 8 --diagnose-interruption
python3 "$E/summarize.py" fresh
```

The diagnostic harness checks the fixture and both kit fingerprints, retains the
sealed prefix and records execution errors separately. A failed candidate run has
no selected program. Only retained invocations have complete query accounting.
This diagnostic continuation is ineligible for promotion. The selection algorithm,
reference, input split, model weights and sandboxed executables have the same
hashes or source as the registered run.

## Replay the published grades using public source

From the experiment checkout, the following commands build the seeded compiler
and prediction instrument and execute every published answer on the frozen final scoring
inputs. The audit compares each observed verdict and first counterexample with
the receipt. The neural sampler and checkpoints are needed only to regenerate
the complete CLI comparison.

```sh
E=train/omega-llm/tools/combined/experiment
sh seed/omega-from-seed.sh
A=$(mktemp -d)
train/omega-llm/tools/combined/build.sh "$A/kit"
"$E/build.sh" "$A/kit"
python3 "$E/audit.py" evidence/OMEGALLM-FRONTIER-20261123/comparison.*.json "$A/kit" --replay-selection --jobs 6
python3 "$E/test_rewrites.py" "$A/kit"
```

The historical checked and prompt-only conditions use the improved kit. Run
`python3 train/omega-llm/tools/combined/regression.py "$IMPROVED" history --jobs 6`
from the repository root with a new output directory. The traversal checks use
`bash seed/helix/ollm_factory/neuro-symbolic-gate.sh` and
`python3 evidence/OMEGALLM-FRONTIER-20261123/controls.py`. The theorem file uses
Lean 4 with the standard library.
