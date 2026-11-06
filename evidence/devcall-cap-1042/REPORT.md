# devcall parameter cap, issue #1042

IMPLEMENTED and EXERCISED on Linux AArch64. Not merged or deployed. This compiler/trust-surface change is draft-only; Drake must approve merging. No GPU or protected serving port was accessed.

Base: omega-mv `9a9263208650` (the requested base). Initial fetch observed origin/main `5287336a50b4b75a357bfc330f599cc604209e40`; this lane deliberately retains the requested base.
Branch: `fix/devcall-param-cap-1042`.

## Contract and allocation

Both AArch64 `hdevcall` and x86linux `xhdev` accept parameter lengths through 1048576 bytes inclusive, rejecting larger lengths with trap 3 / exit 103. `harray` still checks both caller slices; exact header length, nonoverlap, writable arrays and zero caller-pointer bytes remain enforced. `devctl` is unchanged.

There is no parameter bounce buffer to enlarge: generated code binds the checked caller span directly. The private header remains 32 bytes on the stack on both backends. Large fixtures use the existing image-backed global pool, so there is no new heap dependency, mmap resource, or large per-call stack allocation.

Authority: [NVIDIA open-gpu-kernel-modules 20e4e6e1, param_copy.h](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/20e4e6e1/src/nvidia/inc/kernel/rmapi/param_copy.h#L63), `RMAPI_PARAM_COPY_MAX_PARAMS_SIZE (1*1024*1024)`, the default embedded-pointer copy-in cap. WolframLanguageEvaluator: `{2^20,2^20+1}` -> `{1048576,1048577}` bytes.

## Commands and results

All builds/checks used `taskset -c 10-14 nice -n 10`.

- PASS, rc 0: `make -j3 PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2`. Built the existing comparison oracles; no implementation dependency added.
- FAIL, rc 1: first `sh seed/host/check.sh`, preserved as `host-first-attempt.log`. The new mutant manifest omitted the conductor's `file:` prefix, producing INVALID cases, not mutant kills. Corrected the manifest and exact verdict assertions.
- PASS, rc 0: corrected `sh seed/host/check.sh`, `host.log`, final line `PASS native-host qualification; seeded build, C tools are comparison oracles only`.
- PASS: birth stage1 = stage2 = stage3; all sha256 `390629fd22590aaefca852045f8b0ace86c62cefb3b1bc203ce400773c8abc2f`. The same run executes the IR reference comparison, all host fixtures and existing negative controls.
- PASS: `seed/host/tests/devcall.om`, final line `PASS native device parameter binding`. The fixture requires memfd ENOTTY at 16384, 55888 and 1048576 bytes (RM_CONTROL and RM_ALLOC at the cap); above-cap 1048577 and out-of-array spans require exit 103 in forked children. No NVIDIA descriptor is opened.
- PASS: `mutants.log`, conductor rc 1 is the required rejection result: off-by-one compiler `b06bf78f67d2939908c48bba725e1c5597c83b6e9f815d41a5d64d3b7344021d` fails with exit 103 versus expected 0; removed-check compiler `36c36b9a724fc8599bd0cd962550627c1a015c1451fa3139b57d49080574b868` fails with exit 80 versus expected 0. Both substitutions matched exactly once. Final line `OM2GATE FAIL cases=2 pass=0 fail=2 invalid=0 not_run=0`.
- PASS, rc 0: `crumb compile .` and `crumb verify .`; final line `crumb verify: OK: 188 crumbs current`.

The host suite reports NOT_RUN for the non-vendored optional Wycheproof AES-GCM-SIV corpus; the mandatory suite still exits 0. Native x86 execution and GPU qualification are NOT_RUN. x86linux cap lowering is implemented, not independently exercised here.

## Identities and downstream guides

- `seed/out/omc`: `390629fd22590aaefca852045f8b0ace86c62cefb3b1bc203ce400773c8abc2f`
- `seed/omc/omc.om`: `7e0e0c221ed32c52ebf7629b47e7cc1c80026be6349423ca3765d49ff026856b`
- `seed/host/tests/devcall.om`: `2079a5962977ab18b89fb2f7790f0bc535c02e668c42320a5b4eb5de98613cbd`

Compiler path and digest were sent to the Smi agent. No downstream compiler pin or service was changed.

[omega-harness issue #187](https://github.com/aien-dev/omega-harness/issues/187) tracks the pending guide/metadata update: omega-encoding section 0 pins and host/device limits; omega-harness compiler pin guidance; omega MCP keyword 171 `n: ulong (at most 16383)` and its source citations. The mounted MCP remains intentionally pinned to its old compiler. This lane updates the repository keyword entry in OMEGESE, MAPPING contract and host README. The guide issue must not be treated as deployment of the candidate compiler.
