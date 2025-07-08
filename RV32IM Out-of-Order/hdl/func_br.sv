module func_br
import rv32i_types::*;
#(
    parameter Q_INDEX = 4
)
(   
    input   RS_entry_t RS_br_out,

    input   logic   func_in_ready,
    input   logic   cdb_ready,
    output   CDB_t  cdb,
    output  logic   func_ready,

    output logic  [Q_INDEX-1:0]  funcbr_ftq_addr,
    input ftq_entry_t          to_funcbr,

    input   rvfi_entry rvfi_entry_rs_reg,
    output  rvfi_entry rvfi_entry_br
);
    logic [2:0] op_type;
    logic       br_en;
    assign op_type = RS_br_out.op_type[2:0];


    logic [31:0] rs1_v_sync;
    logic [31:0] rs2_v_sync;

    logic  signed [31:0] rs1_signed;
    logic  signed [31:0] rs2_signed;
    logic unsigned [31:0] rs1_unsigned;
    logic unsigned [31:0] rs2_unsigned;

    logic [31:0] rd_v_reg;
    logic [31:0] a,b;

    logic br_pred, br_actual;
    logic [31:0]    br_target;
    logic   br_only_taken;

    logic [31:0] jalr_target;

    logic br_target_mispred, br_mispred;

    assign br_pred = RS_br_out.br_pred;

    assign rs1_v_sync = RS_br_out.rs1_data;
    assign rs2_v_sync = RS_br_out.rs2_data;

    assign rs1_signed = signed'(rs1_v_sync);
    assign rs2_signed = signed'(rs2_v_sync);
    assign rs1_unsigned = unsigned'(rs1_v_sync);
    assign rs2_unsigned = unsigned'(rs2_v_sync);
    
    assign funcbr_ftq_addr = RS_br_out.ftq_addr;

    assign func_ready = cdb_ready;

    always_comb begin
        
        cdb.regf_we    = '1;
        br_only_taken = '0;
        jalr_target = (rs1_v_sync + rs2_v_sync) & 32'hfffffffe;;

        unique case (RS_br_out.op_type[4:3])
            2'b00  : begin //br
                a = RS_br_out.imm;      //pc
                // b = 32'd4;
                cdb.regf_we    = '0;
            end
            2'b01: begin    //jal
                a = rs1_v_sync;         //pc
                // b = 32'd4;
            end
            2'b10: begin    //jalr
                a = RS_br_out.imm;      //pc
                // b = 32'd4;
                // jalr_target = (rs1_v_sync + rs2_v_sync) & 32'hfffffffe;
            end
            default   : begin
                a='0;
                // b='0;
            end
        endcase

        rd_v_reg = a + 32'd4;   //pc + 4
        br_actual = ( RS_br_out.op_type[4:3] == 2'b00 )? br_en : 1'b1;

        br_target = ( RS_br_out.op_type[4:3] == 2'b00 )? rd_v_reg : jalr_target; // actual target either pc+4 if br or rhs if jalr
        
        cdb.rd_paddr = RS_br_out.rd_paddr;
        cdb.rd_data  = rd_v_reg;
        cdb.rob_addr = RS_br_out.rob_addr;
        cdb.valid    = func_in_ready;
        cdb.br_target = br_target;

        br_mispred = br_actual != br_pred;
        br_target_mispred = to_funcbr.br_target != br_target;

        if (RS_br_out.op_type[4:3] == 2'b10 && br_target_mispred) cdb.br_mispred = '1;
        else cdb.br_mispred = br_mispred;

        cdb.br_only_taken    = ( RS_br_out.op_type[4:3] == 2'b00 ) ? br_en : '0;
        cdb.ftq_addr = RS_br_out.ftq_addr;
        
        //RVFI
        rvfi_entry_br          = rvfi_entry_rs_reg;
        rvfi_entry_br.rd_wdata = rd_v_reg;

        if (cdb.br_mispred) begin
            rvfi_entry_br.pc_wdata =  cdb.br_only_taken? (rvfi_entry_rs_reg.pc_rdata + rvfi_entry_rs_reg.br_imm) : br_target;
        end

    end
//0.260451

    always_comb begin
        unique case (op_type)
            branch_f3_beq : br_en = (rs1_unsigned == rs2_unsigned);
            branch_f3_bne : br_en = (rs1_unsigned != rs2_unsigned);
            branch_f3_blt : br_en = (rs1_signed <  rs2_signed);
            branch_f3_bge : br_en = (rs1_signed >=  rs2_signed);
            branch_f3_bltu: br_en = (rs1_unsigned <  rs2_unsigned);
            branch_f3_bgeu: br_en = (rs1_unsigned >=  rs2_unsigned);
            default       : br_en = 1'b0;
        endcase

    end

endmodule : func_br