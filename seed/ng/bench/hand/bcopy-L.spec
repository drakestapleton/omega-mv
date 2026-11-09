@ng a64-enc
; bcopy ngL: the copy loop (omc 0x40011c..0x400164) with loop-invariant constants and addresses hoisted
; (LICM) and the test moved to the bottom (rotation; i = 0 < 65536 on entry). Both bounds checks kept,
; against the hoisted limit. Registers x2..x11 are dead after the loop (x0 r, x1 k live).
; @old 0x40011c 0xd2800002 0xd2a00023 0xeb03005f 0x54000202 0xd29fffe3 0xcb020064 0xd2a00025 0xeb05005f 0x54000562 0xd2a21006 0x386268c8 0xca010109 0xd2a0002a 0xeb0a009f 0x540004a2 0xd2a2102b 0x38246969 0x91000442 0x17ffffef
; @at 0x40011c
movzx 2 0 0 | mov x2, #0x0
movzx 3 1 1 | mov x3, #0x10000
movzx 5 0xffff 0 | mov x5, #0xffff
movzx 6 0x1080 1 | mov x6, #0x10800000
movzx 11 0x1081 1 | mov x11, #0x10810000
subx 4 5 2 | sub x4, x5, x2
subsx 31 2 3 | cmp x2, x3
bcond 2 44 | b.cs @+176
ldrbr 8 6 2 0 | ldrb w8, [x6, x2]
eorx 9 8 1 | eor x9, x8, x1
subsx 31 4 3 | cmp x4, x3
bcond 2 40 | b.cs @+160
strbr 9 11 4 0 | strb w9, [x11, x4]
addxi 2 2 1 0 | add x2, x2, #0x1
subsx 31 2 3 | cmp x2, x3
bcond 3 -10 | b.cc @-40
; @nop 0x400168
