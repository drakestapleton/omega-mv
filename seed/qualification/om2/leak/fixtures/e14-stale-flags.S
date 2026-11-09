// E14 flag-source rule (negative). Hand-assembled function-mode artifact (GNU as, oracle only).
// The second CMP (32-bit, a form the scanner does not record) replaces the flags: the B.CS tests w3, not x2,
// so x2 stays unbounded and the secret store to ctx+40+x2 may hit the declared count [32,40).
// With e14 it must still revoke.
        cmp     x2, #64
        cmp     w3, #1000
        b.cs    1f
        ldrb    w4, [x1]
        add     x5, x2, #40
        strb    w4, [x0, x5]
        ldr     x6, [x0, #32]
        cbz     x6, 2f
1:      mov     x0, #1
        ret
2:      mov     x0, #0
        ret
