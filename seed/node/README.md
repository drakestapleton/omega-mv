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
runs after releases (every `sched_step` collects, then dispatches); no
request exceeds capacity (refused at admission, -8). Under them a reserved
job runs once the jobs running at its reservation have finished and a
worker is free, and each ready job is examined within ceil(64/`win`) window
scans. There is one reservation at a time, and it goes to the oldest job at
the bypass budget. A job at the budget therefore waits only for the
reservations of jobs admitted before it, a finite set; later arrivals never
take the reservation first. Workers are not a resource kind: the reserved
job is offered first at every pick, so it takes the first idle worker once
it fits.

Admission tickets. Room is the smaller of the admission headroom and the free
table slots: a job in review or UNKNOWN keeps its slot, so a table full of
unreviewed results refuses admission even below the limit. `sched_room id`
refuses without room and gives the refused caller a ticket. While tickets
are held only the first holder may enter, whatever the room; a new caller
takes a ticket behind them. `sched_admitr` asks it; so does `jn_admit`,
after its duplicate check and before it journals ADMIT, and a true answer
guarantees the slot (one creator, no other admission in between). A ticket
not asked about for more than `ttl` dispatch events (default 1000) lapses:
asked at event e, it survives while e + `ttl` is at least the current event
count. A caller that went away therefore blocks later holders for at most
`ttl` events; a paused dispatch counts no events, so that block lasts until
dispatch resumes. At most 64 tickets are held, and a caller refused with
the line full holds none.

Leases. `sched_lease j ns` gives a job a lease counted from its assignment;
`sched_overdue` reports a running job past its lease whose worker has not
reported done, once. The authority then cancels or kills it, and the release
follows from the worker's report or the reap. The lease is a clock reading
used for reporting only; selection reads logical counters.

| Function | Contract |
| --- | --- |
| `sched_room id` | May id be admitted now: room is min(admission headroom, free slots); while tickets are held only the first holder may enter. A refused caller gets or keeps a ticket. |
| `sched_lease j ns` | Lease for a waiting, ready or running job, from its next assignment; 0 removes it; -3 otherwise. |
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

Phases S to Z run after A and B, so under `fifo` the gate stops at 11.
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
declaration changes. Values are recomputed only at a policy-2 pick whose
version differs from the last scoring, once however many bumps came before
it. Bumps therefore coalesce and none is lost, because the version is a
counter, not a flag. Completions, failures, resource releases and lease
expiry replan without rescoring: every step collects, then dispatches with
the current values, and none of those events changes a value. No step waits
for other workers and no model is called.

Proposals. `sched_propose id v` lets an outside planner or an operator put
the ready job whose id is `id` first, computed at graph version `v`
(`sched_version`). The proposal names the job, not its table slot. It is
refused when `v` is not current (-9, counted stale), when no ready job has
that id (-3) or when the job does not fit beside the reservation (-8). It
is used once, at the next pick, after the reservation, and only if the
version is still `v`, the job is still ready and it still fits; otherwise
it is dropped and counted stale. Within one scheduler every change of a
slot's occupant bumps the version, so a current version still names the
job it was made for. Across schedulers the version carries the
incarnation: `sched_incarnate n` (right after `sched_new`, n in
1..2^24 - 1, distinct per scheduler; DRA-398 uses the journal fence) makes
the version n × 2^40 plus the bumps since, which no scheduler of another
incarnation reaches.

| Function | Contract |
| --- | --- |
| `sched_goal j pro est unc` | Declare topics, estimate (ms) and its uncertainty (ms) for a waiting or ready job; 0 or -3. |
| `sched_version` | The graph version. It moves on admission, a job becoming ready, cancellation and `sched_goal`, and on nothing else (not on completions, releases, lease expiry, `sched_cap` or `sched_policy`); it versions the inputs of ranking and proposals, not the whole scheduler state. |
| `sched_incarnate n` | Set the incarnation (1..2^24 - 1); the version becomes n × 2^40 and a pending proposal is dropped; 0 or -7. |
| `sched_propose id v` | Propose the ready job with id `id` at version v; 0, -9 stale, -3 no ready job has that id, -8 does not fit beside the reservation, -7 not policy 2. |
| `sched_stat 32..40` | Rescorings, jobs scored, version bumps, proposals accepted, stale, refused, value slot reads, proposals used; 40 the graph version. |

`schedpol-gate goal` runs every phase under policy 2 (exit 0). Phases G, H,
P, I, R2 and K set policy 2 themselves and run after W in the default and
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
