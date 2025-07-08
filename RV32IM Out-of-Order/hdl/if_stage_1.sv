module if_stage_1
import rv32i_types::*;
#(
    parameter PHT_ADDR_L = 8,
    parameter FTQ_DEPTH = 32
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

    output logic dont_do_fetch2,
    input logic stall_fetch2,

    //RVFI
    input rvfi_entry rvfi_entry_commit
);

    logic   [63:0]  order;
    logic   [31:0]  inst_1, inst_2;
    logic   i_request;

    logic   [31:0]  flush_target_reg;
    logic   flushlatch;

    logic   br_pred;
    logic   [31:0]  jalr_target_pred;

    logic [6:0] opcode, opcode2;
    logic [31:0]    br_target_pred, b_imm, j_imm;
    logic br_signal, isbranch;
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
    localparam Q_INDEX = $clog2(FTQ_DEPTH);
    logic [Q_INDEX-1:0] ftq_addr;
    logic [1:0] commit_count;
    logic [31:0] pc_next_reg;

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
        .end_linebuf(end_linebuf)
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

    assign ftq_enq = ~fetch_stall && if_id_reg_next.i_valid && isbranch;
    assign ftq_stall = (ftq_full && if_id_reg_next.i_valid && isbranch && !ftq_deq); // || (i_need_resp) || (instr_full && !instr_deq)||flush;
    assign ftq_deq = rob_commit.valid && (rob_commit.inst_type == 2'd1 || rob_commit.inst_type==2'd2); //br or jalr
    assign update_pht = rob_commit.valid && (rob_commit.inst_type == 2'd1);

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

        .ftq_addr(ftq_addr)
    );

    always_comb begin
        ftq_in.br_target = br_target_pred;  //this will prolly get updated on writeback, this replaces previous rob entry to store it
        ftq_in.pht_addr = pht_read_addr_last;
        ftq_in.ghr = curr_ghr;
        ftq_in.commit_count = count_last;

        flush_target = ftq_out.br_target;
        pht_write_addr = ftq_out.pht_addr;
        commit_ghr = ftq_out.ghr;
        commit_count = ftq_out.commit_count;

    end



    assign b_imm  = {{20{inst_1[31]}}, inst_1[7], inst_1[30:25], inst_1[11:8], 1'b0};
    assign j_imm  = {{12{inst_1[31]}}, inst_1[19:12], inst_1[20], inst_1[30:21], 1'b0};
    assign opcode = inst_1[6:0];

    logic [31:0] a, b;
    logic ibtype;

    // get instruction, pc
    always_comb begin
        if_id_reg_next.order = order;
        if_id_reg_next.inst = inst_1;
        if_id_reg_next.i_valid = ~(flushlatch||flush);
        if_id_reg_next.pc_next = stall_fetch2? pc_next : pc + 32'd4;
        if_id_reg_next.pc = pc;
        ibtype = '0;

        unique case (opcode)                        //inst is 0 on reset so will go to default
            op_b_jal  : begin
                a = pc;
                b = j_imm;
                br_signal = '1;
                isbranch = '1;                      //0 cuz jal can be predicted with 100% accuracy
            end
            op_b_br  : begin
                a = pc;
                b = b_imm;
                br_signal = br_pred;
                isbranch = '1;
                ibtype = '1;
            end
            op_b_jalr  : begin
                a = jalr_target_pred;
                b = '0;
                br_signal = '0;         //pred NT for now until BTB is implemented
                isbranch = '1;          //still enq cuz store targ addr in ftq on wb
            end
            default: begin
                a ='0;
                b = '0;
                br_signal = '0;
                isbranch = '0;
            end
        endcase

        br_target_pred = a + b;
        if (fetch_stall || flushlatch||flush ) br_signal = '0;

        if_id_reg_next.br_pred = br_signal;
        if_id_reg_next.ftq_addr = ftq_addr;

        update_ghr = ibtype && if_id_reg_next.i_valid;

    end

    assign opcode2 = inst_2[6:0];

    // get instruction, pc
    always_comb begin
        
        dont_do_fetch2 = (opcode2 == op_b_jal || opcode2 == op_b_br || opcode2 == op_b_jalr) || end_linebuf || channel_1_branching;

        if_id_reg_next2.order = order + 64'd1;
        if_id_reg_next2.inst = inst_2;
        if_id_reg_next2.i_valid = ~(flushlatch||flush);
        if_id_reg_next2.pc_next = pc + 32'd8;
        if_id_reg_next2.pc = pc + 32'd4;

        // if (opcode == op_b_jal || opcode == op_b_br || opcode == op_b_jalr) begin
                
        // end

        if_id_reg_next2.br_pred = '0;
        if_id_reg_next2.ftq_addr = '0;

    end

    
endmodule : if_stage_1