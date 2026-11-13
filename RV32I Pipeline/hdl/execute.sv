// ============================================================================
// execute : ALU, branch / JALR resolution, address generation, EX/MEM register
// ============================================================================
//
// Redirect (only when the instruction actually leaves EX, i.e. !mem_stall):
//   * branch predicted taken but not taken -> pc + 4 (its not-taken PC)
//   * JALR                                -> (rs1 + imm) & ~1
// The redirect flushes IF/ID and the fetch in flight.
//
// ex_req is the data-cache request of a load/store in EX. The memory stage
// presents it to the cache already in this cycle, so a hit returns in the next
// cycle when the instruction is in MEM.
// ============================================================================

module execute
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    input   id_ex_stage_reg_t   id_ex,
    input   fwd_operands_t      operands,
    input   logic               mem_stall,

    output  redirect_t          redirect,
    output  mem_req_t           ex_req,
    output  ex_mem_stage_reg_t  ex_mem
);

    logic   [31:0]  rs1_v, rs2_v, imm, pc;
    logic   [2:0]   funct3;
    logic           is_load, is_store, is_m;

    assign rs1_v    = operands.rs1_v;
    assign rs2_v    = operands.rs2_v;
    assign imm      = id_ex.imm;
    assign pc       = id_ex.pc;
    assign funct3   = id_ex.funct3;
    assign is_load  = id_ex.opcode == op_b_load;
    assign is_store = id_ex.opcode == op_b_store;
    assign is_m     = id_ex.opcode == op_b_reg && id_ex.funct7 == muldiv;

    // ---- ALU ----------------------------------------------------------------
    function automatic logic [31:0] alu(input logic [2:0] f3, input logic alt,
                                        input logic [31:0] a, input logic [31:0] b);
        unique case (f3)
            arith_f3_add  : return alt ? a - b : a + b;
            arith_f3_sll  : return a << b[4:0];
            arith_f3_slt  : return {31'd0, signed'(a) < signed'(b)};
            arith_f3_sltu : return {31'd0, a < b};
            arith_f3_xor  : return a ^ b;
            arith_f3_sr   : return alt ? unsigned'(signed'(a) >>> b[4:0]) : a >> b[4:0];
            arith_f3_or   : return a | b;
            arith_f3_and  : return a & b;
            default       : return '0;
        endcase
    endfunction

    logic   [31:0]  rd_v;
    logic   [31:0]  pc_plus4;
    logic           br_taken;
    logic   [31:0]  jalr_target;
    logic   [31:0]  pc_wdata;
    logic   [31:0]  addr;

    always_comb begin
        pc_plus4    = pc + 32'd4;
        jalr_target = (rs1_v + imm) & ~32'd1;

        unique case (funct3)
            branch_f3_beq  : br_taken = (rs1_v == rs2_v);
            branch_f3_bne  : br_taken = (rs1_v != rs2_v);
            branch_f3_blt  : br_taken = (signed'(rs1_v) <  signed'(rs2_v));
            branch_f3_bge  : br_taken = (signed'(rs1_v) >= signed'(rs2_v));
            branch_f3_bltu : br_taken = (rs1_v <  rs2_v);
            branch_f3_bgeu : br_taken = (rs1_v >= rs2_v);
            default        : br_taken = 1'b0;
        endcase

        unique case (id_ex.opcode)
            op_b_lui   : rd_v = imm;
            op_b_auipc : rd_v = pc + imm;
            op_b_jal,
            op_b_jalr  : rd_v = pc_plus4;
            op_b_imm   : rd_v = alu(funct3, funct3 == arith_f3_sr && id_ex.funct7[5], rs1_v, imm);
            op_b_reg   : rd_v = alu(funct3, id_ex.funct7[5], rs1_v, rs2_v);  // M ops: from m_unit
            default    : rd_v = '0;
        endcase

        unique case (id_ex.opcode)
            op_b_br   : pc_wdata = br_taken ? pc + imm : pc_plus4;
            op_b_jal  : pc_wdata = pc + imm;
            op_b_jalr : pc_wdata = jalr_target;
            default   : pc_wdata = pc_plus4;
        endcase

        // redirect: fetch predicted every branch taken and stopped after a JALR
        redirect.valid  = id_ex.valid && !mem_stall &&
                          ((id_ex.opcode == op_b_br && !br_taken) || id_ex.opcode == op_b_jalr);
        redirect.target = (id_ex.opcode == op_b_jalr) ? jalr_target : pc_plus4;

        // data-cache request
        addr   = rs1_v + imm;
        ex_req = '0;
        ex_req.addr = {addr[31:2], 2'b00};
        if (id_ex.valid && is_load) begin
            unique case (funct3)
                load_f3_lb, load_f3_lbu : ex_req.rmask = 4'b0001 << addr[1:0];
                load_f3_lh, load_f3_lhu : ex_req.rmask = 4'b0011 << addr[1:0];
                default                 : ex_req.rmask = 4'b1111;
            endcase
        end
        if (id_ex.valid && is_store) begin
            unique case (funct3)
                store_f3_sb : begin ex_req.wmask = 4'b0001 << addr[1:0]; ex_req.wdata = {4{rs2_v[7:0]}};  end
                store_f3_sh : begin ex_req.wmask = 4'b0011 << addr[1:0]; ex_req.wdata = {2{rs2_v[15:0]}}; end
                default     : begin ex_req.wmask = 4'b1111;              ex_req.wdata = rs2_v;            end
            endcase
        end
    end

    // ---- EX/MEM register ----------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            ex_mem <= '0;
        end else if (!mem_stall) begin
            if (!id_ex.valid) begin
                ex_mem.valid <= 1'b0;
            end else begin
                ex_mem.valid    <= 1'b1;
                ex_mem.is_load  <= is_load;
                ex_mem.is_store <= is_store;
                ex_mem.is_m     <= is_m;
                ex_mem.funct3   <= funct3;
                ex_mem.addr_lo  <= addr[1:0];
                ex_mem.req      <= ex_req;
                ex_mem.rd_s     <= id_ex.rd_s;
                ex_mem.rd_v     <= rd_v;
                ex_mem.rvfi     <= '{
                    valid     : 1'b0,
                    order     : '0,
                    inst      : id_ex.inst,
                    rs1_addr  : id_ex.rs1_s,
                    rs2_addr  : id_ex.rs2_s,
                    rs1_rdata : rs1_v,
                    rs2_rdata : rs2_v,
                    rd_addr   : id_ex.rd_s,
                    rd_wdata  : '0,
                    pc_rdata  : pc,
                    pc_wdata  : pc_wdata,
                    mem_addr  : ex_req.addr,
                    mem_rmask : ex_req.rmask,
                    mem_wmask : ex_req.wmask,
                    mem_rdata : '0,
                    mem_wdata : ex_req.wdata
                };
            end
        end
    end

endmodule : execute
