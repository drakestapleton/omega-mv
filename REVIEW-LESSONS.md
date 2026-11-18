# Review lessons

Before requesting review, run the repository gate that owns every changed behavior.
For seeded compiler and front-end work this includes `tests/gates/run.sh seed`.
Its host qualification now runs the complete pool gate and front check parity;
the list of parity inputs lives in `seed/ng/front/check-lists.txt`.
Do not substitute a targeted pass or a lowering pass for the check-parity sweep.
Interrupted commands have no overall passing result. Preserve their logs.

## Host-keyword closure corrective action

A change that adds, removes or renumbers a host keyword runs
`seed/effects/check.sh` inside `tests/gates/run.sh seed`, before that gate's final
PASS. The run counts only if it prints the closure line (`host keywords == table`,
or `closure: host keywords differ from table`). Exit 3, `NOT_RUN`, or any other
exit that does not print that line is not a pass and is not proof the closure was
checked. A closure diff is a failing seed gate. A step that exists only in a
driver outside this repository does not count.

## Runtime-pools review corrective action, 2026-11-12

Three reviews occurred on the recovered runtime-pools change before its next
review. The earlier two exact heads were 7601292ef9d57074cba9a52f831b45227df3c15b
and 04e6492fbc61d3164729c5fa39f71f332e3c25b7; the third was
d1565dd84a5aaeb6deb4b94eb56c9aafd4797a0b.

| Round | Finding kind | Why author or checks missed it | Corrective action |
| --- | --- | --- | --- |
| 1 | NG scope dependency remained unresolved. The growth fallback observation was informational, not a defect. | Compiler and front-end evidence were maintained separately. | Full check parity now executes inside the seeded host gate. Unsupported pool forms retain an explicit scope declaration. |
| 2 | Diagnostic output was omitted from the memory budget. | Only artifact bytes were counted; stderr was not tested as a charged file. | The pending compiler candidate counts diagnostic records; its no-caps gate tests real-file diagnostic output under the caller ceiling. |
| 2 | Larger ceilings could regress from success to refusal. | A few sample budgets did not test monotonicity across compaction boundaries. | The pending compiler candidate no-caps tests sweep budgets across the boundary; in-place growth limits the high-water mark. |
| 2 | A mutant's successful exit was described as a safety failure. | The assertion and evidence label measured different claims. | State the actual differential outcome and memory measurement; never call an unobserved kill a caught safety defect. |
| 2 | Oversized environment entries silently removed the ceiling. | Ordinary malformed values did not exercise the environment-read overflow path. | The pending compiler candidate rejects an oversized entry with error 26 and tests that boundary. |
| 2 | NG usage fixture no longer produced its expected record. | A compiler input changed language scope while its consumer fixture did not. | The pending compiler candidate updates the scope fixture; this correction enforces the full parity gate. |
| 3 | Pool gate and complete front check sweep were omitted. | An intermediate driver was stopped; targeted and lowering checks were mistaken for complete replacement. OMEGA-SEED did not own either omitted gate. | Both now execute unconditionally inside the seeded host qualification, before its final PASS. A nonzero exit or missing final marker stops it. Pool selection overrides are removed within this standard run. |
| 3 | EFI log was not bound to source and compiler. | Log content alone lacked those identities. | Preserve the exact command, clean source head, compiler digest, exit code and log digest for checks outside the standard gate. The host gate emits source and compiler identity. |
| 3 | Protected gate changes lacked operator evidence. | Ordinary local runs were mistaken for the required operator run. | Changes under protected gate paths require the authorized Spark operator run and its evidence before landing. |
| 3 | Typed pins and handwritten status drift. | Copies can diverge from their source. | Derive the compiler digest and source head at execution. Record remaining historical pin duplication rather than claiming it is fixed by this change. |

The third review also found that the new NG refusal fixtures were absent from
the pool gate's explicit keyword-user inventory. The gate must keep rejecting
unknown users; inventory only the named intentional fixtures after inspecting
them, and retain the independent parity coverage. The inventory gate now refuses
entries that are not tracked Omega units or do not contain the excluded feature.
A pending fixture must be added by its own change, never exempted ahead of time.

This corrective change does not claim completion of the wider Omega roadmap,
hardware qualification, or the caller-ceiling feature's release. Those require
their own exact-head results and independent review.

## Admitted scalar storage and historical comparison controls

A scalar accepted in a struct declaration must have valid load and store
lowering. Boolean fields exposed a gap: the AArch64 opcode tables returned
zero for bool, while the NG numeric-conversion operation excludes bool.
Test true and false initialization, read and write, neighboring fields,
arrays and parameter access. NG represents bool cells through selection
and comparison, with validator, interpreter and native checks.

The no-pools compatibility reference remains the historical f615b139
compiler, with only its two missing bool opcode cases corrected. The
reference is rebuilt by that pinned historical binary from pinned source;
the corrected source and binary are independently pinned. The original
boolean crash and corrected execution are both checked. This permits the
intentional bug correction while keeping every corpus row in the byte
comparison and retaining the historical no-pools behavior.

## Compiler size record

The seeded build generates the source line/function counts, encoded word count and
compiler digest through diaggen size mode, and appends a row only for a new final
compiler identity. Do not hand-copy those measurements. The independent size-record
test checks content changes, exact counts and malformed executable refusals.

## DRA-485 evidence-text corrective action, 2026-11-17

The DRA-485 C3 GEMM change took four reviews (all FIX: d83bbc04, e823b59f, 0be0ba36, 0e50400f; verdict files
`~/handoffs/dra485-finish-20261117.VERDICT*.omega-mv.*.md` on the Spark). The CUDApp half of the same task took
three (FIX 5dc27c28, FIX 18ac3327, MERGE a283a896). No round found a wrong kernel result; almost every finding was
about what the evidence text said. A first RCCA after round 3 fixed the cases by hand (numbers recomputed once)
and round 4 found the same kinds again: a hand-typed range that the data contradicted and stale hand-typed counts.
A one-time recompute is not a corrective action; a generator and a gate are.

| Kind | Findings (round.number, both repositories) | Why the author and the checks missed it | Corrective action |
| --- | --- | --- | --- |
| Derived numbers typed from memory | omega-mv 1.1 "launch floor", 1.3 "every shape" when half were sampled, 2.2 "whole last row", 3.1 "208 shapes" = 26 triples, 4.1 "0.04 to 0.06" range, 4.5 unstated denominator; CUDApp 1.1, 1.2, 2.2, 3.5 | Numbers in README and status text were written after the run, not produced from the log; no gate reads evidence text | `tools/c3_gemm_evidence.sh` produces every count, range, median, repeat and the acceptance word from the chip log; READMEs carry them in `<!-- generated: ... -->` blocks; the always-run gate `tests/gates/run.sh evidence-generated` (OMEGA-EVIDENCE-GENERATED in `.aien/always`) reruns every block and generated file in changed Markdown and fails on any difference; since review 5 it also fails a changed evidence README with no generated block and fails typed claims (percent, number range, number after about/above/over/at least/median/best, count of shapes/cases/checks/runs/windows, MET/PARTIAL, typed causes such as memory bound) outside generated blocks in changed evidence READMEs and in the added lines of other changed Markdown; a method constant or source line passes only with an explicit `<!-- typed-ok: REASON -->` marker, which is the review surface; its negative controls are the real sentences of reviews 1 to 5 |
| Acceptance unit not checked against the wording | omega-mv 3.1, 3.2; CUDApp 1.3, 3.6 | An inherited convention (shape = triple x type x layout) was repeated; nothing encoded the acceptance sentence | The generator states the acceptance literally (a shape is a distinct (M, N, K); at least 200; 1 to 8192; both types; four layouts; 0 wrong) and prints MET or NOT MET from the data |
| Hand-maintained copies drift | omega-mv 2.1 and 3.6 (docs/OMEGA.md "chip run pending"), 4.2 and 4.3 (stale counts in comments), 4.4, 4.6; CUDApp 2.4 | Status rows and comments restated evidence numbers, and nobody regenerates a copy | docs/OMEGA.md C3 rows and source comments no longer restate counts; they point at the generated summary. AGENTS.md points at `.aien/always` instead of copying its list |
| Receipts and provenance | omega-mv 1.2 (ceiling cited to a missing path), 1.4 (excerpt log), 2.3 (control patch did not apply), 2.5 (log without binary sha); CUDApp 1.5, 2.1 (receipts overwritten), 2.5 | Runs were named by label and launched by hand | `tools/run_gpu_gemm_chip.sh` (and CUDApp's `tools/run_gpu_fp8_smallrow_chip.sh`) write a provenance header, name outputs by window id and refuse to overwrite; the generated summary prints the header, so a log without it fails to generate |
| Instrument condition not inspected | omega-mv 1.1 (50 us sleep-poll quantum), 1.7, 2.4, 3.3, 3.4 (load, one sample); CUDApp 2.3, 3.1 (kernel cache cleared per call), 3.2 (A/A false-call rate) | The first timed run was the first look at the instrument | The chip tier busy-polls by default (`--spin-us`), so times are not quantized by the sleep-poll; the summary generates run-to-run repeat lines with their denominator for the cases common to a history run (the 26 hand-picked shapes only); all other cases carry one sample |
| Test-tool input checks | omega-mv 1.5 (`--part`), 2.6 (`--spin-us`); CUDApp 1.6, 2.6, 3.3 | Options were added for one run and not given a range | Both options are range-checked and refuse out-of-range values with exit 2 |

Why the first corrective action (review 4 head 5f946b6a) did not hold, found by review 5: it only compared existing generated blocks
with their generator, so numbers typed outside a block, a README with no block, and docs rows passed (review 5 mutations a, c, d), and
step 2 below was a human instruction with no mechanism. Its own commit then added a typed "memory bound" claim, a typed load claim,
a stale hand copy of the always list in AUDIT_SCOPE.md, and an acceptance line that read "every shape correct" as "0 wrong in what
was checked". The corrective action now fails on those patterns; the search for hand copies of the always list is
`git grep -n "EVIDENCE-IMMUTABLE\|ZERO-DISK-SECRETS\|EVIDENCE-GENERATED"` and covers AUDIT_SCOPE.md.

Pre-review step for every later change in this repository that adds or edits evidence or status text:
1. Run `tests/gates/run.sh evidence-generated` (and `evidence-immutable`) and keep the output.
2. Every number in that text that is computed from a log or table (counts, ranges, medians, fractions, percentages,
   MET or PARTIAL) sits inside a generated block. Prose outside the blocks states method and sources only. The gate
   enforces this by pattern (see the table); a line it flags is moved into a generated block or, if it is a method
   constant or a source, marked `<!-- typed-ok: REASON -->`.
3. Read the acceptance sentence of the issue and check that the generated acceptance line counts the unit it names.

The checker and generator are POSIX sh and awk, outside Omega's structure (measuring tools). Their Omega replacement
is a native `.om` evidence tool once the seeded compiler's text and decimal formatting cover it; that is recorded here,
not claimed. Not done: no failing `.om` probe names the exact missing omc capability yet (review 5 finding 7); until one exists
this note is a limitation, not evidence of a compiler gap.
