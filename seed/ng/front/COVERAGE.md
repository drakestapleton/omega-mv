# NG front coverage

The inventory and dated checkpoints below are historical measurements at the named
revisions. Current contract and data lowering is described in the final sections.

## Baseline at a59a425b

The oracle is seed/out/omc, SHA256 6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8.
The check pass and lowering are separate. FRONTGATE checks accept/refuse diagnostics, not execution.
Baseline FRONTGATE: 6322 cases, exact 6205, beyond 11, scope 105, ngonly 1; failures 0; mutants killed 5/5.
Baseline FRONTIRGATE: 62 cases, run 32, refuse 30; failures 0; mutants killed 3/3; controls tripped 2/2; NOT_RUN 0.

## Exhaustive vocabulary inventory

The seeded tables kw and kw2 in seed/omc/omc.om and OMEGESE sections 9, 10, 12 are the authorities.
Y means lowered, P partial, N not lowered, R a reserved spelling without an accepted executable form.
A word being listed Y does not claim that a program containing other missing constructs lowers.
Counts below are MEASURED tracked-file whole-word occurrences across seed/, om/, tests/ (1488 .om files),
including notes and negative fixtures. OM-2-only counts (nominal, layout, fresh, contract, hygiene and unit words)
use 635 files: the 634 with an `om2` line plus seed/omc/omc.om, whose notes name every word, so OM-2 units alone
give each of those counts one less. Counts rank investigation demand, not executed use or language acceptance.
The packed C2 manifest is surveyed separately.

| Words or construct | Baseline IR emitted | Same behavior | Gap |
|---|---|---|---|
| bool, uchar/u8, ushort/u16, uint/u32, ulong/u64, byte/i8, short/i16, int/i32, long/i64, f32, f64, void | P | Fixture-scoped only; generally unproven | subject to construct coverage; bool and qty constants lower |
| qty | Y (ng-front-groups-7) | fixture-scoped only: every unit of tests/quantity (38 run equal, 39 refusals equal), cases/qty_shamt.om | none known for scalars, arrays, globals, constants and shift amounts |
| add sub mul div rem and or xor eq ne lt le gt ge neg not | P | Fixture-scoped only; generally unproven | abstract operands absent |
| shl shr | Y (ng-groups-4) | Fixture-scoped only (cases/sh_mix*.om, cases/qty_shamt.om); generally unproven | a bool or float amount, which omc admits, exits 64 (cases-lower-scope.txt) |
| rotr rotl | P | Fixture-scoped only; generally unproven | abstract operands absent |
| fsqrt fabs bitcast | Y | Fixture-scoped only; generally unproven | subject to operand construct coverage |
| fmin fmax fma | Y: fma (ng-groups-4), fmin/fmax (ng-front-groups-6) | fixture-scoped only: cases/fma_mix.om (fused against unfused), cases/fmm_mix.om (signed zeros, quiet and signaling NaNs, both widths) | none for scalar f32/f64 |
| true false = ( ) | Y | Fixture-scoped only; generally unproven |  |
| get put len new | P | Fixture-scoped only; generally unproven | scalar arrays, struct fields and layout fields lower in the parent's candidate `fe_lst*`/`fe_lly*` (see Nominal section below); runtime pools lower through checked descriptor operations; see "Runtime pools" below |
| view edit part | Y (sized parameters as SLICE: ng-front-groups-8) | Fixture-scoped only; generally unproven |  |
| global text const | Y (empty text, bool and qty const: ng-front-groups-7, -8) | Fixture-scoped only; generally unproven |  |
| struct layout field at little big sizeof offsetof | Y in the candidate (seed/ng/src/front.om, uncommitted when this row was written) | host-EXERCISED only: gate-front-ir `nom-*` rows (31 run, 54 refuse) | struct bool fields (below); functions without main stay function mode |
| abstract ops seal open holds | Y in the candidate (`fe_lseal`) | host-EXERCISED only: gate-front-ir `nom-a-*`, `nom-abstract-*` rows | a-kept-diag and a-exact-diag (no main) stay function mode |
| fn to ret end | P | Fixture-scoped only; generally unproven | main must return int; units without main absent |
| inline for unroll while bound if else break continue trap exit | P | Fixture-scoped only; generally unproven | M1 fixtures only; signed latch wrapping was incorrect before e156056a; contracts absent |
| requires ensures invariant result | N | No: silent omission before the safety head | no observation-point lowering |
| fresh out export | N | NOT_RUN | fresh token; function-mode/out/export units absent |
| note | Y | Fixture-scoped only; generally unproven | ignored |
| own free | R | NOT_RUN | seeded parser refuses their unsupported forms |
| dit scrub | N | NOT_RUN | no value lowering |
| read write monons realns | Y | Fixture-scoped only; generally unproven |  |
| every other host word in table below (95 with cpufence, cpurelax) | Y (ng-front-host, scheduler words ng-front-hostwords-99) | 39 of 99 host programs exit/stdout-equal to omc under ngrun; 60 lowered and ngcheck-accepted, run refused by ngrun's class (IR.md s7.11), NOT_RUN | behavior of words ngrun refuses (process and scheduler, limits, device, network, paths outside scratch, random, cpunow, syncfs) not executed |
| om2, om2 debug/release/diag | P | Fixture-scoped only; generally unproven | fmt and some contract policies exit 64 |
| om2 fmt | N | NOT_RUN | formatting output not reproduced |
| target x86linux/x86efi and efi, ir units | outside D8 | NOT_RUN | existing scope refusal, not an NG CPU-front implementation claim |

## Missing group order by real source-file demand

1. Host effects: fclose 134, fopen 119, argcnt 111, argread 104, fork 71, waitpid 65, sleepns 58,
   unlink 52, killpid 47, execprog 45. Lowered host clocks: monons 103, realns 14.
2. Shift operand types: shl 259, shr 230. Baseline survey first blocker in 131 packed/current inputs. (ng-groups-4 lowers integer value/amount mixes; the survey was not rerun, so the 131 is the baseline count.)
3. Data edge cases: arrays new 445, globals 331, text 308, view 316, edit 259, const 103, qty 75;
   layout 71, field 68, struct 63; fresh 45; nominal abstract 52, holds 67, seal 49, open 34.
4. Contracts: requires 30, ensures 18, invariant 17, result 21; header policies on each file's first om2 line:
   release 12, debug 1, diag 46 (fmt 11).
5. Float intrinsics: fma 16, fmin 7, fmax 7; hygiene scrub 13, dit 7. (ng-groups-4 lowers fma; ng-front-groups-6 fmin/fmax.)
6. Units: export 28, out 72 (whole-word counts include prose); function-mode IR entry requires an IR-owner change.

All ordinary loop/branch forms already have lowering; they need complete fixtures, not a replacement parser.

## Every host keyword and candidate-file count

All entries are N at baseline except read/write/monons/realns, which are Y.

| Word | Files | Word | Files |
|---|---:|---|---:|
| read | 259 | write | 354 |
| fclose | 134 | fsync | 16 |
| fchmod | 8 | fseek | 22 |
| socknew | 14 | listen | 7 |
| accept | 29 | fork | 71 |
| dupfd | 34 | monons | 103 |
| fopen | 119 | unlink | 52 |
| makedir | 38 | getdnts | 14 |
| connect | 16 | bind | 16 |
| waitpid | 65 | fstat | 15 |
| recv | 8 | send | 13 |
| sleepns | 58 | argcnt | 111 |
| argread | 104 | waitio | 17 |
| execprog | 45 | renames | 17 |
| rmdir | 8 | killpid | 47 |
| pipefds | 17 | getpid | 37 |
| realns | 14 | sockname | 7 |
| cwd | 7 | readlnk | 8 |
| sockopt | 5 | random | 22 |
| envcnt | 9 | envread | 8 |
| chdir | 6 | ftrunc | 9 |
| stat | 28 | link | 16 |
| symlnk | 8 | chmod | 8 |
| faccess | 4 | getuid | 8 |
| geteuid | 9 | getgid | 7 |
| getegid | 5 | lstat | 10 |
| truncate | 14 | chown | 2 |
| fchdir | 2 | getppid | 6 |
| umask | 3 | fdsync | 6 |
| memfd | 8 | setsid | 3 |
| getpgid | 2 | setpgid | 11 |
| pread | 24 | pwrite | 14 |
| getsid | 2 | syncfs | 2 |
| shutdown | 4 | devctl | 7 |
| mapnew | 27 | mapdrop | 25 |
| mapread | 19 | mapwrite | 18 |
| devcall | 7 | uvmctl | 7 |
| mapaddr | 8 | mapget | 29 |
| mapset | 26 | maphold | 6 |
| mapbind | 6 | flock | 9 |
| execpure | 11 | cpufence | 7 |
| cpurelax | 7 | peercred | 2 |
| pollfds | 15 | sendmsg | 4 |
| peername | 3 | vfioctl | 3 |
| vfiomap | 4 | vfiomapw | 4 |
| eventfd | 17 | vfioirq | 4 |
| execenv | 5 | prlimit | 8 |

## Baseline source survey

All 5874 packed C2 sources and 1488 tracked .om sources were sent through front-ir (7362 inputs).
Two cyclic size-generator C2 inputs were not materialized in this survey; FRONTGATE covers them.
The per-input result tables are uncommitted lane evidence (hand-off READY-omega-mv-ng-front-coverage-2 names their path); their sha256 values are
tree.tsv 1319f3cdc9a1896472a0b365ed3b50fef7dfe5b88ad7d26310436ed0199c3ea7 (1488 rows),
c2.tsv 95d0a7b52ef52d9d9a191fcc7c30b3e9073d733c71c8565270ab39c27a395058 (5874 rows) and
site.tsv 7c7bfa56a76cbeaec867e8894f6ebff0761b50b023dd53139824089c3fb3412f (7362 rows).
674 emitted IR (this alone is not behavioral parity); 850 reached a lowering/scope refusal. Other inputs were rejected by the check pass.
First refusal site counts (not additive demand estimates): no main 250, missing value dispatcher 220 (172 host-bearing first-blocker lines, 48 other expressions),
unequal shift types 131, D8 scope 116, non-int main signature 42, top-level declaration 19,
struct/layout parameter kinds 16, contract-prefix unresolved calls 16, fmt/contract policy 10, fresh signature 9,
unsupported nominal type 8, unsupported scalar type reader 4, unconsumed allocation queue 1, CPU statement 1,
empty text 6, sized text argument 1.
Several accepted function units end at EOF and intentionally have no main. They are not malformed programs.

## Reproduction and evidence boundary

The standing commands are in README.md. The frozen manifest is seed/qualification/om2/manifest-c2.txt.
The baseline source survey records lowering availability, not stdout/exit parity. A program rejected by the
check pass is never executed. Execution uses FRONTIRGATE only after omc and ng both accepted and ngcheck accepted.
No function-mode blob is executed as an ELF. Function-mode units are explicitly outside this run per Main. Host programs need the independently owned ngrun host extension;
IR acceptance alone is not execution evidence.

## This run: prioritized corrections and contract safety

Main narrowed this run to signed-latch overflow, float-to-integer saturation, this inventory, and at most
one lowering group. The initial demand order put host effects first: 172 accepted-source first-blocker lines contain an unlowered
host word, versus 131 unequal-shift operand-type blockers. Recorded lines are capped at 80 bytes, so the
host-bearing line count is a lower bound, not a sum of distinct word demands. No function-mode ABI or
whole-language completion is claimed. Main subsequently replaced the host group with contract safety,
because several accepted IR units silently omitted contracts. Host lowering is deferred in ham/NEXT.md.

| Construct | Before | After signed-latch head | Float candidate, not READY |
|---|---|---|---|
| signed for latch after body writes max | unchecked wrap, then trap 4 | chk.add trap 1, like omc; i8/i64 both exercised | unchanged |
| float to each integer width | incorrect trapping chk.conv | unchanged | proposed total IR conv; final edge-input forms NOT_RUN |
| integer to integer narrowing | checked conversion | unchanged | range check retained |
| all other missing rows above | not widened | unchanged | unchanged |

The signed-latch head e156056aea955a1e1ac6b881cef0cd660158e3b9 is based on Radicle main
19ed248e73c43bd8ee27fc99582f466123ef5cd5, cherry-picking CompilerBugHunt b498dc3c with credit.
FRONTGATE PASS 6322, FRONTIRGATE PASS 64 (34 run / 30 refuse), all eight mutants killed and both controls
tripped across the two gates. Pre-fix NG: both latch reproducers exit 104, omc exits 101; fixed NG exits 101.

Coverage is a source and fixture inventory, not qualification. MERGED, DEPLOYED and hardware QUALIFIED
are not inferred from host gates. The separate READY files name exact heads, commands and measured counts.

### Semantic coverage warning

IR emission is not evidence of equal behavior. In particular, short native contract clauses were
misread as local assignments, so false/requires/void/fallthrough emitted IR without their required
checks. Their runtime counterexamples and fail-closed correction belong to the separate contract
safety head. Other unqualified rows above remain unproven outside the named differential fixtures;
no whole-language or every-program semantic-equivalence claim follows from the inventory.

## Delivered contract-safety head

86d9ba1ebd8497600e67173b002f39ae7052f057, parent e156056aea955a1e1ac6b881cef0cd660158e3b9.

| Contract fixture | omc runtime | Previous NG runtime | Delivered front-ir | Same runtime behavior proved? |
|---|---:|---:|---|---|
| false, requires | 109 | 0 | exit 64, zero output bytes | No: safely not lowered |
| void, fallthrough | 110 | 0 | exit 64, zero output bytes | No: safely not lowered |

The central clause-recognition guard covers requires, ensures and invariant before any IR is written.
FRONTGATE PASS 6322 (5/5 mutants); FRONTIRGATE PASS 64 (3/3 mutants, 2/2 controls); dedicated
contract scope FRONTGATE PASS 4 with the silent-path guard-removal mutant killed. This is an
explicitly unsupported language boundary, not a successful contract implementation.

## Remaining concrete work

1. Real contracts: preserve the guard as a fallback; consume function prefixes and lower requires to
   chk.true code 9 at entry. Save the prefix cursor for ensures, evaluated at every normal explicit
   or implicit return with one preserved SSA return value and current parameter/array values. Bind
   result only during value postconditions. Emit invariant chk.true code 10 in the loop head before
   its condition, including zero trips and final false tests; for-continue increments first, while-
   continue returns directly to that checked head, and break/exit/trap do not invent postconditions.
   Respect release erasure with no runtime evaluation or optimizer assumptions. Consume fresh array
   signature markers and permit diagnostic mode without changing the check pass. Exercise every
   source and applicable row of seed/omc/contracts/contracts.cases plus observable stdout-before-trap
   probes; retain function-mode exclusions explicitly. Replace scoped-refusal test scaffolding only
   when the real differential and an enforcement-removal mutant pass. No unchecked fact or new op.
2. Float conversion: candidate removes only the wrong float-source chk.conv; integer narrowing stays
   checked. 160 new edge cases and the full existing convert_sat.om are prepared. Two complete runs
   found input-literal error 8 rather than a semantic mismatch on the admitted cases. Large inputs
   now use Wolfram-verified power-of-two constructions within fparse mantissa limits, but those final
   spellings are NOT_RUN. Do not claim the candidate READY until all cases and negative controls pass.
3. Host lowering: ng-front-host and ng-front-hostwords-99 (below) lower all 99 host words. Function-mode units, the data gaps,
   remaining intrinsics and hygiene words remain not lowered or unproven as itemized above.

## ng-groups-4 (2026-11-10, branch ham/ng-front-groups-4)

Two groups lowered, IMPLEMENTED and host-EXERCISED by gate-front-ir only (no QUALIFIED claim):

- Mixed-type shifts. omc admits `shl`/`shr` whose integer value and amount have different types and
  compares the amount's 64-bit register (sign- or zero-extended by its type) unsigned with the value's
  width (`bo_schk`, trap 7). `fe_lsham` emits `conv` to u64, `lt` the width, `chk.true 7`, then `conv` to
  the value's type (exact below the width); the existing checks of `fe_lbop` follow (signed `shl` keeps
  `chk.shl` trap 1). Run cases `sh_mix` (ten type pairs), `sh_mix_wrap` (uchar by ulong 256: 107, never
  a wrapped shift by 0), `sh_mix_neg` (ulong by int -1: 107), `sh_mix_width` (uint by 31 and 32: 107),
  `sh_mix_sovf` (int 2 by uchar 30: 101). A rotate keeps one type (omc error 7, refuse case `rot_mix`).
  A bool or float amount stays not lowered (exit 64, `cases-lower-scope.txt`).
- fma. ΩIR `fma` (46), one rounding, three operands of one float type; `fma_mix` prints f64 and f32
  results whose fused and unfused values differ. omc's refusals stay (`fma_lit` 11, `fma_types` 7).

Still not lowered from these rows at ng-groups-4: fmin and fmax (IR.md min/max then said a NaN operand
gives the other, while OMEGESE and omc follow FMINNM/FMAXNM). Lowered since by ng-front-groups-6 (below).

## ng-front-host (2026-11-10, branch ham/ng-front-host)

All 94 host words of `seed/ng/hostwords.tsv` lower (IMPLEMENTED, host-EXERCISED by gate-front-ir and
gate-front only, no QUALIFIED claim); execenv and prlimit pass the check pass as omc does (gate-front,
`cases-host.txt`, including their `om2 diag` site records). Under ngrun, 39 of the 94 host programs give
omc's exit and stdout; for the other 55 ngrun refuses the word by class (IR.md s7.11) after ngcheck accepts
the lowered ΩIR, so their behavior is NOT_RUN: process 11, limits 1, device 17, network 15, outside
scratch 9, nondeterministic 1, unsafe filesystem 1. README section "Host words" has the lowering rules.

## ng-front-groups-6 (2026-11-10, branch ham/ng-front-groups-6)

fmin and fmax lower to ΩIR min/max (IMPLEMENTED, host-EXERCISED by gate-front-ir only). The IR.md rule
they needed (OMEGESE FMINNM/FMAXNM) and ngrun's rn_fmm arrive with ngrun-hostwords-5 (d5dba5bb), under
this head. Case cases/fmm_mix.om, expected bytes in cases/groups6.expect; lsc_fmin and lsc_fmax moved
from the lower-scope list to run cases.

## ng-front-groups-7 (2026-11-10, branch ham/ng-front-groups-7)

qty lowers as u64 with checked add/sub/mul (IMPLEMENTED, host-EXERCISED by gate-front-ir and gate-front
only). All 77 units of tests/quantity: 38 run with omc's exit and stdout under ngrun, 39 refused with
omc's code and stderr. A qty shift amount (`shl ulong 1 q`, which omc admits) lowers like a ulong amount
(factory bay 12 review fix; before it, ng exit 64): cases/qty_shamt.om.

## ng-front-groups-8 (2026-11-10, branch ham/ng-front-groups-8)

Data edges (IMPLEMENTED, host-EXERCISED by gate-front-ir and gate-front only): sized array parameters as
SLICEs of their declared access (texts reach sized view parameters), OM-2 `fresh` on edit parameters, empty
texts (empty slice of a one-byte global), bool constants. Ported from NgFrontFull's uncommitted data work
(preserved as omega-mv ham/ng-front-data-wip 1323c6e1; its qty and min/max parts are groups 7 and 6).
Still not lowered: struct, layout, field, at, little, big, sizeof, offsetof; abstract, ops, seal, open, holds;
out and export (function mode); contracts (fail closed).

## ng-front-hostwords-99 (2026-11-10, branch ham/ng-front-hostwords-99)

The scheduler words of omc f4fa7951 (Radicle main c106bae0): cpuset 236, cpuget 237, cpunow 238, setprio 239,
getprio 240 (IMPLEMENTED, host-EXERCISED by gate-front-ir, gate-front and gate-ir only). hostwords.tsv and
ngcheck have 99 rows (class `sched`); host-audit's closed id set ends at 240 (HOSTTABLE rows=99
differences=0). ngcheck accepts each lowered program; ngrun refuses cpuset, cpuget, setprio and getprio as
115 and cpunow as 120, so their behavior under ngrun is NOT_RUN. Refusals: cpuget on a text (20), a long pid (7).

## Executable-contract and data lowering

The dated sections above preserve earlier refusal boundaries. The current lowerer
executes checked function and loop prefixes, and lowers nominal types, structs and
layouts. See [README.md](README.md) for ordering and release policy. The canonical
compiler contract manifest feeds the differential gate directly. Function mode
remains separate work. Runtime-pool lowering is described below.

## Nominal, struct and layout lowering: current gate coverage

The implementation and its regression cases are part of this source. This describes
the checks, not hardware qualification. The authoritative case list is
[cases-front-ir.txt](cases-front-ir.txt), including the `nom-*` rows; derive counts
from that file rather than treating historical counts above as current.

The gate exercises:

- Canonical nominal, layout, struct, float-struct, size and long-name cases, with
  accepted programs executed and refusals compared by exit and diagnostic bytes.
  Function-mode units without `main` remain outside lowering scope.
- Struct units whose `main` returns uint, ulong or long through wrapped copies
  `cases/nom_tN.om`. [nom-wrap.sh](cases/nom-wrap.sh) regenerates and checks them;
  `main to int` is the lowered entry signature.
- Evaluation order and bounds: index before value, index traps before value
  overflow, field-cell boundaries, all scalar widths, untouched neighbouring
  fields, layout byte order and short-buffer refusals, and operand ordering before
  retained nominal checks.
- Boolean field storage through [nom_struct_bool.om](cases/nom_struct_bool.om).
  The compiler load/store and NG boolean-cell conversions are fixed; the prior
  SIGILL and invalid numeric-conversion behavior is covered by regressions.
- Deliberately wrong field offsets, bounds, layout byte order and nominal checks
  in [gate-front-ir.om](gate-front-ir.om). A partial case run is not a complete gate.

Release evidence must retain the complete `FRONTIRGATE PASS` result and its source
and compiler identities, alongside the separate check-parity gate.

## Runtime pools

The front end accepts `global NAME T *` for the ten native numeric types and lowers growth, length,
element access and byte I/O to the descriptor-based operations in [IR.md](../IR.md).
`cases/pool_runtime.om` and `seed/omc/omc.om` are ordinary check-parity cases now; their former
scope exclusions are removed. Existing x86/EFI and IR v1 scope exclusions remain.

The lowering manifest reuses the canonical pool cases for growth, bounds, moving storage,
contracts, overflow and byte I/O. `pool-widths-order.om` covers all ten widths, multiple pools,
nested growth and store operand order. `pool-fd-policy.om` covers the interpreter's existing
descriptor restrictions. The IR and native gates separately cover malformed inputs, optimization,
both register-save modes and deliberate pool implementation faults.

These fixtures define coverage, not a claim that every input or target is qualified. Release receipts
must include complete gate results. The interpreter has a 16 MiB live-storage budget, Mach-O pool
operations remain unsupported, and function mode remains separate work.
