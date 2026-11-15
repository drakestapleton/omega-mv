# FR-3: imports by digest

A module is imported by the SHA-256 of its canonical source bytes. The import
line carries no path and no module name. The compiler pin stays in the
sidecar `seed/out/omc.sha256`. The two hashes are of different bytes, and both
have to match.

This is the module driver `seed/modules/driver.om` (command name `ommod`),
specified in `spec/omegese-modules.md`. Units are not pasted together. Each
module is compiled on its own, stored under the digest, and linked by checked
native calls.

## Import syntax

A module source starts at byte 0 with `om2` or `om2 release`, and that line
selects the profile (`debug` or `release`). One import is one line:

```text
import localAlias SOURCE_SHA256 exportedName
```

`SOURCE_SHA256` is 64 lowercase hex digits. `localAlias` is the name this
module calls. `exportedName` is one function the dependency marks with
`export fn`. Fields are single ASCII spaces. Leading spaces before `import`
are allowed. Nothing else is allowed on the line. Aliases are unique in the
module. A handwritten `extern` line is refused. Private functions of the
dependency never become names in the importer.

Program entry is an exported function with no arguments, returning `int` or
`void`. The process exit status is that `int`, or 0 for `void`.

## Hash and canonical bytes

The hash is SHA-256 (FIPS 180-4), lowercase hex. The implementation is
`seed/ng/sha256.om`, linked into the driver. The message is the source file
as read: byte 0 through the last byte, with no newline conversion, no
stripped import lines, and no added profile line. Those bytes are also the
bytes stored in the artifact at offset 176, length S, and the artifact's
source field is the same 64 ASCII hex digits.

The driver checks that SHA-256 of the file it just read equals the
`SOURCE_SHA256` argument of `build` before it compiles. A caller who passes a
digest of different bytes is refused before a module is published.

## Resolution

`build` and `link` take a store directory. The import line does not. The
store key is SHA-256 of these 152 bytes, little-endian where noted:

| Bytes | Contents |
| --- | --- |
| 8 | `OMMOD001` |
| 64 | compiler executable SHA-256, ASCII hex |
| 64 | source SHA-256, ASCII hex |
| 8 | profile, 0 debug or 1 release |
| 8 | target, 1 for `aarch64-linux` |

`KEY.ref` holds 64 ASCII bytes, the artifact digest, and no newline.
`ARTIFACT.mod` is named by SHA-256 of its own bytes. The reference is only a
locator. The driver hashes the artifact, checks the compiler, source,
profile and target fields, and checks each dependency's artifact digest
against the digest recorded in its parent.

A different compiler, profile or target is a different key. It does not
reuse a module that happens to have the same source digest.

## Mismatch and missing

Both refusals exit nonzero, write a named line to stderr, and publish no
final output. Link renames into place only after the image is built, so a
refused link leaves the destination absent. A refused build does not publish
a new artifact.

| What happened | Exit | Stderr name |
| --- | --- | --- |
| Stored bytes, or the file passed to `build`, do not hash to the digest that names them. A one-byte change is this case. | 24 | `ommod: digest-mismatch` |
| No `KEY.ref` for that source digest under this compiler, profile and target, or the reference's artifact file is not in the store. | 34 | `ommod: digest-missing` |

Other refusals keep their numeric codes from `spec/omegese-modules.md` and
the line `ommod: refused (code below)`. Code 24 is only a digest mismatch, so
that name is part of every exit 24. Exit 34 is also used for a malformed
artifact; the name `digest-missing` is written only when the store open
returns "no such file".

## Sidecar composition

`seed/out/omc.sha256` is a `sha256sum` line for the compiler binary:

```text
<64 hex digits>  seed/out/omc
```

`seed/omega-from-seed.sh` writes that line from the compiler it just built.
`build` takes those 64 digits as `COMPILER_SHA256` and checks them against
the compiler file it loads. The same 64 digits are stored in the artifact at
offset 8. An import therefore resolves only for the compiler the sidecar
names. Replacing `seed/out/omc` without updating the sidecar, or updating the
sidecar without the binary, makes `sha256sum -c seed/out/omc.sha256` fail, and
a module built under the other pin does not resolve.

The import digest does not replace the sidecar, and the sidecar does not
replace the import digest. Source bytes and compiler bytes each have their
own hash. `.sha256` sidecars elsewhere in the tree (the compiler, fixtures,
bench outputs) are the same kind of record: hash, two spaces, path. They are
not store keys.

## Units

`seed/modules/fr3-gate.sh` builds the driver with `seed/out/omc`, then:

- `seed/modules/fr3/leaf.om` is imported by its real digest, linked, and the
  program exits 7.
- One byte flipped in that stored module is refused with `digest-mismatch`.
- `seed/modules/fr3/missing.om` names a digest that is not in the store and
  is refused with `digest-missing`.
- Linking the good program twice yields the same output SHA-256.
