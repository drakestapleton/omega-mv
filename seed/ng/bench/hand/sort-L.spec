@ng a64-enc
; sort ngL: the same rewrite as isort-L.spec on sort's isort (omc 0x400128..0x4001cc; the array
; `a edit ulong 40000` arrives in x0): 40000 and 1000000 hoisted into x7, x9, rotation, the eager and
; lowered to branches; bounds checks (trap 3, 0x4001dc) and the while bound counter x5 (trap 4, 0x4001e4) kept.
; @old 0x400128 0xd2800001 0xd2938802 0xeb02003f 0x540004c2 0xd2938803 0xeb03003f 0x540004e2 0xf8617802 0xaa0103e3 0xd2800024 0xd2800005 0xf100007f 0x9a9f97e6 0x8a060088 0xb40002a8 0xd2884809 0xf2a001e9 0xeb0900bf 0x540003a2 0x910004a5 0xd1000468 0xd2938809 0xeb09011f 0x540002c2 0xf8687806 0xeb0200df 0x540000e9 0xd2938808 0xeb08007f 0x54000202 0xf8237806 0xd1000463 0x14000002 0xd2800004 0x17ffffe9 0xd2938805 0xeb05007f 0x54000102 0xf8237802 0x91000421 0x17ffffd9 0xd65f03c0
; @at 0x400128
movzx 1 0 0 | mov x1, #0x0
movzx 7 0x9c40 0 | mov x7, #0x9c40
movzx 9 0x4240 0 | mov x9, #0x4240
movkx 9 0xf 1 | movk x9, #0xf, lsl #16
subsx 31 1 7 | cmp x1, x7
bcond 2 40 | b.cs @+160
ldrxr 2 0 1 1 | ldr x2, [x0, x1, lsl #3]
addxi 3 1 0 0 | add x3, x1, #0x0
movzx 5 0 0 | mov x5, #0x0
cbzx 3 15 | cbz x3, @+60
subsx 31 5 9 | cmp x5, x9
bcond 2 36 | b.cs @+144
addxi 5 5 1 0 | add x5, x5, #0x1
subxi 8 3 1 0 | sub x8, x3, #0x1
subsx 31 8 7 | cmp x8, x7
bcond 2 30 | b.cs @+120
ldrxr 6 0 8 1 | ldr x6, [x0, x8, lsl #3]
subsx 31 6 2 | cmp x6, x2
bcond 9 6 | b.ls @+24
subsx 31 3 7 | cmp x3, x7
bcond 2 25 | b.cs @+100
strxr 6 0 3 1 | str x6, [x0, x3, lsl #3]
addxi 3 8 0 0 | add x3, x8, #0x0
cbnzx 3 -13 | cbnz x3, @-52
subsx 31 3 7 | cmp x3, x7
bcond 2 20 | b.cs @+80
strxr 2 0 3 1 | str x2, [x0, x3, lsl #3]
addxi 1 1 1 0 | add x1, x1, #0x1
subsx 31 1 7 | cmp x1, x7
bcond 3 -25 | b.cc @-100
ret 30 | ret
; @nop 0x4001d0
