module debugcore
(
    input   logic           clk,
    input   logic           rst,

    input   logic [31:0]    inst,
    input   logic [31:0]    rs1_v,
    input   logic [31:0]    rs2_v,
    input   logic [31:0]    rd_v,
    input   logic [4:0]     rs1_s,
    input   logic [4:0]     rs2_s,
    input   logic [4:0]     rd_s,
    input   logic [31:0]    pc,
    input   logic [31:0]    pc_next,
    input   logic [31:0]    mem_addr,
    input   logic [3:0]     mem_rmask,
    input   logic [3:0]     mem_wmask,
    input   logic [31:0]    mem_rdata,
    input   logic [31:0]    mem_wdata,
    input   logic           fetch_rdy,
    input   logic           decode_rdy,
    input   logic           execute_rdy,
    input   logic           mm_rdy,

    input   logic           br_flush,
    input   logic           jalr_resolve,
    input   logic  [31:0]   jalr_target,

    output   logic [31:0]    inst_o,
    output   logic [31:0]    rs1_v_o,
    output   logic [31:0]    rs2_v_o,
    output   logic [31:0]    rd_v_o,
    output   logic [4:0]     rs1_s_o,
    output   logic [4:0]     rs2_s_o,
    output   logic [4:0]     rd_s_o,
    output   logic [31:0]    pc_o,
    output   logic [31:0]    pc_next_o,
    output   logic [31:0]    mem_addr_o,
    output   logic [3:0]     mem_rmask_o,
    output   logic [3:0]     mem_wmask_o,
    output   logic [31:0]    mem_wdata_o,
    output   logic [31:0]    mem_rdata_o,
    output   logic [63:0]    order,
    output   logic           commit
);

logic [31:0] inst_buf[3];
logic [31:0] rs1_v_buf[2], rs2_v_buf[2], pc_buf[2], pc_next_buf[2];
logic [4:0]  rs1_s_buf[2], rs2_s_buf[2];  
logic [3:0]  mem_rmask_buf[2], mem_wmask_buf[2];
logic [31:0] mem_addr_buf[2], mem_wdata_buf[2];  




always_ff @ (posedge clk) begin
    if (rst) begin
        commit <= '0;
        order  <= '1;
    end else begin
        if (fetch_rdy) begin
            inst_buf[0]     <= inst;
        end
        if (decode_rdy) begin
            inst_buf[1]     <= inst_buf[0];
            rs1_v_buf[0]       <= rs1_v;
            rs2_v_buf[0]       <= rs2_v;
            rs1_s_buf[0]       <= rs1_s;
            rs2_s_buf[0]       <= rs2_s;
            pc_buf[0]          <= pc;
            if (jalr_resolve) pc_next_buf[0] <= jalr_target;
            else if (br_flush) pc_next_buf[0]<=pc+4;
            else pc_next_buf[0]     <= pc_next;
            mem_addr_buf[0]    <= mem_addr;
            mem_wdata_buf[0]   <= mem_wdata;
            mem_rmask_buf[0]   <= mem_rmask;
            mem_wmask_buf[0]   <= mem_wmask; 
        end
        if (execute_rdy) begin
            inst_buf[2]     <= inst_buf[1];
            rs1_v_buf[1]    <= rs1_v_buf[0];
            rs2_v_buf[1]    <= rs2_v_buf[0];
            rs1_s_buf[1]    <= rs1_s_buf[0];
            rs2_s_buf[1]    <= rs2_s_buf[0];
            pc_buf[1]       <= pc_buf[0];
            pc_next_buf[1]  <= pc_next_buf[0];
            mem_addr_buf[1] <= mem_addr_buf[0];
            mem_rmask_buf[1]<= mem_rmask_buf[0];
            mem_wmask_buf[1]<= mem_wmask_buf[0];
            mem_wdata_buf[1]<= mem_wdata_buf[0];
             
        end   
        if (mm_rdy) begin
            inst_o          <= inst_buf[2];
            rs1_v_o         <= rs1_v_buf[1];
            rs2_v_o         <= rs2_v_buf[1];
            rs1_s_o         <= rs1_s_buf[1];
            rs2_s_o         <= rs2_s_buf[1];
            pc_o            <= pc_buf[1];
            pc_next_o       <= pc_next_buf[1];
            mem_addr_o      <= mem_addr_buf[1];
            mem_rmask_o     <= mem_rmask_buf[1];
            mem_wmask_o     <= mem_wmask_buf[1];
            mem_rdata_o     <= mem_rdata;
            mem_wdata_o     <= mem_wdata_buf[1];
            rd_v_o          <= rd_v;
            rd_s_o          <= rd_s;
            order           <= order + 1;
            commit          <= '1;
        end else begin
            commit          <= '0;
        end
    end
end

endmodule : debugcore


