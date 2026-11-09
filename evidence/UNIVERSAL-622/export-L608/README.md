# #622 C export: independent corpus, refusals, review and #623 gate runs (L608)

Evidence class: REFERENCE + DIFFERENTIAL, NATIVE (host Linux AArch64, GB10 Spark CPU). No PROOF.
Exporter source is unchanged from omega-mv main `1e3ecbba779ee84e2de70ec231e83533a9c61f45`
(`src/adapters/c-u64-export.om` sha256 in `g1-validate-summary.json` / the build manifest); this branch
adds tests, a make target and this directory only.
Corpus, mutants and author self-test ran at branch head `2d986f31a`; the evidence commit after it adds
only comment lines (ORACLE labels), the spec status text and this directory. Home paths in logs are
written as `$HOME`.

## What was established

| check | command | result |
|---|---|---|
| author self-test (lane, TESTED) | `make -f mk/c-u64-export.mk test-c-export` | PASS, `author-selftest.log` |
| independent corpus (this branch) | `make -f mk/c-u64-export.mk test-c-export-corpus` | PASS 27/27 positives, 15/15 refusal rows, `corpus-and-mutants.log` |
| corpus negative controls | `make -f mk/c-u64-export.mk test-c-export-corpus-mutants` | 4/4 one-line exporter mutants KILLED |
| #623 G1 validation (validation lane, not this author) | `make -f mk/translation-validate.mk test-translation-validate` | PASS at `1e3ecbba`, `g1-validate-summary.json` |
| #623 G2 composition (validation lane) | `make -f mk/translation-validate.mk test-translation-compose` | PASS at `1e3ecbba`, all six directed compositions incl. Rust->C 35/35 and Python->C 39/39, `g2-compose-summary.json` |
| source review | read against the export and codec specs | no defect, `review.md` |

The corpus (`tests/universal/translation/c_export_corpus.json`) is disjoint from F1, the C import
controls and F2. Every expected export text was written by hand from the spec's rendering rules.
Per positive: exact form, deterministic, semantic-only envelope exports identically, exported C compiles
with `cc -std=c17 -O2 -Wall -Wextra -Wno-unused-parameter -Werror -pedantic`, compiled original (cc, or
python3 for the Python cases) equals compiled export on boundary and seeded random vectors, `sa identity`
of the re-import equals the original import (C cases), and `export(import(export)) == export`.
Refusals: bad command and names (64), empty input, all 628 truncations, a trailing byte and an
oversized input (65), every bit-0/bit-7 flip of a 629-byte unit agreeing with the #621 codec's own
`sa decode` (1191 refused 65, 40 refused 68, 27 accepted sidecar changes exporting byte-identically), a
real Python unit whose C rendering needs depth 17 (67) and a stale build (78).

## Guarantees this evidence supports (scope)

- Scope: S1 family only (C 1/1, Rust 2/2, Python 3/4 members of source-aware v1), at most six inputs,
  64 records, output at most 4096 bytes, depth at most 16, re-import at most 64 operations.
- Identity: the C output depends only on the OMSA records (not the sidecar, not the member); the
  re-imported C unit has the same semantic identity as the C import it came from.
- Fidelity: generated C computes the same u64 function as the source on every observed vector, through
  real compilers (gcc for C, python3, and rustc in G2).
- No duplicate lower serializer: the exporter reuses the unchanged `core.om` decoder; omega-bridge emits
  C only from compiled Omega units and has no OMSB/OMSA reader.

## Pins

- Adapter compiler `191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9`, born by
  `tools/source-aware/build` from omega-bridge `0fc7d8662cb799e7c206b17c18ea4c3ec2b8fea9` (Radicle
  storage `rad:z3Hr9ZaiKHwwuNzPK5M8c7uw6pj7y`).
- Native omc `734f0a39319fbfa930bcc62cb30dbf06d47d78e126372b74f5baf478e6126b61`, born by
  `sh seed/omega-from-seed.sh` at omega-mv `acb3f15cdc691b1b046b48b0dad0f9255a12ba4b` (RC=0, sha256
  equal). Bridge generator from omega-bridge `012860dbf26ee62a9838594b9dfd1e3e94a540a9`.
- gcc, python3 and rustc versions are recorded in the summaries.

## NOT_RUN

Exact-head CI (part of the QUALIFIED flag in `translation-v1.md` section 10; there is no CI on the
Radicle forge), native x86, other C compilers, and compose section 4.1 item 2 (native realization of
the exported C). The spec status therefore stays TESTED plus independent validation PASS, not QUALIFIED.
