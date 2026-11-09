@ng a64-enc
; bcopy ngV: ngB vectorised, 16 bytes per pass: LDR Q, REV64 + EXT #8 (a full 16-byte reverse), EOR with k
; broadcast by DUP, STR Q at dst + 65520 - i. 65536 is a multiple of 16, so there is no tail. The SIMD
; words are literal (the encoder has no SIMD forms); each one's text is checked by objdump.
; @old 0x40011c 0xd2800002 0xd2a00023 0xeb03005f 0x54000202 0xd29fffe3 0xcb020064 0xd2a00025 0xeb05005f 0x54000562 0xd2a21006 0x386268c8 0xca010109 0xd2a0002a 0xeb0a009f 0x540004a2 0xd2a2102b 0x38246969 0x91000442 0x17ffffef
; @at 0x40011c
movzx 2 0 0 | mov x2, #0x0
movzx 3 1 1 | mov x3, #0x10000
movzx 4 0xfff0 0 | mov x4, #0xfff0
movzx 6 0x1080 1 | mov x6, #0x10800000
movzx 11 0x1081 1 | mov x11, #0x10810000
; @word 0x4e010c21 | dup v1.16b, w1
; @word 0x3ce268c0 | ldr q0, [x6, x2]
; @word 0x4e200800 | rev64 v0.16b, v0.16b
; @word 0x6e004000 | ext v0.16b, v0.16b, v0.16b, #8
; @word 0x6e211c00 | eor v0.16b, v0.16b, v1.16b
; @word 0x3ca46960 | str q0, [x11, x4]
addxi 2 2 16 0 | add x2, x2, #0x10
subxi 4 4 16 0 | sub x4, x4, #0x10
subsx 31 2 3 | cmp x2, x3
bcond 1 -8 | b.ne @-32
; @nop 0x400168
