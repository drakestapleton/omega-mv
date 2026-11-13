# Run-time pools: a global whose length is set while the program runs

Status: landing 1 (the omc-only words of section 6, gates 1-11 of section 7 and the server case of
section 11) IMPLEMENTED in `seed/omc/omc.om`, gate `seed/omc/gate-pools.sh`, OMEGESE 9.15. Landing 2
(om4 and the growing compiler arena, gates 12-14) IMPLEMENTED: om4 (`seed/rung4/om4.s`) knows `global
NAME T *`, `get`/`put`/`len` on a pool and `r = enlarge P n`, byte for byte as omc; omc's arena `a_ar` is a
run-time pool grown by `a_need` (doubling, `a_grow`); gates `seed/rung4/gate4.sh` (pool cases), gate5,
`seed/omc/gate-nocaps.sh` section 3, `gate12.sh`, `gate-usage.sh` (absolute words; its mutant control is
a_need's doubling made +512 entries, see section 7 item 14); first user (section 11) compiled and run.
ng-front refuses `global NAME T *` as a scope form (exit 64; the ng lane, NgNoCaps2), so
`seed/omc/omc.om` is a declared `scope 0` row of `seed/ng/front/gate-front.om` (section 6). (Historical state of 2026-11-11; section 12 supersedes the two NG pool scope exclusions.) Amended
2026-11-11 (section 6, "The memory ceiling"): the growing arena refuses past a caller-stated real-memory
ceiling, `OMC_MEMORY_MAX`. Revision 2 takes in the
independent design review (consult-codex, 2026-11-11, findings B1-B2, S1-S8, N1-N4; recorded in section
10). Implementation notes (landing 1): `enlarge` is keyword id 244 (above ng's 241..243); a host refusal
returns the host's negative errno, in practice -12 (ENOMEM), the only refusal these mmap and mremap calls can
reach by construction;
the element types are those `global` takes, f32 and f64 included (they use the array path unchanged);
the keyword changes no manifest-c2 row, so section 3.2's manifest-c2 delta has no rows and no file. Section 7
item 14's mutant control is amended there (2026-11-11).

Authority: decision 3 in `~/handoffs/yourtrained-cortex/briefs/decisions-20261111.md`. The lead took it
under Drake's delegation of 2026-11-11 ("Do whatever you think is best ... for longterm ... Lift all of
my prior restrictions"): run-time memory growth, in its smallest form. That is "a region whose size is
known at run time, obtained from the host as zero pages, bounds-checked like every array, no `free`,
no general allocator". Tracked as omega-mv #793 (RM4) and #795 (RM6). The change that lands this text
records the delegated decision in `docs/ROADMAP-1.0.md` RM4 (its Decision paragraph); Drake can reverse it.

## 1. Why

A program can only own memory whose size is written in its text: `global NAME T N` (a fixed N, at most
16777216 elements, at most 1 GiB in all; OMEGESE 9.4) and `new` (4 MiB per function). A program whose
working set depends on its input has to guess a size and then refuse past it. The seeded compiler is the
example. Since 2026-11-11 its tables live in one static arena of 16777216 words (OMEGESE 9.6). "Arena
full" (error 14) is the last capacity it has that grows with the input, and it is not a machine boundary:
it exists only because there is no run-time growth. (omc's other error-14 limits are per-construct
language rules listed in OMEGESE 9.6, the value-nesting bound of its own stack, and the program-image bound
of the branch reach.)

## 2. What exists, and why it is not enough

`mapnew -1 0 BYTES 3 34` (`seed/host/MAPPING.md`) already maps private anonymous zero pages, in up to 128
owned slots. A mapping is reachable only through copy words (`mapread`, `mapwrite`) and single fenced 4-
or 8-byte accesses (`mapget`, `mapset`, each with DSB SY or MFENCE: device-register semantics). No
ordinary Omega array can live in one. `seed/rung4/om4.s` has none of these words.

## 3. The language addition (omc, program mode, AArch64 Linux only in this slice)

1. **Declaration.** `global NAME T *` declares a run-time pool of element type T (uchar .. long, f32 and
   f64: the types `global` takes; `bool` stays error 9, as `elemtype` gives for every bool array today). Its length is 0 when the program
   starts. Like every global it is never passed as an argument and never sliced with `part` (error 19).
   Function mode refuses it with error 9, IR mode with error 9, and any `target` other than the default
   with error 25.
2. **Growth.** `r = enlarge NAME n`, with n a ulong and r a long (error 7 otherwise), allowed only as the
   whole of an assignment (error 9 otherwise) but anywhere in a function, blocks included. It is error 7
   on any name that is not a run-time pool. Results:
   - n <= `len NAME`: r = 0 and nothing changes. `enlarge` means "at least n"; it never shrinks.
   - n > `len NAME`: NAME then has n elements. The first `len NAME` keep their values and the rest are 0.
     r = 0.
   - n times the element size overflows 2^63: r = -22 (EINVAL) and NAME is unchanged. The kernel never
     sees an invalid request, so -22 always means the overflow.
   - The host refuses (mmap or mremap returns -12 ENOMEM under RLIMIT_AS or vm.overcommit_memory=2):
     r = -12 and NAME is unchanged. Note: under a cgroup memory limit (`memory.max`) a private anonymous
     mapping is not refused. Pages are charged when they are first touched, and past the limit the
     kernel's OOM killer ends the process (SIGKILL). That is physical exhaustion. A program's static
     `.bss` behaves the same way today; it is not a new behaviour and not a result `enlarge` can give
     (S2).
   - The keyword is `enlarge`: zero uses as an identifier in the tracked corpus (`git grep -nw enlarge --
     '*.om' '*.omegese'`, 2026-11-11). `grow` has 9 uses, among them `fn grow` in s3s4 fixtures, so it
     would change their C1 verdict (S3). Adding the keyword is still a C1 language decision. It is
     recorded as a manifest-c2 delta (om2 spec section 0), and a corpus scan in the gate checks that no
     tracked unit names `enlarge`.
3. **Length.** `len NAME` is the current length, a run-time ulong. It is never folded.

`get NAME i` and `put NAME i v` behave as for any array and are checked against the current length: an
index at or past it traps 3. A number index is checked at run time too, because the length is not known
at compile time (no error 21, no check elimination), exactly as for an index into an unsized view (spec
section 6). `read fd NAME off n` and `write fd NAME off n` take the pool with the same slice check
against the current length. Every other host word that takes an array (the device and mapping words
`devctl`, `devcall`, `vfioctl`, `uvmctl`, `mapread`, `mapwrite`, `vfioirq`, and the rest) refuses a
pool with error 7 in this slice.

There is no `free`, no shrinking, and no way to give memory back by hand (decision 24 stands).

## 4. Representation and lowering in omc

**A distinct name kind.** A run-time pool is its own name kind (kind 10, "run-time pool"), not kind 4
with length 0. Length 0 already means "unsized view" to `unsz` (omc.om `unsz`), and that would route a
pool through count registers that do not exist (B2b). omc.om dispatches on kind with ordered tests, and
10 sorts above both the struct threshold (`ge k 6`: kinds 6..8 are structs, 9 a constant) and the global
threshold (`ge kind 4`). So the rule is: **at every ordered kind test, the kind-10 branch is written first.**
The sites (omc.om at 3537baad; line numbers approximate, they move with each landing):

| Site (omc.om) | Kind 10 |
|---|---|
| `unsz` (301), `elemaddr` (6331) | own path: slot load, run-time compare, never a constant index check (no error 21) |
| rdval `get` (9901; today `ge k 6` sends it to the struct-field reader vt_fget) | kind-10 test first: the pool path |
| rdval `len` (9919; today `ge k 6` gives error 7) | kind-10 test first: a run-time load of the slot's length, never `vdone 3` |
| `s_put` (10630; today `ge k 6` sends it to s_putf) | kind-10 test first: the pool path |
| `s_global` / `pinset` / `pinlo` / `eof_prog` | never pinned: no X18..X26 register holds a pool base or length (B2a) |
| `arrarg` (6395), `arrpart` (6452) | kind-10 test before `ge k 6` (which gives 7): error 19, as for any global |
| the struct-argument reader (14549; `if lt k 6 fail 7` lets 10 through) | error 7 for kind 10 |
| `vs_arr` (6889, the read/write array path; `ge k 6` gives 7) | kind-10 test first: `read`/`write` take a pool |
| `harray`, `basearg` (6201), `vs_chk`, `vs_call` | `read`/`write`: slot loaded after every operand (below); any other host word: error 7 |
| `xhb` (16455), `xelem` (18614, 18695), x86 and x86efi targets | error 25 |
| contract folding (OMEGESE 12, "Purity, proofs and failure") | `len` of a pool is never constant: `requires eq len P 0` is checked at run time and reported `kept rule=runtime` in om2 diag, never `erased rule=constant-true` |
| unroll and inline folding, check elimination (om2 spec 4) | a pool index is never constant-checked |
| IR mode (`ir_*`) | error 9 |

Gate 10 (section 7) also covers "a pool passed as a struct argument (7)".

**Storage.** Each pool has a hidden 16-byte slot in the program's global pool area, zero at start: the
base address, then the length in elements. Capacity is not stored: it is the length's bytes rounded up to
the page (4096) at every moment, because a growth that fits only raises the length and every mapping was
rounded from the length it was made for. The helper recomputes it. Access: LDP base and length, compare
the index (CMP, B.HS to trap 3), then load or store. LDP needs two allocated registers, so an expression
dense with pool accesses reaches the 16-register limit (error 12) sooner (N3).

**The soundness rule (B1).** A grow moves the pool. Values nest calls (`put P i (f x)`, `get P (f x)`,
`write 1 P 0 (f x)`, an inlined body), so a grow can run between the start and the end of one access. The
move is unobservable only because of this rule, which the lowering must keep and a gate checks:

> In every lowering that touches a pool (get, put, len, read, write), the slot is loaded after the last
> operand of that access has been evaluated, and the base is used only within that access. A length
> checked earlier stays valid, because no word ever shrinks a pool.

Today's codegen already loads an array base after the operands: `s_put` reads the index, then the value,
then calls `elemaddr`; `vt_get` calls `elemaddr` after the index; host words check with `harray`/`vs_chk`
and load the base after `save`. Kind 10 must follow that order. The rule holds while omc has no
shared-memory threads and no signal handlers: omc emits no thread creation and installs no signal handler,
its process words (`execprog` 124, `execpure` 198, `execenv` 233) replace the address space, and `fork`
(keyword 107) is clone with SIGCHLD only (no CLONE_VM): the child owns a private copy-on-write copy of the
slot and of the MAP_PRIVATE pool, so a grow in either process never moves the other's pool. If FR-6
threads or signal handlers ever land, pools must move to a non-moving form (reserve-then-commit, below),
because a stale base in another thread corrupts silently (N1).

**Growth (S1).** The first growth from length 0 is `mmap(0, bytes, PROT_READ|PROT_WRITE,
MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)` (syscall 222). A later growth that fits in the capacity already mapped
(whole pages; the Spark's page size is 4096, measured with `getconf PAGESIZE`) only stores the new
length: the bytes past the old length are still zero, because they were never written (a pool never
shrinks, and nothing writes past its length). A growth past the capacity is `mremap(old, oldbytes,
newbytes, MREMAP_MAYMOVE)` (syscall 216). It moves page tables, not data, so untouched pages stay
unpopulated, there is no old+new copy peak, and on failure the old mapping is intact and the result is
-12. Byte counts are rounded up to 4096. A kernel with larger pages rounds further, which is still correct.

The whole growth is emitted as one fixed helper per unit (`omc_enlarge`: X0 the slot address, X1 the
requested count, X2 the log2 of the element size; result in X0), called with BL from every `enlarge`
site. A unit that does not use pools gets neither the helper nor slots, and its code is byte-identical to
today's.

**Alternatives considered (N2).** Reserve-then-commit (a PROT_NONE reservation, then mprotect to grow in
place) never moves and is the strongest shape for soundness. But the whole reservation counts toward
RLIMIT_AS (MAP_NORESERVE affects only commit accounting), so it fails under omc's 256 MiB salvage limit,
and a per-pool reservation size would be a new fixed number. A view over `mapnew` is bigger (handles and
generations, `mapdrop`, use-after-release traps, 128 slots) and still cannot grow without a copy.
Reserve-then-commit is recorded as the successor shape, tied to FR-6.

## 5. Checker, traps and contracts

- Traps: none new. An index out of range is trap 3, as for every array. Running out of memory is not a
  trap: it is `enlarge`'s negative result, which the program must handle like any host-call result.
- Contracts: `len NAME` of a pool is a run-time value, checked at run time, and never proved constant.
- checker2, the C path and IR mode do not see pools (error 9 in IR mode). Pools are an omc-only (seeded)
  addition of OMEGESE section 9, like the host words.
- No hidden allocation: no existing word allocates (RM4's condition). Only `enlarge` asks the host for
  memory, and its result says what happened.

## 6. What it costs the seed chain and om4 (S5), and the staging

`seed/omc/omc.om` must stay inside om4's language (spec C3), and gate5 (b) requires om4 and omc to build
the same omc from omc.om, byte for byte. omc.om touches its arena only through `get`, `put` and `len` on
`a_ar`. Its I/O goes through the `a_wb` staging buffer, never `read`/`write` on the arena. So om4 needs
only:

- `global NAME T *` in S_GLOBAL (kind 10, the slot);
- the kind-10 path in ELEMADDR (slot load, register or number index, CMP, B.HS trap 3);
- `len NAME` of a pool;
- `r = enlarge NAME n` as a BL to the fixed helper, emitted once per unit when used, from a word table, so
  that byte identity with omc holds by construction.

om4 refuses `read`/`write` on pools and every other pool word with its own error. The units that only
omc accepts are listed in `seed/omc/tests/om4-superset.tsv`, as gate5 section 3 already allows. Estimate:
100 to 200 lines of `om4.s` (MODELED, not measured), `mk4.sh` to rebuild `om4.bin`, new gate4 cases
(accept, out of range, host refusal, a grow inside a block), the gate4 section 2 audit (mismatch 0), and
nextfuzz coverage of the new words. `evidence/SEED-0/rung4/` is not rewritten: gate4 reports the
receipt as differing, as it did for the function-table change 646ed1ec.

Staging, two landings:

1. **omc-only words** (omc.om unchanged in what it uses; the precedent is OMEGESE 9.7 and 9.8, which
   needed no om4 change), with all the gates of section 7 except the arena switch.
2. **om4 learns the minimal subset**, then omc.om declares `global a_ar ulong *` and enlarges it in
   `a_need` (doubling). The static 128 MiB arena and its RLIMIT_AS bound go away, and omc's image shrinks
   by 128 MiB of `.bss`. The new boundary is the machine's. A refused `enlarge` is error 14 with the
   omc-use record (`full=1`, now meaning "the host refused"). Under a cgroup memory limit the host never
   refuses; the memory ceiling below turns that case into the same error 14.

**The memory ceiling (amendment, 2026-11-11; Main: "refusals stay defined").** Reason, measured on the Spark
with the landing-2 compiler (omc 59d7cb5e) and the 87,019,650-byte first-user unit (section 11), which peaks
at 557,184 KiB resident (GNU time; cgroup memory.peak 573,169,664 bytes, of which anon 570,486,784, kernel
1,826,816, page tables 1,658,880):
- under `prlimit --as=268435456` it is a clean error 14 with `full=1` in about 1 s: RLIMIT_AS makes mremap
  fail, and the arena's growth is refused;
- under `systemd-run --user --scope -p MemoryMax=536870912 -p MemorySwapMax=0` it is not refused: pages are
  charged when they are touched, so mmap and mremap never fail inside a cgroup. The kernel reclaimed and
  refaulted omc's own file pages (D state; at 105 s memory.events max=333531, oom_kill=0,
  workingset_refault_file 10869949, pgmajfault 346042) for about 175 s and then the memcg OOM killer ended
  it (SIGKILL, exit 137; 1 min 2.9 s of CPU, no output). The design review's run of the same case was killed
  after 2.36 s: the outcome is an OOM kill either way, after a delay that varies;
- with MemoryMax=1073741824 it compiles and the round trip `cmp`s.

RLIMIT_AS bounds address space, not memory, and decision 2 asks the sandboxes to move to real-memory limits
(cgroup `memory.max`), where the growing arena would be killed or stalled rather than refused. So:

- **The rule.** When a real-memory ceiling C (bytes) is known, every growth keeps the budget H + M + R <= C:
  H the most arena bytes ever handed out (the pages above them were never touched; a compaction lowers the
  words handed out, not the pages it touched), M the margin on H, and R the output reserve, the capacities of
  the artifact's region and of the om2 diag site records' region, which omc writes after the artifact (written
  to a file, both are page cache charged to the same cgroup, dirty until written back). The artifact and the
  site records never pass their regions, so once every growth kept the budget, writing them keeps it: the
  check before the write (H, M, the artifact and the site records) is a guard that does not refuse. Under a
  ceiling, a growth that would move a group to the top past H compacts and grows it in place instead, and a
  group grows to its doubling or not at all: the words handed out then follow the same course for every C,
  so the refusal is monotonic in C (a unit refused at C is refused at every lower C). A growth that does not
  fit is refused as a host refusal is, and the unit is error 14 with the omc-use record, `full=1`. Measured
  with stdout on an ext4 file before this rule (review of 04e6492f): counting only the artifact written so
  far, MemoryMax at the compile's peak + 4 MiB and + 1 MiB was still OOM-killed in about 2.4 s while the
  artifact was written, an om2 diag unit was killed while its site records were written, and the refusal had
  bands (the page unit compiled at 504 and 512 MiB, was refused at 520 to 536, compiled from 544). With it:
  over 384 .. 640 MiB the page unit is refused below 512 MiB and compiles from 512 MiB, and the om2 diag unit
  of 1,200,000 lines below 496 MiB and from 496 MiB, every run with oom_kill 0. The record gains one
  last field, `ceiling=C` (0 when none is known), after the groups; readers take fields by name (gate-usage
  treats it as a group holding 0 words, which no threshold trips). Without a known ceiling the arena grows
  until the host refuses, as designed above.
- **The margin.** M = 16 MiB + (arena bytes) / 128. What is resident beyond the arena's touched words is
  omc's image (read/write part at most 11,196,912 bytes, `memsz` 0xaad9f0, the 8 MiB stack pool included;
  resident on a tiny unit about 0.4 to 0.6 MiB), its file (750,532 bytes), and kernel memory charged to the
  cgroup, mostly page tables: measured 1,826,816 bytes on the first-user unit, 1,474,560 on 1,500,000
  globals and 548,864 on a 64 MiB input, which is 1/441, 1/546 and 1/183 of their final arena bytes, so
  arena / 128 bounds it. The arena's touched words are at most its length, and after a doubling usually
  far less (first-user unit: 570 MB resident against an arena of 805,371,904 bytes). The fixed 16 MiB covers
  the image and text with about 4 MiB left for reclaim of clean page cache; measured: with MemoryMax set
  1 MiB, 4 MiB, 8 MiB and 20 MiB above that unit's own peak and stdout on /dev/null, it compiles in 2.1 to 2.7 s
  (2.09 s with no limit), oom_kill 0 (with stdout on a file the artifact counts too: "The rule"). A file on omc's stdin is page cache charged to the cgroup that read it; it is clean and
  reclaimable and does not count toward the rule.
- **Why the environment and not a lead line.** A lead line (as `usage`, `om2 diag`, read by chk_mode) would
  cost om4 nothing, but omc reads the whole input into the arena (region 0, a_rdin) before it reads any line,
  and the input can itself be the largest region (gate 13's 512 MiB input): the ceiling must be known before
  the input is read, which a line of that input cannot do.
- **The explicit form (this landing).** The environment variable `OMC_MEMORY_MAX`: decimal bytes, 1 to 19
  digits, no sign or spaces, read once when omc starts, before the input, with `envcnt` and `envread`
  (OMEGESE 10, omc host words); the first entry named `OMC_MEMORY_MAX` wins. Absent, empty or `0`: no ceiling.
  Anything else (a non-digit, a sign or space, more than 19 digits, or 2^63 and above) is error 26 on line 0
  before any input is read, so a caller's typo is loud rather than an unbounded compile. Each entry is read
  whole into a buffer of 131072 bytes (Linux keeps an entry below that, MAX_ARG_STRLEN); one that does not fit
  is error 26 too. Code 26 was unused;
  it becomes an io-class row of `seed/omc/error-codes.reg` like 1 and 2 (the compiler's environment, not a
  language input; gate15 case), and row 14's meaning names the ceiling. A ceiling too small for the first
  room is error 14 `full=1` at the first growth. omc.om must stay inside om4's language (spec C3), so om4
  learns `envcnt` and `envread` with words byte-identical to omc's in an OM-1 unit, as it learned the pool
  subset (omc's lowering is about 90 lines of omc.om, about 60 machine words with its argument and range
  checks; estimate 150 to 300 lines of `om4.s`, MODELED). Units compile to the same bytes with or without
  the variable; it changes only whether a large one is refused.
- **The automatic form (successor, not now).** Reading `/proc/self/cgroup`, then `memory.max` and
  `memory.swap.max` under `/sys/fs/cgroup`, would find the ceiling without the caller. It needs `fopen` and
  `read` on a path in omc.om, so om4 must also learn `fopen`; sandboxes may hide `/proc` or the cgroup files
  (bwrap `--unshare-all` without a cgroup mount), so the explicit form stays the contract and the automatic
  one only fills in when the variable is absent.
- **The sandboxes.** The interplane-forge salvage compile (`prlimit --as=268435456`), the omega-mcp compile
  (`--as=536870912`) and forged (`--as=4294967296`) keep a clean error 14 from RLIMIT_AS with nothing to
  change. bench/inference_cost (`driver.sh` `mem_scope`, MemoryMax 536870912 with swap 0 since 15760b50) is
  the case this fixes: its sandboxed compiles run under `bwrap --clearenv`, so the driver must add
  `--setenv OMC_MEMORY_MAX "$MEM_MAX"` (minus whatever else shares the scope) to get error 14 in place of a
  timeout or a kill (its compile timeout is 10 s, `driver.sh`). Every caller that clears the environment (`bwrap --clearenv`, `execenv`, `execpure`)
  passes the variable explicitly; each owner makes that change.

Historical landing-2 consumer handling (superseded for NG pools by section 12): `seed/ng/front/cases-front.txt` runs
`seed/omc/omc.om` as an ng parity case (`gate-front.om`), so a pool in omc.om needs ng-front to treat
`global NAME T *` as a scope form (exit 64; the ng lane, NgNoCaps2, landed it with `seed/ng/front/cases/pool_runtime.om`). Landing 2 carries the row
`seed/omc/omc.om scope 0` in `seed/ng/front/declared.txt`.
A second consumer is ng's no-caps gate: `seed/ng/tests/nocaps/gate.om` (unit 0, gn_uin) feeds `seed/omc/omc.om` to
ng front-check in usage mode as a large real unit, which ng refuses as a scope form (exit 64) once omc.om
holds a pool; the ng lane (NgNoCaps2) chooses between a pinned pre-pool omc.om as that unit and accepting 64.
(Current gate: `gn_uin` uses `seed/node/journal-gate.om` and ng itself for the usage alarm. The earlier omc-based description is historical.)

## 7. Gates, all with negative controls (S7)

1. **Growth and contents.** A pool enlarged from 0 to 1, 4096, 2^20 and 2^27 elements (a loop over more
   than 1000000 elements needs `bound`, OMEGESE 63-67). Values written and read back; old values kept;
   new elements zero. A pool past the 16777216-element limit of sized pools.
2. **Range.** Index = length traps 3 (exit 103) with no write past it; length + 1 is in range after a
   grow; a number index past the length traps 3 at run time. Mutant: the length compare removed, caught.
3. **Stale base (B1).** `enlarge` inside f, where f is called from the value of `put P i (f)`, from the
   index of `get P (f)`, and from the count of `write 1 P 0 (f)` and `read`. Plain and as an OM-2 inline
   body, repeated until mremap has moved the region and its address has been reused. The results must
   be right. Mutant: the slot loaded before the operands, caught.
4. **Pinning (B2a).** An OM-2 unit whose first global is a pool, with sized globals after it; objdump shows
   no X18..X26 base for the pool. Mutant: the pool pinned, caught.
5. **Contracts (B2c).** `requires eq len P 0` and `invariant le i len P` are reported `kept rule=runtime` in om2 diag
   and evaluated at run time; a constant index under unroll and inline keeps its run-time check.
6. **Mutants (RM4).** The n-below-length case, the overflow check, the slot not updated after a failure,
   capacity and length swapped: each caught.
7. **Fuzz differential (RM4).** A seeded random sequence of enlarge/get/put/len against an independent
   model (a Python list), compared at every step.
8. **Host refusal (S2).** Under `prlimit --as` set low, `enlarge` returns -12 and the program goes on
   with the pool unchanged (its own exit status, never a trap); the overflow case gives -22. Under
   `systemd-run --user -p MemoryMax=64M` a program that touches 128 MiB is recorded with its actual
   result (expected: killed, 137), so the documented behaviour cannot drift.
9. **Untouched pages (S1).** A pool enlarged to 2 GiB with one page touched shows VmRSS of about one page
   (`/proc/self/status`).
10. **Refusals (S4).** Function mode (9), IR mode (9), `target x86linux` (25), passing or slicing a pool
    (19), `enlarge` not as a whole assignment (9), `enlarge` on a sized global, a local or a view (7), a
    `bool` pool (9), n not ulong or r not long (7), a pool given to a device or mapping word (7).
11. **Byte identity.** Every tracked `.om` that compiled before compiles to the same bytes, except the
    files that name `enlarge`, listed by name (none on 2026-11-11). The corpus scan for `enlarge` is part
    of the gate.
12. **Seed chain (landing 2).** om4 = omc on the new words (gate5); the fixpoint holds; gate4 cases and the
    audit pass.
13. **The arena (landing 2).** gate-nocaps units far past 128 MiB (a 512 MiB input) compile and run. Under
    `prlimit --as` set too low the result is error 14 with `full=1`. The forged salvage compile, under
    `prlimit --as=268435456`, still passes every unit it passes today. The memory ceiling (section 6): under
    `systemd-run --user --scope -p MemoryMax=C -p MemorySwapMax=0` with `OMC_MEMORY_MAX=C` and stdout on a
    real file, the first-user unit at C = 256 MiB and 448 MiB is error 14 `full=1` with `ceiling=C`,
    oom_kill 0 in memory.events and a wall time under 30 s (the unconstrained compile takes about 2.5 s);
    at a sufficient C it compiles and round-trips (`cmp`); over C = 384 .. 640 MiB every result is 0 or 14 with
    oom_kill 0 and none is 14 above a 0; an om2 diag unit with stderr on a file is 0 or 14 with oom_kill 0; a
    capped doubling that still fits compiles (a
    unit whose doubled arena would pass C, at a C between its need and the doubled size); the `ceiling=`
    field parses in gate-usage; the malformed values (a non-digit, a sign, a leading or trailing space, 20 digits, 2^63,
    an entry too long to read whole) are error 26 on line 0, and empty and 0 mean no ceiling. Mutants: the
    ceiling ignored, caught (killed, or past the 30 s bound); the margin dropped, caught as a differential
    control (at some C omc refuses and the mutant compiles; measured, the mutant is not killed there either,
    because the kernel writes back and reclaims the artifact's pages). Without `systemd-run --user` those rows are NOT_RUN and
    the variable is still checked under `prlimit --as`: with `OMC_MEMORY_MAX` = C and `--as` far above it,
    the unit is error 14 whose record says `ceiling=C` and whose arena never passed the cap, so the ceiling,
    not mremap, refused it.
14. **The alarm, redefined (S6).** Once the arena grows to fit, "top / arena" is near 50 to 100 percent
    by construction. gate-usage then alarms on absolute words in use per group and in all, on compile
    time and on RSS, measured on the largest real units. Its mutant control is a table growth in `a_need`
    that never doubles (+512 words each time, `c = add c 512` in place of `c = shl c 1`): it must trip
    the RSS or absolute-words alarm, and its compile time is recorded. Amended 2026-11-11 (landing 1): the
    first form, the arena itself growing by +1 page instead of doubling, cannot trip any alarm, because
    the arena grows only when a group's doubling does not fit (about log2 of its size times per compile)
    and mremap copies no data; measured on the Spark, the in64m unit took 1.06 s against 1.26 s and
    forged, omc.om, cortex and omega-mcp were within 0.01 to 0.09 s with identical output, while the
    a_need mutant takes globals100k from 26 MB to 1.0 GB resident (0.07 to 0.53 s). omc's self-compile
    time and RSS before and after the switch are recorded (each arena access gains a slot load).

## 8. What #793 and #795 decided, and what they left open

The issue bodies are not readable: GitHub is frozen and hidden, and the Radicle copy has no issues.
`docs/ROADMAP-1.0.md` RM4 and RM6 link them and record:

- **RM4 / #793.** Open until a decision: keep decision 24, or replace it with a named model (the options
  are region/arena with whole-region release, or generation-checked handles `HALLOC/HGEN/HFREE`). Already
  decided as conditions on any model, and met here: exhaustion returns a status and never overruns; no
  existing word gains hidden allocation; use-after-release is refused or trapped (here no release is
  reachable by the program, so there is nothing to use after it); mutants that remove each check; a fuzz
  differential against an independent model (section 7, items 6 and 7). This design is the "region"
  option without release, the smallest form that lifts fixed sizing.
- **RM6 / #795.** Modules by digest. Its acceptance line "per-unit capacities chosen by measurement ...
  gated at their boundary (accept N, refuse N+1 with error 14)" is superseded by the no-caps rule
  (OMEGESE 9.6); this change amends that bullet in RM6. The rest of RM6 does not depend on this design.

## 9. What it does not add

No `free`, no shrinking, no general allocator, no objects, no pointers, no address arithmetic, no
pointer-typed values. No run-time-sized locals (`new` keeps a compile-time size). No change to sized
globals, to any existing word's code, to function mode, IR mode or x86. No garbage collection, no
reference counting, no aliasing. A run-time pool is a global whose length is a run-time value, and
nothing more.

Documents the landings update with it (S8): OMEGESE 9.4 ("no heap, no allocation call"; "no word turns
an array into an address" stays true) and 9.6 (the arena), the error-code registry rows, the `omc.om`
header notes, `docs/ROADMAP-1.0.md` RM4, and the omega-harness guides (omega-encoding, writing-omega),
which are sent to their owner.

## 10. Review record

Independent design review by consult-codex, 2026-11-11, of revision 1 (mmap + copy + munmap, keyword
`grow`, the kind unspecified). Its recommendation was "build after the listed changes". Taken in:

- B1: the soundness rule, with its gate and mutant.
- B2: a distinct kind and the list of sites.
- S1: mremap; no copy loop and no old+new peak.
- S2: the cgroup behaviour stated, with a measured gate.
- S3: the keyword `enlarge`, a scanned corpus and a C1 delta.
- S4: the edge cases and refusals specified.
- S5: om4's minimal subset, a fixed helper, and staging in two landings.
- S6: the alarm redefined in absolute terms.
- S7: the gates added.
- S8: the documents listed.
- N1-N4: recorded above.

Not measured in that review, and to be measured when building: the mremap and RLIMIT_AS behaviour, the
cgroup OOM behaviour, and RSS after a large enlarge.

Recheck of revision 2 (consult-claude, 2026-11-11, at e307a4e1): MERGE_AFTER_FIX. Fixed in this text:
- F1: the ordered kind tests and the missing sites.
- F2: the RM4 wording.
- F3: the slot is base and length, with capacity derived.
- F4: the contract citation.
- F5: the soundness facts about threads and signals.
- F6: "the last capacity that grows with the input".

F7 asked for the corpus scan. `git grep -nw enlarge -- '*.om' '*.omegese'` returns no lines (run before landing).

Final check of this text (consult-claude, at 7b816f20): MERGE_AFTER_FIX. Fixed:
- N1: a bool pool is error 9, as elemtype gives.
- N2: `fork` is clone with SIGCHLD only.
- N3: the om2 diag record words.
- N4: the program-image bound.
- N5: the decision's exact words.
- N6: RM4 says how the decision settled.
- N7: the RM6 per-unit-capacity bullet is amended.

## 11. First users, and programs that keep running

The first inputs waiting for this design, reported 2026-11-11:
- A 64 MiB page encoded by cortex's streaming encoder gives an 87.7 MB unit. omc refuses it cleanly with
  error 14 and a usage record (`namehash=131072/131072`, the arena full). It is the first real input that
  needs the growable arena (landing 2).
- omega-mcp's request path (512 KiB of source, a line of about 960 KiB, fixed buffers) and cortex's store
  capacities. Their owners list both as liftable only with pools.

So the pool form must serve a server unit that keeps running, not only a compiler that exits. As
designed, it does:
- `enlarge` may be called at any time, in any function, as often as needed.
- A pool holds its memory until the process ends, because there is no `free` (decision 24). A server
  should therefore size a pool to its high-water mark and reuse it, writing over it and tracking its own
  used length, rather than enlarging per request.
- A refusal is a status the server handles, for example by answering "too large" to that request and
  going on. It is never a trap.
- The gates of the first landing add a server-shaped case: a loop that serves requests of growing and
  shrinking size from one pool, enlarging only past its high-water mark, with RSS checked to stay at that
  mark.

## 12. NG runtime pools

NG represents each pool as a class 2 global whose type is the scalar element type, with six
token-ordered operations (111..116). See [the complete IR contract](../seed/ng/IR.md#713-run-time-pool-ops-111116).
No REF or SLICE exposes the storage. Each access resolves the descriptor and checks bounds after
its operands, preserving section 4's store order even when an operand grows a pool.

Linux AArch64 uses the canonical mmap/mremap growth helper. The reference interpreter stores pools
separately from frames while enforcing one 16 MiB live-storage budget; allocation refusal preserves
all existing contents. Mach-O pool ops are explicitly unsupported. Native support for other host
words is unchanged. Pool ops are host-only and have no GPU lowering.

`ngcheck` rejects illegal element types, pointer escape, kernel placement, argument types and token
use. Text tools preserve type-invalid inputs for independent validation; they reject unknown wire
classes. The front end removes its old pool scope exclusions, while existing x86/EFI and IR v1 scope
exclusions remain.

The IR, front-lowering and AArch64 gates contain the regression cases and negative controls.
The canonical pool source fixtures are reused for differential execution. Release evidence records
their results and source/compiler identities. Memory measurements can use an external /proc reader
when the native back end cannot yet lower the RSS fixture's `fopen`; that adaptation must be recorded.
