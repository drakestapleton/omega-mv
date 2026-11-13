# execfds (keyword 201)

`r = execfds A off n E eoff en K koff kn` replaces the process, as `execenv A off n E eoff en` does, but it
keeps a chosen list of descriptors open across the exec. It is AArch64 Linux only and program mode only.

## Operands

- **A and E** are the argv and environment packets. They are framed exactly as for `execenv`:
  - a u16 count of at least 1, then u16-length records;
  - the first argv record (the program path) is nonempty, and every environment record is nonempty;
  - there are no embedded zero bytes and no trailing bytes.
- **K** is a flat list of little-endian u32 descriptors to keep. The list may be empty.
  - `kn` must be a multiple of 4.
  - The entries must be strictly increasing, each in 3..2147483647.
  - Stdio 0..2 is always kept and is never listed.

## Order of operations

1. **Framing checks and private decode.** Every framing rule above is checked first, before any decode mapping
   or descriptor changes. Argv/environment are copied and checked on the bytes actually copied; K is also copied
   into the decode region and that copy is checked again. If caller memory changes after the prepass, these
   checks can trap 3 after allocation. The launch reads only the private checked copies, never caller K.
2. **Private table.** `unshare(CLONE_FILES)` gives the process a private descriptor table.
3. **Validation.** `fcntl(F_GETFD)` is called on every kept descriptor. A kept descriptor that is not open returns
   -EBADF, and nothing has been closed at that point.
4. **Clear close-on-exec.** On each kept descriptor, FD_CLOEXEC is cleared, so a kept descriptor survives even if
   it was opened close-on-exec.
5. **Close the rest.** `close_range` closes every gap between kept descriptors and everything after the last one.
6. **Exec.** `execve` runs.

## Failures and refusals

- **Decode memory.** A packet's framing is checked against the bytes actually supplied before any decode memory
  is mapped. A malformed packet, or one whose count field claims more records than its bytes hold, costs only
  the reading of its bytes. For a valid n-byte packet the requested decode has strings
  `S(n)=8 floor((n+15)/8)` and pointers `P(n)=4n+16`, so `S(n)+P(n)<=5n+31` bytes.
  For argv, environment and the keep copy together it is at most `5(n+en)+65+kn` bytes, plus kernel page
  rounding. The keep copy follows the pointer arrays, rounded up to an 8-byte boundary. Wolfram evaluator,
  modeled byte calculation (not an execution receipt): with `t[r_]:=8 Floor[(r+15)/8]+4r+16`,
  `Max[Flatten[Table[8 Ceiling[(t[r]+t[s])/8]-5(r+s),{r,0,7},{s,0,7}]]]` gives `65`;
  `5 (2 (2^60-1))+65+(2^60-1)<2^64` gives `True`. All three slice lengths are checked below 2^60
  before sizing; this is an overflow protection, not an admission quota.
  This excludes the unit's one fixed 65536-byte static fallback region and the ordinary host-register
  save; the new decode frame is 80 bytes. The count field never sizes memory.
  A u16-framed valid packet cannot reach the separate 2^60 machine-arithmetic overflow refusal.
- **Return value.** The word returns only on failure, with that step's negative errno: no fallback or rollback.
  Decode-mapping failure returns before any descriptor effect. Failure of unshare leaves the original table
  unchanged; failure in the initial F_GETFD validation loop leaves every descriptor open and unchanged in the
  private table. A later F_GETFD or F_SETFD failure closes nothing, but kept descriptors already processed may
  have CLOEXEC cleared. A close_range failure leaves already-closed gaps closed and later gaps unprocessed;
  the failed call has only the kernel's guarantees. Only execve's own failure occurs after every unlisted
  descriptor above 2 has closed. Fork before calling when the caller must preserve its descriptor state.
- **No admission limit of its own.** Its packets come from the caller's own program. A caller that forwards
  outsider data keeps its own bounds for that data; this word is not a hostile-ingress decoder.
- **Refusals.** There is no x86linux, x86efi or a64efi lowering (error 25). Function mode refuses it (error 9),
  and so does a contract clause (error 30).

## Gate files

All of these are TEST INSTRUMENTS (never a product path).

### `execfds.om`

The seeded fixture.

- **Parent mode** runs 29 checks. Its exit is the number of the first failed check. Checks 25 to 29 run
  under a self-set RLIMIT_AS of 16 MiB: a valid 4 MiB packet's decode mapping is refused (-12, the control),
  and the same packet with a trailing byte, a zero byte, an empty first record or an empty environment record
  must trap 3 instead, because framing comes before any mapping.
- **Child modes** report which descriptors are open, by opening `/proc/self/fdinfo/N`.
- **Launch modes** are used for the oracle parity.

### `execfds.cases`

Run by the OM-2 conductor:

- the fixture;
- a fault control;
- refusals;
- ten `omc.om` check-removal mutants, each killed at its named check: five on the keep list and the
  CLOEXEC clear, and five on the validation pass that runs before any decode mapping (the pass not called,
  and its trailing, zero-byte, first-record and environment-record checks);
- five ENOSYS fault injections, at unshare, the GETFD loop, the SETFD loop, a gap close_range and the tail
  close_range. Each must fail closed with -38: the kept descriptor is still open and nothing was executed.

### `oracle.py`

The **ORACLE**: Python ctypes, never shipped.

- It decodes the fixture's own packets with independent framing code.
- It prepares the same descriptors with Python's own calls.
- It runs the same contract with libc calls and a ctypes `execve` that keeps duplicate environment entries.
- System call numbers and flag values come from the kernel headers.

It also checks the strace order and does the exact-once `omc.om` substitution for the `no-unshare` mutant.

### `check.sh`

The gate runner. It runs:

1. the cases;
2. oracle parity for six scenarios, which must match byte for byte in exit status and stdout;
3. the strace order check, which uses `strace` as an independent observer, plus the `no-unshare` mutant, which
   only that check can see;
4. the strace memory check: a 4 MiB packet with a trailing byte and a 9-byte packet whose count field says
   65535 must trap 3 with no mmap, mremap or brk at all; the valid 4 MiB packet must show its decode mapping
   (the observer control) and stay within 5(n+m)+65+k bytes plus a page per mapping;
5. the deterministic `snapshot.py` ptrace instrument: capture caller K=[7] from the fixture's marker write,
   pause at unshare return, rewrite caller K to [9], record fcntl/close_range and descriptors before exec, and
   check the re-exec report. The private copy must keep 7 and close 9. The `caller-reread` compiler mutant
   leaves the caller's address in the launch frame; it must instead keep 9/close 7 and be killed by the semantic
   mismatch (exit 1). Instrument/launch failures are exit 2, not kills. No ptrace is NOT_RUN (exit 3), not PASS;
6. controls: the oracle selftest, detection of a changed output, and snapshot launch failure.

Exit codes: 0 PASS, 1 FAIL, 3 NOT_RUN (no strace or ptrace).

## Test-size numbers

None of these is a limit of the word.

- **Fixture checks 22 to 24:**
  - 1100 argv records, one of 65535 bytes;
  - 73 environment records, one of 5004 bytes;
  - 64 records of 65535 bytes, under a self-set RLIMIT_STACK of 8 MiB, to reach the kernel's E2BIG;
  - 1100 kept descriptors (1000..2099). For these the fixture raises its own RLIMIT_NOFILE soft limit to the
    hard limit, and needs a hard limit of at least 2200 (exit 77 otherwise, which is a failure).
- **Probe range.** The descriptor probes cover 3..max(19, last listed + 16).
- **Memory checks.** RLIMIT_AS 16 MiB in checks 25 to 29, and the 4 MiB packets of the strace memory check,
  are test inputs and caps of the test process only.
- **Deadline.** The conductor deadline is 120 s.
