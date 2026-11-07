# Omega Node shared-memory transport, epoch pool, worker supervision, scheduling, authority, journal, coding workflow, operator view and release

This is the first implementation component of [Omega Node](https://github.com/aien-dev/omega-harness/issues/205).
It provides a bounded, single-publisher artifact log for trusted forked Omega
processes. Runtime consumers can share artifact storage and wake only interested
workers. The existing `seed/agent/agent.om` is the coding-agent consumer to evaluate
for integration; this change does not replace its model or tool dispatcher.

Source fragments, concatenated in this order before one program with `fn main`:

| Fragment | Adds |
| --- | --- |
| `transport.om` | one arena: 64 immutable records, topic scan, eventfd hints, stop flag (#1055) |
| `pool.om` | K arenas reused by epoch, reader holds, fail-closed rollover (DRA-286) |
| `super.om` | forked workers, death detection, reaping, creator-loss detection, bounded stop (DRA-286) |
| `sched.om` | subscriptions, dependency wake-ups, bounded admission and review, job loss handling (DRA-287) |
| `seed/authority/action.om` | the existing action records the authority layer commits through |
| `journal.om` | durable journal of every authority transition, fencing, restart recovery (DRA-289) |
| `auth.om` | typed proposals, one commit owner, cancellation of real child tools, operator controls (DRA-288) |
| `gram.om` | the round40 repair grammar, shared by the tool and the creator (DRA-290) |
| `code.om` | the coding workflow: own-model turns, typed tool jobs, review (DRA-290) |

Two child programs serve the workflow as tools: `infer.om` (one model turn
against a local `ollm serve`) and `tool.om` (read, check, replace inside one
root). The component is not yet connected to the live hive. The operator
view and Spark qualification remain implementation work (DRA-291, DRA-292). The
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
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/journal.om seed/node/auth.om seed/node/auth-test.om > build/node/auth-composed.om
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

Limits: without an open journal (the DRA-288 gate) action records live in
creator memory only; `journal.om` makes them durable (DRA-289). Between a worker's death and the
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

## Durable journal and restart recovery (DRA-289)

Status: IMPLEMENTED in `journal.om` and `auth.om`, exercised by
`journal-gate.om` and the controls below on native Linux AArch64: a conductor
forks real creators (with real workers and `/bin/sh` tools), crashes them at
every boundary and restarts them. Evidence is in the DRA-289 pull request.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/journal.om seed/node/auth.om seed/node/journal-test.om > build/node/journal-composed.om
cmp build/node/journal-composed.om seed/node/journal-gate.om
seed/out/omc < seed/node/journal-gate.om > build/node/journal-gate
chmod +x build/node/journal-gate
rm -rf build/node/jt
timeout 120 build/node/journal-gate      # ends "PASS node journal"; uses build/node/jt
```

### Journal

`DIR/journal` is a 64-byte header and then 128-byte records, little endian
64-bit words. Header: magic, format version 1, record size 128, the 4-word
objective identity, FNV-1a 64 of words 0..6. Record: type, seq (1, 2, 3, ...
without gaps), fence, 12 payload words, FNV-1a 64 of words 0..14.

| Type | Payload | Appended by |
| --- | --- | --- |
| 1 OPEN | pid, authority generation | `jn_open`, every creator incarnation |
| 2 ADMIT | job id, dependency topics, flags | `jn_admit`, before `sched_admit` |
| 3 START | operation identity, class, job id, attempt, generation | `au_decide`, after `actstart`, before the grant is published |
| 4 DONE | operation identity, outcome, job id, how (1 reported, 2 worker lost, 3 in flight at restart, 4 key present, 5 key absent, 6 no external effect) | `au_record`, `au_lost`, recovery |
| 5 RELEASE | job id, outcome (300 cancelled) | `jn_release`, before `sched_review`; `auth_cancel` |
| 6 REVOKE | new generation | `auth_revoke` |
| 7 PAUSE | 1 paused, 0 resumed | `auth_pause` |
| 8 CANCEL | job id | `auth_cancel`, before the worker is told |

Order: the in-memory tables first check the transition (a refused one is
never written), then the record is written with `pwrite` and made durable
with `fdatasync`, and only then does anything act on it or publish it: a
grant reaches the worker after its START is durable, a job is reviewed after
its RELEASE is durable, and a job is not released while its operation's DONE
is not durable. A write or sync failure marks the journal failed and every
later append is refused (30), so the creator never acts on a transition that
might not be durable. A new journal's directory entry is synced
(`jn_dsync`).

Fencing: `DIR/lock` is held with `flock(LOCK_EX)` for the creator's life. It
is opened close-on-exec, so tools never inherit it; forked workers do, so a
new creator cannot open the journal until every worker of the old one has
exited (refused with 20 after the wait). Each open appends OPEN with the next
fence number and every record carries the fence of the creator that wrote it,
so each incarnation's records are attributable. The pid lock in
`seed/authority/lock.om` was not reused: it reclaims stale locks by pid, which
races, and has a fixed path.

Torn tail: a partial last record, or a last full record whose checksum or seq
is wrong, was never acknowledged and is cut off (`ftruncate` plus sync). A bad
record before the last one is corruption: the open is refused (23) and the
file is not changed.

Compatibility: a header whose magic, version, record size or checksum differs
is refused (21), never reinterpreted; a different objective identity is
refused (22). A future format must change the version.

### Recovery

`jn_open` reads the journal into the recovery tables; `auth_recover` (after
`sched_new` and `auth_new`, before spawning workers) settles and readmits:
- A START with no DONE was in flight at the crash. Class 3 (an idempotent effect whose key `DIR/k.<op>` the effect itself creates atomically, for example with `ln`) is decided by the key: present is performed, absent is not performed and the job runs again. Class 2 (no external effect) is not performed. Class 1 is UNKNOWN and is never run again. Each gets a DONE.
- An admitted job not yet released: a performed or UNKNOWN last operation releases it with that outcome; a cancelled job is released as cancelled; any other job is admitted again with its dependency topics.
- The action records (state, attempt, generation), the authority generation (above every journaled one) and the pause state are restored, so a performed or UNKNOWN operation is refused if proposed again and a paused objective stays paused.
- A restart that finds nothing in flight adds only its OPEN.

A crash between START and publishing the grant leaves a class 1 operation
UNKNOWN even though its tool never ran. That is the pessimistic side: an
effect is never repeated without proof that it did not happen.

| Function | Contract |
| --- | --- |
| `jn_open dir dn obj ms`, `jn_close` | Creator: take the lock (wait up to ms), create or check the header, cut a torn tail, read every record, append OPEN; release. |
| `auth_recover c` | Settle, release or readmit, restore authority and pause. |
| `jn_admit id deps flags`, `jn_release j` | Durable admission and release around `sched_admit` and `sched_review`. |
| `jn_known id`, `jn_done_j id`, `jn_jout id`, `jn_stat i`, `jn_fence`, `jn_gen`, `jn_act k i` | Recovered state. |

Limits: no checkpoint or compaction yet; recovery replays the whole journal
and the tables hold 64 operations and 256 jobs. Inputs published to the pool
are not journaled, so a recovered job reads whatever its dependency topics
hold after the restart. The key of a class 3 effect must be created by the
effect itself, atomically and last.

### Acceptance and controls

The gate runs, each in a fresh `build/node/jt`, and checks with its own
reader (header, checksums, contiguous seq, fences, START/DONE pairing, one
RELEASE per job, sink lines, keys):
- 0 baseline: a class 1 and a class 3 job each performed once.
- 1 crash after ADMIT: the admitted job is readmitted, the other admitted; both performed once.
- 2 crash after START, before the grant: class 1 UNKNOWN, its tool never ran; two more restarts add only OPEN records.
- 3 the same for class 3: key absent, run again (attempt 2), performed once.
- 4, 5 crash after the tool reported, before DONE: class 1 UNKNOWN with the effect once; class 3 performed by its key.
- 6, 7 crash after DONE, and after RELEASE: released once, nothing run again.
- 8 crash in the middle of writing DONE (60 bytes on disk): the tail is cut, UNKNOWN.
- 9, 10 SIGKILL of the creator while a slow tool runs: the workers kill it; class 3 runs again and performs once, class 1 is UNKNOWN with no effect.
- 11 a second creator while the first runs is fenced (20) and changes nothing.
- 12 another objective (22), another format version (21), a corrupt middle record (23): refused, journal unchanged.
- 15 a paused objective stays paused across a restart until resumed.

| Change | Expected exit |
| --- | --- |
| `journal.om`: cut any bad record as a torn tail (`if true`) | 157 |
| `journal.om`: in `jn_settle`, class 1 in flight becomes not performed (replayed) | 33 |
| `journal.om`: in `jn_settle`, class 3 not probed | 43 |
| `journal.om`: `jn_probe` always reports the key absent | 66 |
| `auth.om`: the reported outcome is not journaled | 10 |
| `journal.om`: no `flock` (no fencing) | 141 |
| `journal.om`: `jn_recover` skips `jn_settle` (the restart never releases the job) | 35 |
| `journal.om`: objective check removed | 151 |
| `journal.om`: version and record-size check removed | 154 |
| `auth.om`: `auth_recover` does not restore pause | 161 |

## Local inference and the coding workflow (DRA-290)

Status: IMPLEMENTED in `infer.om`, `tool.om`, `gram.om` and `code.om`,
exercised on native Linux AArch64 by `code-test.om`, the round40 replay
`tests/tool-replay.om` (seeded Omega; it replaced `tests/tool-replay.py` with
the same check lines, summary and exit status), the tool controls and live runs
of the own Omega model (round40 checkpoint served by aien-train `ollm serve`,
DRA-119, inside a private network namespace). Evidence is in the DRA-290 pull
request. Not QUALIFIED on the Spark and not DEPLOYED.

All six are OM-2 programs (`printf 'om2\n'` before the sources):

```sh
L="seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/journal.om seed/node/auth.om"
{ printf 'om2\n'; cat seed/json/json.om seed/json/jsonw.om seed/net/http.om seed/net/notls.om seed/node/infer.om; } | seed/out/omc > build/node/infer
{ printf 'om2\n'; cat seed/agent/path.om seed/node/gram.om seed/node/tool.om; } | seed/out/omc > build/node/tool
{ printf 'om2\n'; cat seed/net/http.om seed/net/notls.om $L seed/node/view.om seed/node/gram.om seed/node/code.om seed/node/code-main.om; } | seed/out/omc > build/node/code-main
{ printf 'om2\n'; cat seed/net/http.om seed/net/notls.om $L seed/node/view.om seed/node/gram.om seed/node/code.om seed/node/code-test.om; } | seed/out/omc > build/node/code-test
{ printf 'om2\n'; cat seed/json/json.om seed/node/tests/drv.om seed/node/tests/tool-replay.om; } | seed/out/omc > build/node/tool-replay
{ printf 'om2\n'; cat seed/json/json.om seed/node/tests/drv.om seed/node/tests/drv-test.om; } | seed/out/omc > build/node/drv-test
chmod +x build/node/infer build/node/tool build/node/code-main build/node/code-test build/node/tool-replay build/node/drv-test
build/node/code-test unit build/node/cu   # "code checks=57 fail=0", exit 0
build/node/drv-test /tmp/dvt   # "DRV-TEST pass=36 fail=0 not_run=0", exit 0
build/node/tool-replay build/node/tool OMC40 ROUND40 build/node/replay   # "TOOL-REPLAY runs=108 pass=108 fail=0 actions=417", exit 0
```

A failed compile leaves an empty output file that exits 0 when run; check
omc's exit status. `OMC40` is the compiler the round40 model was trained and
evaluated with (sha256 `2c82480596bb…`, omega-mv `e5b32567`; on the Spark
`~/work/omega-node-e5b3/seed/out/omc`): its error text is part of the prompt,
so the check tool must use it. `ROUND40` is the round40 run directory holding
`repair.py` and `final-selected.json`.

### Test drivers

The drivers are seeded Omega built by this checkout's `seed/out/omc`; no
system program is executed. `tool-replay` runs only TOOL (with OMC as its
argument), with stderr to `/dev/null`; `drv-test` runs only its own binary as
the child.

`tool-replay TOOL OMC ROUND40 OUTDIR` replays every recorded round40 run
through TOOL in `OUTDIR/<job.id>` and checks that each rebuilt `repair.py`
prompt equals the next recorded prompt byte for byte. It prints a `MISMATCH`
line (with `want` and `got` in Python repr) or an `ERROR` line per failing step,
then `TOOL-REPLAY runs=R pass=P fail=F actions=A`. It exits 0 when no run
failed, 1 otherwise, and 2 for bad usage or an unreadable fixture. Unlike the
Python driver, it fails a run instead of crashing on a malformed fixture field,
a tool timeout or a malformed `OMNT1` record, and it refuses a job id that is
empty, `.`, `..` or holds `/`. The file header lists its buffer limits.

`tests/drv.om` is the driver library both share (prefix `dv`, composed after
`seed/json/json.om`):

| Group | Functions |
| --- | --- |
| results | `dv_pass`, `dv_fail`, `dv_nrun NAME DETAIL` print `PASS\|FAIL\|NOT_RUN NAME[ DETAIL]` and count; `dv_count KIND` |
| output, formatting | `dv_out`, `dv_err`; `dv_cat`, `dv_byte`, `dv_fmtu`, `dv_fmtl` append at an offset and return the new end |
| bytes | `dv_eq`, `dv_at`, `dv_find`, `dv_atou` (`dvnone` = not a number) |
| arguments | `dv_argc`, `dv_arg I BUF` (length, -22 no such argument, -105 buffer too short) |
| files | `dv_slurp` (-27 does not fit), `dv_spit`, `dv_apnd`, `dv_isdir`, `dv_mkdirp`, `dv_rmrf` (no symbolic link followed), `dv_join` and `dv_dirn` (`os.path.join`, `os.path.dirname`) |
| processes | `dv_pkinit`, `dv_pkadd` build a packed argv; `dv_spawn PK OUT ERR` runs it in its own process group (exit 126 files, 127 exec); `dv_poll`, `dv_reap`, `dv_wait PID DEADLINE` (-110 after killing the group), `dv_kill`, `dv_killg`; status is the exit code or 256 + signal |
| ports | `dv_port`: a free 127.0.0.1 port, never 18091 or 18300 |
| JSON | `dv_jload` (file to tape), `dv_jkey` (the last duplicate wins), `dv_jidx`, `dv_jlen`, `dv_jisl`, `dv_jnum`, `dv_jstr` (UTF-8, surrogate pairs joined), `dv_jsteq` |

`drv-test SCRATCHDIR` checks these functions in `SCRATCHDIR/drv-test.d`
(removed before and after) and prints `DRV-TEST pass=P fail=F not_run=N`; it
exits 1 on any failure, 2 for bad usage. A `drv.om` whose `dv_dirn` keeps a
repeated separator and whose status drops the 256 for a signal gives `FAIL
drv.dirn`, `FAIL drv.kill-reap` and exit 1.

### Qualification runner

`tests/qual.om` replaces the out-of-repo DRA-292 qualification shell conductor.
It composes with SHA-256 and the driver library, invokes only this checkout's
`seed/out/omc` for builds, and ignores the ambient `OMC` variable. Run from the
checkout root, under the operator-approved CPU-pool wrapper, with a fresh
evidence directory outside the source tree:

```
{ printf 'om2\n'; cat om/tls/sha2.om seed/json/json.om seed/node/tests/drv.om seed/node/tests/qual.om; } | ~/work/omega-node-run.sh env -u OMC nice -n 19 seed/out/omc > build/node/qual
{ printf 'om2\n'; cat om/tls/sha2.om seed/node/release.om; } | ~/work/omega-node-run.sh env -u OMC nice -n 19 seed/out/omc > build/node/release
{ printf 'om2\n'; cat seed/json/json.om seed/node/tests/drv.om seed/node/tests/tool-replay.om; } | ~/work/omega-node-run.sh env -u OMC nice -n 19 seed/out/omc > build/node/tool-replay
chmod +x build/node/qual build/node/release build/node/tool-replay
env -u OMC ~/work/omega-node-run.sh build/node/qual /tmp/node-qualification
```

Do not execute a compiler's output when that compilation failed. `HOME` locates
`work/omega-node-e5b3/seed/out/omc`, `handoffs/tool-omega-20261104/round40`, and
`.elan/toolchains/leanprover--lean4---v4.35.0/bin/lean`. The round40 compiler is
an input to tool-adapter checks, never the compiler of the qualification driver
or the Node programs. `build/node/release` and `build/node/tool-replay` must
already exist. Optional seeded `build/node/view-accept` and
`build/node/release-accept` are invoked directly; when absent, acceptance and
every corresponding mutant are `NOT_RUN`, never silently run by Python. Mutant
mutation and compilation still run and fail independently if invalid.

The conductor writes `platform.txt`, `hashes.txt`, `results.txt`, compiler
diagnostics, program outputs and binary hashes. It checks gate composition,
build reproducibility, the old `79894168` reader, code/view/release/journal
mutants, tool replay and controls, the agent check, and the Lean RESULT model.
Mutation replaces whole lines (with optional function scope); the Lean mutant
replaces its exact proposition substring. A missing mutation is a failure.
Source hashes and clean git status are checked again at the end. Exit 0 means
every check passed; exit 1 means one or more failures; exit 3 means no failure
but one or more `NOT_RUN` (a skipped step is never reported as a pass; the shell
conductor it replaces always exited 0); exit 2 means the conductor could not
prepare/read/write its inputs or evidence. `NOT_RUN` is preserved in the
results and receipt.
`platform.txt` records both the hexadecimal affinity mask and `Cpus_allowed_list`.
Evidence from a dirty worktree cannot be promoted to a clean receipt.

SHA-256, copying, composition, mutation, process deadlines, process discovery,
result parsing and evidence writing are seeded Omega. The retained host tools
are read-only git 2.43.0 (`rev-parse`, `status`, `ls-files`, and per-file
`git show 79894168:PATH`, not `tar`), Lean 4.35.0 as a proof oracle,
GNU coreutils 9.4 `uname` for platform identification and `nice` for CPU
priority, and Python 3.12.3 solely for `seed/agent/tests/check.py`. The agent
driver's Omega successor is tracked in omega-mv#1071; its result explicitly
says it is still a Python driver. The slow-compiler adversarial fixture is also
seeded Omega (a sleeping child and parent, killed by the tool adapter's deadline).
No GPU or live model service is opened; there is no crumb-verification stage.

The additive `drv.om` helper `dv_spawnio PK FI FO FE` accepts an already-packed
argv and three open descriptors. It creates a child process group; the caller
retains and closes the descriptors. `dv_spawn PK OUT ERR` now shares one output
file offset when `OUT` and `ERR` name the same path. Both still return the child
PID (or fork error), with child exits 126 for descriptor setup and 127 for exec.

### Receipts

`tests/receipt.om` is the evidence receipt writer, the seeded Omega replacement
for the out-of-repo `omega-node-receipt.py` (prefix `rc`, composed after
`drv.om`). Build it with this checkout's compiler:

```
{ printf 'om2\n'; cat seed/json/json.om seed/json/jsonw.om om/tls/sha2.om \
  seed/node/tests/drv.om seed/node/tests/receipt.om; } > /tmp/receipt.full.om
seed/out/omc < /tmp/receipt.full.om > receipt
```

`receipt EV REPO SUB ISSUE SCRIPT [EXECUTION]` reads `EV/platform.txt`,
`EV/hashes.txt`, `EV/results.txt`, `EV/NAME.out` and `EV/NAME.sha` for every
`PASS NAME compile=0 …` check line, and the last existing of
`EV/repeat-stress.txt` and `EV/repeat-idle.txt` for a `PASS NAME-repeat P/R`
line. It writes the receipt to `REPO/evidence/SUB/receipt.<sha256>.json`, where
the hash is the sha256 of the file's bytes. The file is created exclusively,
with mode 0644. The program then prints the path. The record has the Python
writer's keys in the Python writer's order: `issue`, `source_commit`,
`source_tree`, `platform`, `cpu_affinity_mask_hex`, `execution`,
`timestamp_utc`, `independent_review` (false), `native_aarch64` (`NOT_RUN` when
a results line is NOT_RUN, else `PASS`), `executed_verdict`, `not_run`,
`spark_gate_judge`, `live_hive`, `script`, `hashes`, `checks`, `results`, then
`repeat` (null or one object) or `repeats` (a list).

It refuses, with exit 1 and the Python message on stderr, in these cases:

- `platform.txt` holds no `head H tree T dirty=0`
  (`refused: evidence run was not on a clean tree`).
- A results line is FAIL, including `FAIL count N` with N not 0
  (`refused: results contain FAIL: LINE`).
- The target already exists (`refused: exists PATH`).

It also exits 1 for an unreadable or symbolically linked input, a file over its
buffer, invalid UTF-8 or a JSON writer refusal. It exits 2 for bad usage: fewer
than 5 arguments, or an argument over 4096 bytes. The Python writer raises
there.

The limits are:

- `platform.txt`: 65536 bytes.
- `hashes.txt`: 262144 bytes.
- `results.txt`: 524288 bytes.
- Each `.out`, `.sha` and repeat file: 983040 bytes.
- The JSON: 2 MiB.
- Each path: 4095 bytes.

It differs from the Python writer in these ways:

- The JSON is compact, not indented, and ends with a newline. Non-ASCII text is
  written as raw UTF-8, not as `\uXXXX` escapes. The parsed values are equal,
  but the file name differs because it hashes different bytes.
- `\w`, `\d` and whitespace are ASCII only. A byte of 0x80 or above counts as a
  word byte in a FAIL or NOT_RUN prefix, so such a prefix fails closed.
- The timestamp is truncated to microseconds.
- The FAIL scan runs before any `.out` file is read.

### Programs

`omnode-code INFER TOOL OMC ROOT WORK JDIR PORT VIEW OBJ...` runs 1..4 objectives
`KIND,K,N,A,PATH,TASK` (KIND `add`, `mul` or `loop`) against the files under
ROOT, with the journal in JDIR and compile scratch in `WORK/o<i>`. The creator
holds every objective's state and alone decides; two workers run the granted
jobs, each job one child process in its own process group (`auth_wtool`):

| Job | Child | Input (packed argv published on the objective's topic) |
| --- | --- | --- |
| 1 inference | `infer PORT 160 900 PROMPT` | the prompt of `repair.py` for the current state |
| 2 read | `tool read ROOT PATH` | |
| 3 check, 5 review | `tool check ROOT PATH WORK/o<i> OMC KIND K N A` | |
| 4 replace | `tool replace ROOT PATH OLD NEW` | old and new as the model gave them |

`infer` (exit 2 usage, 3 prompt, 4 connect, 5 deadline, 6 HTTP status, 7
malformed response, 8 busy) connects only to 127.0.0.1, refuses port 18091,
and posts one greedy, non-streamed `/v1/completions` request (aien-train
#76). The server takes one request at a time and keeps generating a few
seconds after a cancelled client is gone, so a 503 is asked again every
second within the deadline; exit 8 means busy until under 2 s were left.
Its record `OMNI1 kind fin ptok ctok plen olen nlen tlen` is followed by
path, old, new and the raw model text; kind 9 is text that is not a protocol
action. No other provider exists: there is no remote or fallback path, so
offline-local is the only mode.

`tool` returns `OMNT1 status olen clen`, the observation and the file. Paths
pass `agpathok` (`seed/agent/path.om`, shared with omagent) and a final
symbolic link is refused; replace writes a temporary file, syncs, renames and
syncs the directory; check follows `repair.py compile_test` with the test
programs run under `execpure`, 10 s for omc and 2 s per test, killing the
whole process group on timeout.

Policy (as `repair.py jobs_run`): at most 7 model turns; read_file only when
unread, omega_check only when read or edited, replace_text only when failed,
`Tests passed.` only when the last check passed, `File not found.` only when
the read found nothing; the path must be the objective's. Before a replace is
granted, the creator checks that old occurs exactly once in the source the
model was shown and that the result stays in the repair grammar (`gr_src`).
Every record is checked against its header lengths and the 3968-byte output
page. A check must return exactly the source the creator holds, a replace
exactly the candidate it computed. `Tests passed.` starts a review job, a
fresh check of the saved file, and only its pass is a PASS. Anything else
ends the objective as FAIL with its reason; nothing is retried or repaired.

| Result | Meaning |
| --- | --- |
| 1 | PASS |
| 10, 11 | action not valid in its state; wrong path |
| 12 | 7 turns used |
| 13 | edit refused (old not exactly once, result outside the grammar, or the tool refused it) |
| 14 | `Tests passed.` without a passing check |
| 15 | the file checked or saved differs from the workflow's source or candidate |
| 16, 17 | inference or tool exited nonzero (no fallback) |
| 18 | malformed record |
| 19 | cancelled (operator `auth_cancel`, or the authority's cancel verdict) |
| 20 | prompt over 3800 bytes |
| 21 | outcome UNKNOWN (a worker or child lost) |
| 22, 23 | job input lost; refused by the authority |

Output: `CWP i turn n` and `CWR i turn n` lines, each followed by n bytes
(the prompt; the model text) and a newline; `CWE i job event value` job
events (1 issued, 2 model action kind, 3 tool status, 4 outcome word, 5
cancel);
`CWO i PASS|FAIL result turns`; `CWSUM pass= fail=`. Exit 0 when
every objective passed, 1 otherwise, 2 usage, 62 out of time, 30 + a journal
refusal.

Restart: the journal's objective identity is the objective arguments' FNV-1a
64. On a restart `auth_recover` settles what the last creator left (an
in-flight replace is UNKNOWN and never rerun); the creator cancels recovered
jobs that still wait for input (pool contents are not journaled), and each
objective resumes from the durable file in state unread with its performed
model turns counted against its 7 and its job ids continuing.

Limits: one inference at a time (one local server); 64 action records per
creator process bound a run to about 4 objectives; lines are split on `\n`
only, so a `\r` makes a line fall outside the grammar where Python's
`splitlines` would split it.

### Acceptance and controls

`code-test unit` (57 checks, no child process) feeds crafted model and tool
records to the creator: the round40 prompts byte for byte; every action in
every state; wrong path; old text absent, twice, many times; an edit outside
the grammar; `Tests passed.` unverified or after an edit; `File not found.`
when not missing; header and length faults; tool content that differs from
the source or candidate; outcome words for exit 4, 5 and 8, a killed child,
cancellation, UNKNOWN and a lost input; the turn limit; an over-long prompt;
a full admission queue (DRA-291: a refused inference waits for its next turn,
a refused tool job ends the objective 23, both counted).
`code-test cancel MS ...` is `omnode-code` with objective 0's first inference
cancelled through `auth_cancel` after MS milliseconds.

| Change to `code.om` | Expected exit |
| --- | --- |
| path not compared | 154 |
| old text not required exactly once | 103 (trap) |
| grammar of the result not checked | 162 |
| `Tests passed.` accepted unverified | 168 |
| checked content not compared | 181 |
| child exit status ignored | 192 |
| 8 turns allowed | 202 |
| saved content not compared | 186 |
| `File not found.` accepted in any state | 171 |
| replace accepted in any state | 157 |
| goal text changed | 151 |
| record length not checked against the page | 174 |
| cancelled read as UNKNOWN | 197 |
| missing file read as read | 178 |
| prompt limit raised to 4000 | 203 |
| refused tool job left waiting (DRA-291) | 206 |

## Operator view and commands (DRA-291)

Status: IMPLEMENTED in `view.om`, `op.om` and `code.om` (with OPER records in
`journal.om`), exercised on native Linux AArch64 by `tests/view-accept.py`,
which drives the real `omnode-code` and `omnode-infer` through `omnode-op`
only, against `tests/fake-serve.om`, a server that answers with the recorded
round40 model turns. Not QUALIFIED on the Spark and not DEPLOYED.

```sh
{ printf 'om2\n'; cat seed/net/http.om seed/net/notls.om seed/node/op.om; } | seed/out/omc > build/node/op
{ printf 'om2\n'; cat seed/net/http.om seed/net/notls.om seed/node/tests/fake-serve.om; } | seed/out/omc > build/node/fake-serve
chmod +x build/node/op build/node/fake-serve
python3 seed/node/tests/view-accept.py $PWD/build/node OMC40 ROUND40 build/node/accept   # VIEWSUM pass=46 fail=0
```

### Model

The creator alone holds and changes state. Before its workers start it maps
one shared page (32768 bytes, `vw_new`) and, when VIEW is not 0, forks the
view process (`vw_spawn`): an `.om` HTTP server on 127.0.0.1 built on
`seed/net/http.om`. The view process only reads the page and posts commands
into its mailbox; it drops the creator's life-pipe write end and the journal
descriptors, and exits when the creator sets the stop word or is gone (its
parent pid changes). Workers never see it.

Every creator loop writes a snapshot under a seqlock and appends one event
per change to a ring of 256 events; the version counts the events of this
incarnation, and the incarnation is the journal's fence. Event types: 1 job
(what, id, value; the same values as the `CWE` lines), 2 objective result,
3 command, 4 pause, 5 worker, 6 admission refused, 7 uncertain effect.

| Request | Answer |
| --- | --- |
| `GET /view` | snapshot: authority (generation, paused, journal seq and failure, fence, version of the last pause change), queue (waiting, ready, running, review, unknown, limit, review limit, admissions refused), commands (committed, refused, last id), workers (pid, incarnation, control acknowledged, paused), uncertain job ids, objectives (kind, K, N, A, state, turns, budget, phase, job in flight, result, version of the last change, redirect and cancel pending, next job seq), limits |
| `GET /view?since=S&inc=I` | delta `[version, type, target, x, a, b]` for every event after S when I is this incarnation and the ring still holds them; otherwise a snapshot (a client resyncs from it) |
| `POST /cmd?id=&op=&target=&inc=&ver=&a=&b=&c=&d=` | acknowledgement `{id, status, version, journal_seq, incarnation}` |
| `GET /health` | `{"ok":true}` |

Polling, not streaming: one request per connection keeps the single-threaded
view process answering commands while a client is slow or gone.

### Commands

Ops: 1 pause, 2 resume, 3 cancel objective, 4 set its turn budget to a
(0..7), 5 redirect it to kind a (1..3), K b, N c, A d (each 0..99).
`omnode-op PORT cmd ID OP TARGET INC VER [A..D]` posts one; `ID` is the
operator's command id, `INC`/`VER` the incarnation and version of the view
the decision was made on.

| Status | HTTP | When |
| --- | --- | --- |
| committed | 200 | durable in the journal and acted on |
| duplicate | 200 | the id was committed before (also by an earlier incarnation); the original version is returned, nothing runs again |
| stale | 409 | another incarnation, or the target changed after VER (the pause state for 1 and 2, the objective for 3..5) |
| invalid | 400 | unknown op or target, out-of-range argument, a finished objective, pausing when paused |
| refused | 500 | the journal refused the record |
| busy | 503 | another command is posted and not yet taken |
| pending | 504 | no acknowledgement in 5 s: post the same id again |

The creator takes one command per loop. Pause and resume go through
`auth_pause` (which journals PAUSE and tells every worker), then OPER is
appended and synced; the objective commands append OPER first and then act:
cancel ends the objective with 19 at once when nothing is in flight, else
its job is cancelled through `auth_cancel` and the objective ends 19 when
the job's result arrives; redirect sets the goal and starts over from
unread the same way; budget takes effect at the next turn (out of turns
ends 12). A committed command's acknowledgement carries the version of its
own command event. At a restart the OPER table is replayed in order after
the objectives resume (pause comes back from the PAUSE record), so a
cancelled objective stays cancelled and a budget or goal stays set.

At the admission limit only inferences are refused: a tool job is issued
after its objective's previous job left the queue, so it takes that job's
place. A refused inference is asked for again at the next turn; a tool job
the authority refuses anyway ends its objective with 23 instead of leaving
it waiting unseen. The view counts the refusals.

An effect whose worker died while the job was assigned is shown at once as
uncertain (snapshot and event 7) and its objective ends 21. The scheduler
cannot tell whether the tool started; the next incarnation's recovery
settles it from the journal: a START without a DONE stays UNKNOWN for good
(and stays listed), no START proves the effect never ran (the job is
cancelled and no longer listed).

### Acceptance and controls

`view-accept.py` (46 checks) runs nine scenarios, each a real
`omnode-code` (or `omnode-code-test overload LIMIT` / `uncertain`, the same
program with a test hook) and the fake server: the full four-objective run
followed only through deltas across a 1.5 s disconnect (no version gaps; the
job events equal the `CWE` lines); resync to a snapshot for another
incarnation or an impossible `since`; stale, invalid, other-incarnation,
committed and duplicate commands (a duplicate pause carries the pause's
original version, though the pause moved the view on before its ack); pause
holding grants for 4 s and resume;
cancel and redirect of an objective whose inference is in flight; a budget
of 2 turns; admission limit 1 with refusals visible, a command committed and
the run completing; a worker killed while assigned a replace; the creator
killed with SIGKILL (the view exits with it, the next incarnation replays
both commands, answers the old id as duplicate with its original version,
and old clients resync). `omnode-op` usage errors exit 2.

Each change below is built into its own copy of the programs and run on one
scenario; the named check must fail. The same copy with no change runs every
scenario first and must pass all of them, else the mutant runs are void.

| Change | Check that fails |
| --- | --- |
| staleness not checked | `cmd-stale-409` |
| committed ids not looked up | `cmd-duplicate-ack` |
| OPER not replayed at restart | `crash-oper-replayed` |
| no uncertain event | `uncertain-event` |
| delta starts one event late | `resync-delta-from-0` |
| incarnation not checked | `cmd-other-incarnation` |
| pause recorded but not applied | `cmd-paused-holds` |
| redirect ignored when the cancelled job returns | `redirect-run-passes` |
| budget ignored | `budget-ends-12` |
| refusals not counted | `overload-refusals-visible` |
| acknowledgement carries the version current after acting | `cmd-pause-duplicate-version` |
| view process outlives its creator | `crash-view-exits-with-creator` |

## Release lifecycle and durable results (DRA-292)

Status: IMPLEMENTED in `release.om` (the lifecycle program `release`),
`journal.om` (RESULT records), `code.om`, `auth.om` and `op.om`; exercised on
native Linux AArch64 by `tests/release-accept.py fake`, which answers with the
recorded round40 turns only. The same driver in `live` mode runs every
scenario against the own model (aien-train `ollm serve`, or `gserve` on the
GB10 inside an authorized window); a fake run is host regression, not model
qualification. Not QUALIFIED and not DEPLOYED.

```sh
# from the checkout root: release compiles itself first, then the six programs
{ printf 'om2\n'; cat om/tls/sha2.om seed/node/release.om; } | seed/out/omc > build/node/release
chmod +x build/node/release
build/node/release build build/node            # BUILD_OK name bytes sha256, six programs
python3 seed/node/tests/release-accept.py fake $PWD/build/node OLDBIN OMC40 ROUND40 build/node/rel
OLLM=/abs/path/ollm VERB=serve CK=... MERGES=... PORT=18294 \
  python3 seed/node/tests/release-accept.py live $PWD/build/node OLDBIN OMC40 ROUND40 build/node/rel
```

The acceptance driver runs `BUILD/release`, so BUILD must hold it.

OLDBIN holds `infer`, `tool` and `code-main` built from the DRA-290 tree
(git 79894168), the reader before OPER and RESULT.

### Lifecycle

`release` (`release.om` composed after `om/tls/sha2.om` for SHA-256) is the
whole lifecycle; no shell remains. Errors are one `release: MESSAGE` line on
stderr with exit 2 for usage, an unknown command or port 18091, 3 for a
process in the wrong state, 1 for any other failure.

| Command | Effect |
| --- | --- |
| `build OUT` | from the checkout root (refuses, 2, without `seed/out/omc`): compose and compile the six programs with this checkout's `seed/out/omc`; two builds are byte-identical |
| `serve STATE PORT OLLM VERB CK MERGES` | start the own-model server; waits for its PORT line |
| `start STATE BIN OMC PORT VIEW` | start `omnode-code` on STATE (`root/`, `work/`, `journal/`, `objs.txt`); BIN must be a directory; refuses (3) while `node.pid` is alive |
| `health STATE` | the model's `GET /health` and the node's view; 0 when both answer |
| `stop STATE` | pause (op 1), wait until nothing runs or is in review (at most 900 s), SIGTERM; `view-at-stop.json` |
| `restore STATE` | start again on the same journal (incarnation + 1), then resume (op 2) |
| `unserve STATE` | stop the model server |
| `snapshot STATE SNAP` | copy `root/`, `work/` and `journal/` into SNAP (each must not exist there); refuses (3) while `node.pid` is alive |
| `rollback STATE SNAP` | replace STATE's `root/`, `work/` and `journal/` with SNAP's copies (all three must exist first); refuses (3) while `node.pid` is alive |

`snapshot` and `rollback` copy directories, regular files (bytes, permission
bits, each file synced) and symbolic links (as links, never followed); any
other file type, or a tree deeper than 64, fails (1) naming the directory and
the errno. They print `snapshot SNAP files F dirs D links L bytes B` (or
`rollback STATE ...`).

Every program `release` starts gets an empty environment and no PATH search
(`execprog`): OLLM, BIN and OMC are paths. Host tools it runs that are not
compiled by `build`: the own-model server OLLM (serve) and `seed/out/omc`
(build). It needs no `sh`, `date`, `sha256sum`, `grep`, `cp` or `tail`.

The journal's lock is the one active authority: a second `omnode-code` on
the same journal exits 50 (30 + 20, fenced) and changes nothing.

Cutover: `stop`, `snapshot`, `restore` with the new BIN. Reversal: `stop`,
`rollback`, `start` with the old BIN. A reader refuses record types newer
than it knows (24, exit 54) before writing anything, so the DRA-290 build
refuses a journal that holds OPER (9) or RESULT (10) and leaves it
unchanged; rolling back therefore needs the snapshot taken before the new
build ran. `journal-rollback-from-snapshot` runs exactly this through
`release snapshot` and `release rollback`.

### Durable results

When an objective ends, `cw_end` appends RESULT (type 10: word 3 the
objective, 4 the result, 5 its turns) before the result is printed. On a
restart an objective with a RESULT is reported again (`CWO` with the same
result and turns) and never resumed: a failure is final, as in DRA-290,
and an objective that ended UNKNOWN (21) cannot issue its effect again. The
journal refuses a second RESULT for an objective, result 0 and an index
past 63 (25) before writing. A result the journal refused is still printed;
that objective resumes after a restart.

An inference worker that dies while it holds a job: inference is class 2
(no external effect), so `au_lost` records it not performed (DONE how 6),
as recovery does at a restart, and the objective asks again; only class 1
and 3 effects stay UNKNOWN. The uncertain-effect test hook kills a worker
only after the job's START is durable: a job is assigned before its
worker's proposal is decided and journaled, and the first acceptance run
killed one holding ADMIT only. That window depends on worker timing, so no
mutant of the guard is killed deterministically; `uncertain-start-durable`
fails whenever it is hit.

### Acceptance and controls

`release-accept.py` runs twelve scenarios on the real programs: the full
four-objective run (prompts and model texts equal the recording, one START
per operation, independent review, results durable across a rerun with no
model request), the lifecycle (start, health, stop with jobs ready, restore,
finish), the creator killed after a replace (no second effect), a conflicting
write after the read (15, the other write kept), a dead inference worker
(rerun), an uncertain replace (21, final after restart), cancel of a running
inference, stale, burst and duplicate commands, the server down (16), a
second authority, journal compatibility in both directions, and address-space
caps from the measured peak (each failing cap explicit with a consistent
journal, then a passing one). Each prints MEASURED latency, RSS and seconds.

A resumed objective reads the file it edited before the restart, a prompt no
recording holds: in fake mode the three checks that need it
(`restart-resumed-completes`, `journal-forward-completes`,
`journal-rollback-completes`) are NOT_RUN, naming the prompt; any other end
fails them. Live mode answers it and requires PASS. The driver exits 0 only
when every check passed, 3 when none failed but some were NOT_RUN, 1 when
one failed.

| Change | Check that fails |
| --- | --- |
| RESULT not journaled | `full-results-durable` |
| journaled RESULT not reported at restart | `full-results-durable` |
| lost inference left UNKNOWN | `worker-death-rerun` |
| second RESULT accepted (journal.om) | journal gate case 16 (exit 173) |
| second RESULT accepted (Lean model) | `second_refused`, `apply_keeps` no longer prove |

`proofs/Result.lean` models `jn_rapply`, the restart decision of `cw_run` and
`au_lost` in Lean 4 core (checked with Lean 4.35.0; every theorem depends on
`propext` only): an applied RESULT is never replaced, a second one for the
objective is refused, every later replay keeps it so the objective is never
resumed, and only a class-2 lost action is recorded not performed. The proof
covers the model; its correspondence to the `.om` code is by reading.

### Release gate

`tests/release-gate.om` checks in Omega that `release stop` makes a durable
pause before it drains and stops the node. It is composed after the JSON
reader and the driver library and needs a release build (`release build`):

```
{ printf 'om2\n'; cat seed/json/json.om seed/node/tests/drv.om seed/node/tests/release-gate.om; } | seed/out/omc > release-gate
release-gate BUILD OMC40 OUT
```

BUILD, OMC40 and OUT are absolute. The gate removes and recreates
`OUT/release-gate.d` and keeps it afterwards. It holds the state with two
objectives and an empty root, an empty fake-serve map, so every model request
gets 404 after 4000 ms and the objective ends 16, and the start and stop output.
The gate starts `fake-serve` and then runs `release start`. It waits for the
first `CWE` job event in `run.out`, while objective 0's inference is in flight
and objective 1 has not run yet. Then it runs `release stop` and checks:

| Check | Passes when |
| --- | --- |
| `stop-rc` | the stop exits 0 (the detail shows its first stderr line) |
| `stop-journal-pause` | the journal holds a PAUSE with word 3 = 1, then an OPER of op 1 and no START after it |
| `stop-view-paused` | `view-at-stop.json` has `authority.paused` 1 and `queue.running` 0 |
| `stop-node-gone` | the pid in `node.pid` no longer exists |

It prints `PASS|FAIL NAME DETAIL` for each check, then `RELGATE pass=P fail=F`.
It exits 0 when nothing failed, 1 when a check failed, and 2 for bad usage. At
the end it sends SIGKILL to the node's process group and to `fake-serve`. On the
real build all four checks pass in about 4 s. The mutant control is a `stop`
that skips the pause (`if ne rl_post rlone 0` replaced by `if false`). Against
it the gate fails `stop-rc` (`release: the node exited while stopping`),
`stop-journal-pause` (`pause_at=none`) and `stop-view-paused`
(`view-at-stop.json` missing, -2), and exits 1.
