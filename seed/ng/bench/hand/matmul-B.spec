@ng a64-enc
; matmul ngB: ngL without the three bounds checks: r = 300i <= 89700 and k < 300 give r + k < 90000;
; q = j + 300k <= 299 + 89700 < 90000; r + j < 90000.
; @old 0x4002bc 0xd2800000 0xf104b01f 0x54000562 0xd2802582 0x9b027c01 0xd2800002 0xf104b05f 0x54000482 0xd2800003 0xaa0203e4 0xd2800005 0xf104b0bf 0x540002a2 0x8b050026 0xd28bf208 0xf2a00028 0xeb0800df 0x54000402 0xd2800409 0xf2a21009 0xf866792a 0xd28bf20b 0xf2a0002b 0xeb0b009f 0x54000322 0xd29f940c 0xf2a2114c 0xf864798d 0x9b0d7d4e 0x8b0e0063 0x9104b084 0x910004a5 0x17ffffeb 0x8b020025 0xd28bf206 0xf2a00026 0xeb0600bf 0x54000182 0xd29f2408 0xf2a212a8 0xf8257903 0x91000442 0x17ffffdc 0x91000400 0x17ffffd5 0xd65f03c0
; @at 0x4002bc
movzx 0 0 0 | mov x0, #0x0
movzx 9 0x20 0 | mov x9, #0x20
movkx 9 0x1080 1 | movk x9, #0x1080, lsl #16
movzx 12 0xfca0 0 | mov x12, #0xfca0
movkx 12 0x108a 1 | movk x12, #0x108a, lsl #16
movzx 15 0xf920 0 | mov x15, #0xf920
movkx 15 0x1095 1 | movk x15, #0x1095, lsl #16
movzx 16 300 0 | mov x16, #0x12c
mulx 1 0 16 | mul x1, x0, x16
movzx 2 0 0 | mov x2, #0x0
movzx 3 0 0 | mov x3, #0x0
addxi 4 2 0 0 | add x4, x2, #0x0
movzx 5 0 0 | mov x5, #0x0
addx 6 1 5 | add x6, x1, x5
ldrxr 10 9 6 1 | ldr x10, [x9, x6, lsl #3]
ldrxr 13 12 4 1 | ldr x13, [x12, x4, lsl #3]
mulx 14 10 13 | mul x14, x10, x13
addx 3 3 14 | add x3, x3, x14
addxi 4 4 300 0 | add x4, x4, #0x12c
addxi 5 5 1 0 | add x5, x5, #0x1
subsx 31 5 16 | cmp x5, x16
bcond 3 -8 | b.cc @-32
addx 5 1 2 | add x5, x1, x2
strxr 3 15 5 1 | str x3, [x15, x5, lsl #3]
addxi 2 2 1 0 | add x2, x2, #0x1
subsx 31 2 16 | cmp x2, x16
bcond 3 -16 | b.cc @-64
addxi 0 0 1 0 | add x0, x0, #0x1
subsx 31 0 16 | cmp x0, x16
bcond 3 -21 | b.cc @-84
ret 30 | ret
; @nop 0x400374
