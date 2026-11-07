# seed/profile: critical source profile (DRA-419)

`profile.om` is a seeded-Omega checker that applies an adaptation of Holzmann's Power of Ten to a
unit of `.om` sources. It runs from the repository root, because it reads the host words from
`seed/effects/effects.om`. Compile the checked unit with the pinned `omc` too. This tool is a
token-level profile, not a parser or a typechecker.

    profile [bounds] [SOURCE ...]     (no SOURCE: read the unit from stdin)

The sources are concatenated in the order given. Line numbers refer to that concatenation.

| exit | stdout | meaning |
|---|---|---|
| 0 | `PROFILE-PASS` | every rule holds |
| 1 | `PROFILE-REFUSED:<rule>:<line>` | first violation |
| 2 | (usage on stderr) | more than 16 arguments, or an unreadable argument |
| 3 | `PROFILE-INVALID` | a capacity was exceeded, the unit has no function, or `fn`/`end` are unbalanced |
| 4 | | I/O error, or a SOURCE cannot be opened |

Capacities, all fail-closed (exit 3): at most 65535 input bytes, 4095 lines, 16383 tokens, 63 bytes per
token, 128 functions and 128 host words. Every loop in the checker is bounded, and its storage is
static globals only.

## Rules

| id | rule |
|---|---|
| B1 | `while` needs `bound N`. A `for` count must be a literal, a `const`, `len X` of a declared array, or carry `bound N`. N must be at most 8192. |
| B2 | Recursion is admitted only in qualified form. Every function on a cycle takes `depth` as its first parameter, never assigns it and has no `new`. Each in-cycle call passes `depth` unchanged, or passes `NAME` after the canonical guard `NAME = add depth 1` / `if gt NAME LIM` (LIM at most 64) / an optional line / `ret`, `exit` or `trap` / `end`, with no reassignment of NAME before the call. An entry from outside the cycle passes a literal or a `const` of at most 64. The omc/DRA-311 leaf-removal analysis then runs over the remaining edges, and any surviving node is refused. |
| B3 | Each `global` and each `new` is at most 65536 elements. All globals together are at most 65536 bytes. The `new` bytes per function, and across the whole unit, are each at most 65536. |
| E1 | The result of a call or host word assigned to a name must be read on the straight-line continuation before the name is reassigned or the function returns. The exemption is `note p10 allow E1 <reason>` on the line before. |
| X1 | Host words (the effects table) appear only in functions marked `note p10 effect` on the line before `fn`. |
| P1 | A function marked `note p10 pure` contains no `put` and calls only pure functions. |
| C1 | `requires`, `ensures` and `invariant` need an earlier `om2` line. `om2 release` is refused, because it compiles contracts out. |

`bounds` mode checks B1, B2, B3, P1 and C1. It skips E1 and X1 for units that carry no p10 annotations,
such as `seed/omc/tests/recursion/nest.om`.

## Profiled modules

`seed/authority/action.om`, `store.om` and `lock.om` are profiled as one unit together with
`dispatch.om`, which is their consumer. The fixes this profile forced are as follows.

- **lock.om**
  - `lread` reported errors as pids 32, 33 and 34. It now sets `lerr`, so a live owner with pid 32 is no longer treated as a read error.
  - `lacq` refuses more than 1000 tries with return 43, and its loop is bounded.
- **store.om**
  - `dec` returns nothing.
  - The primary write and sync error wins over a cleanup close error. This is annotated.
- **dispatch.om**
  - `dcopy` is bounded.
  - A release failure returns 78, unless an earlier failure code is already set.
  - An `actlost` failure returns 79. Before this fix the error was overwritten.
  - A `writerec` failure on the lost path, or on the reconcile path, returns 77. Before this fix it was dropped.

## Limits (what is not proved)

- The analysis is textual and not path-sensitive. It handles the `NAME = ...` form only.
  - It is conservative about loop back-edges: a result read only at a loop head is refused.
  - `break` and `continue` do not end a path.
  - A callee that is not defined in the unit is not treated as a call.
- The unit result is a claim only for the sources passed in. It makes no whole-kernel or
  whole-repository claim, and it does not cover the code behind host words.
- `profile.om` and `gate.om` are not themselves profiled: their tables exceed B3.

## Checks

`sh seed/profile/check.sh` runs these checks:

- `profile.cases` (44 rows): one refusal fixture per rule, pre-fix controls on the real modules, and the capacity and stop rows.
- `mutants.cases`: one `profile.om` mutant per rule, each killed, with each control passing.
- The authority unit profile.
- A staleness check for the six authority gates, then compiling and running each of them.

`.github/workflows/om-profile-arm64.yml` runs the checks on pull requests, on pushes to main, and weekly.
