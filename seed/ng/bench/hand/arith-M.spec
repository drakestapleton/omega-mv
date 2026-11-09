@ng a64-enc
; arith ngM: ngL with rem 1000003 as a multiply by the reciprocal (Granlund-Montgomery round-up method,
; N = 64, l = 20, m = 0x0c6f45449cb59c69 = floor(2^64 (2^20 - d)/d) + 1, the constant gcc -O2 uses; exact
; for every 64-bit dividend, Wolfram receipt in PAYOFF.md): q = (hi + ((t - hi) >> 1)) >> 19, hi = umulh(t, m).
; @old 0x40027c 0xd28b4004 0xf2a04c44 0xeb04007f 0x540001c2 0xd28003e4 0x9b047c25 0x8b0300a1 0x9b037c65 0xd343fc66 0xca0600a4 0xd2884865 0xf2a001e5 0x9ac50888 0x9b059106 0x8b060042 0x91000463 0x17fffff0
; @at 0x40027c
b 136 | b @+544
; @at 0x400478
; @nop 0x40049c
movzx 4 0x5a00 0 | mov x4, #0x5a00
movkx 4 0x262 1 | movk x4, #0x262, lsl #16
movzx 7 31 0 | mov x7, #0x1f
movzx 10 0x4243 0 | mov x10, #0x4243
movkx 10 0xf 1 | movk x10, #0xf, lsl #16
movzx 11 0x9c69 0 | mov x11, #0x9c69
movkx 11 0x9cb5 1 | movk x11, #0x9cb5, lsl #16
movkx 11 0x4544 2 | movk x11, #0x4544, lsl #32
movkx 11 0xc6f 3 | movk x11, #0xc6f, lsl #48
mulx 5 1 7 | mul x5, x1, x7
addx 1 5 3 | add x1, x5, x3
mulx 5 3 3 | mul x5, x3, x3
ubfmx 6 3 3 63 | lsr x6, x3, #3
eorx 8 5 6 | eor x8, x5, x6
umulh 9 8 11 | umulh x9, x8, x11
subx 12 8 9 | sub x12, x8, x9
addx 12 9 12 1 1 | add x12, x9, x12, lsr #1
ubfmx 12 12 19 63 | lsr x12, x12, #19
msubx 6 12 10 8 | msub x6, x12, x10, x8
addx 2 2 6 | add x2, x2, x6
addxi 3 3 1 0 | add x3, x3, #0x1
subsx 31 3 4 | cmp x3, x4
bcond 3 -13 | b.cc @-52
b -142 | b @-568
