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

## Decoder switch review corrective action, 2026-11-23

Three reviews rejected the dsv41-decode Arboris prefetch switch before its
fourth: heads 14b2275448a63e2af1c5ddc182c0276e47d51de5,
bfabe5f4490c73c29293906802b9420cad398f9d and
3ee10c19941953ec6157ec09657da11680d915e1.

| Round | Finding kind | Why author or checks missed it | Corrective action |
| --- | --- | --- | --- |
| 1, 2, 3 | Controls tested helpers, not the composed program. Moving or dropping the switch write in `decode-cli.om` passed every control. | Each control was written for the function just changed. Nothing ran the real binary's entry point without a GPU. | `pfcheck` runs the real decoder's parse-and-start path on the host. `check-decoder-prefetch.sh` drives it, and mutants F and G must fail it. |
| 2, 3 | Assertions that could not fail: a drain with nothing in flight, a slot table that dispatch never writes, an empty binary that runs as exit 0. | No assertion was paired with a wrong implementation that only it rejects. | `check-prefetch-mutants.sh` pairs every off-arm exit and every control with a named mutant and expected result. Assertions with no killing mutant were removed. No success code is 0, and empty builds stop the driver. |
| 3 | Negative controls lived outside the repository and their log lacked the compiler digest. | The mutant script was kept as scratch. | The mutant driver is committed and self-judging. It prints head, compiler digest and binary digests, and passes only on `PREFETCH-MUTANTS PASS`. |
| 1, 2, 3 | Documentation claimed more than the code or evidence: layer0 refusals, "the arm that ran", exit codes, the slot-fill limit. | The README was written from intent before the behaviour was checked. | The README states only what a control or a recorded run shows, and says which. |
| 1, 2 | Environment limits: the read buffer refused default runs with large entries; the page size was assumed to be 4 KiB. | Malformed values were tested, but not the read-overflow path or kernel limits. | The buffer is 2 MiB (MAX_ARG_STRLEN on 64 KiB pages). The control includes a maximum-size entry and repeated names delivered through `execenv`. |

Before any review of a change to `prefetch-switch.om`, `decode-cli.om`,
`check-*prefetch*` or the prefetch path in `forward.om`, run
`check-prefetch-mutants.sh` at the exact head and attach its log. A new
assertion in those controls needs a mutant in the driver that only it
rejects. A behaviour that only a GPU run can show is labelled as such and
backed by that run's stats line, not by the host controls.
