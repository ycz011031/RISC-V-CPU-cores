module execute
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    input   logic   [2:0]   funct3,
    input   logic   [6:0]   funct7,
    input   logic   [6:0]   opcode,
    input   logic   [4:0]   rd_s,


    input   logic   [31:0]  PC_cur_de,
    input   logic           decode_rdy,

    input   logic   [31:0]  rs1_v_de,
    input   logic   [31:0]  rs2_v_de,
    input   logic   [31:0]  imm_sync,

    input   logic   [1:0]   rs_valid_ex,
    input   logic   [31:0]  rs1_fw_ex,
    input   logic   [31:0]  rs2_fw_ex,

    output  logic   [31:0]  jalr_target,
    output  logic           jalr_resolve,
    output  logic           br_flush,
    input   logic           mm_stall,

    output  logic   [31:0]  rd_v_ex,
    output  logic   [4:0]   rd_s_ex,
    output  logic           execute_rdy
    
);


    logic [31:0] rd_v_imm;
    logic [31:0] rd_v_reg;
    logic [31:0] rd_v_lui;
    logic [31:0] rd_v_auipc;
    
    logic [31:0] rs1_v_sync;
    logic [31:0] rs2_v_sync;

    logic  signed [31:0] rs1_signed;
    logic  signed [31:0] rs2_signed;
    logic  signed [31:0] imm_signed;
    logic unsigned [31:0] rs1_unsigned;
    logic unsigned [31:0] rs2_unsigned;
    logic unsigned [31:0] imm_unsigned;

    logic [31:0] jalr_target_reg;


    assign rs1_signed = signed'(rs1_v_sync);
    assign rs2_signed = signed'(rs2_v_sync);
    assign imm_signed = signed'(imm_sync);
    assign rs1_unsigned = unsigned'(rs1_v_sync);
    assign rs2_unsigned = unsigned'(rs2_v_sync);
    assign imm_unsigned = unsigned'(imm_sync);


    always_comb begin
        rs1_v_sync = rs_valid_ex[0] ? rs1_fw_ex : rs1_v_de;
        rs2_v_sync = rs_valid_ex[1] ? rs2_fw_ex : rs2_v_de;
    end

    //RI operations
    always_comb begin
        //alu
        unique case (funct3)
                arith_f3_add  : rd_v_imm = rs1_v_sync + imm_sync;                
                arith_f3_xor  : rd_v_imm = rs1_v_sync ^ imm_sync;
                arith_f3_or   : rd_v_imm = rs1_v_sync | imm_sync;
                arith_f3_and  : rd_v_imm = rs1_v_sync & imm_sync;
                arith_f3_slt  : rd_v_imm = {31'd0,(rs1_signed < imm_signed)};
                arith_f3_sltu : rd_v_imm = {31'd0,(rs1_unsigned < imm_unsigned)};
                arith_f3_sll  : rd_v_imm = rs1_v_sync << imm_sync[4:0];
                arith_f3_sr   : begin
                    if (funct7[5]) begin
                        rd_v_imm = unsigned'(rs1_signed >>> imm_unsigned[4:0]);
                    end else begin
                        rd_v_imm = rs1_unsigned >> imm_unsigned[4:0];
                    end
                end    
                default   : rd_v_imm = '0;
            endcase
    end


    //RR operations
    always_comb begin
        unique case (funct3)
                arith_f3_add   : begin
                    if (funct7[5]) begin
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
                    if (funct7[5]) begin
                        rd_v_reg = unsigned'(rs1_signed >>> rs2_unsigned[4:0]);
                    end else begin
                        rd_v_reg = rs1_unsigned >> rs2_unsigned[4:0];
                    end
                end    
                default   : rd_v_reg = '0;
        endcase
    end

    // BR resolution
    logic br_en;
    always_comb begin
        unique case (funct3)
            branch_f3_beq : br_en = (rs1_unsigned == rs2_unsigned);
            branch_f3_bne : br_en = (rs1_unsigned != rs2_unsigned);
            branch_f3_blt : br_en = (rs1_signed   <  rs2_signed);
            branch_f3_bge : br_en = (rs1_signed   >= rs2_signed);
            branch_f3_bltu: br_en = (rs1_unsigned <  rs2_unsigned);
            branch_f3_bgeu: br_en = (rs1_unsigned >= rs2_unsigned);
            default       : br_en = '0;
        endcase
        if (opcode == op_b_br && br_en == '0 && decode_rdy) br_flush = '1;
        else br_flush = '0;

    end
    
    //JALR Address
    logic [31:0] JALR_address;
    assign JALR_address = rs1_v_sync + imm_sync;

    always_comb begin
        if (decode_rdy && (opcode == op_b_jalr))begin
            jalr_resolve = '1;
            jalr_target  = {JALR_address[31:2],2'b00};
        end else begin
            jalr_resolve = '0;
            jalr_target = jalr_target_reg;
        end
    end


    // LUI and AUIPC operations
    always_comb begin
        rd_v_lui   = imm_sync;
        rd_v_auipc = imm_sync + PC_cur_de;
    end    


    always_ff @ (posedge clk) begin
        if (rst) begin
            execute_rdy <= '0;
            rd_v_ex     <= '0;
            rd_s_ex     <= '0;
            jalr_target_reg <= '0;
        end else if(decode_rdy) begin  


            if (opcode == op_b_jalr) begin
                jalr_target_reg  <= {JALR_address[31:2],2'b00};
            end

            unique case (opcode)
                op_b_lui    : rd_v_ex  <= rd_v_lui;
                op_b_auipc  : rd_v_ex  <= rd_v_auipc;
                op_b_jal    : rd_v_ex  <= PC_cur_de+4;
                op_b_jalr   : rd_v_ex  <= PC_cur_de+4;
                op_b_br     : rd_v_ex  <= '0;
                op_b_load   : rd_v_ex  <= '0;
                op_b_store  : rd_v_ex  <= '0;
                op_b_imm    : rd_v_ex  <= rd_v_imm;
                op_b_reg    : rd_v_ex  <= rd_v_reg;
                default     : rd_v_ex  <= '0;
            endcase
            if (opcode == op_b_br | opcode == op_b_store) rd_s_ex <= '0;
            else rd_s_ex   <= rd_s;
            execute_rdy <= (~mm_stall);
        end else begin
            execute_rdy <= '0;
        end
    end            




endmodule : execute


