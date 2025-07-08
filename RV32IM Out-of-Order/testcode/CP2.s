CP2.s:
.align 4
.section .text
.globl _start
    # This program consists of small snippets
    # containing RAW, WAW, and WAR hazards

    # This test is NOT exhaustive
_start:

# initialize
lui x1,  1
lui x2,  2
lui x3,  3
lui x4,  4
lui x5,  5
lui x6,  6
lui x7,  7
lui x8,  8
lui x9,  9
lui x10, 5
lui x11, 8
lui x12, 4
lui x13, 2

addi x1, x1, -1

nop
nop
nop
nop
nop



mul x10, x1, x2
mulh x11, x2, x3
mulhsu x12, x1, x3
mulhu x14, x3, x4


nop
nop
nop
nop
nop

div x10, x1, x2
divu x11, x1, x2
rem x12, x2, x3
remu x13, x3, x4

nop
nop
nop
nop
nop

div x10, x1, x0
divu x11, x1, x0
rem x12, x2, x0
remu x13, x3, x0

auipc x9, 1230


halt:
    slti x0, x0, -256