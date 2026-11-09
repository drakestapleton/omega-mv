@ng a64-enc
; branch ngC: ngL with both branches if-converted: the Collatz step computes x >> 1 and 3x + 1 and picks
; one with CSEL on TST x, #1; the max update is CMP + CSEL hi. Same loop shape, same bound counter.
; @old 0x40027c 0xd2884804 0xf2a001e4 0xeb04007f 0x54000382 0x91000464 0xd2800005 0xd2800006 0xf100049f 0x54000220 0xd2884808 0xf2a001e8 0xeb0800df 0x54000ee2 0x910004c6 0xd2800028 0x8a080089 0xf100013f 0x54000061 0xd341fc84 0x14000004 0xd2800068 0x9b087c89 0x91000524 0x910004a5 0x17ffffef 0x8b050021 0xeb0200bf 0x54000049 0xaa0503e2 0x91000463 0x17ffffe2
; @at 0x40027c
movzx 7 0x4240 0 | mov x7, #0x4240
movkx 7 0xf 1 | movk x7, #0xf, lsl #16
addxi 4 3 1 0 | add x4, x3, #0x1
movzx 5 0 0 | mov x5, #0x0
movzx 6 0 0 | mov x6, #0x0
subsxi 31 4 1 0 | cmp x4, #0x1
bcond 0 12 | b.eq @+48
subsx 31 6 7 | cmp x6, x7
bcond 2 123 | b.cs @+492
addxi 6 6 1 0 | add x6, x6, #0x1
ubfmx 9 4 1 63 | lsr x9, x4, #1
addx 10 4 4 0 1 | add x10, x4, x4, lsl #1
addxi 10 10 1 0 | add x10, x10, #0x1
andsxi 31 4 0x1 | tst x4, #0x1
cselx 4 10 9 1 | csel x4, x10, x9, ne
addxi 5 5 1 0 | add x5, x5, #0x1
subsxi 31 4 1 0 | cmp x4, #0x1
bcond 1 -10 | b.ne @-40
addx 1 1 5 | add x1, x1, x5
subsx 31 5 2 | cmp x5, x2
cselx 2 5 2 8 | csel x2, x5, x2, hi
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 3 7 | cmp x3, x7
bcond 3 -21 | b.cc @-84
b 7 | b @+28
; @nop 0x4002f8
