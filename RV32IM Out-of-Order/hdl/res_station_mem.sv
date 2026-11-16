module res_station_mem
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

    input   logic dispatch_stall,

    input   RS_entry_t RS_entry_in1,
    input   RS_entry_t RS_entry_in2,
    output  RS_entry_t RS_entry_out,


    input   rvfi_entry rvfi_entry_dispatch1,
    input   rvfi_entry rvfi_entry_dispatch2,
    output  rvfi_entry rvfi_entry_rs,

    output  logic      rs_mem_idle
);

    localparam DEPTH = 2 ** RS_BIT;

    RS_entry_t RS_entry   [DEPTH];
    rvfi_entry rvfi_entry_reg [DEPTH];
    logic      [DEPTH-1:0]  entry_valid;
    assign rs_mem_idle = (entry_valid == '0);

    // Only stores use rs2 here (their data). With STORE_SPLIT a store issues once its
    // address operand is ready; its data follows into the store queue (see
    // mem_queue_in_controller / store_queue), so younger loads are not held behind it.
`ifdef OOO_NO_STORE_SPLIT
    localparam bit STORE_SPLIT = 1'b0;
`else
    localparam bit STORE_SPLIT = 1'b1;
`endif

    logic   [RS_BIT : 0]   head, tail;
    logic   [RS_BIT : 0]   head_next, tail_next;

    assign head_next = head + 1'b1;
    assign tail_next = tail + 1'b1;

    logic   rs1_cdb1_forwarding[DEPTH];
    logic   rs2_cdb1_forwarding[DEPTH];
    logic   rs1_cdb2_forwarding[DEPTH];
    logic   rs2_cdb2_forwarding[DEPTH];

    // RS full logic
    assign RS_full1 = (head[RS_BIT] != tail[RS_BIT]) && (head[RS_BIT-1:0] == tail[RS_BIT-1:0]);
    assign RS_full2 = (head[RS_BIT] != tail_next[RS_BIT]) && (head[RS_BIT-1:0] == tail_next[RS_BIT-1:0]) || RS_full1;

    // RS output logic 
    always_comb begin
        RS_out_valid = 1'b0;
        RS_entry_out = '0;
        rvfi_entry_rs = '0;
        for (integer i = '0; i < DEPTH; i++) begin
            rs1_cdb1_forwarding[i] = RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_1.valid && RS_entry[i].rs1_paddr == cdb_1.rd_paddr && cdb_1.regf_we;
            rs2_cdb1_forwarding[i] = RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_1.valid && RS_entry[i].rs2_paddr == cdb_1.rd_paddr && cdb_1.regf_we;
            rs1_cdb2_forwarding[i] = RS_entry[i].rs1_use && !RS_entry[i].rs1_valid && cdb_2.valid && RS_entry[i].rs1_paddr == cdb_2.rd_paddr && cdb_2.regf_we;
            rs2_cdb2_forwarding[i] = RS_entry[i].rs2_use && !RS_entry[i].rs2_valid && cdb_2.valid && RS_entry[i].rs2_paddr == cdb_2.rd_paddr && cdb_2.regf_we;
        end
        if (entry_valid[head[RS_BIT-1:0]]) begin
            if ((!RS_entry[head[RS_BIT-1:0]].rs1_use || RS_entry[head[RS_BIT-1:0]].rs1_valid || rs1_cdb1_forwarding[head[RS_BIT-1:0]] || rs1_cdb2_forwarding[head[RS_BIT-1:0]]) && (STORE_SPLIT || !RS_entry[head[RS_BIT-1:0]].rs2_use || RS_entry[head[RS_BIT-1:0]].rs2_valid || rs2_cdb1_forwarding[head[RS_BIT-1:0]] || rs2_cdb2_forwarding[head[RS_BIT-1:0]])) begin
                RS_out_valid  = 1'b1;
                RS_entry_out  =  RS_entry[head[RS_BIT-1:0]];
                rvfi_entry_rs =  rvfi_entry_reg[head[RS_BIT-1:0]];
                if (rs1_cdb1_forwarding[head[RS_BIT-1:0]]) begin
                    RS_entry_out.rs1_valid   = 1'b1;
                    RS_entry_out.rs1_data    = cdb_1.rd_data;
                    rvfi_entry_rs.rs1_rdata = cdb_1.rd_data;
                end
                if (rs2_cdb1_forwarding[head[RS_BIT-1:0]]) begin
                    RS_entry_out.rs2_valid   = 1'b1;
                    RS_entry_out.rs2_data    = cdb_1.rd_data;
                    rvfi_entry_rs.rs2_rdata = cdb_1.rd_data;
                end
                if (rs1_cdb2_forwarding[head[RS_BIT-1:0]]) begin
                    RS_entry_out.rs1_valid   = 1'b1;
                    RS_entry_out.rs1_data    = cdb_2.rd_data;
                    rvfi_entry_rs.rs1_rdata = cdb_2.rd_data;
                end
                if (rs2_cdb2_forwarding[head[RS_BIT-1:0]]) begin
                    RS_entry_out.rs2_valid   = 1'b1;
                    RS_entry_out.rs2_data    = cdb_2.rd_data;
                    rvfi_entry_rs.rs2_rdata = cdb_2.rd_data;
                end
            end
        end
    end

    // RS input logic and CDB logic 
    always_ff @( posedge clk ) begin : rs_update
        if (rst||flush) begin
            head <= '0;
            tail <= '0;
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
                    if (rs1_cdb1_forwarding[i]) begin
                        e.rs1_valid   = 1'b1;
                        e.rs1_data    = cdb_1.rd_data;
                        r.rs1_rdata = cdb_1.rd_data;
                    end
                    if (rs2_cdb1_forwarding[i]) begin
                        e.rs2_valid   = 1'b1;
                        e.rs2_data    = cdb_1.rd_data;
                        r.rs2_rdata = cdb_1.rd_data;
                    end
                    if (rs1_cdb2_forwarding[i]) begin
                        e.rs1_valid   = 1'b1;
                        e.rs1_data    = cdb_2.rd_data;
                        r.rs1_rdata = cdb_2.rd_data;
                    end
                    if (rs2_cdb2_forwarding[i]) begin
                        e.rs2_valid   = 1'b1;
                        e.rs2_data    = cdb_2.rd_data;
                        r.rs2_rdata = cdb_2.rd_data;
                    end
                    if (rs1_cdb1_forwarding[i] || rs2_cdb1_forwarding[i] || rs1_cdb2_forwarding[i] || rs2_cdb2_forwarding[i]) begin
                        RS_entry[i]       <= e;
                        rvfi_entry_reg[i] <= r;
                    end
                end
            end
            if (!dispatch_stall) begin
                case ({dispatch_ready1, dispatch_ready2})
                    2'b11: begin
                        RS_entry  [tail[RS_BIT-1:0]]   <= RS_entry_in1;
                        entry_valid[tail[RS_BIT-1:0]] <= 1'b1;
                        rvfi_entry_reg[tail[RS_BIT-1:0]]   <= rvfi_entry_dispatch1;
                        RS_entry  [tail_next[RS_BIT-1:0]]   <= RS_entry_in2;
                        entry_valid[tail_next[RS_BIT-1:0]] <= 1'b1;
                        rvfi_entry_reg[tail_next[RS_BIT-1:0]]   <= rvfi_entry_dispatch2;
                        tail <= tail + 2'd2;
                    end
                    2'b10: begin
                        RS_entry  [tail[RS_BIT-1:0]]   <= RS_entry_in1;
                        entry_valid[tail[RS_BIT-1:0]] <= 1'b1;
                        rvfi_entry_reg[tail[RS_BIT-1:0]]   <= rvfi_entry_dispatch1;
                        tail <= tail + 2'd1;
                    end
                    2'b01: begin
                        RS_entry  [tail[RS_BIT-1:0]]   <= RS_entry_in2;
                        entry_valid[tail[RS_BIT-1:0]] <= 1'b1;
                        rvfi_entry_reg[tail[RS_BIT-1:0]]   <= rvfi_entry_dispatch2;
                        tail <= tail + 2'd1;
                    end
                    default: ;
                endcase
            end
            if (func_ready && RS_out_valid) begin
                entry_valid[head[RS_BIT-1:0]] <= 1'b0;
                head <= head + 1'b1;
            end
        end
    end
    
endmodule : res_station_mem