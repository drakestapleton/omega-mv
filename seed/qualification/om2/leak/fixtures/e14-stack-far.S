// E14 stack rule (negative), L1039 review P1. Hand-assembled function-mode artifact (GNU as, oracle only).
// x3 = SP - 0x2aaa00000000 never lies in memory the SP has covered (a heap or mapped-file address on
// Linux AArch64), so the secret byte stored there may be the declared count [32,40): with e14 it must
// revoke. A rule that only checks "address below the entry SP" excuses it (false PASS).
        mov     x3, sp
        movz    x9, #0x2aaa, lsl #32
        sub     x3, x3, x9
        ldrb    w4, [x1]
        strb    w4, [x3]
        ldr     x5, [x0, #32]
        cbz     x5, 1f
        mov     x0, #1
        ret
1:      mov     x0, #0
        ret
