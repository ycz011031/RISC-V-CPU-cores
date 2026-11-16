module load_queue 
import rv32i_types::*;
#(
            parameter               MEM_DEPTH     = 8,
            parameter               MEM_INDEX = 3
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,

    input   logic                   load_enq,
    input   logic                   load_deq,
    input   logic [MEM_INDEX-1 : 0] load_deq_idx,
    input   load_entry_t            load_din,

    input   logic [MEM_INDEX:0]     store_head,
    input   logic                   store_deq,

    input   logic                   load_inflight,      // the load the D-cache is answering:
    input   logic [MEM_INDEX-1 : 0] load_inflight_idx,  // not picked again

    output  load_entry_t            load_dout,
    output  logic                   load_out_valid,
    output  logic [MEM_INDEX-1 : 0] load_out_idx,
    output  logic                   load_full,

    input   rvfi_entry              rvfi_entry_load_in,
    output  rvfi_entry              rvfi_entry_load_out,

    output  logic                   lq_mem_idle
);

    load_entry_t                load_entry [MEM_DEPTH];
    rvfi_entry                  rvfi_load_entry [MEM_DEPTH];
    logic   [MEM_DEPTH-1:0]         entry_valid;

    logic   [MEM_INDEX : 0]     next_empty;
    assign lq_mem_idle = entry_valid == '0;

    assign load_full = (next_empty == unsigned'((MEM_INDEX+1)'(MEM_DEPTH)));

    logic   [MEM_DEPTH-1:0] new_depend_idx[MEM_DEPTH-1:0];

    // age matrix: older[i][j] = entry j was already in the queue when entry i came in.
    // The D-cache gets the oldest ready load (the old pick, the highest ready index, served
    // the newest loads first, so the load at the ROB head waited behind younger ones).
`ifdef OOO_LQ_NO_AGE
    localparam bit AGE_ORDER = 1'b0;    // old pick: highest ready index
`else
    localparam bit AGE_ORDER = 1'b1;
`endif
    logic   [MEM_DEPTH-1:0] older [MEM_DEPTH];
    logic   [MEM_DEPTH-1:0] ready;
    // A reused slot holds the newest load, so its column is cleared in every row: stale bits
    // from the slot's previous load would make two loads each wait for the other.
    always_ff @(posedge clk) begin
        if (load_enq && !(rst || flush)) begin
            for (integer i = 0; i < MEM_DEPTH; i++) older[i][next_empty[MEM_INDEX-1:0]] <= 1'b0;
            older[next_empty[MEM_INDEX-1:0]] <= entry_valid;
        end
    end

    // load input logic and CDB logic 
    always_ff @( posedge clk ) begin : rs_update
        if (rst||flush) begin
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                load_entry[i] <= '0;
                rvfi_load_entry[i] <= '0;
                entry_valid[i] <= 1'b0;
            end
        end
        else begin
            if (load_enq) begin
                load_entry[next_empty]   <= load_din;
                if (store_deq) begin
                    load_entry[next_empty].depend_idx[store_head[MEM_INDEX-1:0]] <= '0;
                end
                rvfi_load_entry[next_empty]   <= rvfi_entry_load_in;
                entry_valid[next_empty] <= 1'b1;
            end
            if (load_deq) begin
                entry_valid[load_deq_idx] <= 1'b0;
            end
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                if (store_deq) begin
                    load_entry[i].depend_idx[store_head[MEM_INDEX-1:0]] <= '0;
                end
            end

        end
    end

    always_comb begin
        load_out_valid = 1'b0;
        load_dout = '0;
        load_out_idx = '0;
        next_empty = unsigned'((MEM_INDEX+1)'(MEM_DEPTH));
        rvfi_entry_load_out = '0;
        for (integer i = '0; i < MEM_DEPTH; i++) begin
            if (!entry_valid[i]) begin
                next_empty = unsigned'((MEM_INDEX+1)'(i));
            end
        end
        if (load_enq) begin
            if (load_din.depend_idx == '0) begin
                load_out_valid  = 1'b1;
                load_dout  =  load_din;
                rvfi_entry_load_out =  rvfi_entry_load_in;
                load_out_idx       = MEM_INDEX'(unsigned'(next_empty));
            end
        end
        for (integer i = '0; i < MEM_DEPTH; i++) begin
            new_depend_idx[i] = load_entry[i].depend_idx;
            if (store_deq) begin
                new_depend_idx[i][store_head[MEM_INDEX-1:0]] = '0;
            end
            ready[i] = entry_valid[i] && new_depend_idx[i] == '0 &&
                       !(load_inflight && load_inflight_idx == MEM_INDEX'(unsigned'(i)));
        end
        for (integer i = '0; i < MEM_DEPTH; i++) begin
            if (ready[i] && (!AGE_ORDER || (older[i] & ready) == '0)) begin     // oldest ready load
                load_out_valid  = 1'b1;
                load_dout  =  load_entry[i];
                rvfi_entry_load_out =  rvfi_load_entry[i];
                load_out_idx       = MEM_INDEX'(unsigned'(i));
            end
        end
    end

endmodule : load_queue