# native/net/tcp: native TCP in seeded Omega (ledger L232)

TCP over IPv4 and ARP, written in Omega and built by the pinned seeded `omc`.
The pin is omega-mv's own: the SHA-256 in `seed/out/omc.sha256` at the omega-mv root (kernel/ is
folded into omega-mv), which `gate.sh` reads and checks; it refuses any other compiler. No C, no heap, no outside library
in the stack or its drivers.

| File | What it is |
|---|---|
| `tcp.om` | The stack: Ethernet II, ARP (4 entries), IPv4 (no options sent, fragments refused), and TCP after RFC 9293 with the deviations listed under Limits: RFC 6298 RTO (with the 5.7 restart at 3 s after a SYN timeout), RFC 5681 slow start and congestion avoidance from an RFC 6928 initial window, RFC 6582 NewReno fast retransmit and recovery, RFC 5961 RST/SYN/ACK hardening, RFC 6528 initial sequence numbers (SipHash-2-4 of the 4-tuple under a 128-bit key, plus a clock), out-of-order reassembly into a 64 KiB ring (first copy wins), FIN ordering (a FIN ends the stream: bytes past it are dropped, RFC 9293 3.10.7.4), TIME-WAIT, and zero-window persist probes of one octet. One connection block plus one passive port. The embedding unit supplies `tlinkout`, the clock and the key (`tkey`); without a key no connection opens and `trnd` refuses (trap 8, exit 108). |
| `tcpd.om` | Guest driver (`cat tcp.om tcpd.om \| omc`). Runs as a process inside a Linux guest: rtnetlink brings `eth0` up with GRO off, an AF_PACKET socket carries raw frames. The guest kernel has no IPv4 address, so this stack alone answers for 10.0.2.15. It takes the 16-byte sequence number key from the guest's `getrandom(2)` and exits 7 if it gets fewer bytes. Modes: echo, receive to file, send a file, and `key` (a host check of the key path for `gate.sh corpus`: it asks for N bytes, prints the installed key words and one `trnd` value, and exits with no network). |
| `link.om` | Impairment relay between the guest NIC and QEMU's slirp network: seeded drop, hold-back reordering, duplication, and hostile injection toward the guest (15 kinds, see the `lmutate` note). Hostile variants go ahead of the real frame. |
| `peer.om` | Host peer on 127.0.0.1 (slirp forwards into the guest): echo check, send, receive and compare. |
| `corpus.om` | Hosted hostile corpus (`cat tcp.om corpus.om \| omc`): exact-state cases, in 30 case groups, for every mechanism named in the `tcp.om` row (expected values from the RFC formulas, and SipHash outputs from OpenSSL as an independent oracle), with the payload of sent segments checked against the stream written; a seeded fuzz phase with invariants; and a final transfer whose sequence numbers wrap past 2^32. The single-line edits of the congestion, RTO, ACK and FIN code that no case kills are listed under Limits. |
| `nokey.om` | `trnd` with no key installed (`cat tcp.om nokey.om \| omc`): must trap 8. |
| `mutants.tsv` | Single-line edits of `tcp.om` and `tcpd.om`, at least one per claimed mechanism, each with the check that must fail on it (a corpus check id, `nokey` or `tcpdkey`). |
| `mutgen.awk` | Generates single-line edits (operator, constant and condition flips, deleted statements) of the functions `gate.sh` names; `gate.sh corpus` runs all of them. |
| `gate.sh` | The gates (verification rig, POSIX sh). `corpus` mode: pin check, corpus, NOT_RUN controls and mutants. QEMU mode: the corpus mode, then one fresh QEMU guest per profile and scenario. |

## Gates

```
sh gate.sh corpus OMC OUTDIR
sh gate.sh OMC IMAGE BUSYBOX OUTDIR [PROFILES] [SCENARIOS]
```

`corpus` (what `tests/gates/run.sh kernel-tcp-corpus` runs). It first checks
its tables against pins in `gate.sh`: the rows of `mutants.tsv` (all well
formed, no name or edit twice), the rows `mutgen.awk` makes, and the unasserted
list below. Then `trnd` without a key must trap 8 (`nokey.om`), and `tcpd key`
must install two different nonzero keys in two runs, wipe its buffer, and exit 7
on a 15-byte read. The corpus at fuzz 0 must run exactly the pinned number of
checks, set of check ids (sha256) and case groups, then at `FUZZ` seeded frames
(default 2,000,000, the pinned minimum; anything lower fails) print `CORPUS_PASS`
with that fuzz count. The controls follow: a missing and a wrong compiler must
each make `gate.sh` exit 3 with NOT_RUN (corpus and QEMU mode); `FUZZ` below the
pin must fail; changed copies of this directory must each fail their own gate
(a mutant row deleted, commented out or duplicated, a case group skipped, one
check deleted, an unasserted row deleted, a generated function dropped, `trnd`
unrefused, a constant `tcpd` key, `tcpd`'s short read kept); and the kill rule
must count neither a trap without the row's check failing nor another check's
failure. Every row of `mutants.tsv`, built and run at fuzz 0, must fail its own
check: nonzero exit, no `CORPUS_PASS` and `CORPUS_FAIL check=ID`, or `nokey`, or
`tcpdkey`. Last, every generated edit is built and run at fuzz 0 (and with
`nokey.om`); exactly the edits listed as unasserted under Limits may survive. It
ends with `GENERATED rows= built= killed= survived= not_built= kill_rate=` and
`TCP_CORPUS_GATE PASS checks=N fuzz=F groups=G mutants=M killed=M generated=X
gen_killed=Y survivors=Z controls=C`, exit 0, only when all of that holds; any
other result is exit 1.

Exit codes in both modes: 3 NOT_RUN (never a pass) when the gate cannot run:
missing pin, missing or wrong compiler, and in QEMU mode no QEMU, no access to
`/dev/kvm`, or no IMAGE or BUSYBOX; 2 when a unit does not build with the
pinned compiler; 1 when a check fails.

QEMU mode profiles (per mille, per direction): `clean` (none), `loss` (3% drop),
`reorder` (15% held back 1 to 3 frames or 40 ms), `hostile` (2% drop, 10%
reorder, 2% duplicate, 20% hostile injection toward the guest). Scenarios:
`echo` (1 MiB echoed back to the host), `h2g` (2,000,000 bytes host to guest,
digest checked in the guest with busybox `sha256sum`), `g2h` (the 1,914,704 byte
busybox binary guest to host). A run passes only when the peer, the guest
stack, QEMU's exit and the digest all agree (echo bytes are compared one by
one by `peer.om`), and the link log proves the profile's impairments happened;
a hostile run must have injected all 15 kinds.

Verification-only dependencies (not in the stack): QEMU `qemu-system-aarch64`
with KVM, a Linux arm64 `Image` with virtio-net and AF_PACKET, a static
aarch64 busybox (guest init, `sha256sum`, and the g2h payload), POSIX sh, awk,
gzip, cpio, sha256sum, sed and timeout. The SipHash expected values in
`corpus.om` came from OpenSSL 3.0.13 (`openssl mac ... SIPHASH`); OpenSSL is not
needed to run the gates.

Oracle defect (QEMU's slirp, libslirp 4.7.0-1ubuntu3.1, unchanged on upstream
master): `tcp_input` runs `tcp_dooptions` on every segment outside LISTEN, and
an MSS option on a SYN calls `tcp_mss`, whose `sbreserve` resets the socket's
send buffer (`sb_cc = 0`). A duplicated or late SYN-ACK that reaches slirp
after it has buffered host data therefore silently discards that data. Found
when a hostile echo run lost 113,152 bytes inside slirp (packet capture: slirp's
second segment carried file offset 114,612 at stream offset 1,460). The relay
therefore never holds back or duplicates SYN segments travelling toward slirp;
the stack answers a duplicate SYN in syn-received with a plain ACK (RFC 9293).
Residual: if the relay drops slirp's handshake ACK and every following slirp
segment for the guest's 1 s SYN-ACK timer, the retransmitted SYN-ACK can still
hit the defect; no run has shown it.

## Evidence

- Hosted corpus: exercised by `gate.sh corpus` at each head that runs it; the
  result belongs to that head and compiler only.
- QEMU: the stack runs as a process in a Linux guest over AF_PACKET, KVM
  virtio-net against QEMU's slirp. That exercises it; it proves nothing. No
  QEMU result is committed in this tree. The one earlier recorded run (aienux
  commit 468c8efd, `GATE_PASS runs=12`) used omc 6d1b1cf5, which `gate.sh` now
  refuses, and a `tcp.om` that has changed since, so it is not evidence for this
  code; that commit's title said "proved in QEMU", which overstated it.
- Hardware: NOT_RUN. The stack is not bound into the AIENOS kernel's
  virtio-net driver.

## Limits and deviations (not claimed)

- One connection at a time; no window scaling, SACK or timestamps; receive
  window 65,535 bytes; TIME-WAIT is 1 s (`Tcf 8`), not 2 MSL of minutes. A
  passive block whose SYN-ACK is never answered returns to LISTEN when its
  retries run out (12 retransmissions, given up at the 13th timeout, 483 s),
  as it does on an exact RST.
  Until then every other client's SYN gets a RST, so one unanswered SYN
  every 8 minutes keeps the only listener busy.
- No FIN-WAIT-2 timeout and no keep-alive: a peer that never sends its FIN
  keeps the only block in FIN-WAIT-2. A peer that keeps answering zero-window
  probes keeps a connection open indefinitely (RFC 1122 4.2.2.17); probes back
  off to one per 60 s. Bounding either is the embedding application's job.
- Urgent data is not supported: URG and the urgent pointer are ignored on
  input and never sent (RFC 9293 3.8.5 requires them).
- No sender silly-window avoidance and no Nagle algorithm (RFC 9293 3.8.6.2.1,
  RFC 1122 4.2.3.4): every write goes out as soon as the windows allow, in
  segments as small as the data. Receiver-side window updates do wait for a
  full segment of space.
- The initial congestion window is 10 segments (RFC 6928), not the at most 4 of
  RFC 5681; after a lost SYN or SYN-ACK it is 1 segment (RFC 5681 3.1).
- RTO (RFC 6298): the minimum is 200 ms (`Tcf 10`), below the 1 s of rule 2.4
  (a SHOULD), so recovery on a fast link does not wait a full second; the
  maximum is 60 s (rule 2.5); the clock is in milliseconds.
- Initial sequence numbers (RFC 6528): ISN = M + F modulo 2^32, F the low 32
  bits of SipHash-2-4 over own IPv4, peer IPv4, own port and peer port under a
  128-bit key, M a 4 microsecond clock taken from the millisecond clock (it
  steps by 250 once per millisecond). The key comes from the embedder's entropy
  source; under `tcpd` that is the Linux guest's `getrandom(2)`, and a short
  read stops `tcpd` before any connection. Bound into the AIENOS kernel it would
  have to come from the kernel's RNDR entropy service, which refuses rather
  than falls back; that binding does not exist. The key is never rotated.
  `tcpd`'s ephemeral port is 40000 plus 14 bits of SipHash over a counter.
- Blind in-window forgery is inherent to TCP without authentication: an
  attacker who knows the 4-tuple and lands a sequence number exactly at
  RCV.NXT can reset the connection (RFC 5961 narrows this to one exact value).
  With RFC 6528 numbers an off-path host cannot compute another
  connection's ISN from the ISNs it sees on its own without the key (the corpus checks
  each 4-tuple field and a Berlekamp-Massey predictor over 512 observations);
  an on-path host can still reset or inject, as nothing authenticates segments.
  The QEMU hostile profile therefore injects only frames a correct stack must
  refuse in every state: on handshake segments (SYN set or ACK clear) only the
  malformed kinds 0 to 5, on ARP only garbage frames, because a RST with an
  acceptable ACK or a SYN-ACK with a foreign ISS is legal there. Exact-state
  cases (in-window RST, SYN, ACK range, SYN-SENT reset) are in the corpus.
- Challenge ACKs (RFC 5961 sections 3 to 5) are not rate limited (section 7
  recommends a limit): every forged in-window RST or SYN, or out-of-range ACK,
  gets one ACK.
- Frames to the Ethernet broadcast address are taken only for ARP; IPv4 to a
  broadcast or multicast MAC, or to any IPv4 address but our own, is dropped.
- Fixed tables: 4 ARP entries reused round robin (any on-link host can evict
  the gateway entry, as ARP is unauthenticated) and one connection block. The
  drivers' main loops (`tcpd` 100,000,000 passes, `link` 1,000,000,000) trap
  if ever reached; the gate's deadlines (QEMU 200 s, link 230 s) end a run
  long before that.
- ARP is unauthenticated (RFC 826).
- QEMU only (see Evidence); not run on hardware.
- Unasserted edits: the single-line edits `mutgen.awk` makes of the functions
  `gate.sh` names (`GEN_FNS`) that no corpus case kills. Each is equivalent to the
  code (the reason follows it) or, where marked, differs in a case the corpus does
  not build. `gate.sh corpus` requires the survivors to be exactly these rows.

<!-- unasserted -->
- `tsample` 1: `if lt r s` -> `if le r s`: at R = SRTT the difference is 0 either way.
- `tsample` 1: `put Tcb kSRT umax add sub w div w 8 r 1` -> `put Tcb kSRT umax add sub w div w 8 r 0`: once kSRT is nonzero, 8 SRTT - SRTT + R is at least 1; the floor only keeps 0 meaning "no sample yet".
- `tsample` 1: `o = add div get Tcb kSRT 8 umax get Tcb kRVR 1` -> `o = add div get Tcb kSRT 8 umax get Tcb kRVR 0`: RTTVAR is 0 only after 0 ms samples, where SRTT/8 is 0 and the RTO floor (`Tcf 10`, never 0 after `tinit`) gives the same RTO.
- `tretx1` 1: `if ne get Tcb kFSN 0` -> `if true`: with no data outstanding, `tretx1` runs only while our FIN is the octet outstanding.
- `tretx1` 1: `if eq u get Tcb kFSQ` -> `if true`: as above; SND.UNA is then the FIN's sequence number.
- `tnewack` 1: `put Tcb kSYA 1` -> `put Tcb kSYA 2`: a flag only compared with 0.
- `tnewack` 1: `if gt sub n d 0` -> `if ge sub n d 0`: the guarded line adds n - d, which is 0 where the conditions differ.
- `tnewack` 1: `if gt sub n d 0` -> `if gt add n d 0`: as above.
- `tnewack` 1: `if gt sub n d 0` -> `if true`: as above.
- `tnewack` 1: `if slt get Tcb kNXT get Tcb kUNA` -> `if sle get Tcb kNXT get Tcb kUNA`: at equality the assignment changes nothing.
- `twinupd` 1: `a = get Tpk 9` -> `a = get Tpk 10`: the SND.WL2 test decides only when SEG.SEQ = SND.WL1, and under the SND.UNA =< SEG.ACK rule SND.WL2 =< SEG.ACK always holds (RFC 9293 still states it); a value read the same way from every segment keeps it true.
- `twinupd` 1: `a = get Tpk 9` -> `a = get Tpk 8`: as above.
- `twinupd` 1: `if or slt w1 s and eq w1 s sle get Tcb kWL2 a` -> `if or sle w1 s and eq w1 s sle get Tcb kWL2 a`: as above (at SEG.SEQ = SND.WL1 the SND.WL2 test holds).
- `twinupd` 1: `put Tcb kWL2 a` -> `note mutant`: as above.
- `tfinacked` 1: `if eq get Tcb kFSN 0` -> `if false`: `tfinacked` is called only in FIN-WAIT-1, CLOSING and LAST-ACK, after our FIN went out.
- `tfinacked` 1: `ret false` -> `ret true`: as above.
- `tackin` 1: `put Tcb kACK 1` -> `put Tcb kACK 2`: a flag only compared with 0.
- `tackin` 2: `put Tcb kACK 1` -> `put Tcb kACK 2`: as above.
- `tackin` 2: `st = get Tcb kST` -> `note mutant`: inside `tackin` the state changes only from syn-received to ESTABLISHED, and neither has a FIN of ours to acknowledge.
- `tfinacc` 1: `put Tcb kPFN 1` -> `put Tcb kPFN 2`: a flag only compared with 0.
- `tfinacc` 1: `put Tcb kACK 1` -> `put Tcb kACK 2`: as above.
- `tfinacc` 1: `put Tcb kACK 1` -> `note mutant`: every caller has already set kACK for the same segment.
- `tfinacc` 1: `if eq st 6` -> `if true`: `tfinacc` runs in states 4 to 6 only, and 4 and 5 return before this line.
- `tdrain` 1: `while lt c 65535 bound 65536` -> `while le c 65535 bound 65536`: no byte is stored 65535 past the read head (`tstore` stores inside the window), so the extra pass finds none.
- `tdrain` 1: `while lt c 65535 bound 65536` -> `while lt c 65536 bound 65536`: as above.
- `tdata` 1: `if or lt st 4 gt st 6` -> `if or lt st 3 gt st 6`: syn-received never reaches `tdata` (`tackin` refuses the segment or moves the block to ESTABLISHED).
- `tdata` 1: `put Tcb kACK 1` -> `put Tcb kACK 2`: a flag only compared with 0.
- `tfinin` 1: `put Tcb kACK 1` -> `put Tcb kACK 2`: as above.
- `tfinin` 2: `put Tcb kACK 1` -> `put Tcb kACK 2`: as above.
- `tfinin` 2: `put Tcb kACK 1` -> `note mutant`: a FIN past the window comes only on a segment with data (a bare one is unacceptable), for which `tdata` has set kACK.
- `tfinin` 3: `put Tcb kACK 1` -> `put Tcb kACK 2`: a flag only compared with 0.
- `ttimeout` 1: `put Tcb kSYT 1` -> `put Tcb kSYT 2`: as above.
- `ttimeout` 2: `put Tcb kSYT 1` -> `put Tcb kSYT 2`: as above.
- `tprobe` 1: `if slt get Tcb kMAX get Tcb kNXT` -> `if sle get Tcb kMAX get Tcb kNXT`: at equality the assignment changes nothing.
- `tpersist` 1: `if not tcansend` -> `if false`: in every state that cannot send, the next checks return (nothing unsent, or SND.UNA < SND.MAX while the SYN is outstanding).
- `tpersist` 1: `put Tcb kPRS umax add n get Tcb kRTO 1` -> `put Tcb kPRS umax add n get Tcb kRTO 2`: differs only by 1 ms when the clock reads 0 and the RTO floor is 1 ms; no case does that (the floor keeps 0 meaning "not armed").
- `tpersist` 1: `put Tcb kPRS umax add n get Tcb kRTO 1` -> `put Tcb kPRS umax add n get Tcb kRTO 0`: now + RTO is at least 1, as the RTO floor is.
- `tpersist` 1: `put Tcb kRAT 0` -> `note mutant`: no RTT measurement runs when the persist timer fires (nothing is outstanding, so the timed segment was acknowledged and kRAT cleared).
- `tread` 1: `n = umin get Tcb kRCN umin cap 65536` -> `n = umin get Tcb kRCN umin cap 65537`: kRCN is at most 65535 and bounds n first.
- `tread` 1: `n = umin get Tcb kRCN umin cap 65536` -> `n = umin get Tcb kRCN umin cap 65535`: as above.
<!-- /unasserted -->
