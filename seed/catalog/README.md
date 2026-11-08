# seed/catalog: catalog, lock and resolver

A program written against the catalog is a short *compact source*. The source calls entries by
name, and a *lock* picks the entries that one build may use. `resolve` turns the catalog, the lock
and the compact source into one complete compilation unit. omc compiles that unit unchanged.

| file | content |
|---|---|
| `catalog.om` | catalog v1: entry #1 `add_times` |
| `resolve.om` | the resolver (OM-2 program; it uses `om/sha256/sha256-om2.om`) |
| `gate.sh` | glue for the gate: resolver build, f4 programs, Wolfram table, irequiv, refusals |
| `measure.sh` | glue for bytes and times of arms A (hand), B (catalog call) and C (catalog inline) |
| `tests/` | f4 programs, locks, drivers, `expected.tsv` (from Wolfram) and `neg/` refusal inputs |

## Build

```
{ sed 's/^export fn /fn /' om/sha256/sha256-om2.om; cat seed/catalog/resolve.om; } > full.om
seed/out/omc < full.om > resolve && chmod +x resolve
```

A program does not accept `export`, so `sed` drops that word from the sha256 functions. Nothing else
changes. Both compilers build the resolver: `seed/out/omc` and the f4 workflow pin `omc 2c824805`
(omega-mv e5b32567).

## Commands

```
resolve build CATALOG LOCK COMPACT MAP    unit on stdout, map written to MAP, one ACCT line on stderr
resolve card CATALOG LOCK                 per lock line: signature, card text, "e.g. " example
resolve ids CATALOG                       "NAME IDENTITY" per entry
```

The resolver reads no stdin, clock, environment or randomness. Identical inputs give identical
bytes; the gate checks this by resolving twice and comparing the outputs with `cmp`. A successful
run exits 0. A refusal writes nothing to stdout and creates no map file.

## Catalog entry

An entry is a *record*: the `note card` and `note eg` lines immediately before an `fn` line,
followed by that fn block, which ends at its matching `end`. Any other `note` line or a blank line
breaks the record. A line outside every record is `RESOLVE_SYNTAX`, and the catalog must end with
LF. Only the fn block is copied into a unit. The arm C lock appends ` inline` to the fn line.

- **identity**: the lowercase hex sha256 of the record bytes, each line with its LF
  (`sha256_hash` of `om/sha256/sha256-om2.om`). `gate.sh` compares it with `sha256sum` of the same
  lines.
- **dependencies**: a catalog name used in a body. Every dependency must be locked
  (`RESOLVE_UNLOCKED`). A self call or a cycle is `RESOLVE_CYCLE`. Units hold dependencies first
  and keep lock order otherwise.
- **admitted subset**:
  - Parameters are of integer scalar type. The return type is an integer scalar or `void`, and no
    word follows it.
  - Body lines are `note` lines, or they start with `if else while for ret break continue end`
    or `NAME =`.
  - Body words are operators and words from `tops` (arithmetic, comparisons, logic, `bound`),
    integer types, decimal numbers, the entry's own parameters and locals, or catalog names.
  - Anything else (`write`, `new`, `get`, `trap`, calls outside the catalog) is
    `RESOLVE_NOT_ADMITTED` at that catalog line. An entry therefore has no effects, no memory and
    no host words.

### Entry #1: `add_times`

```
fn add_times x int k int n ulong to int
s = x
for i ulong n
s = add s k
end
ret s
end
```

The f4 calc loop `s = x; for i ulong N; s = add s int K; end; ret s` becomes `ret add_times x K N`.

- **Value.** The result is x + n·k. Wolfram checks:
  - `Simplify[Nest[#+k&,x,n]/.n->3]` gives `3k+x`.
  - `RSolve[{a[j+1]==a[j]+k,a[0]==x},a[j],j]` gives `a[j] -> j*k + x`.
- **Traps.** Each `add` traps 1 (exit 101) on int overflow. With lo = -2^31 and hi = 2^31-1, the
  hand loop traps exactly when the final sum is out of range. Wolfram checks:
  - `Resolve[ForAll[{x,k,n}, lo<=x<=hi && n>=0, Equivalent[Exists[j,0<=j<=n, x+j k>hi || x+j k<lo], x+n k>hi || x+n k<lo]], Reals]` gives `True`.
  - `Resolve[ForAll[{x,k,n,j}, lo<=x<=hi && n>=0 && 0<=j<=n && lo<=x+n k<=hi, lo<=x+j k<=hi], Reals]` gives `True`.
- **Limit.** n ≤ 1000000. A `for` loop with a count that is not a literal is lowered as
  `while lt i n bound 1000000` (OMEGESE §4). For n > 1000000, the entry traps 4 (exit 104) at pass
  1000001, unless trap 1 comes first.

## Lock

Each lock line is `NAME SP IDENTITY [SP inline]`, at most 32 lines. A lock has no comments.

| lock line problem | refusal |
|---|---|
| unknown name | `RESOLVE_UNKNOWN` |
| identity differs from the catalog | `RESOLVE_IDENTITY` (a different catalog version) |
| name listed twice | `RESOLVE_DUPLICATE` |
| malformed line | `RESOLVE_SYNTAX` |

## Compact source and modes

- **Insertion.** Locked entries go immediately before the compact source's first `fn` line, or at
  the end of the unit when the source has no `fn` line.
- **Collisions** (`RESOLVE_COLLISION`):
  - a top-level name (`fn`, `text`, `global`, `const`, `struct`, `layout`, `abstract`) equal to a
    locked entry or to a parameter or local of one;
  - a binding (fn-line word, `for` variable, `NAME =`) equal to a locked entry.
- **Unlocked use.** A catalog name the source uses but neither locks nor defines is
  `RESOLVE_UNLOCKED` at the compact line. Any compact word equal to a catalog entry name counts as a
  use, also where omc would read it as a local name: lock it or rename the local.
- **om2 header.** The resolver reads the first line that is neither blank nor a note line, compared
  as a whole line from column 0, the way omc does (`om2lead`, `cp_mode`, `chk_mode`). These are om2
  headers: `om2`, `om2 diag`, `om2 debug`, `om2 release`, `om2 diag debug`, `om2 diag release`. A
  `check` or `next` line (compiler A) is followed by its om2 header on the next such line.
- **om2 insertion.** Inline entries require OM-2. When an inline entry is locked and the source has
  no om2 header, the resolver writes `om2` as unit line 1 (map `R om2`).
- **Mode refusals** (`RESOLVE_MODE`):
  - an `ir` header with an inline entry;
  - an `om2 fmt` header with any entry;
  - a `target` header line with an inline entry and no om2 (where om2 belongs next to target is
    not decided);
  - a `check` or `next` line with an inline entry and no om2 header after it;
  - in a source that would become OM-2 because of an insertion, a word that means something else
    in OM-2: the OM-2 keyword table of omc (`kw2`), the contract words `requires`, `ensures` and
    `invariant`, the unsized-view `*`, and a hex literal (`0x...`, error 6 in OM-1). On a `text`
    line only `text` and the name are read, not the literal. So one compact source either behaves
    the same with lock B and lock C or is refused with lock C.

## Map and accounting

- **Map.** One line per unit line: `C <compact line>`, `E <entry> <catalog line>` or `R om2`.
  `gate.sh` checks every unit line against the line its map line names.
- **Accounting.** One `ACCT` line on stderr:
  `ACCT compact_bytes= lock_bytes= catalog_bytes= entry_bytes= unit_bytes= unit_lines= entries= inline= om2_added=`.
  - `catalog_bytes` is the whole catalog file. It is charged to every build.
  - `entry_bytes` counts the fn blocks copied into the unit.

## Refusals

A refusal is one stderr line `RESOLVE_<NAME> line <N> <catalog|lock|compact|unit|map> <detail>` and
exit status. The detail is cut at 1000 bytes; the line feed is always written.

| name | exit |
|---|---|
| USAGE | 2 |
| IO | 3 |
| UNKNOWN | 10 |
| IDENTITY | 11 |
| COLLISION | 12 |
| DUPLICATE | 13 |
| CYCLE | 14 |
| CAPACITY | 15 |
| NOT_ADMITTED | 16 |
| MODE | 17 |
| UNLOCKED | 18 |
| SYNTAX | 19 |

Capacity limits (`RESOLVE_CAPACITY`):

| item | limit |
|---|---|
| catalog | 262144 B |
| lock | 4096 B and 32 lines |
| compact source | 65536 B |
| unit | 524288 B |
| map | 2097152 B |
| entries | 64 |
| record | 4096 B |
| parameters and locals per entry | 64 |
| top-level names in the compact source | 1024 |

A CR byte in any input is `RESOLVE_SYNTAX`.

## Gate

`seed/catalog/gate.sh [OUTDIR]` (env `OA`, `OB` = the two compilers) runs these checks:

1. Builds `resolve` with both compilers.
2. Checks the identity against `sha256sum`.
3. Resolves the four f4 programs (items 76666, 83423, 82342 and 85188) for arms B and C. Each
   resolve runs twice and the outputs are compared with `cmp`. The units from both resolver
   builds are compared, and the map is checked: a catalog fn line carries ` inline` exactly when
   the lock marks the entry inline, and the unit's ` inline` lines equal the lock's.
4. Compiles arms A, B and C with both compilers and compares their exit values with the Wolfram
   constants `Mod[{70+4*3, 71+5*3, 72+1*6, 70+2*4}, 256] -> {82, 86, 78, 78}`.
5. Runs every row of `tests/expected.tsv` through native drivers (`tests/drive.om`,
   `tests/dmain.om`):
   - f4 rows on arms A, B and C;
   - entry rows (x, k, n) on arms B and C.

   The rows include the int overflow boundaries, n = 0, n = 1000000 and n = 1000001 (trap 4).
6. Resolves a two-entry dependency closure (`tests/two.cat.om`, exit 94), which checks that the
   dependency comes first. Also checks that a compact source that already starts with `om2` keeps
   its own header, that every om2 header form in `tests/hdr/` is kept (exit 82 on both compilers;
   `checkom2` is resolved only), that `requires` as an OM-1 name runs with lock B
   (`tests/requires.compact.om`, `0+4*3 -> 12`), and that OM-2 words inside a text literal are not
   refused (`tests/textok.compact.om`).
7. Checks the wrong-constant mutant (`tests/neg/wrongk.cat.om`):
   - with the old lock it is refused (`RESOLVE_IDENTITY`);
   - re-locked, every step exits 0 and writes bytes, the table detects some rows but not all, and
     irequiv detects it.
8. irequiv `check` on the resolved `ir` unit (`tests/ir.compact.om`): hand loop vs catalog call
   over three ushort windows of x (top, bottom and middle of int), 65536 inputs each.
9. Runs 25 refusal controls (exit status, first four diagnostic words, empty stdout, no map), the
   usage refusal, and a diagnostic longer than its cap (still one line).

`expected.tsv` was written by this Wolfram query (the evaluator's output saved unchanged), with
`lo=-2^31; hi=2^31-1`:

```
f[x_,k_,n_]:=Which[n>10^6, If[lo<=x+10^6 k<=hi,"trap4","trap1"], lo<=x+n k<=hi, ToString[x+n k], True, "trap1"]
```

Rows:

- each f4 item uses x in {lo, lo+1, -1, 0, 1, 70, V, t-1, t, t+1, hi} with t = hi-K·N;
- the entry rows use pairs (k,n) in {(-7,5), (0,10^6), (1,10^6), (-1,10^6), (hi,1), (lo,1), (3,0),
  (0,10^6+1), (4,3)}, with x at lo, -1, 0, 1, hi and at those of hi-k·n, hi-k·n+1, lo-k·n and
  lo-k·n-1 that are int values (53 rows).

What irequiv cannot cover:

- **Arm C.** irequiv reads `ir` units, and `inline` is OM-2. Arm C is covered by the native table.
- **The whole int range of x.** `check` enumerates at most 24 parameter bits, so it covers three
  65536-wide windows. The rest of the range is covered by the Wolfram proofs above and the table.
- **k and n.** They stay fixed at the f4 constants.

## Measure

`seed/catalog/measure.sh OUTDIR REPS` writes `measure.tsv` with these columns:

- bytes: source, lock, catalog, entry, unit and executable;
- exit status;
- time: summed wall-clock ns of REPS resolve, omc and run invocations, including process start.

Arms: A is the hand program, B the compact source with `tests/lock.b`, C the compact source with
`tests/lock.c`. Programs: the four f4 items and `big` (n = 1000000). Run it under the CPU pool lock.
