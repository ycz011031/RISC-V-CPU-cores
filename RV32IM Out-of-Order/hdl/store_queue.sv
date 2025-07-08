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
    output  logic                   store_full,

    output  logic                   store_all_commited,
    input   logic                   store_commit,

    output  logic                   sq_mem_idle

    // input   rvfi_entry              rvfi_entry_store_queue_in,
    // output  rvfi_entry              rvfi_entry_store_queue_out
);
    logic store_empty;
    logic [MEM_INDEX:0]  store_commit_head;
    logic [MEM_DEPTH-1:0] store_committed;
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
        store_out_valid = (!store_empty) && store_committed[store_head[MEM_INDEX-1:0]] && store_entry_valid[store_head[MEM_INDEX-1:0]];
        store_dout = store_empty ? store_din : store_entry[store_head[MEM_INDEX-1:0]];
    end

endmodule : store_queue