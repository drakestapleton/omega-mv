# Independent source review: C17 u64 exporter v1 (L608)

Reviewer: factory bay 8 (run 285, card t_481af7ed). Not the exporter's author. Subject at omega-mv main
`1e3ecbba779ee84e2de70ec231e83533a9c61f45`: `src/adapters/c-u64-export.om`, `tools/adapters/c-export`,
`tools/adapters/build-c-export.py` against `spec/universal/c-u64-export-v1.md` and
`spec/universal/source-aware-v1.md`. Verdict: no defect found; one test expectation corrected (below).

## Checked properties

| property | where | finding |
|---|---|---|
| No second decoder or serializer | build concatenates the unchanged `vendor/sha256.om` and `core.om`; exporter calls `decode n` and reads `M`/`O*` | Holds. The exporter has no envelope parser or encoder of its own. omega-bridge main `f6b7cc40` emits C only from compiled Omega units (`src/native.om`, `src/freest.om`) and has no OMSB/OMSA reader, so the two C emitters take different inputs and do not overlap. |
| Output from records only | `xemit`, `xsignature` read `Oc/Oa/Ob/Oi` and `Xn/Xnm` only | Holds. The sidecar is decoded (validated) by `core.om` and never read. Exercised: semantic-only envelopes export identically; every accepted sidecar bit change exports byte-identically (corpus Z13). |
| S1 family gate | `xs1`, `xkind` | Language/profile pairs C 1/1, Rust 2/2, Python 3/4; runtime 0, ABI 1; per-record type 1, effects 0, alias 0; input attr 0/obligations 1; constant attr 1/obligations 0; ops 2..4 attr 1 and member obligations (1 or 5); any other opcode is 68. |
| Input slots | `xs1` second loop plus core decode | Core decode makes slots unique (`source-aware-v1` section "Input slot immediates 0..5 must be unique"); `xs1` refuses a slot >= input count, so the slots are exactly a permutation of 0..n-1. |
| Single-digit `i<s>` | `xemit` (`48 + slot`), `xsignature` (`48 + s`) | Safe: at most six input slots (0..5) by the v1 codec. |
| Fixed arrays (64) | `Xpr/Xln/Xdp/Xcn` | Safe: the v1 codec bounds a unit to 1..64 records, which is the size of `core.om`'s own operation arrays. |
| Operand order | `xmetric` reads metrics of `Oa/Ob` | Safe: the codec requires operands to reference earlier results, so metrics are computed before use. |
| Minimal parentheses | `xpa` (left: lower), `xpb` (right: lower or equal) | Matches spec rule; keeps the SSA tree for left-associative `-` and `*`. Mutant M1 (`le` to `lt` in `xpb`) is killed by the corpus. |
| Root selection | `xroot` | NORMALIZED rule as specified (n >= 3, `const 0` at n-2, `add(r, n-2)` with r < n-2); otherwise the last result. Mutant M3 (always last result) is killed. |
| Limits before output | `main`: total length, depth, re-import count all checked before the first write | Holds; refusals write nothing to stdout (corpus Z14, G1/G2 LIMIT rows). Saturation at 2^20 prevents overflow of the length/count metrics on shared graphs. |
| Length self-check | `if ne get Xl 0 total` | Defensive check that the emitted length equals the precomputed one; exits 65 if violated (unreachable in all runs). |
| Name rule | `xnameok`, wrapper `1 <= len <= 255` | `calc`, or `omega_` + at least one `[A-Za-z0-9_]`, at most 32 bytes; anything else 64 (corpus Z01..Z08). |
| Build identity | `tools/adapters/c-export` | Compiler sha256 `191b776e…98e9`, exact three-file source closure and binary hash checked before dispatch; otherwise 78 (corpus Z15). |

## Correction made during the review

The first corpus draft required every single-bit change to be refused. 27 of 1258 changes were accepted:
all inside the OMSP sidecar (encoding byte and span words), all accepted by the #621 codec's own
`sa decode`, and every one exported byte-identically. Spans and the encoding byte are not covered by
the sidecar hashes in `source-aware-v1`, so those are valid envelopes, not exporter defects. The rule
was corrected to agreement with the reference codec (Z13), which is the property the spec states.

## Not covered here

Exact-head CI (required for the QUALIFIED flag by `translation-v1.md` section 10) is NOT_RUN: there is
no CI on the Radicle forge for this branch. Native x86, other C compilers than the recorded GCC and
section 4.1 item 2 native realization of exported C are outside this review.
