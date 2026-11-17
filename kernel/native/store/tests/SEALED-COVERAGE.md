# Sealed store: coverage matrix (rollback and nonce safety)

This file covers `store_sealed.c` and the tests in this directory. Every run is a host emulation over image files: there is no real disk, no live volume, no key rotation and no GPU. Each row names the test that asserts the property, and the `GUARD:` mutants that `make mutants` deletes, each of which some test must then catch.

A mutant counts as killed only when a test exits 1 and prints its own `STORE_*: FAIL` or `TORN_SLOT_RULES: FAIL` verdict. For store mutants, a UBSan report of the invalid access also counts. A crash, a signal, any other exit status, a build or link failure, or a gate timeout never counts. See the comment on the `mutants` rule in the `Makefile`.

The samples below are finite and collision-free. They are regression checks, not proof that values are unique without condition. Uniqueness rests on HMAC-SHA256 and SHA-256 behaving as PRFs and collision-resistant hashes.

## Key scope, objects and chunks

| Item | Mapping |
|---|---|
| Key scope | `k_domain` of one store (`ss_keys`). The rig derives it from seed `0x11` (class production, `key_generation` 1). `K_OTHER` (seed `0x22`) is an unrelated scope. |
| Envelope id and nonce prefix | `HMAC(HKDF-Expand(k_domain, "AIENOS-SEALED-ENVID-KEY-V2\0", 32), "AIENOS-SEALED-ENVID-V2\0" ‖ uuid ‖ gen u64 ‖ index u32 ‖ kind u16 ‖ version u16 ‖ key_generation u64 ‖ class u8 ‖ len u64 ‖ SHA-256(pt))`. Bytes 0..15 are the envelope id, an input to the per-object key. Bytes 16..23 are the nonce prefix. Everything is little-endian. |
| Chunk nonce | nonce prefix ‖ chunk index u32 (12 bytes), under the per-object AES-GCM-SIV key (`native/m5`), with `SS_CHUNK` = 4096 B. |
| Synthetic ids | store `RIG_UUID`. Gen 2: index 0 is kind 40 v1, 700 B (1 chunk); index 1 is kind 41 v2, 9000 B (3 chunks). Gen 3: index 0 is kind 42 v1, 600 B. `test_envid_oracle` prints this line. |

Pairs only need to be new within one key scope, and the tests ask nothing more. They never require nonce bytes to be unique across unrelated keys. `test_envid_oracle` only checks that another `k_domain` gives a different pair.

## Matrix

| Property | What is asserted | Test (`store_sealed_test.c` unless named) | Mutants |
|---|---|---|---|
| **Confidentiality under nonce misuse** (rollback, then rewrite) | After a whole-disk rollback to gen 2, a rewrite of gen 3 with different bytes gives a new envelope id and nonce prefix, 24 rounds in a row. A one-bit change gives a new pair, and so does a kind change. The identical object at the identical place gives the identical pair: deterministic, and it shows nothing the old image did not. | `test_nonce` | `envid-plaintext`, `envid-kind` |
| | Every bound field, checked against an **independent oracle**: HMAC-SHA256 (RFC 2104) and HKDF-Expand (RFC 5869) written in the test over SHA-256 alone, pinned by FIPS 180 "abc", RFC 4231 cases 1–2 and RFC 5869 case 1. The stored pairs of gen 2 objects 0 and 1, and of every gen 3 rewrite, must equal the oracle. | `test_envid_oracle`, `test_nonce` | `envid-store`, `envid-generation`, `envid-index`, `envid-kind`, `envid-version`, `envid-key-generation`, `envid-class`, `envid-length`, `envid-plaintext`, `envid-domain` |
| | The old predictable V1 id (SHA-256 of uuid ‖ gen ‖ 0) is not produced. A V1-sealed envelope with valid digests mounts but is refused on read, and the output buffer is wiped. | `test_nonce` | The V1 derivation cannot be expressed as a deleted line. The oracle refuses any change to the derivation; the PR that added this file records the replacement mutant run. |
| | AES-GCM-SIV against its published vectors, plus the chunk AAD and nonce layout. | `native/crypto/tests/crypto_test.c` (RFC 8452), `native/m5/tests/m5_test.c` | (crypto and m5 suites) |
| **Authentication** | Flipped envelope bytes, a forged commit, wrong store or class, a bad transaction MAC or magic, an unclaimed or twice-claimed envelope, a forged keyslot chain: each is refused with its typed error. | `test_forgery`, `test_identity`, `test_keyslot` | `tx-mac`, `tx-class`, `tx-store`, `commit-*`, `claim-*`, `envelope-digest`, `unclaimed-envelope`, `keyslot-*` |
| **Replay** | A version-1 transaction record is refused (`SS_E_FORMAT_VERSION`). So are a replayed or duplicate record, a generation gap or skip, a counter mismatch, a broken chain, a forked anchor at the same counter, an anchor naming another store, and a duplicate anchor sequence. | `test_nonce`, `test_forgery`, `test_rollback` | `tx-version-1`, `tx-counter`, `tx-gen-range`, `tx-duplicate`, `tx-gap`, `tx-chain`, `anchor-record-class`, `anchor-record-store`, `anchor-region` |
| **Crash consistency** | Power cut at every block boundary of one sealed transaction (512 B and 4 KiB): the reopened image shows exactly the old state or exactly the new one. A crash between the Store commit and the anchor leaves the anchor one behind (prepared advance), twice, and the next transaction catches up. Torn anchor slots are covered by the torn_slot rules. | `store_powercut_test.c` `sealed_cuts`, `test_anchor_crash`, `torn_slot_test.c` | `anchor-catch-up`, the torn_slot `GUARDS` |
| **Store-only and anchor-only rollback** | Store rolled back one or two generations under the current anchor: `SS_E_ROLLBACK`. Anchor one behind: accepted as the crash window (`SS_RB_PREPARED_ADVANCE`). Anchor two behind: `SS_E_INCONSISTENT`. Anchor missing after genesis: `SS_E_ROLLBACK`. | `test_rollback`, `test_nonce` | `anchor-*` |
| **Whole-image freshness** | **Not detected (documented limit).** Rolling back the Store and the anchor together mounts at the stale generation and reports a valid resume. The test asserts exactly that, so a successful mount is never counted as freshness. | `test_rollback` ("LIMITATION") | none |

## Whole-image freshness needs an external trust anchor

The disk alone cannot tell a whole-image rollback from the real state, because both regions are self-consistent. Freshness needs a monotonic counter that the attacker cannot roll back with the disk, such as a TPM NV counter (TRUST-1). The store's anchor generation is compared against that counter at open. That work belongs to [aienux#32](https://github.com/aien-dev/aienux/issues/32). This file adds no TPM code and no on-disk format change.

## Reproduce

From a checkout at the pinned revision, run `make -C native/store test mutants`. It ends with `AIENOS_STORE_NATIVE: PASS`, `TORN_SLOT_MUTANTS: PASS` and `AIENOS_STORE_MUTANTS: PASS`. The shared gate `tests/gates/aienos-store-native.gate` (`tests/gates/run.sh store-native`) runs the same command.
