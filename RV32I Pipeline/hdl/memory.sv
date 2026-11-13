// ============================================================================
// memory : data-cache access, RV32M completion, MEM/WB register
// ============================================================================
//
// Data port (hold-until-response):
//   * a load/store in MEM that has not been answered keeps presenting its
//     request (ex_mem.req);
//   * otherwise, if EX is advancing, the load/store in EX presents its request
//     early, so a cache hit is answered next cycle when it reaches MEM.
// mem_stall is high while the instruction in MEM waits for the cache (miss)
// or for m_unit. It freezes fetch / decode / execute / memory in place; MEM/WB
// receives a bubble.
//
// RV32M ops start m_unit when they leave EX and complete in MEM (m_done).
// ============================================================================

module memory
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    input   id_ex_stage_reg_t   id_ex,      // for starting M ops
    input   fwd_operands_t      operands,
    input   mem_req_t           ex_req,     // request of a load/store in EX
    input   ex_mem_stage_reg_t  ex_mem,

    output  mem_req_t           dmem_req,
    input   mem_rsp_t           dmem_rsp,

    output  logic               mem_stall,
    output  mem_wb_stage_reg_t  mem_wb
);

    // ---- RV32M ----------------------------------------------------------------
    logic           m_start, m_done;
    logic   [31:0]  m_result;

    assign m_start = id_ex.valid && !mem_stall &&
                     id_ex.opcode == op_b_reg && id_ex.funct7 == muldiv;

    m_unit m_unit (
        .clk    (clk),
        .rst    (rst),
        .start  (m_start),
        .funct3 (id_ex.funct3),
        .rs1_v  (operands.rs1_v),
        .rs2_v  (operands.rs2_v),
        .done   (m_done),
        .result (m_result)
    );

    // ---- stall / data request -------------------------------------------------
    logic   mem_ldst;
    logic   done;

    assign mem_ldst = ex_mem.valid && (ex_mem.is_load || ex_mem.is_store);

    always_comb begin
        if (!ex_mem.valid)      done = 1'b1;
        else if (mem_ldst)      done = dmem_rsp.resp;
        else if (ex_mem.is_m)   done = m_done;
        else                    done = 1'b1;
        mem_stall = !done;

        if (mem_ldst && !dmem_rsp.resp)     dmem_req = ex_mem.req;     // hold
        else if (!mem_stall)                dmem_req = ex_req;         // early issue from EX
        else                                dmem_req = '0;
    end

    // ---- load data ------------------------------------------------------------
    logic   [31:0]  rdata;
    logic   [31:0]  load_v;
    logic   [31:0]  rd_v;
    rvfi_entry      rvfi;

    assign rdata = dmem_rsp.rdata;

    always_comb begin
        unique case (ex_mem.funct3)
            load_f3_lb  : load_v = {{24{rdata[8*ex_mem.addr_lo + 7]}}, rdata[8*ex_mem.addr_lo +: 8]};
            load_f3_lbu : load_v = {24'd0,                             rdata[8*ex_mem.addr_lo +: 8]};
            load_f3_lh  : load_v = {{16{rdata[16*ex_mem.addr_lo[1] + 15]}}, rdata[16*ex_mem.addr_lo[1] +: 16]};
            load_f3_lhu : load_v = {16'd0,                                  rdata[16*ex_mem.addr_lo[1] +: 16]};
            default     : load_v = rdata;
        endcase

        if (ex_mem.is_load)     rd_v = load_v;
        else if (ex_mem.is_m)   rd_v = m_result;
        else                    rd_v = ex_mem.rd_v;

        rvfi           = ex_mem.rvfi;
        rvfi.rd_wdata  = (ex_mem.rd_s != '0) ? rd_v : '0;
        rvfi.mem_rdata = ex_mem.is_load ? rdata : '0;
    end

    // ---- MEM/WB register (commit point) ----------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_wb <= '0;
        end else if (!ex_mem.valid || mem_stall) begin
            mem_wb.valid <= 1'b0;
        end else begin
            mem_wb <= '{valid: 1'b1, rd_s: ex_mem.rd_s, rd_v: rd_v, rvfi: rvfi};
        end
    end

endmodule : memory
