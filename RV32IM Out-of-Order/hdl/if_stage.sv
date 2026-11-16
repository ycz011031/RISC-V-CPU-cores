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
    input logic   [31:0]  rob_commit_rd_data,   // committed rd value (link address of a call)
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
    nx_sel_t        nx_sel;

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
    logic [PHT_ADDR_L-1:0]  curr_ghr, ghr_now;
    logic ibtype;
    logic update_ghr;
    logic [1:0] count_last;
    logic ftq_enq, ftq_deq, ftq_full, ftq_empty;
    ftq_entry_t ftq_in, ftq_out;
    logic [Q_INDEX-1:0] ftq_addr;
    logic [1:0] commit_count;
    logic [31:0] pc_next_reg;

    logic ras_push, ras_pop;
    ras_entry_t ras_in, ras_out;

    logic end_linebuf, channel_1_branching;

    // ---- slot 2 control flow ------------------------------------------------------
    // A fetch group holds at most one control-flow instruction, in either slot.
    // Slot 2 may hold a conditional branch or a jal (not a jalr) when slot 1 holds
    // no control flow. It gets its own prediction (gshare br_pred2), target adder,
    // FTQ entry and RAS push (jal call), and only takes effect when lane 2 is
    // actually enqueued (!stall_fetch2); otherwise it is fetched in slot 1 next cycle.
    logic        slot1_ctrl, br2, jal2, s2_br, s2_ctrl, br_pred2, br_signal2, s2_taken, lane2_en;
    logic [31:0] b_imm2, j_imm2, target2;
    logic [PHT_ADDR_L-1:0] pht_read_addr_last2;
    logic [1:0]  count_last2;

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


    // Which candidate pc_next is. The line buffer compares every candidate's line with
    // its tags in parallel and picks the result with nx_sel, so its demand decision does
    // not wait for the pc_next mux and then a tag compare.
    always_comb begin
        if (fetch_stall)       nx_sel = NX_PC;
        else if (flush)        nx_sel = NX_FLUSH;
        else if (flushlatch)   nx_sel = NX_FLUSH_REG;
        else if (br_signal)    nx_sel = NX_BR;
        else if (stall_fetch2) nx_sel = NX_PC4;
        else if (s2_taken)     nx_sel = NX_T2;
        else                   nx_sel = NX_PC8;
    end

    always_comb begin
        unique case (nx_sel)
            NX_PC:        pc_next = pc;
            NX_FLUSH:     pc_next = flush_target;
            NX_FLUSH_REG: pc_next = flush_target_reg;
            NX_BR:        pc_next = br_target_pred;
            NX_PC4:       pc_next = pc + 32'd4;
            NX_T2:        pc_next = target2;
            default:      pc_next = pc + 32'd8;
        endcase
    end

    // gshare slot-2 index, (pc_next + 4)[PHT_ADDR_L+1:2], formed per candidate (each with its
    // own low-bit adder) and picked with nx_sel, so the +4 is not after the pc_next mux.
    localparam IW = PHT_ADDR_L + 2;
    logic [PHT_ADDR_L-1:0] nx_idx2, br_idx2, t2_idx2;
    function automatic logic [PHT_ADDR_L-1:0] idx_of(input logic [IW-1:0] a);
        return a[IW-1:2];
    endfunction
    assign t2_idx2 = idx_of((pc[IW-1:0] + IW'(8)) + (jal2 ? j_imm2[IW-1:0] : b_imm2[IW-1:0]));
    always_comb begin
        unique case (nx_sel)
            NX_PC:        nx_idx2 = idx_of(pc[IW-1:0] + IW'(4));
            NX_FLUSH:     nx_idx2 = idx_of(flush_target[IW-1:0] + IW'(4));
            NX_FLUSH_REG: nx_idx2 = idx_of(flush_target_reg[IW-1:0] + IW'(4));
            NX_BR:        nx_idx2 = br_idx2;
            NX_PC4:       nx_idx2 = idx_of(pc[IW-1:0] + IW'(8));
            NX_T2:        nx_idx2 = t2_idx2;
            default:      nx_idx2 = idx_of(pc[IW-1:0] + IW'(12));
        endcase
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
    
    // the line buffer owns the I-cache port (demand fetches and next-line prefetches)
    logic        lb_ufp_read;
    assign ufp_rmask = {4{lb_ufp_read}};

    //line buffer for instructions
`ifndef OOO_LB_ENTRIES
`define OOO_LB_ENTRIES 3
`endif
    line_buf_superscalar #(.ENTRIES(`OOO_LB_ENTRIES)) line_buf_superscalar_i (
        .clk(clk),
        .rst(rst),
        .pc(pc),
        .pc_next(pc_next),
        .nx_sel(nx_sel),
        .nx_flush(flush_target),
        .nx_flush_reg(flush_target_reg),
        .nx_br(br_target_pred),
        .nx_t2(target2),
        .ufp_rdata(ufp_rdata),
        .ufp_resp(ufp_resp),
        .ufp_addr(ufp_addr),
        .ufp_read(lb_ufp_read),
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
        .pc_next_idx2(nx_idx2),
        .fetch_stall(fetch_stall),
        .flush(flush),
        .flush_flip(rob_commit.inst_type == 3'd1),
        // .br_mispred_actual(flush),
        .update_pht(update_pht),
        .update_ghr(update_ghr),
        .br_pred(br_pred),
        .br_pred2(br_pred2),
        .use_slot2(s2_br),
        .pht_read_addr_last2(pht_read_addr_last2),
        .count_last2(count_last2),
        .jalr_target_pred(jalr_target_pred),
        .curr_ghr(curr_ghr),
        .ghr_out(ghr_now),
        .pht_read_addr_last(pht_read_addr_last),
        .commit_ghr(commit_ghr),
        .count_last(count_last),
        .commit_count(commit_count),

        .pht_write_addr(pht_write_addr)
    );

    // ---- return address stack ------------------------------------------------
    // Calls / returns follow the RISC-V hint table (link = x1 or x5):
    //   jal  rd=link                         push
    //   jalr rd=link, rs1!=link              push
    //   jalr rd!=link, rs1=link              pop
    //   jalr rd=link, rs1=link, rd!=rs1      pop + push
    //   jalr rd=link, rs1=link, rd==rs1      push
    // Fetch updates the speculative stack; commit updates the committed stack
    // (jal from the ROB's rd, jalr from the bits saved in its FTQ entry, the
    // return address from the PRF commit read); a flush restores the
    // speculative stack from the committed one.
    logic push, pop;
    logic c_push, c_pop;

    function automatic logic is_link(input logic [4:0] r);
        return r == 5'd1 || r == 5'd5;
    endfunction

    RAS #( .RAS_HEIGHT(RAS_HEIGHT), .RAS_ADDR_L(RAS_ADDR_L)) ras_i(
        .clk(clk),
        .rst(rst),
        .push(ras_push),
        .pop(ras_pop),
        .push_addr(ras_in.ret_addr),
        .top_addr(ras_out.ret_addr),
        .c_push(c_push),
        .c_pop(c_pop),
        .c_push_addr(rob_commit_rd_data),
        .flush(flush)
    );

    assign ras_push = (~fetch_stall && push && if_id_reg_next.i_valid) ||
                      (jal2 && s2_ctrl && is_link(inst_2[11:7]) && lane2_en);
    assign ras_pop = ~fetch_stall && pop && if_id_reg_next.i_valid;
    assign ras_stall = 1'b0;            // circular: overflow drops the oldest entry

    // commit lane 1 only: lane 2 never commits control flow
    assign c_push = rob_commit.valid && ((rob_commit.inst_type == 3'd2 && is_link(rob_commit.rd_aaddr)) ||
                                         (rob_commit.inst_type == 3'd4 && ftq_out.ras_push));
    assign c_pop  = rob_commit.valid && rob_commit.inst_type == 3'd4 && ftq_out.ras_pop;

    assign ftq_enq = (~fetch_stall && if_id_reg_next.i_valid && isbranch) || (s2_br && lane2_en);
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
        ftq_in.br_target = s2_br ? target2 : br_target_pred;  //this will prolly get updated on writeback, this replaces previous rob entry to store it
        ftq_in.pht_addr = s2_br ? pht_read_addr_last2 : pht_read_addr_last;
        ftq_in.ghr = (ibtype || s2_br) ? curr_ghr : ghr_now;     // jalr: history is not shifted
        ftq_in.commit_count = s2_br ? count_last2 : count_last;
        ftq_in.ras_push = push;             // only read back for a jalr
        ftq_in.ras_pop = pop;
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
    logic auipc_count;
    logic auipc_jalr_flag;
    logic [31:0] auipc_jalr_imm_reg;

    logic [31:0]    jal_target, jalr_target, br_target_addr;

    assign jal_target = pc + j_imm;
    assign jalr_target = ras_out.ret_addr;
    assign br_target_addr = pc + b_imm;

    always_comb begin
        ras_in.ret_addr = s2_ctrl ? pc + 32'd8 : pc + 32'd4;     // a slot-2 jal call returns past it
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
        br_idx2 = '0;

        unique case (opcode)                        //inst is 0 on reset so will go to default
            op_b_jal  : begin
                // a = pc;
                // b = j_imm;
                br_target_pred = jal_target;
                br_idx2 = idx_of((pc[IW-1:0] + IW'(4)) + j_imm[IW-1:0]);
                br_signal = '1;
                isjal = '1;
                isbranch = '0;                     //1 for now cuz dp is ambiguous //0 cuz jal can be predicted with 100% accuracy
                push = is_link(rd_addr);           // function call
            end
            op_b_br  : begin
                // a = pc;
                // b = b_imm;
                br_target_pred = br_target_addr;
                br_idx2 = idx_of((pc[IW-1:0] + IW'(4)) + b_imm[IW-1:0]);
                br_signal = br_pred;
                isbranch = '1;
                ibtype = '1;
            end
            op_b_jalr  : begin
                // a = pc;
                // b = 32'd4;
                br_target_pred = jalr_target;
                br_idx2 = idx_of(jalr_target[IW-1:0] + IW'(4));
                br_signal = '0;         //pred NT for now until BTB is implemented
                isjalr = '1;          //still enq cuz store targ addr in ftq on wb
                isbranch = '1;
                push = is_link(rd_addr);
                pop  = is_link(rs1_addr) && (!is_link(rd_addr) || rd_addr != rs1_addr);
                if (pop) begin                           // function return: predict the stack top
                    br_signal = '1;
                end
                if (push && !pop) begin                  // function call
                    if (rs1_addr == 5'd1 && auipc_count) begin
                        // a = auipc_jalr_imm_reg;
                        // b = i_imm;
                        br_target_pred = auipc_target;
                        br_idx2 = idx_of((auipc_jalr_imm_reg[IW-1:0] + IW'(4)) + i_imm[IW-1:0]);
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

        update_ghr = (ibtype && if_id_reg_next.i_valid) || (s2_br && lane2_en);

    end
//0.293108
    // auipc ra -> jalr ra pair (a far call): remember the auipc result when it
    // is the last instruction fetched, in either lane, until the next fetch
    // group is taken (stall cycles keep it)
    logic auipc_lane2;
    assign auipc_lane2 = opcode2 == op_b_auipc && inst_2[11:7] == 5'd1 &&
                         if_id_reg_next2.i_valid && !stall_fetch2;

    always_ff @(posedge clk) begin
        if(rst || flush) begin
            auipc_jalr_imm_reg <= '0;
            auipc_count <= '0;
        end else if (!fetch_stall && if_id_reg_next.i_valid) begin
            if (auipc_lane2) begin
                auipc_count <= '1;
                auipc_jalr_imm_reg <= {inst_2[31:12], 12'h000} + pc + 32'd4;
            end else if (auipc_jalr_flag && !(if_id_reg_next2.i_valid && !stall_fetch2)) begin
                auipc_count <= '1;
                auipc_jalr_imm_reg <= u_imm + pc;
            end else begin
                auipc_count <= '0;
            end
        end
    end

    assign opcode2 = inst_2[6:0];

    assign b_imm2  = {{20{inst_2[31]}}, inst_2[7], inst_2[30:25], inst_2[11:8], 1'b0};
    assign j_imm2  = {{12{inst_2[31]}}, inst_2[19:12], inst_2[20], inst_2[30:21], 1'b0};
    assign target2 = (pc + 32'd4) + (jal2 ? j_imm2 : b_imm2);

    always_comb begin
        slot1_ctrl = opcode == op_b_jal || opcode == op_b_br || opcode == op_b_jalr;
`ifdef OOO_NO_SLOT2_CTRL
        br2        = '0;                        // experiment: control flow only in slot 1 (old rule)
        jal2       = '0;
`else
        br2        = opcode2 == op_b_br;
        jal2       = opcode2 == op_b_jal;
`endif
        s2_ctrl    = (br2 || jal2) && !slot1_ctrl;
        s2_br      = br2 && !slot1_ctrl;
        br_signal2 = jal2 ? 1'b1 : br_pred2;
        lane2_en   = !stall_fetch2 && if_id_reg_next2.i_valid;
        s2_taken   = s2_ctrl && br_signal2 && inst_valid && !(fetch_stall || flushlatch || flush);
    end

    // get instruction, pc
    always_comb begin
        
        dont_do_fetch2 = (opcode2 == op_b_jalr) ||
`ifdef OOO_NO_SLOT2_CTRL
                         (opcode2 == op_b_jal || opcode2 == op_b_br) ||
`endif
                         ((br2 || jal2) && slot1_ctrl) ||                 // one control-flow instruction per group
                         (br2 && ftq_full && !ftq_deq) ||                 // no FTQ entry for it this cycle
                         end_linebuf || channel_1_branching;

        if_id_reg_next2.order = order + 64'd1;
        if_id_reg_next2.inst = inst_2;
        if_id_reg_next2.i_valid = ~(flushlatch||flush || dont_do_fetch2) && inst_valid;
        if_id_reg_next2.pc = pc + 32'd4;

        // if (opcode == op_b_jal || opcode == op_b_br || opcode == op_b_jalr) begin
                
        // end

        if_id_reg_next2.br_pred = s2_ctrl ? br_signal2 : 1'b0;
        if_id_reg_next2.ftq_addr = s2_br ? ftq_addr : '0;
        if_id_reg_next2.pc_next = s2_taken ? target2 : pc + 32'd8;

    end


    
endmodule : if_stage