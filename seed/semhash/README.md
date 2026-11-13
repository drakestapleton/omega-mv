# seed/semhash: meaning hash and semantic diff for Omega units (M1)

`semhash.om` is a seeded-Omega tool. It gives every function of a `.om` unit a hash of what the function
means, not how it is spelled. Renaming locals or parameters, adding or removing notes, blank lines or
spacing, and reordering functions do not change a function's hash. The tool errs toward CHANGED: when
it cannot prove that a spelling is meaning-free, it keeps the spelling verbatim, so the change shows
up as CHANGED rather than SAME.

The design is close to Unison's content-addressed definitions. A call is hashed as the callee's
hash (Merkle), so a change in a leaf reaches every transitive caller, and a function-name-only rename
keeps its hash.

## Build

`semhash.om` has no `om2` line. It is compiled after the plain-function form of `om/sha256/sha256-om2.om`:

```sh
mkdir -p build
{ sed 's/^export fn /fn /' om/sha256/sha256-om2.om; cat seed/semhash/semhash.om; } > build/semhash.full.om \
  && $OMC < build/semhash.full.om > build/semhash && chmod +x build/semhash
```

`$OMC` is the pinned seed compiler. `check.sh` pins sha256
`bef974c1414dbac5b8f636d872a5815fb04594cda7bb213e9c0e0a1ff6f31c5b`. A missing or different compiler
makes it print `SEMHASH NOT_RUN` and exit 3.

## Modes

| command | output | exit |
| --- | --- | --- |
| `semhash < u.om` or `semhash hash < u.om` | `FN name hex line=N[ verbatim][ cycle]` per function, then `UNIT hex fns=n` | 0 |
| `semhash canon < u.om` | the unit with locals renamed by first occurrence (`v0 v1 ...`, or the first of `w y z q` whose letter-digit names are unused), with notes and blank lines dropped and tokens joined by one space | 0 |
| `semhash diff a.om b.om` | `SAME`, `CHANGED` or `REMOVED name`, `RENAMED a->b`, `ADDED name`, then `EXPORTS CHANGED` and `ENTRY CHANGED a->b` if they apply, then `DIFF SAME` or `DIFF CHANGED n=K` | 0 same, 1 changed |
| `semhash keywords` | the keyword table (`word code`) the tool classifies with | 0 |
| `semhash dups < records` | records are hash-mode `FN` lines with a unit path in front (`PATH FN name hex line=N...`). Every `SKIP ...` line is echoed. Then, for each set of two or more records with the same 64-digit hash, `DUP hex n=K` followed by `  PATH name line=N...` per member, in input order; last `DUPS groups=G fns=F records=R skipped=S` | 0 |

The other exit codes are:

- 2: a usage error or an unreadable diff file.
- 3: refused input, with the reason on stderr. The causes are:
  - a CR byte;
  - an input over 8 MiB;
  - a control byte outside a note;
  - an unterminated text, fn or layout block;
  - a token starting with `$`, `#` or `@`;
  - a duplicate fn name;
  - a capacity overflow;
  - no free canon letter;
  - canon of an `om2 fmt` unit.
- 91-94: internal errors.

## Duplicate-function report (#827 M1)

`sh seed/semhash/dups.sh SEMHASH [-i INDEX] [DIR...]` hashes every `.om` unit under the given
directories (default `om seed`, from the repository root, in `LC_ALL=C` path order), puts each
unit's path in front of its `FN` lines and pipes them to `SEMHASH dups`. A unit that semhash
refuses becomes `SKIP path rc=N reason`. With `-i INDEX` the records themselves, which form the
function-level meaning-hash index (one `PATH FN name hex line=N...` line per function), are also
written to `INDEX`. Equal hashes mean equal meaning as far as this tool can prove it (see the next
two sections), so a group is a set of functions that one shared definition could replace.
The grouping is in `semhash.om`; the script only lists files and runs the tool.

At omega-mv `d3d1b1bc` the report over `om/` and `seed/` is `dups/report-d3d1b1bc.txt`:
`DUPS groups=449 fns=1542 records=6959 skipped=17`. The 17 skipped units are the
deliberately malformed compiler fixtures (CR bytes, unterminated blocks) and
`dups/refused.om`. The largest group is 66 copies of `fn main to int` / `ret 0`. Many groups are
test fixtures that repeat a helper on purpose; others, such as `inb`, `obflush`, `ob1` and
`hexval` in `om/aarch64`, `om/codec`, `om/evidence`, `om/gpumath` and `om/tls`, are library code
that could share one unit.

## What a function hash covers

- **The profile header**: the exact `om2 ...` or `ir` lead line, or `om1`.
- **The function's tokens**:
  - parameters and locals become `$k`, numbered by first occurrence;
  - each callee becomes `#<callee hash>`, and a self call becomes `@self`;
  - every other token is kept as written.
- **Declarations**: every declaration the function uses, followed transitively. These are global,
  text, const, struct, layout, abstract and holds.
- **Unrecognised top-level lines**: every one of them.
- **Mutual recursion**: functions in one call cycle are hashed as a group. Each member keeps its own
  name and the names of the other members, and gets ` cycle` on its FN line.
- **The unit hash**: covers the header and every item in source order. Reordering therefore keeps
  every function hash and changes the unit hash.

## Not normalised (renaming these reports CHANGED)

The following are not normalised:

- Function names inside a call cycle. Because of this, RENAMED is not detected for cycle members.
- Global, text, const, struct, field, layout and abstract names.
- Locals spelled like any struct or layout field name. `get c fa` reads field `fa` when `fa` is a
  layout field, so these locals are never renamed.
- Locals longer than 8 bytes.
- Contextual names (`requires ensures invariant result`).
- Every local of a function whose parameter list the tool cannot parse. That function is marked
  ` verbatim`.
- Parentheses and grouping, number spelling (`10` vs `0xa`), and the operand order of commutative
  operators.

Changing the profile line changes every function hash. A change to a declaration that no function
uses does not show as CHANGED for any function, but it does change the unit hash. Function order
matters only through the `ENTRY` and `EXPORTS` lines and the unit hash.

## Check

Run `sh seed/semhash/check.sh` from anywhere. It makes these checks:

1. **Keyword parity**: the tool's table must equal the two `word:code` lists of `seed/omc/genkw.awk` plus the
   `fn kw2` table of `seed/omc/omc.om`, decoded in sh.
2. **Oracle**: for every unit omc accepts, `omc(canon(x))` must be byte-identical to `omc(x)`.
   - The units are rung4, contracts, omc tests, om2, host tests, the json compositions, blake3,
     sha256, leakscan, the tool itself and the cases.
   - For a unit omc refuses, the canon form must stay refused.
   - `om2 fmt` units are skipped, because their output is the formatted source text.
3. **Cases**: `cases/*.om` are diffed against `cases/base.om`, and stdout and the exit code are
   compared with `cases/*.exp`.
   - `inv_*` cases must be all SAME.
   - `neg_*` cases are the negative controls, which must report CHANGED.
   - `ren_fn` must report `RENAMED`.
4. **Unit hashes**: they must be equal for alpha renaming and for notes and spacing, and differ for
   reordering.
5. **Refusals and usage**: the CR input, reserved-byte input and unknown-mode cases are checked.
6. **Mutant**: a copy of the tool with `while` dropped from its table must fail both keyword parity
   and the oracle (`mutant killed`).
7. **Dups**: `dups.sh` over `dups/` (`a.om`, `b.om`, `refused.om`) must print `dups/dups.exp`
   exactly: `a.om sq` and `b.om sq2` (a renamed parameter) group, `inc` and `inc2` (a different
   constant) do not, and `refused.om` is a SKIP. Control: the same records with one hash digit
   changed past the first 16 must give `groups=0`, so grouping compares the whole hash, not the key.

`cases` in the PASS line counts the oracle-identical units, the non-control cases and the dups
check. `controls` counts the `neg_*` cases, the three refusal and usage checks, the killed mutant
and the dups control.
