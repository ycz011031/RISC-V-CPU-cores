module memory
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    input   logic   [2:0]   funct3, 
    input   logic   [6:0]   funct7,
    input   logic   [6:0]   opcode,
    
    input   logic           decode_rdy,
    input   logic           execute_rdy,

    input   logic   [31:0]  imm_de,
 
    input   logic   [31:0]  rs1_v_de,
    input   logic   [31:0]  rs2_v_de,
    input   logic   [31:0]  rs1_fw_ex,
    input   logic   [31:0]  rs2_fw_ex,
    input   logic   [1:0]   rs_valid_ex,

    input   logic   [31:0]  dmem_rdata,
    input   logic           dmem_resp,

    input   logic   [31:0]  rd_v_ex,
    input   logic   [4:0]   rd_s_ex,

    input   logic           br_flush,

    output  logic   [31:0]  mem_rdata,

    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    output  logic   [31:0]  dmem_wdata,


    output  logic   [31:0]  rd_v_mm,
    output  logic   [4:0]   rd_s_mm,
    output  logic           mm_rdy,
    output  logic           mm_stall      

);




logic [2:0]  funct3_cache;
logic [6:0]  opcode_cache;
logic [31:0] addr_cache;
logic        mm_rdy_reg;
logic        resp_latch;

logic [31:0] rs2_v_sync;
logic [31:0] rs1_v_sync;

logic [31:0] MM_addr_sync;

// ---------------------------------------------------------------------------
// RV32M: MUL/DIV ops are handled like loads whose "memory" is m_unit. They
// issue in the slot where a load would issue its dmem request, then the
// memory stage waits for m_done the way it waits for dmem_resp (same
// mm_stall / replay path). resp_any merges the two response sources (only
// one op can be outstanding at a time).
// ---------------------------------------------------------------------------
logic        is_m_ex;      // M op in the execute slot (decode register)
logic        m_cache;      // M op outstanding in the memory stage
logic        m_start;
logic        m_done;
logic [31:0] m_result;
logic        resp_any;

assign is_m_ex  = (opcode == op_b_reg) && (funct7 == muldiv);
assign resp_any = dmem_resp | m_done;

//stage 1

assign rs1_v_sync = rs_valid_ex[0] ? rs1_fw_ex : rs1_v_de;
assign rs2_v_sync = rs_valid_ex[1] ? rs2_fw_ex : rs2_v_de;

assign MM_addr_sync = rs1_v_sync + imm_de;

assign m_start = decode_rdy && !br_flush && !mm_stall && is_m_ex;

m_unit m_unit (
    .clk    (clk),
    .rst    (rst),
    .start  (m_start),
    .funct3 (funct3),
    .rs1_v  (rs1_v_sync),
    .rs2_v  (rs2_v_sync),
    .done   (m_done),
    .result (m_result)
);


always_ff @ (posedge clk)begin
    if (rst) begin
        funct3_cache <= '0;
        opcode_cache <= '0;
        m_cache      <= '0;
        addr_cache   <= '0;
        resp_latch   <= '1;
    end else if (br_flush)begin
        opcode_cache <= '0;
        m_cache      <= '0;
    end else if (decode_rdy && !mm_stall) begin
        funct3_cache <= funct3;
        opcode_cache <= opcode;
        m_cache      <= is_m_ex;
        addr_cache   <= MM_addr_sync;
        if (opcode == op_b_store | opcode == op_b_load | is_m_ex)resp_latch   <= '0;
    end 
    if((resp_any|br_flush)&& !((opcode == op_b_store | opcode == op_b_load | is_m_ex)&&decode_rdy)) begin
        resp_latch   <= '1;
    end
end

always_comb begin
        if ((decode_rdy && !br_flush) && !mm_stall) begin
            unique case(opcode)
                    op_b_store : begin
                        dmem_addr  = {MM_addr_sync[31:2],2'b00};
                        dmem_rmask = '0;                
                        unique case(funct3)
                            store_f3_sb : dmem_wmask = 4'b0001 << MM_addr_sync[1:0];
                            store_f3_sh : dmem_wmask = 4'b0011 << MM_addr_sync[1:0];
                            store_f3_sw : dmem_wmask = 4'b1111;
                            default     : dmem_wmask = 4'b1111;
                        endcase
                        unique case(funct3)
                            store_f3_sb : dmem_wdata = {4{rs2_v_sync[7:0]}};
                            store_f3_sh : dmem_wdata = {2{rs2_v_sync[15:0]}};
                            store_f3_sw : dmem_wdata = rs2_v_sync;
                            default     : dmem_wdata = '1;
                        endcase
                    end
                    op_b_load : begin
                        dmem_addr  = {MM_addr_sync[31:2],2'b00};
                        dmem_wmask = '0;
                        dmem_wdata = '0;
                        unique case(funct3)
                            load_f3_lb : dmem_rmask = 4'b0001 << MM_addr_sync[1:0];
                            load_f3_lh : dmem_rmask = 4'b0011 << MM_addr_sync[1:0];
                            load_f3_lw : dmem_rmask = 4'b1111;
                            load_f3_lbu: dmem_rmask = 4'b0001 << MM_addr_sync[1:0];
                            load_f3_lhu: dmem_rmask = 4'b0011 << MM_addr_sync[1:0];
                            default    : dmem_rmask = 4'b0000;
                        endcase                
                    end
                    default   : begin
                        dmem_addr  = '0;
                        dmem_wmask = '0;
                        dmem_rmask = '0;
                        dmem_wdata = '0;
                    end
            endcase
        end else begin
            dmem_addr  = '0;
            dmem_wmask = '0;
            dmem_rmask = '0;
            dmem_wdata = '0;
        end
    end
                    
// stage 2

always_ff @ (posedge clk) begin
    if (rst) begin
        mm_rdy_reg  <= '0;
        rd_v_mm <= '0;
        rd_s_mm <= '0;
    end else if (m_cache) begin
        if(!resp_latch&&execute_rdy)rd_s_mm  <= rd_s_ex;
        if (m_done) rd_v_mm <= m_result;
        else        rd_v_mm <= '0;
    end else if (opcode_cache == op_b_store) begin
        rd_v_mm  <= '0;
        rd_s_mm  <= '0;
    end else if (opcode_cache == op_b_load) begin
        if(!resp_latch&&execute_rdy)rd_s_mm  <= rd_s_ex;
        if (dmem_resp) begin
            mem_rdata  <= dmem_rdata;
            unique case (funct3_cache) 
                load_f3_lb  : rd_v_mm <= {{24{dmem_rdata[7 +8 *addr_cache[1:0]]}}, dmem_rdata[8 *addr_cache[1:0] +: 8 ]};
                load_f3_lbu : rd_v_mm <= {{24{1'b0}}                          , dmem_rdata[8 *addr_cache[1:0] +: 8 ]};
                load_f3_lh  : rd_v_mm <= {{16{dmem_rdata[15+16*addr_cache[1]  ]}}, dmem_rdata[16*addr_cache[1]   +: 16]};
                load_f3_lhu : rd_v_mm <= {{16{1'b0}}                          , dmem_rdata[16*addr_cache[1]   +: 16]};
                load_f3_lw  : rd_v_mm <= dmem_rdata;
                default     : rd_v_mm <= '0;
            endcase
        end else rd_v_mm <= '0;
        //TODO
    end else begin
        mm_rdy_reg   <= execute_rdy;
        if (opcode_cache == op_b_br || opcode_cache == op_b_store) rd_v_mm <= '0;
        else if (!resp_latch || mm_stall) rd_v_mm <= rd_v_mm;
        else rd_v_mm  <= rd_v_ex;
        if (opcode_cache == op_b_br || opcode_cache == op_b_store) rd_s_mm <= '0;
        else if (!resp_latch || mm_stall) rd_s_mm <= rd_s_mm;
        else rd_s_mm  <= rd_s_ex;
    end
end

always_comb begin
    if (opcode_cache == op_b_load || opcode_cache == op_b_store || m_cache || !mm_rdy)begin
        mm_stall = (~resp_any)&(~resp_latch);
    end
    else begin  
        mm_stall = '0;
    end
end

always_ff @ (posedge clk)begin
    if (opcode_cache == op_b_load || opcode_cache == op_b_store || m_cache || !resp_latch)begin
        mm_rdy <= resp_any;
    end
    else mm_rdy <= execute_rdy;
end

endmodule : memory