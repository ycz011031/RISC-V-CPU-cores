// ============================================================================
// fetch : PC, static prediction, instruction request, IF/ID register
// ============================================================================
//
// The instruction port follows the hold-until-response protocol: fetch keeps
// presenting `pc` until a response for that address arrives. The response
// carries the address it answers (raddr), so a hit for an abandoned
// (wrong-path) request is recognised and dropped. A miss for an abandoned
// request is never answered by the cache at all.
//
// Prediction: branches are predicted taken (target computed here), JAL is
// always taken, and a JALR stops fetching until execute redirects (no
// wrong-path fetches, so no wasted cache reads). A not-taken branch is
// redirected by execute to its own pc + 4 (the not-taken PC travels with it
// in the ID/EX register).
//
// Low power: fetch does not request while the memory stage holds the
// pipeline, and it never requests while waiting for a JALR target.
// ============================================================================

module fetch
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  mem_req_t           imem_req,
    input   mem_rsp_t           imem_rsp,

    input   redirect_t          redirect,       // from execute
    input   logic               mem_stall,      // backend frozen
    input   logic               decode_ready,   // decode consumes IF/ID this cycle

    output  if_id_stage_reg_t   if_id
);

    localparam logic [31:0] RESET_PC = 32'haaaaa000;

    logic   [31:0]  pc;             // address being fetched
    logic           jalr_wait;      // a JALR is in flight; wait for its target

    logic   [31:0]  pc_n;
    logic           jalr_wait_n;
    logic           take;           // capture the response into IF/ID

    logic   [31:0]  inst;
    logic   [6:0]   opcode;
    logic   [31:0]  b_imm, j_imm;
    logic   [31:0]  pc_pred;

    assign inst   = imem_rsp.rdata;
    assign opcode = inst[6:0];
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

    always_comb begin
        unique case (opcode)
            op_b_jal : pc_pred = pc + j_imm;
            op_b_br  : pc_pred = pc + b_imm;    // predict taken
            default  : pc_pred = pc + 32'd4;
        endcase

        take = imem_rsp.resp && (imem_rsp.raddr == pc) && !jalr_wait
            && (!if_id.valid || decode_ready) && !redirect.valid;

        if (redirect.valid)  pc_n = redirect.target;
        else if (take)       pc_n = pc_pred;
        else                 pc_n = pc;

        if (redirect.valid)                     jalr_wait_n = 1'b0;
        else if (take && opcode == op_b_jalr)   jalr_wait_n = 1'b1;
        else                                    jalr_wait_n = jalr_wait;

        imem_req.addr  = {pc_n[31:2], 2'b00};
        imem_req.rmask = (!jalr_wait_n && !mem_stall) ? 4'b1111 : 4'b0000;
        imem_req.wmask = '0;
        imem_req.wdata = '0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            pc        <= RESET_PC;
            jalr_wait <= 1'b0;
            if_id     <= '0;
        end else begin
            pc        <= pc_n;
            jalr_wait <= jalr_wait_n;
            if (redirect.valid) begin
                if_id.valid <= 1'b0;                    // wrong path
            end else if (take) begin
                if_id <= '{valid: 1'b1, inst: inst, pc: pc};
            end else if (decode_ready) begin
                if_id.valid <= 1'b0;                    // consumed
            end
        end
    end

endmodule : fetch
