.section .text
.globl _start
_start:
    addi x1, x0, 4
    nop             # nops in between to prevent hazard
    nop
    nop
    nop
    nop
    addi x3, x1, 8
    nop
    nop
    nop
    nop
    nop
    
    lui x1, 0x00001
    nop
    nop
    nop
    nop
    nop
    lui x2, 0x00002
    nop
    nop
    nop
    nop
    nop
    lui x3, 0x00003
    nop
    nop
    nop
    nop
    nop
    lui x4, 0x00004
    nop
    nop
    nop
    nop
    nop
    lui x5, 0x00005
    nop
    nop
    nop
    nop
    nop
    lui x6, 0x00006
    nop
    nop
    nop
    nop
    nop
    lui x7, 0x00007
    nop
    nop
    nop
    nop
    nop
    lui x8, 0x00008
    nop
    nop
    nop
    nop
    nop
    lui x9, 0x00009
    nop
    nop
    nop
    nop
    nop
    lui x10, 0x0000A
    nop
    nop
    nop
    nop
    nop
    lui x11, 0x0000B
    nop
    nop
    nop
    nop
    nop
    lui x12, 0x0000C
    nop
    nop
    nop
    nop
    nop
    lui x13, 0x0000D
    nop
    nop
    nop
    nop
    nop
    lui x14, 0x0000E
    nop
    nop
    nop
    nop
    nop
    lui x15, 0x0000F
    nop
    nop
    nop
    nop
    nop
    lui x16, 0x00010
    nop
    nop
    nop
    nop
    nop
    lui x17, 0x00011
    nop
    nop
    nop
    nop
    nop
    lui x18, 0x00012
    nop
    nop
    nop
    nop
    nop
    lui x19, 0x00013
    nop
    nop
    nop
    nop
    nop
    lui x20, 0x00014
    nop
    nop
    nop
    nop
    nop
    lui x21, 0x00015
    nop
    nop
    nop
    nop
    nop
    lui x22, 0x00016
    nop
    nop
    nop
    nop
    nop
    lui x23, 0x00017
    nop
    nop
    nop
    nop
    nop
    lui x24, 0x00018
    nop
    nop
    nop
    nop
    nop
    lui x25, 0x00019
    nop
    nop
    nop
    nop
    nop
    lui x26, 0x0001A
    nop
    nop
    nop
    nop
    nop
    lui x27, 0x0001B
    nop
    nop
    nop
    nop
    nop
    lui x28, 0x0001C
    nop
    nop
    nop
    nop
    nop
    lui x29, 0x0001D
    nop
    nop
    nop
    nop
    nop
    lui x30, 0x0001E
    nop
    nop
    nop
    nop
    nop
    lui x31, 0x0001F
    nop
    nop
    nop
    nop
    nop
    # Store Byte (SB)
    sb  x1, 0(x5)          # Store least significant byte of x1 at 0x1000
    nop
    nop
    sb  x2, 1(x5)          # Store least significant byte of x2 at 0x1001
    nop
    nop
    sb  x3, 2(x5)          # Store least significant byte of x3 at 0x1002
    nop
    nop
    sb  x4, 3(x5)          # Store least significant byte of x4 at 0x1003
    nop
    nop

    # Store Halfword (SH)
    sh  x1, 4(x5)          # Store least significant halfword of x1 at 0x1004
    nop
    nop
    sh  x2, 6(x5)          # Store least significant halfword of x2 at 0x1006
    nop
    nop

    # Store Word (SW)
    sw  x3, 8(x5)          # Store full word of x3 at 0x1008
    nop
    nop
    sw  x4, 12(x5)         # Store full word of x4 at 0x100C
    nop
    nop

    lb x6, 0(x5)           # Load byte from 0x1000 into x6 (sign-extended)
    nop
    nop
    lb x7, 1(x5)           # Load byte from 0x1001 into x7 (sign-extended)
    nop
    nop

    # Load Byte Unsigned (LBU)
    lbu x8, 2(x5)          # Load byte from 0x1002 into x8 (zero-extended)
    nop
    nop
    lbu x9, 3(x5)          # Load byte from 0x1003 into x9 (zero-extended)
    nop
    nop

    # Load Halfword Signed (LH)
    lh x10, 4(x5)          # Load halfword from 0x1004 into x10 (sign-extended)
    nop
    nop
    lh x11, 6(x5)          # Load halfword from 0x1006 into x11 (sign-extended)
    nop
    nop

    # Load Halfword Unsigned (LHU)
    lhu x12, 6(x5)         # Load halfword from 0x1006 into x12 (zero-extended)
    nop
    nop

    # Load Word (LW)
    lw x13, 8(x5)          # Load word from 0x1008 into x13
    nop
    nop
    lw x14, 12(x5)         # Load word from 0x100C into x14
    nop
    nop

    nop
    nop
    nop
    nop
    nop
    add x1, x2, x3
    nop
    nop
    nop
    nop
    nop
    add x1, x2, x3   # opcode=0110011, funct3=000, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    sub x4, x5, x6   # opcode=0110011, funct3=000, funct7=0100000
    nop
    nop
    nop
    nop
    nop
    sll x7, x8, x9   # opcode=0110011, funct3=001, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    slt x10, x11, x12 # opcode=0110011, funct3=010, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    sltu x13, x14, x15 # opcode=0110011, funct3=011, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    xor x16, x17, x18 # opcode=0110011, funct3=100, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    srl x19, x20, x21 # opcode=0110011, funct3=101, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    sra x22, x23, x24 # opcode=0110011, funct3=101, funct7=0100000
    nop
    nop
    nop
    nop
    nop
    or x25, x26, x27  # opcode=0110011, funct3=110, funct7=0000000
    nop
    nop
    nop
    nop
    nop
    and x28, x29, x30 # opcode=0110011, funct3=111, funct7=0000000

    addi x1, x2, 10   # opcode=0010011, funct3=000
    nop
    nop
    nop
    nop
    nop
    slli x3, x4, 2    # opcode=0010011, funct3=001, shamt=2
    nop
    nop
    nop
    nop
    nop
    slti x5, x6, 5    # opcode=0010011, funct3=010
    nop
    nop
    nop
    nop
    nop
    sltiu x7, x8, 5   # opcode=0010011, funct3=011
    nop
    nop
    nop
    nop
    nop
    xori x9, x10, 15  # opcode=0010011, funct3=100
    nop
    nop
    nop
    nop
    nop
    srli x11, x12, 1  # opcode=0010011, funct3=101, shamt=1
    nop
    nop
    nop
    nop
    nop
    srai x13, x14, 1  # opcode=0010011, funct3=101, shamt=1, funct7=0100000
    nop
    nop
    nop
    nop
    nop
    ori x15, x16, 20  # opcode=0010011, funct3=110
    nop
    nop
    nop
    nop
    nop
    andi x17, x18, 25 # opcode=0010011, funct3=111
    nop
    nop
    nop
    nop
    nop

    lui x1, 0x12345   # opcode=0110111
    nop
    nop
    nop
    nop
    nop
    lui x2, 0x67890   # opcode=0110111
    nop
    nop
    nop
    nop
    nop
    lui x3, 0xABCDE   # opcode=0110111
    nop
    nop
    nop
    nop
    nop
    lui x4, 0xFFFFF   # opcode=0110111

    auipc x5, 0x10000 # opcode=0010111
    nop
    nop
    nop
    nop
    nop
    auipc x6, 0x20000 # opcode=0010111
    nop
    nop
    nop
    nop
    nop
    auipc x7, 0x30000 # opcode=0010111
    nop
    nop
    nop
    nop
    nop
    auipc x8, 0x40000 # opcode=0010111
    nop
    nop
    nop
    nop
    nop

    addi x1, x0, 4
    addi x3, x1, 8

    addi x1, x0, 5        # x1 = 5
    addi x2, x0, 10       # x2 = 10
    add x3, x1, x2        # x3 = x1 + x2  (Forward from EX to next inst.)
    sub x4, x3, x2        # x4 = x3 - x2  (Forward from EX)
    
    # -------- Forwarding from MM Stage --------
    add x5, x4, x3        # x5 = x4 + x3  (Depends on MM result)
    sub x6, x5, x3        # x6 = x5 - x3  (Uses MM forwarded value)

    # -------- Forwarding from WB Stage --------
    add x7, x6, x5        # x7 = x6 + x5  (Uses WB forwarded value)
    xor x8, x7, x6        # x8 = x7 ^ x6  (Uses WB result)

    # -------- Load-Use Hazard (Requires Stall) --------
    lui x9, 0xaaff0       # Load base address (Assume some memory location)
    sw  x4, 12(x5)
    lw x10, 12(x5)         # Load x10 from memory (May require stall)
    add x11, x10, x2      # Use x10 immediately (Load-Use Hazard)
    sub x12, x11, x2 




    slti x0, x0, -256 # this is the magic instruction to end the simulation
    nop               # preventing fetching illegal instructions
    nop
    nop
    nop
    nop
