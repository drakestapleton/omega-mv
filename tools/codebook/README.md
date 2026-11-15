# tools/codebook: signed layered digit codebook (T-002 items 7-10)

Native OM-2 (`codebook.om`), built on the seeded SHA-256 core by `build.sh`, proved in Lean 4
(`proof/CodebookProof.lean`), tested by `test.sh`, mutation-checked by `mutate.sh`.

- **Wire.** A code is `(9xx)^k t`: k escape groups 900..999, then one terminal 000..899, every group
  exactly 3 decimal digits (1 tokenizer token each). A message is codes concatenated with no separator.
  Fixed width makes it prefix-free; 9xx escapes to the next layer, recursively.
- **Where.** Codes ride only in an inbox-line field `ocb2:<cbsha>:<counter>:<digits>:<mac>` (the last
  `|` field of a 6-field line). A leftover `ocb1:` line is legacy and never verifies. A bot DM stays one bare trit.
- **Codebook.** `codebook.tsv`, append-only `code<TAB>type<TAB>meaning`; types `r45 inst sig emerg`;
  `#` lines are comments. Its sha256 is the codebook id. 000-040 are the R45 ids, 041-099 reserved for
  instruction ids, 1xx signals, 3xx emergencies (power OB/LB are 310/311), 9xx escapes.
- **MAC.** HMAC-SHA256(key, `ocb2|cbsha|counter|lane|ts|from|to|tag|text|ref|digits`), key from a file
  path (mode must be `0600` with no group/other bits; the path must not contain a `boards/`
  segment). Counter file `STATE/<sender>.ctr` is `<counter> <ts>` (strictly increasing counter,
  and ts ≥ last ts), replaced atomically. `sign` stdin is 9 pipe fields
  `lane|ts|from|to|tag|text|ref|counter|digits`; `verify` takes an optional lane (`n` or `e`).
- **Trit.** `verify` prints `<verdict> <trit>`; trit 2 only for `ok` with a 3xx code, otherwise 1 (including every `ocb1:` line).

```
sh tools/codebook/build.sh                      # build/codebook/codebook
printf '901.12 345\n' | build/codebook/codebook enc      # 901012345
printf '901012345\n' | build/codebook/codebook dec       # 901.12 345
build/codebook/codebook sha tools/codebook/codebook.tsv
printf 'n|2026-11-15T12:00|omega-lead|a|task|do x|-|7|300\n' | build/codebook/codebook sign tools/codebook/codebook.tsv KEYFILE
build/codebook/codebook verify tools/codebook/codebook.tsv KEYFILE STATEDIR < inbox-lines
sh tools/codebook/test.sh ; sh tools/codebook/mutate.sh ; lean tools/codebook/proof/CodebookProof.lean
```

Round 4 (combined with tools/trit): `codebook.om` is the shared core and `main.om` the command line;
`tools/trit/build.sh` compiles the same `codebook.om` into trit. `codebook ext OLD NEW` exits 0 with
`ok <newsha>` when NEW is a valid codebook that starts with every byte of OLD, else `ERR notprefix`
(exit 6) or exit 4 when either file is invalid. `verify` holds `flock(LOCK_EX)` on `STATE/ctr.lock` for
the whole verify-and-advance pass and fsyncs STATE after each counter rename.
