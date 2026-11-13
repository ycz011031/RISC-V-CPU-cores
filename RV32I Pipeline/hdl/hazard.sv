// ============================================================================
// hazard_handler : operand forwarding into EX, load-use / M-use detection
// ============================================================================
//
// Forwarding sources, youngest first: EX/MEM (ALU result of the instruction in
// MEM; not for loads / M ops, whose result only exists at the end of MEM),
// then MEM/WB. Older values come from the register file, which bypasses a
// same-cycle write to the decode read port.
//
// load_use: the instruction in IF/ID reads the destination of a load or M op
// in ID/EX. Hold IF/ID for one cycle; the value is then forwarded from MEM/WB.
// ============================================================================

module hazard_handler
import rv32i_types::*;
(
    input   id_ex_stage_reg_t   id_ex,
    input   ex_mem_stage_reg_t  ex_mem,
    input   mem_wb_stage_reg_t  mem_wb,

    input   logic               if_id_valid,
    input   logic   [4:0]       dec_rs1_s,      // sources of the instruction in IF/ID
    input   logic   [4:0]       dec_rs2_s,      // (0 when unused)

    output  fwd_operands_t      operands,
    output  logic               load_use
);

    // pure function: always_comb sensitivity is explicit
    function automatic logic [31:0] forward(
        input logic [4:0]           rs_s,
        input logic [31:0]          rs_v,
        input ex_mem_stage_reg_t    ex_mem,
        input mem_wb_stage_reg_t    mem_wb
    );
        if (rs_s == '0)
            return rs_v;
        else if (ex_mem.valid && !ex_mem.is_load && !ex_mem.is_m && ex_mem.rd_s == rs_s)
            return ex_mem.rd_v;
        else if (mem_wb.valid && mem_wb.rd_s == rs_s)
            return mem_wb.rd_v;
        else
            return rs_v;
    endfunction

    logic id_ex_late;   // ID/EX holds a load or M op (result only at the end of MEM)

    always_comb begin
        operands.rs1_v = forward(id_ex.rs1_s, id_ex.rs1_v, ex_mem, mem_wb);
        operands.rs2_v = forward(id_ex.rs2_s, id_ex.rs2_v, ex_mem, mem_wb);

        id_ex_late = id_ex.valid && id_ex.rd_s != '0 &&
                     (id_ex.opcode == op_b_load ||
                      (id_ex.opcode == op_b_reg && id_ex.funct7 == muldiv));
        load_use   = id_ex_late && if_id_valid &&
                     (dec_rs1_s == id_ex.rd_s || dec_rs2_s == id_ex.rd_s);
    end

endmodule : hazard_handler
