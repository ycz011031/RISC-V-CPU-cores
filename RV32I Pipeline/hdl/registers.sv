module registers
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,
    input   mem_wb_stage_reg_t  wb,             // write port (MEM/WB register)
    input   logic   [4:0]       rs1_s, rs2_s,
    output  logic   [31:0]      rs1_v, rs2_v
);

    logic [31:0]   data[32];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < 32; i++) begin
                data[i] <= '0;
            end
        end else if (wb.valid && (wb.rd_s != 5'd0)) begin
            data[wb.rd_s] <= wb.rd_v;
        end
    end

    // read with write-through bypass (a same-cycle write is visible to decode)
    always_comb begin
        rs1_v = (rs1_s == '0) ? '0 : (wb.valid && wb.rd_s == rs1_s) ? wb.rd_v : data[rs1_s];
        rs2_v = (rs2_s == '0) ? '0 : (wb.valid && wb.rd_s == rs2_s) ? wb.rd_v : data[rs2_s];
    end

endmodule : registers
