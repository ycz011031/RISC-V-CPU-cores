mem_test.s:
.align 4
.section .text
.globl _start
    # This program consists of small snippets
    # containing RAW, WAW, and WAR hazards

    # This test is NOT exhaustive
_start:
# Spike can only use memory from 0x1eceb000 with length 0xe1315000
# initialize
lui x1,  4
lui x2,  4
lui x3,  4
lui x4,  4
lui x5,  4
lui x6,  8
lui x7,  8
lui x8,  8
lui x9,  16
lui x10, 16
lui x11, 24
lui x12, 24
lui x13, 24

#store operations
sb x1, 0(x5)
sw x1, 0(x5)
sb x2, 0(x5)
sb x3, 4(x5)
sb x4, 8(x5)

sh x1, 4(x6)
sh x2, 6(x5)

sw x3, 4(x5)
sw x4, 12(x5)
sw x1, 8(x1)

#load operations

lb x6, 4(x5)
lb x7, 4(x5)

lbu x8, 2(x5)
lbu x9, 3(x5)

lh x10, 4(x5)
lh x11, 6(x10)

lhu x12, 6(x10)

lw x13, 8(x5)

halt:
    slti x0, x0, -256



