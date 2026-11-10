@ng a64-enc
; leafcall ngI: mix inlined into the loop (MUL, LSR #5, EOR), constants hoisted, rotation; the loop
; works in x1 (s), x2 (t), x3 (i) as omc does, so the exit state matches with no moves.
; @old 0x40028c 0xd2987004 0xf2a03924 0xeb04007f 0x54000302 0xd100c3ff 0xeb3c63ff 0x54000f63 0xf90003e0 0xf90007e1 0xf9000be2 0xf9000fe3 0xf90013fe 0xf9400fe0 0xd28f3621 0xf2b3c6e1 0x97ffffcd 0xaa0003e4 0xf94003e0 0xf94007e1 0xf9400be2 0xf9400fe3 0xf94013fe 0x9100c3ff 0x8b040021 0xca010042 0x91000463 0x17ffffe6
; @at 0x40028c
movzx 4 0xc380 0 | mov x4, #0xc380
movkx 4 0x1c9 1 | movk x4, #0x1c9, lsl #16
movzx 5 0x79b1 0 | mov x5, #0x79b1
movkx 5 0x9e37 1 | movk x5, #0x9e37, lsl #16
mulx 6 3 5 | mul x6, x3, x5
ubfmx 7 3 5 63 | lsr x7, x3, #5
eorx 6 6 7 | eor x6, x6, x7
addx 1 1 6 | add x1, x1, x6
eorx 2 2 1 | eor x2, x2, x1
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 3 4 | cmp x3, x4
bcond 3 -7 | b.cc @-28
b 15 | b @+60
; @nop 0x4002f8
