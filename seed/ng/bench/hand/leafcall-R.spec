@ng a64-enc
; leafcall ngR: the call loop (omc 0x40028c..0x4002f4) keeps the call to mix (0x4001fc, untouched: it
; reads x0, x1 and clobbers only x0, x2, x3) but holds t0, s, t, i, the limit 30000000 and the constant
; 2654435761 in x9..x14, registers mix does not touch, and the link register in x15 for the whole loop:
; no per-call frame, stack check, 5 stores and 5 loads (register allocation across calls, the
; interprocedural form). Rotation (i = 0 on entry). Exit: x0..x3 restored to omc's exit values.
; @old 0x40028c 0xd2987004 0xf2a03924 0xeb04007f 0x54000302 0xd100c3ff 0xeb3c63ff 0x54000f63 0xf90003e0 0xf90007e1 0xf9000be2 0xf9000fe3 0xf90013fe 0xf9400fe0 0xd28f3621 0xf2b3c6e1 0x97ffffcd 0xaa0003e4 0xf94003e0 0xf94007e1 0xf9400be2 0xf9400fe3 0xf94013fe 0x9100c3ff 0x8b040021 0xca010042 0x91000463 0x17ffffe6
; @at 0x40028c
addxi 9 0 0 0 | add x9, x0, #0x0
addxi 10 1 0 0 | add x10, x1, #0x0
addxi 11 2 0 0 | add x11, x2, #0x0
addxi 12 3 0 0 | add x12, x3, #0x0
movzx 13 0xc380 0 | mov x13, #0xc380
movkx 13 0x1c9 1 | movk x13, #0x1c9, lsl #16
movzx 14 0x79b1 0 | mov x14, #0x79b1
movkx 14 0x9e37 1 | movk x14, #0x9e37, lsl #16
addxi 15 30 0 0 | add x15, x30, #0x0
addxi 0 12 0 0 | add x0, x12, #0x0
addxi 1 14 0 0 | add x1, x14, #0x0
bl -47 | bl @-188
addx 10 10 0 | add x10, x10, x0
eorx 11 11 10 | eor x11, x11, x10
addxi 12 12 1 0 | add x12, x12, #0x1
subsx 31 12 13 | cmp x12, x13
bcond 3 -7 | b.cc @-28
addxi 30 15 0 0 | add x30, x15, #0x0
addxi 0 9 0 0 | add x0, x9, #0x0
addxi 1 10 0 0 | add x1, x10, #0x0
addxi 2 11 0 0 | add x2, x11, #0x0
addxi 3 12 0 0 | add x3, x12, #0x0
b 5 | b @+20
; @nop 0x4002f8
