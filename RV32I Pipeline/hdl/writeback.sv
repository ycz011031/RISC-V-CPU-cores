module writeback
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    input   logic   [31:0]  rd_v_mm,
    input   logic   [4:0]   rd_s_mm,
    input   logic           mm_rdy,

    output  logic   [31:0]  rd_v_wb,
    output  logic   [4:0]   rd_s_wb,
    output  logic           regf_we
);


    always_ff @ (posedge clk) begin
        if (rst) begin
            rd_v_wb <= '0;
            rd_s_wb <= '0;
            regf_we <= '0;
        end else if (mm_rdy) begin
            rd_v_wb <= rd_v_mm;
            rd_s_wb <= rd_s_mm;
            regf_we <= '1;
        end else begin
            regf_we <= '0;
        end
    end

endmodule : writeback        
        