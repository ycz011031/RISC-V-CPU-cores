// ============================================================================
// decode : instruction decode, register-file read, ID/EX register
// ============================================================================
//
// ID/EX update:
//   mem_stall           : hold, but refresh rs1/rs2 with the forwarded values
//                         (a producer may leave the forwarding window while
//                         this instruction waits)
//   redirect / load-use : insert a bubble
//   otherwise           : take the instruction in IF/ID
// ============================================================================

module decode
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    input   if_id_stage_reg_t   if_id,
    input   logic               mem_stall,
    input   logic               load_use,
    input   logic               flush,      // redirect from execute
    input   fwd_operands_t      operands,   // forwarded operands of ID/EX

    // register-file read port; addresses are 0 for unused sources
    output  logic   [4:0]       rs1_s,
    output  logic   [4:0]       rs2_s,
    input   logic   [31:0]      rs1_v,
    input   logic   [31:0]      rs2_v,

    output  id_ex_stage_reg_t   id_ex
);

    logic   [31:0]  inst;
    logic   [6:0]   opcode;
    logic           uses_rs1, uses_rs2, writes_rd;
    logic   [31:0]  imm;

    assign inst   = if_id.inst;
    assign opcode = inst[6:0];

    always_comb begin
        uses_rs1  = opcode inside {op_b_jalr, op_b_br, op_b_load, op_b_store, op_b_imm, op_b_reg};
        uses_rs2  = opcode inside {op_b_br, op_b_store, op_b_reg};
        writes_rd = !(opcode inside {op_b_br, op_b_store});

        rs1_s = uses_rs1 ? inst[19:15] : 5'd0;
        rs2_s = uses_rs2 ? inst[24:20] : 5'd0;

        unique case (opcode)
            op_b_lui, op_b_auipc : imm = {inst[31:12], 12'h000};
            op_b_jal             : imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            op_b_br              : imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            op_b_store           : imm = {{21{inst[31]}}, inst[30:25], inst[11:7]};
            op_b_jalr, op_b_load,
            op_b_imm             : imm = {{21{inst[31]}}, inst[30:20]};
            default              : imm = '0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            id_ex <= '0;
        end else if (mem_stall) begin
            id_ex.rs1_v <= operands.rs1_v;
            id_ex.rs2_v <= operands.rs2_v;
        end else if (flush || load_use || !if_id.valid) begin
            id_ex.valid <= 1'b0;
        end else begin
            id_ex <= '{
                valid  : 1'b1,
                inst   : inst,
                pc     : if_id.pc,
                opcode : opcode,
                funct3 : inst[14:12],
                funct7 : inst[31:25],
                rd_s   : writes_rd ? inst[11:7] : 5'd0,
                rs1_s  : rs1_s,
                rs2_s  : rs2_s,
                rs1_v  : rs1_v,
                rs2_v  : rs2_v,
                imm    : imm
            };
        end
    end

endmodule : decode
