// E14 flag-source rule (positive control for the two negatives above). Hand-assembled (GNU as, oracle only).
// CMP x2,#64; B.CS leaves x2 in 0..63 on the fall-through edge, so the secret store to ctx+40+x2 is in
// 40..103, outside [32,40): excused (bounded-offset), the count load stays public, PASS.
        cmp     x2, #64
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
