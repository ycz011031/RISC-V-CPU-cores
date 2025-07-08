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
            if (entry_valid[i]) begin
                new_depend_idx[i] = load_entry[i].depend_idx;
                if (store_deq) begin
                    new_depend_idx[i][store_head[MEM_INDEX-1:0]] = '0;
                end
                if (new_depend_idx[i] == '0) begin
                    load_out_valid  = 1'b1;
                    load_dout  =  load_entry[i];
                    rvfi_entry_load_out =  rvfi_load_entry[i];
                    load_out_idx       = MEM_INDEX'(unsigned'(i));
                end
            end
        end
    end

endmodule : load_queue