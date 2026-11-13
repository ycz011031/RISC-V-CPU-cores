module res_station_2way
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

    input   logic   dispatch_ready1,
    input   logic   dispatch_ready2,
    input   logic   func_ready,


    output  logic   RS_full1,
    output  logic   RS_full2,
    output  logic   RS_out_valid,

    input   logic   dispatch_stall,

    input   RS_entry_t RS_entry_in1,
    input   RS_entry_t RS_entry_in2,
    output  RS_entry_t RS_entry_out,

    input   rvfi_entry rvfi_entry_dispatch1,
    input   rvfi_entry rvfi_entry_dispatch2,
    output  rvfi_entry rvfi_entry_rs
);

    localparam DEPTH = 2 ** RS_BIT;

    RS_entry_t RS_entry   [DEPTH];
    rvfi_entry rvfi_entry_reg [DEPTH];
    logic      entry_valid[DEPTH];

    logic   [RS_BIT : 0]   next_empty;
    logic   [RS_BIT : 0]   next_next_empty;
    logic   [RS_BIT-1 : 0] out_idx;

    // RS full logic
    assign RS_full1  = (next_empty == unsigned'((RS_BIT+1)'(DEPTH)));
    assign RS_full2 =  (next_next_empty == unsigned'((RS_BIT+1)'(DEPTH)));

    // RS output logic 
    always_comb begin
        RS_out_valid = 1'b0;
        RS_entry_out = '0;
        out_idx = '0;
        next_empty = unsigned'((RS_BIT+1)'(DEPTH));
        next_next_empty = unsigned'((RS_BIT+1)'(DEPTH));

        rvfi_entry_rs = '0;
        for (integer i = '0; i < DEPTH; i++) begin
            if (entry_valid[i]) begin
                if ((!RS_entry[i].rs1_use || RS_entry[i].rs1_valid) && (!RS_entry[i].rs2_use || RS_entry[i].rs2_valid)) begin
                    RS_out_valid  = 1'b1;
                    RS_entry_out  =  RS_entry[i];
                    rvfi_entry_rs =  rvfi_entry_reg[i];
                    out_idx       = RS_BIT'(unsigned'(i));
                end
            end else begin
                if (next_empty != unsigned'((RS_BIT+1)'(DEPTH))) begin
                    next_next_empty = next_empty;
                    next_empty = unsigned'((RS_BIT+1)'(i));
                end else begin
                    next_empty = unsigned'((RS_BIT+1)'(i));
                end
            end
        end
    end

    // RS input logic and CDB logic 
    always_ff @( posedge clk ) begin : rs_update
        if (rst||flush) begin
            for (integer i = '0; i < DEPTH; i++) begin
                RS_entry[i] <= '0;
                rvfi_entry_reg[i] <= '0;
                entry_valid[i] <= 1'b0;
            end
        end
        else begin
            for (integer i = '0; i < DEPTH; i++) begin
                if (entry_valid[i]) begin
                    // Wakeup is applied to a copy and written back as one whole-element
                    // NBA. Same behavior as per-field NBAs, but Vivado xsim can drop
                    // field-select NBAs into unpacked arrays of structs.
                    automatic RS_entry_t e = RS_entry[i];
                    automatic rvfi_entry r = rvfi_entry_reg[i];
                    automatic logic wake = 1'b0;
                    if (RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_1.valid && RS_entry[i].rs1_paddr == cdb_1.rd_paddr && cdb_1.regf_we) begin
                        e.rs1_valid   = 1'b1;
                        wake = 1'b1;
                        e.rs1_data    = cdb_1.rd_data;
                        r.rs1_rdata = cdb_1.rd_data;
                    end
                    if (RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_1.valid && RS_entry[i].rs2_paddr == cdb_1.rd_paddr && cdb_1.regf_we) begin
                        e.rs2_valid   = 1'b1;
                        wake = 1'b1;
                        e.rs2_data    = cdb_1.rd_data;
                        r.rs2_rdata = cdb_1.rd_data;
                    end
                    if (RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_2.valid && RS_entry[i].rs1_paddr == cdb_2.rd_paddr && cdb_2.regf_we) begin
                        e.rs1_valid   = 1'b1;
                        wake = 1'b1;
                        e.rs1_data    = cdb_2.rd_data;
                        r.rs1_rdata = cdb_2.rd_data;
                    end
                    if (RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_2.valid && RS_entry[i].rs2_paddr == cdb_2.rd_paddr && cdb_2.regf_we) begin
                        e.rs2_valid   = 1'b1;
                        wake = 1'b1;
                        e.rs2_data    = cdb_2.rd_data;
                        r.rs2_rdata = cdb_2.rd_data;
                    end
                    if (wake) begin
                        RS_entry[i]       <= e;
                        rvfi_entry_reg[i] <= r;
                    end
                end
            end
            if (dispatch_ready1&& !dispatch_stall) begin
                RS_entry  [next_empty]   <= RS_entry_in1;
                entry_valid[next_empty] <= 1'b1;
                rvfi_entry_reg[next_empty]   <= rvfi_entry_dispatch1;
            end
            if (dispatch_ready2&& !dispatch_stall) begin
                RS_entry  [next_next_empty]   <= RS_entry_in2;
                entry_valid[next_next_empty] <= 1'b1;
                rvfi_entry_reg[next_next_empty]   <= rvfi_entry_dispatch2;
            end
            // if (!dispatch_stall) begin
            //     case ({dispatch_ready1, dispatch_ready2})
            //         2'b11: begin
            //             RS_entry  [next_empty]   <= RS_entry_in1;
            //             entry_valid[next_empty] <= 1'b1;
            //             rvfi_entry_reg[next_empty]   <= rvfi_entry_dispatch1;
            //             RS_entry  [next_next_empty[RS_BIT-1:0]]   <= RS_entry_in2;
            //             entry_valid[next_next_empty[RS_BIT-1:0]] <= 1'b1;
            //             rvfi_entry_reg[next_next_empty[RS_BIT-1:0]]   <= rvfi_entry_dispatch2;
            //             tail <= tail + 2'd2;
            //         end
            //         2'b10: begin
            //             RS_entry  [next_empty]   <= RS_entry_in1;
            //             entry_valid[next_empty] <= 1'b1;RS_entry_in1
            //             rvfi_entry_reg[next_empty]   <= rvfi_entry_dispatch1;
            //             tail <= tail + 2'd1;
            //         end
            //         2'b01: begin
            //             RS_entry  [next_empty]   <= RS_entry_in2;
            //             entry_valid[next_empty] <= 1'b1;
            //             rvfi_entry_reg[next_empty]   <= rvfi_entry_dispatch2;
            //             tail <= tail + 2'd1;
            //         end
            //         default: ;
            //     endcase
            // end
            if (func_ready && RS_out_valid) begin
                entry_valid[out_idx] <= 1'b0;
            end
        end
    end
    
endmodule : res_station_2way
