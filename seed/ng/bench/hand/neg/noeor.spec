@ng a64-enc
; bcopy ngB: ngL plus bounds-check elimination (i in [0, 65536) by the loop test, 65535 - i too), the
; store index kept as its own down-counting induction variable x4.
; @old 0x40011c 0xd2800002 0xd2a00023 0xeb03005f 0x54000202 0xd29fffe3 0xcb020064 0xd2a00025 0xeb05005f 0x54000562 0xd2a21006 0x386268c8 0xca010109 0xd2a0002a 0xeb0a009f 0x540004a2 0xd2a2102b 0x38246969 0x91000442 0x17ffffef
; @at 0x40011c
movzx 2 0 0 | mov x2, #0x0
movzx 3 1 1 | mov x3, #0x10000
movzx 4 0xffff 0 | mov x4, #0xffff
movzx 6 0x1080 1 | mov x6, #0x10800000
movzx 11 0x1081 1 | mov x11, #0x10810000
ldrbr 8 6 2 0 | ldrb w8, [x6, x2]
strbr 8 11 4 0 | strb w8, [x11, x4]
addxi 2 2 1 0 | add x2, x2, #0x1
subxi 4 4 1 0 | sub x4, x4, #0x1
subsx 31 2 3 | cmp x2, x3
bcond 1 -6 | b.ne @-24
; @nop 0x400168
