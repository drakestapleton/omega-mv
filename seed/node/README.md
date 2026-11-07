# Omega Node shared-memory transport, epoch pool, worker supervision, scheduling and authority

This is the first implementation component of [Omega Node](https://github.com/aien-dev/omega-harness/issues/205).
It provides a bounded, single-publisher artifact log for trusted forked Omega
processes. Runtime consumers can share artifact storage and wake only interested
workers. The existing `seed/agent/agent.om` is the coding-agent consumer to evaluate
for integration; this change does not replace its model or tool dispatcher.

Four source fragments, concatenated in this order before one program with `fn main`:

| Fragment | Adds |
| --- | --- |
| `transport.om` | one arena: 64 immutable records, topic scan, eventfd hints, stop flag (#1055) |
| `pool.om` | K arenas reused by epoch, reader holds, fail-closed rollover (DRA-286) |
| `super.om` | forked workers, death detection, reaping, creator-loss detection, bounded stop (DRA-286) |
| `sched.om` | subscriptions, dependency wake-ups, bounded admission and review, job loss handling (DRA-287) |

The component is not yet connected to the live hive. Authority integration,
persistent recovery, a dashboard and a real model-backed coding workflow remain
implementation work (DRA-288 to DRA-292). The
[Linear project](https://linear.app/drake-stapleton/project/omega-node-shared-memory-hive-runtime-37058a1eac4b)
tracks that integration. This is a component contract, not a whole-system master plan.

## Build and check

Use a Linux AArch64 host and the existing approved seeded compiler. Record its
hash independently before rebuilding. The source baseline used here is
`7caba0c0094628b384abf8961a33bd95ae9412cc`, with `seed/out/omc` SHA-256
`5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df`.

`transport-gate.om` is the exact byte concatenation of `transport.om` followed by
`transport-test.om`. No separators, headers or substitutions are inserted. Verify
that correspondence before compiling, and stop if any command fails:

```sh
mkdir -p build/node
cat seed/node/transport.om seed/node/transport-test.om > build/node/composed.om
cmp build/node/composed.om seed/node/transport-gate.om
sha256sum seed/out/omc
seed/out/omc < seed/node/transport-gate.om > build/node/transport-gate
readelf -h build/node/transport-gate
chmod +x build/node/transport-gate
timeout 30 build/node/transport-gate
```

Expected: `PASS node transport`, exit 0. A failed compile, signal, timeout or trap
is not a passing refusal test. The test forks real OS processes, uses anonymous
shared mappings and eventfds, and opens no GPU, model endpoint or network socket.
Use a disposable checkout. The standard `crumb-verify`, `evidence-immutable` and
`zero-disk-secrets` gates also apply. The native seed gate remains required before
qualification; an emulated component pass does not replace it.

For an explicitly labelled emulated development check on x86, run the existing
AArch64 compiler and its accepted ELF output through `qemu-aarch64-static`:

```sh
qemu-aarch64-static seed/out/omc < seed/node/transport-gate.om > build/node/transport-gate
readelf -h build/node/transport-gate
chmod +x build/node/transport-gate
timeout 30 qemu-aarch64-static build/node/transport-gate
```

## Contract and ownership

`transport.om` is a source fragment. Concatenate it before one consumer containing
`fn main`. It adds no compiler word or hidden runtime dependency.

| Function | Contract |
| --- | --- |
| `node_new` | Positive mapping handle, or negative OS error. Call before fork. Records creator PID. |
| `node_publish h topics src n` | Creator only; copies up to 4096 bytes from a fixed 4096-byte view. Returns new version or negative refusal. Nonzero 64-bit topic mask. |
| `node_next h cursor topics` | Next matching version greater than cursor; zero if none currently published; negative refusal on invalid input. |
| `node_read h version dst` | Copies immutable bytes to a fixed 4096-byte destination; returns length. Bytes beyond that length are unchanged. |
| `node_stop h` | Creator sets a sticky stop flag. Does not itself wake blocked workers or cancel external effects. |
| `node_notify fd` | Adds a wake hint to one nonblocking eventfd; zero on success or saturation, negative error otherwise. |
| `node_drain fd` | Consumes a coalesced hint; an already empty descriptor is harmless. |
| `node_wait h wake stop interval` | Waits on distinct nonnegative descriptors. Returns 2 for stop, 1 for work hint, 0 for timeout, negative error otherwise. Interval is nanoseconds; negative means infinite. |
| `node_reset h epoch` | Creator only. Drops the published count to zero, clears every record version, clears stop and records `epoch` (nonzero) at header offset 40. Only `pool.om` calls it, after proving no reader holds the arena. |
| `node_epoch h` | The epoch recorded by the last `node_reset`; zero for a fresh arena. |

All handles must be live handles from `node_new`, and descriptors must remain
owned and open throughout the call. Invalid mapping handles trap in the compiler
runtime. These API checks do not turn writable shared memory into an isolation
boundary. Only trusted transport code receives the mapping. Untrusted tool
processes must use validated proposals through the existing authority owner.

Transport refusal codes are local to this API. Eventfd and polling helpers return
Linux-style negative errors. Record APIs return the refusal meanings documented
in the source; callers must interpret the result in the context of the operation.

The creator PID check catches accidental publication or stop from a forked worker.
It is not authentication, crash fencing or PID-reuse protection. A supervisor must
retire the entire arena and its workers if the publisher dies. Never hand an old
arena to a replacement publisher. Authority generations belong in the integrating
runtime, not in an assertion that a PID is a capability.

## Publication and wake-up order

The creator writes payload and immutable record metadata, publishes the record
version, then publishes the latest version. `mapset` and `mapget` use the existing
compiler's fenced aligned accesses. A reader first observes the published count,
then validates the selected record version before accessing its bytes. Readers
never race a rewrite of a published payload.

After publishing, notify each subscribed worker through its own eventfd. Sharing
one eventfd among workers would distribute wake-ups instead of broadcasting them.
To stop, call `node_stop`, then notify every worker's separate control eventfd.
`node_wait` gives stop priority when work and control are both ready. A caller
must also check stop between bounded work units and validate authority again
before committing effects.

A consumer scans relevant published versions, processes them, advances its cursor,
then waits. On wake, scan again even if notifications have coalesced. Publication
between the scan and wait leaves an eventfd hint pending. Publication concurrent
with draining is covered by the scan after the drain. Signals may be stale;
they never encode an artifact count or transfer authority. An eventfd error must
be handled by the supervisor; it does not undo an already committed publication.

`node_wait` returns EINTR to the caller, which can recompute a monotonic deadline.
The eventfd helpers bound interruption retries and return the last interruption
if exhausted. A positive wait result does not promise that the worker will be
scheduled within a deadline. Cancellation of running model/tool work is separate.

## Capacity and lifetime

The arena holds 64 immutable records. Full publication returns -2 without
overwriting old data. Inside one epoch nothing is recycled. Drop mappings only
after all readers finish; unmap each process's handle or terminate that process.
Fork inherits the arena; exec does not.

Reuse across epochs is `pool.om`'s job (next section): it resets an arena only
after the current epoch has moved past it and no worker holds it.

MODELED layout, checked with Wolfram Language:
`{4096+64*(64+4096), Mod[64+4096,64]}` returned `{270336, 0}`.
The first value is arena bytes; the second checks slot-stride alignment. Header
words at offsets 0, 8, 16, 24, 32 and 40 hold magic, ABI, count, stop, creator PID
and epoch.
Record slots start at 4096 with stride 4160; version, length and topic mask are
at slot offsets 0, 8 and 16, followed by payload at offset 64. These are ordinary
CPU mappings, with no GPU-coherence or cross-machine shared-memory claim.

## Acceptance and negative controls

The gate checks malformed versions/lengths, nonzero topics, header and record
corruption, retained old data at capacity, worker publication refusal, notification
coalescing, stop priority, and both consumers' selected payloads byte for byte.
Both workers are forked before publication. Their acknowledgements and exits are
checked. Failure cleanup signals and reaps only the exact created child PIDs.

Generate each control in a disposable copy of `transport.om`, append the unchanged
test, compile successfully, and run with the same timeout:

| Change in transport source | Expected gate exit |
| --- | --- |
| Mapping mode `NBYTES 3 33` to `NBYTES 3 34` | 87 (child verification failure) |
| Each `if ne mapget h off 8 v` to `if false` | 33 (record-version refusal lost) |
| `if ne and mapget h add off 16 8 topics 0` to `if true` | 21 (topic filter lost) |
| Each `ret 2` to `ret 1` | 55 (stop no longer distinguished from work) |
| Each creator comparison `if ne mapget h 32 8 ulong getpid` to `if false` | 87 (child detects unauthorized publication accepted) |

These controls check observable protocol behavior. Emulation does not establish
weak-memory correctness on physical ARM hardware. The abstract Lean model in
omega-harness PR 206 does not prove this implementation or its memory ordering.

## Epoch pool and worker supervision (DRA-286)

Status: IMPLEMENTED in `pool.om` and `super.om`. Exercised by `pool-gate.om` and
the negative controls below on native Linux AArch64. Evidence and pins are in the
DRA-286 pull request. Not connected to the live hive.

### Build and check

`pool-gate.om` is the exact byte concatenation of `transport.om`, `pool.om`,
`super.om` and `pool-test.om`:

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/pool-test.om > build/node/pool-composed.om
cmp build/node/pool-composed.om seed/node/pool-gate.om
seed/out/omc < seed/node/pool-gate.om > build/node/pool-gate
chmod +x build/node/pool-gate
timeout 120 build/node/pool-gate           # all phases, ends "PASS node pool"
timeout 90 build/node/pool-gate stress     # concurrent stress phase only
```

The gate forks real processes, uses anonymous shared mappings, pipes and
eventfds, sends SIGKILL only to the exact PIDs it created, and opens no GPU,
model endpoint or socket. It needs about 3 s, most of it the stalled worker's
2 s stop deadline.

### Pool contract

`pool_new K W` maps K arenas (1..8) and one 4096-byte control page before any
fork, so every worker inherits the same shared memory. Arena 0 opens epoch 1.
Epoch numbers only grow; an arena is reused for a later epoch, never an epoch
number.

| Function | Contract |
| --- | --- |
| `pool_new k w` | Control handle, -7 for K outside 1..8 or W outside 1..64, or a mapping errno (all mappings made so far are dropped). |
| `pool_acquire c w` | Worker w holds the current epoch: returns that arena, -1 stopped, -5 invalid, -7 bad worker, -8 the epoch moved 16 times running. |
| `pool_hold c w e` | The step `pool_acquire` repeats: store hold e, read the epoch again, refuse -8 if it moved. Every refusal clears the hold. |
| `pool_release c w` | Clears hold w. The old arena must not be read afterwards. |
| `pool_roll c` | Creator only. Opens epoch E+1 in a free arena or one whose older epoch no worker holds, then publishes E+1. -9 when every other arena is held: nothing changes (fail closed). -1 once stopped, -6 from a non-creator. |
| `pool_pick c`, `pool_reuse c i n` | The two steps of `pool_roll`, separate so the gate can interleave them with a worker. |
| `pool_publish c topics src n` | Creator: publish to the current epoch; when that arena is full, roll once and publish there. |
| `pool_current c`, `pool_epoch c` | Current arena handle and epoch. |
| `pool_stop c`, `pool_stopped c` | Sticky stop flag on the control page; creator only. |
| `pool_setw c w pid state`, `pool_clear c w` | Creator bookkeeping: worker PID and state (1 live, 2 reaped), and clearing a reaped worker's hold. |
| `pool_free c` | Drop this process's mappings of the pool. |

Control page u64 words: 0 magic, 8 ABI, 16 current epoch, 24 stop, 32 creator
PID, 40 K, 48 W, 64+8k arena handle, 128+8k arena epoch (0 while free or being
reset), 256+8w hold of worker w, 768+8w worker PID, 1280+8w worker state.

Writers: the creator writes the epoch, the arena table and every arena record.
Worker w writes only hold word w while it lives. The creator clears hold w only
after it has reaped worker w, so a dead worker's hold never blocks reuse forever
and a live worker's hold is never cleared under it.

Reclamation is epoch-based. A worker stores its hold, then reads the current
epoch again; the creator publishes the new epoch before it scans holds. `mapset`
and `mapget` each put `DSB SY` on both sides of their access, so either the scan
sees the hold or the worker's second read sees the move and it retries. An arena
is reset only when its epoch is older than the current one and unheld. A held
older epoch therefore stays complete and unchanged for as long as it is held,
while newer epochs are published in other arenas.

### Supervision contract

| Function | Contract |
| --- | --- |
| `sup_init c` | Creator: one creator life pipe and wake, stop and ack eventfds for each of W slots. On failure everything it opened is closed. |
| `sup_spawn c w` | Creator: fork worker w. 0 in the child, the PID in the creator, -16 if slot w is live, -7 bad slot, or an errno. |
| `sup_wwait c w interval` | Worker: 3 creator gone, 2 stop, 1 wake hint (drained; rescan state), 0 timeout, or an errno. Creator loss outranks stop, stop outranks work. |
| `sup_ack w`, `sup_wake w`, `sup_take fd` | Post an ack, post a wake hint, read and reset an eventfd counter. |
| `sup_poll c interval`, `sup_pollx c interval acks` | Creator: wait for deaths and, unless `acks` is false, acks (left pending for `sup_take`). Reap every worker whose life pipe hung up. Returns the number reaped, or the first reap or poll error. |
| `sup_reap c w` | Creator: reap the exact PID (SIGKILL after about 1 s if it has not exited), then close its life pipe, clear its hold and mark it reaped. A `waitpid` error releases nothing. |
| `sup_stop c interval` | Creator: set stop, post every live worker's stop eventfd, and reap until all exit or the interval ends. That wait ignores acks, so a pending ack cannot turn it into a spin that kills before the deadline. Then SIGKILL and reap the rest. Returns how many were killed. |
| `sup_live c`, `sup_closeall` | Live worker count; close every descriptor this module opened. |

Death is detected without scanning PIDs. Each worker alone holds the write end
of its close-on-exec life pipe: the creator closes its copy right after the
fork, so later workers never inherit it. The worker's exit hangs up the
creator's read end. In the other direction, each child closes the creator's
life-pipe write end at once, so creator death hangs up every worker's read end
and `sup_wwait` returns 3. Workers must not `exec` themselves: exec closes the
life pipe and is treated as death. Tools started by a worker should fork first.

### Negative controls

Each control is a one-line change to a disposable copy, composed with the
unchanged other fragments and test, compiled and run with the same timeout:

| Change | Expected exit |
| --- | --- |
| `pool.om`: `pool_held`'s `ret true` to `ret false` (holds ignored) | 28; with `stress`, 129, 130 or 133 |
| `transport.om`: delete `r = mapset h 16 8 0` in `node_reset` (count kept) | 34 |
| `super.om`: delete `r = pool_clear c w` (dead worker keeps its hold) | 74 |
| `super.om`: delete every `r = killpid int` line (no kill escalation) | 84 |
| `super.om`: delete `r = fclose get swpar 1` (child keeps creator end) | 99 |
| `super.om`: `if ne get p 22 0` to `if false` (creator loss ignored) | 99 |
| `pool.om`: delete `r = mapset c hw 8 e` (hold never stored) | 24; with `stress`, 129, 130 or 133 |
| `super.om`: delete `r = fclose wr` (creator keeps a worker's life end) | 72 |
| `pool.om`: `if ne mapget c 16 8 e` to `if false` (no epoch recheck) | 144 |
| `super.om`: `sup_stop` waits with `acks` true (pending ack spins the wait) | 90 |

The recheck control is deterministic because the gate runs the protocol steps
in the losing order (`pool_hold` after `pool_roll` and `pool_pick`). The same
mutant under the timing-dependent `stress` phase exited 0 in 5 of 5 probes:
the window needs two rolls inside one announce, so stress alone does not prove
the recheck.

## Cooperative scheduling (DRA-287)

Status: IMPLEMENTED in `sched.om`, exercised by `sched-gate.om` and the
controls below on native Linux AArch64. Evidence is in the DRA-287 pull request.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/node/sched-test.om > build/node/sched-composed.om
cmp build/node/sched-composed.om seed/node/sched-gate.om
seed/out/omc < seed/node/sched-gate.om > build/node/sched-gate
chmod +x build/node/sched-gate
timeout 120 build/node/sched-gate        # all phases; prints idle and wake figures, ends "PASS node sched"
timeout 60 build/node/sched-gate idle    # the idle and wake phase only
```

### Model

One creator owns admission, assignment, collection and review. Workers write
only their own cell. No step waits for every worker, so a slow or dead worker
holds only its own job.

A job moves through these states: 1 waiting for a dependency topic, 2 ready,
3 running on one worker, 4 in review, then free. A job can also become 6
UNKNOWN: its worker died mid-job and the job is not marked safe to rerun.
Admitted work (states 1 to 3) and work in review (4) have separate limits.
`sched_admit` refuses with -2 at the admission limit; nothing is queued behind
the refusal. When review is full, a finished worker keeps its result and gets
no new job, so assignment stops instead of dropping work.

Scheduling page cell of worker w (128 bytes at 128w). Creator words: 0 assigned
seq, 8 job id, 16 input epoch, 24 input version (`node_count`), 32 interest
topics, 40 wake stamp. Worker words: 64 done seq, 72 outcome, 80 wakes,
88 last wake latency, 96 largest wake latency. Result bytes go in a
4096-byte outbox per worker. The worker writes them and the outcome before its
done seq. The creator writes a worker word (done seq) only after reaping that
worker, to retire its assignment.

Wake-ups are hints. The creator publishes or assigns first and posts the wake
second. The worker's wait drains the hint, then the worker re-reads its cell
and rescans before it waits again. A post that lands after the drain leaves the
eventfd readable, so the next wait returns at once: no wake-up is lost, and
several posts coalesce into one wake.

| Function | Contract |
| --- | --- |
| `sched_new c a rl` | Creator, before fork: map the scheduling page and outboxes; admission limit a and review limit rl, each 1..64. |
| `sched_admit id deps flags` | Slot, or -2 at the admission limit. deps 0: ready now; otherwise waiting for a publication whose topics meet deps. flags bit 0: safe to rerun after worker death. |
| `sched_want w topics` | Creator: publications meeting `topics` wake worker w. |
| `sched_publish c topics src n` | `pool_publish`, then waiting jobs whose deps meet topics become ready, subscribed live workers are woken, and ready jobs are dispatched. |
| `sched_step c interval` | Creator loop: wait for an ack or death, take acks, retire reaped workers' jobs (`sched_lost`), collect, dispatch. |
| `sched_dispatch c`, `sched_collect c` | Assign ready jobs to idle live workers; move finished results into review while there is room. |
| `sched_lost c w` | After a reap: a rerunnable job is ready again (attempt + 1); any other job becomes UNKNOWN and is never run again. A finished result is still collected. |
| `sched_review j`, `sched_settle j` | Accept a reviewed result (returns its outcome) or release an UNKNOWN job whose outcome was settled elsewhere. Effects are committed by `auth.om` (DRA-288); review only releases the job. |
| `sched_pause c on` | Pause (no job is assigned) or resume and dispatch. Returns the number dispatched. |
| `sched_cancel j` | 1 waiting or ready job freed, 2 running (the caller must tell its worker), 3 already in review, 4 UNKNOWN, -3 no such job. |
| `sched_stop c interval` | `sup_stop`, then retire every reaped worker's job. |
| `sched_wjob w`, `sched_wdone w q outcome src n`, `sched_wwait c w interval`, `sched_wscan c w` | Worker side: the pending assignment, the finish report (result, then outcome, then done seq, then ack), a wait that records wake latency, and a scan of subscribed versions in the held epoch. |

A worker's scan cursor follows the current epoch. If an epoch it never held is
reclaimed, the worker never receives the versions published in it. Consumers
that need every version must be assigned work rather than relying on
subscriptions alone.

### Acceptance and controls

The gate covers the following phases:
- Irrelevant topics wake nobody.
- 30 relevant publications reach two subscribers in full; a lazy subscriber needs exactly 2 wakes.
- Six fast jobs finish and are reviewed while a slow job still runs.
- Admission refuses the 9th job and review holds at 2.
- A dependency topic starts a waiting job and another topic does not.
- Two workers are killed mid-job. The rerunnable job runs again elsewhere (attempt 2); the other becomes UNKNOWN.
- Stop under load: 8 admitted and 3 running jobs; everything finishes in under 1 s with 3 UNKNOWN and 5 still ready.
- Idle CPU and wake-ups:
  - Two idle workers and the creator use at most 2 clock ticks while the creator waits 2 s.
  - In 200 publication rounds, each worker wakes exactly once per round.

| Change | Expected exit |
| --- | --- |
| `sched.om`: `if ne and sc_cell w 32 topics 0` to `if true` (interest ignored) | 16 |
| `sched.om`: delete the `sc_wake w` after `sc_set w 0 q` (no wake on assignment) | 34 |
| `sched.om`: `if ge sched_count 4 4 get sclim 1` to `if false` (review unbounded) | 50 |
| `sched.om`: `if ge sched_count 1 3 get sclim 0` to `if false` (admission unbounded) | 48 |
| `sched.om`: `put sjst j 6` to `put sjst j 2` (UNKNOWN job rerun) | 83 |
| `sched.om`: delete `sc_set w 64 get scseq w` (dead worker's assignment not retired) | 92 |
| `sched.om`: `put sjst j 1` to `put sjst j 2` (dependencies ignored) | 68 |
| `super.om`: `iv = interval` to `iv = 0`, run with `idle` (workers spin) | 138 |

## Proposals, authority and cancellation (DRA-288)

Status: IMPLEMENTED in `auth.om`, exercised by `auth-gate.om` and the controls
below on native Linux AArch64, with real forked workers running real child
tools (`/bin/sh`). Evidence is in the DRA-288 pull request.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/auth.om seed/node/auth-test.om > build/node/auth-composed.om
cmp build/node/auth-composed.om seed/node/auth-gate.om
seed/out/omc < seed/node/auth-gate.om > build/node/auth-gate
chmod +x build/node/auth-gate
timeout 120 build/node/auth-gate         # ends "PASS node authority"
```

### Model

A worker proposes; the creator alone decides and commits. Every effect is one
action record of `seed/authority/action.om`, keyed by its operation identity:
`actstart` when the creator grants it, `actrecon` with the worker's reported
outcome, `actlost` when the worker dies with it in flight. A performed
operation is never started again, and an UNKNOWN one is never retried (verdict
7); `actstart` enforces both, and the attempt limit (verdict 8).

A proposal (words 0..15 of the worker's 4096-byte proposal page) is typed
(version 1, kind 1) and carries the job id and assignment seq, the worker
slot and incarnation, the input epoch and version it read, the authority
generation it holds, the 4-word operation identity and the effect class
(1 external effect, 2 none). The creator refuses it, in this order, when it
is malformed (1), not the worker's current assignment (2), from another
incarnation of the slot (3), stale (4: the input differs from the assignment,
the epoch was rolled, or a newer version was published on one of the job's
dependency topics), under a revoked generation (5), or for a job being
cancelled (6). A refused job finishes with outcome 16 + verdict.

A granted tool runs as the leader of its own process group (both sides call
`setpgid`), stdin on `/dev/null`, output into the proposal page from byte 128.
Cancellation of its job, authority revocation, stop or creator loss make the
worker SIGKILL the whole group. The outcome comes from the wait status alone:
a tool that exited is performed (2), even if a cancel raced its exit; a killed
tool with an external effect is UNKNOWN (0); a killed class 2 tool is not
performed (1). Group members left behind are killed either way. If the worker
dies, the creator kills the tool group named in the worker's cell and records
the action UNKNOWN.

Control reaches a worker through its own control eventfd, in addition to the
wake and stop eventfds, so a worker waiting for a decision or running a tool
handles it at once. Each control carries a seq the worker acknowledges, with
the paused flag it saw. Pause stops both assignment and decisions; running
tools go on. Revocation moves the generation on: pending proposals under the
old one are refused, running granted tools are cancelled, and a report already
made is still recorded as made.

Control page cell of worker w (128 bytes at 128w). Creator words: 0 control
seq, 8 cancel target (assignment seq), 16 decided proposal seq, 24 verdict,
32 generation at the decision. Worker words: 64 control ack, 72 proposal seq,
80 report seq, 88 outcome, 96 tool wait status, 104 paused as seen, 112 tool
process group, 120 tool output bytes. Words 8192 and 8200 mirror the
generation and the paused flag.

| Function | Contract |
| --- | --- |
| `auth_new c`, `auth_free` | Creator, after `sup_init` and before any spawn: map the control and proposal pages and one control eventfd per slot; generation 1. |
| `auth_spawn c w` | `sup_spawn` with a new incarnation of slot w. |
| `auth_step c` | After `sched_step`: record reports, close the actions of reaped workers (`actlost`, tool group killed), decide pending proposals unless paused. |
| `auth_revoke c`, `auth_pause c on`, `auth_cancel c j` | The operator controls: new generation; pause or resume; cancel a job (`sched_cancel`, then the worker's control for a running one). |
| `auth_act op i`, `auth_cell w off`, `auth_wout w dst` | Read an action record word, a control cell word, a worker's tool output. |
| `auth_propose w q op class`, `auth_wdecide c w q interval` | Worker: propose, then wait for the verdict while handling control. |
| `auth_wtool c w q pk pn class`, `auth_wreport w q outcome` | Worker: run the granted tool (packed argv as `execprog`), report its outcome. |
| `auth_wwait c w x interval`, `auth_wctl w` | Worker wait on wake, stop, creator loss, control and optionally fd x; the control handler (ack, paused, cancel target). |

Limits: action records live in creator memory only, so a creator restart
loses them (DRA-289 adds the journal). Between a worker's death and the
creator's `auth_step` the tool's group id could in principle be reused; the
window is one creator step. At most 64 action records are live.

### Acceptance and controls

Job id = kind × 1000 + operation number. The gate covers the following
phases:
- A: a granted operation runs once and is performed; the same operation in a new job is refused (7) and its tool does not run again.
- B: a proposal is refused as stale (4) after a newer version on its dependency topic or an epoch roll; a newer version on another topic does not make it stale.
- C: forged incarnation, job id and version are refused (3, 2, 1) and no tool runs.
- D: revocation before the decision refuses (5). Revocation during a tool kills its grandchild and records UNKNOWN; the operation is then refused (7). Revocation after the tool reported still records performed.
- E: cancel before start frees the job with no action record. Cancel during a tool kills its grandchild and records UNKNOWN. Cancel in review changes nothing. A cancel 200 ms after the tool's own process exited, while its grandchild still held the output, records performed and still kills the grandchild.
- F: a worker killed mid-tool: the creator kills the tool's group and the action and job are UNKNOWN.
- G: pause is acknowledged by every worker within 1 s; while paused a pending proposal stays undecided and a ready job is not assigned; resume performs both.

| Change | Expected exit |
| --- | --- |
| `auth.om`: delete both `setpgid` calls (no process group) | 58 |
| `auth.om`: `r = killpid neg int pid 9` to `r = killpid int pid 9` (direct kill only) | 58 |
| `auth.om`: a killed tool always reports UNKNOWN (`if k` / `ret 0` before `ret au_outcome st class`) | 85 |
| `auth.om`: `ret ne node_next h au_pw w 7 t 0` to `ret false` (newer input ignored) | 27 |
| `auth.om`: `if ne au_pw w 8 get augen 0` compares the proposal with itself (generation ignored) | 52 |
| `auth.om`: `if ne au_pw w 5 get auinc w` compares the proposal with itself (incarnation ignored) | 40 |
| `auth.om`: in `au_commit`, `k = au_find op` to `k = neg long 1` (duplicate performed) | 17 |
| `auth.om`: delete `au_ctl w au_cell w 16` in `auth_revoke` (running tools not cancelled) | 55 |
| `auth.om`: delete `au_ctl w sc_cell w 0` in `auth_cancel` (worker never told) | 75 |
| `auth.om`: delete `x = killpid neg int p 9` in `au_lost` (dead worker's tool left running) | 96 |
| `auth.om`: decide proposals while paused | 120 |
| `sched.om`: `if ne get scpause 0 0` to `if false` (assign while paused) | 121 |
