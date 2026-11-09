// E14 stack rule, boundary (negative). Hand-assembled function-mode artifact (GNU as, oracle only).
// Same as e14-stack-edge.S but the secret byte goes to SP+16 = R, the first byte of the caller's memory:
// it is not provably below the entry SP, so with e14 it must revoke the declared count field and the
// count load stays DATA MANUAL / NOT_RUN. A callee that believes its array is larger than the caller's
// (A1 across calls) is this same shape.
        sub     sp, sp, #16
        mov     x3, sp
        ldrb    w4, [x1]
        strb    w4, [x3, #16]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        add     sp, sp, #16
        ret
1:      mov     x0, #0
        add     sp, sp, #16
        ret
