# native/net/tcp: native TCP in seeded Omega (ledger L232)

TCP over IPv4 and ARP, written in Omega and built by the pinned seeded `omc`
(omega-mv `1e3ecbba779ee84e2de70ec231e83533a9c61f45`, `seed/out/omc` sha256
`6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`, rebuilt
from the seed with an identical hash). No C, no heap, no outside library in the
stack or its drivers.

| File | What it is |
|---|---|
| `tcp.om` | The stack: Ethernet II, ARP (4 entries), IPv4 (no options sent, fragments refused), TCP per RFC 9293 with RFC 6298 RTO, RFC 5681/6582 NewReno congestion control and fast retransmit, RFC 5961 RST/SYN/ACK hardening, out-of-order reassembly into a 64 KiB ring (first copy wins), FIN ordering, TIME-WAIT, zero-window probing. One connection block plus one passive port. The embedding unit supplies `tlinkout` and the clock. |
| `tcpd.om` | Guest driver (`cat tcp.om tcpd.om \| omc`). Runs as a process inside a Linux guest: rtnetlink brings `eth0` up with GRO off, an AF_PACKET socket carries raw frames. The guest kernel has no IPv4 address, so this stack alone answers for 10.0.2.15. Modes: echo, receive to file, send a file. |
| `link.om` | Impairment relay between the guest NIC and QEMU's slirp network: seeded drop, hold-back reordering, duplication, and hostile injection toward the guest (15 kinds, see the `lmutate` note). Hostile variants go ahead of the real frame. |
| `peer.om` | Host peer on 127.0.0.1 (slirp forwards into the guest): echo check, send, receive and compare. |
| `corpus.om` | Hosted hostile corpus (`cat tcp.om corpus.om \| omc`): exact-state cases, a seeded fuzz phase with invariants, and a final transfer whose sequence numbers wrap past 2^32. |
| `gate.sh` | The gate (verification rig, POSIX sh): checks the compiler pin, builds everything, runs the corpus, then boots one fresh QEMU guest per profile and scenario. |

## Gate

```
sh gate.sh OMC IMAGE BUSYBOX OUTDIR [PROFILES] [SCENARIOS]
```

Profiles (per mille, per direction): `clean` (none), `loss` (3% drop),
`reorder` (15% held back 1 to 3 frames or 40 ms), `hostile` (2% drop, 10%
reorder, 2% duplicate, 20% hostile injection toward the guest). Scenarios:
`echo` (1 MiB echoed back to the host), `h2g` (2,000,000 bytes host to guest,
digest checked in the guest with busybox `sha256sum`), `g2h` (the 1,914,704 byte
busybox binary guest to host). A run passes only when the peer, the guest
stack, QEMU's exit and the digest all agree (echo bytes are compared one by
one by `peer.om`), and the link log proves the profile's impairments happened;
a hostile run must have injected all 15 kinds. The corpus runs 2,000,000 fuzz
frames by default (`FUZZ=`).

Verification-only dependencies (not in the stack): QEMU `qemu-system-aarch64`
with KVM, a Linux arm64 `Image` with virtio-net and AF_PACKET, a static
aarch64 busybox (guest init, `sha256sum`, and the g2h payload), POSIX sh,
gzip, cpio, sha256sum.

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

## Limits (not claimed)

- One connection at a time; no window scaling, SACK or timestamps; receive
  window 65,535 bytes; TIME-WAIT is 1 s (`Tcf 8`), not 2 MSL of minutes.
- Blind in-window forgery is inherent to TCP without authentication: an
  attacker who knows the 4-tuple and lands a sequence number exactly at
  RCV.NXT can reset the connection (RFC 5961 narrows this to one exact value).
  The QEMU hostile profile therefore injects only frames a correct stack must
  refuse in every state: on handshake segments (SYN set or ACK clear) only the
  malformed kinds 0 to 5, on ARP only garbage frames, because a RST with an
  acceptable ACK or a SYN-ACK with a foreign ISS is legal there. Exact-state
  cases (in-window RST, SYN, ACK range, SYN-SENT reset) are in the corpus.
- ARP is unauthenticated (RFC 826).
- QEMU only. The stack runs as a Linux guest process over AF_PACKET; it is not
  bound into the AIENOS kernel's virtio-net driver and has not run on hardware.
