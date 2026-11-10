# CPU worker facilities

Status: DRAFT, ham/om-threads. Additive to OM-2 and the OM-3 draft. Not MERGED or DEPLOYED.

## Scheduler words

Program mode, AArch64 Linux and x86linux only. Function mode is error 9,
x86efi error 25, a contract expression error 30. Every result is long,
a successful kernel result or minus errno. No allocation or privilege change.

| word | operands | kernel operation |
|---|---|---|
| cpuset | pid int, A byte array, off ulong, n ulong | sched_setaffinity |
| cpuget | pid int, A writable byte array, off ulong, n ulong | sched_getaffinity |
| cpunow | none | getcpu, CPU result only |
| setprio | which int, who int, priority int | setpriority |
| getprio | which int, who int | getpriority, raw kernel value 20 minus nice |

The byte slices are checked before the syscall (trap 3). Affinity masks use
Linux bit numbering, low CPU first. A zero pid means the calling thread, not
all threads. cpuget returns the number of mask bytes copied, not zero.
The kernel rejects a mask with no permitted online CPU with -22. cpuget needs
a sufficiently large, machine-word-sized buffer. cpunow is a snapshot, not a
promise about subsequent scheduling unless the thread has one allowed CPU.
setprio retains ordinary Linux authorization checks; it does not bypass nice
limits. which 0 is PRIO_PROCESS, who 0 the calling thread. Higher nice reduces
priority. These words are effects, never contract predicates.

Syscall authority: Linux asm-generic/unistd.h and x86 syscall_64.tbl.
AArch64 numbers: 122,123,168,140,141. x86linux: 203,204,309,141,140.

## Reversible decision

Choose raw Linux scheduler operations and caller-owned buffers, not a hidden
worker runtime or allocator. Existing host words already use checked slices and
negative errno. Revert the additive host words and the benchmark caller to undo.
Thread design and its checked-sharing/lifecycle evidence will be a separate head.

## Gate

seed/host/affinity/sched.cases uses the existing Omega OM-2 conductor. It checks
inherited-mask selection, single-core observation, readback, invalid mask and
pid, out-of-bounds slice, priority read/set/readback and invalid which. Compiler
mutants replace setaffinity by getaffinity on both targets; invalid-mask check
must catch both. x86 runs are EMULATED, not native x86 qualification.

bench/omc_efficiency/run.om calls cpuset/setprio in its conductor child instead
of launching taskset/nice. Other children and the coordinator retain their
inherited scheduler state. Pool locking remains the launcher's responsibility.

The priority child independently reads /proc/thread-self/stat field 19. Offset checks
use off 9 with sentinels; AArch64 and x86 offset-removal mutants must fail at
fixture exit 14. Set/get syscall-swap mutants must fail at exit 3. The fixture
also pins the last inherited core and checks cpunow there (exit 17/18), so a
cpunow that ignores the getcpu result fails even when the first inherited core
is CPU 0; the AArch64 and x86 load-removal mutants must fail at exit 18. The
last-core pin runs on every pool shape (on a one-core pool the last core is the
first), so exit 18 holds on single-core pools too; only a one-core mask of CPU 0
cannot tell a constant 0 from getcpu, and there the mutant rows fail. Under a nice 19
pool setprio 0 0 19 is a no-op, so the priority child also asks for nice 18:
without CAP_SYS_NICE the result must be -13 with nice still 19, and where it is
allowed nice must read 18 and raw getprio 2 (exit 19 otherwise). The AArch64 and
x86 mutants that hardwire the setprio operand to 19 must fail at exit 19. Caller cases
compose the existing run.om helpers with only its main replaced: cpk1, runpk,
child and selfpin run unchanged, then a real conductor child checks its single
allowed core and priority. Invalid CPU 1024 is refused with exit 118.

## Constant provenance

WolframLanguageEvaluator query
`Table[{w,FromDigits[Reverse[ToCharacterCode[w]],256]},{w,{"cpuset","cpuget","cpunow","setprio","getprio"}}]`
returned `{cpuset,127979077595235}`, `{cpuget,127978876268643}`,
`{cpunow,131320478265443}`, `{setprio,31359662648747379}`,
`{getprio,31359662648747367}`. These are keyword encodings, not measurements.

## Coordinator build and compatibility

Build run.om with this head's seeded compiler, even when its BASE argument is
an older compiler. BASE and CAND still select the benchmark arms; they do not
select the compiler used to build the coordinator. This is an implementation
addendum to the frozen OMC-EFF-4 driver description, not a change to its rounds,
metrics, validity rules, affinity target or priority adjustment. The frozen
protocol files and historical receipts are left unchanged.

selfpin runs after child working-directory and stream setup, immediately before
execprog. It preserves the former nice -n 19 adjustment, including an inherited
negative nice: getprio gives raw = 20 minus nice, so setprio gets
min(19,39 minus raw). WolframLanguageEvaluator
`FullSimplify[20 - raw + 19 == 39 - raw]` returned True.
The coordinator and unrelated subprocesses keep their inherited scheduler state.

The priority oracle is /proc/thread-self/stat because the Linux word targets
the calling thread. On the Spark's x86 emulator probe, /proc/self/stat supplied
synthetic zero priority/nice fields while /proc/thread-self/stat reported
priority 39 and nice 19, consistent with raw getprio 1. The per-thread oracle
therefore preserves an independent kernel check on both targets instead of
accepting the emulator's synthetic process record. No priority check is skipped.
