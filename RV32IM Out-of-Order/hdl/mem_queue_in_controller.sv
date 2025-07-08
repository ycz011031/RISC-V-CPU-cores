module mem_queue_in_controller
import rv32i_types::*;
#(
            parameter               MEM_DEPTH     = 8
)(
    input   RS_entry_t      RS_mem_out,
    input   logic           func_in_ready,

    output  CDB_t           cdb,
    input   logic           cdb_ready,

    output  logic           load_enq,
    output  logic           store_enq,
    output  load_entry_t    load_din,
    output  store_entry_t   store_din,

    input   logic           load_full,
    input   logic           store_full,

    input   store_entry_t   store_entry [MEM_DEPTH],
    input   logic   [MEM_DEPTH-1:0]        store_entry_valid,

    output  logic           func_ready,

    input   rvfi_entry      rvfi_entry_rs_reg,
    output  rvfi_entry      rvfi_entry_store,
    output  rvfi_entry      rvfi_entry_load_in
);

    logic is_store;
    logic [31:0] mem_wdata;
    logic [3:0] mem_wmask, mem_rmask;
    logic [2:0] mem_op;

    always_comb begin
        is_store = RS_mem_out.rs2_use;
        mem_op = RS_mem_out.op_type[2:0];
        rvfi_entry_store = rvfi_entry_rs_reg;
        rvfi_entry_load_in = rvfi_entry_rs_reg;
        cdb = '0;
        mem_wmask = '0;
        mem_rmask = '0;
        mem_wdata = '0;
        if (is_store) begin
            load_enq = '0;
            func_ready = !store_full && cdb_ready;
            store_enq = func_in_ready && func_ready;
            load_din = '0;
            store_din.rob_addr        = RS_mem_out.rob_addr;   //for load instruction wb use
            store_din.order           = RS_mem_out.order;
            store_din.mem_op          = mem_op;
            if (unsigned'($countones(RS_mem_out.rs1_data + RS_mem_out.imm)) == '0) begin
                store_din.mem_addr        = '0;
            end else begin
                store_din.mem_addr        = RS_mem_out.rs1_data + RS_mem_out.imm;
            end
            unique case (mem_op)
                store_f3_sb:                mem_wmask = 4'b0001 << store_din.mem_addr[1:0];
                store_f3_sh:                mem_wmask = 4'b0011 << store_din.mem_addr[1:0];
                store_f3_sw:                mem_wmask = 4'b1111;
                default:                    mem_wmask = '0;
            endcase
            store_din.mem_wmask       = mem_wmask;
            unique case (mem_op)
                store_f3_sb:                mem_wdata[8 *store_din.mem_addr[1:0] +: 8 ] = RS_mem_out.rs2_data[7 :0];
                store_f3_sh:                mem_wdata[16*store_din.mem_addr[1]   +: 16] = RS_mem_out.rs2_data[15:0];
                store_f3_sw:                mem_wdata = RS_mem_out.rs2_data;
                default:                    mem_wdata = '0;
            endcase
            store_din.mem_wdata       = mem_wdata;
            store_din.mem_addr     = {store_din.mem_addr[31:2],2'b00};
            cdb.rd_paddr = '0;
            cdb.rd_data  = '0;
            cdb.regf_we  = '0;
            cdb.rob_addr = RS_mem_out.rob_addr;
            cdb.valid    = func_in_ready && !store_full;
            cdb.br_mispred= '0;
            cdb.br_target ='0;
            rvfi_entry_store.mem_addr     = {store_din.mem_addr[31:2],2'b00};
            rvfi_entry_store.mem_wmask    = store_din.mem_wmask;
            rvfi_entry_store.mem_wdata    = store_din.mem_wdata;
        end else begin
            func_ready = !load_full;
            load_enq = func_in_ready && func_ready;
            store_enq = '0;
            store_din = '0;
            load_din.rob_addr         = RS_mem_out.rob_addr;
            load_din.rd_paddr         = RS_mem_out.rd_paddr;
            load_din.order            = RS_mem_out.order;
            load_din.mem_op           = mem_op;
            if (unsigned'($countones(RS_mem_out.rs1_data + RS_mem_out.imm)) == '0) begin
                load_din.mem_addr        = '0;
            end else begin
                load_din.mem_addr        = RS_mem_out.rs1_data + RS_mem_out.imm;
            end            unique case (mem_op)
                load_f3_lb, load_f3_lbu:    mem_rmask = 4'b0001 << load_din.mem_addr[1:0];
                load_f3_lh, load_f3_lhu:    mem_rmask = 4'b0011 << load_din.mem_addr[1:0];
                load_f3_lw:                 mem_rmask = 4'b1111;
                default:                    mem_rmask = '0;
            endcase
            load_din.mem_rmask        = mem_rmask;
            load_din.depend_idx = '0;
            for (integer i = '0; i < MEM_DEPTH; i++) begin
                // if (store_entry_valid[i]) begin
                //     load_din.depend_idx[i] = '1;
                // end else begin
                //     load_din.depend_idx[i] = '0;
                // end
                if (store_entry_valid[i] && store_entry[i].mem_addr == load_din.mem_addr) begin
                    load_din.depend_idx[i] = '1;
                end else begin
                    load_din.depend_idx[i] = '0;
                end
            end
            rvfi_entry_load_in.mem_addr    = {load_din.mem_addr[31:2],2'b00};
            rvfi_entry_load_in.mem_rmask   = load_din.mem_rmask;
        end
    end


endmodule : mem_queue_in_controller