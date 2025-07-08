module id_stage
import rv32i_types::*;
#(parameter PADDR_L = 8)
(
    input  if_id_stage_reg_t  if_id_reg,
    output id_dis_stage_reg_t id_dis_reg_next,
    output rvfi_entry         rvfi_entry_decode, 

    // input  logic fifo_enq,
    input  logic fifo_empty,
    
    // input br_taken,

    output  logic               rs1_read,
    output  logic [4:0]         rs1_addr,  
    input   logic               rs1_renamed,
    input   logic [PADDR_L-1:0] rs1_paddr,
    input   logic [31:0]        rs1_data,

    output  logic               rs2_read,
    output  logic [4:0]         rs2_addr,
    input   logic               rs2_renamed,
    input   logic [PADDR_L-1:0] rs2_paddr,
    input   logic [31:0]        rs2_data,

    output  logic               rename_rd,
    input   logic [PADDR_L-1:0] rd_paddr,
    output  logic [4:0]         rd_aaddr,

    input   logic                dispatch_stall,
    output  logic               stall_id_prf_out,
    input  logic               PRF_full,

    input rob_entry_t rob_commit_entry_1,
    input rob_entry_t rob_commit_entry_2,
    input  logic [31:0] rob_commit_data_1,
    input  logic [31:0] rob_commit_data_2
);
    //TODO: add stall logic for instruction queue
    logic   [31:0]  inst;
    logic   [2:0]   funct3;
    logic   [6:0]   funct7;
    logic   [6:0]   opcode;
    logic   [31:0]  i_imm;
    logic   [31:0]  s_imm;
    logic   [31:0]  b_imm;
    logic   [31:0]  u_imm;
    logic   [31:0]  j_imm;

    logic           regf_we;

    logic   [31:0]  a;
    logic   [31:0]  b;

    logic           br_en;

    logic           inst_valid;
    logic           rs1_rob1, rs1_rob2, rs2_rob1, rs2_rob2;
    assign rs1_rob1 = rob_commit_entry_1.valid && rob_commit_entry_1.rd_paddr == rs1_paddr && rob_commit_entry_1.rd_aaddr == rs1_addr;
    assign rs1_rob2 = rob_commit_entry_2.valid && rob_commit_entry_2.rd_paddr == rs1_paddr && rob_commit_entry_2.rd_aaddr == rs1_addr;
    assign rs2_rob1 = rob_commit_entry_1.valid && rob_commit_entry_1.rd_paddr == rs2_paddr && rob_commit_entry_1.rd_aaddr == rs2_addr;
    assign rs2_rob2 = rob_commit_entry_2.valid && rob_commit_entry_2.rd_paddr == rs2_paddr && rob_commit_entry_2.rd_aaddr == rs2_addr;

    assign inst_valid = (~fifo_empty)  && !dispatch_stall;
    assign inst = if_id_reg.inst;

    assign rs1_read = inst_valid && id_dis_reg_next.ctrl_word.use_rs1 && rs1_addr!= 5'd0;
    assign rs2_read = inst_valid && id_dis_reg_next.ctrl_word.use_rs2 && rs2_addr!= 5'd0;
    assign regf_we = id_dis_reg_next.regf_we;

    assign rename_rd = inst_valid && id_dis_reg_next.regf_we; // && !dispatch_stall;

    assign stall_id_prf_out = (rename_rd && PRF_full);

    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];
    assign opcode = inst[6:0];
    assign i_imm  = {{21{inst[31]}}, inst[30:20]};
    assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
    assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    assign u_imm  = {inst[31:12], 12'h000};
    assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    assign rs1_addr  = inst[19:15];
    assign rs2_addr  = inst[24:20];
    assign rd_aaddr = if_id_reg.inst[11:7];

    logic [31:0] rs1_data_rob, rs2_data_rob;
    logic rs1_rob_flag, rs2_rob_flag;

    always_comb begin

        id_dis_reg_next.op_type = {2'b00, funct3};
        id_dis_reg_next.regf_we = 1'b0;
        id_dis_reg_next.imm = 'x;
        id_dis_reg_next.ctrl_word.set_inst_sel = alu_inst;
        id_dis_reg_next.ctrl_word.wb_sel = alu_result;
        id_dis_reg_next.cmpop = '0;

        id_dis_reg_next.ctrl_word.isload = 1'b0;
        id_dis_reg_next.ctrl_word.isstore = 1'b0;
        id_dis_reg_next.ctrl_word.isbranch = 1'b0;
        id_dis_reg_next.ctrl_word.isjal = 1'b0;
        id_dis_reg_next.ctrl_word.isjalr = 1'b0;

        id_dis_reg_next.ctrl_word.br_taken = 1'b0;

        id_dis_reg_next.ctrl_word.use_rs1 = 1'b0;
        id_dis_reg_next.ctrl_word.use_rs2 = 1'b0;

        unique case (opcode)
            op_b_lui  : begin
                id_dis_reg_next.imm = u_imm;
                id_dis_reg_next.regf_we = 1'b1;
            end
            op_b_auipc: begin
                id_dis_reg_next.imm = u_imm;
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.op_type = '0;
            end
            op_b_jal  : begin
                id_dis_reg_next.imm = j_imm;
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.ctrl_word.isjal = 1'b1;
                id_dis_reg_next.op_type[4:3] = 2'b01;
            end
            op_b_jalr : begin
                id_dis_reg_next.imm = i_imm;
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.ctrl_word.isjalr = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
                id_dis_reg_next.op_type[4:3] = 2'b10;
            end
            op_b_br   : begin
                id_dis_reg_next.imm = b_imm;
                id_dis_reg_next.cmpop = funct3;
                id_dis_reg_next.ctrl_word.isbranch = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs2 = 1'b1;
                id_dis_reg_next.op_type[4:3] = 2'b00;
            end
            op_b_load : begin
                id_dis_reg_next.imm = i_imm;
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.ctrl_word.isload = 1'b1;
                id_dis_reg_next.ctrl_word.wb_sel = mem_out;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
            end
            op_b_store: begin
                id_dis_reg_next.imm = s_imm;
                id_dis_reg_next.ctrl_word.isstore = 1'b1;
                id_dis_reg_next.ctrl_word.wb_sel = mem_out;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs2 = 1'b1;
            end
            op_b_imm  : begin
                id_dis_reg_next.imm = i_imm;
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
                id_dis_reg_next.op_type[4:3] = {1'b0,funct7[5]};
            end
            op_b_reg  : begin
                id_dis_reg_next.regf_we = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs1 = 1'b1;
                id_dis_reg_next.ctrl_word.use_rs2 = 1'b1;
                id_dis_reg_next.op_type[4:3] = {funct7[0],funct7[5]};
                unique case (funct3)
                    arith_f3_slt: begin 
                        id_dis_reg_next.cmpop = branch_f3_blt;
                        id_dis_reg_next.ctrl_word.set_inst_sel = set_inst;
                    end
                    arith_f3_sltu: begin
                        id_dis_reg_next.cmpop = branch_f3_bltu;
                        id_dis_reg_next.ctrl_word.set_inst_sel = set_inst;
                    end
                    default: ;
                endcase
            end
            default   : ;
        endcase
    
        id_dis_reg_next.inst        = if_id_reg.inst;
        id_dis_reg_next.i_valid     = dispatch_stall ? '0:inst_valid;
        id_dis_reg_next.order       = if_id_reg.order;
        id_dis_reg_next.rs1_addr    = rs1_addr;
        id_dis_reg_next.rs2_addr    = rs2_addr;
        id_dis_reg_next.rs1_data    = rs1_rob_flag? rs1_data_rob:rs1_data;
        id_dis_reg_next.rs2_data    = rs2_rob_flag? rs2_data_rob:rs2_data;
        id_dis_reg_next.rs1_renamed = rs1_rob_flag? '0:rs1_renamed;
        id_dis_reg_next.rs2_renamed = rs2_rob_flag? '0:rs2_renamed;
        id_dis_reg_next.rs1_paddr   = rs1_paddr;
        id_dis_reg_next.rs2_paddr   = rs2_paddr;
        id_dis_reg_next.rd_paddr    = id_dis_reg_next.regf_we? rd_paddr: '0;
        id_dis_reg_next.rd_addr     = id_dis_reg_next.regf_we? rd_aaddr: '0;
        id_dis_reg_next.opcode      = opcode;
        id_dis_reg_next.pc          = if_id_reg.pc;
        id_dis_reg_next.br_pred     = if_id_reg.br_pred;
        id_dis_reg_next.ftq_addr     = if_id_reg.ftq_addr;
    end

    
    always_comb begin
        if (rs1_renamed && (rs1_rob1 || rs1_rob2)) begin
            rs1_data_rob = rs1_rob1? rob_commit_data_1 : rob_commit_data_2;
            rs1_rob_flag = '1;
        end else begin
            rs1_data_rob = '0;
            rs1_rob_flag = '0;
        end

        if (rs2_renamed && (rs2_rob1 || rs2_rob2)) begin
            rs2_data_rob = rs2_rob1? rob_commit_data_1 : rob_commit_data_2;
            rs2_rob_flag = '1;
        end else begin
            rs2_data_rob = '0;
            rs2_rob_flag = '0;
        end
    end

    //RVFI
    always_comb begin
        rvfi_entry_decode           = '0;
        rvfi_entry_decode.order     = if_id_reg.order-2'd2;
        rvfi_entry_decode.inst      = if_id_reg.inst;
        rvfi_entry_decode.rs1_addr  = (id_dis_reg_next.ctrl_word.use_rs1)? rs1_addr : '0;
        rvfi_entry_decode.rs2_addr  = (id_dis_reg_next.ctrl_word.use_rs2)? rs2_addr : '0;
        rvfi_entry_decode.rs1_rdata = rs1_rob_flag? rs1_data_rob:rs1_data;
        rvfi_entry_decode.rs2_rdata = (id_dis_reg_next.ctrl_word.use_rs2)? (rs2_rob_flag? rs2_data_rob:rs2_data): '0;
        rvfi_entry_decode.rd_addr   = id_dis_reg_next.regf_we? if_id_reg.inst[11:7] : '0;
        rvfi_entry_decode.pc_rdata  = if_id_reg.pc;
        rvfi_entry_decode.pc_wdata  = if_id_reg.pc_next;
        rvfi_entry_decode.br_imm = b_imm;
    end

endmodule: id_stage