# RISC-V CPU Cores Project

This repository contains implementations of RISC-V CPU cores, including a pipelined RV32I processor and an out-of-order RV32IM processor. These designs are part of the ECE 411 coursework and demonstrate advanced computer architecture concepts.

## RV32I Pipeline

### Overview
The RV32I Pipeline folder contains the implementation of a 5-stage pipelined processor compliant with the RV32I instruction set architecture (ISA). The design excludes the `FENCE*`, `ECALL`, `EBREAK`, and `CSRR*` instructions. The processor supports naturally aligned loads and stores and resolves all hazards without unnecessary stalls.

### Key Features
- **5-Stage Pipeline:** Includes Fetch, Decode, Execute, Memory, and Writeback stages.
- **Hazard Resolution:** Implements forwarding and stalling mechanisms to handle data and control hazards.
- **Memory Ports:** Exposes separate instruction and data memory ports with specific timing characteristics.
- **Documentation:** Includes diagrams and detailed specifications in the `README.md` and `doc` folder.

### Files
- `hdl/`: Contains SystemVerilog files for the processor's hardware implementation.
- `hvl/`: Includes testbenches and verification components.
- `testcode/`: Provides assembly test programs for functional verification.
- `options.json`: Configuration file for synthesis and simulation.

### References
- [RISC-V Instruction Set Manual](https://drive.google.com/file/d/1uviu1nH-tScFfgrovvFCrj7Omv8tFtkp/view)

---

## RV32IM Out-of-Order

### Overview
The RV32IM Out-of-Order folder contains the implementation of an out-of-order processor supporting the RV32IM ISA. This design demonstrates advanced features such as speculative execution and dynamic scheduling.

### Key Features
- **Out-of-Order Execution:** Implements dynamic instruction scheduling to improve performance.
- **Superscalar Design:** Capable of issuing multiple instructions per cycle.
- **Speculative Execution:** Supports branch prediction and speculative memory access.
- **Configurable Parameters:** Allows customization of clock period, extensions, and memory behavior via `options.json`.
- **Synopsys IP Integration:** Supports the use of Synopsys digital IP for arithmetic operations.

### Files
- `hdl/`: Contains SystemVerilog files for the processor's hardware implementation.
- `hvl/`: Includes testbenches and verification components.
- `sim/`: Provides scripts and configurations for simulation and synthesis.
- `docs/`: Contains detailed guides and resources
- `options.json`: Configuration file for synthesis and simulation.

### References
- [Synopsys Datasheets](https://www.synopsys.com/): Documentation for supported IP modules.

