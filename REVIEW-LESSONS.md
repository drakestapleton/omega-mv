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

## DRA-485 evidence-text corrective action, 2026-11-17 (revised 2026-11-18 after reviews 5, 6 and 7)

The DRA-485 C3 GEMM change in this repository had reviews 1 to 7 and 9 (all FIX: d83bbc04, e823b59f, 0be0ba36, 0e50400f,
5f946b6a, 3b87b07e, 76046707, 3686d5de; review 8 was stopped before a verdict; verdict files `~/handoffs/dra485-finish-20261117.VERDICT*.omega-mv.*.md` on the Spark).
The CUDApp half took three (FIX 5dc27c28, FIX 18ac3327, MERGE a283a896). No round found a wrong kernel result; almost
every finding was about what the evidence text said, or about the corrective action meant to stop that.

| Kind | Findings (round.number, both repositories) | Why the author and the checks missed it | Corrective action |
| --- | --- | --- | --- |
| Derived numbers and claims typed by hand | omega-mv 1.1 "launch floor", 1.3 "every shape" when half were sampled, 2.2 "whole last row", 3.1 "208 shapes" = 26 triples, 4.1 "0.04 to 0.06", 5.1 "memory bound", 5.4 load1, 7.6 sampling stride; CUDApp 1.1, 1.2, 2.2, 3.5 | Text was written after the run, not produced from the log; no gate read evidence text | `tools/c3_gemm_evidence.sh` produces every count, range, median, repeat and the acceptance line from the chip log into `<!-- generated: ... -->` blocks. The always-run gate `tests/gates/run.sh evidence-generated` (rules R1 to R3 in the header of `tools/evidence_generated_check.sh`) checks, in evidence directories that opt in by holding a generated marker, that generated text equals its generator and that a generator takes only files of the directory as input; and in any touched evidence directory with a SHA256SUMS, that the manifest verifies (and, if the directory opted in, lists every data file). Hand-written prose is judged by the exact-head review, not by the gate |
| Corrective action fitted to its own controls, then over-scoped | 5.2, 6.2, 6.3, 6.4, 7.1, 7.3, 7.4, 7.5, 9.1, 9.2 | Rounds 5 to 7 tried to make a gate judge hand-written prose (word lists, then per-line hash markers) and tested it only on the author's sentences; review 9 showed the always-run version would fail other lanes' ordinary evidence commits and that the line markers bound nothing the exact-head review does not | The gate judges no prose and runs only where a directory opts in or carries a manifest; its self-test runs the real gate end to end in a scratch git repository, including a control that an unrelated lane's evidence directory passes untouched |
| Acceptance unit not checked against the wording | omega-mv 3.1, 3.2, 5.5; CUDApp 1.3, 3.6 | An inherited convention (shape = triple x type x layout) was repeated; nothing encoded the acceptance sentence | The generator states the acceptance literally and prints MET, PARTIAL (when any shape was compared on a sample only) or NOT MET from the data |
| Hand-maintained copies drift | omega-mv 2.1, 3.6, 4.2 to 4.6, 5.3, 7.8, 7.9; CUDApp 2.4 | Status rows, comments and process text restated values that change elsewhere | `docs/OMEGA.md` C3 rows point at the generated acceptance line and type no status word for the GEMM run; AGENTS.md and AUDIT_SCOPE.md point at `.aien/always` instead of copying it |
| Receipts and provenance | omega-mv 1.2, 1.4, 2.3, 2.5, 6.1 (SHA256SUMS broken by an edit); CUDApp 1.5, 2.1, 2.5 | Runs were named by label and launched by hand; nothing checked the manifest | `tools/run_gpu_gemm_chip.sh` writes a provenance header and refuses to overwrite; the gate runs `sha256sum -c` in every touched evidence directory and fails a data file that is not in SHA256SUMS |
| The checker can be loosened by the change it judges | 7.11 | The gate ran only the change's own copy | When the base ref has the checker and the change edits it, `tests/gates/run.sh` also runs the base copy on the change (tested: a change that replaces the checker with `exit 0` and adds a typed claim fails) |
| Instrument condition not inspected | omega-mv 1.1, 1.7, 2.4, 3.3, 3.4; CUDApp 2.3, 3.1, 3.2 | The first timed run was the first look at the instrument | The chip tier busy-polls by default (`--spin-us`); repeat lines are generated for the cases common to a history run (the 26 hand-picked shapes only); all other cases carry one sample |
| Test-tool input checks | omega-mv 1.5, 2.6; CUDApp 1.6, 2.6, 3.3 | Options were added for one run and not given a range | Both options are range-checked and refuse out-of-range values with exit 2 |

Why each corrective action did not hold. Action 1 (5f946b6a) compared only existing generated blocks. Actions 2 and 3 (3b87b07e,
76046707) tried to recognise false prose by its words and were tested only on the author's sentences. Action 4 (3686d5de) bound every
hand line to a marker the author made himself, which adds nothing to the exact-head review, and as an always-run gate it would have
failed other lanes. Cause of the kind: a corrective action sized to the whole repository's prose instead of to the defect. The
action at this head is the small one: numbers are generated, generated text and manifests are checked, prose stays with review.

Pre-review step for every later change in this repository that adds or edits evidence or `docs/OMEGA.md`:
1. Run `tests/gates/run.sh evidence-generated` (and `evidence-immutable`) and keep the output.
2. Put every number or status computed from a log or table in a generated block; check each remaining hand-written
   sentence against its source before review.
3. Read the acceptance sentence of the issue and check that the generated acceptance line counts the unit it names.

Omega: the checker and the generator are bash and POSIX sh with awk. Earlier text here said their Omega replacement waits for
decimal formatting in the seeded compiler; that was not true. A probe compiled with the pinned omc (sha256 2c824805...) formats
0.0552 as `0.0552` with integer arithmetic and `write` (binary sha256 7a149476..., 2026-11-18). Porting both tools to `.om` is
open work (ledger), not a missing compiler capability; the shell tools stay as transitional code until an Omega version passes
the same self-test.
