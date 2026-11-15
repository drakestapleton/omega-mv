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
`shifts`, `bound_ub`, `slack_ub`, `lower_ub`, `overhead_ub`, `bound=PASS` and `lower=PASS`.

Refusals follow `turing-coder`'s order: encode checks the TPS1, the TSY1, then the pair; decode
the TPS1, the coded file, then the decode; verify the TPS1, the coded file and the whole decode,
then the TSY1 and the pair, then byte identity (compared through the TSY1 digests of domain,
header and symbols, which stands for comparing the bytes). On every single-fault input of the
gate both tools report the same code.

Every file is streamed through fixed buffers: memory does not grow with the number of symbols
(640 KB peak on a 2,172,776-symbol, 91 MB stream where the C tool used 154 MB). Each input is read
twice: a validation pass (trailer digest with SHA-256 in Omega, header, every record or symbol)
and the coding pass, which re-checks every record and symbol and hashes the file again; a file
that changed between the passes is refused (DIGEST). An output path that names an input (same
device and inode) is refused before anything is opened for writing, and a refusal after the
output was created removes it.

Two ceilings come from the 64-bit micro-bit sums, not from a buffer (Wolfram W3). `tpsload`
refuses `n > 1152514738906` with ARG before the body-size check, because `16005647*n + 480000000`
no longer fits in `2^64-1`. `report` refuses a coded file of more than `2305843009213` bytes with
ARG, because `coded_bytes * 8 * 1000000` no longer fits. The host gate builds a 160-byte TPS1
(header and a real trailer, no record body) at `n = cap+1` and requires ARG; the same shape with
`n = 1` is FORMAT, which is the size check, so that refusal is not mistaken for the cap. A sum
that would wrap anyway raises ALARM 7. `tcr-om selftest overflow` forms the upper sum at
`n = cap+1` with the maximum per-symbol ideal and must take that alarm. `selftest` itself forms
the same sum at `n = cap` and the coded-byte product at the byte cap, and must not alarm.

## The bounds

For a coded file of n symbols (header and flush counted, CODER_SPEC section 4 accounting), with
T the section 8 ideal length of exactly the coded symbols:

    upper:  coded_bits <= T + 480 + 0.005647 n
    lower:  coded_bits >= T + 472 - G,   G = sum, over the symbols coded as the last symbol of
                                             their row (s = K - 1), of log2(1 + 256/q)

In integers (micro-bits, as checked by the program on every run):

    1,000,000 x coded_bits <= ideal_ub + 5647 n + 480,000,000
    1,000,000 x coded_bits >= ideal_ub + 472,000,000 - n - gain_ub

where gain_ub sums, over the last-symbol occurrences, ub(q) - ub(q + 256) + 2 for q <= 65280 and
5649 for larger q (an upper bound of 10^6 log2(1 + 256/q); receipts W2 and W3).

Where the terms come from: 480 bits are the 448-bit header plus 32 bits of flush; 0.005647 bits
per symbol is the worst case of the `range >> 16` truncation. On the lower side, the last symbol
of a row takes the slack `range - r * cum`, which can give it up to 256/q more than its share, so
that symbol can code below its ideal (by about 8 bits at q = 1). "T bytes on disk" therefore holds
up to these two stated terms, and the lower term shows in the data: on the gate's real units the
coded length sits 1.2 to 17.8 bits above the lower bound, and a selftest case that codes only last
symbols comes out 70,682 bits below its ideal length, still inside the lower bound.

Relation to the frozen calibration envelope (CODER_SPEC section 9, S4): S4 is an empirical
two-sided band, |overhead - 448| <= 64 + 0.001 N bits, fitted to observed data. The bounds here are
worst-case and proved: the upper slope 0.005647 bits per symbol is larger than S4's 0.001
(CODER_SPEC itself notes adversarial sequences reach about 0.0056), and the lower term depends on
the data. Nothing here changes S4 or its receipts; on every gate unit the Omega files are the C
coder's bytes, so they sit exactly where the C coder's do.

### Proof chain

1. **Model and telescoping (Lean 4, `docs/turing/proofs/TcrBound.lean`).** An explicit model of
   section 5 (`step`, `renorm`, `run`), for every list of valid symbols (q >= 1,
   cum + q <= 65536, cum + q = 65536 for the last symbol of the row):
   - `encode_bound`: (2^32 - 1) * prod q_t * 16711681^n * 256^S < 2^32 * (2^40)^n
   - `encode_lower`: 2^24 * (2^16)^n <= (2^32 - 1) * prod wq_t * 256^S, wq_t = q_t (+ 256 for a
     last symbol)

   where S is the number of renormalisation shifts. Lemmas `step_lb` and `step_ub` (each step keeps
   at least (1 - 65535/2^24) of p * R and at most R * wq / 2^16), `step_ge` (R' >= 256 and R' <= R,
   so at most two shifts and no overflow), `renorm_spec`, `run_bound`, `run_lower`. Negative
   controls: `bad_step_violates` (r = R >> 17 breaks the step inequality), `tight_without_loss`
   (the per-symbol loss factor is needed) and `lower_needs_slack` (the +256 credit is needed).
   The gate runs `lean TcrBound.lean` with the toolchain pinned in
   `docs/turing/proofs/lean-toolchain` (`leanprover/lean4:v4.35.0`) and requires 10 axiom lines,
   no `sorry` and no axiom outside propext, Classical.choice, Quot.sound (observed: `step_lb`,
   `step_ub` [propext, Quot.sound]; `run_bound`, `encode_bound`, `run_lower`, `encode_lower`
   [propext, Classical.choice, Quot.sound]; the three controls and `constants` none).
2. **Logarithm (receipts W1, W3).** log2 of `encode_bound`:
   8S < sum_t (16 - log2 q_t) + n (24 - log2 16711681) + (32 - log2 (2^32 - 1)), where
   sum_t (16 - log2 q_t) is the exact ideal length I, `24 - log2 16711681 = -log2(1 - 65535/2^24)`
   = eps with 10^6 eps = 5646.4768..., and 32 - log2(2^32 - 1) = 3.359e-10. log2 of
   `encode_lower`: 8S >= I - G - (log2(2^32 - 1) - 24), with log2(2^32 - 1) - 24 = 7.99999999966.
3. **Length identity (checked, not proved).** payload_bytes = S + 4, where S is the number of
   renormalisation shifts (one per time `range` goes below `2^24`), not a value computed from the
   payload. The flush is five `shift_low` calls; the fifth resolves (low is 0 by then) and its
   cache byte is the only one not emitted, which is why the emitted payload is S + 4 rather than
   S + 5. What each path actually compares:

   - **encode.** `encs` counts S in `EN[5]`. `encend` does not. `ST[6]` is the bytes emitted
     (`EN[6]`). `report` raises ALARM 1 when those bytes differ from S + 4. A carry before the
     first cached byte has nowhere to land; `shlow` raises the same ALARM 1 instead of refusing
     the input.
   - **decode and verify.** `decs` counts S in `DC[5]`, once per payload byte read in that loop.
     `decbeg` reads four bytes and does not count them. `ST[6]` is the declared payload. `ST[7]`
     is `DC[5]`. `report` raises ALARM 1 when the declared payload differs from S + 4. It does not
     store `payload - 4` back into `ST[7]`.
   - **selftest.** The same two comparisons: emitted bytes against `EN[5] + 4`, and, after a
     decode that round-trips, the payload against `DC[5] + 4`.

   A run that passes has `coded_bits = 8(S + 4) + 448 = 8S + 480`. A decoder that counts two
   shifts for one renorm byte still decodes, then fails ALARM 1; the host gate builds that mutant
   and requires the identity alarm on verify. Lean does not prove this identity.
4. **Integer ideal (receipt W2).** Wolfram recomputed the section 8 ub rule for every
   q = 1..65535: exact - ub lies in [-0.50019, +0.49984] ub; sum ub = 94,539,136,349 and
   sum q * ub mod 2^64 = 1,549,081,999,916,376. `tcr-om selftest` recomputes both sums in Omega and
   must match (ALARM 5 otherwise), so the Omega ub equals the rule for every q.
5. **Combining.** Upper: 10^6 coded_bits < ideal_ub + n (10^6 eps + 0.49984) + 480 x 10^6 +
   3.4e-4, and 5647 >= 10^6 eps + 0.501 leaves at least 0.022 ub per symbol, more than the
   3.4e-4 ub constant for any n >= 1; n = 0 gives equality (480 bits, a 4-byte payload). Lower:
   10^6 coded_bits > ideal_ub - 0.50019 n + 472 x 10^6 - 10^6 G, and 10^6 G <= gain_ub (each term
   is within 0.50019 + 0.49984 < 2 ub of its exact gain; for q > 65280 the gain is at most its value
   at q = 65281, 5646.48 ub < 5649).

Model-to-system link: the Lean `step`/`renorm` are a transcription of CODER_SPEC section 5 and of
the arithmetic in `encs`. The Lean proof covers that model, not `encs`. It never mentions `low`,
the cache, pending bytes, or `coded_bits`. `tc_range.om` is byte-identical to the C reference on
every gate unit and on two whole dev files (below). The renormalisation loops in `encs` and `decs`
carry `bound 2`, so a third shift (a range below 256, which `step_ge` rules out) traps (exit 104).
Byte identity with C and the run-time checks are what tie the model to the program. A change to
`encs` that the Lean model does not follow is caught by the byte identity with C and by those
checks, not by Lean.

## Results (EXERCISED on the Spark, omc `26540e6d...`, omega-mv base e4271abd)

`make test-turing-range-om` (part of the `turing-yield` gate step):

- selftest: 726 synthetic cases, 1,926,840 symbols, K = 2..16, four row shapes, three symbol
  choices (sampled, least likely, always the last symbol), n = 0 to 200,000: round trip exact,
  identity and both bounds hold; one random payload byte flipped per case is detected in all 726
  cases; ub rule exhaustive match. Smallest upper slack for n >= 1: 5647 ub (a single q = 1
  symbol, within eps of the bound); smallest lower slack 11,228 ub.
- 14 real units (2 committed CTR1 traces x the TY-2 candidate, uniform:9 and the five EXP-001
  candidates B0..B3, M): Omega encode byte-identical to C, C verifies every Omega file, Omega
  verifies every C file, Omega decode byte-identical to the TSY1, ideal_ub equal to the C value,
  both bounds PASS. Example (trace crumbs 05-07, TY-2 candidate): n = 1418, ideal 1456.957896
  bits, coded 1936 bits (242 bytes), upper bound 1944.965342 bits, lower bound 1922.925988 bits.
- Single-fault inputs refused with the same code as the C tool: flipped payload byte (CORRUPT),
  truncated (TRUNC), trailing byte (TRAIL), other TPS1 (BINDING), altered magic (HEADER),
  corrupted TPS1 (DIGEST), TSY1 of another trace (COUNT), corrupted TSY1 (DIGEST). A decode
  refused after its output was created leaves no file; an output path naming an input is refused
  (ARG) and the input is unchanged.
- Mutants caught on that run: `range >> 15` (no longer byte-identical), upper-bound constants
  lowered (ALARM 2), ub rounding removed (ALARM 5), lower-bound constant raised by 10 bits
  (ALARM 6).
- Lean: 10 theorems checked, standard axioms only.

The host script's later checks (decoder shift alarm, `n = cap+1` refused ARG, ALARM 7 on a
wrapping sum, and the `range >> 15` mutant required to differ or alarm on more than one unit)
are not part of the Spark paragraph above.

Whole dev file (seed 1 only; seeds 8 to 10 untouched), not part of the gate because the data is not
in the repository: 2,172,776 symbols, TY-2 candidate: ideal 1,752,630.382351 bits, coded 1,754,208
bits (219,276 bytes), byte-identical to C, round trip exact, upper slack 11,172 bits, lower bound
1,752,900.795377 bits; uniform:9 also byte-identical, both bounds PASS. Single core, nice 10, on a
shared machine at load 28 to 37: Omega encode 5.4 to 10.8 s, verify 5.1 to 21.8 s, decode 5.5 to
17.7 s; C encode 0.52 to 0.84 s.

## Not claimed

- Coder B (rANS, `TCA1`) is not ported; `tcr-om` refuses `rans` with usage.
- The length identity (proof step 3) is checked on encode, decode, verify and selftest, as that
  step describes. It is not proved in Lean. The Lean proof covers the model (`step`, `renorm`,
  `run`), not `encs`.
- The Lean check runs `lean` on the single file (it imports nothing); there is no lake project in
  this repository.
- C remains the reference implementation of the calibration profile; nothing here changes
  CODER_SPEC, S4 or any frozen receipt.

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

W3:

    {N[10^6*Log2[1 + 256/65281], 20], Ceiling[10^6*Log2[1 + 256/65281]], N[10^6*Log2[1 + 256/1], 20],
     N[Log2[2^32 - 1] - 24, 20], Floor[(2^64 - 1 - 480*10^6)/16005647], Floor[(2^64 - 1)/(8*10^6)]}
    -> {5646.4768139155787531..., 5647, 8.0056245491938781...*10^6, 7.9999999996640963..., 1152514738906, 2305843009213}

16005647 = 16,000,000 + 5647 is the largest growth of the upper bound per symbol in ub (ub(1) plus
the slope), so the bound of n symbols fits a 64-bit word up to the stated n.
