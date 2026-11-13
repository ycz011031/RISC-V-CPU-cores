// ============================================================================
// core : 5-stage RV32IM pipeline (fetch, decode, execute, memory, writeback)
// ============================================================================
// Instruction and data ports use the hold-until-response protocol (mem_req_t /
// mem_rsp_t, see pkg/types.sv); cpu.sv puts the arbiter and the shared cache
// behind them. Writeback is the MEM/WB register driving the register-file
// write port; it is also the commit point (rvfi).
// ============================================================================

module core
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    output  mem_req_t       imem_req,
    input   mem_rsp_t       imem_rsp,
    output  mem_req_t       dmem_req,
    input   mem_rsp_t       dmem_rsp,

    output  rvfi_entry      rvfi            // commit port
);

    if_id_stage_reg_t   if_id;
    id_ex_stage_reg_t   id_ex;
    ex_mem_stage_reg_t  ex_mem;
    mem_wb_stage_reg_t  mem_wb;
    fwd_operands_t      operands;
    redirect_t          redirect;
    mem_req_t           ex_req;

    logic               mem_stall;      // memory stage waiting: freeze the pipe
    logic               load_use;       // hold IF/ID one cycle
    logic               decode_ready;

    logic   [4:0]       rs1_s, rs2_s;
    logic   [31:0]      rs1_v, rs2_v;

    assign decode_ready = !mem_stall && !load_use;

    fetch fetch (
        .clk          (clk),
        .rst          (rst),
        .imem_req     (imem_req),
        .imem_rsp     (imem_rsp),
        .redirect     (redirect),
        .mem_stall    (mem_stall),
        .decode_ready (decode_ready),
        .if_id        (if_id)
    );

    decode decode (
        .clk          (clk),
        .rst          (rst),
        .if_id        (if_id),
        .mem_stall    (mem_stall),
        .load_use     (load_use),
        .flush        (redirect.valid),
        .operands     (operands),
        .rs1_s        (rs1_s),
        .rs2_s        (rs2_s),
        .rs1_v        (rs1_v),
        .rs2_v        (rs2_v),
        .id_ex        (id_ex)
    );

    registers registers (
        .clk          (clk),
        .rst          (rst),
        .wb           (mem_wb),
        .rs1_s        (rs1_s),
        .rs2_s        (rs2_s),
        .rs1_v        (rs1_v),
        .rs2_v        (rs2_v)
    );

    hazard_handler hazard_handler (
        .id_ex        (id_ex),
        .ex_mem       (ex_mem),
        .mem_wb       (mem_wb),
        .if_id_valid  (if_id.valid),
        .dec_rs1_s    (rs1_s),
        .dec_rs2_s    (rs2_s),
        .operands     (operands),
        .load_use     (load_use)
    );

    execute execute (
        .clk          (clk),
        .rst          (rst),
        .id_ex        (id_ex),
        .operands     (operands),
        .mem_stall    (mem_stall),
        .redirect     (redirect),
        .ex_req       (ex_req),
        .ex_mem       (ex_mem)
    );

    memory memory (
        .clk          (clk),
        .rst          (rst),
        .id_ex        (id_ex),
        .operands     (operands),
        .ex_req       (ex_req),
        .ex_mem       (ex_mem),
        .dmem_req     (dmem_req),
        .dmem_rsp     (dmem_rsp),
        .mem_stall    (mem_stall),
        .mem_wb       (mem_wb)
    );

    // ---- commit (RVFI) ----------------------------------------------------------
    logic [63:0] order_q;

    always_ff @(posedge clk) begin
        if (rst)               order_q <= '0;
        else if (mem_wb.valid) order_q <= order_q + 64'd1;
    end

    always_comb begin
        rvfi       = mem_wb.rvfi;
        rvfi.valid = mem_wb.valid;
        rvfi.order = order_q;
    end

endmodule : core
