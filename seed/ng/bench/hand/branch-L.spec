@ng a64-enc
; branch ngL: the Collatz loops (omc 0x40027c..0x4002f4) with the constant 1000000 hoisted into x7 (outer
; limit and the while iteration bound, both 1000000), both loops tested at the bottom (rotation; the inner
; loop keeps a guard because n = 0 starts at x = 1), immediates folded into TST / CMP #imm, x*3+1 as
; ADD x, x, x, LSL #1 then ADD #1. The parity test and the max update stay branches. The while bound
; counter x6 and its trap 4 are kept (Collatz termination is not provable). Exit: x3 = 1000000 as in omc.
; @old 0x40027c 0xd2884804 0xf2a001e4 0xeb04007f 0x54000382 0x91000464 0xd2800005 0xd2800006 0xf100049f 0x54000220 0xd2884808 0xf2a001e8 0xeb0800df 0x54000ee2 0x910004c6 0xd2800028 0x8a080089 0xf100013f 0x54000061 0xd341fc84 0x14000004 0xd2800068 0x9b087c89 0x91000524 0x910004a5 0x17ffffef 0x8b050021 0xeb0200bf 0x54000049 0xaa0503e2 0x91000463 0x17ffffe2
; @at 0x40027c
movzx 7 0x4240 0 | mov x7, #0x4240
movkx 7 0xf 1 | movk x7, #0xf, lsl #16
addxi 4 3 1 0 | add x4, x3, #0x1
movzx 5 0 0 | mov x5, #0x0
movzx 6 0 0 | mov x6, #0x0
subsxi 31 4 1 0 | cmp x4, #0x1
bcond 0 13 | b.eq @+52
subsx 31 6 7 | cmp x6, x7
bcond 2 123 | b.cs @+492
addxi 6 6 1 0 | add x6, x6, #0x1
andsxi 31 4 0x1 | tst x4, #0x1
bcond 1 3 | b.ne @+12
ubfmx 4 4 1 63 | lsr x4, x4, #1
b 3 | b @+12
addx 4 4 4 0 1 | add x4, x4, x4, lsl #1
addxi 4 4 1 0 | add x4, x4, #0x1
addxi 5 5 1 0 | add x5, x5, #0x1
subsxi 31 4 1 0 | cmp x4, #0x1
bcond 1 -11 | b.ne @-44
addx 1 1 5 | add x1, x1, x5
subsx 31 5 2 | cmp x5, x2
bcond 9 2 | b.ls @+8
addxi 2 5 0 0 | add x2, x5, #0x0
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 3 7 | cmp x3, x7
bcond 3 -23 | b.cc @-92
b 5 | b @+20
; @nop 0x4002f8
