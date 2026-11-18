# Disposable local control probe

Run from an AArch64 Linux checkout. The probe forks exactly two synthetic Omega workers. It has no journal, provider credentials, network listener or connection to the running hive.

```sh
mkdir -p build/node
cat seed/node/transport.om seed/node/pool.om seed/node/super.om seed/node/probe/control.om |
  seed/out/omc > build/node/n0 && chmod +x build/node/n0
seed/out/omc < seed/node/probe/check.om > build/node/n0-check && chmod +x build/node/n0-check
build/node/n0 &
server=$!
build/node/n0-check "$server" && wait "$server"
```

The server listens for 60 seconds on a Linux abstract Unix stream socket. Its address is a zero byte, ASCII `omega-node-n0.`, then the server PID as four little-endian bytes. Clients must have the server's UID. Authenticate the server with SO_PEERCRED before sending commands.

Use one connection per command. Write three bytes (length 2, version 1, operation), then half-close the write side. Operations 1 through 6 are IDENTITY, SNAPSHOT, PAUSE, RESUME, SHUTDOWN and STOP_SLOW. A fourth byte invalidates the frame. An incomplete request expires after one second. The event loop admits one client per pass, holds eight connections at most and buffers four request bytes and twelve reply bytes per slot.

The twelve reply bytes are length 11, version 1, echoed operation, result (0 applied, 1 refused), paused, responsive-worker state, slow-worker state, whether a work acknowledgement has been observed, then the server PID in little-endian order. Worker states are 0 running, 1 stop requested, 2 reaped after an acknowledged stop request with clean exit, and 3 unknown or unexpectedly lost. PAUSE stops new work hints. A hint already in flight can still complete. STOP_SLOW requests termination of the blocked worker. SNAPSHOT reports a confirmed stop only after the kernel returns the owned child's wait status. On SHUTDOWN the reply acknowledges the request. Server exit zero confirms both children were reaped. Abrupt server death wakes workers through the supervisor's creator-life pipe.

The latency acceptance threshold is 200 ms for each of 32 sequential SNAPSHOT commands while six other clients hold partial frames and the slow worker waits. Record maximum latency, load, machine, binary digest and all responses in the test receipt. This is a local liveness threshold, independent of model throughput.
