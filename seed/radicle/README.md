# Radicle request boundary pilot

`adapter.om` is a first-party Omega request validator and host-tool boundary for
DRA-445. It is a component, **not a deployed CI adapter or a scheduler**. It reads
one Radicle CI v1 patch trigger from stdin and a trusted context file from argv[1].
It emits a bounded JSON ticket, or passes that ticket on stdin to the absolute
host executable configured in argv[2], through the existing `execprog` boundary.
No shell interpolation, environment inheritance, new queue, journal or permission
owner is introduced. It reuses `seed/json/json.om`.

The context supplies `status=active`, `rid`, `patch`, `revision`, `candidate`,
`base`, `toolchain`, `task`, `attempt`, `generation`, and `policy`. Hashes use full
lowercase hex. Generation is a canonical positive decimal string within the
existing cockpit's 2^53-1 limit. The broker's repository, patch, current head,
first commit, selected revision head and revision base must agree. Only Created
or Updated events for open patches are supported. Duplicate bound JSON keys and
ambiguous selected revisions are refused. Titles and descriptions never become
commands.

The context is a **trusted input**, not proof of admission. Its authentication,
immutability and freshness belong to the existing authority. The validator does
not compare `toolchain` to a running binary, hash an integration tree, authenticate
a signer or enforce cancellation after host dispatch. A malicious trusted context
or host program is outside this component's protection. Consumers must not expose
argv[1] or argv[2] to candidate-controlled configuration.

## Build and checks

From the repository root, on Linux AArch64:

```sh
sh seed/radicle/check.sh /absolute/new/output/directory
```

The check pins the canonical compiler SHA-256, composes the existing JSON reader
and this fragment, and executes the Python JSON oracle against the resulting
native binary. Python and the shell are verification tools only. The fixture
records public catalog patch 527569162000cd15db2eeecb7cf09c343dc2475d, revision with
the same ID, candidate 049356cbf40e7238fa1c206a9f58f58d60575bdd, and base
1a7aa1e50a226af3e1f925d240def8f71f4252f8. The test constructs a broker wire fixture
from that fetched metadata; it is not a captured live broker delivery.

Exit statuses: 2 usage; 20 input/read limit; 21 invalid JSON or duplicate bound
key; 22 missing/malformed field; 23 identity mismatch or ambiguous revision;
24 unsupported or cancelled state; 25 ticket capacity; 26 I/O/wait failure;
27 failed host exec; 28 signalled host. Otherwise the host's exit status propagates.
No `success` or `triggered` response is synthesized. Configured host execution is
trusted, synchronous and bounded by the caller's timeout/cancellation mechanism.

## Integration limit and next boundary

The installed `aien-local-ci trigger REPO SHA` writes a repository/head trigger.
It has no base/toolchain/attempt input and no bound cancellation/reconciliation
operation. Calling it and reporting CI success would violate this contract.
The unmerged Omega Node stack at dfe157917 contains scheduler/auth/journal
components but is absent from canonical main and documents that live-hive
integration is unfinished. The cockpit's Core #925 task API owns durable command
replay, generation and attempt transitions; retain that owner.

The next integration must extend the incumbent host adapter to accept this ticket,
resolve it inside its durable authority, preserve all fields, expose idempotent
status and cancellation, and return the official broker `triggered` and `finished`
messages only from that recorded result. This component must not be installed as
`cib`'s executable until that boundary and its process/crash tests exist.

Duplicate/restart tests here prove deterministic normalization across independent
processes. They **do not** prove idempotent scheduling, durable result replay,
revocation races, cancellation of running jobs, or exactly-once external effects.
Those acceptance rows stay NOT_RUN. No shared scheduler or service is changed.

## Upstream interface pins

- `radicle-ci-adapter` 0.1.1, published source commit
  8ac2f7728d7b5aedd1b128927c63c0216653d194 (`adapterlib`). Crate archive SHA-256
  6f0a73c642801805b86b61c87f3f19e9dd04b0d49ec7b10b037a7f4279a4b80d.
  [Official source/API](https://docs.rs/radicle-ci-adapter/0.1.1/radicle_ci_adapter/).
  This protocol is newline-delimited JSON; triggered carries a run_id object and
  optional info_url, finished carries success/failure. No cancellation message
  exists in this pinned request enum.
- `radicle-artifact` 0.23.3, source commit
  ab598682e255465b59c757e23aa3df6ad02f6719. Crate archive SHA-256
  2553bce0960e5c0d0878b4fdf0395fb8053fb9282113d11992ae94a5e272f65b.
  [Official repository](https://radicle.norman.life/z4VYyJ9KuwMNkXGQnmKuGPGKw3inv.git).
  `register` records signed discovery metadata, not bytes; `download`/`fetch`
  require the artifact daemon even with HTTP locations; `verify` checks cached
  bytes against local COB metadata without a daemon. `attest` does not rehash.
  No artifact daemon or new upstream runtime dependency was installed in this pilot.

## Public restore pilot

A fresh isolated Radicle 1.10.3 profile fetched omega-mv from the external Rosa
peer, including the exact catalog patch, Git objects, identity and parent-level
signed refs. After stopping that isolated node, a network-disabled `bwrap` process
used only restored files: checked the compiler hash, compiled the resolver,
expanded and compiled item76666, and observed its expected exit 82. Repeated
cached builds matched byte-for-byte. A mutated catalog lock was refused with 11,
empty stdout and no map.

This proves restoration of the public **Git-tracked compiler/catalog artifacts**,
not `radicle-artifact` blob/collection retention. It is a fresh logical peer on
the same Spark, with externally retained source, not an independent restore
machine or an accepted release. No private files, keys, weights or journals were
published. No upstream defect was reproduced, so no upstream regression or
maintainer contact was created.
