# Native Omega modules, version 1

`seed/modules/driver.om` is the seeded, offline AArch64 Linux module driver.
It compiles each source independently, stores native object bytes by SHA-256,
and links native call relocations. It never joins dependency source into a
compilation. Its only composed source is the driver itself, which reuses the
existing `seed/ng/sha256.om` compression implementation. This version is the
pure function-mode subset; it is not a general shared-library loader.

## Build the driver and check it

From the repository root, with its seeded compiler already built:

```sh
{ printf 'om2\n'; cat seed/ng/sha256.om seed/modules/driver.om; } > /tmp/ommod.om
seed/out/omc < /tmp/ommod.om > /tmp/ommod
chmod +x /tmp/ommod
python3 seed/modules/tests/check.py /absolute/path/to/object-enabled-omc /tmp/modules-check
```

The first two commands must succeed before executing the output. The test
output directory must be new. The test harness is an independent Python/C/ASM
oracle, not a runtime dependency. It derives the compiler and source hashes
from actual bytes and reports them. The native driver has no shell, Python,
C-library, network, or registry dependency. Full seed qualification and the
integration review remain the owning release lane's responsibility.

## Commands and source

Create the chosen store directory first. All paths may be relative to the
original working directory or absolute. Symbolic links in any traversed path
component are refused, including the store and source paths.

```text
ommod build COMPILER COMPILER_SHA256 PROFILE aarch64-linux STORE SOURCE SOURCE_SHA256
ommod link STORE COMPILER_SHA256 PROFILE aarch64-linux SOURCE_SHA256 ARTIFACT_SHA256 program ENTRY OUTPUT
ommod link STORE COMPILER_SHA256 PROFILE aarch64-linux SOURCE_SHA256 ARTIFACT_SHA256 function - OUTPUT
```

`PROFILE` is `debug` or `release`. Hashes are exactly 64 lowercase hex digits.
Build checks both the supplied source digest and compiler executable digest.
Success prints `BUILT ARTIFACT_SHA256` or `CACHE ARTIFACT_SHA256`. A cache hit
hashes the supplied compiler but does not invoke it. Link needs no compiler
file. It requires the exact root artifact digest returned by build.

Source starts at byte zero with `om2\n` or `om2 release\n`, agreeing with the
profile. An import occupies one line:

```text
import localAlias SOURCE_SHA256 exportedName
```

It names one function from a dependency already built in the same store and
compiler/profile/target context. The driver derives a typed `extern fn`
declaration from that dependency's validated object metadata. Aliases and
export names use the compiler's ASCII identifier subset, at most 63 bytes.
Import fields have single ASCII spaces; leading spaces before `import` are
allowed. No trailing fields or comments are allowed on import lines. Aliases
are unique within a module. Original `extern` lines are refused. All other
source lines are preserved byte for byte after the profile line, including
comments and local definitions. Dependencies' private names never enter this
source or another module's symbol namespace.

The compiler input is `object\n`, the profile line, generated extern lines,
and the original source with import lines removed. Explicit `export fn`
definitions provide public entries. Private functions remain module-local.
The compiler independently checks call types, array capabilities, and its
function-mode restrictions. This format excludes globals, text,
struct/layout/nominal interfaces, inline external interfaces, and fresh
external parameters. A module may use `read`, `write`, `exit` and the
function-mode host subset that needs no program image (files, identity,
clocks; OMEGESE "Native object output"); the device words stay refused. The
stack each host word pushes is in the object's stack record, so the stack
check below covers it (`seed/omc/gate-objhost.sh`). Internal functions may retain fresh semantics.
Only acyclic module and call graphs are accepted, including unused imports
and unreachable private calls. Program entry must be exported, zero-argument,
and return `int` or `void`. `main` has no special meaning in objects.

## Content identity and storage

All integer fields below are unsigned little-endian 64-bit values. No trailing
bytes are allowed. An artifact is:

| Offset | Value |
| --- | --- |
| 0 | Eight bytes `OMMOD001` |
| 8 | Compiler executable SHA-256, 64 ASCII bytes |
| 72 | Original source SHA-256, 64 ASCII bytes |
| 136 | Profile, 0 debug or 1 release |
| 144 | Target, 1 AArch64 Linux |
| 152 | Original source byte count S |
| 160 | Native object byte count O |
| 168 | Import count D |
| 176 | Original source, S bytes |
| 176 + S | Native object, O bytes |
| 176 + S + O | D artifact digests, 64 ASCII bytes each, in source import order |

The complete artifact's hash is its filename, `ARTIFACT_SHA256.mod`.
A lookup reference has filename `KEY.ref`, containing exactly the 64 ASCII
bytes of that artifact hash, without a newline. `KEY` is SHA-256 of the first
152 artifact bytes, which bind the domain/version, source, compiler, profile,
and target. The reference is only a locator: its target bytes are hashed,
their identity fields checked, and each dependency is required to match the
exact artifact digest recorded by its parent. Every level binds transitive
identities. A different profile or compiler never reuses a digest-only match.

Source and compiler files are read into owned snapshots and hashed there.
Only those compiler bytes are written to a private randomly named executable
snapshot for invocation. Compiler input and output use anonymous files. The
snapshot is unlinked after the child is reaped. Cache payload and reference
publication are independent atomic no-replace renames, with checked writes,
file sync and directory sync. A crash between them can leave an unreferenced
payload; rebuilding verifies and reuses those bytes before publishing the
reference. Concurrent publication may safely refuse instead of overwriting.
Interrupted temporary files are not live references or executable link outputs.

Link snapshots all inputs before writing the final image. It writes a unique
file in the selected output parent, syncs it, and renames without replacement.
An existing output remains untouched. A refused link creates no final output.
Directory traversal opens each component with AArch64 `O_DIRECTORY|O_NOFOLLOW`;
regular-file reads also use `O_NONBLOCK`, then require a regular-file stat, so
a FIFO cannot stall a read. There is no runtime module-count or object-size
cap. Runtime pools grow with actual input; allocation failure is a refusal.
Machine address space, Linux path/component lengths, the compiler's parameter
ABI, native branch reach, and its 8 MiB caller stack remain real boundaries.

Length arithmetic is checked, never wrapped. Sizes, offsets and growth requests
go through `sizeadd`, `sizemul` and `growto`; every arena reservation refuses
(code 20) when used plus request passes signed address space (byte arena) or
2^60-1 words (word table, the byte count must fit signed 64 bits). The SHA-256
message length field is 64 bits of bit count, so inputs of 2^61 bytes or more
are refused before any read. The growth slack is added only when it fits.

Content hashes provide integrity and exact identity, not publisher signatures
or a native-code sandbox. A caller must trust the pinned compiler and the
artifact identity it elects to run. A party who replaces both a reference and
its self-consistent contents chooses a new identity; a pinned root link still
refuses that substitution.

## Native object validation

The standalone object is `OMOBJ001`, as produced by the compiler:

| Offset | Value |
| --- | --- |
| 0 | Eight bytes `OMOBJ001` |
| 8, 16, 24 | Version 1, target 1, profile 0/1 |
| 32, 40 | Code start 176, code end/metadata start C |
| 48, 56, 64 | Function, call and explicit export counts |
| 72..175 | Zero |

Code `[176,C)` starts with an AArch64 `B` slot for each export in source
order, or an unused word when there are none. Local calls are resolved;
external calls contain `0x94000000` before linking. Metadata follows code:

* Each function: flags (0 private, 1 exported, 2 imported), object-relative
  address (0 for imported), result type, parameter count, maximum local stack
  bytes, name length; then name bytes, zero padding to the next 8-byte offset
  relative to the standalone object, and its parameter records.
* Each parameter: type, kind (0 scalar, 2 view, 3 edit/out), element count
  (0 for an unsized array), layout (0), fresh (0/1).
* Each call: object-relative instruction offset, source function index,
  destination function index, stack cost at this call including its save area.

Scalar type IDs are compiler IDs 1..13; 12 (`void`) is result-only. Parameters
must fit six native argument slots; an unsized view/edit consumes two. Imported
functions have zero address and stack. Names are unique within an object,
export entry instructions must point to the exact corresponding function,
real function addresses are aligned and increasing, and imports must match
both source aliases and complete dependency export signatures.

Every call record must name a unique aligned instruction within its source
function, with the expected local branch or unresolved external opcode. Every
native `BL` word must have a record. Indices, counts, lengths, zero padding,
reserved fields, type legality and exact end-of-object are independently
checked. Stack needs are settled from leaves upward:
`need(f) = max(local(f), cost(call) + need(callee) for each call)`.
Unsettled functions/modules are cycles; a need above 8 MiB is refused. The
linker copies native code and patches call words to the resolved export
address, checking signed 26-bit instruction displacement reach.

## Link outputs

Program output is a static AArch64 Linux ELF with separate RX code and RW
zero-filled context/stack segments. Its wrapper provides X7, a trap entry
that exits with 100 + trap code, and exactly 8 MiB of stack above the context
page. Normal exit uses the entry's `int` result, or zero for `void`.

Function output starts with one `B` slot per root export in source order,
followed by all native module code. It retains the Omega OM2 native ABI:
X7 is the caller's runtime context, `[X7+16]` is its trap entry, and the caller
supplies a suitably sized stack and preserves the ABI's pinned registers.
The independent test caller follows omega-bridge's native ABI, saves host
callee-saved integer/FP registers, and provides its own 8 MiB stack.

The last eight bytes are `OMLINK01`; the preceding u64 is descriptor size,
excluding those 16 footer bytes. The descriptor starts that many bytes before
the size field. It has an export count, followed in root source order by:
`code offset, required stack bytes, result type, parameter count, name length`,
then name bytes and the same 40-byte parameter records, without padding.
Offsets are relative to the first output byte. It is derived from the actual
validated objects, not a separately maintained interface file. The descriptor
is metadata after code, not an additional entry point.

## Refusals and qualification

The driver returns 10 for usage, 20/21 for address/allocation refusal, 22..24
for malformed reads/digests, 25..27 for path/read/write errors, 28 for source
imports, 30..32 for object/relocation validation, 33 for missing export, 34 for
store identity/format, 35 for import signature, 36 for cycles, 37 for stack,
38 for no-replace publication failure, 39 for compiler/child failure, and 40
for the requested entry. Stderr supplies that numeric code after the line
`ommod: refused (code below)`. Two refusals also write a named line first:

| What happened | Exit | Stderr name |
| --- | --- | --- |
| Bytes do not match the digest that names them: stored artifact bytes (a stored blob of the wrong length included), the source file passed to `build`, the compiler file against `COMPILER_SHA256`, or a dependency artifact against the digest its parent records. A one-byte change is this case. | 24 | `ommod: digest-mismatch` |
| The store open returns "no such file": no `KEY.ref` for that source digest under this compiler, profile and target, or the referenced artifact file is absent. | 34 | `ommod: digest-missing` |

Exit 24 is only a digest mismatch, so its name is part of every exit 24.
Exit 34 is also used for a malformed artifact or reference; the name
`digest-missing` is written only for "no such file". Compiler stderr
is retained. Tests require an explicit driver refusal rather than accepting
a crash/trap as correct rejection.

Tests cover separate native compilation, two roots reusing identical native
bytes, a single-unit execution oracle, function-mode scalar and array calls,
program and host trap paths, void and release entries, cache no-exec tracing,
identity/payload/metadata/relocation mutations, cycles, stack overflow,
symlink/FIFO handling, existing output preservation, orphan payload recovery,
a 71-module graph, exhaustive synthetic boundary cases for the length
arithmetic (exact Python integers as oracle, no large allocation), and
implementation mutants for relocation, stack and arithmetic checks.
