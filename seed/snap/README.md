# seed/snap: words that click

Status: IMPLEMENTED, HOST_TESTED (2026-11-14). Not wired into any engine. No model has written a strand. GPU: NOT_RUN.

In an Omega program some items have no alternative: after `add a b` the line must end, and after `ret x` at
the end of a function the next line must be `end`. `snap.om` finds those items exactly where it can and
leaves everything else alone. It is the base for two ways of not paying a model step for them:

- Build 1, snap in the engine: the engine asks `snap` after each item and appends a forced item without
  sampling it. Output is the same program. Not built: no engine file is touched here.
- Build 2, single strand: the model writes only the items that were choices (`strip` shows that form) and
  `expand` puts the forced items back.

## Use

    seed/out/omc < seed/snap/snap.om > snap && chmod +x snap
    { cat seed/snap/words.table; echo '%%'; echo strip;  cat prog.om;  } | ./snap > prog.strand
    { cat seed/snap/words.table; echo '%%'; echo expand; cat prog.strand; } | ./snap > prog.back.om

`words.table` is one line per compiler word, `NAME ARITY FLAGS`, generated from omega-mcp `data/reference.json`
for the compiler in use (the reference whose `pin.omc_sha256` is `seed/out/omc`'s sha256; get it with
`git clone https://interplane.io/drakestapleton/omega-mcp.git` and use `omega-mcp/data/reference.json` at the
commit whose pin matches, or make it with that repository's `tools/gen-reference.py` against omega-mv at the
pinned head) by `gate.py --table REFERENCE_JSON > seed/snap/words.table`; the gate fails when the
file is stale for that reference or the reference's pin is not the compiler under test. FLAGS: 1 a type word; 2 a word whose
reference form has an optional tail (`[` in the form) and no rule of its own in snap, today only `kfdctl`,
whose SUFFIX length depends on the request; 0 otherwise. Modes: `strip`, `expand`, `count`. Every mode prints
`snap items N forced F bad B` on stderr. `strip` and `count` exit 3 (strip with no stdout) when the program has
something else where an item was forced (omc refuses such a program too). Other exits: 64 an unknown mode
word, 65 a bad table number (also input with no `%%` line, whose mode word is then read as a table row),
70 memory refused by the host, 71 read error, 72 write error. A mode word with no line end after it is an
empty program: exit 0, `items 0`. `expand` reports a forced line end at the very end of a strand line as an
ordinary item, so its `forced` count can be lower than `strip`'s; its output is unaffected.

## What is forced (and what is deliberately not)

Forced: the end of a line whose words are all present (statement words, operators and host words by their
table arity, known functions by their parameter count, known names), and `end` after a line that ends its
path (`ret`, `exit`, `trap`, `break`, `continue`) unless an `else` may still come.

Left open, so nothing is forced on that line: a name not yet known (it may be a later function), a word
with an optional tail (table flag 2, e.g. `kfdctl`), any bracket, `while` before an optional `bound`, `for` after its counter name, `get`/`put`/`offsetof` in a unit
with `struct`, `layout` or `abstract`, a function header in an `om2` unit, every top-level line that is not
a `fn` line. This under-counts; it never forces an item that had an alternative in the tested programs.

Limit of `expand`: a `note` line written between a path end and its forced `end` comes back after that
`end`. The compiled program is the same. `text` lines and `note` lines are copied with their leading and
trailing blanks removed, so an `om2 fmt` unit (whose omc output is its own formatted source) does not come back
byte for byte; a compiled program does.

## Gate

    python3 seed/snap/gate.py seed/out/omc REFERENCE_JSON SCRATCH PROGRAM_DIR...

Before any check the gate requires REFERENCE_JSON's pin to be omc's sha256 and `words.table` to equal its
projection, and checks that the oracle's word lists match `snap.om`'s. F (alarm) probes every word snap reads
by its table arity: a program with exactly that many arguments compiles and one more word is refused (error 5);
the words no probe program fits are printed by name on every run (today device words that need an
allowlisted request value, and `part`), and stay a known gap.

Python is the test conductor and the oracle (`snapref.py`, a second writing of the same rules); the product
is `snap.om`. The gate checks every program omc accepts: A strip equals the oracle, B expand equals the
oracle and compiles to the same binary as the original, C at every forced position omc refuses one more
word (line end) or one more statement (`end`), D seven broken machines each fail, E (alarm) every word
with an optional tail is used by at least one accepted program, so a new such word needs a fixture.

## Measured (host only)

Compiler: omega-mv main `098be1e5`, omc sha256 `26540e6d…8991`, run through the omega MCP sandbox.
Programs: 59 accepted examples of omega-harness main `f8561115` and the 20 `bench/inference_cost` reference
solutions (the table below); the gate adds the programs in `fixtures/`.

| Set | Programs | Items | Forced | Qwen3.8-27B tokens, program | tokens, strand |
|---|---|---|---|---|---|
| bench/inference_cost references | 20 | 1022 | 218 (21.3%) | 1265 | 1067 |
| omega-harness examples | 59 | 7891 | 1536 | 15057 | 13575 |
| both | 79 | 8913 | 1754 (19.7%) | 16322 | 14642 |

Items are words and line ends. Not re-checked here: the token counts below and the 0.313 row cost were
measured by the SnapPairs lane and their receipts are not in this repository. Tokens were counted with the tokenizer of Qwen3.8-27B-FP8 rev `017b9c7a`
(tokenizer.json sha256 `0997f410…`). On the bench set the strand is 198 tokens shorter (15.7%).

Gate run on the Spark (Linux AArch64) with the committed `seed/out/omc` (sha256 `26540e6d…8991`, unchanged at
omega-mv main `e4271abd`), programs from the omega-harness examples, `bench/inference_cost/tasks` (references
and the 20 deliberately wrong `mutant.om` answers, which still compile) and the fixtures: `SNAPGATE PASS
accepted=110 items=9510 forced=1909 positions=1909 mutants=7/7 probed=125 unprobed=8 fail=0`.

- A/B: 110 of 110 accepted programs pass; every expanded program compiles to the same binary.
- C: at all 1909 forced positions omc refused the alternative (error 5: 1548, error 16: 243, error 17: 118).
  26 of the 144 `end` positions were refused with error 16 instead of 17, so there the inserted statement may
  have been refused for another reason; those are weaker evidence.
- D: 7 of 7 mutants caught (each fails 2 to 108 of the 110 programs).
- E: optional-tail words: `kfdctl`, used by `fixtures/fx_kfdctl_*.om`.
- F: 125 words probed in omc, 0 wrong; 8 unprobed, named in the gate output.
- The 71 programs omc refuses were all answered by `strip` (none trapped).
- Fixed 2026-11-15: `strip` refused valid `kfdctl` programs (exit 3) because the table gave `kfdctl` a fixed
  arity of 5 while its SUFFIX adds 0, 1, 3 or 5 words by request. The first gate had no program using it.

MODELED, not measured: on the bench set Build 2 needs 1265/1067 = 1.186 times fewer model steps; Build 1
needs 1265/(1067 + 0.313 x 198) = 1.120 times fewer row-passes if a forced row costs 0.313 of a row (the
FP8 matrix-vector figure measured on the MI300X, one session, synthetic matrix; other per-row costs ignored).
Whether a model writes the strand form as correctly as the normal form is not measured.
