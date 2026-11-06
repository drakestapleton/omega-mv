# Scalar fma and exact-literal candidate

Status: IMPLEMENTED and EXERCISED on the AArch64 Linux CPU. The required seed and native-host gates PASS. Not MERGED, not DEPLOYED, and not GPU/device qualification.

## Source and ownership

- Base: omega-mv origin/main `5287336a50b4b75a357bfc330f599cc604209e40`.
- Branch: `feat/seeded-fma-exact-literals`.
- Compiler source: `seed/omc/omc.om`, SHA-256 `0a0f4bbc361e555de223d93e774ed5c8d96da401ab574983897ecc82539e0549`.
- Seed-born executable SHA-256: `d89bdc08ca21ea9726f1117adc791f683287d3698ea112a9db5519df2e79aeec`.
- Retained local candidate: `build/seed/fma/omc` in the private OmcFloat worktree. Reproduce it with the seed command below; generated binaries are not a production-pin update.
- Exact decimal conversion is reused from draft #1027 core commit `681d6f487ac3c237e0b8d73c287e0a8f232b1434` (#1024, #1026), not independently reimplemented. This draft overlaps that source fix and must be integrated after, or together with, #1027.
- Parent BridgeViews explicitly retained the bridge e5b32567 profile and gave integrated pin-refresh priority to BridgeHost. Active generated units and compiler pins are intentionally unchanged. A separately authorized batch reseed, generated-unit regeneration and full pin refresh remain a merge prerequisite; do not treat this draft as installed.

## Contract

`fma a b c` is keyword 227. Three same-type f32 or f64 values are required. AArch64 emits scalar FMADD (not FMUL/FADD), following Arm FPMulAdd/FPCR for rounding, subnormals, signed zeros, infinities and NaNs. Integer/mixed operands refuse with error 7, unresolved decimal operands with error 11. x86linux and x86efi refuse with error 9 because the existing baseline is SSE2; IR refuses float words with error 3. Ordinary multiply/add semantics are unchanged.

Encoding reference: <https://www.scs.stanford.edu/~zyedidia/arm64/fmadd_float.html>. FMADD uses Rm at 20..16, Ra at 14..10, Rn at 9..5 and Rd at 4..0, with f32/f64 base words 0x1f000000/0x1f400000. The compiler never writes FPCR.

## Exact oracle

`oracle.wl` is the full query submitted to the mounted WolframLanguageEvaluator; `oracle-result.json` is its actual response. It reconstructs decimal text as exact rational numbers, rounds with integer nearest-even, and checks every inherited `lit_round.want` row. Result: `{512, 0, {}}` (rows, mismatches, mismatch list).

The same query gives the fused adversaries:

- `(1+2^-23)*(1-2^-23)-1 -> -2^-46`, binary32 `a8800000`.
- `(1+2^-52)*(1-2^-52)-1 -> -2^-104`, binary64 `b970000000000000`.
- Rounding each product first gives zero in both cases.
- `nearestBits[6816702656/10^33,52,11] -> 4260540855293878576` (`3b207b55a6d4a130` in the verified table).
- `nearestBits[24703282292062328/10^340,52,11] -> 1`.

Wolfram also checked fixture overflow-cancellation, subnormal-tie and mask constants. No Python/C floating-point oracle was executed for these claims. The inherited #1027 Python verifier remains unmodified and is not part of this qualification run.

## Commands actually run

All builds/gates ran serialized, restricted to cores 10–14 at nice 10. Full argv, status, start timestamp and final lines are in `commands-v3.json`; complete logs are adjacent.

1. `taskset -c 10-14 nice -n 10 sh seed/omega-from-seed.sh` — **rc 0**, `fixpoint-v2.log`; final line `RC=0`. All three stages are byte-identical, SHA-256 `d89bdc08ca21ea9726f1117adc791f683287d3698ea112a9db5519df2e79aeec`.
2. `taskset -c 10-14 nice -n 10 make -j3 build/omegese/omegese build/omega_emit/omega_emit build/checker2/checker2` — **rc 0**, `oracles.log`. Existing C tools are comparison oracles only.
3. `taskset -c 10-14 nice -n 10 sh seed/host/check.sh` — **rc 0**, `host-v2.log`; final line `PASS native-host qualification; seeded build, C tools are comparison oracles only`.

The host run includes:

- `gate8`: **PASS 48 cases**, including `fma exit 0`, all eleven fma refusals, and **512 literal patterns**.
- `gate-fma`: fused control **exit 0**; absent mutation-site refusal **93**; FMSUB and unfused mutants each detected by fixture **exit 1**; discarded-remainder and ties-down mutants detected by unequal literal patterns. Final line: `PASS gate-fma fused control, fail-closed mutator and 4 wrong-word/rounding mutants`.
- `gate17`: **300 programs byte-identical** to the pinned historical compiler.
- `gate18`: **163 literal keyword packs**, computed entries and scoped efi entry match.
- Native-host, contract, ingress, dit/scrub, hex and cryptographic regression/mutant gates also completed.

The host script explicitly reports `NOT_RUN wycheproof aes_gcm_siv_test.json: not vendored`; this is not presented as a passed external corpus.

## Retained failed attempts

`fixpoint.log` records the initial bootstrap refusal (rc 12, line 4536): the single large bitfield expression exceeded om4's live-value budget. Splitting field accumulation fixed it without another helper (the bootstrap function budget is retained).

`host.log` records the first host attempt (rc 1): the qualification-only mutator reused a long `argread` result as an unsigned source length. Giving the argument read its own long variable fixed error 7. These failed records are retained; the later successful evidence is not substituted into them.

## Remaining authorization boundary

No GPU, live-service, driver, boot, trust or gate-policy changes were made. No merge/deployment authority is claimed. Active pin refresh and skill adoption are separate integration work, not implied by passing this candidate's gates.
