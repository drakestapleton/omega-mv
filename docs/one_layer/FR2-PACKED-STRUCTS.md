# FR-2 packed structs

A packed struct is the same struct as section 9.7 of OMEGESE. `packed` is a layout attribute on that struct. It is not a new type, not a second field table, and not the OM-2 `layout` block. `new`, `get`, `put`, `view`, `edit`, `sizeof` and `offsetof` are the same words. What changes is the image: where each field sits, and which load or store reaches it.

The attribute is the word `packed` immediately after `struct`, before the name. It is recognized by that spelling in that one place. It is not a keyword. A variable may still be named `packed` (the compiler's own source does). An ordinary struct cannot be named `packed`, because that spelling in this position is the attribute. `struct packed Name ... end` is a packed struct named `Name`. `struct packed packed a uchar end` is a packed struct whose name is `packed`.

```
struct packed [little|big] Name field Type [Count | bits N] ... end
```

`little` and `big` are optional and come after `packed`, before the name. The default is `little`. The same spellings are OM-2 keywords in other positions; here they are the endian attribute, in both modes.

The record a later C ABI reads is the struct the compiler already keeps, plus six fields. Do not invent a second layout.

| Record | Meaning |
|---|---|
| `st_pack` | 0: 8-byte cells (9.7). 1: byte-packed image. 2: byte-packed image that contains a bitfield |
| `st_be` | 0 little, 1 big |
| `st_bytes` | image size in bytes. `sizeof` of a packed struct |
| `st_cells` | stack slots of 8 bytes. The slot is then rounded up to 16, as an ordinary struct slot is. This is not `sizeof` |
| `sf_boff` | byte offset of the field. `offsetof` |
| `sf_bits` | bit width. 0 means the field occupies its whole type |
| `sf_bpos` | bit index of a bitfield inside the byte at `sf_boff` (0..7) |
| `sf_type`, `sf_len`, `sf_name` | unchanged. `sf_len` 0 is a scalar. A bitfield is a scalar |

## Byte packing

A field with no `bits` occupies `Count * width` bytes, or `width` bytes when `Count` is omitted. `width` is the scalar size: bool 1, uchar/byte 1, ushort/short 2, uint/int/f32 4, ulong/long/f64 8. `Count` is 1..64, the same bound as an ordinary array field.

The first field starts at byte 0. The next field starts at the next byte after this one. If the bit cursor is not on a byte boundary, it advances to the next byte first and the leftover bits are padding. There is no padding between byte fields that follow a byte boundary, and no trailing padding in `sizeof`. The alignment of the struct is 1. A field of a multi-byte type may therefore sit at an odd address.

The image is at most 512 bytes, the same budget as 64 ordinary cells. One more byte is error 14. More than 16 fields is error 14, as for an ordinary struct. An empty packed struct is error 16.

`struct packed P a uchar b ushort c uint end` is 7 bytes. `a` is at 0, `b` at 1, `c` at 3.

An ordinary struct is unchanged: every field is still one or more 8-byte cells, and `sizeof` is 8 times the cell count. `struct P a uchar b ushort c uint end` is 24 bytes.

## Bit packing

`field Type bits N` is allowed only on a packed struct. `N` is 1..width of `Type` in bits. `Type` is an integer from `uchar` through `long`. bool, f32, f64 and a non-integer are error 7. `N` of 0 or past the width is error 8. A missing number is error 4. A word that is not a number is error 16. `bits` together with an array count is not the form; the count and the bit width are two different tails of the field.

The image is a bit string. The cursor starts at bit 0.

- Little: bit 0 of the image is the least significant bit of byte 0. The least significant bit of the value is stored at the first allocated bit.
- Big: bit 0 of the image is the most significant bit of byte 0. The most significant bit of the value is stored at the first allocated bit.

A bitfield is placed at the cursor when it fits in the 8-byte window that starts at the current byte (64 minus the bit index in that byte). When it does not fit, the cursor advances to the next byte and the leftover bits of the current byte are padding. A 64-bit field therefore always starts on a byte. The field then occupies the next `N` bits. `sizeof` rounds the final cursor up to a byte.

This window is what makes one 8-byte register enough to hold the field. It is a rule of this language, not a copy of a C compiler's bitfield allocator.

`struct packed F a uint bits 4 b uint bits 4 end` is 1 byte. Both fields have `offsetof` 0. `a` is bits 0..3 and `b` is bits 4..7 of that byte. The value 1 in `a` and 2 in `b` is the byte 0x21.

`struct packed big F a uint bits 4 b uint bits 4 end` is the same size and the same offsets. The value 1 in `a` and 2 in `b` is the byte 0x12, because `a` takes the high nibble.

`struct packed H a uint bits 1 b ulong bits 64 end` is 9 bytes. `a` is at byte 0. `b` does not fit in the remaining 63 bits, so `b` is at byte 1 and `sizeof` is 9.

An 8-bit field on a byte boundary is the same byte under either endian. A 16-bit field on a byte boundary is the same image as a `ushort` of that endian. The two forms are defined to agree so a reader does not keep two answers.

`bits` on an ordinary struct is not this attribute. The word is then a field name, and the following number is not a type (error 16).

## Endianness

The endian attribute is a property of the whole struct.

Little is the byte order of Linux on this machine, both the Grace CPU in GB10 and x86-64. A multi-byte field is stored least significant byte first. A load reassembles the numeric value the program sees, sign-extending a signed field and leaving an f32 or f64 as its IEEE bits.

Big stores the most significant byte first, then reverses on the way back to the register, so `get` returns the same number that `new` stored. A big struct is not the memory image of a C struct compiled for this Linux.

## Unaligned access

A packed field is addressed as `base + byte_offset`, with the width of the field, and the offset is not scaled by that width. The base of a stack slot is 16-byte aligned. The field need not be.

AArch64, GB10 (Grace, Armv8. The manual on this machine is Arm ARM DDI 0487 M.d). The lowering is the unscaled register-offset form, the same `LDR`/`STR` family OM-2 `layout` already emits (`ldun`/`stun` in `seed/omc/omc.om`): byte, halfword, word or 64-bit, option LSL with the scale bit clear. It is not a load-exclusive, a store-exclusive, an acquire/release, an atomic, or a pair (`LDP`/`STP`).

DDI 0487 M.d, B2.8.2.1.1 (page B2-312): for a single-register load or store of that kind, if `SCTLR_ELx.A` is 0, an address that is not aligned to the element size performs the unaligned access. Linux userspace runs with that bit clear. If the bytes of the access do not all lie in one 16-byte-aligned 16-byte block, the access is not single-copy atomic, even where FEAT_LSE2 makes a contained access atomic. A packed store is therefore a plain store. Decision 37 stands: this is not a shared-memory operation, and it is not an atomic.

x86-64. The lowering is the ordinary general-purpose `MOV` already used for an external layout (`xlayout` in `omc.om`): the address is `base + byte_offset`, then an 8, 16, 32 or 64-bit move. It is not `MOVAPS` and it is not a locked move. Linux leaves the alignment-check flag clear, so that move completes at any byte address. A split across a cache line is a plain split, not a locked split lock.

Both targets reverse bytes for `big` before the store and after the load (`ly_rev`). A bool is stored as one byte, 0 or 1. An f32 uses a 32-bit move and an f64 a 64-bit move.

## Stack, calls, and what this does not allocate

Decision 24: there is no heap and no `free`. `new` of a packed struct is a stack slot, returned when the function returns, the same as an ordinary struct. The slot is the image rounded up to 16 bytes. `sizeof` does not include that tail. When the struct has a bitfield, the slot is cleared first so padding bits are zero; a byte field is stored at its full width and does not need the clear.

A parameter is still one pointer (`view` or `edit`). Omega does not pass the image in registers. A function still does not return a struct.

IR mode still refuses `struct`, packed or not, with error 9. That refusal stays until the IR aggregate work has a head to rebase onto. The attribute is already on the native struct, so the IR lowering is a consumer of `st_pack` and the field record, not a second type.

## FR-7 hook

FR-7 (shared objects and the C ABI) is a different piece of work. When it classifies a struct for a C call it reads the record above and does not guess.

- Size is `st_bytes`. Alignment is 1. Field offsets, bit widths and bit positions are `sf_boff`, `sf_bits` and `sf_bpos`.
- Omega's own call is still the pointer. FR-7 must not replace that with an AAPCS64 or SysV by-value classification for calls that stay inside Omega.
- A `st_be` of 1 is not a C aggregate on little-endian SysV or AAPCS64. The only honest C passing form for it is an opaque image of `st_bytes` bytes. A little packed struct can be the image of a C struct with alignment 1, if and only if every field is a byte field (`sf_bits` 0) and the C side was packed to 1 with the same order and the same widths. Bitfields are this document's rule, not GCC's, and FR-7 must not pretend they match.
- A packed store is not atomic (B2.8.2.1.1). FR-7 does not publish one as a C `_Atomic` or as a shared object field under decision 37.
