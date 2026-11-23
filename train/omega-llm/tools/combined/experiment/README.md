# Reproduce the selection experiment on AArch64 Linux

Use the repository seed compiler, Python 3.11+ for the outside judge, and the CPU
sampler and model files named in the combined solver README. The model files are
private. The published per-task responses can be audited without them.

Build the corrected baseline kit from commit `e522d8a124b388473d4705ba524a46cf56f8476d`
and the improved kit from the experiment source commit recorded with the results.
Install the identical model assets in both. Build the prediction instrument in
both kits from the experiment checkout. It uses the verifier, compiler and
`execpure` runner and consumes inputs without expected outputs.

From the experiment source root, with absolute paths in `BASE` and `IMPROVED`:

```sh
E=train/omega-llm/tools/combined/experiment
"$E/build.sh" "$BASE"
"$E/build.sh" "$IMPROVED"
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
