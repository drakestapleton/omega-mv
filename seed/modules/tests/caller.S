// Independent AArch64 OM2 ABI caller: preserve host state, supply private stack and X7.
.text
.global invoke
.type invoke, %function
invoke:
 stp x19,x20,[sp,#-16]!
 stp x21,x22,[sp,#-16]!
 stp x23,x24,[sp,#-16]!
 stp x25,x26,[sp,#-16]!
 stp x27,x28,[sp,#-16]!
 stp x29,x30,[sp,#-16]!
 stp d8,d9,[sp,#-16]!
 stp d10,d11,[sp,#-16]!
 stp d12,d13,[sp,#-16]!
 stp d14,d15,[sp,#-16]!
 mov x19,sp
 mov x16,x0
 mov x17,x1
 mov x7,x2
 mov x0,x3
 mov x1,x4
 mov x2,x5
 mov sp,x17
 blr x16
 mov sp,x19
 ldp d14,d15,[sp],#16
 ldp d12,d13,[sp],#16
 ldp d10,d11,[sp],#16
 ldp d8,d9,[sp],#16
 ldp x29,x30,[sp],#16
 ldp x27,x28,[sp],#16
 ldp x25,x26,[sp],#16
 ldp x23,x24,[sp],#16
 ldp x21,x22,[sp],#16
 ldp x19,x20,[sp],#16
 ret
.global trap_entry
.type trap_entry, %function
trap_entry:
 add x0,x1,#100
 mov x8,#93
 svc #0
.section .note.GNU-stack,"",%progbits
