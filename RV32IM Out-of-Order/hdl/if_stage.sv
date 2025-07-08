module if_stage
import rv32i_types::*;
#(
    parameter PHT_ADDR_L = 8,
    parameter FTQ_DEPTH = 32,
    parameter RAS_HEIGHT = 8,
    parameter RAS_ADDR_L = $clog2(RAS_HEIGHT),
    parameter Q_INDEX = $clog2(FTQ_DEPTH)
)
(   input   logic   clk,
    input   logic   rst,
    input   logic   fetch_stall,
    input   logic   [31:0] pc,
    input   logic   [255:0] ufp_rdata,
    input   logic   ufp_resp,
    
    output  logic   [31:0] pc_next,
    output  logic   [31:0] ufp_addr,
    output  logic   [3:0]  ufp_rmask,
    output  logic   i_need_resp,
    output  if_id_stage_reg_t if_id_reg_next, if_id_reg_next2,

    //BR interface
    // input logic br_mispred_actual, //coming from func_br or cdb or rob?
    input logic flush,
    // input logic     [31:0]  flush_target,
    // input logic     [PHT_ADDR_L-1:0] commit_ghr,
    input rob_entry_t     rob_commit,
    input CDB_t           cdb,

    output logic          flush_ufp,
    output logic          ftq_stall,
    output logic          ras_stall,

    input logic  [Q_INDEX-1:0]  funcbr_ftq_addr,
    output ftq_entry_t          to_funcbr,

    output logic dont_do_fetch2,
    input logic stall_fetch2,

    //RVFI
    input rvfi_entry rvfi_entry_commit
);

    logic   [63:0]  order;
    logic   [31:0]  inst_1, inst_2;
    logic   inst_valid;
    logic   i_request;

    logic   [31:0]  flush_target_reg;
    logic   flushlatch;

    logic   br_pred;
    logic   [31:0]  jalr_target_pred;

    logic [6:0] opcode, opcode2;
    logic [31:0]    br_target_pred, b_imm, j_imm, u_imm, i_imm;
    logic br_signal, isbranch, isjal, isjalr;
    logic update_pht;

    logic     [31:0]  flush_target;
    logic   [PHT_ADDR_L-1:0]    pht_write_addr;
    logic     [PHT_ADDR_L-1:0] commit_ghr;

    logic [PHT_ADDR_L-1:0] pht_read_addr_last;
    logic [PHT_ADDR_L-1:0]  curr_ghr;
    logic update_ghr;
    logic [1:0] count_last;
    logic ftq_enq, ftq_deq, ftq_full, ftq_empty;
    ftq_entry_t ftq_in, ftq_out;
    logic [Q_INDEX-1:0] ftq_addr;
    logic [1:0] commit_count;
    logic [31:0] pc_next_reg;

    logic ras_push, ras_pop, ras_full, ras_empty;
    ras_entry_t ras_in, ras_out;
    logic [RAS_ADDR_L-1:0] ras_addr;

    logic end_linebuf, channel_1_branching;

    assign flush_ufp = flushlatch;
    assign channel_1_branching = br_signal;

    // pc_next selection and order selection

    always_ff @(posedge clk) begin

        if (rst) begin
            flushlatch <= 1'b0;
            flush_target_reg <= 32'haaaaa000;
        end
        else if (flush && fetch_stall) begin
            flushlatch <= 1'b1;
            flush_target_reg <= flush_target;
        end
        else if (!fetch_stall && flushlatch) begin
            flushlatch <= 1'b0;
        end
    end


    always_comb begin
        if (fetch_stall) begin
            pc_next = pc;

        end else if (flush) begin
            pc_next = flush_target;

        end else if (flushlatch) begin
            pc_next = flush_target_reg;

        end else if (br_signal) begin
            pc_next = br_target_pred;

        end else if (stall_fetch2) begin
            pc_next = pc + 32'd4;
        end else begin
            pc_next = pc + 32'd8;
        end
    end

    // order updating
    always_ff @(posedge clk) begin
        if (rst) order <= '0;
        else if (flush) order <= rvfi_entry_commit.order + 64'd1;
        else if (fetch_stall) order <= order;
        else order <= (stall_fetch2 && !flushlatch)? (order + 1'b1) : (order + 2'd2);
        if (rst) pc_next_reg <= 32'haaaaa000;
        else pc_next_reg <= pc_next;
    end
    //instruction memory access
    
    always_comb begin
        ufp_addr = pc_next_reg;
        if (i_need_resp) begin
            ufp_rmask = '1;
        end else begin
            ufp_rmask = '0;
        end
    end

    //line buffer for instructions
    line_buf_superscalar line_buf_superscalar_i (
        .clk(clk),
        .rst(rst),
        .pc(pc),
        .pc_next(pc_next),
        .ufp_rdata(ufp_rdata),
        .ufp_resp(ufp_resp),
        .inst_1(inst_1),
        .inst_2(inst_2),
        .i_request(i_request),
        .i_need_resp(i_need_resp),
        .end_linebuf(end_linebuf),
        .inst_valid(inst_valid)
    );

    gshare #( .PHT_ADDR_L(PHT_ADDR_L)) gshare_i(
        .clk(clk),
        .rst(rst),
        // .pc(pc),
        .pc_next(pc_next),
        .fetch_stall(fetch_stall),
        .flush(flush || flushlatch),
        // .br_mispred_actual(flush),
        .update_pht(update_pht),
        .update_ghr(update_ghr),
        .br_pred(br_pred),
        .jalr_target_pred(jalr_target_pred),
        .curr_ghr(curr_ghr),
        .pht_read_addr_last(pht_read_addr_last),
        .commit_ghr(commit_ghr),
        .count_last(count_last),
        .commit_count(commit_count),

        .pht_write_addr(pht_write_addr)
    );

    // logic [RAS_ADDR_L-1:0]  ras_flush_top_pointer;
    // ras_entry_t             ret_ras_top, ret_ras_in, ret_ras_out;
    // logic ret_ras_empty, ret_ras_full, ret_ras_push, ret_ras_pop, ret_ras_stall;

    // RAS #( .RAS_HEIGHT(RAS_HEIGHT), .RAS_ADDR_L(RAS_ADDR_L)) spec_ras_i(
    //     .clk(clk),
    //     .rst(rst),
    //     .flush(flush),
    //     .push(ras_push),
    //     .pop(ras_pop),
    //     .din(ras_in), 
    //     .dout(ras_out),
    //     .full(ras_full),
    //     .empty(ras_empty),
    //     .ras_addr(ras_addr),

    //     .ret_ras_top(ret_ras_out),
    //     .ret_pointer(ras_flush_top_pointer),
    //     .ret_ras_empty(ret_ras_empty)
    // );

    // ret_RAS #( .RAS_HEIGHT(RAS_HEIGHT), .RAS_ADDR_L(RAS_ADDR_L)) retirement_ras_i(
    //     .clk(clk),
    //     .rst(rst),
    //     .push(ret_ras_push),
    //     .pop(ret_ras_pop),
    //     .din(ret_ras_in), 
    //     .dout(ret_ras_out),
    //     .full(ret_ras_full),
    //     .empty(ret_ras_empty),
    //     .ras_flush_top(ras_flush_top_pointer)
    // );

    // logic push, pop;
    // logic [31:0] func_ret;

    // assign ret_ras_push = rob_commit.valid && (rob_commit.inst_type == 3'd5 || rob_commit.inst_type==3'd6);
    // assign ret_ras_pop = rob_commit.valid && (rob_commit.inst_type == 3'd7);
    // assign ret_ras_stall = ret_ras_full && ret_ras_push;
    // assign ret_ras_in.ret_addr = func_ret;

    // assign ras_push = ~fetch_stall && push;
    // assign ras_pop = ~fetch_stall && pop;
    // assign ras_stall = ras_full && push;

    RAS_old #( .RAS_HEIGHT(RAS_HEIGHT), .RAS_ADDR_L(RAS_ADDR_L)) ras_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .push(ras_push),
        .pop(ras_pop),
        .din(ras_in), 
        // .cdb(cdb), 
        .dout(ras_out),
        .full(ras_full),
        .empty(ras_empty),
        .ras_addr(ras_addr)
    );

    logic push, pop;

    assign ras_push = ~fetch_stall && push && if_id_reg_next.i_valid;
    assign ras_pop = ~fetch_stall && pop && if_id_reg_next.i_valid;
    assign ras_stall = ras_full && push;

    assign ftq_enq = ~fetch_stall && if_id_reg_next.i_valid && isbranch;
    assign ftq_stall = (ftq_full && if_id_reg_next.i_valid && isbranch && !ftq_deq); // || (i_need_resp) || (instr_full && !instr_deq)||flush;
    assign ftq_deq = rob_commit.valid && (rob_commit.inst_type == 3'd1 || rob_commit.inst_type==3'd4); //br or jalr
    assign update_pht = rob_commit.valid && (rob_commit.inst_type == 3'd1);
//0.585929
    ftq #( .DEPTH(FTQ_DEPTH), .Q_INDEX(Q_INDEX)) ftq_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .enq(ftq_enq),
        .deq(ftq_deq),
        .din(ftq_in), 
        .cdb(cdb),  

        .dout(ftq_out),
        .full(ftq_full),
        .empty(ftq_empty),

        .ftq_addr(ftq_addr),
        
        .funcbr_ftq_addr(funcbr_ftq_addr),
        .to_funcbr(to_funcbr)
    );

    always_comb begin
        ftq_in.br_target = br_target_pred;  //this will prolly get updated on writeback, this replaces previous rob entry to store it
        ftq_in.pht_addr = pht_read_addr_last;
        ftq_in.ghr = curr_ghr;
        ftq_in.commit_count = count_last;
        // ftq_in.func_ret = br_target_pred;

        flush_target = ftq_out.br_target;
        pht_write_addr = ftq_out.pht_addr;
        commit_ghr = ftq_out.ghr;
        commit_count = ftq_out.commit_count;
        // func_ret = ftq_out.func_ret;

    end

    logic [4:0]         rs1_addr,  rd_addr;

    assign b_imm  = {{20{inst_1[31]}}, inst_1[7], inst_1[30:25], inst_1[11:8], 1'b0};
    assign j_imm  = {{12{inst_1[31]}}, inst_1[19:12], inst_1[20], inst_1[30:21], 1'b0};
    assign u_imm  = {inst_1[31:12], 12'h000};
    assign i_imm  = {{21{inst_1[31]}}, inst_1[30:20]};
    assign opcode = inst_1[6:0];

    assign rd_addr = inst_1[11:7];
    assign rs1_addr  = inst_1[19:15];

    // logic [31:0] a, b;
    logic ibtype;
    logic auipc_count;
    logic auipc_jalr_flag;
    logic [31:0] auipc_jalr_imm_reg;

    logic [31:0]    jal_target, jalr_target, br_target_addr;

    assign jal_target = pc + j_imm;
    assign jalr_target = ras_out.ret_addr;
    assign br_target_addr = pc + b_imm;

    always_comb begin
        ras_in.ret_addr = pc+32'd4;
    end

    logic [31:0] auipc_target;
    assign auipc_target = i_imm + auipc_jalr_imm_reg;

    // get instruction, pc
    always_comb begin
        if_id_reg_next.order = order;
        if_id_reg_next.inst = inst_1;
        if_id_reg_next.i_valid = ~(flushlatch||flush) && inst_valid;
        if_id_reg_next.pc_next = stall_fetch2? pc_next : pc + 32'd4;
        if_id_reg_next.pc = pc;
        
        ibtype = '0;
        push = '0;
        pop = '0;

        isbranch = '0;
        isjal = '0;
        isjalr = '0;
        auipc_jalr_flag = '0;
        br_target_pred = '0;

        unique case (opcode)                        //inst is 0 on reset so will go to default
            op_b_jal  : begin
                // a = pc;
                // b = j_imm;
                br_target_pred = jal_target;
                br_signal = '1;
                isjal = '1;
                isbranch = '0;                     //1 for now cuz dp is ambiguous //0 cuz jal can be predicted with 100% accuracy
                if (rd_addr == 5'd1) begin               // function call
                    push = '1;  // only push when valid
                end
            end
            op_b_br  : begin
                // a = pc;
                // b = b_imm;
                br_target_pred = br_target_addr;
                br_signal = br_pred;
                isbranch = '1;
                ibtype = '1;
            end
            op_b_jalr  : begin
                // a = pc;
                // b = 32'd4;
                br_target_pred = jalr_target;
                br_signal = '0;         //pred NT for now until BTB is implemented
                isjalr = '1;          //still enq cuz store targ addr in ftq on wb
                isbranch = '1;
                if (rd_addr == 5'd0 && rs1_addr == 5'd1 ) begin      //maybe add && rs1_addr == 5'd1 to improve accuracy         // function return
                    // a = ras_out.ret_addr;
                    pop = '1;
                    br_signal = '1;
                    isbranch = '1; //push to both ras and ftq for now
                end
                if (rd_addr == 5'd1) begin               // function call
                    push = '1;  // only push when valid
                    if (rs1_addr == 5'd1 && auipc_count) begin
                        // a = auipc_jalr_imm_reg;
                        // b = i_imm;
                        br_target_pred = auipc_target;
                        br_signal = '1;
                        isbranch = '1; //push to both ras and ftq for now
                    end
                end
            end
            op_b_auipc: begin
                if (rd_addr == 5'd1) begin
                    auipc_jalr_flag = if_id_reg_next.i_valid;
                end
                // a ='0;
                // b = '0;
                br_signal = '0;
            end
            default: begin
                // a ='0;
                // b = '0;
                br_signal = '0;
            end
        endcase

        // br_target_pred = pop? a : a + b;
        if (inst_valid && (fetch_stall || flushlatch||flush)) br_signal = '0;

        if_id_reg_next.br_pred = br_signal;
        if_id_reg_next.ftq_addr = ftq_addr;

        update_ghr = ibtype && if_id_reg_next.i_valid;

    end
//0.293108
    always_ff @(posedge clk) begin
        if(rst || flush) begin
            auipc_jalr_imm_reg <= '0;
            auipc_count <= '0;
        end else if (auipc_jalr_flag) begin
            auipc_count <= '1;
            auipc_jalr_imm_reg <= u_imm + pc;
        end else begin
            auipc_count <= '0;
            // auipc_jalr_imm_reg <= '0;
        end
    end

    assign opcode2 = inst_2[6:0];

    // get instruction, pc
    always_comb begin
        
        dont_do_fetch2 = (opcode2 == op_b_jal || opcode2 == op_b_br || opcode2 == op_b_jalr) || end_linebuf || channel_1_branching;

        if_id_reg_next2.order = order + 64'd1;
        if_id_reg_next2.inst = inst_2;
        if_id_reg_next2.i_valid = ~(flushlatch||flush || dont_do_fetch2) && inst_valid;
        if_id_reg_next2.pc_next = pc + 32'd8;
        if_id_reg_next2.pc = pc + 32'd4;

        // if (opcode == op_b_jal || opcode == op_b_br || opcode == op_b_jalr) begin
                
        // end

        if_id_reg_next2.br_pred = '0;
        if_id_reg_next2.ftq_addr = '0;

    end


    
endmodule : if_stage