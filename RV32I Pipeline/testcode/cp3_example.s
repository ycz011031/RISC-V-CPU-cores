.section .text
.globl _start
_start:
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
    lui x9, 0x10000       # Load base address (Assume some memory location)
    sw  x4, 0(x9)

    lw x10, 0(x9)         # Load x10 from memory (May require stall)
    add x11, x10, x2      # Use x10 immediately (Load-Use Hazard)
    sub x12, x11, x2 

     # -------- Forwarding from EX Stage --------
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

    # -------- Store Before Load (No RAW Hazard) --------
    lui x9, 0x10000       # Load base address (Assume some memory location)
    sw x7, 0(x9)          # Store x7 into memory
    lw x10, 0(x9)         # Load x10 from memory (should get x7's value)
    add x11, x10, x2      # Use x10 immediately (depends on load)

    # -------- Load-Use Hazard (Requires Stall) --------
    lw x12, 0(x9)         # Load x12 from memory
    add x13, x12, x2      # Use x12 immediately (Load-Use Hazard)
    sub x14, x13, x2      # Further dependency on x13 (should work after stall)

    # -------- Multiple Forwarding Cases --------
    add x15, x14, x1      # Forward from WB
    sub x16, x15, x4      # Forward from MM
    xor x17, x16, x6      # Forward from EX
    add x18, x17, x10     # Mixing forwarded and loaded values

    slti x0, x0, -256 # this is the magic instruction to end the simulation
    nop               # preventing fetching illegal instructions
    nop
    nop
    nop
    nop
