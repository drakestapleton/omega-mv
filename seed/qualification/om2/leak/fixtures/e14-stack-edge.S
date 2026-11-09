// E14 stack rule, boundary (positive). Hand-assembled function-mode artifact (GNU as, oracle only).
// f(x0 = ctx, x1 = secret byte): a 16-byte local array [SP, SP+16) lies below the entry SP R, so the byte
// stored at SP+15 is at R-1: outside any caller range. The declared count [32,40) stays public: PASS.
        sub     sp, sp, #16
        mov     x3, sp
        ldrb    w4, [x1]
        strb    w4, [x3, #15]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        add     sp, sp, #16
        ret
1:      mov     x0, #0
        add     sp, sp, #16
        ret
