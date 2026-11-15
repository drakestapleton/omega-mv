# trit: wake signal per bot (T-002)

```
trit DIR BOT...            one line "<bot> <1|2> <token>" per bot that has work
trit DIR --ack BOT TOKEN   prints the receipt "<bot> 0", then the next wake if any
```
Reads `DIR/inbox/<bot>.md` and the emergency lane `DIR/inbox/<bot>.emergency.md`. Only prints;
delivery stays outside (SendToAgent). Trit meaning follows TURNS.md (Drake 12:24): 1 = task,
2 = stop, 0 = read/done receipt (only from `--ack`), silence = nothing to do.

Exit status: 0 printed at least one line, 1 silent (no bot has work), 2 usage, 3 ack refused, 4 invalid codebook, 5 bad key,
70+ internal/I-O.

- A line is content when it starts `YYYY-MM-DDT`; headers are not content. `fyi` lines never wake.
- Format: 6 fields = `ts|from|to|tag|text|ref`, otherwise `ts|from|tag|text|ref`, after removing a
  last field that starts `ocb2:` or leftover `ocb1:` (the tools/codebook signature). A signed line
  must be the 6-field form.
- Signature (binding format, tools/codebook): last `|` field `ocb2:<cbsha>:<counter>:<digits>:<mac>`,
  mac = HMAC-SHA256(key, `ocb2|cbsha|counter|lane|ts|from|to|tag|text|ref|digits`). Lane is `n` or `e`
  from the file being read, not from the line. `to` must equal the bot being read. An `ocb1:` line is
  legacy and is capped at trit 1. trit is built from the same `tools/codebook/codebook.om` bytes
  (OM-2 has no imports; build.sh concatenates it) and `fn verified` calls its `verx`. Key and codebook:
  `DIR/codebook/key` (mode `& 077` must be 0; the path must not contain a `boards/` segment),
  `DIR/codebook/codebook.tsv`; without both nothing verifies. Counters: `DIR/inbox/<bot>.<sender>.ctr`
  (`<counter> <ts>`, per receiving bot), lock `DIR/inbox/<bot>.ctr.lock`.
- **2 only from a verified 3xx**: a line is 2 only when it verifies (codebook id, known codes, MAC,
  counter above the stored one and above any earlier verified line from that sender in this pass,
  and ts ≥ the last accepted ts)
  and one of its codes is a single 3xx group. Everything else that is not `fyi` is 1: STOP text, a
  `stop` tag, unsigned, tampered, wrong-key, stale and replayed lines. There is no `--trust-unsigned`.
- Stop text (still parsed, wakes at 1): the tag is `stop`, or the text is `STOP` / starts `STOP ` / `STOP:`.
- Reading never writes counters. `--ack` takes the lock (flock LOCK_EX), verifies every line up to the
  token and advances the counters (`.tmp`, fsync, renameat2, fsync of the directory), unlocks, then
  moves the cursor the same way. A crash between the two leaves those lines unread but stale (1).
- Emergency lane: a verified 3xx is 2 and is reported before the normal lane (ack it to see normal
  work). Other admitted lines there are 1 and are reported only when the normal lane is quiet.
  Admission: sender (field 2) is `drake` or a slug with `DIR/inbox/<slug>.md`, and the timestamp parses.
  Quota: at most 3 MAC-verified lines per sender within 60 minutes, counted once per (sender,
  counter) over the whole file; unsigned and forged lines and replayed copies use no quota. Unread
  rejected lines are counted on stderr: `rejected <bot> <n>`.
- Token: `L<offset>:<sha256 of bytes 0..offset>`, L = `n` or `e`, offset = end of the last complete line
  the trit was computed on. `--ack` moves that cursor to exactly the token; it refuses (exit 3, cursor
  untouched) a malformed token, an offset not at a line end inside the file, behind the cursor, or a
  prefix that no longer hashes to the token. There is no plain `--ack BOT`.
- Cursor: `DIR/inbox/<bot>[.emergency].md.cur` = `<offset> <sha256 of the whole prefix>`; any in-place
  rewrite before the offset, a truncation, or a malformed cursor makes the whole file unread. Written
  to `.tmp`, fsynced, then `renames` (renameat2) over the cursor, then the directory is fsynced.

Build and test from the repo root: `sh tools/trit/build.sh && sh tools/trit/test.sh`.
Proof: `lean tools/trit/proof/TritSignal.lean`. Namespace `TritBin` mirrors trit.om function by
function; `sh tools/trit/proof/difftest.sh` (python3 + lean) runs it with `#eval` against the binary
on generated fixture dirs and requires identical stdout, stderr and exit status. The fixtures include codebook-signed lines
(valid, tampered, wrong key/id, replayed, stale counter files) and unsigned STOP lines.
`sh tools/trit/mutate.sh` runs 16 mutants against both.
