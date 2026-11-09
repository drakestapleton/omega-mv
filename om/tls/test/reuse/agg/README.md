# Gate 3 adapters (#639): the protections of three other repositories

`gate3.plan` runs each repository's own tests for the reuse-sensitive protections #639 names
(controls) and real one-site source mutants that must build and fail at the intended assertion
(mutants), through `../aggregate.om`. Run it with the other plans through `../agg.sh` (see
`../README.md`); its rows never take the pool lock themselves.

## Checkouts

Each repository is checked out detached at its pin, clean, under `build/tls/reuse/src/`:

| Directory | Repository | Pin | Source |
| --- | --- | --- | --- |
| `oh` | Open Humanity | `d929a34d61716a347506fe3e64e2a09a0fddf317` | the GitHub main history; Radicle OH main `f68d7a2` is an unrelated genesis history without the #29 to #31 fixes |
| `ux` | aienux | `c874c3b737626d8c588c04cfa37019e9dde56964` | Radicle `rad:z2Q6ob2gL6Qo5oUMpyehukayVF7mN` main |
| `sc` | Sovereign Core | `314c0cc2360c75fd44edfc55ae22db036e792e96` | Radicle `rad:z44GqrPVAPjZkhoD2MWVjqy18ighN` |

```
git clone --no-checkout SOURCE build/tls/reuse/src/DIR && git -C build/tls/reuse/src/DIR checkout --detach PIN
```

A missing checkout makes its rows NOT_RUN (the `cwd` is absent); a checkout at another commit or
with local changes fails the `*-head` and `*-clean` rows, and every later row of that repository
is NOT_RUN through `after`.

## Rows

Deadlines are at least three times the durations measured on the Spark from a cold build (for example
`oh-control` 30.5 s with `time 180`, `ux-store-control` 116 s with `time 360`, `sc-control` 76 s
with `time 240`). Cargo keeps its build caches in `build/tls/reuse/target-oh` and
`build/tls/reuse/target-sc` (`CARGO_TARGET_DIR`), which `agg.sh` does not remove, so later runs are
faster. A first run on a slower host can pass a deadline; that row is INVALID (status 124), never
PASS, and a rerun with the warm caches settles it.

- Toolchain: `rustc 1.98.1`, `cargo 1.98.1`, `cc 13.3.0` exact version lines.
- Controls: `oh-control` (beacon-core and oh-core unit tests, 15 named tests and both totals),
  `ux-store-control` and `ux-crypto-control` (`make test mutants` in `native/store` and
  `native/crypto`), `sc-control` (aien-kv-store, the seal_nonce tests and all three totals).
- Mutants, each applied from a sha-bound diff in `mutants/`, then restored with `git apply -R` of
  the same diff and checked clean. The restore depends on the apply row, so an INVALID mutant is
  still restored.

| Mutant | Protection | Killing assertion |
| --- | --- | --- |
| `oh-replay-clear` | #29 replay cache refuses at capacity | `test_replay_capacity_two_keeps_history` |
| `oh-encrypt-unchecked` | #30 contributory X25519 on encrypt | `test_encrypt_to_peer_refuses_low_order_keys` |
| `oh-decrypt-unchecked` | #30 contributory X25519 on decrypt | `test_decrypt_from_peer_refuses_low_order_ephemeral` |
| `oh-recv-exhaustion` | #31 receive counter never wraps | `test_recv_counter_exhausted_never_wraps` |
| `oh-send-exhaustion` | #31 send counter never wraps (nonce reuse) | `test_send_counter_last_record_then_exhausted` |
| `oh-session-unbound` | session key binding | `test_record_from_an_old_session_is_rejected` |
| `oh-read-resume` | #31 terminal state after a partial record | `test_eof_inside_a_record_is_terminal` |
| `oh-write-resume` | #31 terminal state after a failed send | `test_failed_send_is_terminal` |
| `ux-v1-predictable-envid` | aienux #445 envelope id and nonce prefix never repeat | `store_sealed_test.c` lines 1113, 1122, 1123, 1135 |
| `sc-m1-entropy-error-dropped` | SC #708 a nonce-source error is returned | `entropy_source_error_returns_random_and_leaves_the_buffer_unchanged` |
| `sc-m2-aad-shortened` | SC #708 the whole region is bound as AAD | `aad_binding_rejects_identity_digest_and_padding_bytes` (byte 300) |
| `sc-m3-aad-removed` | SC #708 AAD present at all | same test (byte 0) |

## Known defects of the pinned trees (not fixed here)

- Open Humanity `d929a34` does not build with `--locked`: its `Cargo.lock` holds thiserror
  2.0.21 while every manifest asks for `"1.0"`. `mutants/oh-lockfix.diff` is the 7-line lock
  that cargo itself resolves offline (thiserror 1.0.69, no source change); the plan applies it
  before the OH rows and removes it at the end. The fix belongs in Open Humanity.
- Open Humanity has no test that the transport keys depend on the handshake transcript: deriving
  them from the DH secret alone passes all 31 `transport::tests`. No mutant row covers transcript
  binding, because no existing test can kill it.
- aienux prints `STORE_RUST_CROSSCHECK: NOT_RUN`; no row claims it.
- Open Humanity's own guard runner `scripts/aienet0/mutants.sh` is not a row (it needs a
  `RECOMPUTE` executable and a whole-workspace build).
