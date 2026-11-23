# Eight-query selection experiment

The unit is one task. Freeze the development and evaluation manifests, input pools,
references, and final scoring rows before developing the selection policy. Reserve
the 80 evaluation tasks for one run after development. The historical 165 tasks are
regression tests. The private checkpoint stays at SHA-256
`08fc55505c8fa6a094e30807e616b64e4ea6d186cd4ef769ed877e469bcaac91`.

Compare the corrected production CLI on the eight fixed rows with the experimental
selector on the same eight rows and on four fixed plus four adaptive rows. Also
measure the fixed CLI with the new sketches to isolate their contribution. Run the
two selection arms with the same generator build and order. Measure each proposed
rewrite separately on development, then together, against the original sketcher.
Report counts by task group, differences by task, elapsed seconds, query inputs and
counts, route and selected program. A correct answer must pass every final scoring
input. For rewrites compare the entire array, including the inactive tail.

Keep the trusted reference in the test harness. For each unanswered pool input
maximize the number of unordered pairs of surviving programs giving different
predictions. Ties take the first input in frozen pool order. With no disagreement,
take the first unused fixed input. Charge exactly one reference query for each new
observation. Regenerate proposals using only the available observations when the
survivor list empties. At eight answers choose the shortest surviving program in
UTF-8 bytes (canonical whitespace, one final newline), breaking ties by generator
order. An empty set means abstention. Solver errors stop the experiment.

Select the two development rewrite families with the most incorrect or abstaining
fixed-CLI tasks, breaking tied counts by family name. Preserve the baseline build
and measure each pattern with the other disabled. The adaptive method advances
only if it improves on the corrected fixed CLI in the fresh evaluation on all four
criteria: more correct answers, at most as many wrong answers, fewer wrong branch
answers and at most eight reference queries on every task. Publish all outcomes.
