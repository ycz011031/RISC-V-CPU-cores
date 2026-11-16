module mem_queue_out_controller
import rv32i_types::*;
#(
            parameter               MEM_DEPTH     = 8,
            parameter               MEM_INDEX = 3
)(
    input   logic           clk,
    input   logic           rst,
    input   logic           flush,

    input   load_entry_t    load_dout,
    input   store_entry_t   store_dout,
    input   logic   [MEM_INDEX-1 : 0]  load_out_idx,

    input   logic           load_out_valid,
    input   logic           store_out_valid,
    input   store_entry_t   store_next_dout,        // the store after the store-queue head
    input   logic           store_next_valid,

    output  logic           load_deq,
    output  logic [MEM_INDEX-1 : 0] load_deq_idx,   // also: the load in flight (load queue skips it)
    output  logic           load_inflight,
    output  logic           store_deq,

    output  logic [31:0]    d_ufp_addr,
    output  logic [3:0]     d_ufp_rmask,
    output  logic [3:0]     d_ufp_wmask,
    output  logic [31:0]    d_ufp_wdata,
    input   logic [31:0]    d_ufp_rdata,
    input   logic           d_ufp_resp,

    output  CDB_t           cdb,

    input   rvfi_entry      rvfi_entry_load_out,
    output  rvfi_entry      rvfi_entry_load
);

// One D-cache access in flight. With PIPELINED the next access is presented in the
// response cycle of the current one (the D-cache has ACCEPT_ON_RESP = 1), so hits
// stream one per cycle; otherwise one access every two cycles. The next access comes
// from the queues as if the current one had left: the store after the store-queue
// head, or a load other than the one being answered. Stores go first.
`ifdef OOO_DCACHE_NO_PIPE
localparam bit PIPELINED = 1'b0;
`else
localparam bit PIPELINED = 1'b1;
`endif

logic   load_busy, store_busy, mem_busy;
logic   [31:0] mem_read_data;

load_entry_t   load_reg;
store_entry_t  store_reg;
rvfi_entry rvfi_entry_load_out_reg;

logic          resp_now, free, take_st, take_ld, st_c_valid;
store_entry_t  st_c;

assign mem_busy      = load_busy || store_busy;
assign load_inflight = load_busy;
assign resp_now      = mem_busy && d_ufp_resp;
assign free          = !mem_busy || (PIPELINED && resp_now);
assign st_c_valid    = store_busy ? store_next_valid : store_out_valid;
assign st_c          = store_busy ? store_next_dout  : store_dout;
assign take_st       = free && !flush && st_c_valid;
assign take_ld       = free && !flush && !st_c_valid && load_out_valid;

always_ff @(posedge clk) begin
    if (rst||flush) begin
        load_busy <= '0;
        store_busy <= '0;
        load_reg <= '0;
        load_deq_idx <= '0;
        store_reg <= '0;
        rvfi_entry_load_out_reg <= '0;
    end else if (take_st) begin
        store_busy <= '1;
        load_busy  <= '0;
        store_reg  <= st_c;
    end else if (take_ld) begin
        load_busy  <= '1;
        store_busy <= '0;
        load_reg   <= load_dout;
        load_deq_idx <= load_out_idx;
        rvfi_entry_load_out_reg <= rvfi_entry_load_out;
    end else if (resp_now) begin
        load_busy  <= '0;
        store_busy <= '0;
    end
end

always_comb begin
    load_deq = '0;
    store_deq = '0;
    d_ufp_addr  = '0;
    d_ufp_rmask = '0;
    d_ufp_wmask = '0;
    d_ufp_wdata = '0;
    cdb = '0;
    rvfi_entry_load = '0;
    mem_read_data = d_ufp_rdata;

    // the access in flight: answered now, or still presented
    if (store_busy) begin
        if (d_ufp_resp) begin
            store_deq = '1;
        end else begin
            d_ufp_addr  = (flush)? '0 : {store_reg.mem_addr[31:2],2'b00};
            d_ufp_wmask = (flush)? '0 : store_reg.mem_wmask;
            d_ufp_wdata = store_reg.mem_wdata;
        end
    end else if (load_busy) begin
        if (d_ufp_resp) begin
            load_deq = '1;
            cdb.rd_paddr = load_reg.rd_paddr;
            cdb.regf_we  = '1;
            cdb.rob_addr = load_reg.rob_addr;
            cdb.valid    = '1;
            cdb.br_mispred= '0;
            cdb.br_target ='0;

            unique case (load_reg.mem_op)
                load_f3_lb  : cdb.rd_data = {{24{mem_read_data[7 +8 *load_reg.mem_addr[1:0]]}}, mem_read_data[8 *load_reg.mem_addr[1:0] +: 8 ]};
                load_f3_lbu : cdb.rd_data = {{24{1'b0}}                          , mem_read_data[8 *load_reg.mem_addr[1:0] +: 8 ]};
                load_f3_lh  : cdb.rd_data = {{16{mem_read_data[15+16*load_reg.mem_addr[1]  ]}}, mem_read_data[16*load_reg.mem_addr[1]   +: 16]};
                load_f3_lhu : cdb.rd_data = {{16{1'b0}}                          , mem_read_data[16*load_reg.mem_addr[1]   +: 16]};
                load_f3_lw  : cdb.rd_data = mem_read_data;
                default     : cdb.rd_data  = '0;
            endcase

            //RVFI load wb entry
            rvfi_entry_load              = rvfi_entry_load_out_reg;
            rvfi_entry_load.mem_rdata    = mem_read_data;
            rvfi_entry_load.rd_wdata     = cdb.rd_data;
        end else begin
            d_ufp_addr  = (flush)? '0 : {load_reg.mem_addr[31:2],2'b00};
            d_ufp_rmask = (flush)? '0 : load_reg.mem_rmask;
        end
    end

    // the next access (idle, or in the response cycle when pipelined)
    if (take_st) begin
        d_ufp_addr  = {st_c.mem_addr[31:2],2'b00};
        d_ufp_wmask = st_c.mem_wmask;
        d_ufp_wdata = st_c.mem_wdata;
    end else if (take_ld) begin
        d_ufp_addr  = {load_dout.mem_addr[31:2],2'b00};
        d_ufp_rmask = load_dout.mem_rmask;
    end
end

endmodule : mem_queue_out_controller
