# SPDX-License-Identifier: AGPL-3.0-only
# One line per required mnemonic; ADD x1,x2,x3 must be 0x00221800.
add x1, x2, x3
sub x4, x5, x6
addi x7, x8, -4
ld x9, 8(x10)
sd x11, 16(x12)
sw x13, 4(x14)
lwu x15, 0(x16)
lui x17, 0x1000
jal x18, 8
mul.lo x19, x20, x21
zmac z0, x1, x2
modp z3, z4
red.sum z5, x6, x7
andi x22, x23, 7
beq x24, x25, 4
bne x26, x27, -4
halt
