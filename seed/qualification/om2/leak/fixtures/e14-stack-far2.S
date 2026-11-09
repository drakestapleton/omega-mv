// E14 stack rule (negative), L1039 review P1. Hand-assembled function-mode artifact (GNU as, oracle only).
// x3 = SP - 8 MiB (two SUB #0x400,lsl #12), the SP itself never moved: the address is representable as a
// stack interval but is below everything the SP has covered, so with e14 it must revoke.
        mov     x3, sp
        sub     x3, x3, #0x400, lsl #12
        sub     x3, x3, #0x400, lsl #12
        ldrb    w4, [x1]
        strb    w4, [x3]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        ret
1:      mov     x0, #0
        ret
