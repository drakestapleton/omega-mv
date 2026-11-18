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

## Aienux fold review corrective action, 2026-11-18

Three reviews blocked the fold of aienux into `kernel/`: aienux `1f12818d`
(27 findings), omega-mv `c9e503afd` (19) and omega-mv `5cd0af98f` (about 40).
The root-cause analysis groups the findings into six kinds. The table gives each
kind, why it recurred, and the corrective action with the tool that enforces it.
A citation `[ctl:GATE-ID/name]` names a control the gate runs and that must
print `CONTROL GATE-ID/name FAILED_AS_REQUIRED`.

| Kind | Finding kind | Why it recurred | Corrective action |
| --- | --- | --- | --- |
| K1 | A claim broader than its check ("every claimed mechanism has a failing case", "any ALARM fails", "cannot be weakened"). | Authors wrote the claim and then tested the reviewer's examples, so no universal sentence was tied to a control. A round-2 author adversarial pass did not hold, because the author picks the variants. | CA1: `tools/gate_claims_lint.sh` (OMEGA-GATE-CLAIMS, always-run). A sentence about gates or checks with every/any/all/never/cannot/only must cite `[ctl:GATE-ID/name]`, and the name must be listed in `tests/gates/controls/GATE-ID.controls` [ctl:OMEGA-GATE-CLAIMS/uncited-claim] [ctl:OMEGA-GATE-CLAIMS/unlisted-control]. `tests/gates/run.sh` fails a step whose run lacks the CONTROL line of a listed name. Claims present at `5cd0af98f` are listed in `tools/gate-claims-baseline.txt`; an edited one counts as new [ctl:OMEGA-GATE-CLAIMS/baseline-edited]. |
| K2 | A gate trusts an anchor that the head can rewrite (the IMPORT constant, regenerated pins, a count pin, the wiring parser). | Each fix pinned values in files that the same commit can edit, which moved the weakness instead of closing it. | CA2: `tools/gate_anchor.sh` and `tools/gate-anchors.txt` (OMEGA-GATE-ANCHOR, always-run). A changed gate-integrity file makes the head BLOCKED_OPERATOR unless the change is acknowledged; the landing receipt lists each changed anchor. Kernel steps need a base that holds `kernel/`, else NOT_RUN [ctl:OMEGA-KERNEL-GATE-WIRING/base-without-kernel]. |
| K3 | NOT_RUN reported as PASS or as the wrong exit: verify-all and store-native exited 0 on NOT_RUN, and missing tools gave 127, 2 or 1. | Each arm decided its own exit, and fixes were made one arm at a time. | CA3: `kernel_step` in `tests/gates/run.sh`, the one wrapper for the kernel steps. Exit 127 or 3, or exit 0 with a NOT_RUN or SKIP verdict line, becomes exit 3 [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-127-pass] [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-verdict-ignored] [ctl:OMEGA-KERNEL-GATE-WIRING/wrapper-skip-ignored]. Each step starts with `need TOOL...`, and `omega_gate_wiring.sh --self-test` runs the step once per listed tool with that tool removed from PATH and requires exit 3 [ctl:OMEGA-KERNEL-GATE-WIRING/no-cargo-crypto-boundary]. |
| K4 | Hand parsers narrower than the language: rc patterns, the wiring awk on indentation, raw Lean names. | Text matching was chosen for speed. | CA4: parse with the real tool. `kernel/scripts/omega_gate_wiring.sh` takes case arms from bash (`bash -n`, `declare -f`, a DEBUG-trap dry run of each arm) and runs `tests/gates/run.sh` against stub runners [ctl:OMEGA-KERNEL-GATE-WIRING/root-arm-shadow-indented] [ctl:OMEGA-KERNEL-GATE-WIRING/root-arm-shadow-comment] [ctl:OMEGA-KERNEL-GATE-WIRING/kernel-step-underscore]. It reads manifests with the judge's grammar (aien-test `manifest.rs`) [ctl:OMEGA-KERNEL-GATE-WIRING/exec-duplicate] [ctl:OMEGA-KERNEL-GATE-WIRING/exec-decoy-notes]. A text parser that remains needs a control for each syntax variant it ignores. |
| K5 | Fixed caps and silent waits: NVMe budgets, the RPC cap, swtpm ports and listen wait, the test_pipe hang. | They were written to stop hangs. | CA5: Drake's no-caps rule. `kernel/scripts/swtpm_start.sh` bounds ports by the port range and the wait by the step timeout, with ALARM lines past 20 pairs and 5 s [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-busy-25-pairs] [ctl:OMEGA-KERNEL-VERIFY-ALL/swtpm-slow-7s]. A lint for new numeric limits without an ALARM in changed lines is not built yet. |
| K6 | The author verifies the author's own fix. | Findings were fixed first and review 4 was requested next. | CA6: before any further review, a separate red-team lane (fresh agent, adversarial, no edits) attacks the head with the earlier verdicts; review 4 is requested only once it finds nothing blocking. |

Review request checklist for kernel work, in addition to the gates that own the
change: run `tests/gates/run.sh gate-claims` and `tests/gates/run.sh gate-anchor`,
run `tests/gates/run.sh kernel-gate-wiring`, and run every changed kernel step with
`AIEN_BASE_REF` set to the branch it lands on. Give each control's command, exit
status and log sha256 in the handoff.
