# RISC-V CPU Cores Project

This repository contains implementations of RISC-V CPU cores: a 5-stage pipelined processor (originally RV32I, now RV32IM) and an out-of-order RV32IM processor. These designs are part of the ECE 411 coursework and demonstrate advanced computer architecture concepts.

Both cores are plain, vendor-neutral RTL by default. Synopsys DesignWare IP is optional (`USE_SYNOPSYS_DW`). Both cores simulate on **Vivado xsim** and run the same RV32IM benchmarks. See [Vendor-neutral RTL and xsim flow](#vendor-neutral-rtl-and-xsim-flow).

## RV32I Pipeline

### Overview
The RV32I Pipeline folder contains the implementation of a 5-stage pipelined processor compliant with the RV32I instruction set architecture (ISA), extended with the **M extension** (RV32IM; the folder keeps its original name). The design excludes the `FENCE*`, `ECALL`, `EBREAK`, and `CSRR*` instructions. The processor supports naturally aligned loads and stores and resolves all hazards without unnecessary stalls.

### Key Features
- **5-Stage Pipeline:** Fetch, Decode, Execute, Memory, Writeback (`hdl/core.sv`). Stages are connected by packed structs from `pkg/types.sv`, in the same style as the out-of-order core: `if_id_stage_reg_t`, `id_ex_stage_reg_t`, `ex_mem_stage_reg_t`, `mem_wb_stage_reg_t`, `redirect_t`, `fwd_operands_t`, `mem_req_t` / `mem_rsp_t`, and an `rvfi_entry` commit port.
- **Memory system (low-power configuration):** `hdl/cpu.sv` = core, then `arbiter`, then one **shared 2 KB direct-mapped write-back cache** (`ip/pcache.sv` with `WAYS=1, SETS=64`: pipelined, so hits stream one per cycle; a 32-line fully associative victim cache), then the OoO core's `dram_adapter`. The top-level ports are the same banked DRAM interface as the out-of-order core, so both run on the same testbench memory model. The arbiter gives data accesses priority over instruction fetch.
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
- **Branch prediction:** gshare (4K x 2-bit PHT, 12-bit global history; `+define+OOO_PHT_BITS=n`), an 8-entry return address stack repaired from a commit-time copy on every flush, and `auipc ra` + `jalr ra` call targets computed in fetch. Mispredicts are recovered when the branch commits.
- **Fetch line buffer:** `hdl/line_buf_superscalar.sv` holds `ENTRIES` lines (3; `+define+OOO_LB_ENTRIES=n`) with LRU replacement. When the I-cache port is idle it prefetches the line after the one being fetched, and a cache response for the line fetch is waiting on goes straight to the fetch slots in the response cycle (`+define+OOO_LB_NO_BYPASS` to disable). Before, every move to a new line cost 2 cycles even on an I-cache hit. Against that (2 entries): `coremark_rv32i` +17.6% IPC, `compression` +10.8%, `coremark_im` +9.1%, `mergesort` +7.3%, `aes_sha` +3.1%. The third entry adds `compression` +14.1% (magic +18.2%), `coremark_rv32i` / `mergesort` +0.9%. For timing, the allocation logic does not wait for the next-PC mux: the prefetch victim is chosen from registered state only (the LRU entry that is neither `pc`'s line nor the line filled last; it can take the line `pc_next` lands on, which fetch then requests again: 1.1% of cycles on `coremark_im`, under 0.2% elsewhere; `+define+OOO_LB_NX_VICTIM` restores the exact rule), and fetch passes every next-PC candidate (pc, pc+4, pc+8, flush targets, predicted targets) with a select code, so their lines are compared with the tags in parallel. Without the bypass: `coremark_rv32i` -3.2%, `coremark_im` / `mergesort` -1.2%. This replaces `prefechter_nl`, which only warmed the I-cache after a miss.
- **Fetch groups:** a group holds at most one control-flow instruction, in either slot (slot 2 may hold a branch or `jal`, predicted from a second copy of the gshare table; `+define+OOO_NO_SLOT2_CTRL` restores the slot-1-only rule), and slot 2 reads word 0 of the next line when that line is already in the line buffer. Against slot-1-only fetch: `coremark_rv32i` +3.7% IPC, `compression` +2.6%, `coremark_im` -1.1% (more mispredicts: the then 256-entry table saw a different history pattern), the rest unchanged.
- **Multipliers:** three copies of the sequential 5-cycle multiplier (`func_mul` `NUM_MUL`, set by `MUL_UNITS` in `cpu.sv` or `+define+OOO_MUL_UNITS=n`) work in parallel and share one CDB port. Against a single unit: `fft` +7.0% IPC, `coremark_im` +0.6%, the rest unchanged (two units already give `fft` +6.0%).
- **Window:** 64-entry ROB and 64 rename registers (`PADDR_L` = `ROBADDR_L` = 6 in `cpu.sv` and `pkg/types.sv`; `+define+OOO_WIN_BITS=n`). With the 4K predictor, against a 32-entry window and a 256-entry table (DRAM IPC): `fft` +15.2%, `coremark_rv32i` +10.5%, `mergesort` +5.8%, `coremark_im` +3.6%, `aes_sha` +0.7%, `compression` -3.4% (its memory station became the wall, fixed by the store split below).
- **Memory ordering:** the memory station issues in order, and a store issues once its address is ready; its data comes later from the CDB into the store queue, which drains a store only after it commits and has its data. A load waits for an older store only when they share a byte of the same word (there is no store-to-load forwarding), and the load queue sends the oldest ready load to the D-cache (`+define+OOO_LQ_NO_AGE`: highest ready index). Load and store queues: 4 entries (`MEM_DEPTH` in `cpu.sv` and `pkg/types.sv`, which sizes `depend_idx`; `+define+OOO_MEM_DEPTH=n`, 8 gives the same IPC). `+define+OOO_NO_STORE_SPLIT` makes a store wait for its data again. Against waiting for the data (DRAM IPC): `compression` +29.3%, `aes_sha` +20.0%, `fft` +4.1%, `coremark_im` +3.3%, `mergesort` +1.4%, `coremark_rv32i` +0.6%. The earlier dependence check compared a store's word address with a load's byte address, so a byte or halfword load at offset 1-3 did not wait for an older store to the same word.
- **D-cache access stream:** `mem_queue_out_controller` presents the next access in the response cycle of the current one (the store after the store-queue head, or a load other than the one being answered; stores first), and the D-cache accepts it (`ACCEPT_ON_RESP = 1`), so hits stream one per cycle instead of one every two (`+define+OOO_DCACHE_NO_PIPE` restores the old rate). DRAM IPC: `fft` +7.4%, `aes_sha` +6.1% (magic +11.7%), `mergesort` +3.8%, `coremark_im` +3.4%, `coremark_rv32i` +1.4%. `+define+OOO_ICACHE_SETS=n` sets the I-cache size (16 sets = 2 KB).
- **Timing** (Vivado 2025.1 out-of-context synthesis, xcku5p, all OpenRAM models as flip-flops): worst path 5.76 ns at commit 918675d, 6.51 ns now (I-cache hit -> response bypass -> fetch predecode -> branch target -> line-buffer next-line compare -> demand tag write; the second gshare table's index is formed per next-PC candidate, 6.31 ns); LUTs 46.1K -> 68.2K, flip-flops 53.0K -> 59.5K. Without the bypass the worst path starts at the ROB flush instead. The new caches model their SRAM as a registered address and a flip-flop read, which maps differently from the old OpenRAM macro.
- **Configurable Parameters:** Allows customization of clock period, extensions, and memory behavior via `options.json`.
- **Caches:** 2 KB 4-way I-cache (32 B line port, read-only) and 2 KB 4-way write-back D-cache (one hit per cycle), both `ip/pcache.sv` with a 32-line victim cache. The DRAM-side `arbiter_pro` issues the I and D misses in arrival order (FCFS); its next-line prefetch goes last.
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

### Cache IP (`ip/pcache.sv`, `ip/cache_sram.sv`)
All three caches (OoO I and D, pipeline shared) are one parameterized module:

| Parameter | Meaning | OoO I | OoO D | Pipeline |
|---|---|---|---|---|
| `WAYS`, `SETS` | geometry (32 B lines) | 4, 16 | 4, 16 | 1, 64 |
| `UFP_BYTES` | upward port width: 4 (word) or 32 (line) | 32 | 4 | 4 |
| `WRITABLE` | write-back, write-allocate; 0 = read-only | 0 | 1 | 1 |
| `VC_ENTRIES` | fully associative victim cache lines (0 = none) | 32 | 32 | 32 |
| `ACCEPT_ON_RESP` | accept the next request in the hit-response cycle | 0 | 1 | 1 |
| `ID_W` | sideband id returned with the response | - | - | 1 (I/D source) |

* **Pipelined:** a request is accepted and the tag/data SRAMs are read; the
  next cycle compares and answers a hit. With `ACCEPT_ON_RESP = 1` a new
  request is accepted in that same cycle, so hits stream one per cycle. That
  needs the requester to present its *next* request in the response cycle,
  as the pipeline core's fetch and memory stage and the OoO memory queue do.
  OoO fetch keeps showing the answered request through the response cycle, so
  the I-cache uses `0`: one hit every two cycles, as with the old caches.
* **Store hits** go to a one-line write buffer that is written into the data
  SRAM in the next cycle the port is free; later reads of that line are
  forwarded from it. A store that hits a different line while the buffer is
  full costs one cycle.
* **Blocking misses**, at most one per cache. The victim way is an invalid
  way, or else the tree pseudo-LRU way. A main-array miss that hits the
  victim cache swaps the two lines (no DRAM access). Otherwise the line is
  read from DRAM and the victim moves into the victim cache (FIFO,
  exclusive), whose displaced line is written back first if dirty. After a
  refill the cache looks up whatever is presented *now* (hold-until-response).
* `cache_sram` is a behavioral single-port SRAM (vendor neutral). With
  `` `define USE_OPENRAM_SRAM`` the geometries that have an OpenRAM macro
  (`mp_cache_*`, `dm_cache_*` in `<core>/sram/output`) use it instead. The OoO
  `sim/Makefile` (Synopsys flow) defines it; xsim does not.
* `+define+PCACHE_VC_ENTRIES=n` overrides the victim-cache size in both
  `cpu.sv` files (for experiments).

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

Regression results (Vivado 2025.1 xsim, generic `ip/` operators and caches,
segment IPC). Every benchmark passes the RVFI monitor on both cores, and both
cores retire bit-identical commit logs:

| Benchmark | OoO IPC | Pipeline IPC | OoO IPC, magic | Pipeline IPC, magic | Commit logs |
|---|---|---|---|---|---|
| `m_ext_test` (1,939 M-ops) | 0.252 | 0.147 | 0.296 | 0.181 | identical |
| `coremark_rv32i` | 0.701 | 0.692 | 0.719 | 0.709 | identical |
| `coremark_im` | 0.772 | 0.552 | 0.829 | 0.578 | identical |
| `aes_sha` | 0.783 | 0.297 | 0.998 | 0.430 | identical |
| `compression` | 1.527 | 0.679 | 1.586 | 0.684 | identical |
| `fft` | 1.039 | 0.610 | 1.084 | 0.623 | identical |
| `mergesort` | 0.838 | 0.591 | 0.867 | 0.605 | identical |

Both cores use the same DRAM model, but with different clock periods (OoO
1.4 ns, pipeline 2 ns). The DRAM timings are in ns, so a miss costs the OoO
core more cycles, and IPC is not directly comparable across the two columns.
"Magic" is `run_regress.py --magic` (see above): the caches stay, DRAM timing goes.

Effect of the cache rework (`ip/pcache.sv`), DRAM IPC: previous caches ->
pcache without victim cache (`-D PCACHE_VC_ENTRIES=0`) -> pcache with the
32-line victim cache (default), and DRAM line fills per 1000 instructions
without -> with the victim cache:

| Benchmark | OoO IPC | OoO fills/1k (I+D) | Pipeline IPC | Pipeline fills/1k |
|---|---|---|---|---|
| `coremark_rv32i` | 0.474 -> 0.473 -> 0.476 | 4.3 -> 2.1 | 0.630 -> 0.633 -> 0.692 | 8.8 -> 2.4 |
| `coremark_im` | 0.594 -> 0.593 -> 0.626 | 11.2 -> 5.0 | 0.481 -> 0.486 -> 0.552 | 18.9 -> 5.9 |
| `aes_sha` | 0.366 -> 0.358 -> 0.506 | 63.5 -> 16.3 | 0.202 -> 0.205 -> 0.297 | 128.4 -> 65.4 |
| `compression` | 0.820 -> 0.820 -> 0.820 | 0.7 -> 0.7 | 0.508 -> 0.533 -> 0.679 | 17.1 -> 0.7 |
| `fft` | 0.677 -> 0.678 -> 0.680 | 2.5 -> 2.0 | 0.453 -> 0.468 -> 0.610 | 16.3 -> 2.6 |
| `mergesort` | 0.599 -> 0.599 -> 0.604 | 3.1 -> 2.3 | 0.431 -> 0.450 -> 0.591 | 19.9 -> 3.0 |

* **Pipelining** shows in the pipeline column only (previous -> no victim
  cache, up to +5%). The old shared cache already streamed read hits; what is
  new is store hits through the write buffer. The OoO requesters could not
  issue back to back then (the OoO D-cache now does, see the key features).
* **The victim cache** removes most conflict misses of the direct-mapped
  shared cache (68-96% of its misses hit the victim cache on CoreMark,
  compression, fft and mergesort). On the OoO core it matters where the 4-way
  caches thrash: `aes_sha` (I-cache) and `coremark_im`.
* **FCFS** at the OoO DRAM arbiter gave the same IPC as fixed I-first priority
  (A/B on `aes_sha`): the two caches' misses rarely overlap.
* `aes_sha` without a victim cache is 2% below the old OoO caches: the I-cache
  spends more cycles waiting on DRAM, most likely because of a different
  replacement order on a thrashing footprint.

Branch prediction fixes in the OoO core, IPC before -> after (DRAM / magic),
and mispredicts per committed jalr and conditional branch:

| Benchmark | OoO IPC, DRAM | OoO IPC, magic | jalr mispredicts | branch mispredict rate |
|---|---|---|---|---|
| `coremark_rv32i` | 0.476 -> 0.489 | 0.484 -> 0.498 | 11,019 -> 0 of 21,284 | 23.2% -> 25.4% |
| `coremark_im` | 0.626 -> 0.636 | 0.667 -> 0.675 | 497 -> 0 of 2,492 | 7.9% -> 8.6% |
| `aes_sha` | 0.505 -> 0.591 | 0.594 -> 0.697 | 11,550 -> 0 of 13,146 | 13.4% -> 2.8% |
| `compression` | 0.820 -> 0.932 | 0.827 -> 0.934 | 0 of 1 | 8.3% -> 0.0% |
| `fft` | 0.680 -> 0.750 | 0.698 -> 0.771 | 5,837 -> 8 of 8,184 | 23.8% -> 5.1% |
| `mergesort` | 0.604 -> 0.692 | 0.620 -> 0.713 | 6,149 -> 8 of 8,184 | 23.1% -> 19.0% |

* **Return address stack** (`hdl/RAS.sv`): the stack read the slot above its
  top, so returns were predicted wrong, and nothing repaired it after a flush.
  It now keeps a speculative copy (updated in fetch) and a committed copy
  (updated at commit from the ROB, the FTQ and the PRF commit read); a flush
  copies the committed stack into the speculative one. Push/pop follow the
  RISC-V link-register hints (x1/x5).
* **Calls** compiled as `auipc ra` + `jalr ra` were predicted only when the
  `auipc` was in fetch lane 1 and fetch did not stall; both lanes and stalls
  are handled now.
* **gshare history** did not shift (`{ghr[6:1], pred}` is 7 bits wide), was
  reset by the commit-time flush latch, and a jalr flush flipped a history bit
  it never added. With the intended 8-bit history the 256-entry table aliases on
  CoreMark (+2 points there); a trace model of the commit logs puts a
  1024-entry table with 10-bit history below the old rate on every benchmark.

Tools in `tools/xsim/`:

| Script | Purpose |
|---|---|
| `run_xsim.py` | compile, elaborate, and run one core/program; `--tcl` runs a custom xsim probe script, `-D`/`--extra-src` add defines and sources |
| `run_regress.py` | run the benchmark list on both cores and compare commit logs; `--magic`, `--build <dir>` for variants (extra `run_xsim.py` args after `--`) |
| `perf_report.py` | collect the perf-probe counters of all regression builds into `perf_rows.json` |
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
