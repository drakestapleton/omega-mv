# seed/text: bytes, search, fields, integer text and UTF-8 code points in seeded Omega

The RM5 text unit of `docs/ROADMAP-1.0.md`: a composable `.om` file with no new compiler word, no
global, no `text`, no host word and no `om2` line of its own. A program puts `om2` first and
concatenates the unit before its own code:

```sh
{ printf 'om2\n'; cat seed/text/text.om app.om; } > app.full.om
seed/out/omc < app.full.om > app
```

| Function | Result |
|---|---|
| `tx_eq a b`, `tx_cmp a b` | byte equality; unsigned byte order, a proper prefix first (-1, 0, 1) |
| `tx_find h nd from` | first index >= from of nd in h, or `txnone`; empty nd is found at from |
| `tx_field s sep p` | end of the field starting at p (next sep, or `len s`); the split loop is in its note |
| `tx_pdec`, `tx_phex`, `tx_pdeci` (`s o n v`) | strict `[0-9]+`, `[0-9a-fA-F]+`, `-?[0-9]+` into `v[0]`: 0, `txeempty`, `txedigit`, `txerange` (never wrapped; a bad byte is reported before range) |
| `tx_fdec`, `tx_fdeci`, `tx_fhex` (`v [w] b o`) | decimal / lowercase hex (zero-padded to w <= 16) at `b[o ..]`: the end offset, or `txespace` with b unchanged |
| `tx_u8ok s o n` | `o + n` when well-formed UTF-8 (RFC 3629 section 4), else the first byte of the first ill-formed or truncated sequence |
| `tx_u8dec s o n` | the code point starting at `s[o]` as `(cp << 3) \| length`, or `txnone` when that sequence is ill-formed or truncated (same rules as `tx_u8ok`) |
| `tx_u8len cp` | UTF-8 length 1..4 of cp, or 0 for a surrogate D800..DFFF or a value above 10FFFF |
| `tx_u8enc cp b o` | cp as UTF-8 at `b[o ..]`: the end offset, `txerange` for a surrogate or out-of-range value, or `txespace` with b unchanged |

Arrays are OM-2 unsized views and edits owned by the caller; pass a slice with `part A o k`, and never
two slices of one array in one call (omc error 19). A slice outside its array traps 3. Long inputs are
walked in blocks of 65536, so lengths far above the 1000000-pass loop guard work. The UTF-8 state
machine is the one in `seed/json/json.om` (`js_u8st`), copied as `tx_u8st`; `tx_find` is a plain
comparison loop (time up to `len h * len nd`).

## Gate

`sh seed/text/tests/gate.sh` builds `tests/txdrv.om` with the unit, runs the cases from
`tests/gen.om` and requires every answer to equal that oracle's. `gen.om` is a separate seeded Omega
program that never calls `text.om`: byte loops for comparison, order, search and fields; strict-form
checks plus a digit-string comparison against the range limits for integer text; Unicode table 3-7
for UTF-8 validation, decoding and encoding. It replaced the Python oracle `tests/gen.py`: on omc
`cfd96b48` it wrote the same 18 files byte for byte as gen.py at `b2433586` (rows=1840870), and, built
without the 1-byte parse loop, the same files as gen.py at `965c3996` (rows=1839334), MT19937 seeded and
drawn as CPython 3.12's `random.Random(20261108)`. UTF-8 coverage: every 1- and 2-byte string, every
3-byte string with lead E0..EF, every 4-byte string with lead F0..F4 and second byte 80..BF over a
fixed sample of the last two bytes, and seeded random mixes; plus inputs that cross the 65536 block
edge. Integer text: fixed edges, every 1-byte string and every byte followed by `1` for D, H and I,
and seeded random digit strings. Decoding is checked on every 1- and 2-byte string, every 3-byte
string led by E0, E1, E8, ED, EF, sampled 4-byte strings and random mixes; encoding for every 7th code
point, the whole D700..E100 band, edges past 10FFFF and every room size 0..4. Twelve mutants (decimal
overflow boundary, surrogates, overlong E0 forms, needle at the end, prefix order, -2^63, truncated
sequence, 3-byte decode mask, U+D800 encoded, 3-byte lead byte, U+07FF length, backquote read as a
hex digit) must each give a wrong answer. Host run 2026-11-10 at omc `cfd96b48`: `TEXTGATE PASS
rows=1840870 mutants=12`. The gate is standalone and is not in `seed/host/check.sh`; its driver is
still sh with perl for the mutant edits (migration debt). Exit status: 0 PASS, 1 FAIL, 3 NOT_RUN (the
run was interrupted by HUP, INT or TERM). On a FAIL against the oracle the gate keeps its run folder
and names the cases file, the driver's exit status (100+N is trap N) and the got and want files.

The gate also runs `tests/boundary.cases` through the existing OM-2 conductor. It checks
empty end slices, wrapped offsets and counts, insufficient output space, unchanged caller
storage on clean refusal, invalid UTF-8 code points, and exact bounds traps. Two additional
mutants remove the offset and length guards; each must turn the expected trap into a clean
wrong return. These checks do not require allocating enormous arrays.

Function-mode `text` literals, including empty literals, are refused with error 9 under
OMEGESE section 9.12. The boundary cases enforce that named refusal, satisfying RM5's
literal support-or-refusal choice without claiming a foreign text ABI. The byte-array
functions remain composable; cross-language callers require separate RM7 qualification.

Not here yet: number text for floats (see `seed/json/jsonf.om`).
