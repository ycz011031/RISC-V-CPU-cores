# RISC-V CPU Cores Project

This repository contains implementations of RISC-V CPU cores: a 5-stage pipelined processor (originally RV32I, now RV32IM) and an out-of-order RV32IM processor. These designs are part of the ECE 411 coursework and demonstrate advanced computer architecture concepts.

Both cores are plain, vendor-neutral RTL by default. Synopsys DesignWare IP is optional (`USE_SYNOPSYS_DW`). Both cores simulate on **Vivado xsim** and run the same RV32IM benchmarks. See [Vendor-neutral RTL and xsim flow](#vendor-neutral-rtl-and-xsim-flow).

## RV32I Pipeline

### Overview
The RV32I Pipeline folder contains the implementation of a 5-stage pipelined processor compliant with the RV32I instruction set architecture (ISA), extended with the **M extension** (RV32IM; the folder keeps its original name). The design excludes the `FENCE*`, `ECALL`, `EBREAK`, and `CSRR*` instructions. The processor supports naturally aligned loads and stores and resolves all hazards without unnecessary stalls.

### Key Features
- **5-Stage Pipeline:** Fetch, Decode, Execute, Memory, Writeback (`hdl/core.sv`). Stages are connected by packed structs from `pkg/types.sv`, in the same style as the out-of-order core: `if_id_stage_reg_t`, `id_ex_stage_reg_t`, `ex_mem_stage_reg_t`, `mem_wb_stage_reg_t`, `redirect_t`, `fwd_operands_t`, `mem_req_t` / `mem_rsp_t`, and an `rvfi_entry` commit port.
- **Memory system (low-power configuration):** `hdl/cpu.sv` = core, then `arbiter`, then one **shared 2 KB direct-mapped write-back cache** (`cache_shared`, 64 x 32 B, the OoO core's `dm_cache_*` SRAM macros), then the OoO core's `dram_adapter`. The top-level ports are the same banked DRAM interface as the out-of-order core, so both run on the same testbench memory model. The arbiter gives data accesses priority over instruction fetch.
- **Hold-until-response memory protocol:** a requester keeps presenting a request until it gets the response. A request that is dropped or changed is abandoned: a miss still fills the line, but the cache never answers it, because after every fill it looks up whatever is presented *now*. Responses carry the address they answer (`raddr`), so fetch drops a hit for a wrong-path request. Stale wrong-path responses therefore cannot reach the core, and the old replay/flush plumbing is gone.
- **Simple control:** one global stall (the memory stage waiting on a cache miss or the M unit) freezes the pipe in place, with no replay. A load-use or M-use hazard holds IF/ID for one cycle. Forwarding comes from EX/MEM and MEM/WB, and the register file bypasses same-cycle writes. ID/EX refreshes its operands from the forwarding network while frozen.
- **Branches:** predicted taken (target adder in fetch); JAL is always taken. A not-taken branch is redirected by execute to its own `pc + 4`: the not-taken PC travels with the branch in ID/EX, so no separate buffer is needed. After a JALR, fetch stops requesting until execute supplies the target, so there are no wrong-path cache reads.
- **Low power:** SRAMs are chip-selected only on an actual read or write. Fetch does not request while the pipeline is frozen or waiting for a JALR target. One cache array serves both instructions and data.
- **M Extension:** `hdl/m_unit.sv` executes MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU. An M op starts when it leaves EX and completes in MEM; the pipeline stalls until it is done.

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
py tools/xsim/run_xsim.py ooo prog.elf --magic              # magic memory: no DRAM timing

# shared benchmark list on both cores, with commit-log cross-check
py tools/xsim/run_regress.py
py tools/xsim/run_regress.py --magic         # same, with magic memory
```

Vivado is found through `XILINX_VIVADO`, `PATH`, or the standard install
locations, or you can pass `--vivado <dir>`. Build output goes to `<core>/xsim/`
(git-ignored):
`run/simulation.log`, `spike/commit.log` (Spike `--log-commits` format), and
`logs/<bench>.*` from the regression.

`--magic` (testbench define `ECE411_MAGIC_MEM`) replaces the DRAM model with
`hvl/common/magic_dram_w_burst.sv`, the banked-interface version of the old
pipeline testbench's `MAGIC` memory option. It is always ready, returns the
first beat the cycle after a request, and has no DRAM timing. The cores'
caches stay in the path, so cold and conflict misses still pay their short
fill handshake; the model prints the number of line reads and writes at the
end of the run. Magic builds go to `<core>/xsim_magic/`.

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
| `m_ext_test` (1,939 M-ops) | 0.253 | 0.145 | identical |
| `coremark_rv32i` | 0.474 | 0.630 | identical |
| `coremark_im` | 0.594 | 0.481 | identical |
| `aes_sha` | 0.366 | 0.202 | identical |
| `compression` | 0.820 | 0.508 | identical |
| `fft` | 0.678 | 0.453 | identical |
| `mergesort` | 0.599 | 0.431 | identical |

Both cores use the same DRAM model, but with different clock periods (OoO
1.4 ns, pipeline 2 ns). The DRAM timings are in ns, so a miss costs the OoO
core more cycles, and IPC is not directly comparable across the two columns.
The pipeline runs the low-power memory configuration: one 2 KB direct-mapped
cache shared by instructions and data. Code/data conflicts in that cache are
the main cost on `aes_sha`.

With magic memory (`run_regress.py --magic`), IPC and cache line fills per
1000 instructions:

| Benchmark | OoO IPC (DRAM -> magic) | Pipeline IPC (DRAM -> magic) | OoO fills/1k inst | Pipeline fills/1k inst |
|---|---|---|---|---|
| `coremark_rv32i` | 0.474 -> 0.488 | 0.630 -> 0.686 | - | - |
| `coremark_im` | 0.594 -> 0.664 | 0.481 -> 0.546 | 17.9 | 18.9 |
| `aes_sha` | 0.366 -> 0.568 | 0.202 -> 0.361 | 89.3 | 126.5 |
| `compression` | 0.820 -> 0.827 | 0.508 -> 0.605 | 1.9 | 18.2 |
| `fft` | 0.678 -> 0.696 | 0.453 -> 0.567 | 3.0 | 16.5 |
| `mergesort` | 0.599 -> 0.618 | 0.431 -> 0.537 | 5.2 | 21.9 |

Tools in `tools/xsim/`:

| Script | Purpose |
|---|---|
| `run_xsim.py` | compile, elaborate, and run one core/program; `--tcl` runs a custom xsim probe script, `-D`/`--extra-src` add defines and sources |
| `run_regress.py` | run the benchmark list on both cores and compare commit logs |
| `elf2mem.py` | ELF to `$readmemh` image (256-bit lines for the banked DRAM model both cores use; `--word-bytes` for other memories) |
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
