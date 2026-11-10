@ng a64-enc
; isort ngL: the leaf function isort (omc 0x400278..0x40033c, global a at 0x10800020) with 20000,
; 1000000 and the array base hoisted into x7, x8, x9 (LICM), both loops tested at the bottom (rotation;
; the inner loop keeps a CBZ guard), the eager `and moving gt k 0` lowered to branches (the flag is gone:
; p <= v leaves the loop directly; both operands are side-effect free, so eager and short-circuit agree).
; Every bounds check (trap 3, 0x40034c) and the while bound counter x4 (trap 4, 0x400354) are kept.
; @old 0x400278 0xd2800000 0xd289c401 0xeb01001f 0x540005c2 0xd289c402 0xeb02001f 0x540005e2 0xd2800403 0xf2a21003 0xf8607861 0xaa0003e2 0xd2800023 0xd2800004 0xf100005f 0x9a9f97e5 0x8a050066 0xb4000326 0xd2884808 0xf2a001e8 0xeb08009f 0x54000462 0x91000484 0xd1000446 0xd289c408 0xeb0800df 0x54000382 0xd2800409 0xf2a21009 0xf8667925 0xeb0100bf 0x54000129 0xd289c406 0xeb06005f 0x54000282 0xd2800408 0xf2a21008 0xf8227905 0xd1000442 0x14000002 0xd2800003 0x17ffffe5 0xd289c404 0xeb04005f 0x54000142 0xd2800405 0xf2a21005 0xf82278a1 0x91000400 0x17ffffd1 0xd65f03c0
; @at 0x400278
movzx 0 0 0 | mov x0, #0x0
movzx 7 0x4e20 0 | mov x7, #0x4e20
movzx 8 0x4240 0 | mov x8, #0x4240
movkx 8 0xf 1 | movk x8, #0xf, lsl #16
movzx 9 0x20 0 | mov x9, #0x20
movkx 9 0x1080 1 | movk x9, #0x1080, lsl #16
subsx 31 0 7 | cmp x0, x7
bcond 2 46 | b.cs @+184
ldrxr 1 9 0 1 | ldr x1, [x9, x0, lsl #3]
addxi 2 0 0 0 | add x2, x0, #0x0
movzx 4 0 0 | mov x4, #0x0
cbzx 2 15 | cbz x2, @+60
subsx 31 4 8 | cmp x4, x8
bcond 2 42 | b.cs @+168
addxi 4 4 1 0 | add x4, x4, #0x1
subxi 6 2 1 0 | sub x6, x2, #0x1
subsx 31 6 7 | cmp x6, x7
bcond 2 36 | b.cs @+144
ldrxr 5 9 6 1 | ldr x5, [x9, x6, lsl #3]
subsx 31 5 1 | cmp x5, x1
bcond 9 6 | b.ls @+24
subsx 31 2 7 | cmp x2, x7
bcond 2 31 | b.cs @+124
strxr 5 9 2 1 | str x5, [x9, x2, lsl #3]
addxi 2 6 0 0 | add x2, x6, #0x0
cbnzx 2 -13 | cbnz x2, @-52
subsx 31 2 7 | cmp x2, x7
bcond 2 26 | b.cs @+104
strxr 1 9 2 1 | str x1, [x9, x2, lsl #3]
addxi 0 0 1 0 | add x0, x0, #0x1
subsx 31 0 7 | cmp x0, x7
bcond 3 -25 | b.cc @-100
ret 30 | ret
; @nop 0x400340
