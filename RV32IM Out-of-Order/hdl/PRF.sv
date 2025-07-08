module PRF #(
    parameter PADDR_L = 8
)(
    input   logic               clk,
    input   logic               rst,
    input   logic               flush,

    //dispatch interface
    input   logic               rs1_read_1,
    input   logic [PADDR_L-1:0] rs1_addr_1,
    output  logic               rs1_valid_1,  
    output  logic [31:0]        rs1_data_1,

    input   logic               rs2_read_1,
    input   logic [PADDR_L-1:0] rs2_addr_1,
    output  logic               rs2_valid_1,
    output  logic [31:0]        rs2_data_1,

    //dispatch interface
    input   logic               rs1_read_2,
    input   logic [PADDR_L-1:0] rs1_addr_2,
    output  logic               rs1_valid_2,  
    output  logic [31:0]        rs1_data_2,

    input   logic               rs2_read_2,
    input   logic [PADDR_L-1:0] rs2_addr_2,
    output  logic               rs2_valid_2,
    output  logic [31:0]        rs2_data_2,

    //commit
    input   logic               rd_commit_read_1,
    input   logic [PADDR_L-1:0] rd_commit_addr_1,
    output  logic               rd_commit_valid_1,
    output  logic [31:0]        rd_commit_data_1,

    input   logic               rd_commit_read_2,
    input   logic [PADDR_L-1:0] rd_commit_addr_2,
    output  logic               rd_commit_valid_2,
    output  logic [31:0]        rd_commit_data_2,

    //CDB interface 1
    input   logic [PADDR_L-1:0] rd_wb_addr_1,
    input   logic [31:0]        rd_wb_data_1,
    input   logic               rd_wb_valid_1,

    //CDB interface 2
    input   logic [PADDR_L-1:0] rd_wb_addr_2,
    input   logic [31:0]        rd_wb_data_2,
    input   logic               rd_wb_valid_2

);


localparam PRF_SIZE = 2**PADDR_L;

logic [PRF_SIZE- 1:0] reg_valid;
logic [31:0] reg_data [PRF_SIZE];


always_ff @ (posedge clk) begin
    if (rst||flush) reg_valid <= '0;
    else begin 
        if (rd_wb_valid_1) begin
            reg_valid[rd_wb_addr_1] <= '1;
            reg_data [rd_wb_addr_1] <= rd_wb_data_1;
        end
        if (rd_wb_valid_2) begin
            reg_valid[rd_wb_addr_2] <= '1;
            reg_data [rd_wb_addr_2] <= rd_wb_data_2;
        end
        if (rd_commit_read_1) reg_valid[rd_commit_addr_1] <= '0;
        if (rd_commit_read_2) reg_valid[rd_commit_addr_2] <= '0;
    end
end

always_comb begin
    if(rs1_read_1)begin
        rs1_data_1  = reg_data[rs1_addr_1];
        rs1_valid_1 = reg_valid[rs1_addr_1];
    end else begin
        rs1_data_1  = '0;
        rs1_valid_1 = '0;
    end
    if (rs2_read_1)begin
        rs2_data_1  = reg_data[rs2_addr_1];
        rs2_valid_1 = reg_valid[rs2_addr_1];
    end else begin
        rs2_data_1  = '0;
        rs2_valid_1 = '0;
    end
    if(rs1_read_2)begin
        rs1_data_2  = reg_data[rs1_addr_2];
        rs1_valid_2 = reg_valid[rs1_addr_2];
    end else begin
        rs1_data_2  = '0;
        rs1_valid_2 = '0;
    end
    if (rs2_read_2)begin
        rs2_data_2  = reg_data[rs2_addr_2];
        rs2_valid_2 = reg_valid[rs2_addr_2];
    end else begin
        rs2_data_2  = '0;
        rs2_valid_2 = '0;
    end




    if (rd_commit_read_1)begin
        rd_commit_data_1  = reg_data[rd_commit_addr_1];
        rd_commit_valid_1 = reg_valid[rd_commit_addr_1];
    end else begin
        rd_commit_data_1  = '0;
        rd_commit_valid_1 = '0;
    end 
    if (rd_commit_read_2)begin
        rd_commit_data_2  = reg_data[rd_commit_addr_2];
        rd_commit_valid_2 = reg_valid[rd_commit_addr_2];
    end else begin
        rd_commit_data_2  = '0;
        rd_commit_valid_2 = '0;
    end 
end

endmodule