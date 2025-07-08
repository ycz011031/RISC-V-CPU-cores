module RAT
import rv32i_types::*;
 #(
        parameter PADDR_L = 8
    )
(
    input   logic               clk,
    input   logic               rst,
    input   logic               flush,

    //rename interface
    input   logic [4:0]         rd_addr_a_1,
    input   logic [PADDR_L-1:0] rd_addr_p_1,
    input   logic               rd_rename_1,

    input   logic [4:0]         rd_addr_a_2,
    input   logic [PADDR_L-1:0] rd_addr_p_2,
    input   logic               rd_rename_2,

    //dispatch interface
    input   logic               rs1_read_1,
    input   logic [4:0]         rs1_addr_1,  
    output  logic               rs1_renamed_1, 
    output  logic [PADDR_L-1:0] rs1_paddr_1,
    output  logic [31:0]        rs1_data_1,

    input   logic               rs2_read_1,
    input   logic [4:0]         rs2_addr_1,
    output  logic               rs2_renamed_1,
    output  logic [PADDR_L-1:0] rs2_paddr_1,
    output  logic [31:0]        rs2_data_1,

    //dispatch interface
    input   logic               rs1_read_2,
    input   logic [4:0]         rs1_addr_2,  
    output  logic               rs1_renamed_2, 
    output  logic [PADDR_L-1:0] rs1_paddr_2,
    output  logic [31:0]        rs1_data_2,

    input   logic               rs2_read_2,
    input   logic [4:0]         rs2_addr_2,
    output  logic               rs2_renamed_2,
    output  logic [PADDR_L-1:0] rs2_paddr_2,
    output  logic [31:0]        rs2_data_2,


    output  logic               rd_commit_1,
    output  logic [PADDR_L-1:0] rd_commit_paddr_1,
    input   logic [31:0]        rd_commit_data_1,
    
    output  logic               rd_commit_2,
    output  logic [PADDR_L-1:0] rd_commit_paddr_2,
    input   logic [31:0]        rd_commit_data_2,

    input   rob_entry_t         rob_commit_1,
    input   rob_entry_t         rob_commit_2
);

logic [31:0]        reg_data[32];
logic [PADDR_L-1:0] reg_paddr[32];
logic [31:0]        reg_renamed;


logic [4:0]         rd_commit_aaddr_1, rd_commit_aaddr_2;
logic rd1_cm1, rd1_cm2, rd2_cm1, rd2_cm2;

logic rs1_ch1, rs2_ch1;

assign rd_commit_1 = rob_commit_1.valid && rob_commit_1.inst_type != 3'd3 && rob_commit_1.inst_type != 3'd1;
assign rd_commit_aaddr_1 = rob_commit_1.rd_aaddr;
assign rd_commit_paddr_1 = rob_commit_1.rd_paddr;

assign rd_commit_2 = rob_commit_2.valid && rob_commit_2.inst_type != 3'd3 && rob_commit_2.inst_type != 3'd1;
assign rd_commit_aaddr_2 = rob_commit_2.rd_aaddr;
assign rd_commit_paddr_2 = rob_commit_2.rd_paddr;

assign rd1_cm1 = !(rd_rename_1 && rd_commit_aaddr_1==rd_addr_a_1) && rd_commit_paddr_1==reg_paddr[rd_commit_aaddr_1];
assign rd1_cm2 = !(rd_rename_1 && rd_commit_aaddr_2==rd_addr_a_1) && rd_commit_paddr_2==reg_paddr[rd_commit_aaddr_2];
assign rd2_cm1 = !(rd_rename_2 && rd_commit_aaddr_1==rd_addr_a_2) && rd_commit_paddr_1==reg_paddr[rd_commit_aaddr_1];
assign rd2_cm2 = !(rd_rename_2 && rd_commit_aaddr_2==rd_addr_a_2) && rd_commit_paddr_2==reg_paddr[rd_commit_aaddr_2];

assign rs1_ch1 = rd_rename_1 && (rs1_addr_2 == rd_addr_a_1);
assign rs2_ch1 = rd_rename_1 && (rs2_addr_2 == rd_addr_a_1);


//commit & rename
always_ff @(posedge clk) begin
    if (rst) begin
        reg_renamed <= '0;
        for (integer i = 0; i < 32; i++) begin
            reg_data[i] <= '0;
            reg_paddr[i] <= '0;
        end
    end else if (flush) begin
        reg_renamed <= '0;
        if (rd_commit_1) reg_data[rd_commit_aaddr_1] <= rd_commit_data_1;
        if (rd_commit_2) reg_data[rd_commit_aaddr_2] <= rd_commit_data_2;
            
    end else begin
        if (rd_commit_1) begin
            reg_data[rd_commit_aaddr_1] <= rd_commit_data_1;
            if ((rd1_cm1 && rd2_cm1)) reg_renamed[rd_commit_aaddr_1] <= '0;
        end
        if (rd_commit_2) begin
            reg_data[rd_commit_aaddr_2] <= rd_commit_data_2;
            if ((rd1_cm2 && rd2_cm2)) reg_renamed[rd_commit_aaddr_2] <= '0;
        end
        if (rd_rename_1 && !(rd_rename_2 && (rd_addr_a_1 == rd_addr_a_2))) begin
            reg_paddr[rd_addr_a_1] <= rd_addr_p_1;
            reg_renamed[rd_addr_a_1] <= '1;
        end
        if (rd_rename_2) begin
            reg_paddr[rd_addr_a_2] <= rd_addr_p_2;
            reg_renamed[rd_addr_a_2] <= '1;
        end

    end
end

//rs1 rs2 read operation
always_comb begin
    if (rs1_read_1) begin
        if (rs1_addr_1 == '0) begin
            rs1_data_1     = '0;
            rs1_renamed_1  = '0;
            rs1_paddr_1    = '0;
        end else begin
            rs1_data_1     = reg_renamed[rs1_addr_1] ? '0 : reg_data[rs1_addr_1];
            rs1_renamed_1  = reg_renamed[rs1_addr_1];
            rs1_paddr_1    = reg_renamed[rs1_addr_1] ? reg_paddr[rs1_addr_1] : '0;
        end
    end else begin
        rs1_data_1     ='0;
        rs1_renamed_1  ='0;
        rs1_paddr_1    ='0;
    end

    if (rs2_read_1) begin
        if (rs2_addr_1 == '0) begin
            rs2_data_1     = '0;
            rs2_renamed_1  = '0;
            rs2_paddr_1    = '0;
        end else begin
            rs2_data_1     = reg_renamed[rs2_addr_1] ? '0 : reg_data[rs2_addr_1];
            rs2_renamed_1  = reg_renamed[rs2_addr_1];
            rs2_paddr_1    = reg_renamed[rs2_addr_1] ? reg_paddr[rs2_addr_1] : '0;
        end
    end else begin
        rs2_data_1     = '0;
        rs2_renamed_1  = '0;
        rs2_paddr_1    = '0;
    end


    if (rs1_read_2) begin
        if (rs1_addr_2 == '0) begin
            rs1_data_2     = '0;
            rs1_renamed_2  = '0;
            rs1_paddr_2    = '0;
        end else begin
            rs1_data_2     = reg_renamed[rs1_addr_2] ? '0 : reg_data[rs1_addr_2];
            rs1_renamed_2  = rs1_ch1 ? '1 : reg_renamed[rs1_addr_2];
            rs1_paddr_2    = rs1_ch1 ? rd_addr_p_1 : (reg_renamed[rs1_addr_2] ? reg_paddr[rs1_addr_2] : '0);
        end
    end else begin
        rs1_data_2     ='0;
        rs1_renamed_2  ='0;
        rs1_paddr_2    ='0;
    end

    if (rs2_read_2) begin
        if (rs2_addr_2 == '0) begin
            rs2_data_2     = '0;
            rs2_renamed_2  = '0;
            rs2_paddr_2    = '0;
        end else begin
            rs2_data_2     = reg_renamed[rs2_addr_2] ? '0 : reg_data[rs2_addr_2];
            rs2_renamed_2  = rs2_ch1 ? '1 : reg_renamed[rs2_addr_2];
            rs2_paddr_2    = rs2_ch1 ? rd_addr_p_1 : (reg_renamed[rs2_addr_2] ? reg_paddr[rs2_addr_2] : '0);
        end
    end else begin
        rs2_data_2     = '0;
        rs2_renamed_2  = '0;
        rs2_paddr_2    = '0;
    end
end

endmodule : RAT