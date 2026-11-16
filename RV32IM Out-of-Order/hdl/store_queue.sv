module store_queue 
import rv32i_types::*;
#(
            parameter               MEM_DEPTH     = 8,
            parameter               MEM_INDEX = 3
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,

    input   logic                   store_enq,
    input   logic                   store_deq,
    input   store_entry_t           store_din,

    output  store_entry_t           store_entry [MEM_DEPTH],
    output  logic [MEM_DEPTH-1:0]   store_entry_valid,
    output  logic [MEM_INDEX:0]     store_head,
    output  logic [MEM_INDEX:0]     store_tail,

    output  store_entry_t           store_dout,
    output  logic                   store_out_valid,
    output  store_entry_t           store_next_dout,        // the entry after the head, for the
    output  logic                   store_next_valid,       // D-cache response cycle of the head
    output  logic                   store_full,

    output  logic                   store_all_commited,
    input   logic                   store_commit,

    output  logic                   sq_mem_idle,

    input   CDB_t                   cdb_1, cdb_2,           // late store data
    output  logic   [31:0]          commit_wdata,           // the store committing now: write data (RVFI)
    output  logic   [31:0]          commit_rdata            // ... and its register value (RVFI rs2_rdata)

    // input   rvfi_entry              rvfi_entry_store_queue_in,
    // output  rvfi_entry              rvfi_entry_store_queue_out
);
    logic store_empty;
    logic [MEM_INDEX:0]  store_commit_head;
    logic [MEM_DEPTH-1:0] store_committed;
    logic [MEM_INDEX:0]  store_hn;
    // RS input logic and CDB logic 
    assign sq_mem_idle = store_entry_valid == '0;
    always_ff @( posedge clk ) begin : rs_update
        if (rst) begin
            store_head <= '0;
            store_tail <= '0;
            store_commit_head <= '0;
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                store_entry[i] <= '0;
                store_entry_valid[i] <= '0;
            end
        end else if (flush) begin
            store_head <= store_head;
            store_tail <= store_commit_head;
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                if (!store_committed[i]) begin
                    store_entry[i] <= '0;
                    store_entry_valid[i] <= '0;
                end
            end
        end
        else begin
            // pick up store data that was not ready when the address went in
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                if (store_entry_valid[i] && !store_entry[i].data_valid) begin
                    if (cdb_1.valid && cdb_1.regf_we && cdb_1.rd_paddr == store_entry[i].data_paddr) begin
                        store_entry[i].mem_wdata  <= cdb_1.rd_data;
                        store_entry[i].data_valid <= 1'b1;
                    end else if (cdb_2.valid && cdb_2.regf_we && cdb_2.rd_paddr == store_entry[i].data_paddr) begin
                        store_entry[i].mem_wdata  <= cdb_2.rd_data;
                        store_entry[i].data_valid <= 1'b1;
                    end
                end
            end
            if (store_enq) begin
                store_entry [store_tail[MEM_INDEX-1:0]]   <= store_din;
                store_entry_valid[store_tail[MEM_INDEX-1:0]] <= '1;
                store_committed[store_tail[MEM_INDEX-1:0]] <= '0;
                store_tail <= store_tail + 1'b1;
            end
            if (store_deq) begin
                store_entry_valid[store_head[MEM_INDEX-1:0]] <= '0;
                store_head <= store_head + 1'b1;
            end
            if (store_commit) begin
                store_committed[store_commit_head[MEM_INDEX-1:0]] <= '1;
                store_commit_head <= store_commit_head + 1'b1;
            end
        end
    end
    
    always_comb begin
        
        store_full = (store_head[MEM_INDEX] != store_tail[MEM_INDEX]) && (store_head[MEM_INDEX-1:0] == store_tail[MEM_INDEX-1:0]);
        store_empty = store_head == store_tail;
        store_all_commited = store_commit_head == store_tail;
        // Start store operation only when (1) store queue not empty (2) store entry at store_head dependency all resolved (3) ROB already committed it
        store_out_valid = (!store_empty) && store_committed[store_head[MEM_INDEX-1:0]] && store_entry_valid[store_head[MEM_INDEX-1:0]]
                          && store_entry[store_head[MEM_INDEX-1:0]].data_valid;
        commit_rdata = store_entry[store_commit_head[MEM_INDEX-1:0]].mem_wdata;
        commit_wdata = store_wdata(store_entry[store_commit_head[MEM_INDEX-1:0]].mem_op,
                                   store_entry[store_commit_head[MEM_INDEX-1:0]].mem_wmask, commit_rdata);
        store_dout = store_empty ? store_din : store_entry[store_head[MEM_INDEX-1:0]];
        store_dout.mem_wdata = store_wdata(store_dout.mem_op, store_dout.mem_wmask, store_dout.mem_wdata);
        store_hn = store_head + 1'b1;
        store_next_valid = (!store_empty) && (store_hn != store_tail) && store_committed[store_hn[MEM_INDEX-1:0]]
                           && store_entry_valid[store_hn[MEM_INDEX-1:0]] && store_entry[store_hn[MEM_INDEX-1:0]].data_valid;
        store_next_dout = store_entry[store_hn[MEM_INDEX-1:0]];
        store_next_dout.mem_wdata = store_wdata(store_next_dout.mem_op, store_next_dout.mem_wmask, store_next_dout.mem_wdata);
    end

`ifndef SYNTHESIS
    // the data's producer is older than the store, so it has broadcast before the store commits
    always @(posedge clk) if (!rst && store_commit && !store_entry[store_commit_head[MEM_INDEX-1:0]].data_valid)
        $error("store_queue: store committed without its data (order %0d)", store_entry[store_commit_head[MEM_INDEX-1:0]].order);
`endif

endmodule : store_queue