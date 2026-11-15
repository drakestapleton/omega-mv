# TURING Yield: a decodable bitstream in Omega (L111)

Drake, 2026-10-19 (ledger L111): "decodable bitstream for TURING Yield: a real lossless coder ...
whose output length equals the ideal code length T within a stated bound, so T becomes bytes on
disk". Under the Omega-first rule the coder is written in Omega, not C.

## What it is

`src/turing/tc_range.om` is coder A of `calibration/docs/CODER_SPEC.md` (range coder, `TCR1`)
written in Omega. It reads the same TPS1 probability stream and TSY1 symbol file as the C
reference `src/turing/tc_range.c` (built into `turing-coder`, `mk/turing_exp001_b.mk`), writes the
same coded file, and decodes it back.

Build (the unit is composed after the FIPS 180-4 unit `seed/ng/sha256.om`, with an `om2` first
line so its unsized text views compile; compiler = the repository's own `seed/out/omc`):

    { printf 'om2\n'; cat seed/ng/sha256.om src/turing/tc_range.om; } | seed/out/omc > tcr-om

CLI, same shape as `turing-coder` (range only):

    tcr-om encode range IN.tps IN.tsy OUT.tcr
    tcr-om decode range IN.tps IN.tcr OUT.tsy
    tcr-om verify range IN.tps IN.tsy IN.tcr
    tcr-om selftest

Exit 0 accepted, 2 refused (one stderr line with the CODER_SPEC section 10 code and name), 1 usage,
3 ALARM (a proved property failed on this run; never expected, loud if it happens). Encode,
decode and verify print `count`, `ideal_ub`, `coded_bytes`, `coded_bits`, `payload_bytes`,
`shifts`, `bound_ub`, `slack_ub`, `overhead_ub` and `bound=PASS`.

Every file is streamed through fixed buffers: memory does not grow with the number of symbols
(640 KB peak on a 2,172,776-symbol, 91 MB stream where the C tool used 154 MB), so no input size is
capped. Each input is read twice: a validation pass (trailer digest with SHA-256 in Omega, header,
every record or symbol) and the coding pass. A refused encode or decode removes its partial output.

## The bound

For a coded file of n symbols (header and flush counted, CODER_SPEC section 4 accounting):

    1,000,000 x coded_bits  <=  ideal_ub + 5647 x n + 480,000,000

In bits: coded length <= T_ideal + 480 + 0.005647 n, where T_ideal is the section 8 ideal length
of exactly the coded symbols. The 480 bits are the 448-bit header plus 32 bits of range-coder
flush; 0.005647 bits per symbol is the worst case of the `range >> 16` truncation. The program
checks the bound on every run (ALARM exit 3 if it ever fails).

Proof chain:

1. **Per step and telescoped (Lean 4, `docs/turing/proofs/TcrBound.lean`).** Over an explicit
   model of section 5 (`step`, `renorm`, `run`), for every list of valid symbols
   (q >= 1, cum + q <= 65536, cum + q = 65536 for the last symbol of the row):
   `encode_bound`: (2^32 - 1) * prod q_t * 16711681^n * 256^S < 2^32 * (2^40)^n,
   where S is the number of renormalisation shifts. Lemmas: `step_lb` (each step keeps at least
   (1 - 65535/2^24) of p * R), `step_ge` (R' >= 256 and R' <= R, so at most two shifts and no
   overflow), `renorm_spec`, `run_bound`. Negative controls: `bad_step_violates` (r = R >> 17
   breaks the step inequality) and `tight_without_loss` (without the loss factor the inequality
   fails at R = 2^24 + 65535: the per-symbol cost is real). Checked with the pinned toolchain
   `leanprover/lean4:v4.35.0` (`lean docs/turing/proofs/TcrBound.lean`, no imports, exit 0);
   axioms: `step_lb` [propext, Quot.sound], `run_bound` and `encode_bound` [propext,
   Classical.choice, Quot.sound], the three controls and `constants` none. No `sorry`.
2. **Logarithm (Wolfram, receipt W1).** log2 of `encode_bound`:
   8S < sum_t (16 - log2 q_t) + n (24 - log2 16711681) + (32 - log2 (2^32 - 1)).
   sum_t (16 - log2 q_t) is the exact ideal length I; Wolfram: `FullSimplify[24 - Log2[16711681]
   == -Log2[1 - 65535/2^24]]` = True, so the middle term is n * eps with
   eps = -log2(1 - 65535/2^24), 10^6 eps = 5646.4768125983...; 32 - log2(2^32 - 1) = 3.359e-10.
3. **Length identity (checked on every run, not proved).** payload_bytes = S + 4: each
   `shift_low` call is one byte position, the flush makes 5 calls and the last cache byte is not
   emitted. `tc_range.om` compares the two counts on every encode, decode, verify and selftest case
   and raises ALARM 1 if they differ. So coded_bits = 8 (S + 4) + 448 = 8S + 480.
4. **Integer ideal (Wolfram, receipt W2).** The section 8 ub rule is within 0.501 ub of the exact
   value per symbol; Wolfram recomputed the rule for every q = 1..65535 and found
   max(exact - ub) = 0.49984 ub, min = -0.50019 ub, sum ub = 94,539,136,349 and
   sum q * ub mod 2^64 = 1,549,081,999,916,376. `tcr-om selftest` recomputes both sums in Omega and
   must match (ALARM 5 otherwise), so the Omega ub equals the rule for every q.
5. Combining 2 to 4: 10^6 coded_bits < ideal_ub + n (10^6 eps + 0.501) + 480 x 10^6 + 3.4e-4, and
   ceil(10^6 eps + 0.501) = 5647 (Wolfram W1) leaves 0.022 ub per symbol, more than the 3.4e-4 ub
   constant for any n >= 1; n = 0 gives equality (480 bits, payload of 4 bytes).

Model-to-system link: the Lean `step`/`renorm` are transcribed from CODER_SPEC section 5 and
`encs` in `tc_range.om`; `tc_range.om` is byte-identical to the C reference on every gate unit and
on two whole dev files (below), and the renormalisation loops in `encs` and `decs` carry `bound 2`:
a third shift (a range below 256, which `step_ge` rules out) would trap 4 (exit 104), so the "at
most two shifts" fact is also enforced at run time.
The theorem is about the model; the byte identity and the run-time checks are what tie it to the
program.

How tight it is: the n = 1 selftest case of a symbol with q = 1 codes 16 bits of ideal into 496
bits, slack 5647 ub, i.e. within eps of the bound. On real data the slack is far larger (the
truncation loses about 5e-4 bits per symbol, CODER_SPEC section 9).

## Results (EXERCISED on the Spark, omc `26540e6d...`, omega-mv base e4271abd)

`make test-turing-range-om` (part of the `turing-yield` gate step):

- selftest: 484 synthetic cases, 1,284,560 symbols, K = 2..16, four row shapes, sampled and
  worst-information symbols, n = 0 to 200,000: round trip exact, identity and bound hold, one
  flipped payload byte detected in every case (484 of 484); ub rule exhaustive match.
- 14 real units (2 committed CTR1 traces x the TY-2 candidate, uniform:9 and the five EXP-001
  candidates B0..B3, M): Omega encode byte-identical to C, C verifies every Omega file, Omega
  verifies every C file, Omega decode byte-identical to the TSY1, ideal_ub equal to the C value.
  Example (trace crumbs 05-07, TY-2 candidate): n = 1418, ideal 1456.957896 bits, coded 1936 bits
  (242 bytes), bound 1944.965342 bits.
- Refusals with the right code: flipped byte (SYMBOL), truncated (TRUNC), trailing byte (TRAIL),
  other TPS1 (BINDING), altered magic (HEADER), corrupted TPS1 (DIGEST), TSY1 of another trace
  (COUNT), usage.
- Mutants caught: `range >> 15` (output no longer byte-identical), bound constants lowered (ALARM 2),
  ub rounding removed (ALARM 5).

Whole dev file (seed 1 only; seeds 8 to 10 untouched), not part of the gate because the data is not
in the repository: 2,172,776 symbols, TY-2 candidate: ideal 1,752,630.382351 bits, coded 1,754,208
bits (219,276 bytes), byte-identical to C, round trip exact, slack 11,172 bits; uniform:9 also
byte-identical. Single core, nice 10, shared machine: Omega encode 2.90 s, verify 2.89 s, decode
3.98 s; C encode 0.56 s.

## Not claimed

- Coder B (rANS, `TCA1`) is not ported; `tcr-om` refuses `rans` with usage.
- `verify` checks the TSY1 before the coded file; the C tool checks the coded file first. Refusal
  codes agree when an input has one fault; with several faults the first code reported can differ.
- The length identity (step 3) is checked on every run, not proved.
- The Lean check used `lean` from the pinned toolchain on the single file (it imports nothing);
  it is not wired into a lake project inside this repository.
- C remains the reference implementation of the calibration profile; nothing here changes
  CODER_SPEC or any frozen receipt.

## Wolfram receipts (Wolfram Language evaluator, 2026-11-15)

W1:

    eps = -Log2[1 - 65535/2^24];
    {N[eps*10^6, 20], N[eps*10^6 + 501/1000, 20], Ceiling[eps*10^6 + 501/1000], N[32 - Log2[2^32 - 1], 20]}
    -> {5646.4768125983298532..., 5646.9778125983298532..., 5647, 3.3590361500552744...*10^-10}
    FullSimplify[24 - Log2[16711681] == -Log2[1 - 65535/2^24]]  -> True

W2 (the CODER_SPEC section 8 rule, transcribed, for every q):

    ub[q_] := Module[{ip = BitLength[q] - 1, m, f = 0, l, x}, m = BitShiftLeft[q, 62 - ip];
      Do[m = Floor[m*m/2^62]; If[m >= 2^63, f = BitOr[f, BitShiftLeft[1, 32 - i]]; m = BitShiftRight[m, 1]], {i, 1, 32}];
      l = BitOr[BitShiftLeft[ip, 32], f]; x = BitShiftLeft[16, 32] - l; BitShiftRight[x*1000000 + 2^31, 32]];
    t = Table[ub[q], {q, 1, 65535}]; d = Table[N[-Log2[q/65536]*10^6, 40] - t[[q]], {q, 1, 65535}];
    {ub[1], ub[32768], ub[43481], ub[46819], Max[d], Min[d], Total[t], Mod[Sum[q*t[[q]], {q, 1, 65535}], 2^64]}
    -> {16000000, 1000000, 591903, 485194, 0.49983840009545..., -0.50019182915248..., 94539136349, 1549081999916376}

The four test values agree with CODER_SPEC section 8.
