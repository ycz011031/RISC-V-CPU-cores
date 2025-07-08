module cpu
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,

    input   logic               bmem_rvalid
);

    localparam INSTR_DEPTH = 16;
    localparam MEM_DEPTH = 4;
    localparam RS_BIT = 3;
    localparam PADDR_L = 5;
    localparam ROBADDR_L = 5;
    localparam PRF_SIZE = 2 ** PADDR_L;
    localparam MEM_INDEX = $clog2(MEM_DEPTH);

    localparam PHT_ADDR_L = 8;
    localparam FTQ_DEPTH = 16;
    localparam RAS_HEIGHT = 8;
    localparam RAS_ADDR_L = $clog2(RAS_HEIGHT);
    localparam Q_INDEX = $clog2(FTQ_DEPTH);

    logic flush, flush_1, flush_2;
    // !!!!!!! COPY BRANCH FOR MAIN!!!!!!
    // GMPD4 208.40//
    //Coremark IPC 0.5258, PD4 20.1//
    //aes-sha  IPC 0.3238, PD4 6390.75//
    //compression IPC 0.6502 //
    //fft         IPC 0.6352 //
    //mergesort   IPC 0.5509 //
    // serial 008//

    
    logic [31:0] i_ufp_addr;
    logic [3:0]  i_ufp_rmask;
    logic [3:0]  i_ufp_wmask;
    logic [255:0] i_ufp_rdata;
    logic [31:0] i_ufp_wdata;
    logic        i_ufp_resp;

    logic [31:0] d_ufp_addr;
    logic [3:0]  d_ufp_rmask;
    logic [3:0]  d_ufp_wmask;
    logic [31:0] d_ufp_rdata;
    logic [31:0] d_ufp_wdata;
    logic        d_ufp_resp;

    logic [31:0] dfp_addr_i ,dfp_addr_d;
    logic        dfp_read_i ,dfp_read_d;
    logic        dfp_write_i,dfp_write_d;
    logic [255:0]dfp_rdata_i,dfp_rdata_d;
    logic [255:0]dfp_wdata_i,dfp_wdata_d;
    logic        dfp_resp_i ,dfp_resp_d;

    logic ufp_miss;


    logic stall_fetch2, dont_do_fetch2;

    logic dummy1;
    logic [31:0] dummy2;

    assign dummy1 = bmem_ready;
    assign dummy2 = bmem_raddr;

    if_id_stage_reg_t instr_queue_out_1;
    if_id_stage_reg_t instr_queue_out_2;



    assign i_ufp_wmask = '0;
    assign i_ufp_wdata = '0;
    //---------------------------------------------------------------------------------

    //---------------------------------------------------------------------------------

    //RAT accessing logics
    logic               RAT_rs1_read_1, RAT_rs2_read_1;
    logic               RAT_rs1_read_2, RAT_rs2_read_2;
    logic [4:0]         RAT_rs1_addr_1, RAT_rs2_addr_1;
    logic [4:0]         RAT_rs1_addr_2, RAT_rs2_addr_2;
    logic               RAT_rs1_renamed_1, RAT_rs2_renamed_1;
    logic               RAT_rs1_renamed_2, RAT_rs2_renamed_2;
    logic [PADDR_L-1:0] RAT_rs1_paddr_1, RAT_rs2_paddr_1;
    logic [PADDR_L-1:0] RAT_rs1_paddr_2, RAT_rs2_paddr_2;
    logic [31:0]        RAT_rs1_data_1, RAT_rs2_data_1;
    logic [31:0]        RAT_rs1_data_2, RAT_rs2_data_2;
    logic               RAT_rd_rename_1,RAT_rd_rename_2;
    logic [4:0]         RAT_rd_aaddr_1, RAT_rd_aaddr_2;
    logic [PADDR_L-1:0] RAT_rd_paddr_1, RAT_rd_paddr_2;


    //Reservation stations accessing logics
    RS_entry_t          RS_entry_in_1, RS_entry_in_2;
    logic               dispatch_ready_ALU_1, dispatch_ready_MUL_1, dispatch_ready_DIV_1;
    logic               dispatch_ready_LUI_1, dispatch_ready_MEM_1, dispatch_ready_BR_1;
    logic               dispatch_ready_ALU_2, dispatch_ready_MUL_2, dispatch_ready_DIV_2;
    logic               dispatch_ready_LUI_2, dispatch_ready_MEM_2, dispatch_ready_BR_2;
    logic               RS_ALU_full_1, RS_MUL_full_1, RS_DIV_full_1;
    logic               RS_LUI_full_1, RS_MEM_full_1, RS_BR_full_1;
    logic               RS_ALU_full_2, RS_MUL_full_2, RS_DIV_full_2;
    logic               RS_LUI_full_2, RS_MEM_full_2, RS_BR_full_2;
    logic               func_lui_ready, func_mem_ready, func_br_ready;
    logic               func_mul_ready, func_div_ready;
    logic               func_alu1_ready, func_alu2_ready;
    CDB_t               alu1_cdb, alu2_cdb, mul_cdb, div_cdb;
    CDB_t               lui_cdb, st_cdb, ld_cdb, br_cdb;


    // ROB accessing logics
    disp_rob_t            disp_rob_entry_1, disp_rob_entry_2;
    logic                 rob_enq_1, rob_enq_2;
    logic                 rob_deq_1, rob_deq_2; 
    logic [ROBADDR_L-1:0] rob_addr_1, rob_addr_2;
    logic                 rob_full_1, rob_empty_1;
    logic                 rob_full_2, rob_empty_2;

    // PRF accessing logics
    logic                   PRF_empty, PRF_almost_empty;
    logic                   PRF_full, PRF_almost_full; //from free list
    logic                   PRF_rs1_read_1, PRF_rs2_read_1;
    logic                   PRF_rs1_read_2, PRF_rs2_read_2;
    logic [PADDR_L-1:0]     PRF_rs1_addr_1, PRF_rs2_addr_1;
    logic [PADDR_L-1:0]     PRF_rs1_addr_2, PRF_rs2_addr_2;
    logic                   PRF_rs1_valid_1, PRF_rs2_valid_1;
    logic                   PRF_rs1_valid_2, PRF_rs2_valid_2;
    logic [31:0]            PRF_rs1_data_1, PRF_rs2_data_1;
    logic [31:0]            PRF_rs1_data_2, PRF_rs2_data_2;
    logic                   rd_commit_read_1, rd_commit_read_2;
    logic [PADDR_L-1:0]     rd_commit_addr_1, rd_commit_addr_2;
    logic                   rd_commit_valid_1, rd_commit_valid_2;
    logic [31:0]            rd_commit_data_1, rd_commit_data_2;
    rob_entry_t             rob_out_1, rob_out_2;

    
    //Sequential logic signals
    logic   [31:0]      pc, pc_next;

    if_id_stage_reg_t   if_id_reg, if_id_reg_next, if_id_reg_next2;

    id_dis_stage_reg_t  id_dis_reg_1, id_dis_reg_next_1;
    id_dis_stage_reg_t  id_dis_reg_2, id_dis_reg_next_2;
    RS_entry_t          RS_alu1_out, RS_alu1_out_next;
    RS_entry_t          RS_alu2_out, RS_alu2_out_next;
    RS_entry_t          RS_mul_out,  RS_mul_out_next;
    RS_entry_t          RS_div_out,  RS_div_out_next;
    RS_entry_t          RS_lui_out,  RS_lui_out_next;
    RS_entry_t          RS_mem_out,  RS_mem_out_next;
    RS_entry_t          RS_br_out,   RS_br_out_next;

    logic             RS_alu1_out_valid, RS_alu1_out_valid_next;
    logic             RS_alu2_out_valid, RS_alu2_out_valid_next;
    logic             RS_mul_out_valid,  RS_mul_out_valid_next;
    logic             RS_div_out_valid,  RS_div_out_valid_next;
    logic             RS_lui_out_valid,  RS_lui_out_valid_next;
    logic             RS_mem_out_valid,  RS_mem_out_valid_next;
    logic             RS_br_out_valid,   RS_br_out_valid_next;

    //MISC
    logic   alu1_cdb_rdy, alu2_cdb_rdy, mul_cdb_rdy, div_cdb_rdy;
    logic   lui_cdb_rdy, st_cdb_rdy, ld_cdb_rdy, br_cdb_rdy;
    CDB_t   cdb_main_1, cdb_main_2;

    logic   fetch_stall, i_need_resp, initialized;
    logic   flush_ufp;
    logic   dispatch_stall_1, dispatch_stall_2;
    logic   dispatch_stall;

    logic   instr_deq, instr_enq, instr_enq2;
    logic   instr_empty, instr_full;
    logic   instr_almost_empty, instr_almost_full;
    logic   instr_enq_reg;

    logic   mem_deq, mem_enq;
    logic   mem_empty, mem_full;
    logic   store_all_commited, store_commit;

    logic   [31:0]   ufp_addr_o;
    logic            ufp_rmask_o;
    logic   [255:0]  ufp_rdata_o;
    logic            ufp_resp_o;

    logic            ftq_stall;

    logic            ras_stall;
    logic            d_cache_en;
    logic            rs_mem_idle,sq_mem_idle,lq_mem_idle;
    assign           d_cache_en = !(rs_mem_idle && sq_mem_idle && lq_mem_idle) || RS_mem_out_valid;

    logic  [Q_INDEX-1:0]  funcbr_ftq_addr;
    ftq_entry_t          to_funcbr;


    //RVFI signals
    rvfi_entry rvfi_entry_decode_1, rvfi_entry_decode_reg_1;
    rvfi_entry rvfi_entry_decode_2, rvfi_entry_decode_reg_2;
    rvfi_entry rvfi_entry_dispatch_1;
    rvfi_entry rvfi_entry_dispatch_2;
    rvfi_entry rvfi_entry_rs_alu1, rvfi_entry_rs_alu1_reg;
    rvfi_entry rvfi_entry_rs_alu2, rvfi_entry_rs_alu2_reg;
    rvfi_entry rvfi_entry_rs_mul, rvfi_entry_rs_mul_reg;
    rvfi_entry rvfi_entry_rs_div, rvfi_entry_rs_div_reg;
    rvfi_entry rvfi_entry_rs_lui, rvfi_entry_rs_lui_reg;
    rvfi_entry rvfi_entry_rs_mem, rvfi_entry_rs_mem_reg;
    rvfi_entry rvfi_entry_rs_br, rvfi_entry_rs_br_reg;
    rvfi_entry rvfi_entry_func_alu1;
    rvfi_entry rvfi_entry_func_alu2;
    rvfi_entry rvfi_entry_func_mul;
    rvfi_entry rvfi_entry_func_div;
    rvfi_entry rvfi_entry_func_lui;
    rvfi_entry rvfi_entry_func_st;
    rvfi_entry rvfi_entry_func_ld;
    rvfi_entry rvfi_entry_func_br;
    rvfi_entry rvfi_entry_load_in,   rvfi_entry_load_out;
    rvfi_entry rvfi_entry_cdb_reg_1, rvfi_entry_cdb_reg_2;
    rvfi_entry rvfi_entry_commit_1,  rvfi_entry_commit_2;

    logic  debug_cg;
    logic stall_id_prf_out_1, stall_id_prf_out_2, decode_stall;

    assign debug_cg = (d_ufp_rmask != '0 || d_ufp_wmask != '0) && d_cache_en == '0; 

    // Stalling logic               maybe inlcude i_request here so we don't need that initialized logic (assuming that problem is due to i_need_resp going high on next cycle)
    always_comb begin
        flush_1 = rob_out_1.valid && rob_out_1.br_mispred;
        flush_2 = rob_out_2.valid && rob_out_2.br_mispred;
        flush   = flush_1 || flush_2;
        dispatch_stall = dispatch_stall_1 || dispatch_stall_2;
        instr_deq = ~dispatch_stall && !decode_stall;
        fetch_stall = (i_need_resp) || (instr_full && !instr_deq)|| flush || ftq_stall;  //  maybe add || (ftq_full && !ftq_deq)
        stall_fetch2 = dont_do_fetch2 || fetch_stall || (instr_almost_full && !instr_deq);

        //dispatch_stall output from dispatch stage
    end

    assign instr_enq = ~fetch_stall && initialized && if_id_reg_next.i_valid;     //stall will be high if queue is full rn so we should change that
    assign instr_enq2 = ~stall_fetch2 && initialized && if_id_reg_next2.i_valid;
                                                    
    // Sequential pipeline logic
    always_ff @(posedge clk) begin
        if (rst || flush) begin

            pc <= (rst) ? 32'haaaa9ff8 : pc_next;  // 32'haaaaa000 - 4

            if_id_reg    <= '0;
            id_dis_reg_1 <= '0;
            id_dis_reg_2 <= '0;
            RS_alu1_out  <= '0;
            RS_alu2_out  <= '0;
            RS_mul_out   <= '0;
            RS_div_out   <= '0;
            RS_lui_out   <= '0;
            RS_mem_out   <= '0;
            RS_br_out    <= '0;
            RS_alu1_out_valid <= '0;
            RS_alu2_out_valid <= '0;
            RS_mul_out_valid  <= '0;
            RS_div_out_valid  <= '0;
            RS_lui_out_valid  <= '0;
            RS_mem_out_valid  <= '0;
            RS_br_out_valid   <= '0;
            initialized       <= '0;
            instr_enq_reg     <= '0;
        end
        else begin
            if (initialized == 0) begin
                initialized <= '1;
            end

            if (!dispatch_stall  && !decode_stall) begin
                rvfi_entry_decode_reg_1 <= rvfi_entry_decode_1; 
                rvfi_entry_decode_reg_2 <= rvfi_entry_decode_2;
            end 
            pc <= pc_next;
            
            if_id_reg     <= if_id_reg_next;
            instr_enq_reg <= instr_enq;            

            if (!dispatch_stall && !decode_stall) id_dis_reg_1 <= id_dis_reg_next_1;
            if (!dispatch_stall && !decode_stall) id_dis_reg_2 <= id_dis_reg_next_2;


            if (func_alu1_ready) begin             
                RS_alu1_out            <= RS_alu1_out_next;
                rvfi_entry_rs_alu1_reg <= rvfi_entry_rs_alu1;
                RS_alu1_out_valid      <= RS_alu1_out_valid_next;
            end

            if (func_alu2_ready) begin             
                RS_alu2_out            <= RS_alu2_out_next;
                rvfi_entry_rs_alu2_reg <= rvfi_entry_rs_alu2;
                RS_alu2_out_valid      <= RS_alu2_out_valid_next;
            end

            if (func_mul_ready) begin  
                RS_mul_out            <= RS_mul_out_next;
                rvfi_entry_rs_mul_reg <= rvfi_entry_rs_mul;
                RS_mul_out_valid      <= RS_mul_out_valid_next;
            end

            if (func_div_ready) begin
                RS_div_out            <= RS_div_out_next;      
                rvfi_entry_rs_div_reg <= rvfi_entry_rs_div;
                RS_div_out_valid      <= RS_div_out_valid_next;
            end

            if (func_lui_ready) begin             
                RS_lui_out            <= RS_lui_out_next;
                rvfi_entry_rs_lui_reg <= rvfi_entry_rs_lui;
                RS_lui_out_valid      <= RS_lui_out_valid_next;
            end
            
            if (func_mem_ready) begin             
                RS_mem_out            <= RS_mem_out_next;
                rvfi_entry_rs_mem_reg <= rvfi_entry_rs_mem;
                RS_mem_out_valid      <= RS_mem_out_valid_next;
            end

            if (func_br_ready) begin             
                RS_br_out             <= RS_br_out_next;
                rvfi_entry_rs_br_reg  <= rvfi_entry_rs_br;
                RS_br_out_valid       <= RS_br_out_valid_next;
            end
        end
    end


    prefechter_nl prefechter_nl(
        .clk(clk),
        .rst(rst),
        .flush(flush || flush_ufp),

        .ufp_addr_i(i_ufp_addr),
        .ufp_rmask_i(i_ufp_rmask),
        .ufp_rdata_i(i_ufp_rdata),
        .ufp_resp_i(i_ufp_resp),
        .ufp_miss(ufp_miss),

        .ufp_resp_o,
        .ufp_rdata_o,
        .ufp_rmask_o,
        .ufp_addr_o
    );


    cache i_cache(
        .clk(clk),
        .rst(rst),

        .ufp_addr(ufp_addr_o),
        .ufp_rmask(ufp_rmask_o),
        .ufp_rdata(ufp_rdata_o),
        .ufp_resp(ufp_resp_o),
        .ufp_miss(ufp_miss),

        .dfp_addr(dfp_addr_i),
        .dfp_read(dfp_read_i),
        .dfp_write(dfp_write_i),
        .dfp_rdata(dfp_rdata_i),
        .dfp_wdata(dfp_wdata_i),
        .dfp_resp(dfp_resp_i)
    );

    cache_d d_cache(
        .clk(clk),
        .rst(rst),

        .ufp_addr(d_ufp_addr),
        .ufp_rmask(d_ufp_rmask),
        .ufp_wmask(d_ufp_wmask),
        .ufp_rdata(d_ufp_rdata),
        .ufp_wdata(d_ufp_wdata),
        .ufp_resp(d_ufp_resp),

        .dfp_addr(dfp_addr_d),
        .dfp_read(dfp_read_d),
        .dfp_write(dfp_write_d),
        .dfp_rdata(dfp_rdata_d),
        .dfp_wdata(dfp_wdata_d),
        .dfp_resp(dfp_resp_d),

        .d_cache_en(d_cache_en)
    );

    arbiter_pro arbiter(
        .clk(clk),
        .rst(rst),

        .dfp_addr_i (dfp_addr_i),
        .dfp_read_i (dfp_read_i),
        .dfp_write_i(dfp_write_i),
        .dfp_wdata_i(dfp_wdata_i),
        .dfp_rdata_i(dfp_rdata_i),
        .dfp_resp_i (dfp_resp_i),

        .dfp_addr_d (dfp_addr_d),
        .dfp_read_d (dfp_read_d),
        .dfp_write_d(dfp_write_d),
        .dfp_wdata_d(dfp_wdata_d),
        .dfp_rdata_d(dfp_rdata_d),
        .dfp_resp_d (dfp_resp_d),

        .bmem_addr,
        .bmem_read,
        .bmem_write,
        .bmem_wdata,
        .bmem_raddr,
        .bmem_rdata,
        .bmem_rvalid
    );
    
    //instruction fetch stage

    if_stage #(
        .PHT_ADDR_L(PHT_ADDR_L), 
        .FTQ_DEPTH(FTQ_DEPTH), 
        .RAS_HEIGHT(RAS_HEIGHT), 
        .RAS_ADDR_L(RAS_ADDR_L), 
        .Q_INDEX(Q_INDEX)
        ) 
        if_stage_i (

        .clk,
        .rst,
        .fetch_stall,
        .pc,
        .ufp_rdata(i_ufp_rdata),
        .ufp_resp(i_ufp_resp),
        .pc_next,
        .ufp_addr(i_ufp_addr),
        .ufp_rmask(i_ufp_rmask),
        .if_id_reg_next,
        .if_id_reg_next2,
        .i_need_resp,

        .flush(flush),
        .rob_commit(rob_out_1),
        .cdb(cdb_main_2),

        .flush_ufp,
        .ftq_stall,
        .dont_do_fetch2(dont_do_fetch2),
        .stall_fetch2(stall_fetch2),
        .ras_stall,
        .funcbr_ftq_addr,
        .to_funcbr,
        
        .rvfi_entry_commit(rvfi_entry_commit_1)
    );
    
    instr_queue_2ways  #(.DEPTH(INSTR_DEPTH)) instr_queue_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .enq1(instr_enq),
        .enq2(instr_enq2),
        .deq1(instr_deq),
        .deq2(instr_deq),
        .din1(if_id_reg_next),
        .din2(if_id_reg_next2),    
        .dout1(instr_queue_out_1),
        .dout2(instr_queue_out_2),
        .full(instr_full),
        .almost_full(instr_almost_full),
        .empty(instr_empty),
        .almost_empty(instr_almost_empty)
    );

    
    assign decode_stall = stall_id_prf_out_1 || stall_id_prf_out_2;


    id_stage #( .PADDR_L(PADDR_L)) id_stage_1(
        .if_id_reg        (instr_queue_out_1),
        .id_dis_reg_next  (id_dis_reg_next_1), 
        .rvfi_entry_decode(rvfi_entry_decode_1),
        .fifo_empty(instr_empty),

        .rs1_read   (RAT_rs1_read_1),
        .rs1_addr   (RAT_rs1_addr_1),  
        .rs1_renamed(RAT_rs1_renamed_1),
        .rs1_paddr  (RAT_rs1_paddr_1),
        .rs1_data   (RAT_rs1_data_1),

        .rs2_read   (RAT_rs2_read_1),
        .rs2_addr   (RAT_rs2_addr_1),
        .rs2_renamed(RAT_rs2_renamed_1),
        .rs2_paddr  (RAT_rs2_paddr_1),
        .rs2_data   (RAT_rs2_data_1),

        .rename_rd(RAT_rd_rename_1),
        .rd_paddr (RAT_rd_paddr_1),
        .rd_aaddr (RAT_rd_aaddr_1),

        .dispatch_stall(dispatch_stall),
        .stall_id_prf_out(stall_id_prf_out_1),
        .PRF_full (PRF_full),

        .rob_commit_entry_1(rob_out_1),
        .rob_commit_entry_2(rob_out_2),
        .rob_commit_data_1(rd_commit_data_1),
        .rob_commit_data_2(rd_commit_data_2)
    );

    id_stage #( .PADDR_L(PADDR_L)) id_stage_2(
        .if_id_reg        (instr_queue_out_2),
        .id_dis_reg_next  (id_dis_reg_next_2), 
        .rvfi_entry_decode(rvfi_entry_decode_2),
        .fifo_empty(instr_almost_empty),

        .rs1_read   (RAT_rs1_read_2),
        .rs1_addr   (RAT_rs1_addr_2),  
        .rs1_renamed(RAT_rs1_renamed_2),
        .rs1_paddr  (RAT_rs1_paddr_2),
        .rs1_data   (RAT_rs1_data_2),

        .rs2_read   (RAT_rs2_read_2),
        .rs2_addr   (RAT_rs2_addr_2),
        .rs2_renamed(RAT_rs2_renamed_2),
        .rs2_paddr  (RAT_rs2_paddr_2),
        .rs2_data   (RAT_rs2_data_2),

        .rename_rd(RAT_rd_rename_2),
        .rd_paddr (RAT_rd_paddr_2),
        .rd_aaddr (RAT_rd_aaddr_2),

        .dispatch_stall(dispatch_stall),
        .stall_id_prf_out(stall_id_prf_out_2),
        .PRF_full (PRF_almost_full),
        .rob_commit_entry_1(rob_out_1),
        .rob_commit_entry_2(rob_out_2),
        .rob_commit_data_1(rd_commit_data_1),
        .rob_commit_data_2(rd_commit_data_2)
    );

    dp_stage #(.PADDR_L(PADDR_L), .ROBADDR_L(ROBADDR_L)) dp_stage_1 (

        .clk(clk),
        .rst(rst),

        //RS station communication
        .dp_rs_reg_next(RS_entry_in_1),
        .dispatch_ready({dispatch_ready_BR_1, 
                         dispatch_ready_MEM_1, 
                         dispatch_ready_LUI_1, 
                         dispatch_ready_DIV_1, 
                         dispatch_ready_MUL_1, 
                         dispatch_ready_ALU_1}),

        .RS_full        ({RS_BR_full_1, 
                          RS_MEM_full_1, 
                          RS_LUI_full_1, 
                          RS_DIV_full_1, 
                          RS_MUL_full_1, 
                          RS_ALU_full_1}),

        .ROB_full(rob_full_1), //TODO update here


        .PRF_full (PRF_full),

        //ROB communication
        .disp_rob (disp_rob_entry_1),
        .rob_enq  (rob_enq_1),
        .rob_addr (rob_addr_1),

        //PRF communication
        .rs1_read (PRF_rs1_read_1),
        .rs1_addr (PRF_rs1_addr_1),
        .rs1_valid(PRF_rs1_valid_1),  
        .rs1_data (PRF_rs1_data_1),

        .rs2_read (PRF_rs2_read_1),
        .rs2_addr (PRF_rs2_addr_1),
        .rs2_valid(PRF_rs2_valid_1),
        .rs2_data (PRF_rs2_data_1),

        //decode communication
        .id_dis_reg    (id_dis_reg_1),
        .dispatch_stall(dispatch_stall_1),
        .stall_in(dispatch_stall_2),

        .cdb_main_1(cdb_main_1),
        .cdb_main_2(cdb_main_2),

        .rvfi_entry_decode_reg(rvfi_entry_decode_reg_1),
        .rvfi_entry_dispatch  (rvfi_entry_dispatch_1)
    );

    dp_stage #(.PADDR_L(PADDR_L), .ROBADDR_L(ROBADDR_L)) dp_stage_2 (
        .clk(clk),
        .rst(rst),

        //RS station communication
        .dp_rs_reg_next(RS_entry_in_2),
        .dispatch_ready({dispatch_ready_BR_2, 
                         dispatch_ready_MEM_2, 
                         dispatch_ready_LUI_2, 
                         dispatch_ready_DIV_2, 
                         dispatch_ready_MUL_2, 
                         dispatch_ready_ALU_2}),

        .RS_full        ({RS_BR_full_2, 
                          RS_MEM_full_2, 
                          RS_LUI_full_2, 
                          RS_DIV_full_2, 
                          RS_MUL_full_2, 
                          RS_ALU_full_2}),

        .ROB_full(rob_full_2), //TODO update here
        .PRF_full (PRF_almost_full),

        //ROB communication
        .disp_rob (disp_rob_entry_2),
        .rob_enq  (rob_enq_2),
        .rob_addr (rob_addr_2),

        //PRF communication
        .rs1_read (PRF_rs1_read_2),
        .rs1_addr (PRF_rs1_addr_2),
        .rs1_valid(PRF_rs1_valid_2),  
        .rs1_data (PRF_rs1_data_2),

        .rs2_read (PRF_rs2_read_2),
        .rs2_addr (PRF_rs2_addr_2),
        .rs2_valid(PRF_rs2_valid_2),
        .rs2_data (PRF_rs2_data_2),

        //decode communication
        .id_dis_reg    (id_dis_reg_2),
        .dispatch_stall(dispatch_stall_2),
        .stall_in (dispatch_stall_1),

        .cdb_main_1(cdb_main_1),
        .cdb_main_2(cdb_main_2),

        .rvfi_entry_decode_reg(rvfi_entry_decode_reg_2),
        .rvfi_entry_dispatch  (rvfi_entry_dispatch_2)
    );


    PRF #(.PADDR_L(PADDR_L)) PRF_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .rs1_read_1 (PRF_rs1_read_1),
        .rs1_addr_1 (PRF_rs1_addr_1),
        .rs1_valid_1(PRF_rs1_valid_1),  
        .rs1_data_1 (PRF_rs1_data_1),

        .rs2_read_1 (PRF_rs2_read_1),
        .rs2_addr_1 (PRF_rs2_addr_1),
        .rs2_valid_1(PRF_rs2_valid_1),
        .rs2_data_1 (PRF_rs2_data_1),

        .rs1_read_2 (PRF_rs1_read_2),
        .rs1_addr_2 (PRF_rs1_addr_2),
        .rs1_valid_2(PRF_rs1_valid_2),  
        .rs1_data_2 (PRF_rs1_data_2),

        .rs2_read_2 (PRF_rs2_read_2),
        .rs2_addr_2 (PRF_rs2_addr_2),
        .rs2_valid_2(PRF_rs2_valid_2),
        .rs2_data_2 (PRF_rs2_data_2),

        .rd_commit_read_1 (rd_commit_read_1),
        .rd_commit_addr_1 (rd_commit_addr_1),
        .rd_commit_valid_1(rd_commit_valid_1),
        .rd_commit_data_1 (rd_commit_data_1),

        .rd_commit_read_2 (rd_commit_read_2),
        .rd_commit_addr_2 (rd_commit_addr_2),
        .rd_commit_valid_2(rd_commit_valid_2),
        .rd_commit_data_2 (rd_commit_data_2),

        .rd_wb_addr_1 (cdb_main_1.rd_paddr),
        .rd_wb_data_1 (cdb_main_1.rd_data),
        .rd_wb_valid_1(cdb_main_1.valid && cdb_main_1.regf_we),

        .rd_wb_addr_2 (cdb_main_2.rd_paddr),
        .rd_wb_data_2 (cdb_main_2.rd_data),
        .rd_wb_valid_2(cdb_main_2.valid && cdb_main_2.regf_we)
    );

    RAT #(.PADDR_L(PADDR_L))   RAT_i (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        //rename interface
        .rd_addr_a_1(RAT_rd_aaddr_1),
        .rd_addr_p_1(RAT_rd_paddr_1),
        .rd_rename_1(RAT_rd_rename_1 && !dispatch_stall && !decode_stall),

        .rd_addr_a_2(RAT_rd_aaddr_2),
        .rd_addr_p_2(RAT_rd_paddr_2),
        .rd_rename_2(RAT_rd_rename_2 && !dispatch_stall && !decode_stall),


        //dispatch interface
        .rs1_read_1   (RAT_rs1_read_1),
        .rs1_addr_1   (RAT_rs1_addr_1),  
        .rs1_paddr_1  (RAT_rs1_paddr_1),
        .rs1_data_1   (RAT_rs1_data_1),
        .rs1_renamed_1(RAT_rs1_renamed_1),

        .rs1_read_2   (RAT_rs1_read_2),
        .rs1_addr_2   (RAT_rs1_addr_2),  
        .rs1_paddr_2  (RAT_rs1_paddr_2),
        .rs1_data_2   (RAT_rs1_data_2),
        .rs1_renamed_2(RAT_rs1_renamed_2),

        .rs2_read_1   (RAT_rs2_read_1),
        .rs2_addr_1   (RAT_rs2_addr_1),        
        .rs2_paddr_1  (RAT_rs2_paddr_1),
        .rs2_data_1   (RAT_rs2_data_1),
        .rs2_renamed_1(RAT_rs2_renamed_1),

        .rs2_read_2   (RAT_rs2_read_2),
        .rs2_addr_2   (RAT_rs2_addr_2),        
        .rs2_paddr_2  (RAT_rs2_paddr_2),
        .rs2_data_2   (RAT_rs2_data_2),
        .rs2_renamed_2(RAT_rs2_renamed_2),

        .rd_commit_1      (rd_commit_read_1),
        .rd_commit_paddr_1(rd_commit_addr_1),
        .rd_commit_data_1 (rd_commit_data_1),

        .rd_commit_2      (rd_commit_read_2),
        .rd_commit_paddr_2(rd_commit_addr_2),
        .rd_commit_data_2 (rd_commit_data_2),

        .rob_commit_1(rob_out_1),
        .rob_commit_2(rob_out_2)
    );

    ROB #(.ROBADDR_L(ROBADDR_L))   ROB_i (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .disp_rob_1(disp_rob_entry_1),
        .disp_rob_2(disp_rob_entry_2),
        .cdb1(cdb_main_1),
        .cdb2(cdb_main_2),

        .enq1(rob_enq_1),
        .enq2(rob_enq_2),
        .deq1(rob_deq_1),
        .deq2(rob_deq_2),

        .rob_addr_1(rob_addr_1),
        .rob_addr_2(rob_addr_2),

        .full (rob_full_1),
        .almost_full(rob_full_2),
        .empty(rob_empty_1),
        .almost_empty(rob_empty_2),

        .store_all_commited(store_all_commited),
        .store_commit(store_commit),

        .rob_out_1(rob_out_1),
        .rob_out_2(rob_out_2),

        .rvfi_entry_cdb_reg_1(rvfi_entry_cdb_reg_1),
        .rvfi_entry_cdb_reg_2(rvfi_entry_cdb_reg_2),
        .rvfi_entry_commit_1(rvfi_entry_commit_1),
        .rvfi_entry_commit_2(rvfi_entry_commit_2)
    );

    logic [63:0] total_branches, total_brs, total_jals, total_jalrs;
    logic [63:0] total_mispredicts, total_brs_mispredicts, total_jals_mispredicts, total_jalrs_mispredicts;

    always_ff @(posedge clk) begin
        if (rst) begin
            total_branches <= '0;
            total_brs <= '0;
            total_jals <= '0;
            total_jalrs <= '0;

            total_mispredicts <= '0;
            total_brs_mispredicts <= '0;
            total_jals_mispredicts <= '0;
            total_jalrs_mispredicts <= '0;

        end else if (rvfi_entry_commit_1.valid && (rob_out_1.inst_type != 3'd3 && rob_out_1.inst_type!=3'd0 )) begin //rob_out_1.inst_type == 3'd1 || rob_out_1.inst_type==3'd2 || rob_out_1.inst_type==3'd4
            total_branches <= total_branches + 64'd1;
            if (rob_out_1.br_mispred) begin
                total_mispredicts <= total_mispredicts + 64'd1;
            end

            if (rob_out_1.inst_type == 3'd1) begin
                total_brs <= total_brs + 64'd1;
                if (rob_out_1.br_mispred) begin
                    total_brs_mispredicts <= total_brs_mispredicts + 64'd1;
                end
            end

            if (rob_out_1.inst_type == 3'd2 || rob_out_1.inst_type == 3'd5) begin
                total_jals <= total_jals + 64'd1;
                if (rob_out_1.br_mispred) begin
                    total_jals_mispredicts <= total_jals_mispredicts + 64'd1;
                end
            end

            if (rob_out_1.inst_type == 3'd4 || rob_out_1.inst_type == 3'd6 || rob_out_1.inst_type == 3'd7) begin
                total_jalrs <= total_jalrs + 64'd1;
                if (rob_out_1.br_mispred) begin
                    total_jalrs_mispredicts <= total_jalrs_mispredicts + 64'd1;
                end
            end

        end
    end


    free_list #(.PADDR_L(PADDR_L)) free_list_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .enq1(rob_out_1.status && rob_out_1.inst_type != 3'd3 && rob_out_1.inst_type != 3'd1),
        .enq2(rob_out_2.status && rob_out_2.inst_type != 3'd3 && rob_out_2.inst_type != 3'd1),

        .deq1(RAT_rd_rename_1 && !dispatch_stall && !decode_stall),
        .deq2(RAT_rd_rename_2 && !dispatch_stall && !decode_stall),


        .next_addr1(RAT_rd_paddr_1),
        .next_addr2(RAT_rd_paddr_2),

        .full        (PRF_empty),
        .almost_full (PRF_almost_empty),
        .empty       (PRF_full),
        .almost_empty(PRF_almost_full)
    );

    res_station #( .RS_BIT(4)) res_station_ALU1(

        .clk(clk),
        .rst(rst),
        .flush(flush),
        .RS_entry_in(RS_entry_in_1),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready(dispatch_ready_ALU_1),
        .func_ready    (func_alu1_ready),
        .RS_entry_out  (RS_alu1_out_next),
        .RS_full       (RS_ALU_full_1),
        .RS_out_valid  (RS_alu1_out_valid_next),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch(rvfi_entry_dispatch_1),
        .rvfi_entry_rs      (rvfi_entry_rs_alu1)
    );

    res_station #( .RS_BIT(4)) res_station_ALU2(
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .RS_entry_in(RS_entry_in_2),


        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready(dispatch_ready_ALU_2),
        .func_ready    (func_alu2_ready),
        .RS_entry_out  (RS_alu2_out_next),
        .RS_full       (RS_ALU_full_2),
        .RS_out_valid  (RS_alu2_out_valid_next),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch(rvfi_entry_dispatch_2),
        .rvfi_entry_rs      (rvfi_entry_rs_alu2)
    );
    
    func_alu func_alu_1(   
        .RS_alu_out   (RS_alu1_out),
        .func_in_ready(RS_alu1_out_valid),
        .cdb_ready    (alu1_cdb_rdy),
        .cdb          (alu1_cdb),
        .func_ready   (func_alu1_ready),
        .rvfi_entry_rs_reg(rvfi_entry_rs_alu1_reg),
        .rvfi_entry_alu   (rvfi_entry_func_alu1)
    );

    func_alu func_alu_2(   
        .RS_alu_out   (RS_alu2_out),
        .func_in_ready(RS_alu2_out_valid),
        .cdb_ready    (alu2_cdb_rdy),
        .cdb          (alu2_cdb),
        .func_ready   (func_alu2_ready),
        .rvfi_entry_rs_reg(rvfi_entry_rs_alu2_reg),
        .rvfi_entry_alu   (rvfi_entry_func_alu2)
    );

    res_station_2way #( .RS_BIT(RS_BIT)) res_station_MUL(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_entry_in1(RS_entry_in_1),
        .RS_entry_in2(RS_entry_in_2),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready1(dispatch_ready_MUL_1),
        .dispatch_ready2(dispatch_ready_MUL_2),

        .func_ready  (func_mul_ready),
        .RS_entry_out(RS_mul_out_next),
        .RS_out_valid(RS_mul_out_valid_next),

        .RS_full1(RS_MUL_full_1),
        .RS_full2(RS_MUL_full_2),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch1(rvfi_entry_dispatch_1),
        .rvfi_entry_dispatch2(rvfi_entry_dispatch_2),
        .rvfi_entry_rs       (rvfi_entry_rs_mul)
    );    

    func_mul func_mul_i(   
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_out       (RS_mul_out),
        .func_in_ready(RS_mul_out_valid),
        .cdb_ready    (mul_cdb_rdy),
        .cdb          (mul_cdb),
        .func_ready   (func_mul_ready),

        .rvfi_entry_rs_reg(rvfi_entry_rs_mul_reg),
        .rvfi_entry_mul   (rvfi_entry_func_mul)
    );


    res_station_2way #( .RS_BIT(RS_BIT)) res_station_DIV(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_entry_in1(RS_entry_in_1),
        .RS_entry_in2(RS_entry_in_2),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready1(dispatch_ready_DIV_1),
        .dispatch_ready2(dispatch_ready_DIV_2),

        .func_ready  (func_div_ready),
        .RS_entry_out(RS_div_out_next),
        .RS_out_valid(RS_div_out_valid_next),

        .RS_full1(RS_DIV_full_1),
        .RS_full2(RS_DIV_full_2),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch1(rvfi_entry_dispatch_1),
        .rvfi_entry_dispatch2(rvfi_entry_dispatch_2),
        .rvfi_entry_rs       (rvfi_entry_rs_div)
    );    

    func_div func_div_i(   
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_out       (RS_div_out),
        .func_in_ready(RS_div_out_valid),
        .cdb_ready    (div_cdb_rdy),
        .cdb          (div_cdb),
        .func_ready   (func_div_ready),

        .rvfi_entry_rs_reg(rvfi_entry_rs_div_reg),
        .rvfi_entry_div   (rvfi_entry_func_div)
    );

    res_station_2way #( .RS_BIT(RS_BIT)) res_station_LUI(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_entry_in1(RS_entry_in_1),
        .RS_entry_in2(RS_entry_in_2),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready1(dispatch_ready_LUI_1),
        .dispatch_ready2(dispatch_ready_LUI_2),

        .func_ready  (func_lui_ready),
        .RS_entry_out(RS_lui_out_next),
        .RS_out_valid(RS_lui_out_valid_next),

        .RS_full1(RS_LUI_full_1),
        .RS_full2(RS_LUI_full_2),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch1(rvfi_entry_dispatch_1),
        .rvfi_entry_dispatch2(rvfi_entry_dispatch_2),
        .rvfi_entry_rs       (rvfi_entry_rs_lui)
    );

    func_lui func_lui_i(   
        .RS_lui_out   (RS_lui_out),
        .func_in_ready(RS_lui_out_valid),
        .cdb_ready    (lui_cdb_rdy),
        .cdb          (lui_cdb),
        .func_ready   (func_lui_ready),
        .rvfi_entry_rs_reg(rvfi_entry_rs_lui_reg),
        .rvfi_entry_lui   (rvfi_entry_func_lui)
    );

    res_station_mem #( .RS_BIT(RS_BIT)) res_station_MEM(
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .RS_entry_in1(RS_entry_in_1),
        .RS_entry_in2(RS_entry_in_2),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready1(dispatch_ready_MEM_1),
        .dispatch_ready2(dispatch_ready_MEM_2),

        .RS_full1(RS_MEM_full_1),
        .RS_full2(RS_MEM_full_2),

        .func_ready  (func_mem_ready),
        .RS_entry_out(RS_mem_out_next),        
        .RS_out_valid(RS_mem_out_valid_next),

        .dispatch_stall(dispatch_stall),


        .rvfi_entry_dispatch1(rvfi_entry_dispatch_1),
        .rvfi_entry_dispatch2(rvfi_entry_dispatch_2),
        .rvfi_entry_rs       (rvfi_entry_rs_mem),
        .rs_mem_idle         (rs_mem_idle)
    );  //A reservation stations that output in order, for only load/store use

    logic   load_enq, store_enq, load_deq, store_deq, load_out_valid, store_out_valid;
    load_entry_t load_din, load_dout;
    store_entry_t store_din, store_dout;
    logic   load_full, store_full;
    store_entry_t   store_entry [MEM_DEPTH];
    logic [MEM_DEPTH-1 : 0] store_entry_valid;
    logic [MEM_INDEX-1 : 0] load_out_idx, load_deq_idx;
    logic [MEM_INDEX:0]     store_head, store_tail;

    mem_queue_in_controller #(.MEM_DEPTH(MEM_DEPTH)) mem_queue_in_controller_i (
        .RS_mem_out(RS_mem_out),
        .func_in_ready(RS_mem_out_valid),

        .cdb(st_cdb),
        .cdb_ready(st_cdb_rdy),

        .load_enq(load_enq),
        .store_enq(store_enq),
        .load_din(load_din),
        .store_din(store_din),

        .load_full(load_full),
        .store_full(store_full),

        .store_entry(store_entry),
        .store_entry_valid(store_entry_valid),

        .func_ready(func_mem_ready),

        .rvfi_entry_rs_reg(rvfi_entry_rs_mem_reg),
        .rvfi_entry_store(rvfi_entry_func_st),

        .rvfi_entry_load_in(rvfi_entry_load_in)
    );

    load_queue #(.MEM_DEPTH(MEM_DEPTH), .MEM_INDEX(MEM_INDEX)) load_queue_i (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .load_enq(load_enq),
        .load_deq(load_deq),
        .load_deq_idx(load_deq_idx),
        .load_din(load_din),

        .store_head(store_head),
        .store_deq(store_deq),

        .load_dout(load_dout),
        .load_out_valid(load_out_valid),
        .load_out_idx(load_out_idx),
        .load_full(load_full),

        .rvfi_entry_load_in(rvfi_entry_load_in),
        .rvfi_entry_load_out(rvfi_entry_load_out),

        .lq_mem_idle(lq_mem_idle)
    );

    store_queue #(.MEM_DEPTH(MEM_DEPTH), .MEM_INDEX(MEM_INDEX)) store_queue_i (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .store_enq(store_enq),
        .store_deq(store_deq),
        .store_din(store_din),

        .store_entry(store_entry),
        .store_entry_valid(store_entry_valid),
        .store_head(store_head),
        .store_tail(store_tail),

        .store_dout(store_dout),
        .store_out_valid(store_out_valid),
        .store_full(store_full),

        .store_all_commited(store_all_commited),
        .store_commit(store_commit),

        .sq_mem_idle(sq_mem_idle)
    );

    mem_queue_out_controller #(.MEM_DEPTH(MEM_DEPTH), .MEM_INDEX(MEM_INDEX)) mem_queue_out_controller_i (
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .load_dout(load_dout),
        .store_dout(store_dout),
        .load_out_idx(load_out_idx),

        .load_out_valid(load_out_valid),
        .store_out_valid(store_out_valid),

        .load_deq(load_deq),
        .load_deq_idx(load_deq_idx),
        .store_deq(store_deq),

        .d_ufp_addr(d_ufp_addr),
        .d_ufp_rmask(d_ufp_rmask),
        .d_ufp_wmask(d_ufp_wmask),
        .d_ufp_wdata(d_ufp_wdata),
        .d_ufp_rdata(d_ufp_rdata),
        .d_ufp_resp(d_ufp_resp),

        .cdb(ld_cdb),


        .rvfi_entry_load_out(rvfi_entry_load_out),
        .rvfi_entry_load    (rvfi_entry_func_ld)
    );

    res_station_2way #( .RS_BIT(RS_BIT)) res_station_BR(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .RS_entry_in1(RS_entry_in_1),
        .RS_entry_in2(RS_entry_in_2),

        .cdb_1(cdb_main_1),
        .cdb_2(cdb_main_2),

        .dispatch_ready1(dispatch_ready_BR_1),
        .dispatch_ready2(dispatch_ready_BR_2),


        .func_ready  (func_br_ready),
        .RS_entry_out(RS_br_out_next),        
        .RS_out_valid(RS_br_out_valid_next),

        .RS_full1(RS_BR_full_1),
        .RS_full2(RS_BR_full_2),

        .dispatch_stall(dispatch_stall),

        .rvfi_entry_dispatch1(rvfi_entry_dispatch_1),
        .rvfi_entry_dispatch2(rvfi_entry_dispatch_2),
        .rvfi_entry_rs       (rvfi_entry_rs_br)
    );


    func_br #(.Q_INDEX(Q_INDEX)) func_br_i(  
        .funcbr_ftq_addr(funcbr_ftq_addr),
        .to_funcbr    (to_funcbr),
        .RS_br_out    (RS_br_out),
        .func_in_ready(RS_br_out_valid),
        .cdb_ready    (br_cdb_rdy),
        .cdb          (br_cdb),
        .func_ready   (func_br_ready),
        .rvfi_entry_rs_reg(rvfi_entry_rs_br_reg),
        .rvfi_entry_br    (rvfi_entry_func_br)
    );

    cdb cdb_i(
        .clk(clk),
        .rst(rst),
        .flush(flush),

        .alu1_cdb(alu1_cdb),
        .alu2_cdb(alu2_cdb),
        .mul_cdb (mul_cdb),
        .div_cdb (div_cdb),
        .lui_cdb (lui_cdb),
        .st_cdb  (st_cdb),
        .ld_cdb  (ld_cdb),
        .br_cdb  (br_cdb),

        .out_cdb_1(cdb_main_1),
        .out_cdb_2(cdb_main_2),

        .alu1_cdb_rdy(alu1_cdb_rdy),
        .alu2_cdb_rdy(alu2_cdb_rdy),
        .mul_cdb_rdy (mul_cdb_rdy),
        .div_cdb_rdy (div_cdb_rdy),
        .lui_cdb_rdy (lui_cdb_rdy),
        .st_cdb_rdy  (st_cdb_rdy),
        .ld_cdb_rdy  (ld_cdb_rdy),
        .br_cdb_rdy  (br_cdb_rdy),

        .rvfi_entry_alu1(rvfi_entry_func_alu1),
        .rvfi_entry_alu2(rvfi_entry_func_alu2),
        .rvfi_entry_mul (rvfi_entry_func_mul),
        .rvfi_entry_div (rvfi_entry_func_div),
        .rvfi_entry_lui (rvfi_entry_func_lui),
        .rvfi_entry_st  (rvfi_entry_func_st),
        .rvfi_entry_ld  (rvfi_entry_func_ld),
        .rvfi_entry_br  (rvfi_entry_func_br),
        
        .rvfi_entry_cdb_reg_1(rvfi_entry_cdb_reg_1),
        .rvfi_entry_cdb_reg_2(rvfi_entry_cdb_reg_2)
    );


    endmodule : cpu