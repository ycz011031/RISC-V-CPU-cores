module decode
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    input   logic   [31:0]  inst,
    input   logic   [31:0]  PC_cache,
    input   logic   [31:0]  PC_cur,
    input   logic           fetch_rdy,

    output  logic   [2:0]   funct3,
    output  logic   [6:0]   funct7,
    output  logic   [6:0]   opcode,
    output  logic   [4:0]   rs1_s,
    output  logic   [4:0]   rs2_s,
    output  logic   [4:0]   rd_s,
    output  logic   [31:0]  PC_cur_de,
    output  logic   [31:0]  PC_next_de,

    input   logic   [31:0]  rs1_v,
    input   logic   [31:0]  rs2_v,

    input   logic           br_flush,
    input   logic           mm_stall,

    output  logic   [31:0]  rs1_v_sync,
    output  logic   [31:0]  rs2_v_sync,
    output  logic   [4:0]   rs1_s_sync,
    output  logic   [4:0]   rs2_s_sync,
    output  logic   [31:0]  imm_sync,

    output  logic   [31:0]  MM_addr_sync,

    output  logic           decode_rdy
);


    logic [31:0]  i_imm;
    logic [31:0]  s_imm;
    logic [31:0]  b_imm;
    logic [31:0]  u_imm;
    logic [31:0]  j_imm;
    logic [6:0]   opcode_async;
    logic [2:0]   funct3_async;
    logic [31:0]  MM_addr_async_s;
    logic [31:0]  MM_addr_async_l;
     
    assign rs1_s = inst[19:15];
    assign rs2_s = inst[24:20];
    assign opcode_async = inst[6:0];
    assign funct3_async = inst[14:12];

    assign i_imm  = {{21{inst[31]}}, inst[30:20]};
    assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign u_imm  = {inst[31:12], 12'h000};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    
    assign MM_addr_async_s = s_imm + rs1_v;
    assign MM_addr_async_l = i_imm + rs1_v;
    
    
    always_ff @(posedge clk)begin
        if (rst) begin
            opcode <= '0;
            funct3 <= '0;
            funct7 <= '0;
            rd_s   <= '0;
            rs1_v_sync <= '0;
            rs2_v_sync <= '0;
            imm_sync   <= '0;
            decode_rdy <= '0;
        end else if (fetch_rdy) begin    
            decode_rdy   <= (~br_flush)&(~mm_stall);
            opcode       <= inst[6:0];
            funct3       <= inst[14:12];
            funct7       <= inst[31:25];
            rd_s         <= inst[11:7];
            rs1_v_sync   <= rs1_v;
            rs2_v_sync   <= rs2_v;
            PC_cur_de    <= PC_cache;
            PC_next_de   <= PC_cur;
            rs1_s_sync   <= inst[19:15];
            if (inst[6:0] == op_b_store || inst[6:0]==op_b_reg || inst[6:0]==op_b_br) rs2_s_sync   <= inst[24:20];
            else rs2_s_sync <= '0;
            if (opcode_async == op_b_store) begin
                MM_addr_sync <= MM_addr_async_s;
            end else begin
                MM_addr_sync <= MM_addr_async_l;
            end

            unique case(opcode_async)
                op_b_lui    : imm_sync <= u_imm;
                op_b_auipc  : imm_sync <= u_imm;
                op_b_jal    : imm_sync <= j_imm;
                op_b_jalr   : imm_sync <= i_imm;
                op_b_br     : imm_sync <= b_imm;
                op_b_load   : imm_sync <= i_imm;
                op_b_store  : imm_sync <= s_imm;
                op_b_imm    : imm_sync <= i_imm;
                op_b_reg    : imm_sync <= '0;
                default     : imm_sync <= '0;
            endcase
        end else decode_rdy <= '0;
    end 
      




endmodule : decode