# IR aggregates and floats

Status: floats, fixed-size arrays and struct values are emitted. A struct-typed field is accepted in IR and refused by the native compiler (error 16). Packed alignment 1 is not this slice. The native backend still stores struct fields in 8-byte cells.

This is the shared model for Omega's IR. The wire is OSC (`spec/one-layer-format.md`). An integer-only unit stays version 1 and keeps the bytes it had. A unit that uses f32 or f64 is version 7: tags 13 and 14 on ordinary value registers, `nstructs` 0, `nregions` 0, then the same function records. Version 7 already admits those tags. Putting them in a version 1 unit is a range error, so the producer does not do it.

The native AArch64 path already runs floats, arrays and 8-byte-cell structs. This note is about the IR those paths and the wasm backend share. It does not copy a C ABI.

## 1. Type model

Scalar tags, one byte, same numbers as the wire:

| tag | meaning | width |
|---|---|---|
| 0 | void | none |
| 1 | bool | 1 bit, stored as 0 or 1 |
| 2..5 | u8 u16 u32 u64 | 8, 16, 32, 64 |
| 6..9 | i8 i16 i32 i64 | 8, 16, 32, 64 |
| 13 | f32 | 32, IEEE binary32, high 32 bits of a constant are 0 |
| 14 | f64 | 64, IEEE binary64 |

Tags 10, 11 and 12 stay what the wire already says (reference, bytes, cells). This slice does not emit them. An array is not a reference with `free`. The language has no `free` (decision 24). An array is a region (section 4). A struct is not a reference either (section 5).

No tag converts to another tag because it was nearby. `f32` and `f64` are ordinary words, and so are `uint`, `ulong` and the rest. Writing the word is the conversion. A bare integer where a float is expected is error 7. A bare float literal where an integer is expected is error 7. A float literal with no type expected is error 11. `bool` and a number, integer or float, convert only by comparison (error 9), the same rule the integer IR already uses.

`fma`, `fsqrt`, `fabs`, `fmin`, `fmax` and `bitcast` stay out of this IR. IR reports error 3 for the word, including a well-typed `fma f64 1.0 f64 2.0 f64 3.0` and an ill-typed one. The native path types the operands first: a bare `fma 1.0 2.0 3.0` or `fsqrt 1.0` is error 11, a mixed `fma f64 1.0 uint 1 f64 2.0` is error 7, and a well-typed `fma` compiles. The BIN and UN opcodes have no fused subcode and no reinterpret subcode. Emitting an unfused multiply and add would round twice and call it `fma`. A later slice can add one opcode for each, with the native rounding, rather than a stand-in.

## 2. Float values

Binary32 and binary64, roundTiesToEven. The IR carries no rounding-mode field. A program cannot change the mode under a running function. That is the mode the AArch64 path already uses (FPCR default) and the mode wasm uses.

A decimal literal is converted once, by the same converter the native path uses (`fbits`). The bits are a CONST. An unsuffixed literal takes the float type of its context. A `f32` or `f64` suffix must match that type (error 7). A literal that rounds to infinity is error 8, as on the native path. Signed zero keeps its sign bit.

Operations on a float, and what they do:

| word | IR | result |
|---|---|---|
| add sub mul div | BIN 1..4 | one IEEE operation, roundTiesToEven |
| neg | UN 1 | sign flip, no rounding |
| eq ne lt le gt ge | CMP 1..6 | bool 0 or 1 |
| `f32` / `f64` of an integer | CAST | roundTiesToEven (SCVTF / UCVTF) |
| `f32` of `f64`, `f64` of `f32` | CAST | demote or promote, one rounding |
| integer type of a float | CAST | truncate toward zero, saturate, NaN becomes 0 (FCVTZS / FCVTZU) |

div by zero yields an infinity of the right sign. 0/0 yields a NaN. No float operation traps. Overflow yields an infinity. Underflow yields a subnormal or a signed zero, per IEEE.

Comparisons use the IEEE predicates, not a total order. NaN compares false for eq, lt, le, gt and ge. `ne` of a NaN is true. -0 and +0 compare equal. The sign of zero is still in the bits of a CONST, so a backend that looks at the bits can tell them apart. `bitcast` is the word that would expose those bits to the program. It is refused in this slice (error 3), so a program cannot read the payload yet. The comparisons above are still tested.

`rem`, `and`, `or`, `xor`, `shl`, `shr` and `not` on a float are error 7. A float is not a `for` count and not an index (error 7).

A float constant (`const N f64 1.0`) folds to the same CONST as the literal. An integer literal under a float constant is error 16, as in a native constant. A float constant used as a trap code, a `while` bound or a length is error 16 on both paths. A float constant used as a `for` count is error 7 on both paths, the same code as a float literal in that place.

## 3. Layout and alignment

Alignment is the scalar's own size, and that size is a power of two:

| type | size | alignment |
|---|---|---|
| bool, u8, i8 | 1 | 1 |
| u16, i16 | 2 | 2 |
| u32, i32, f32 | 4 | 4 |
| u64, i64, f64 | 8 | 8 |

This is the Arm load that actually moves the value: one access, naturally aligned. It is not a C ABI. C leaves several of these up to the platform, and a packed attribute then fights the platform. Here the default is the machine width. A later packed form is an explicit layout whose alignment is 1, written as its own syntax. It is not the silent default, and it does not change the sizes above.

The native backend still stores every struct field in an 8-byte cell, including an f32 in the low half. That cell rule stays until the packed-struct work lands. The rule in this note is the one that work implements. `sizeof` and `offsetof` on the native path keep meaning 8-byte cells until that landing, so existing programs do not move under them.

An array's stride is the element size. There is no padding between elements. An f32 array is 4 bytes per element. An f64 array is 8.

A struct's fields are in source order. Each field starts at the next offset that is a multiple of its alignment. The struct's alignment is the widest field alignment. The struct's size rounds up to a multiple of that alignment, so an array of the struct keeps every element aligned. There is no extra tail past that round-up, no bitfield, and no flexible last member.

Example, under this rule, not under today's 8-byte cells: `struct S a bool b f64 end` is `a` at 0, seven padding bytes, `b` at 8, size 16, alignment 8. `struct T a f32 b f32 end` is size 8, alignment 4. `struct U a u8 b u8 end` is size 2, alignment 1.

## 4. Arrays

An array is a version 7 region, class 1 (function-local). The region id is the name. The element count is fixed and is part of the type. The producer emits RINIT of the initial value at the `new`, then RLOAD and RSTORE for `get` and `put`. Opcode 9 LOAD and opcode 10 STORE stay the old reference ops. This slice does not emit them, because those ops belong to the `free` model. `new` is only in the function's outermost block (error 9 inside `if`, the same place the native path refuses it). `free` stays error 9. A module-global array is still refused with the other `global` forms (error 9).

The index is an integer, not a byte offset and not a pointer. A float index is error 7. A bool index is error 7. A constant index outside `0 .. count-1` is error 21, the same compile error the native path uses. A register index is compared as unsigned with the count before any address is formed (a negative signed index is a huge unsigned value and fails the compare). The failure is trap 3, the same trap the native path uses (`B.HS` after the compare). The address is `base + index * stride` only after that compare. There is no wrapping index.

The count is not a hidden maximum. The native limits stay what they are: a local array up to 4 MiB in total, a global pool up to 1 GiB in total, a single dimension up to 16777216 elements. Those are the existing capacity checks (error 23), not a new cap.

## 5. By value and by region

A scalar, including a float, is a value. The bits move. Nothing aliases them.

A struct is a value. Its identity is its fields, not an address. Passing a struct copies the fields. A small struct lands in registers. A struct that does not fit is copied through a local region that the callee owns. The IR still says "copy the fields". It does not say "pass a pointer and hope the ABI agrees". Sharing one struct on purpose is an array of one struct, which is a region, and the sharing is written down.

An array is a region id. Passing it does not copy the elements. `own` moves the region. `edit` and `view` borrow it for the call. The borrow ends when the call returns. There is no `free` and no pointer for the program to keep. The region dies with its owner. A backend may reuse the physical storage on the next call. A correct program cannot see the previous values, because the next entry RINITs before any load.

Calls stay "earlier functions only", so a region is not re-entered.

## 6. How the existing backends lower it

Floats, this slice:

- The producer writes version 7 when any register or result uses tag 13 or 14, and version 1 otherwise.
- CONST holds the IEEE bits. f32 uses the low 32 and zeroes the high 32.
- BIN, UN, CMP and CAST are the opcodes the wire already has. The type on the register tells the backend which form.
- `seed/wasm/irwasm.om` is the backend that runs them. Integer-to-float casts convert the i64 register that already holds the extended integer (`f32.convert_i64_*` / `f64.convert_i64_*`), because that register is the value, not a raw i32 slot. f32 to f64 is `f64.promote_f32`. f64 to f32 is `f32.demote_f64`. Float-to-int stays the saturating lowering irwasm already had.
- The AArch64 path is unchanged. It never reads this IR. The gate runs the same expression both ways and compares the bool.

Arrays: the producer writes the region table and opcodes 30, 31 and 33. irwasm lowers RLOAD, RSTORE and RINIT, and it checks the index before the address. A constant index outside the array is error 21 on both paths. A register index that fails the compare traps: irwasm does not return, and the native path exits 103.

Structs: the producer writes the version 7 struct table in front of the regions. Each scalar field is its own register. `new` moves the initializer into that register, and a later `put` moves into the same register, so the field does not alias a constant. An array field is its own region. A struct-typed field is tag 12 and its length is the inner struct's index plus 1. irwasm reads that table and does not execute a field opcode; the field values are the ordinary registers. The native compiler still refuses a struct-typed field with error 16. Two `new`s are two values: writing one leaves the other as it was. `t = s` is error 7 on both paths. The wire offsets follow section 3. The native `sizeof` and `offsetof` stay on 8-byte cells.

## 7. What the producer still refuses

| program | error |
|---|---|
| global, text, free, new inside if | 9 on both paths |
| a struct-typed field | accepted in IR; native error 16 |
| t = s, a struct or array name used as a scalar, put on a scalar | 7 on both paths |
| fma, fsqrt, fabs, fmin, fmax, bitcast, continue | 3 in IR. Native types first: bare float literals are 11, a mixed operand is 7, and a well-typed fma compiles |
| float mixed with a typed integer, rem, shifts, bitwise, not, float for-count, bad suffix | 7 |
| bool and float | 9 |
| a float literal with no expected type, `x = 1.0` | 11 |
| integer literal as a float constant | 16 |
