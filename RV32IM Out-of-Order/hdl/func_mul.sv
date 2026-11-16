module func_mul
import rv32i_types::*;
#(
    parameter int NUM_MUL = 1          // sequential multipliers working in parallel
)
(
    input    logic              clk,
    input    logic              rst,
    input    logic              flush,

    input    RS_entry_t         RS_out,
    input    logic              func_in_ready,
    input    logic              cdb_ready,
    output   CDB_t              cdb,
    output   logic              func_ready,

    input    rvfi_entry         rvfi_entry_rs_reg,
    output   rvfi_entry         rvfi_entry_mul
);

/**********************************************************************************
A bank of NUM_MUL sequential multipliers (DW_mult_seq / gen_mult_seq, 5 cycles).
An op from the input register starts on the lowest free unit, so up to NUM_MUL
ops are in flight. Finished units share the one CDB port: the lowest-index
finished unit drives it, and a unit is freed when its result is granted.
NUM_MUL = 1 behaves exactly like the original single-unit design.
***********************************************************************************/

localparam int SLOT_W = (NUM_MUL > 1) ? $clog2(NUM_MUL) : 1;

logic rst_n;
assign rst_n = ~(rst||flush);

logic mul_hold;
assign mul_hold = '0;

// ---- operand preparation (shared: a unit samples a/b only on its start) ----
logic [31:0] rs1_v, rs2_v, rs1_inv, rs2_inv;
logic [31:0] a_mul, b_mul;
assign rs1_v   = RS_out.rs1_data;
assign rs2_v   = RS_out.rs2_data;
assign rs1_inv = (~rs1_v)+32'd1;
assign rs2_inv = (~rs2_v)+32'd1;

always_comb begin
    unique case (RS_out.op_type[1:0])
        2'b00, 2'b01: begin             // mul, mulh: |a| * |b|
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = (RS_out.rs2_data[31])? rs2_inv : rs2_v;
        end
        2'b10: begin                    // mulhsu: |a| * b
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = rs2_v;
        end
        2'b11: begin                    // mulhu
            a_mul = rs1_v;
            b_mul = rs2_v;
        end
    endcase
end

// ---- units ------------------------------------------------------------------
logic [NUM_MUL-1:0]  slot_busy;         // unit holds an op (running or waiting for the CDB)
logic [NUM_MUL-1:0]  slot_start;
logic [NUM_MUL-1:0]  slot_complete;
logic [63:0]         slot_product [NUM_MUL];
RS_entry_t           slot_inst    [NUM_MUL];
rvfi_entry           slot_rvfi    [NUM_MUL];

genvar g;
generate
    for (g = 0; g < NUM_MUL; g++) begin : g_unit
// Synopsys DesignWare IP is only used when USE_SYNOPSYS_DW is defined.
// Otherwise the vendor-neutral, port-compatible gen_mult_seq (ip/gen_mult_seq.sv)
// is used: an implicit operator constrained as a multicycle path.
`ifdef USE_SYNOPSYS_DW
        DW_mult_seq #(.a_width(32),
                      .b_width(32),
                      .tc_mode(0),
                      .num_cyc(5),
                      .rst_mode(1),
                      .input_mode(1),
                      .output_mode(1),
                      .early_start(1)
                      )
                      DW_mult_seq(
                       .clk,
                       .rst_n,
                       .hold(mul_hold),
                       .start(slot_start[g]),
                       .a(a_mul),
                       .b(b_mul),
                       .complete(slot_complete[g]),
                       .product(slot_product[g])
                      );
`else
        gen_mult_seq #(.a_width(32),
                       .b_width(32),
                       .tc_mode(0),
                       .num_cyc(5),
                       .rst_mode(1),
                       .input_mode(1),
                       .output_mode(1),
                       .early_start(1)
                       )
                       u_gen_mult_seq(
                        .clk,
                        .rst_n,
                        .hold(mul_hold),
                        .start(slot_start[g]),
                        .a(a_mul),
                        .b(b_mul),
                        .complete(slot_complete[g]),
                        .product(slot_product[g])
                       );
`endif
    end
endgenerate

// ---- issue: lowest free unit ------------------------------------------------
logic              any_free;
logic [SLOT_W-1:0] free_idx;
logic              mul_en;              // an op starts this cycle

always_comb begin
    any_free = '0;
    free_idx = '0;
    for (int i = NUM_MUL-1; i >= 0; i--) begin
        if (!slot_busy[i]) begin
            any_free = '1;
            free_idx = SLOT_W'(i);
        end
    end
    mul_en     = func_in_ready && any_free;
    func_ready = any_free;
    slot_start = '0;
    if (mul_en) slot_start[free_idx] = '1;
end

// ---- completion: lowest finished unit drives the CDB -------------------------
logic              any_done;
logic [SLOT_W-1:0] done_idx;

always_comb begin
    any_done = '0;
    done_idx = '0;
    for (int i = NUM_MUL-1; i >= 0; i--) begin
        if (slot_busy[i] && slot_complete[i]) begin
            any_done = '1;
            done_idx = SLOT_W'(i);
        end
    end
end

always_ff @(posedge clk) begin
    if (rst||flush) begin
        slot_busy <= '0;
        for (int i = 0; i < NUM_MUL; i++) slot_inst[i] <= '0;
    end else begin
        if (any_done && cdb_ready) slot_busy[done_idx] <= '0;
        if (mul_en) begin
            slot_busy[free_idx] <= '1;
            slot_inst[free_idx] <= RS_out;
            slot_rvfi[free_idx] <= rvfi_entry_rs_reg;
        end
    end
end

// ---- result sign fix-up and CDB --------------------------------------------
RS_entry_t   cur_inst;                  // op driving the CDB this cycle
logic [63:0] mul_result, result_inv, rd_64;
logic [31:0] rd_v;
logic        mul_complete;

// probe compatibility: busy = no unit free
logic        busy;
assign busy = !any_free;

always_comb begin
    cur_inst     = slot_inst[done_idx];
    mul_result   = slot_product[done_idx];
    result_inv   = (~mul_result)+32'd1;
    mul_complete = any_done;

    unique case (cur_inst.op_type[1:0])
        2'b00, 2'b01:
            rd_64 = (cur_inst.rs1_data[31]^cur_inst.rs2_data[31])?  result_inv:mul_result;
        2'b10:
            rd_64 = (cur_inst.rs1_data[31])? result_inv:mul_result;
        2'b11:
            rd_64 = mul_result;
    endcase

    if(cur_inst.op_type[1:0] == 2'b00)rd_v=rd_64[31:0];
    else rd_v=rd_64[63:32];

    if (any_done) begin
        cdb.rd_paddr = cur_inst.rd_paddr;
        cdb.rob_addr = cur_inst.rob_addr;
        cdb.rd_data  = rd_v;
        cdb.regf_we  = cur_inst.regf_we;
        cdb.valid    = '1;
        cdb.br_mispred= '0;
        cdb.br_target ='0;
        cdb.br_only_taken = '0;
        cdb.ftq_addr = cur_inst.ftq_addr;

        //RVFI
        rvfi_entry_mul          = slot_rvfi[done_idx];
        rvfi_entry_mul.rd_wdata = rd_v;

    end else begin
        cdb='0;
        rvfi_entry_mul = '0;
    end
end

endmodule : func_mul
