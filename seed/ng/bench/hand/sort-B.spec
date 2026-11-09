@ng a64-enc
; sort ngB: sort-L plus the range-analysis eliminations argued in isort-B.spec (length 40000 is part of
; the parameter type, so the same proof holds).
; @old 0x400128 0xd2800001 0xd2938802 0xeb02003f 0x540004c2 0xd2938803 0xeb03003f 0x540004e2 0xf8617802 0xaa0103e3 0xd2800024 0xd2800005 0xf100007f 0x9a9f97e6 0x8a060088 0xb40002a8 0xd2884809 0xf2a001e9 0xeb0900bf 0x540003a2 0x910004a5 0xd1000468 0xd2938809 0xeb09011f 0x540002c2 0xf8687806 0xeb0200df 0x540000e9 0xd2938808 0xeb08007f 0x54000202 0xf8237806 0xd1000463 0x14000002 0xd2800004 0x17ffffe9 0xd2938805 0xeb05007f 0x54000102 0xf8237802 0x91000421 0x17ffffd9 0xd65f03c0
; @at 0x400128
movzx 1 0 0 | mov x1, #0x0
movzx 7 0x9c40 0 | mov x7, #0x9c40
ldrxr 2 0 1 1 | ldr x2, [x0, x1, lsl #3]
addxi 3 1 0 0 | add x3, x1, #0x0
cbzx 3 8 | cbz x3, @+32
subxi 8 3 1 0 | sub x8, x3, #0x1
ldrxr 6 0 8 1 | ldr x6, [x0, x8, lsl #3]
subsx 31 6 2 | cmp x6, x2
bcond 9 4 | b.ls @+16
strxr 6 0 3 1 | str x6, [x0, x3, lsl #3]
addxi 3 8 0 0 | add x3, x8, #0x0
cbnzx 3 -6 | cbnz x3, @-24
strxr 2 0 3 1 | str x2, [x0, x3, lsl #3]
addxi 1 1 1 0 | add x1, x1, #0x1
subsx 31 1 7 | cmp x1, x7
bcond 3 -13 | b.cc @-52
ret 30 | ret
; @nop 0x4001d0
