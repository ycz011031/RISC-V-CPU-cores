module func_lui
import rv32i_types::*;
(   
    input   RS_entry_t RS_lui_out,

    input   logic   func_in_ready,
    input   logic   cdb_ready,
    output  CDB_t   cdb,
    output  logic   func_ready,

    input   rvfi_entry rvfi_entry_rs_reg,
    output  rvfi_entry rvfi_entry_lui
);

    always_comb begin
        func_ready = cdb_ready;
        if (func_in_ready) begin
            cdb.rd_paddr = RS_lui_out.rd_paddr;
            cdb.rob_addr = RS_lui_out.rob_addr;
            cdb.rd_data  = RS_lui_out.rs2_data;
            cdb.regf_we  = RS_lui_out.regf_we;
            cdb.valid    = '1;
            cdb.br_mispred = '0;
            cdb.br_target ='0;
            cdb.br_only_taken = '0;
            cdb.ftq_addr = RS_lui_out.ftq_addr;

            rvfi_entry_lui = rvfi_entry_rs_reg;
            rvfi_entry_lui.rd_wdata = RS_lui_out.rs2_data;
            rvfi_entry_lui.rs1_addr = '0;
            rvfi_entry_lui.rs2_addr = '0;
        end else begin
            cdb            = '0;
            rvfi_entry_lui = '0;
        end
    end

endmodule : func_lui