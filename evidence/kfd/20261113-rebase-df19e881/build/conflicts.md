# Rebase resolution

Replayed all commits after c4e5e963 from amdserve/kfd-word (655126c08048c27ea5a01ce772a5ba62f339c371), except old repin 5374214664f55507cde1b5b75c44894461ca6a94, onto df19e881e4f1833d96d87fb9825933bdfed3b006 on amdserve/kfd-word-r2. Original branch retained. No push.

- 88436da90: CONTRIBUTORS.md conflict: retained both main's new attribution rows and the KFD row. seed/omc/size-history.tsv conflict: retained both main's generated row and historical KFD rows. seed/out/omc and seed/out/omc.sha256 conflicts: kept main's binary/pin during source replay; rebuilt the final combined source afterward, rather than checking in any old KFD compiler.
- 7bf05860f: seed/out/omc and seed/out/omc.sha256 conflicts: same derived-artifact policy.
- 655126c08: CONTRIBUTORS.md conflict: retained all main rows and the dated earlier KFD rebase attribution.
- seed/omc/omc.om and docs/one_layer/OMEGESE.md merged without textual conflict. Main's compiler work and KFD source were preserved.

First seed birth refused stale diagnostic identity, as designed. Inspected the generated-source diff: only d2pin changed. Copied build/seed/birth/diagnostics-source.om to seed/omc/omc.om and reran the normal birth procedure. This generated the diagnostic identity and size-history row using main's seeded diaggen; no hand-authored derived size fields.

Pin inventory: git grep of the main revision for its consumer pin (read from main's om/units.sh) is retained in main-pin-consumers.txt. Main's consumers still named 106558ba even though its committed compiler was 447b7175. The existing repin3 instrument in the previous evidence covers the discovered text consumers and regenerates the src bindings through om/units.sh. Used REPIN_WHAT='omc KFD words rebased with current diagnostic and module compiler work', REPIN_LANDING='Add checked KFD ioctl', REPIN_MAIN=df19e881. It regenerated bindings and checked byte identity. Historical evidence was not rewritten.

Hand-maintained artifact debt remains as previously recorded: compiler pin copies in main's discovered files are maintained by the external repin3 instrument, not a change-triggered repository generator. The source of truth is seed/out/omc.sha256; observed stale on main here (consumer 106558ba versus binary 447b7175). Fixing repository-wide pin architecture is outside this rebase assignment.

Host/emulator only. No AMD GPU or other GPU execution, service changes, sudo, deployment, merge, or push is authorized or claimed. The harness guides were not edited: no new word or language behavior beyond the existing KFD branch is introduced by this rebase.

The first full gate attempt then exposed two semantic integration defects not caught by textual rebase:

- KFD's four compile-time fail calls lacked the diagnostic-site annotations introduced by main. Added distinct site identifiers and descriptions without renumbering existing identifiers, then regenerated strings and source identity through seeded diaggen, rebuilt the compiler to fixpoint and repinned all current consumers again.
- The KFD test's function-mode compiler mutant expected adjacent semantic lines, but main's diagnostic annotations now separate those lines. The matcher permits only the known diagnostic note/store pair between semantic lines; it still requires exactly one complete match and compiles/runs every mutant. No check or negative control was removed.

The first make gate was interrupted by SIGTERM, not a gate verdict. See interruption.txt and interruption-record.jsonl. At Main's instruction, the complete gate set runs again in the fresh sibling clone omega-mv-r2-gate at final-source-head; the original failures and partial log remain separate evidence.
