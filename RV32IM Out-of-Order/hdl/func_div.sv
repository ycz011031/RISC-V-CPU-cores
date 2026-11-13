module func_div
import rv32i_types::*;
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
    output   rvfi_entry         rvfi_entry_div
);

logic rst_n;
assign rst_n = ~(rst||flush);

logic div_en;
logic div_hold;
logic div_complete;
logic [31:0] rs1_v;
logic [31:0] rs2_v;


RS_entry_t cur_inst;

logic [31:0] a_mul;
logic [31:0] b_mul;

rvfi_entry rvfi_input_reg;


logic [1:0] num_active_inst;
logic counter;

logic [31:0] rd_v;
logic [31:0] rd_v_d0;
logic busy;

logic div_0;
logic [31:0] quotient;
logic [31:0] remainder;
logic [31:0] quotient_inv;
logic [31:0] remainder_inv;

assign div_hold  = '0;
assign rs1_v = RS_out.rs1_data;
assign rs2_v = RS_out.rs2_data;

logic [31:0] rs1_inv,rs2_inv;
logic [63:0] result_inv;
assign rs1_inv    = (~rs1_v)+32'd1;
assign rs2_inv    = (~rs2_v)+32'd1;
assign quotient_inv = (~quotient)+32'd1;
assign remainder_inv= (~remainder)+32'd1;

// Synopsys DesignWare IP is only used when USE_SYNOPSYS_DW is defined.
// Otherwise the vendor-neutral, port-compatible gen_div_seq (ip/gen_div_seq.sv)
// is used: an implicit operator constrained as a multicycle path.
`ifdef USE_SYNOPSYS_DW
DW_div_seq #(
    .a_width(32),
    .b_width(32),
    .tc_mode(0),
    .num_cyc(17),
    .rst_mode(1),
    .input_mode(1),
    .output_mode(1),
    .early_start(0)
)DW_div_seq(
    .clk,
    .rst_n,
    .hold(div_hold),
    .start(div_en),
    .a(a_mul),
    .b(b_mul),
    .complete(div_complete),
    .divide_by_0(div_0),
    .quotient,
    .remainder
);
`else
gen_div_seq #(
    .a_width(32),
    .b_width(32),
    .tc_mode(0),
    .num_cyc(17),
    .rst_mode(1),
    .input_mode(1),
    .output_mode(1),
    .early_start(0)
)u_gen_div_seq(
    .clk,
    .rst_n,
    .hold(div_hold),
    .start(div_en),
    .a(a_mul),
    .b(b_mul),
    .complete(div_complete),
    .divide_by_0(div_0),
    .quotient,
    .remainder
);
`endif

always_ff @(posedge clk) begin
    if (rst||flush) begin
        cur_inst        <='0;
        busy            <='0;
    end else begin
        if (func_in_ready && !busy) rvfi_input_reg <= rvfi_entry_rs_reg;
        if (func_in_ready && !busy) cur_inst<= RS_out;
        
        // asserting and deasserting busy signal;
        if (func_in_ready && !busy) busy<='1;
        else if(div_complete && cdb_ready)busy<='0;
    end
end

always_comb begin
    unique case (RS_out.op_type[1:0])
        2'b00: begin
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = (RS_out.rs2_data[31])? rs2_inv : rs2_v;
        end
        2'b01: begin
            a_mul = rs1_v;
            b_mul = rs2_v;
        end
        2'b10: begin
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = (RS_out.rs2_data[31])? rs2_inv : rs2_v;
        end
        2'b11: begin
            a_mul = rs1_v;
            b_mul = rs2_v;
        end
    endcase

    div_en = (func_in_ready && !busy);
    func_ready =  ~busy; // ~ (busy || div_en);



    unique case (cur_inst.op_type[1:0])
        2'b00: 
            rd_v = (cur_inst.rs1_data[31]^cur_inst.rs2_data[31])?  quotient_inv:quotient;
        2'b01: 
            rd_v = quotient;
        2'b10:
            rd_v = (cur_inst.rs1_data[31])? remainder_inv:remainder;
        2'b11:
            rd_v = remainder;
    endcase          

    unique case (cur_inst.op_type[1])
        1'b0: rd_v_d0 = '1;
        1'b1: rd_v_d0 = cur_inst.rs1_data;
    endcase


    if (div_complete && busy)begin
        cdb.rd_paddr = cur_inst.rd_paddr;
        cdb.rob_addr = cur_inst.rob_addr;
        cdb.regf_we  = cur_inst.regf_we;
        cdb.rd_data  = (cur_inst.rs2_data == '0)? rd_v_d0:rd_v;
        cdb.valid    = '1;
        cdb.br_mispred= '0;
        cdb.br_target ='0;
        cdb.br_only_taken = '0;
        cdb.ftq_addr = cur_inst.ftq_addr;

        //RVFI
        rvfi_entry_div          = rvfi_input_reg;
        rvfi_entry_div.rd_wdata = (cur_inst.rs2_data == '0)? rd_v_d0:rd_v;

    end else begin
        cdb='0;
        rvfi_entry_div = '0;
    end
end

endmodule : func_div
