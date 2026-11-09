# Omega `.om`: what is done, what completion still needs

Status: 2026-10-23. This file is the audit trail for the objective "complete and evolve the `.om`
language". It separates work that is implemented and gated from work that is blocked on a decision or
on an external store. It is not a claim that the language is complete. Its counts and pins are those of
2026-10-23 and are not refreshed here; OM-2 (section 9.13 of OMEGESE.md) has landed since, and the 1.0
gaps and acceptance gates are planned in `docs/ROADMAP-1.0.md`.

Evidence lives in `seed/README.md` (rungs), `seed/omc/gate*.sh`, `seed/host/check.sh`, and
`evidence/SEED-0/`.

## 1. Implemented and gated

| Area | What exists | Gate / evidence |
|---|---|---|
| Core language | functions, parameters (scalar, view/edit arrays, structs), if/else, while/bound, for, break, continue, ret, trap, note, prefix values, grouping | gates 6-11, gate-ir; corpus |
| Types | bool, u8..u64, i8..i64, f32/f64, arrays with explicit length, structs of 8-byte cells | gate8, gate9, gate10, gate6 |
| Types rules | no implicit conversion; typed literals; range checks; signed traps; unsigned wrap; shifts; division/remainder; float IEEE semantics | gate14 (Wolfram-derived expectations) |
| Memory model | stack arrays (new), globals (pools), structs, view/edit, no free, no pointers, checked indices | gates 6-12, host |
| Constants | integer and float literals; expressions, calls, array lengths, struct field lengths, trap codes, loop bounds, for counts; integer folding in IR | gate16, gate-ir |
| Layout | sizeof/offsetof over 8-byte cells; scalar sizes | gate10 |
| Host words | file/path/metadata, links, permissions/ownership, access, identity, process groups, time, sleep, sockets, poll, fork/exec/wait, pipes, dup, argv/env, random, chdir, fchdir, cwd, truncate/ftrunc, chmod/chown, stat/lstat, memfd, fdatasync, pread/pwrite, getsid/syncfs/shutdown | seed/host/check.sh |
| Diagnostics | 29 emitted compiler codes (1..25, 27..30; 26 unused) in one registry, `seed/omc/error-codes.reg`, each with a minimal case refused at its exact line, and a drift check against omc.om, irwasm.om and OMEGESE §9.14/§11.1 | gate15 (`codereg.om`) |
| Robustness | 600 deterministic fuzz programs; capacity boundaries; 300-program differential fuzz against the pinned compiler; 30 randomized two-function IR units; keyword generator parity | gate12, gate13, gate17, gate18, gate-ir |
| IR mode | OSC IR v1 scalar subset: up to 32 functions, calls to earlier functions, integer constants folded, break; arrays/structs/floats out of scope; `TYPE value` casts convert an operand of any scalar type | gate-ir (10/10 dev, 9 call units, 3 break units, 1 shift unit, 4 bool units, 24 cast units, 2 contract-name units, 30 fuzz units; 29 refusals, including the error-30 contract lines of #791, and 38 validation refusals) |

Compiler: 7,208 lines, 251 functions, sha256
`ef19aa993d210ad20070ef99bce1e2ef02921d9541d7a443f973072c4d6fa6a3` (119,643 bytes).

Benchmark parity: 103 authored `.om` sources and 53 build-plan targets compile to identical bytes
and refusals as the pinned compiler `e5d60db8…` (rung R15; rechecked after every keyword).

## 2. Open compiler work

IR mode is complete for the **scalar** OSC-1 subset: scalar values, up to 32 functions, calls to
earlier functions with full 63-byte names, integer constants (values, trap codes, loop bounds, for
counts), and break. `gate-ir` pins this against the C oracle and checker2. No self-contained compiler
feature remains for that subset.

**Spec-blocked / model-divergent target extensions.**

1. **IR arrays.** OSC-1 arrays carry explicit `free`; the `.om` language has no `free` (decision 24)
   and returns arrays automatically. The C oracle therefore cannot validate an IR lowering of `.om`
   arrays, and IR mode refuses `new`/`get`/`put`. Needs an ownership model that both sides share.

OSC-1 also explicitly excludes structs and strings, and its scalar tags are integer-only; `omegese`
cannot emit them, so there is no reference unit to verify against.

1. **IR structs.** Version-2 struct records exist, but allocation, field ops and identity need the
   OSC-1 struct lowering spec.
3. **IR floats.** Float constants cannot be folded until the IR type system carries f32/f64.

**Decision-bound language/ecosystem work.**

4. **Generic byte/string utilities.** OM-1 array parameters carry an exact length. OM-2 units take
   arrays of any length through unsized `view T *` / `edit T *` parameters (OMEGESE.md §9.13); the
   standard library itself is still open.
5. **`sync` naming.** The benchmark corpus uses `sync` as an identifier four times; any new keyword
   must pass the corpus collision audit (rung R13).

## 3. Blocked on a decision or an external store

| FR / decision | Gap | Why it is blocked |
|---|---|---|
| FR-1 file I/O | complete for the exposed set (open/read/write/seek/stat/link/chmod/chown/truncate/memfd) | no blocker for this subset |
| FR-2 packed structs | OM-1 structs are 8-byte cells. OM-2 `layout NAME SIZE` / `field F T [N] at OFF little\|big` gives packed integer fields with explicit byte order (OMEGESE.md §9.13; refusal error 29 gated by `gate15.sh` `e29_layout_past`) | no packed layout in OM-1 units; the OM-2 run cases (`seed/omc/om2/s3/s3.cases`) are not in OMEGA-SEED |
| FR-3 imports by digest | no `import`; units concatenate | requires the OSC content-addressed unit store (external) |
| FR-4 floats | implemented end to end for AArch64 (types, literals, arithmetic, arrays, pools, structs) | IR floats are spec-blocked: OSC-1 scalar tags are integer-only |
| FR-5 mmap/ioctl | implemented for AArch64 program mode as handle-checked words `devctl devcall uvmctl mapnew mapdrop mapread mapwrite mapaddr mapget mapset maphold mapbind` (ids 166..177, `seed/omc/genkw.awk`; contracts in [`seed/host/MAPPING.md`](../../seed/host/MAPPING.md), tests `seed/host/tests/{mapio,devcall,memcheck,reserve}.om` run by `seed/host/gate.om`) | access through a raw integer address stays refused: `mapaddr` exports a ulong but access requires the live owned handle; no GPU launcher or model execution (MAPPING.md) |
| FR-6 threads/atomics | absent | decision 37 (disjoint threads) has no chosen design |
| FR-7 shared objects/C ABI | OM-2 `export fn` gives multi-entry function-mode units (OMEGESE.md §9.13); foreign callers bind them through the omega-bridge native ABI (`om/units.sh`; omega-bridge `docs/NATIVE-ABI.md`: v1 for OM-1 units, v2 for OM-2 units) | no ELF shared objects, symbol tables or relocations; units link only as generated C bindings |
| FR-8 kernel words | absent | needs a target kernel interface, not a compiler change |
| FR-9 x86-64 | DRAFT, merged as #923 from historical backend `7eca2ac3f` on canonical base `6999fa9e6`; see [design and unsupported paths](../X86-LINUX.md) | full existing fixture differential last ran EMULATED (QEMU) at source `62d1d0d6` (`seed/qualification/x86-linux/20261030-main-62d1d0d6.json`): 15182 PASS, 0 FAIL, 2 NOT_RUN (QEMU invalid-fd ioctl artifacts), 222 EXCLUDED, aggregate verdict FAIL because NOT_RUN is not PASS; the same run's objdump invalid-encoding and valid-wrong-encoding controls PASS; native x86 NOT_RUN; default AArch64 byte preservation is not separately recorded in that receipt; no completion or qualification claim |
| decision 24 | no heap, no free | Drake's rule; any allocation model would reverse it |
| decision 37 | no shared-state threads | design decision pending |

## 4. Next concrete step

No self-contained compiler feature remains for the supported scalar subset. Next work requires a
decision (FR-3/6/8, FR-2/7 for OM-1 units only, decisions 24/37) or a shared target-extension model (IR arrays,
structs, floats); FR-9 is merged as a draft (#923) described above, not a completed second target.
