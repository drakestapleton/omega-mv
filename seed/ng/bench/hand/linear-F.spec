@ng a64-enc
; linear ngF: ngB with instruction selection for f32 loads: LDR S straight into the FP register, then
; FCVT (2 instructions where omc spends LDR W + FMOV + FCVT).
; @old 0x4000b4 0xf104009f 0x54000462 0xb8647806 0x1e2700c0 0x1e22c015 0xd2802008 0x9b087c66 0xd2802009 0x9b097c88 0xd2800009 0xf104013f 0x54000262 0xd288000a 0xeb0a00df 0x540002c2 0xb866782b 0x1e270160 0x1e22c01b 0xd2a0002d 0xeb0d011f 0x54000202 0xb868784e 0x1e2701c0 0x1e22c01e 0x1e7e0b7f 0x1e7f2ab5 0x910004c6 0x91000508 0x91000529 0x17ffffed 0x9e6602a5 0xaa0503e0 0xd65f03c0
; @at 0x4000b4
subsxi 31 4 256 0 | cmp x4, #0x100
bcond 2 35 | b.cs @+140
ldrsr 0 0 4 1 | ldr s0, [x0, x4, lsl #2]
fcvtds 21 0 | fcvt d21, s0
movzx 8 256 0 | mov x8, #0x100
mulx 6 3 8 | mul x6, x3, x8
mulx 8 4 8 | mul x8, x4, x8
movzx 10 0x3f00 0 | mov x10, #0x3f00
subsx 31 6 10 | cmp x6, x10
bcond 8 27 | b.hi @+108
movzx 13 0xff00 0 | mov x13, #0xff00
subsx 31 8 13 | cmp x8, x13
bcond 8 24 | b.hi @+96
movzx 9 0 0 | mov x9, #0x0
ldrsr 0 1 6 1 | ldr s0, [x1, x6, lsl #2]
fcvtds 27 0 | fcvt d27, s0
ldrsr 1 2 8 1 | ldr s1, [x2, x8, lsl #2]
fcvtds 30 1 | fcvt d30, s1
fmuld 31 27 30 | fmul d31, d27, d30
faddd 21 21 31 | fadd d21, d21, d31
addxi 6 6 1 0 | add x6, x6, #0x1
addxi 8 8 1 0 | add x8, x8, #0x1
addxi 9 9 1 0 | add x9, x9, #0x1
subsxi 31 9 256 0 | cmp x9, #0x100
bcond 3 -10 | b.cc @-40
fmovxd 5 21 | fmov x5, d21
orrx 0 31 5 | mov x0, x5
ret 30 | ret
; @nop 0x400138
