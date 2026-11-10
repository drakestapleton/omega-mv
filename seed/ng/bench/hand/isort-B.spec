@ng a64-enc
; isort ngB: ngL plus range-analysis eliminations: j < 20000 (loop test), 1 <= k <= j so k - 1 and k are in
; [0, 20000), so every bounds check goes; k strictly decreases on every continuing pass from k <= 19999, so
; the while bound (1000000) cannot be reached and its counter goes too.
; @old 0x400278 0xd2800000 0xd289c401 0xeb01001f 0x540005c2 0xd289c402 0xeb02001f 0x540005e2 0xd2800403 0xf2a21003 0xf8607861 0xaa0003e2 0xd2800023 0xd2800004 0xf100005f 0x9a9f97e5 0x8a050066 0xb4000326 0xd2884808 0xf2a001e8 0xeb08009f 0x54000462 0x91000484 0xd1000446 0xd289c408 0xeb0800df 0x54000382 0xd2800409 0xf2a21009 0xf8667925 0xeb0100bf 0x54000129 0xd289c406 0xeb06005f 0x54000282 0xd2800408 0xf2a21008 0xf8227905 0xd1000442 0x14000002 0xd2800003 0x17ffffe5 0xd289c404 0xeb04005f 0x54000142 0xd2800405 0xf2a21005 0xf82278a1 0x91000400 0x17ffffd1 0xd65f03c0
; @at 0x400278
movzx 0 0 0 | mov x0, #0x0
movzx 7 0x4e20 0 | mov x7, #0x4e20
movzx 9 0x20 0 | mov x9, #0x20
movkx 9 0x1080 1 | movk x9, #0x1080, lsl #16
ldrxr 1 9 0 1 | ldr x1, [x9, x0, lsl #3]
addxi 2 0 0 0 | add x2, x0, #0x0
cbzx 2 8 | cbz x2, @+32
subxi 6 2 1 0 | sub x6, x2, #0x1
ldrxr 5 9 6 1 | ldr x5, [x9, x6, lsl #3]
subsx 31 5 1 | cmp x5, x1
bcond 9 4 | b.ls @+16
strxr 5 9 2 1 | str x5, [x9, x2, lsl #3]
addxi 2 6 0 0 | add x2, x6, #0x0
cbnzx 2 -6 | cbnz x2, @-24
strxr 1 9 2 1 | str x1, [x9, x2, lsl #3]
addxi 0 0 1 0 | add x0, x0, #0x1
subsx 31 0 7 | cmp x0, x7
bcond 3 -13 | b.cc @-52
ret 30 | ret
; @nop 0x400340
