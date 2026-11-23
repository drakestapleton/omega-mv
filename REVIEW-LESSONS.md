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

## C to OM migration

Corrective action for the waves 29-36 change, which took three reviews (findings sorted into
kinds K1-K5 in its root-cause record). Every change that deletes C, or switches a consumer from
C to an OM replacement, does these before its first review:

1. Run `make check-retirement` (tools/migration/parity_check.sh over docs/migration/PARITY.tsv).
   It needs a row for every C file the change deletes and every C file whose same-stem .om it
   adds or edits outside tests/. A row names the make target holding the C-vs-OM differential
   and lists every function the C file defines with external linkage, as covered by that
   target or excluded with a reason; `-` as target means there is no differential, and every
   function then carries the reason. Its bite controls must fail. A consumer switch waits until
   the replacement's row has a real differential target (K1: an OM module went live with no
   test against the C still in the tree).
2. A check whose input was the C (nm over objects, grep over .c, objdump) must also scan the OM
   replacement, or be listed as a `check` row with a reason; check-retirement fails otherwise
   (K2: checks on retired C kept passing while covering nothing).
3. Derive counts and statuses from the run's own output, never type them from memory. A status
   such as NOT_APPLICABLE needs its probe's exit status checked; a probe that fails is an
   error, not evidence (K3).
4. Parity references are committed goldens generated from a commit on main, with the generator
   recorded (commit, command, blob and sha256) and the generator removed from the tree in the
   next commit, as tests/language/parity_golden and tests/visor/effect_golden do. Never pin a
   branch-only commit and never leave a new C dumper in the tree (K4).
5. After deleting C, grep the whole tree for its path and stem (`grep -rn '<stem>\.[ch]'
   Makefile mk/ src/ tests/ tools/ docs/ spec/`) and fix or annotate every hit (K5).
6. "Covered" in PARITY.tsv means reached on the C reference by the differential's corpus and
   compared. Measure it (gcov on the C reference build) instead of reasoning from the call
   graph; record what was measured in the ledger's header.
