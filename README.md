# RISC-V CPU Cores Project

This repository contains implementations of RISC-V CPU cores: a 5-stage pipelined processor (originally RV32I, now RV32IM) and an out-of-order RV32IM processor. These designs are part of the ECE 411 coursework and demonstrate advanced computer architecture concepts.

Both cores are plain, vendor-neutral RTL by default. Synopsys DesignWare IP is optional (`USE_SYNOPSYS_DW`). Both cores simulate on **Vivado xsim** and run the same RV32IM benchmarks. See [Vendor-neutral RTL and xsim flow](#vendor-neutral-rtl-and-xsim-flow).

## RV32I Pipeline

### Overview
The RV32I Pipeline folder contains the implementation of a 5-stage pipelined processor compliant with the RV32I instruction set architecture (ISA), extended with the **M extension** (RV32IM; the folder keeps its original name). The design excludes the `FENCE*`, `ECALL`, `EBREAK`, and `CSRR*` instructions. The processor supports naturally aligned loads and stores and resolves all hazards without unnecessary stalls.

### Key Features
- **5-Stage Pipeline:** Includes Fetch, Decode, Execute, Memory, and Writeback stages.
- **Hazard Resolution:** Implements forwarding and stalling mechanisms to handle data and control hazards.
- **Memory Ports:** Exposes separate instruction and data memory ports with specific timing characteristics.
- **M Extension:** `hdl/m_unit.sv` executes MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU. M-ops are handled like loads whose "memory" is the mul/div unit: they issue in the memory stage's load slot, stall the pipeline through the existing `mm_stall`/replay path until the unit responds, and get the same load-use bubble in fetch.
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
- **Synopsys IP Integration (optional):** Uses DesignWare `DW_mult_seq` / `DW_div_seq` when `USE_SYNOPSYS_DW` is defined (the `sim/Makefile` VCS/Verilator flow does this), otherwise the vendor-neutral `ip/gen_*_seq.sv`.

### Files
- `hdl/`: Contains SystemVerilog files for the processor's hardware implementation.
- `hvl/`: Includes testbenches and verification components.
- `sim/`: Provides scripts and configurations for simulation and synthesis.
- `docs/`: Contains detailed guides and resources
- `options.json`: Configuration file for synthesis and simulation.

### References
- [Synopsys Datasheets](https://www.synopsys.com/): Documentation for supported IP modules.


---

## Vendor-neutral RTL and xsim flow

### Synopsys IP gating
The only Synopsys-specific RTL was the sequential multiplier/divider
(`DW_mult_seq`, `DW_div_seq`). Every instance is now wrapped in

```systemverilog
`ifdef USE_SYNOPSYS_DW
    DW_mult_seq  #(...) ...   // DesignWare (needs the DW sim models / synthesis library)
`else
    gen_mult_seq #(...) ...   // ip/gen_mult_seq.sv, same parameters and ports
`endif
```

| Where | Instances |
|---|---|
| `RV32IM Out-of-Order/hdl/func_mul.sv`, `func_div.sv` | OoO multiply / divide functional units |
| `RV32I Pipeline/hdl/m_unit.sv` | pipeline M unit (both operators) |

The original Synopsys flow (`RV32IM Out-of-Order/sim/Makefile`) defines
`USE_SYNOPSYS_DW`, so VCS/Verilator/DC behave as before. Define it in any other
Synopsys-based flow (synthesis scripts, etc.) that should keep using DesignWare.

### Vendor-neutral operator IP (`ip/`)
| File | Purpose |
|---|---|
| `ip/gen_mult_seq.sv` | Drop-in for `DW_mult_seq` (same parameter and port list) |
| `ip/gen_div_seq.sv`  | Drop-in for `DW_div_seq` (same parameter and port list) |
| `ip/xilinx_mcp.xdc`  | Vivado multicycle-path constraints for both |

Each operator is an **implicit operator closed with a multicycle path**.
Operands are registered on `start`, and the result is a plain `*` (or an explicit
restoring-division array, which avoids relying on `/` support in FPGA tools).
The result register only loads when an internal counter expires
`LATENCY = num_cyc - early_start` edges later (4 cycles for MUL and 17 for DIV,
as both cores configure them). `complete` handshakes exactly like DesignWare:
it drops on the `start` edge and rises with a valid result. The boundary
registers are `dont_touch`, so the XDC can find them and synthesis cannot fold
them into DSP pipeline stages.

Checked with Vivado 2025.1 (out-of-context synthesis of the pipeline `m_unit`,
xc7a100t, 100 MHz): worst setup slack is -81.2 ns without the constraints
(the combinational divider is about 91 ns) and +6.3 ns with `ip/xilinx_mcp.xdc`.
Hold is met. Cost is 4 DSPs, about 2.4k LUTs and 307 FFs. If you change
`num_cyc` / `early_start`, update the multipliers in the XDC.

### Simulating on Vivado xsim
Requirements: Vivado (xsim) and Python 3. No RISC-V toolchain, Spike, or
`bin/` course scripts are needed. Run from the repository root (`py` on Windows,
`python3` on Linux):

```sh
# one program on one core
py tools/xsim/run_xsim.py ooo      "RV32IM Out-of-Order/testcode/coremark_im.elf"
py tools/xsim/run_xsim.py pipeline "RV32IM Out-of-Order/testcode/im/fft.elf"
py tools/xsim/run_xsim.py pipeline prog.elf --wave          # also write a .wdb waveform

# shared benchmark list on both cores, with commit-log cross-check
py tools/xsim/run_regress.py
```

Vivado is found through `XILINX_VIVADO`, `PATH`, or the standard install
locations, or you can pass `--vivado <dir>`. Build output goes to `<core>/xsim/`
(git-ignored):
`run/simulation.log`, `spike/commit.log` (Spike `--log-commits` format), and
`logs/<bench>.*` from the regression.

How correctness is checked on xsim:
* **riscv-formal RVFI monitor** (`hvl/common/rvfimon.v`) checks every retired
  instruction against the ISA spec, including real RV32M semantics, plus the X
  checks in `hvl/common/monitor.sv`.
* **Cross-core commit-log comparison**: `run_regress.py` requires both cores to
  retire bit-identical instruction streams (PC, instruction, rd value, memory
  address and data).
* The Spike DPI co-simulation (`spike.so`, Linux/VCS only) is disabled on xsim
  (`ECE411_NO_SPIKE_DPI`). `$fsdb*` dumping is skipped under `ECE411_XSIM`.

Regression results (Vivado 2025.1 xsim, generic `ip/` operators, segment IPC).
Every benchmark passes the RVFI monitor on both cores, and both cores retire
bit-identical commit logs:

| Benchmark | OoO IPC | Pipeline IPC | Commit logs |
|---|---|---|---|
| `m_ext_test` (1,939 M-ops) | 0.253 | 0.109 | identical |
| `coremark_rv32i` | 0.474 | 0.213 | identical |
| `coremark_im` | 0.594 | 0.149 | identical |
| `aes_sha` | 0.366 | 0.134 | identical |
| `compression` | 0.820 | 0.239 | identical |
| `fft` | 0.678 | 0.136 | identical |
| `mergesort` | 0.599 | 0.134 | identical |

The pipeline's low IPC comes mostly from the testbench memory model
(`n_port_pipeline_memory_32_w_mask`, random 2 to 7 cycle misses on an
8-entry tag filter) and the design's replay-on-stall scheme. RV32I-only code
behaves exactly as before the M extension was added (same cycle counts).

Tools in `tools/xsim/`:

| Script | Purpose |
|---|---|
| `run_xsim.py` | compile, elaborate, and run one core/program; `--tcl` runs a custom xsim probe script, `-D`/`--extra-src` add defines and sources |
| `run_regress.py` | run the benchmark list on both cores and compare commit logs |
| `elf2mem.py` | ELF to `$readmemh` image (32-bit words for the pipeline, 256-bit bursts for the OoO DRAM model) |
| `gen_rvfi_ref.py` | `hvl/common/rvfi_reference.json` to `rvfi_reference.svh` |
| `gen_m_test.py` | toolchain-free generator for `testcode/m_ext_test.elf`, a directed RV32M test (corner operands, divide by zero, overflow, M-op hazards) |

### Simulator portability fix in the OoO core
Vivado xsim 2025.1 can silently drop **field-select nonblocking assignments
into unpacked arrays of structs** (`RS_entry[i].rs1_valid <= 1'b1;`) in this
design. Small test cases do not reproduce it, but in the full core a
reservation-station wakeup is lost and the core deadlocks. The CDB wakeup in
`res_station.sv`, `res_station_2way.sv` and `res_station_mem.sv` now applies
the update to a local copy and writes the whole element back with one
nonblocking assignment. RTL behavior is the same on every simulator.
