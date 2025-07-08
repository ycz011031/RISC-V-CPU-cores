module hazard_handler
import rv32i_types::*;
(   
    input   logic           clk,
    input   logic           rst,

    input   logic           execute_rdy,
    input   logic           mm_rdy,
    input   logic           wb_rdy,

    input   logic   [4:0]   rs1_s_de,
    input   logic   [4:0]   rs2_s_de,

    input   logic   [31:0]  rd_v_ex,
    input   logic   [31:0]  rd_v_mm,
    input   logic   [31:0]  rd_v_wb,
    input   logic   [4:0]   rd_s_ex,
    input   logic   [4:0]   rd_s_mm,
    input   logic   [4:0]   rd_s_wb,

    output  logic   [31:0]  rs1_fw_ex,
    output  logic   [31:0]  rs2_fw_ex,
    output  logic   [1:0]   rs_valid_ex
);

//Forward everthing to termination register of ID, with no exceptions
//Load - Use hazard would require 1 NOP insertion

logic [4:0]  rd_s_ch;
logic [31:0] rd_v_ch;
logic        ch_rdy;

always_ff @(posedge clk)begin
    if (rst) begin
        rd_s_ch <= '0;
        rd_v_ch <= '0;
    end else begin
        if (wb_rdy) begin
            rd_s_ch <= rd_s_wb;
            rd_v_ch <= rd_v_wb;
            ch_rdy  <= '1;
        end else begin
            rd_s_ch <= '0;
            rd_v_ch <= '0;
            ch_rdy  <= '1;
        end
    end
end


always_comb begin
    if (rs1_s_de != '0) begin
        if ((rs1_s_de == rd_s_ex) && execute_rdy) begin
            rs_valid_ex[0]  = '1;
            rs1_fw_ex       = rd_v_ex;
        end else if ((rs1_s_de == rd_s_mm) && mm_rdy) begin
            rs_valid_ex[0]  = '1;
            rs1_fw_ex       = rd_v_mm;
        end else if ((rs1_s_de == rd_s_wb) && wb_rdy) begin
            rs_valid_ex[0]  = '1;
            rs1_fw_ex       = rd_v_wb;
        end else if ((rs1_s_de == rd_s_ch) && ch_rdy) begin
            rs_valid_ex[0]  = '1;
            rs1_fw_ex       = rd_v_ch; 
        end else begin
            rs_valid_ex[0]  = '0;
            rs1_fw_ex       = '0;
        end
    end else begin
        rs_valid_ex[0] ='0;
        rs1_fw_ex      ='0;
    end 

    if (rs2_s_de != '0) begin
        if ((rs2_s_de == rd_s_ex) && execute_rdy) begin
            rs_valid_ex[1]  = '1;
            rs2_fw_ex       = rd_v_ex;
        end else if ((rs2_s_de == rd_s_mm) && mm_rdy) begin
            rs_valid_ex[1]  = '1;
            rs2_fw_ex       = rd_v_mm;
        end else if ((rs2_s_de == rd_s_wb) && wb_rdy) begin
            rs_valid_ex[1]  = '1;
            rs2_fw_ex       = rd_v_wb;
        end else if ((rs2_s_de ==rd_s_ch) && ch_rdy) begin
            rs_valid_ex[1]  = '1;
            rs2_fw_ex       = rd_v_ch;
        end else begin
            rs_valid_ex[1]  = '0;
            rs2_fw_ex       = '0;
        end
    end else begin
        rs_valid_ex[1] ='0;
        rs2_fw_ex       =0;
    end

end


endmodule : hazard_handler