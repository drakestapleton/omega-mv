# FR-3: imports by digest

A module is imported by the SHA-256 of its source bytes. The import line
carries no path and no module name. The compiler pin stays in the sidecar
`seed/out/omc.sha256`. The two hashes are of different bytes, and both have
to match.

This is the module driver `seed/modules/driver.om` (command name `ommod`).
Units are not pasted together. Each module is compiled on its own, stored
under the digest, and linked by checked native calls.

`spec/omegese-modules.md` is the one normative text. It defines the import
line, the commands, the artifact layout, the store key and `KEY.ref`, and the
refusal codes, including the two named stderr lines `ommod: digest-mismatch`
(exit 24) and `ommod: digest-missing` (exit 34). This page does not restate
them; it records what FR-3 adds and how the gate shows it.

## What the digest covers

The digest is SHA-256 (`seed/ng/sha256.om`, linked into the driver) of the
source file as read: byte 0 through the last byte, with no newline
conversion and no stripped import lines. `build` checks that digest against
its `SOURCE_SHA256` argument before it compiles, so a caller who passes a
digest of different bytes is refused before a module is published.

## Sidecar composition

`seed/out/omc.sha256` is a `sha256sum` line for the compiler binary:

```text
<64 hex digits>  seed/out/omc
```

`seed/omega-from-seed.sh` writes that line from the compiler it just built.
`build` takes a `COMPILER_SHA256` argument, checks it against the compiler
file it loads, and the store key binds it. `ommod` does not read the
sidecar itself: `seed/modules/fr3-gate.sh` passes the sidecar's 64 digits
as that argument after `sha256sum -c seed/out/omc.sha256` succeeds. An
import therefore resolves only for the compiler digest the caller passed,
and a module built under another compiler digest does not resolve.

The import digest does not replace the sidecar, and the sidecar does not
replace the import digest. `.sha256` sidecars elsewhere in the tree (the
compiler, fixtures, bench outputs) are the same kind of record: hash, two
spaces, path. They are not store keys.

## Units

`seed/modules/fr3-gate.sh` builds the driver with `seed/out/omc`, then:

- `seed/modules/fr3/leaf.om` is imported by its real digest, linked, and the
  program exits 7.
- Linking the good program twice from the same store yields the same output
  SHA-256. This shows `link` is deterministic over identical inputs; it is
  not a rebuild from a fresh store.
- One byte flipped in that stored module is refused with `digest-mismatch`,
  and the link output is not created.
- `seed/modules/fr3/missing.om` names a digest that is not in the store and
  is refused with `digest-missing`; the store holds the same files before and
  after the refused build.
- `build` with a source digest that does not match the source file, and
  `build` with a `COMPILER_SHA256` that does not match the compiler file,
  are each refused with `digest-mismatch`.
- Linking after the referenced module file is removed from the store
  (its `KEY.ref` still present) is refused with `digest-missing`, and the
  link output is not created.

Each unit prints `PASS <unit>`; a failed unit prints `FAIL <unit>` with what
it saw to stderr and the gate exits 1.
