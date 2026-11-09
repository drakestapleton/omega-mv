@ng a64-enc
; arith ngL: the hash loop (omc 0x40027c..0x4002bc) rebuilt at the end of the file with its loop head on a
; 64-byte boundary (0x4004c0; the M variant uses the same head), constants 40000000, 31 and 1000003 hoisted
; into x4, x7, x10 (LICM), the test at the bottom (rotation; i = 0 < 40000000 on entry). rem stays UDIV+MSUB.
; arith has no array accesses, so there is no B rung. Exit state: x3 = x4 = 40000000 as in omc.
; @old 0x40027c 0xd28b4004 0xf2a04c44 0xeb04007f 0x540001c2 0xd28003e4 0x9b047c25 0x8b0300a1 0x9b037c65 0xd343fc66 0xca0600a4 0xd2884865 0xf2a001e5 0x9ac50888 0x9b059106 0x8b060042 0x91000463 0x17fffff0
; @at 0x40027c
b 140 | b @+560
; @at 0x400478
; @nop 0x4004ac
movzx 4 0x5a00 0 | mov x4, #0x5a00
movkx 4 0x262 1 | movk x4, #0x262, lsl #16
movzx 7 31 0 | mov x7, #0x1f
movzx 10 0x4243 0 | mov x10, #0x4243
movkx 10 0xf 1 | movk x10, #0xf, lsl #16
mulx 5 1 7 | mul x5, x1, x7
addx 1 5 3 | add x1, x5, x3
mulx 5 3 3 | mul x5, x3, x3
ubfmx 6 3 3 63 | lsr x6, x3, #3
eorx 8 5 6 | eor x8, x5, x6
udivx 9 8 10 | udiv x9, x8, x10
msubx 6 9 10 8 | msub x6, x9, x10, x8
addx 2 2 6 | add x2, x2, x6
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 3 4 | cmp x3, x4
bcond 3 -10 | b.cc @-40
b -139 | b @-556
