# Omega Node shared-memory transport, epoch pool and worker supervision

This is the first implementation component of [Omega Node](https://github.com/aien-dev/omega-harness/issues/205).
It provides a bounded, single-publisher artifact log for trusted forked Omega
processes. Runtime consumers can share artifact storage and wake only interested
workers. The existing `seed/agent/agent.om` is the coding-agent consumer to evaluate
for integration; this change does not replace its model or tool dispatcher.

Three source fragments, concatenated in this order before one program with `fn main`:

| Fragment | Adds |
| --- | --- |
| `transport.om` | one arena: 64 immutable records, topic scan, eventfd hints, stop flag (#1055) |
| `pool.om` | K arenas reused by epoch, reader holds, fail-closed rollover (DRA-286) |
| `super.om` | forked workers, death detection, reaping, creator-loss detection, bounded stop (DRA-286) |

The component is not yet connected to the live hive. Persistent recovery,
authority integration, a dashboard and a real model-backed coding workflow remain
implementation work (DRA-287 to DRA-292). The
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
