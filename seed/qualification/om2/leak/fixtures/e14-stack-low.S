// E14 stack rule, lower boundary (positive). Hand-assembled function-mode artifact (GNU as, oracle only).
// The lowest byte of a 16-byte frame, [SP], is memory the SP covered: excused (stack-below-entry-sp), the
// declared count load stays public, PASS.
        sub     sp, sp, #16
        mov     x3, sp
        ldrb    w4, [x1]
        strb    w4, [x3]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        add     sp, sp, #16
        ret
1:      mov     x0, #0
        add     sp, sp, #16
        ret
