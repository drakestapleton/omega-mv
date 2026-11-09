// E14 stack rule, lower boundary (negative). Hand-assembled function-mode artifact (GNU as, oracle only).
// Same as e14-stack-low.S but the secret byte goes to [SP-1], one byte below the lowest SP of the walk:
// not memory the SP has covered, so with e14 it must revoke.
        sub     sp, sp, #16
        mov     x3, sp
        ldrb    w4, [x1]
        sturb   w4, [x3, #-1]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        add     sp, sp, #16
        ret
1:      mov     x0, #0
        add     sp, sp, #16
        ret
