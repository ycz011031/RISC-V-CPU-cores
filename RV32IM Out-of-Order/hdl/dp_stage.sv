module dp_stage
import rv32i_types::*;
#(
    parameter PADDR_L = 8,
    parameter ROBADDR_L = 8
)
(
    input logic clk, 
    input logic rst,
    //RS station communication
    output  RS_entry_t      dp_rs_reg_next,
    output  logic [5:0]     dispatch_ready,
    input   logic [5:0]     RS_full,
    input   logic           ROB_full,

    input   logic           PRF_full,

    //ROB communication
    output  disp_rob_t      disp_rob,
    output  logic           rob_enq,
    input   logic [ROBADDR_L-1:0] rob_addr,

    //PRF communication
    output  logic               rs1_read,
    output  logic [PADDR_L-1:0] rs1_addr,
    input   logic               rs1_valid,  
    input   logic [31:0]        rs1_data,

    output  logic               rs2_read,
    output  logic [PADDR_L-1:0] rs2_addr,
    input   logic               rs2_valid,
    input   logic [31:0]        rs2_data,

    //decode communication
    input   id_dis_stage_reg_t  id_dis_reg,
    output  logic               dispatch_stall,
    input   logic               stall_in,

    input  CDB_t                cdb_main_1,
    input  CDB_t                cdb_main_2,

    //RVFI
    input   rvfi_entry rvfi_entry_decode_reg,
    output  rvfi_entry rvfi_entry_dispatch
);

    logic use_rs1, use_rs2, use_imm, use_rd, use_PC;

    //debug logic probe
    logic[6:0] opcode;
    logic inst_valid;
    logic [4:0] op_type;
    logic [PADDR_L-1:0]rd_paddr;

    // logic [31:0] brjal_target;
    logic        matchfull;

    logic rs1valid_reg, rs2valid_reg;

    logic rs1_cdb1, rs2_cdb2, rs1_cdb2, rs2_cdb1;
    assign rs1_cdb1 = cdb_main_1.valid && cdb_main_1.regf_we && rs1_addr == cdb_main_1.rd_paddr;
    assign rs1_cdb2 = cdb_main_2.valid && cdb_main_2.regf_we && rs1_addr == cdb_main_2.rd_paddr;
    assign rs2_cdb1 = cdb_main_1.valid && cdb_main_1.regf_we && rs2_addr == cdb_main_1.rd_paddr;
    assign rs2_cdb2 = cdb_main_2.valid && cdb_main_2.regf_we && rs2_addr == cdb_main_2.rd_paddr;

    always_ff @(posedge clk) begin
        if(rst) begin
            rs1valid_reg <= '0;
            rs2valid_reg <= '0;
        end
        else if ((dispatch_stall|| stall_in)) begin
            if (rs1_valid) rs1valid_reg <= '1;
            if (rs2_valid) rs2valid_reg <= '1;
        end
        else if (!(dispatch_stall|| stall_in)) begin
            rs1valid_reg <= '0;
            rs2valid_reg <= '0;
        end
    end


    assign opcode     = id_dis_reg.opcode;
    assign inst_valid = id_dis_reg.i_valid;
    assign op_type    = id_dis_reg.op_type;
    assign rd_paddr   = id_dis_reg.rd_paddr;

    always_comb begin
        use_rs1 = ~(id_dis_reg.opcode == op_b_jal || id_dis_reg.opcode == op_b_lui || id_dis_reg.opcode == op_b_auipc) ? '1:'0;
        use_rs2 =  (id_dis_reg.opcode == op_b_reg || id_dis_reg.opcode == op_b_br || id_dis_reg.opcode == op_b_store)? '1:'0;
        use_imm = !(id_dis_reg.opcode == op_b_reg)? '1:'0;
        use_rd  = ~(id_dis_reg.opcode == op_b_store || id_dis_reg.opcode == op_b_br)? '1:'0;
    end

    always_comb begin
        rs1_read = id_dis_reg.rs1_renamed;
        rs2_read = id_dis_reg.rs2_renamed;
        rs1_addr = id_dis_reg.rs1_paddr;
        rs2_addr = id_dis_reg.rs2_paddr;
    end;

    logic [31:0] rs1_data_actual,rs2_data_actual;
    logic [31:0] rs1_data_cdb, rs2_data_cdb;
    logic cdb_flag1, cdb_flag2;
    always_comb begin
        if (use_rs1 && (rs1_cdb1 || rs1_cdb2))begin
            rs1_data_cdb = rs1_cdb1 ? cdb_main_1.rd_data : cdb_main_2.rd_data;
            cdb_flag1    = '1;
        end else begin
            rs1_data_cdb = rs1_data;
            cdb_flag1    = '0;
        end

        if (use_rs2 && (rs2_cdb1 || rs2_cdb2))begin
            rs2_data_cdb = rs2_cdb1 ? cdb_main_1.rd_data : cdb_main_2.rd_data;
            cdb_flag2    = '1;
        end else begin
            rs2_data_cdb = rs2_data;
            cdb_flag2    = '0;
        end
    end

    always_comb begin
        rs1_data_actual = (id_dis_reg.rs1_renamed)? rs1_data_cdb : id_dis_reg.rs1_data;
        rs2_data_actual = (id_dis_reg.rs2_renamed)? rs2_data_cdb : id_dis_reg.rs2_data; 

        // brjal_target = id_dis_reg.pc + id_dis_reg.imm;

        dp_rs_reg_next.rob_addr  = rob_addr;
        dp_rs_reg_next.rs1_use   = use_rs1;
        dp_rs_reg_next.rs1_paddr = rs1_addr;
        dp_rs_reg_next.rs1_valid = (id_dis_reg.rs1_renamed)? ((rs1_valid||rs1valid_reg)? '1:cdb_flag1) : (use_rs1? 1'b1 : 1'b0);
        dp_rs_reg_next.rs1_data  = use_rs1? rs1_data_actual : id_dis_reg.pc;
        dp_rs_reg_next.rs2_use   = use_rs2;
        dp_rs_reg_next.rs2_paddr = rs2_addr;
        dp_rs_reg_next.rs2_valid = (id_dis_reg.rs2_renamed)? ((rs2_valid||rs2valid_reg)? '1:cdb_flag2) : (use_rs2? 1'b1 : 1'b0);
        dp_rs_reg_next.rs2_data  = use_rs2? rs2_data_actual : id_dis_reg.imm;
        dp_rs_reg_next.rd_paddr  = rd_paddr;
        dp_rs_reg_next.regf_we   = id_dis_reg.regf_we;
        dp_rs_reg_next.imm       = (id_dis_reg.ctrl_word.isbranch || id_dis_reg.ctrl_word.isjalr)? id_dis_reg.pc : id_dis_reg.imm; //store pc if br or jalr else store mem imm
        dp_rs_reg_next.order     = id_dis_reg.order;
        dp_rs_reg_next.op_type   = id_dis_reg.op_type;
        dp_rs_reg_next.br_pred   = id_dis_reg.br_pred;
        dp_rs_reg_next.ftq_addr   = id_dis_reg.ftq_addr;

        unique case(opcode)
            op_b_lui: begin
                dispatch_ready = {2'b00, id_dis_reg.i_valid, 3'b000};
                matchfull = RS_full[3] && id_dis_reg.i_valid;
            end
            op_b_reg: begin
                dispatch_ready[5:3] = 3'b000;
                
                unique casez ({id_dis_reg.op_type[4],id_dis_reg.op_type[2]})
                    2'b0? : dispatch_ready[2:0] = {2'b00,id_dis_reg.i_valid};
                    2'b10 : dispatch_ready[2:0] = {1'b0,id_dis_reg.i_valid,1'b0};
                    2'b11 : dispatch_ready[2:0] = {id_dis_reg.i_valid,2'b00};
                endcase
                unique casez ({id_dis_reg.op_type[4],id_dis_reg.op_type[2]})
                    2'b0? : matchfull = RS_full[0] && id_dis_reg.i_valid;
                    2'b10 : matchfull = RS_full[1] && id_dis_reg.i_valid;
                    2'b11 : matchfull = RS_full[2] && id_dis_reg.i_valid;
                endcase
            end
            op_b_imm,op_b_auipc: begin
                dispatch_ready = {5'b00000,id_dis_reg.i_valid};
                matchfull = RS_full[0] && id_dis_reg.i_valid;
            end
            op_b_load, op_b_store: begin
                dispatch_ready = {1'b0,id_dis_reg.i_valid,4'b0000};
                matchfull = RS_full[4] && id_dis_reg.i_valid;
            end
            op_b_br, op_b_jal, op_b_jalr: begin
                dispatch_ready = {id_dis_reg.i_valid,5'b00000};
                matchfull = RS_full[5] && id_dis_reg.i_valid;
            end
            default: begin
                dispatch_ready = {6'b000000};
                matchfull = '0;
            end
        endcase

        dispatch_stall = ((RS_full!=6'd0 && matchfull) || ROB_full || PRF_full)&&id_dis_reg.i_valid;
        
    end

    logic [2:0] inst_type;// 0:normal 1:branch 2:jal 3:store,4:jalr, 5: jal call, 6: jalr call, 7: jalr return
    logic [3:0] condition;
    assign condition[0] = id_dis_reg.ctrl_word.isbranch;
    assign condition[1] = id_dis_reg.ctrl_word.isstore;
    assign condition[2] = id_dis_reg.ctrl_word.isjal;
    assign condition[3] = id_dis_reg.ctrl_word.isjalr;


    always_comb begin

        unique case(condition)
            4'b0000 : inst_type = 3'd0;
            4'b0001 : inst_type = 3'd1;
            4'b0010 : inst_type = 3'd3;
            4'b0100 : begin 
                // inst_type = (id_dis_reg.rd_addr) == 5'd1 ? 3'd5 : 3'd2;
                inst_type = 3'd2;
            end
            4'b1000 : begin 
                // inst_type = (id_dis_reg.rd_addr == 5'd1) ? 3'd6 : (id_dis_reg.rd_addr == 5'd0 && id_dis_reg.rs1_addr == 5'd1)? 3'd7 : 3'd2;
                inst_type = 3'd4;
            end
            default: inst_type = 'x;
        endcase 

        rob_enq            = id_dis_reg.i_valid && !(dispatch_stall|| stall_in);
        disp_rob.valid     = id_dis_reg.i_valid & !(dispatch_stall|| stall_in);
        disp_rob.inst_type = inst_type;
        disp_rob.rd_paddr  = id_dis_reg.rd_paddr;
        disp_rob.rd_aaddr  = id_dis_reg.rd_addr;
    end


    //RVFI
    always_comb begin
        rvfi_entry_dispatch = rvfi_entry_decode_reg;
        rvfi_entry_dispatch.rs1_rdata  = use_rs1? rs1_data_actual:'0;
        rvfi_entry_dispatch.rs2_rdata  = use_rs2? rs2_data_actual:'0;
    end

endmodule : dp_stage