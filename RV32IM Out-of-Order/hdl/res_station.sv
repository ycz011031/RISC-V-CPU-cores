module res_station
import rv32i_types::*;
#(
    parameter   RS_BIT = 4
)
(   
    input   logic   clk,
    input   logic   rst,    
    input   logic   flush,

    input   CDB_t   cdb_1,
    input   CDB_t   cdb_2,

    input   logic   dispatch_ready,
    input   logic   func_ready,    
    output  logic   RS_full,
    output  logic   RS_out_valid,

    input   logic   dispatch_stall,

    input   RS_entry_t RS_entry_in,
    output  RS_entry_t RS_entry_out,

    input   rvfi_entry rvfi_entry_dispatch,
    output  rvfi_entry rvfi_entry_rs
);

    localparam DEPTH = 2 ** RS_BIT;

    RS_entry_t RS_entry   [DEPTH];
    rvfi_entry rvfi_entry_reg [DEPTH];
    logic      entry_valid[DEPTH];

    logic   [RS_BIT : 0]   next_empty;
    logic   [RS_BIT-1 : 0] out_idx;

    logic   rs1_cdb1_forwarding[DEPTH];
    logic   rs2_cdb1_forwarding[DEPTH];
    logic   rs1_cdb2_forwarding[DEPTH];
    logic   rs2_cdb2_forwarding[DEPTH];

    // RS full logic
    assign RS_full = (next_empty == unsigned'((RS_BIT+1)'(DEPTH)));

    // RS output logic 
    always_comb begin
        RS_out_valid = 1'b0;
        RS_entry_out = 'x;
        out_idx = '0;
        next_empty = unsigned'((RS_BIT+1)'(DEPTH));
        rvfi_entry_rs = '0;
        for (integer i = '0; i < DEPTH; i++) begin
            rs1_cdb1_forwarding[i] = RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_1.valid && RS_entry[i].rs1_paddr == cdb_1.rd_paddr && cdb_1.regf_we;
            rs2_cdb1_forwarding[i] = RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_1.valid && RS_entry[i].rs2_paddr == cdb_1.rd_paddr && cdb_1.regf_we;
            rs1_cdb2_forwarding[i] = RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_2.valid && RS_entry[i].rs1_paddr == cdb_2.rd_paddr && cdb_2.regf_we;
            rs2_cdb2_forwarding[i] = RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_2.valid && RS_entry[i].rs2_paddr == cdb_2.rd_paddr && cdb_2.regf_we;
            if (entry_valid[i]) begin
                if ((!RS_entry[i].rs1_use || RS_entry[i].rs1_valid || rs1_cdb1_forwarding[i] || rs1_cdb2_forwarding[i]) && (!RS_entry[i].rs2_use || RS_entry[i].rs2_valid || rs2_cdb1_forwarding[i] || rs2_cdb2_forwarding[i])) begin
                    RS_out_valid  = 1'b1;
                    RS_entry_out  =  RS_entry[i];
                    rvfi_entry_rs =  rvfi_entry_reg[i];
                    if (rs1_cdb1_forwarding[i]) begin
                        RS_entry_out.rs1_valid   = 1'b1;
                        RS_entry_out.rs1_data    = cdb_1.rd_data;
                        rvfi_entry_rs.rs1_rdata = cdb_1.rd_data;
                    end
                    if (rs2_cdb1_forwarding[i]) begin
                        RS_entry_out.rs2_valid   = 1'b1;
                        RS_entry_out.rs2_data    = cdb_1.rd_data;
                        rvfi_entry_rs.rs2_rdata = cdb_1.rd_data;
                    end
                    if (rs1_cdb2_forwarding[i]) begin
                        RS_entry_out.rs1_valid   = 1'b1;
                        RS_entry_out.rs1_data    = cdb_2.rd_data;
                        rvfi_entry_rs.rs1_rdata = cdb_2.rd_data;
                    end
                    if (rs2_cdb2_forwarding[i]) begin
                        RS_entry_out.rs2_valid   = 1'b1;
                        RS_entry_out.rs2_data    = cdb_2.rd_data;
                        rvfi_entry_rs.rs2_rdata = cdb_2.rd_data;
                    end
                    out_idx       = RS_BIT'(unsigned'(i));
                end
            end else begin
                next_empty = unsigned'((RS_BIT+1)'(i));
            end
        end
    end

    // RS input logic and CDB logic 
    always_ff @( posedge clk ) begin : rs_update
        if (rst||flush) begin
            for (integer i = '0; i < DEPTH; i++) begin
                //RS_entry[i] <= '0;
                //rvfi_entry_reg[i] <= '0;
                entry_valid[i] <= 1'b0;
            end
        end
        else begin
            for (integer i = '0; i < DEPTH; i++) begin
                if (entry_valid[i]) begin
                    if (rs1_cdb1_forwarding[i]) begin
                        RS_entry[i].rs1_valid   <= 1'b1;
                        RS_entry[i].rs1_data    <= cdb_1.rd_data;
                        rvfi_entry_reg[i].rs1_rdata <= cdb_1.rd_data;
                    end
                    if (rs2_cdb1_forwarding[i]) begin
                        RS_entry[i].rs2_valid   <= 1'b1;
                        RS_entry[i].rs2_data    <= cdb_1.rd_data;
                        rvfi_entry_reg[i].rs2_rdata <= cdb_1.rd_data;
                    end
                    if (rs1_cdb2_forwarding[i]) begin
                        RS_entry[i].rs1_valid   <= 1'b1;
                        RS_entry[i].rs1_data    <= cdb_2.rd_data;
                        rvfi_entry_reg[i].rs1_rdata <= cdb_2.rd_data;
                    end
                    if (rs2_cdb2_forwarding[i]) begin
                        RS_entry[i].rs2_valid   <= 1'b1;
                        RS_entry[i].rs2_data    <= cdb_2.rd_data;
                        rvfi_entry_reg[i].rs2_rdata <= cdb_2.rd_data;
                    end
                end
            end
            if (dispatch_ready&& !dispatch_stall) begin
                RS_entry  [next_empty]   <= RS_entry_in;
                entry_valid[next_empty] <= 1'b1;
                rvfi_entry_reg[next_empty]   <= rvfi_entry_dispatch;
            end
            if (func_ready && RS_out_valid) begin
                entry_valid[out_idx] <= 1'b0;
            end
        end
    end
    
endmodule : res_station