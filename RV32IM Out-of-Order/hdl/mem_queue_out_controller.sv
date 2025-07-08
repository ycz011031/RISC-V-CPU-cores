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

    output  logic           load_deq,
    output  logic [MEM_INDEX-1 : 0] load_deq_idx,
    output  logic           store_deq,

    output  logic [31:0]    d_ufp_addr,
    output  logic [3:0]     d_ufp_rmask,
    output  logic [3:0]     d_ufp_wmask,
    output  logic [31:0]    d_ufp_wdata,
    input   logic [31:0]    d_ufp_rdata,
    input   logic           d_ufp_resp,

    output  CDB_t           cdb,
    // input   logic           cdb_ready,

    input   rvfi_entry      rvfi_entry_load_out,
    output  rvfi_entry      rvfi_entry_load
);

logic   load_busy, store_busy, mem_busy;
logic   [31:0] mem_read_data;

load_entry_t   load_reg;
store_entry_t  store_reg;
rvfi_entry rvfi_entry_load_out_reg;

assign mem_busy = load_busy || store_busy;
//assign d_cache_en = store_dout.mem_wmask || load_dout.mem_rmask || store_busy || load_busy;

always_ff @(posedge clk) begin
    if (rst||flush) begin
        load_busy <= '0;
        store_busy <= '0;
        load_reg <= '0;
        load_deq_idx <= '0;
        store_reg <= '0;
        rvfi_entry_load_out_reg <= '0;
    end else begin
        if (!mem_busy) begin
            if (store_out_valid) begin
                store_busy <= '1;
                store_reg <= store_dout;
            end else if (load_out_valid) begin
                load_busy <= '1;
                load_reg <= load_dout;
                load_deq_idx <= load_out_idx;
                rvfi_entry_load_out_reg <= rvfi_entry_load_out;
            end
        end else begin
            if (load_busy && d_ufp_resp) begin
                load_busy <= '0;
            end 
            if (store_busy && d_ufp_resp) begin
                store_busy <= '0;
            end
        end
    end
end

load_entry_t   load_data;
store_entry_t  store_data;

always_comb begin
    load_deq = '0;
    store_deq = '0;
    d_ufp_addr  = '0;
    d_ufp_rmask = '0;
    d_ufp_wmask = '0;
    d_ufp_wdata = '0;
    cdb = '0;
    rvfi_entry_load = '0;
    load_data = '0;
    store_data = '0;
    if (store_busy || (!mem_busy && store_out_valid)) begin
        store_data = store_busy? store_reg : store_dout; 
        if (d_ufp_resp) begin
            store_deq = '1;
        end else begin
            d_ufp_addr  = (flush)? '0 : {store_data.mem_addr[31:2],2'b00};
            d_ufp_wmask = (flush)? '0 : store_data.mem_wmask;
            d_ufp_wdata = store_data.mem_wdata;
        end
    end else if (load_busy || (!mem_busy && load_out_valid)) begin
        load_data = load_busy? load_reg : load_dout; 
        if (d_ufp_resp) begin
            load_deq = '1;
            mem_read_data = d_ufp_rdata;
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
            d_ufp_addr  = (flush)? '0 : {load_data.mem_addr[31:2],2'b00};
            d_ufp_rmask = (flush)? '0 : load_data.mem_rmask;
        end
    end

end

endmodule : mem_queue_out_controller