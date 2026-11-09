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
`tests/gen.py` and requires every answer to equal the Python oracle (test harness only, `python3 -I`,
never part of an Omega build): bytes comparison and order, `bytes.find`, `bytes.split`, `int()` on the
strict forms with explicit range limits, `format()`, and `bytes.decode('utf-8')` whose error start is
the expected index. UTF-8 coverage: every 1- and 2-byte string, every 3-byte string with lead E0..EF,
every 4-byte string with lead F0..F4 and second byte 80..BF over a fixed sample of the last two bytes,
and seeded random mixes; plus inputs that cross the 65536 block edge. Decoding is checked against the
first code point Python decodes (every 1- and 2-byte string, every 3-byte string led by E0, E1, E8, ED,
EF, sampled 4-byte strings, random mixes); encoding against `chr(cp).encode()` for every 7th code
point, the whole D700..E100 band, edges past 10FFFF and every room size 0..4. Eleven mutants (decimal
overflow boundary, surrogates, overlong E0 forms, needle at the end, prefix order, -2^63, truncated
sequence, 3-byte decode mask, U+D800 encoded, 3-byte lead byte, U+07FF length) must each give a wrong
answer. Host run 2026-11-08 at omc `cfd96b48`: `TEXTGATE PASS rows=1840870 mutants=11`. Like `seed/json`, the gate is standalone (it needs Python) and is not in `seed/host/check.sh`.

Not here yet: number text for floats (see `seed/json/jsonf.om`),
and text in function mode (RM5's ABI item).
