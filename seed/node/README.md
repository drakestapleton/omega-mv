# Omega Node shared-memory transport, epoch pool, worker supervision, scheduling, authority, journal and coding workflow

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
| `sched.om` | subscriptions, dependency wake-ups, bounded admission and review, job loss handling (DRA-287); resource requests and the selection policy (P-DRA-14) |
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
| `super.om`: `iv = interval` to `iv = long 0`, run with `idle` (workers spin) | 138 |

## Resource-aware selection (P-DRA-14)

Owner: the adaptive scheduling lane, [P-DRA-14](https://linear.app/drake-stapleton/project/aien-adaptive-scheduling-feasible-work-and-fair-progress-f20e588c68cd)
(DRA-395 to DRA-399). It owns selection policy, fairness, reservation and
ranking in `sched.om` and `schedpol-test.om`; transport, pool, supervision,
authority, journal and the workflow stay with their DRA-286..290 owners.
There is one scheduler: these are policies of `sched_dispatch`, not a second
dispatcher.

Status: IMPLEMENTED: resource requests, capacity admission and policy 0, FIFO
head-of-line, which reproduces the stop rule of the reference pump (DRA-395);
policy 1, fair fitting with reservation, admission tickets and leases, the
default (DRA-396); policy 2, goal-aware ranking with coalesced rescoring and
versioned proposals (DRA-397). The head-of-line regression fails under policy
0 and passes under policies 1 and 2.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/node/schedpol-test.om > build/node/schedpol-composed.om
cmp build/node/schedpol-composed.om seed/node/schedpol-gate.om
seed/out/omc < seed/node/schedpol-gate.om > build/node/schedpol-gate
chmod +x build/node/schedpol-gate
timeout 300 build/node/schedpol-gate            # policy 1: exit 0
timeout 300 build/node/schedpol-gate goal       # policy 2: exit 0
timeout 300 build/node/schedpol-gate fifo       # policy 0: exit 11, the blocked head
timeout 300 build/node/schedpol-gate noreserve  # no reservation: exit 61, starvation
```

### Reference pump and ownership

aien-dev/aien-sovereign-core-mv at `dffdbd195edcbe1ec3bd2fa255355b15c530f31e`,
`crates/spark-harness/src/scheduler/core.rs` (blob `32c3f431b58c`) `Core::pump`
fills a bounded ready queue in task-id order (lines 584-596), then dispatches
from its head while `PermitPool::try_acquire` succeeds (598-602); the first
head that does not fit ends the pump. A request over the limits is refused at
registration (`ExceedsCapacity`, 654-655 with `permits.rs` 51-54).

That pump is reference-only, not deployed and not yet superseded:
- `scheduler/mod.rs` (blob `001db62c4f4a`) says it is opt-in (`ProvisionalConfig::enabled` false by default) and that no spark-harness API or MCP tool uses it.
- Its only consumer in that repository is the optional `aien-runtime` feature `provisional-prep` and that crate's tests.
- The installed `~/.local/bin/spark-harness` on the Spark (sha256 `9fe2941155ca…`, built 2026-09-18) offers `test`, `mcp`, `validate` and `eval` and contains no provisional-scheduler code; no spark-harness process runs.

`sched.om` becomes the forward owner when this stack merges and DRA-292
deploys it. Until then neither scheduler dispatches live hive work.

Call graph of the Omega side (one creator calls everything):

| Entry | Callers |
| --- | --- |
| `sched_dispatch` | `sched_step` (`code.om` `cw_drive`, tests), `sched_publish` (`code.om` `cw_issue`), `sched_pause` (`auth_pause`) |
| `sched_admit`, `sched_admitr` | `jn_admit` (`journal.om`, from `cw_issue`), the readmission in `jn_recover` |
| `sched_collect`, `sched_lost` | `sched_step`, `sched_stop` |
| `sched_cancel`, `sched_review` | `auth_cancel`, `jn_release` |
| `sched_wjob`, `sched_wdone` | the worker loops (`code.om` `cw_worker`, `cw_job`) |

The coding workflow keeps one inference in flight itself (`cw_plan`), always
starting with the lowest-numbered objective that needs a turn, above the
scheduler, which sees every job as one worker and no resource.

### Resources and policy 0

A request is one ulong of four 16-bit counts: kind 0 CPU slots, 1 memory MiB,
2 inference slots, 3 caller-defined. Capacities default to 65535 of each, so
callers that declare nothing (`sched_admit`) always pass their own fit check
and are never refused for resources; under policy 0 they can still wait
behind a resource-blocked head. A job takes its whole need when it is
assigned and gives it back when its worker reports done (even while its
result waits for review room) or is reaped. Every job also needs one idle
live worker. A capacity is never set below the current use or below one
admitted job's need.

One behaviour changes for every caller: DRA-287 assigned ready jobs in slot
order, which is an accident of which slot was free; selection now follows a
policy. Phase F below is the case that differs: a job admitted first into a
lower slot but made ready later by a publication used to be assigned first;
under policy 0 the job that became ready first is. No consumer in this
directory depends on slot order (the DRA-287, DRA-288, DRA-289 gates and the
DRA-290 unit checks pass unchanged).

Policy 0 serves the ready job that became ready first, if it fits; when it
does not, nothing is assigned. That is the stop rule of the reference pump
(598-602): a head that does not fit holds back every later job. Its queue is
not reproduced. The pump batches newly eligible tasks in task-id order into
a queue of `queue_capacity`, so an eligible task can be left outside it
(scenario b of the Rust reproduction); here every admitted job is in the
table and ready order is the order of becoming ready. The bounded-queue
exclusion is therefore evidenced for Rust only.

| Function | Contract |
| --- | --- |
| `sched_admitr id deps flags req` | `sched_admit` with a resource request; -8 when a kind exceeds its capacity (counted, never queued). |
| `sched_cap caps` | Set every capacity; -8 and no change when a kind would fall below its use or below one admitted job's need. |
| `sched_policy p win db by ttl` | Policy 0, 1 or 2, candidate window 1..64 slots, dispatch budget 1..64 per event, bypass budget 1..65535, ticket lifetime 1..1000000 dispatch events; -7 out of range. |
| `sched_stat i` | Counters 0..15 (10 tickets issued, 11 tickets lapsed, 12 leases overdue), capacity 16..19, use 20..23, policy words 24..31 (policy, window, budget, bypass budget, cursor, reserved slot + 1, tickets held, ticket lifetime), goal counters 32..40 (DRA-397). |

Admission order (`sjarr`) and ready order (`sjrdy`) are logical counters, so
selection never reads the clock.

### Regression and controls

`schedpol-test.om` checks after every creator step that each kind's use is at
most its capacity and equals the needs of the running jobs that hold it, and
that every running job whose worker has not reported done holds its need.

| Phase | Scenario | Exit when it fails |
| --- | --- | --- |
| C | requests over CPU, memory or inference capacity refused (-8) and counted; lowering a capacity below an admitted need, or below the use of two running jobs that each fit it alone, refused with nothing changed | 30..41, 130..134 |
| D | 12 jobs with mixed needs on 3 workers, capacity 4 CPU, 1024 MiB, 1 inference: each runs once, all resources free at the end | 42..48 |
| V | review limit 1: both 1-CPU jobs finish, one result waits for review room, yet both CPUs are free and a 2-CPU job runs | 120..126 |
| F | order between a job admitted first but made ready later by a publication (x) and one ready earlier (y): policy 0 serves y (ready order), policy 1 serves x (admission age) | 50..57 |
| A | blocked head: a (3 CPU) runs, b (2 CPU) cannot fit, c (1 CPU) fits | 11 with the witness line |
| B | a second head-of-line case after the pump's queue-of-two scenario: a runs, b and d (2 CPU) wait, e (1 CPU) fits | 21 with the witness line |

A and B do not fail on a timeout alone. When the fitting job has not run
within 400 ms, the test checks, with no step in between, that a is running
and unfinished and holds its need, that the head is ready and does not fit,
that the job behind it is ready and fits, that a live worker is idle and that
dispatch stopped at the head; then it prints the witness and the phase
returns 11 (21). Both phases always run; the first failure is the exit.
Under policy 0 (`fifo`) the gate passes C, D, V and F and exits 11:

```
schedpol hol witness head=20050 fits_behind=30050 free_cpu=1 idle_worker=1 hol_stops=40
schedpol hol witness head=20050 fits_behind=50050 free_cpu=1 idle_worker=1 hol_stops=40
```

This is the block the Rust pump shows; its reproduction (test source,
command, output) is kept in `evidence/node-schedpol/rust-reference.*.json`.

| Change to `sched.om` | Expected exit |
| --- | --- |
| `if not sp_feas req` to `if false` (impossible requests admitted) | 31 |
| the `lt sp_need caps k get suse k` check of `sched_cap` made `if false` (capacity below use accepted) | 131 |
| `sp_take j` deleted from `sp_start` (running jobs hold nothing) | 130 |
| `sp_give j` deleted from `sched_collect` (resources never returned) | 133 |
| `sp_give j` moved after the review-room check in `sched_collect` (release waits for review) | 122 |
| `if gt sp_need req k a` to `if false` in `sp_fits` (capacity ignored) | 44 |
| `sp_ready j` in `sched_publish` to `put sjst j 2` (ready order not stamped; a policy-0 property, run with `fifo`) | 54 |

### Policy 1: fair fitting with reservation (DRA-396)

Policy 1 is the default; policy 0 stays as the FIFO baseline for the
DRA-399 comparison. Both are arms of one `sched_dispatch`.

Each pick reads the reserved slot, if any, and otherwise scans at most
`win` slots (default 64) from a cursor that persists across picks and
dispatch events. After every window scan the cursor moves on by `win`, so
consecutive scans cover consecutive windows, also when one event picks
several times, and every slot is examined within ceil(64/`win`) window
scans. A pick that takes the reserved job scans no window. Among
the examined ready jobs the pick takes the one admitted first (`sjarr`:
unique, so no ties) that fits. At most `db` jobs are assigned per event.
After each event one pass over the table counts bypasses and picks a
reservation (64 maintenance reads). Waiting age is the admission
order, kept when a rerunnable job goes back to ready after its worker died.
Under policy 1 phase F serves the job admitted first.

A ready job admitted before the youngest job assigned in an event was
bypassed once. With no reservation, the oldest ready job at the bypass
budget `by` (default 4) is reserved. The reserved job is offered first;
while it does not fit, every other pick may use, of each kind, only the free
capacity beyond what the reserved job needs. Of each kind,
min(free, reserved need) therefore never falls, and the reserved job runs as
soon as running work has released enough. Assignment or cancellation of the
reserved job ends the reservation.

Liveness rests on these assumptions: every running job ends (completes, or
its lease is enforced by the authority); at least one worker stays live;
results in review are eventually reviewed, so a worker holding a finished
result while review is full is eventually freed (phase Z shows the reserved
job waiting on review, then running); dispatch is eventually unpaused and
keeps getting opportunities while ready jobs remain (every `sched_step`
collects, then dispatches, so the creator loop must keep stepping, also
after a window scan that found nothing and with no running job left to
release anything); a job that is safe to rerun is not lost to worker deaths
forever (each attempt ending is not enough: some attempt must settle); no
request exceeds capacity (refused at admission, -8). Under them a reserved
job runs once the jobs running at its reservation have finished and a
worker is free, and each ready job is examined within ceil(64/`win`) window
scans. There is one reservation at a time, and it goes to the oldest job at
the bypass budget. A job at the budget therefore waits only for the
reservations of jobs admitted before it, a finite set; later arrivals never
take the reservation first. Workers are not a resource kind: the reserved
job is offered first at every pick, so it takes the first idle worker once
it fits. This is an argument from the source under the stated assumptions;
the phases exercise the supplied finite workloads (phase S among them) and
are not a proof for arbitrary workloads.

Admission tickets. Room is the smaller of the admission headroom and the free
table slots: a job in review or UNKNOWN keeps its slot, so a table full of
unreviewed results refuses admission even below the limit. `sched_room id`
refuses without room and gives the refused caller a ticket. While tickets
are held only the first holder may enter, whatever the room; a new caller
takes a ticket behind them. `sched_admitr` asks it; so does `jn_admit`,
after its duplicate check and before it journals ADMIT, and a true answer
guarantees the slot (one creator, no other admission in between). Every
ask by a ticket holder renews its ticket, whether it is refused or told
yes (a caller with room and no ticket gets none). A ticket not asked about
for more than `ttl` dispatch events (default 1000) lapses: asked at event
e, it survives while e + `ttl` is at least the current event count. A
caller that went away therefore blocks later holders for at most `ttl`
events; a paused dispatch counts no events, so that block lasts until
dispatch resumes. At most 64 tickets are held, and a caller refused with
the line full holds none.

Leases. `sched_lease j ns` gives a waiting or ready job a lease counted from
its next assignment; on a running job it replaces the lease, measured from
now. `ns` is at most 2^50 ns (about 13 days; Wolfram
`UnitConvert[Quantity[2^50,"Nanoseconds"],"Days"]` -> 13.03 days): a larger
value is refused (-7) and nothing changes. The monotonic clock is below
2^63, so every deadline, clock plus `ns`, stays below 2^63 + 2^50 < 2^64:
it never wraps into the past or onto 0, the no-deadline value. Assignment
and reassignment use the stored, already checked duration.
`sched_overdue` reports a running job past its lease whose worker has not
reported done, once. The authority then cancels or kills it, and the release
follows from the worker's report or the reap. The lease is a clock reading
used for reporting only; selection reads logical counters.

| Function | Contract |
| --- | --- |
| `sched_room id` | May id be admitted now: room is min(admission headroom, free slots); while tickets are held only the first holder may enter. A refused caller gets or keeps a ticket; every ask by a holder renews its ticket. |
| `sched_lease j ns` | Lease for a waiting, ready or running job, from its next assignment (running: from now); 0 removes it; -3 for a slot not waiting, ready or running; -7 for ns above 2^50; a refusal changes nothing. |
| `sched_overdue` | Slot of a running, unfinished job past its lease, reported once; 64 when none. |

`schedpol-gate` takes one optional argument: `fifo` runs every phase under
policy 0, `noreserve` sets the bypass budget to 65535 (no reservation in
practice). Each step also checks the bounds since the last step. An event
makes at most one pick more than it assigns, so candidate reads are at most
(assigned + events) × (`win` + 1), the reserved probe included, or × 64
under policy 0, exit 9; maintenance reads at most 64 per event, exit 14; the
cursor moved by exactly `win` per window scan (mod 64), exit 15. The cursor
check is the traversal witness. It runs at every step of every phase and
around the dispatches that publication (phase F) and resume (phase Z) cause
outside a step. These checks read the scheduler's own counters, so they
bound the work the counters record; they are not an independent trace of
which slots were read.

| Phase | Scenario | Exit when it fails |
| --- | --- | --- |
| S | three workers, 4 CPU; 1-CPU jobs start staggered and each one finishing is replaced, so the CPUs are never all free at once; big (4 CPU) arrives: it is reserved and runs | 61 never ran (the `noreserve` control), 62..66 |
| Q | admission limit 2: X then Y refused hold tickets; with room for one, Y is refused and X admitted; Y enters later; a ticket not asked about lapses, so a new caller enters | 70..80 |
| L | 200 ms lease on a 3 s job not safe to rerun: the deadline is at least 200 ms after admission and the report comes at or after it, once; worker killed, job UNKNOWN, CPU free. A rerunnable job killed the same way keeps its admission age and completes | 81..89, 140..145 |
| R | the reserved job is cancelled: freed with no effect, reservation cleared | 90..97 |
| W | window 4, budget 2, two workers (an event may pick twice), 12 ready jobs in slots 0..11: every pick reads at most 5 slots, every scan moves the cursor on by 4, and all 12 run | 9, 15, 101..103 |
| T | limit 3 held by two short jobs and one waiting on a topic nobody publishes, three ticket holders; with exactly two openings the second holder and a new caller are refused, the first two holders enter in order; the waiting job is cancelled, and with three openings the new caller (now a holder) waits for the holder ahead | 104..109 |
| X | every slot holds a job in review, admission limit not reached: a new caller is refused and holds a ticket; one review frees one slot, which goes to the first holder | 190..194 |
| Z | review limit 1 and full; a reserved job is ready at every step for 600 ms while the workers hold finished results, and all CPU is free at the end of that interval; reviewing lets it run | 195..199 |
| M | lease bounds: 2^50 + 1 and 2^64 - 1 refused (-7) on a waiting and on a running job with lease and deadline unchanged; 2^50 accepted on both, the running job's deadline ahead of the clock and nothing overdue; a running renewal to 2^49 puts the deadline between clock + 2^49 read just before and just after the call; the job completes | 200..207 |
| N | admission limit 1, ticket lifetime 2: X, refused at event e, asks at e + 1 and is told yes; at e + 3 its renewed ticket still holds and newcomer Y is refused; at e + 4 it lapses (one lapse) and Y is admitted | 210..212 |
| U | four idle workers, dispatch budget 2, six ready 1-CPU jobs on 4 CPU: one dispatch assigns exactly 2; all six complete | 220, 221 |

Phases S to U run after A and B, so under `fifo` the gate stops at 11.
`journal-gate` case 16 checks `jn_admit` at the admission limit: a duplicate
id is refused as a duplicate and takes no ticket (170..173). Case 17 checks
a full table below the limit: 64 jobs put in UNKNOWN directly (synthetic
occupancy, the state a worker loss leaves a job not safe to rerun in;
nothing is spawned and no recovery runs). A new id is refused with a
ticket, the journal does not grow, and the independent journal reader finds
no ADMIT for it; after one slot is settled the same id is admitted and
journaled once (174..177).

| Change | Expected exit (derived from the check it trips) |
| --- | --- |
| cursor never moves (`put scpol 4 …` deleted from `sp_fair`) | 15: the first window scan in W leaves the cursor where it was |
| cursor moves by 1 instead of `win` (`rem add cur win 64` to `rem add cur 1 64`) | 15 |
| tickets ignored (`if eq get scpol 6 0` to `if true` in `sched_room`) | 75 |
| holders below the room may enter (`if eq t 0` to `if lt t room`) | 105 |
| room ignores free slots (`if lt fs room` to `if false`) | 191 |
| no hold-back for the reserved job (`rq = get sjneed rj` to `rq = ulong 0`) | 61 |
| never reserve (`put scpol 5 add o 1` deleted) | 61 |
| lease never reported (`if ge now d` to `if false`) | 82 |
| lease reported 100 ms early (`if ge now d` to `if ge add now 100000000 d`) | 83 |
| cancel keeps the reservation | 94 |
| window ignored (`for i ulong win` to `for i ulong 64` in `sp_fair`) | 9 |
| tickets never lapse | 80 |
| `jn_admit` asks for room before the duplicate check (`journal.om`) | 170 (`journal-gate`) |
| `jn_admit` skips the room check (`journal.om`) | 173 (`journal-gate`): case 16 journals ADMIT for the refused id, so its later admission is refused as a duplicate |
| the same, with case 16 not run | 175 (`journal-gate`): case 17's refused admission grows the journal |
| FIFO counts 3 per slot read (`sp_fifo`), run with `fifo` | 9: the first FIFO pick reads more than 64 per pick allows |
| lease duration unbounded (the 2^50 check deleted from `sched_lease`) | 200: 2^50 + 1 is accepted on waiting job w |
| lease stored before the bound check | 200: the refusal returns -7 but w's lease is no longer 0 |
| running renewal is a no-op (the `if eq s 3` deadline block deleted from `sched_lease`) | 206: the deadline stays near assignment + 2^50, above clock + 2^49 |
| a successful ask does not renew the head holder's ticket | 211: X's ticket lapses at e + 3 and newcomer Y is admitted |
| dispatch budget ignored (`for i ulong get scpol 2` to `for i ulong 64`) | 220: one dispatch assigns 4 |

### Policy 2: goal-aware ranking and replanning (DRA-397)

Policy 2 is policy 1 with a different order among the examined jobs that
fit. The reservation, the hold-back, feasibility and the bypass budget come
first, unchanged, so ranking cannot starve old work: a job ranked low is
bypassed, reaches the bypass budget and is reserved like under policy 1.
Authority checks stay where they are (`sched_pause`, `auth.om`). Policy 1
stays the default until DRA-399's matched comparison shows otherwise.

Inputs: `sched_goal j pro est unc` declares, for a waiting or ready job, the
topics its completion will publish (`pro`), its work estimate in ms (`est`,
declared, or derived by the caller from its own measurements) and that
estimate's uncertainty in ms (`unc`, recorded, not used to rank). They are
estimates: they order ready jobs and nothing else. Nothing is learned.

Key, in order: larger unblock value, smaller estimate, older admission
(`sjarr`, unique, so there are no ties). The unblock value of a ready job,
in jobs, is the number of waiting jobs whose deps meet its declared topics
(depth 1) plus the waiting jobs whose deps meet the topics those declare
(depth 2), each counted once. Lookahead stops at depth 2: at most 128 slot
reads per job scored plus 64 per rescoring (the pass that finds ready
jobs), counted in `sched_stat 38` and checked at every step (exit 8). A
proposal adds one candidate read per pick, so under policy 2 a pick reads
at most `win` + 2 slots (exit 9).

Replanning. Every committed change that can alter a value bumps the graph
version: a job becomes ready (admission, publication, rerun after a worker
death), a waiting job is admitted, a waiting or ready job is cancelled, a
declaration changes. While the version is not exhausted, values are
recomputed only at a policy-2 ranking pass whose version differs from the
last scoring, once however many bumps came before it. Bumps therefore
coalesce and none is lost, because the version is a counter, not a flag. A
pick that takes the reserved job ranks nothing and scores nothing.
Completions, failures, resource releases and lease expiry replan without
rescoring: every step collects, then dispatches with the current values, and
none of those events changes a value. No step waits for other workers and no
model is called.

Proposals. `sched_propose id v` lets an outside planner or an operator put
the ready job whose id is `id` first, computed at graph version `v`
(`sched_version`). The proposal names the job, not its table slot. It is
refused until the scheduler has an incarnation and once its version is
exhausted (-6), when `v` is not current (-9, counted stale), when no ready
job or more than one has that id (-3) or when the job does not fit beside
the reservation (-8). It is used once, at the next pick, after the
reservation, and only if the version is still `v` and not exhausted, the
job is still ready and it still fits; otherwise it is dropped and counted
stale. Within one scheduler every admission, cancellation of a waiting or
ready job and readiness bumps the version, so a job that leaves the ready
state and a new occupant of its slot are both seen. Across schedulers the
version carries the incarnation: `sched_incarnate n` (once, after
`sched_new`, n in 1..2^24 - 1, distinct per scheduler; DRA-398 uses the
journal fence) makes the version n × 2^40 plus the bumps since. The last
scoring stays below that, so jobs admitted or declared before a late
incarnation are rescored at the next ranking pass.
The bump that would reach 2^40 does not carry into the next incarnation's
range: the version stays and is exhausted, proposals are refused for the
rest of that scheduler and every ranking pass rescores, since the version no
longer tells whether the inputs moved.

| Function | Contract |
| --- | --- |
| `sched_goal j pro est unc` | Declare topics, estimate (ms) and its uncertainty (ms) for a waiting or ready job; 0 or -3. |
| `sched_version` | The graph version. It moves on admission, a job becoming ready, cancellation and `sched_goal`, and on nothing else (not on completions, releases, lease expiry, `sched_cap` or `sched_policy`); it versions the inputs of ranking and proposals, not the whole scheduler state. |
| `sched_incarnate n` | Set the incarnation (1..2^24 - 1), once: the version becomes n × 2^40, a pending proposal is dropped, values are rescored at the next ranking pass and proposals are accepted; 0, or -7 (out of range, already set, or exhausted). |
| `sched_propose id v` | Propose the ready job with id `id` at version v; 0, -6 no incarnation or exhausted, -9 stale, -3 no ready job or more than one has that id, -8 does not fit beside the reservation, -7 not policy 2. |
| `sched_stat 32..41` | Rescorings, jobs scored, version bumps, proposals accepted, stale, refused, value slot reads, proposals used; 40 the graph version; 41 the proposal state (0 no incarnation, 1 accepting, 2 exhausted). |

`schedpol-gate goal` runs every phase under policy 2 (exit 0). Phases G, H,
P, I, R2, X, L and K set policy 2 themselves and run after W in the default and
`goal` modes; the `fifo` and `noreserve` controls stop at their earlier
expected failures (11 and 61), so they never reach these phases. Every
dispatch a phase causes outside a creator step (resume, publication) is
bracketed by the same step bounds.

| Phase | Scenario | Exit when it fails |
| --- | --- | --- |
| G | one worker, bypass budget 4, ten jobs admitted while paused: x (value 0), z (unblocks d: 1), a (unblocks b, which unblocks c: 2), f (unblocks g1..g3: 3); decisions made before each finished job publishes. Order f a z b x d c g1 g2 g3: useful work first, x reserved after four bypasses. Run twice: identical decisions | 150, 151 first run, 152 second |
| H | four graph changes while paused, one rescoring at the first pick; a completion with nothing published, no rescoring; a publication readying two jobs, one rescoring; cancelling a waiting job is one change | 160..166 |
| P | a stale proposal is refused and counted; one naming an id with no ready job is refused; a current one is used over a higher-ranked job; one made stale by a later change is rejected at use and counted; -7 outside policy 2 | 170..178 |
| I | scheduler 1 (incarnation 1) hands out a version for job a in slot 0; scheduler 2 (incarnation 2) puts job b in slot 0 with as many bumps: the old version is stale, a's id names no job, b's proposal is accepted, incarnation 0 is refused | 184, 185 |
| R2 | 5 CPU, bypass budget 1: with B (4 CPU) reserved, x (2 CPU) is refused beside it; cancelling B clears the reservation and x is accepted; an event with no idle worker reserves B2 and keeps the proposal; at the next pick x no longer fits beside B2, so the proposal is dropped and counted stale and x stays ready; once B2 fits, y (1 CPU) is accepted beside it and at the next event B2 runs first, then y is used, and x, bypassed by y, becomes the reservation | 186..189, 179 |
| X | no incarnation: a proposal is refused; a second incarnation is refused; after the first a proposal is accepted and used. At the last revision of incarnation 5 a proposal is accepted, the next bump exhausts the version instead of reaching incarnation 6, proposals are refused, the pending one is dropped at use and every pick rescores. Two ready jobs sharing an id: a proposal naming it is refused | 120..127 |
| L | one worker, paused: an older unrelated job, a younger producer declaring a topic and a job waiting on it are admitted and declared, then the scheduler incarnates; at resume the producer runs | 128 |
| K | the key on two slots: value before estimate before age; outside policy 2 age only | 180..183 |

| Change to `sched.om` | Expected exit (derived from the check it trips) |
| --- | --- |
| goal off (`if goal` to `if false` in `sp_better`) | 151: x runs first |
| depth 2 ignored (its count never incremented in `sp_value`) | 151: a and z tie, z older runs second |
| rescore every pick (version check removed in `sp_rescore`) | 162 |
| becoming ready does not bump (`sp_bump` removed from `sp_ready`) | 151: b keeps value 0, x runs fourth |
| waiting admission does not bump | 160 |
| cancellation does not bump | 165 |
| proposal version unchecked at `sched_propose` | 170 |
| proposal version unchecked at use (`sp_proposal`) | 176 |
| estimate ignored in the key | 181 |
| incarnation ignored (`sched_incarnate` leaves the version at 0) | 184: both schedulers reach version 1, so the old version is current |
| proposal fit not rechecked at use (`sp_proposal`) | 189: x is used beside B2 |
| proposals accepted without an incarnation (state check removed in `sched_propose`) | 120 |
| incarnation set twice (once check removed in `sched_incarnate`) | 121 |
| version carries into the next incarnation (saturation removed in `sp_bump`) | 123: the version moves to 6 × 2^40 |
| exhausted version not checked at use (`sp_proposal`) | 125: the pending proposal still names the stuck version and is used |
| exhausted version trusted by `sp_rescore` | 126: the second pick does not rescore |
| an id shared by two ready jobs accepted (`sched_propose` takes the last) | 127 |
| incarnation marks the values scored (`sched_incarnate` sets the last scoring to the new version) | 128: the values stay 0, so the key falls to the estimate and the unrelated job (no estimate) runs |

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
64-bit words. Header: magic, format version 2, record size 128, the 4-word
objective identity, FNV-1a 64 of words 0..6. Record: type, seq (1, 2, 3, ...
without gaps), fence, 12 payload words, FNV-1a 64 of words 0..14.

| Type | Payload | Appended by |
| --- | --- | --- |
| 1 OPEN | pid, authority generation, scheduler policy version (`SPVER`) | `jn_open`, every creator incarnation |
| 2 ADMIT | job id, dependency topics, flags, resource request, table slot | `jn_admitr` (`jn_admit` with no request), before `sched_admits` |
| 3 START | operation identity, class, job id, attempt, generation | `au_decide`, after `actstart`, before the grant is published |
| 4 DONE | operation identity, outcome, job id, how (1 reported, 2 worker lost, 3 in flight at restart, 4 key present, 5 key absent, 6 no external effect) | `au_record`, `au_lost`, recovery |
| 5 RELEASE | job id, outcome (300 cancelled) | `jn_release`, before `sched_review`; `auth_cancel` |
| 6 REVOKE | new generation | `auth_revoke` |
| 7 PAUSE | 1 paused, 0 resumed | `auth_pause` |
| 8 CANCEL | job id | `auth_cancel`, before the worker is told |
| 10 | reserved for RESULT (DRA-292) | |
| 11 POLICY | policy, window, dispatch budget, bypass budget, ticket lifetime, capacities: the whole setting, the last one wins | `jn_policy`, `jn_cap`, before `sched_policy`, `sched_cap` |
| 12 GOAL | job id, topics, estimate ms, uncertainty ms | `jn_goal`, before `sched_goal` |
| 13 FAIR | dispatch event, assigned slot bitmap, bypassed slot bitmap, cursor, reserved slot + 1 | `jn_drain`, from `sched.om`'s replay ring |

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
is refused (21), never reinterpreted (a version 1 journal from before DRA-398
is refused); a different objective identity is refused (22). An OPEN whose
scheduler policy version differs from this build's `SPVER` is refused (33):
the recorded FAIR decisions belong to another selection rule. A future
format must change the version.

### Recovery

`jn_open` reads the journal into the recovery tables; `auth_recover` (after
`sched_new` and `auth_new`, before spawning workers) settles and readmits:
- A START with no DONE was in flight at the crash. Class 3 (an idempotent effect whose key `DIR/k.<op>` the effect itself creates atomically, for example with `ln`) is decided by the key: present is performed, absent is not performed and the job runs again. Class 2 (no external effect) is not performed. Class 1 is UNKNOWN and is never run again. Each gets a DONE.
- An admitted job not yet released: a performed or UNKNOWN last operation releases it with that outcome; a cancelled job is released as cancelled; any other job is admitted again, in admission order, into the table slot its ADMIT recorded, with its dependency topics, resource request, bypass count (from the FAIR records) and declared goal (GOAL).
- Before that, the scheduler's incarnation is set to the fence (`sched_incarnate`, so a proposal made for an earlier creator is stale) and the last POLICY is applied (capacities, then policy); after it, the cursor, the dispatch event count and the reservation (moved to the reserved job's slot) of the last FAIR are restored (`sched_frestore`), and only then is the replay ring attached.
- The action records (state, attempt, generation), the authority generation (above every journaled one) and the pause state are restored, so a performed or UNKNOWN operation is refused if proposed again and a paused objective stays paused.
- A restart that finds nothing in flight adds only its OPEN.

A crash between START and publishing the grant leaves a class 1 operation
UNKNOWN even though its tool never ran. That is the pessimistic side: an
effect is never repeated without proof that it did not happen.

| Function | Contract |
| --- | --- |
| `jn_open dir dn obj ms`, `jn_close` | Creator: take the lock (wait up to ms), create or check the header, cut a torn tail, read every record, append OPEN; release. |
| `auth_recover c` | Settle, release or readmit, restore authority and pause. |
| `jn_admitr id deps flags req`, `jn_admit id deps flags`, `jn_release j` | Durable admission (with or without a resource request) and release around `sched_admits` and `sched_review`. |
| `jn_policy p win db by ttl`, `jn_cap req`, `jn_goal j pro est unc` | Durable policy, capacities and goal declaration: POLICY or GOAL written first, then `sched_policy`, `sched_cap`, `sched_goal`; -5 when the journal refuses (nothing changed). |
| `jn_drain` | Write `sched.om`'s replay ring as FAIR records (also first thing in every append and in `auth_step`), so a dispatch decision is durable before any transition that follows it. |
| `jn_known id`, `jn_done_j id`, `jn_jout id`, `jn_stat i`, `jn_fence`, `jn_gen`, `jn_act k i` | Recovered state. |

Limits: no checkpoint or compaction yet; recovery replays the whole journal
and the tables hold 64 operations and 256 jobs. Inputs published to the pool
are not journaled, so a recovered job reads whatever its dependency topics
hold after the restart. The key of a class 3 effect must be created by the
effect itself, atomically and last. Scheduling state not restored: reservation
tickets (a recovered reservation starts a new ticket), policy 0's ready order
(`sjrdy`: recovered ready jobs are stamped in admission order) and proposals
(they are stale after a restart by the incarnation). The incarnation is the
fence itself: a fence past 2^24 - 1 fails recovery (31) instead of reusing
an earlier incarnation. Dependency readiness is restored: a publication
that makes waiting jobs ready leaves a readiness record, and a job it made
ready is ready again after recovery.

Replay is exact at drained points: after a successful `jn_drain`, which runs
first in every journal append and in every `auth_step`. Decisions and
readiness wait in the volatile ring until then. For authority-mediated
actions, the dispatch decision is drained durably before START and before
the action grant; assignment, worker wakeup and the worker's work before
its grant may happen before that drain. A
publication's readiness is not durable when `sched_publish` returns: a crash
before the next drain loses it, and the published artifact with it (the pool
is not journaled either), so recovery is as if the publication had not
happened: a job waiting on it waits until it is published again. A crash inside a dispatch event
recovers that event's cursor, reservation and the bypass counts of the jobs
it did not assign, and the jobs it assigned are admitted again with bypass
count 0. The dispatch event count is restored to the last journaled
decision's; events that changed nothing leave no record. The count stamps
replay records, so later records still follow the last durable one, and it
ages admission tickets; tickets are not restored, so every ticket after a
recovery is aged from the restored count.

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

### Durable scheduling policy and deterministic replay (DRA-398)

Status: IMPLEMENTED in `sched.om`, `journal.om` and `auth.om`, exercised by
`replay-gate.om` on native Linux AArch64 (evidence in the DRA-398 pull
request). Not wired into `tests/gates/` (that needs an operator); the receipt
runs it.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/journal.om seed/node/auth.om seed/node/replay-test.om > build/node/replay-composed.om
cmp build/node/replay-composed.om seed/node/replay-gate.om
seed/out/omc < seed/node/replay-gate.om > build/node/replay-gate
chmod +x build/node/replay-gate
timeout 180 build/node/replay-gate       # ends "PASS node replay"; uses build/node/rpa, rpb
```

Every input of a selection decision is journaled before it acts: the request
and table slot with ADMIT, the policy words and capacities (POLICY), the goal
declarations (GOAL). The decisions themselves are recorded as they are made:
each dispatch event that assigns a job or moves the reservation puts one
record (event, assigned and bypassed slot bitmaps, cursor, reserved slot) in
`sched.om`'s 64-record replay ring, and so does each publication that makes
waiting jobs ready (a readiness record: the current event, no assigned or
bypassed slot, the slots made ready). `jn_drain` writes the ring as FAIR
records before any other record and at every `auth_step`, so no later
transition is durable before the decision or readiness that preceded it.
Dispatch and publication refuse to run while the ring is full (counter 15;
publication returns -105 with nothing published), so nothing is lost to a
journal that cannot keep up. A window scan that assigned nothing moves only
the cursor; `jn_drain` writes one FAIR with empty bitmaps for it when the
cursor or the reservation differs from the last FAIR.

Replay refuses (25) any record that contradicts the tables, and nothing
changes: an ADMIT into a slot another unreleased job holds; a FAIR that both
decides (assigns or bypasses) and makes ready, the first FAIR of a journal
included; a decision FAIR that does not follow the last event (a readiness
record may share it); a cursor outside the table; a slot both assigned and
bypassed; an assigned, bypassed or reserved slot that does not hold a live
ready job (live: admitted, not released, not cancelled; ready: no deps, or
made ready by an earlier readiness record); a slot made ready that does not
hold a live waiting job; a reservation on a job the same record assigned.
Recovery then readmits each
unfinished job into its recorded slot (never another), makes it ready again
if a publication had, and restores its bypass count and goal. Any of these
the scheduler refuses, and a reservation that does not name a ready job,
fails the recovery (31).

The gate runs four cases (policy 1 and 2, crash after 3 and after 6 of 10
dispatch events) and four special checks:
- R, a reference creator, runs all events on journal a; C runs the first k on journal b and dies; C2 recovers journal b and runs the rest. Before event 1 the creator publishes the topic job 7001 waits on, so 7001 is ready by publication across the crash. C2's state right after recovery equals R's after event k (cursor, reserved job, slots, ids and bypass counts of ready jobs, needs, estimates, uncertainties and topics of every unfinished job, policy words with the ticket lifetime 777, capacities, bypass sum, job 7001's state and bypass count), and C plus C2 make the same decisions as R, event by event. C3 recovers journal b once more and equals R's final state. Each case also proves it tests something: a bypass count, a nonzero cursor and job 7001 ready at the boundary, a reservation during the run, a final cursor different from the boundary's.
- Mid-event crash: C' dies right after a dispatch and its PAUSE record, before the creator collects or releases the jobs it assigned (the replay workers are not stopped from finishing them). C2' has that event's cursor and reservation and the bypass counts of the jobs it did not assign; the jobs it assigned are ready again.
- Records refused: a FAIR that repeats the last event, a FAIR naming a free slot, an OPEN written under another `SPVER`, an ADMIT into a held slot (23), a FAIR assigning and bypassing one slot (24), a FAIR assigning a waiting job (26), a readiness record for a ready job (27; a valid one at the last event is accepted), a FAIR reserving a cancelled job (25), a first FAIR that both assigns and readies (28: refused, nothing changes).
- Failed journal: revoke, pause, cancel, admission, policy, capacities and goal each return their refusal and change nothing; a full ring stops dispatch (44) and publication (47).
- Fence range (29): recovery refuses fence 2^24 + 1, which a 24-bit mask would fold onto incarnation 1, and leaves the scheduler unincarnated; fence 2^24 - 1 is then accepted.

`code.om` (omega-node's, BOARD note): the inference cancel hook checks `auth_cancel`'s result before converting it, so a refusing journal leaves the job running and the hook armed (it retries); restart cleanup exits 55. `code-test unit` covers the hook with a refusing journal. `journal-test.om` cases 16 and 17 journal the CANCEL and RELEASE (16) and the RELEASE (17) that their synthetic frees used to skip, which the held-slot refusal now requires.

| Change | Expected exit (derived from the check it trips) |
| --- | --- |
| `journal.om`: ADMIT records request 0 | 53: the needs fold differs at the boundary |
| `journal.om`: POLICY words not restored | 53 |
| `journal.om`: capacities not restored | 53: `sched_new`'s 65535 per kind, the capacities word differs |
| `journal.om`: readmission takes the lowest free slot instead of the recorded one | 20: the reserved job moves from recorded slot 2 to slot 0; C2's first dispatch assigns slot 0, free in the journal, its FAIR is refused and the PAUSE after it fails (53 derived before review r2) |
| `journal.om`: FAIR bypass counts not replayed | 53 |
| `sched.om`: `sched_frestore` leaves the cursor at 0 | 53 |
| `journal.om`: POLICY restored with ticket lifetime 1000 instead of the recorded 777 | 53: the policy word differs |
| `sched.om`: publication journals no readiness record | 53: C2 readmits 7001 waiting, R has it ready at the boundary |
| `journal.om`: a replayed readiness record does not make the job ready again | 53: as above |
| `journal.om`: GOAL not restored | 73: policy 2, the waiting job's declaration |
| `journal.om`: GOAL restored without its uncertainty | 73 |
| `sched.om`: recovery keeps the event count at 0 | 20: C2's first FAIR is stamped at or before the last journaled event; its next record is refused and the PAUSE fails |
| `journal.om`: `jn_append` does not drain first | 93: the mid-event FAIR is lost |
| `journal.om`: `jn_recover` does not attach the ring | 53: R and C journal no FAIR either, so C2 recovers cursor 0 and 7001 waiting (derived 56 before review r1) |
| `journal.om`: only a journal with no FAIR attaches the ring | 56: C2's decisions are never journaled, C3 differs |
| `journal.om`: a FAIR repeating an event accepted | 96 |
| `journal.om`: a FAIR naming a free slot accepted | 96: the replay traps (index out of bounds) |
| `journal.om`: ADMIT into a held slot accepted | 23 |
| `journal.om`: a FAIR assigning and bypassing one slot accepted | 24 |
| `journal.om`: a FAIR assigning a waiting job accepted | 26 |
| `journal.om`: a readiness record for a ready job accepted | 27 |
| `journal.om`: a FAIR reserving a cancelled job accepted | 25 |
| `journal.om`: OPEN's `SPVER` not checked | 98 |
| `auth.om`: revoke ignores a refused REVOKE | 40 |
| `auth.om`: pause ignores a refused PAUSE | 41 |
| `auth.om`: cancel ignores a refused CANCEL | 42 |
| `sched.om`: dispatch ignores a full ring | 44 |
| `sched.om`: publication ignores a full ring | 44: the readiness record is written past the ring and traps (103) in the ring child, which the parent reports as 44 |
| `journal.om`: the shape check below the first-record exception (the r1 code) | 28 |
| `journal.om`: recovery masks the fence to 24 bits (the r1 code) | 29: 2^24 + 1 becomes incarnation 1 and is accepted |
| `code.om`: the cancel hook converts `auth_cancel`'s result before checking it (the r1 code) | 105 (`code-test unit`): -5 traps the conversion (CAST) |

### Policy comparison on real workers (DRA-399)

`bench-test.om` runs the same pinned workloads under four arms: policy 0
(FIFO), 1 (fair fitting, the default), 2 (goal-aware) and arm 3, policy 2
given the true durations as estimates. Arm 3 is an ORACLE upper bound, not
a policy result. The workers are real forked processes on the host's wall
clock. A worker sleeps for the milliseconds in the low four decimal digits
of its job id, then reports the outcome id + 1. The creator loop is
`sched_step` with the dispatch timed. After every step and every
publication it samples the job table, reviews finished jobs and publishes
what each declared. Every arm sees the same jobs, requests, durations,
declarations, workers (2) and capacities (4 CPU). Each job declares its
topics with `sched_goal`. Its declared estimate is the duration times 1/2,
1, 3/2 or 2, chosen by a fixed hash of its id, with the estimate itself as
the declared uncertainty, so policy 2 is never told the duration. Only arm
3 declares the true duration.

```sh
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/node/bench-test.om > build/node/bench-composed.om
cmp build/node/bench-composed.om seed/node/bench-gate.om
seed/out/omc < seed/node/bench-gate.om > build/node/bench-gate && chmod +x build/node/bench-gate
build/node/bench-gate > bench.txt   # 120 runs (6 scenarios x 4 arms x 5), ends "PASS node bench"
```

| Scenario | Workload |
| --- | --- |
| 1 blocked head | h (2 CPU, 600 ms), then H (4 CPU, 300 ms), then six 1-CPU jobs of 200 ms |
| 2 long chain | eight 1-CPU fillers of 300 ms, then a chain of six 150 ms jobs, each waiting on the topic the previous one publishes |
| 3 fan-out | six 1-CPU fillers of 300 ms, then a 100 ms root publishing a topic six 200 ms jobs wait on |
| 4 sustained arrivals | 24 jobs of 100..400 ms needing 1..3 CPU, four every 150 ms |
| 5 queue pressure | 30 jobs of 100..300 ms needing 1..2 CPU offered at once against an admission limit of 8 (tickets) |
| 6 worker failure | 12 rerunnable jobs of 150..450 ms needing 1..3 CPU; worker 0 is SIGKILLed 250 ms in while busy and not replaced |

Each run prints `bench S P R` followed by these fields:
- **makespan:** from the first admission to the last review;
- **idle eligible capacity:** the integral over time of min(idle live workers, ready jobs that fit the free capacity), in worker-microseconds;
- **dispatch time:** nanoseconds inside `sched_dispatch` from the creator loop (dispatches inside publication and resume are not timed), and the number of those calls;
- **scheduler counters:** events, candidate reads, maintenance reads, value reads;
- **reworked jobs:** jobs that returned to ready after starting;
- **reservations:** those made, and those that were contested;
- **verified jobs:** jobs reviewed with the expected outcome;
- **VmHWM:** the creator's peak resident memory;
- **waits:** ready to started, in microseconds. There is one value for each start whose job was sampled ready at least once, so a job that a rework returns to ready contributes again.

A wait is measured at the sample after the step that dispatched the job, so its resolution is one creator step (at most 1 ms of polling plus the sampling). A job that becomes ready and starts within a single creator step or publication is never sampled ready and gets no value: its wait is below that resolution. The number of such starts is the jobs plus the reworks minus the waits printed. The statistics count each of them as a wait of 0.

Every run checks:
- the capacity invariant (exit 70);
- that a new reservation goes to the oldest ready job at the bypass budget (71);
- that every job is reviewed once with its expected outcome within 20 s (72);
- setup (73..77).

Statistics are computed with Wolfram from the raw lines; the queries are quoted with the results.

#### Results, 2026-11-07 (MEASURED on a synthetic workload; not speed evidence)

There are two runs of the same binary: bench-gate sha256 `8bd6c1a7…`, built at bd57beaa with omc 5f90edea. Both ran under `flock pool-8-9.lock taskset -c 8-9 nice -n 10`; core 9 is the X925 timing core.
- **Receipt `evidence/node-schedpol/receipt.323ef72e….json`** (`schedrcpt.om`, cases-399): bench-gate PASS, and mutants 70/71/72 killed. The receipt keeps only the last 4000 bytes of stdout (repetition 4), so it is not the source of the statistics.
- **Rerun for the statistics**, 11:52:14Z to 11:57:19Z, exit 0, 120 lines, `PASS node bench`. The raw output is filed as `bench.8f28e6a5….txt` with `bench.8f28e6a5….meta.json` (commit, binary, command, times, load), in `~/handoffs/hive/sched/bench399/` next to `stats.wl`, `stats.tsv` and `relative.tsv`.

The load average was 11 to 13. `live-cpu` (core 0) sampled from 11:54:00Z to 11:57:20Z: 2 of 21 samples had a foreign running thread on 8/9, none of them the bench's. The first 106 s were not sampled.

Medians over 5 repetitions, with makespan in ms, idle eligible capacity in worker-ms and dispatch time in ns per call. Waits (ms) pool every start of the 5 repetitions.

Two wait columns are given, because the zero rule was defined after the output had been seen:
- **wait (0 rule):** unsampled starts (the "unsampled" column) count as 0;
- **sampled:** recorded waits only.

They differ only where there are unsampled starts. p95 is Wolfram's default `Quantile[w, 95/100]` (inverse empirical CDF).

| S | Arm | Makespan (min..max) | Idle | ns/dispatch | Rework | Reservations (contested) | Starts / unsampled | Wait median, p95, max (0 rule) | Sampled median, p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | FIFO | 1506.9 (1504.1..1507.6) | 601.3 | 305.7 | 0 | 0 | 40 / 0 | 1002.8, 1305.8, 1306.9 | same |
| 1 | fair | 1305.7 (1303.5..1329.3) | 200.4 | 319.1 | 0 | 4 (0) | 40 / 0 | 501.4, 1104.8, 1105.0 | same |
| 1 | goal | 1504.3 (1305.4..1508.1) | 0.04 | 341.2 | 0 | 7 (2) | 40 / 0 | 401.5, 1006.4, 1307.0 | same |
| 1 | ORACLE | 1506.4 (1505.0..1507.7) | 0.03 | 364.2 | 0 | 8 (4) | 40 / 0 | 301.7, 1205.3, 1307.1 | same |
| 2 | FIFO | 2108.1 (2106.9..2155.1) | 0.02 | 240.3 | 0 | 0 | 70 / 25 | 150.5, 1203.7, 1238.4 | 602.3, 1204.0 |
| 2 | fair | 2109.4 (2107.5..2110.6) | 0.02 | 296.0 | 0 | 0 | 70 / 25 | 150.4, 1204.8, 1206.3 | 602.3, 1205.3 |
| 2 | goal | 1807.7 (1805.4..1811.7) | 0.03 | 315.7 | 0 | 24 (14) | 70 / 10 | 376.1, 1205.7, 1206.7 | 451.8, 1205.7 |
| 2 | ORACLE | 1807.2 (1806.1..1807.7) | 0.02 | 295.9 | 0 | 12 (8) | 70 / 5 | 300.3, 1205.6, 1206.7 | 301.4, 1205.6 |
| 3 | FIFO | 1606.7 (1606.4..1610.9) | 0.02 | 222.8 | 0 | 0 | 65 / 10 | 300.7, 902.8, 903.5 | 301.7, 903.1 |
| 3 | fair | 1606.7 (1606.0..1609.7) | 0.02 | 288.2 | 0 | 0 | 65 / 10 | 301.1, 902.8, 904.2 | 301.6, 903.5 |
| 3 | goal | 1606.1 (1605.3..1606.6) | 0.02 | 337.8 | 0 | 25 (10) | 65 / 0 | 602.4, 1304.5, 1304.9 | same |
| 3 | ORACLE | 1605.5 (1604.0..1610.3) | 0.02 | 332.0 | 0 | 20 (15) | 65 / 0 | 602.1, 1303.8, 1306.9 | same |
| 4 | FIFO | 4016.6 (4013.9..4017.5) | 1807.2 | 281.5 | 0 | 0 | 120 / 0 | 1431.0, 2764.3, 3065.4 | same |
| 4 | fair | 3514.9 (3414.1..3517.2) | 202.1 | 319.2 | 0 | 5 (0) | 120 / 0 | 981.0, 2461.3, 2564.9 | same |
| 4 | goal | 3613.5 (3612.3..3715.2) | 594.9 | 347.7 | 0 | 42 (13) | 120 / 0 | 856.4, 2560.6, 2710.9 | same |
| 4 | ORACLE | 3616.5 (3614.9..3622.1) | 110.3 | 329.1 | 0 | 45 (22) | 120 / 0 | 752.4, 2413.1, 2669.8 | same |
| 5 | FIFO | 3012.6 (3011.7..3014.0) | 0.02 | 263.5 | 0 | 0 | 150 / 0 | 601.4, 602.7, 603.8 | same |
| 5 | fair | 3012.7 (3011.5..3013.8) | 0.04 | 304.3 | 0 | 0 | 150 / 0 | 601.3, 602.6, 602.9 | same |
| 5 | goal | 3013.3 (3011.4..3014.0) | 0.03 | 328.8 | 0 | 50 (5) | 150 / 0 | 399.7, 1103.0, 1109.0 | same |
| 5 | ORACLE | 3013.7 (3011.5..3020.8) | 0.04 | 316.5 | 0 | 40 (0) | 150 / 0 | 502.2, 1003.6, 1004.4 | same |
| 6 | FIFO | 3465.1 (3463.3..3466.2) | 301.1 | 222.2 | 5 | 0 | 65 / 0 | 1305.7, 2861.3, 2863.5 | same |
| 6 | fair | 3466.2 (3463.4..3467.1) | 0.02 | 247.8 | 5 | 0 | 65 / 0 | 1205.3, 3213.0, 3216.0 | same |
| 6 | goal | 3618.3 (3367.0..3664.3) | 0.02 | 283.2 | 5 | 19 (9) | 65 / 0 | 1255.4, 3159.8, 3213.8 | same |
| 6 | ORACLE | 3464.6 (3464.2..3479.5) | 0.02 | 243.8 | 5 | 16 (6) | 65 / 0 | 1004.4, 3013.6, 3027.5 | same |

In every run all jobs were reviewed with the expected outcome, and the creator's VmHWM was at most 416 KB. Scenario 6's one rework per run is the job running on the killed worker.

Median makespan relative to FIFO (`Round[100 (m[[s, p]]/m[[s, 1]] - 1), 0.1]`):

| Scenario | Fair | Goal-aware | ORACLE |
| --- | --- | --- | --- |
| 1 blocked head | −13.4 % | −0.2 % | 0 % |
| 2 long chain | +0.1 % | −14.2 % | −14.3 % |
| 3 fan-out | 0 % | 0 % | −0.1 % |
| 4 sustained arrivals | −12.5 % | −10.0 % | −10.0 % |
| 5 queue pressure | 0 % | 0 % | 0 % |
| 6 worker failure | 0 % | +4.4 % | 0 % |

What these traces show, within their limits (sleep workers, 2 workers, 5 repetitions, one host):
- **Fair fitting (policy 1, the default).** It removes most of FIFO's idle eligible capacity in the blocked-head and sustained-arrival scenarios (601 to 200 and 1807 to 202 worker-ms) and shortens them by 13.4 % and 12.5 %. Their median waits fall from 1003 to 501 ms and from 1431 to 981 ms. It never lengthens a makespan by more than 0.1 %.
- **Goal-aware (policy 2).**
  - It is the only policy that shortens the long chain (−14.2 %), matching the ORACLE arm.
  - In fan-out its median wait rises from 301 to 602 ms at an unchanged makespan.
  - Under queue pressure its median wait falls from 601 to 400 ms but its p95 rises from 603 to 1103 ms.
  - In worker failure its median makespan is 4.4 % longer, with a 3367..3664 ms spread across repetitions.
  - In the blocked head its 5 makespans spread from 1305 to 1508 ms.
- **Dispatch cost.** It is 222 to 364 ns per call in every arm; policy 2 costs more per call than FIFO in every scenario.

The live workflow ran policy 1 only, so no live comparison exists between the arms.

## Local inference and the coding workflow (DRA-290)

Status: IMPLEMENTED in `infer.om`, `tool.om`, `gram.om` and `code.om`,
exercised on native Linux AArch64 by `code-test.om`, the round40 replay
`tests/tool-replay.py`, the tool controls and live runs of the own Omega
model (round40 checkpoint served by aien-train `ollm serve`, DRA-119, inside a
private network namespace). Evidence is in the DRA-290 pull request. Not
QUALIFIED on the Spark and not DEPLOYED.

All four are OM-2 programs (`printf 'om2\n'` before the sources):

```sh
L="seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/sched.om seed/authority/action.om seed/node/journal.om seed/node/auth.om"
{ printf 'om2\n'; cat seed/json/json.om seed/json/jsonw.om seed/net/http.om seed/net/notls.om seed/node/infer.om; } | seed/out/omc > build/node/infer
{ printf 'om2\n'; cat seed/agent/path.om seed/node/gram.om seed/node/tool.om; } | seed/out/omc > build/node/tool
{ printf 'om2\n'; cat $L seed/node/gram.om seed/node/code.om seed/node/code-main.om; } | seed/out/omc > build/node/code-main
{ printf 'om2\n'; cat $L seed/node/gram.om seed/node/code.om seed/node/code-test.om; } | seed/out/omc > build/node/code-test
chmod +x build/node/infer build/node/tool build/node/code-main build/node/code-test
build/node/code-test unit build/node/cu   # "code checks=54 fail=0", exit 0
python3 seed/node/tests/tool-replay.py build/node/tool OMC40 ROUND40 build/node/replay   # pass=108 fail=0
```

A failed compile leaves an empty output file that exits 0 when run; check
omc's exit status. `OMC40` is the compiler the round40 model was trained and
evaluated with (sha256 `2c82480596bb…`, omega-mv `e5b32567`): its error text is
part of the prompt, so the check tool must use it. `ROUND40` is the round40
run directory holding `repair.py` and `final-selected.json`.

### Programs

`omnode-code INFER TOOL OMC ROOT WORK JDIR PORT OBJ...` runs 1..4 objectives
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
cancel); `CWO i PASS|FAIL result turns`; `CWSUM pass= fail=`. Exit 0 when
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

`code-test unit` (54 checks, no child process) feeds crafted model and tool
records to the creator: the round40 prompts byte for byte; every action in
every state; wrong path; old text absent, twice, many times; an edit outside
the grammar; `Tests passed.` unverified or after an edit; `File not found.`
when not missing; header and length faults; tool content that differs from
the source or candidate; outcome words for exit 4, 5 and 8, a killed child,
cancellation, UNKNOWN and a lost input; the turn limit; an over-long prompt.
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

### Live coding workflow under the durable scheduler (DRA-399)

`live-test.om` runs the coding workflow above for real on native Linux
AArch64: `ollm serve` with the own round40 model, `code-main`, `code-test`,
`tool` and `infer`. The scheduler is the journal v2 one with the default
policy that `sched_new` sets (policy 1). The driver only starts the programs
and checks what they did; it implements none of their logic. It replaces the
DRA-290 shell and Python harness (`inner.sh`, `crash.sh`, `prep.py`, `cmp.py`,
`jread.py`).

```sh
{ printf 'om2\n'; cat seed/json/json.om om/tls/sha2.om seed/node/live-test.om; } \
  | seed/out/omc > build/node/live-test        # omc exit status must be 0
bwrap --dev-bind / / --unshare-net --die-with-parent -- \
  build/node/live-test BASE NODE OLLM MODELDIR OMC40 SEL [serve=0] [parts=fcr]
```

- **Paths.** All paths are absolute, and BASE must not exist yet.
  - NODE holds `infer`, `tool`, `code-main` and `code-test`.
  - MODELDIR holds `model.ck` and `merges.bin`.
  - OMC40 is the compiler the objectives are checked with (omega-mv e5b32567).
  - SEL is round40's `final-selected.json`.
- **Server.** The model server listens on 127.0.0.1:18399, inside the network namespace.
- **Negative control.** `serve=0` starts no server.
- **Parts.** `parts=` selects the full run (f), the cancellation (c) and the crash and restart (r). A part left out is `NOT_RUN`.
- **Exit status.** 0 only when every check passed, 1 otherwise, 2 for a usage error.
- **Output.** One `PASS|FAIL|NOT_RUN name detail` line per check, then `LIVE checks N pass P fail F not_run R`. The checks are backed by these evidence lines:
  - `HASH`: sha256 and size of every pinned input, every node program and the driver itself (`/proc/self/exe`).
  - `SEL`: the four round40 rows used.
  - `PREP`: the prepared objective files.
  - `SERVE`: server pid and readiness.
  - `RUN`: program exit and milliseconds.
  - `REVIEW`, `SNAP`.
  - `JOP`: one line per journaled operation.

Objectives: the four round40 loop rows `item76666` (logic fault),
`item83423` (missing file), `item82342` (syntax fault) and `item85188`
(correct already). Each row's broken file is written into `root/jobs` and
compared byte for byte with the selection's `broken` text. Each scenario
(`BASE/full`, `BASE/cancel`, `BASE/crash`) has its own root, work
directory, journal and server.

| Check | Passes when |
| --- | --- |
| prereq-hashes | model, merges, ollm, the objectives' compiler and the selection match their pinned sha256; every node program is hashed |
| selection | the four rows parse from SEL and their broken files are prepared |
| full-workflow | `code-main` with all four objectives exits 0 with `CWSUM pass=4 fail=0` and every `CWO i PASS 1`; no node process remains 15 s later and the server's process group is gone |
| full-journal | the journal reads back intact: every OPEN under SPVER 3, fences increasing, no POLICY record (the default policy was never changed), one OPEN, every operation started exactly once and done, nothing open, objective identity `OMNC`, 4, issue 290 |
| round40-transcript | every `CWP` prompt and every `CWR` model reply equals round40's recorded turn byte for byte, in order, and each objective took round40's number of turns (5, 2, 5, 3) |
| review-outputs | an independent `tool check` (OMC40) of each objective's final file: the three files equal the selection's correct text and give `Tests passed.`; the missing-file objective's file is still absent and gives `File not found.` |
| cancel-mid-inference | `code-test cancel 20000` on objective 0 exits 1 with `CWO 0 FAIL 19` after one cancel event, the server logs the dropped request as `C 499`, no node process remains and the server group is gone |
| cancel-journal | the journal checks above with one objective, plus at least one CANCEL record |
| crash-restart | run 1 of objective 0 is SIGKILLed (status 137) while an `infer` child is running the first inference after the replace landed. Only the creator is killed; its workers and the inference are left to the node's own cleanup, and no node process may remain 15 s later. The file on disk is then the correct text. Run 2 restarts on the same root, work and journal and must exit 0 with `CWO 0 PASS`, leaving nothing behind |
| crash-journal | the journal checks above with two OPENs, plus at least one operation settled by the restart (`auth_recover`) |
| no-leak | at the end no process whose program is under NODE remains |

bwrap shares the host's process namespace, so the NODE process count sees every process on the host whose program lies under NODE. Keep monitors and other tools out of NODE. In the first DRA-399 full run, the core sampler lived in `build/node`, and that alone failed full-workflow and no-leak.

`live-cpu.om` is the core-contamination sampler that goes with these runs. Every 10 s it reads `/proc/*/task/*/stat` (read-only) until the file STOP exists. It prints one line per sample: `CPU <realns> cwo <c> run89 <r> own <o> foreign <f>`, followed by ` pid/tid:comm` for each foreign thread.

- `run89` counts threads in state R whose last processor (stat field 39) is 8 or 9.
- `own` counts those whose program is under `/tmp/wtlive/build/node/` or is the pinned ollm.
- `cwo` counts the `CWO ` lines in WATCH, which marks the objective boundaries.

```sh
{ printf 'om2\n'; cat seed/node/live-cpu.om; } | seed/out/omc > build/lt399/live-cpu
taskset -c 0 nice -n 19 build/lt399/live-cpu PART/end.txt PART/run/<scenario>/run.out > PART/cpu.log
```

#### Results, 2026-11-07 (EXERCISED; not QUALIFIED)

All runs were on native AArch64, CPU only (spark-b87b, Linux 7.0.0-1019-nvidia). Each ran under `flock pool-8-9.lock taskset -c 8-9 nice -n 10 bwrap --unshare-net`. Core 9 is the X925 timing core.

Run directory: `~/handoffs/hive/sched/live399/20261107T085509Z/<part>/`, holding `cmd.sh`, `live.out`, `live.rc`, `cpu.log`, `ps-ollm.txt` and the scenario's `run/`.

Hashes (`HASH` lines; full list in `start.txt` and `start-addendum.txt`):
- Node programs at aa2abf84: infer 8cc5fb30…, tool a1bdecb0…, code-main 7a1c14c0…, code-test 1b270fba….
- Compilers: in-tree omc 5f90edea…, and the objectives' compiler 2c824805… (omega-mv e5b32567).
- Model inputs: ollm f99fce9f…, model.ck 7c7b5b52…, merges.bin 73a29baf…, and the round40 selection 2017a902….
- Drivers: live-test 1b30b1de… before the slot fix and 25c9a30a… after it; live-cpu 5b638039….

| Part | live-test | Checks pass/fail/not_run | Result |
| --- | --- | --- | --- |
| neg (`serve=0`, c) | 1b30b1de | 3/2/6 | cancel-mid-inference and cancel-journal FAIL with no server, as required |
| f | 1b30b1de | 5/2/4 | FAIL. The sampler ran from `build/node`, which failed no-leak and full-workflow. code-main exited 0 with `CWSUM pass=4 fail=0` in 1790389 ms. full-journal, transcript and review PASS. |
| c | 1b30b1de | 5/0/6 | PASS: `CWO 0 FAIL 19` at 20049 ms, server `C 499`, 7 journal records with 1 CANCEL |
| r | 1b30b1de | 5/0/6 | PASS. Run 1 was SIGKILLed (137) during the first inference after the replace, and the file on disk was correct. Run 2 exited 0 with `CWO 0 PASS 1 6` in 244394 ms. Journal: 80 records, 2 OPENs, 13 operations each started once, 1 settled by the restart. |
| f2 | 1b30b1de | 6/1/4 | FAIL from the driver slot collision (CWSUM count in lcw 60 = objective 3's CWE slot; 18 `CWE 3` lines read as 19). code-main exited 0 with `CWSUM pass=4 fail=0` in 1645009 ms. full-journal (174 records), transcript, review and no-leak PASS. |
| f3 | 25c9a30a | 3/4/4 | FAIL. code-main hit its fixed 3600 s deadline (exit 62, 3600078 ms) with o0 and o1 PASS (5 and 2 turns, as in round40) and o2 and o3 unfinished, so journal, transcript and review fail as consequences. no-leak PASS. |
| c2 | 25c9a30a | 5/0/6 | PASS: `CWO 0 FAIL 19` at 20090 ms, server `C 499`, 7 journal records with 1 CANCEL |
| r2 | 25c9a30a | 5/0/6 | PASS, on a contended host. Run 1 was SIGKILLed (137) during the first inference after the replace, and the file on disk was correct. Run 2 issued no second replace and exited 0 with o0 PASS in 590011 ms. Journal: 80 records, 2 OPENs, 13 operations each started once, 1 settled by the restart. |
| f4 | 25c9a30a | 7/0/4 | PASS, in the quiet slot granted by Manager cycle 24 (13:56:50Z-14:21:48Z, pool-8-9, no spark-window). The start check inside the lock passed: load1 9.64, and no ollm/train process running (ownmodel's eval was stopped). code-main exited 0 with `CWSUM pass=4 fail=0`, o0..o3 PASS in 5/2/5/3 turns. full-journal: 174 records, 29 operations each started once, 0 bad. Transcript, review and no-leak PASS. Partly contended: ownmodel's eval ran 13:58:31Z-14:00:29Z, resumed on a false END line from my script, then re-paused. The sampler found a foreign thread on 8/9 in 10 of 150 samples: brief runnable threads of host processes, none ollm or train (listed under Contamination). Not shown in the table: an earlier launch at 13:56:12Z was refused at once ("BASE must not exist": the driver script had created BASE) and ran no inference. Its record is kept; attempt 1 at 12:15:29Z was NOT_RUN (load 10.45, 4 ollm processes). |

Each part exits 1 whenever a check is NOT_RUN (`lt_end`), so the check table, not the exit status, is the verdict.

f4 is the fixed driver's first full four-objective run to end (CWSUM 4/0).

**Contamination.** `live-cpu` takes one sample every 10 s and counts the samples in which a foreign thread was running on core 8 or 9. Data lines only; the closing `CPU done samples N` line is not a sample:
- f: 7 of 106 samples. The sampler started at 09:08:31Z, about 12 minutes after f did (08:56:00Z), so the start of f was not sampled.
- c: none in 4 samples.
- r: 7 of 73 samples (4 of them `grep`).
- f2: 22 of 155 samples (11 of them `grep`).
- f3: 95 of 349 samples (46 of them `grep`). The `grep` threads came from many pids and cannot be attributed after the fact; the others included `kcompactd0`, `git`, `python3` and `kswapd0`.
- c2: 5 of 5 samples (4 of them `grep`).
- r2: 51 of 185 samples (9 of them `grep`).
- f4: 10 of 150 samples, each a briefly runnable thread of a host process, some of them long-lived daemons: `mi-scavenger` and `agent-archive` twice each; `tailscaled`, `tokio-rt-worker`, `pi-fs-worker`, `python`, `omp`, `git` and `find` once each (one sample held both `tailscaled` and `mi-scavenger`). None was ollm or train.

The sampler ran on core 5 for f, c and the start of r, and on core 0 from 09:35:59Z (partway through r) onward. The `cpu.NOTE` files record the core-0 use as unapproved; the Manager approved it in cycle 16 (BOARD 2026-11-07T11:19:33Z).

f3, c2 and r2 ran on a contended host, and f4 on a partly contended one (ownmodel's eval 13:58:31Z-14:00:29Z; load1 9.64 at the start and 17.59 at the end). Their wall times are recorded but are not measurements of the workflow.

f3's turns took 2 to 5 times longer than f2's at equal token counts (for example 644695 ms against 279335). ollm stayed alone on core 9, the load average was 22 on 20 cores, and other lanes' ollm serve, train and gtrain processes were running on other cores (`f3/NOTE`, `ps-ollm.txt`). Shared memory bandwidth is the likely cause, but it was not measured.

These timings are not speed evidence.

**Against DRA-290's harness** (same programs, model and objectives):

| Run | DRA-290 | This run |
| --- | --- | --- |
| full | exit 0 in 1632430 ms | exit 0 in 1790389 ms (f), 1645009 ms (f2) and 1492808 ms (f4, partly contended); f3 hit the 3600 s deadline (contended) |
| cancel | `C 499 … 22072` | 20049 ms (c) and 20090 ms (c2) |
| crash run 2 | 295826 ms | 244394 ms (r) and 590011 ms (r2, contended) |

**Limits:**
- One server, CPU only.
- DEPLOYED.json's runtime_sha256 926c30fa… does not match the ollm used here (f99fce9f…), so this is not the deployed runtime (DRA-292).
- Only policy 1 ran live. The FIFO and goal-aware live arms are NOT_RUN.

