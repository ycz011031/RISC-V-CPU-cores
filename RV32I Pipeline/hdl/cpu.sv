module cpu
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,

    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    input   logic   [31:0]  dmem_rdata,
    output  logic   [31:0]  dmem_wdata,
    input   logic           dmem_resp
);

    logic   [31:0]  inst;
    logic   [31:0]  PC_cur;
    logic   [31:0]  PC_next;
    logic   [31:0]  PC_cache;
    logic           fetch_rdy;
    logic           mm_stall;

    logic   [31:0]  jalr_target;
    logic           jalr_resolve;
    logic           br_flush;



    


    fetch fetch(
        .clk(clk),
        .rst(rst),

        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .imem_rdata(imem_rdata),
        .imem_resp(imem_resp),

        .mm_stall(mm_stall),

        .jalr_target(jalr_target),
        .jalr_resolve(jalr_resolve),
        .br_flush(br_flush),

        .inst(inst),
        .PC_cur(PC_cur),
        .PC_next(PC_next),
        .PC_cache(PC_cache),
        .fetch_rdy(fetch_rdy)
    );

    logic   [2:0]   funct3;
    logic   [6:0]   funct7;
    logic   [6:0]   opcode;
    logic   [4:0]   rs1_s;
    logic   [4:0]   rs2_s;
    logic   [4:0]   rd_s;
    logic   [31:0]  PC_cur_de;
    logic   [31:0]  PC_next_de;

    logic   [31:0]  rs1_v;
    logic   [31:0]  rs2_v;

    logic   [31:0]  rs1_v_sync;
    logic   [31:0]  rs2_v_sync;
    logic   [4:0]   rs1_s_sync;
    logic   [4:0]   rs2_s_sync;
    logic   [31:0]  imm_sync;

    logic   [31:0]  MM_addr_sync;

    logic           decode_rdy;

    decode decode(
        .clk(clk),
        .rst(rst),

        .inst(inst),
        .PC_cur(PC_cur),
        .PC_cache(PC_cache),
        .fetch_rdy(fetch_rdy),

        .funct3(funct3),
        .funct7(funct7),
        .opcode(opcode),
        .rs1_s(rs1_s),
        .rs2_s(rs2_s),
        .rd_s(rd_s),
        .PC_cur_de(PC_cur_de),
        .PC_next_de(PC_next_de),

        .rs1_v(rs1_v),
        .rs2_v(rs2_v),

        .br_flush(br_flush),
        .mm_stall(mm_stall),


        .rs1_v_sync(rs1_v_sync),
        .rs2_v_sync(rs2_v_sync),
        .rs1_s_sync(rs1_s_sync),
        .rs2_s_sync(rs2_s_sync),
        .imm_sync(imm_sync),

        .MM_addr_sync(MM_addr_sync),

        .decode_rdy(decode_rdy)
    );

    logic   [31:0]  rd_v_ex;
    logic   [4:0]   rd_s_ex;
    logic           execute_rdy;

    logic   [1:0]   rs_valid_ex;
    logic   [31:0]  rs1_fw_ex;
    logic   [31:0]  rs2_fw_ex;

    execute execute(
        .clk(clk),
        .rst(rst),

        .funct3(funct3),
        .funct7(funct7),
        .opcode(opcode),
        .rd_s(rd_s),

        .PC_cur_de(PC_cur_de),
        .decode_rdy(decode_rdy),

        .rs1_v_de(rs1_v_sync),
        .rs2_v_de(rs2_v_sync),
        .imm_sync(imm_sync),

        .rs_valid_ex(rs_valid_ex),
        .rs1_fw_ex(rs1_fw_ex),
        .rs2_fw_ex(rs2_fw_ex),

        .jalr_target(jalr_target),
        .jalr_resolve(jalr_resolve),
        .br_flush(br_flush),
        .mm_stall(mm_stall),

        .rd_v_ex(rd_v_ex),
        .rd_s_ex(rd_s_ex),
        .execute_rdy(execute_rdy)
    );   



    logic [31:0] mem_rdata;
    logic [31:0] rd_v_mm;
    logic [4:0]  rd_s_mm;
    logic        mm_rdy;
    

    memory memory(
        .clk(clk),
        .rst(rst),

        .funct3(funct3),
        .opcode(opcode),

        .decode_rdy(decode_rdy),
        .execute_rdy(execute_rdy),

        .rs1_v_de(rs1_v_sync),
        .rs2_v_de(rs2_v_sync),
        .imm_de(imm_sync),

        .rs_valid_ex(rs_valid_ex),
        .rs1_fw_ex(rs1_fw_ex),
        .rs2_fw_ex(rs2_fw_ex),

        .dmem_resp(dmem_resp),
        .dmem_rdata(dmem_rdata),

        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_rmask(dmem_rmask),
        .dmem_wmask(dmem_wmask),

        .rd_v_ex(rd_v_ex),
        .rd_s_ex(rd_s_ex),

        .br_flush(br_flush),
        

        .mem_rdata(mem_rdata),

        .rd_v_mm(rd_v_mm),
        .rd_s_mm(rd_s_mm),
        .mm_rdy(mm_rdy),
        .mm_stall(mm_stall)
        
    );






    logic   [31:0]  rd_v_wb;
    logic   [4:0]   rd_s_wb;
    logic           regf_we;

    writeback writeback(
        .clk(clk),
        .rst(rst),

        .rd_v_mm(rd_v_mm),
        .rd_s_mm(rd_s_mm),
        .mm_rdy(mm_rdy),

        .rd_v_wb(rd_v_wb),
        .rd_s_wb(rd_s_wb),
        .regf_we(regf_we)
    );

    hazard_handler hazard_handler(
        .clk(clk),
        .rst(rst),

        .execute_rdy(execute_rdy),
        .mm_rdy(mm_rdy),
        .wb_rdy(regf_we),

        .rs1_s_de(rs1_s_sync),
        .rs2_s_de(rs2_s_sync),

        .rd_v_ex(rd_v_ex),
        .rd_v_mm(rd_v_mm),
        .rd_v_wb(rd_v_wb),
        .rd_s_ex(rd_s_ex),
        .rd_s_mm(rd_s_mm),
        .rd_s_wb(rd_s_wb),

        .rs1_fw_ex(rs1_fw_ex),
        .rs2_fw_ex(rs2_fw_ex),
        .rs_valid_ex(rs_valid_ex)
    );


    registers registers(
        .clk(clk),
        .rst(rst),

        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .rs1_s(rs1_s),
        .rs2_s(rs2_s),

        .rd_v(rd_v_wb),
        .rd_s(rd_s_wb),
        .regf_we(regf_we)
    );

    logic [31:0]    inst_o;
    logic [31:0]    rs1_v_o;
    logic [31:0]    rs2_v_o;
    logic [31:0]    rd_v_o;
    logic [4:0]     rs1_s_o;
    logic [4:0]     rs2_s_o;
    logic [4:0]     rd_s_o;
    logic [31:0]    pc_o;
    logic [31:0]    pc_next_o;
    logic [31:0]    mem_addr_o;
    logic [63:0]    order;
    logic           commit;

    logic           regf_we_o;
    logic [3:0]     mem_rmask_o;
    logic [3:0]     mem_wmask_o;
    logic [31:0]     mem_rdata_o;
    logic [31:0]     mem_wdata_o;


    assign regf_we_o   = mm_rdy;

    logic [31:0] rs1_v_db;
    logic [31:0] rs2_v_db;

    assign rs1_v_db = rs_valid_ex[0]? rs1_fw_ex : rs1_v_sync;
    assign rs2_v_db = rs_valid_ex[1]? rs2_fw_ex : rs2_v_sync;

    debugcore debugcore(
        .clk(clk),
        .rst(rst),

        .inst(inst),
        .rs1_v(rs1_v_db),
        .rs2_v(rs2_v_db),
        .rd_v (rd_v_mm),
        .rs1_s(rs1_s_sync),
        .rs2_s(rs2_s_sync),
        .rd_s (rd_s_mm),
        .pc (PC_cur_de),
        .pc_next(PC_next_de),
        .mem_addr(dmem_addr),
        .mem_rmask(dmem_rmask),
        .mem_wmask(dmem_wmask),
        .mem_rdata(mem_rdata),
        .mem_wdata(dmem_wdata),
        .fetch_rdy(fetch_rdy),
        .decode_rdy(decode_rdy),
        .execute_rdy(execute_rdy),
        .mm_rdy(mm_rdy),

        .br_flush(br_flush),
        .jalr_resolve(jalr_resolve),
        .jalr_target(jalr_target),

        .inst_o(inst_o),
        .rs1_v_o(rs1_v_o),
        .rs2_v_o(rs2_v_o),
        .rd_v_o (rd_v_o),
        .rs1_s_o(rs1_s_o),
        .rs2_s_o(rs2_s_o),
        .rd_s_o (rd_s_o),
        .pc_o(pc_o),
        .pc_next_o(pc_next_o),
        .mem_addr_o(mem_addr_o),
        .mem_rdata_o(mem_rdata_o),
        .mem_wdata_o(mem_wdata_o),
        .mem_rmask_o(mem_rmask_o),
        .mem_wmask_o(mem_wmask_o),
        .order(order),
        .commit(commit)
    );


endmodule : cpu
