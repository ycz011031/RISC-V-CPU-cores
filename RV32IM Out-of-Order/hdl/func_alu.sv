module func_alu
import rv32i_types::*;
(   
    input   RS_entry_t RS_alu_out,

    input   logic   func_in_ready,
    input   logic   cdb_ready,
    output   CDB_t  cdb,
    output  logic   func_ready,

    input   rvfi_entry rvfi_entry_rs_reg,
    output  rvfi_entry rvfi_entry_alu
);
    logic [4:0] alu_op;
    assign alu_op = RS_alu_out.op_type;


    logic [31:0] rs1_v_sync;
    logic [31:0] rs2_v_sync;

    assign rs1_v_sync = RS_alu_out.rs1_data;
    assign rs2_v_sync = RS_alu_out.rs2_data;

    logic  signed [31:0] rs1_signed;
    logic  signed [31:0] rs2_signed;
    logic unsigned [31:0] rs1_unsigned;
    logic unsigned [31:0] rs2_unsigned;

    assign rs1_signed = signed'(rs1_v_sync);
    assign rs2_signed = signed'(rs2_v_sync);
    assign rs1_unsigned = unsigned'(rs1_v_sync);
    assign rs2_unsigned = unsigned'(rs2_v_sync);


    assign func_ready = cdb_ready;

    logic [31:0] rd_v_reg;

        //RR operations
    always_comb begin
        unique case (alu_op[2:0])
                arith_f3_add   : begin
                    if (alu_op[3]&&RS_alu_out.rs2_use) begin
                        rd_v_reg = rs1_v_sync - rs2_v_sync;
                    end else begin
                        rd_v_reg = rs1_v_sync + rs2_v_sync;
                    end
                end
                arith_f3_xor  : rd_v_reg = rs1_v_sync ^ rs2_v_sync;
                arith_f3_or   : rd_v_reg = rs1_v_sync | rs2_v_sync;
                arith_f3_and  : rd_v_reg = rs1_v_sync & rs2_v_sync;
                arith_f3_slt  : rd_v_reg = {31'd0,(rs1_signed < rs2_signed)};
                arith_f3_sltu : rd_v_reg = {31'd0,(rs1_unsigned < rs2_unsigned)};
                arith_f3_sll  : rd_v_reg = rs1_v_sync << rs2_v_sync[4:0];
                arith_f3_sr   : begin
                    if (alu_op[3]) begin
                        rd_v_reg = unsigned'(rs1_signed >>> rs2_unsigned[4:0]);
                    end else begin
                        rd_v_reg = rs1_unsigned >> rs2_unsigned[4:0];
                    end
                end    
                default   : rd_v_reg = '0;
        endcase
            cdb.rd_paddr = RS_alu_out.rd_paddr;
            cdb.rd_data  = rd_v_reg;
            cdb.regf_we  = RS_alu_out.regf_we;
            cdb.rob_addr = RS_alu_out.rob_addr;
            cdb.valid    = func_in_ready;
            cdb.br_mispred= '0;
            cdb.br_target ='0;
            cdb.br_only_taken = '0;
            cdb.ftq_addr = RS_alu_out.ftq_addr;
            //RVFI
            rvfi_entry_alu          = rvfi_entry_rs_reg;
            rvfi_entry_alu.rd_wdata = rd_v_reg;      
    end

endmodule : func_alu