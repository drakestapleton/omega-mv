@ng a64-enc
; sieve ngL: the leaf pass (omc 0x4001fc..0x400338, fl at 0x10800020, 2000001 bytes) with 2000001,
; 2000000, 1000000, the base, 1999999 and the stored 1 hoisted into x10..x15 (LICM), every loop tested at
; the bottom (rotation; guards kept where entry is not already known to pass the test), the zero store
; from WZR. Bounds checks (trap 3, 0x400348) and both while bound counters x1, x3 (trap 4, 0x400350) kept.
; @old 0x4001fc 0xd2800000 0xd2909021 0xf2a003c1 0xeb01001f 0x54000162 0xd2800001 0xd2909022 0xf2a003c2 0xeb02001f 0x54000942 0xd2800403 0xf2a21003 0x38206861 0x91000400 0x17fffff3 0xd2800040 0xd2800001 0x9b007c02 0xd2909003 0xf2a003c3 0xeb03005f 0x540004c8 0xd2884804 0xf2a001e4 0xeb04003f 0x54000782 0x91000421 0xd2909022 0xf2a003c2 0xeb02001f 0x540006a2 0xd2800403 0xf2a21003 0x38606864 0xf100009f 0x540002c1 0x9b007c02 0xd2800003 0xd2909004 0xf2a003c4 0xeb04005f 0x54000208 0xd2884805 0xf2a001e5 0xeb05007f 0x54000502 0x91000463 0xd2800024 0xd2909025 0xf2a003c5 0xeb05005f 0x54000402 0xd2800406 0xf2a21006 0x382268c4 0x8b000042 0x17ffffee 0x91000400 0x17ffffd7 0xd2800001 0xd2800002 0xd2908fe3 0xf2a003c3 0xeb03005f 0x540001c2 0x91000843 0xd2909024 0xf2a003c4 0xeb04007f 0x540001c2 0xd2800405 0xf2a21005 0x386368a6 0xf10000df 0x54000041 0x91000421 0x91000442 0x17fffff0 0xaa0103e0 0xd65f03c0
; @at 0x4001fc
movzx 10 0x8481 0 | mov x10, #0x8481
movkx 10 0x1e 1 | movk x10, #0x1e, lsl #16
movzx 11 0x8480 0 | mov x11, #0x8480
movkx 11 0x1e 1 | movk x11, #0x1e, lsl #16
movzx 12 0x4240 0 | mov x12, #0x4240
movkx 12 0xf 1 | movk x12, #0xf, lsl #16
movzx 13 0x20 0 | mov x13, #0x20
movkx 13 0x1080 1 | movk x13, #0x1080, lsl #16
movzx 14 0x847f 0 | mov x14, #0x847f
movkx 14 0x1e 1 | movk x14, #0x1e, lsl #16
movzx 15 1 0 | mov x15, #0x1
movzx 0 0 0 | mov x0, #0x0
subsx 31 0 10 | cmp x0, x10
bcond 2 70 | b.cs @+280
strbr 31 13 0 0 | strb wzr, [x13, x0]
addxi 0 0 1 0 | add x0, x0, #0x1
subsx 31 0 10 | cmp x0, x10
bcond 3 -5 | b.cc @-20
movzx 0 2 0 | mov x0, #0x2
movzx 1 0 0 | mov x1, #0x0
mulx 2 0 0 | mul x2, x0, x0
subsx 31 2 11 | cmp x2, x11
bcond 8 25 | b.hi @+100
subsx 31 1 12 | cmp x1, x12
bcond 2 61 | b.cs @+244
addxi 1 1 1 0 | add x1, x1, #0x1
subsx 31 0 10 | cmp x0, x10
bcond 2 56 | b.cs @+224
ldrbr 4 13 0 0 | ldrb w4, [x13, x0]
cbnzw 4 14 | cbnz w4, @+56
mulx 2 0 0 | mul x2, x0, x0
movzx 3 0 0 | mov x3, #0x0
subsx 31 2 11 | cmp x2, x11
bcond 8 10 | b.hi @+40
subsx 31 3 12 | cmp x3, x12
bcond 2 50 | b.cs @+200
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 2 10 | cmp x2, x10
bcond 2 45 | b.cs @+180
strbr 15 13 2 0 | strb w15, [x13, x2]
addx 2 2 0 | add x2, x2, x0
subsx 31 2 11 | cmp x2, x11
bcond 9 -8 | b.ls @-32
addxi 0 0 1 0 | add x0, x0, #0x1
mulx 2 0 0 | mul x2, x0, x0
subsx 31 2 11 | cmp x2, x11
bcond 9 -23 | b.ls @-92
movzx 1 0 0 | mov x1, #0x0
movzx 2 0 0 | mov x2, #0x0
addxi 3 2 2 0 | add x3, x2, #0x2
subsx 31 3 10 | cmp x3, x10
bcond 2 32 | b.cs @+128
ldrbr 6 13 3 0 | ldrb w6, [x13, x3]
cbnzw 6 2 | cbnz w6, @+8
addxi 1 1 1 0 | add x1, x1, #0x1
addxi 2 2 1 0 | add x2, x2, #0x1
subsx 31 2 14 | cmp x2, x14
bcond 3 -8 | b.cc @-32
addxi 0 1 0 0 | add x0, x1, #0x0
ret 30 | ret
; @nop 0x40033c
