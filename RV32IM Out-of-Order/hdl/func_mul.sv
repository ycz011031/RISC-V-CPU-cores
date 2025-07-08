module func_mul
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
    output   rvfi_entry         rvfi_entry_mul
);

/**********************************************************************************
Busy signal never goes low if say one mul completes and there is another one in the res station ready to be executed
***********************************************************************************/

logic rst_n;
assign rst_n = ~(rst||flush);

logic mul_en;
logic mul_hold;
logic mul_complete;
logic [31:0] rs1_v;
logic [31:0] rs2_v;
logic [63:0] mul_result;
logic [63:0] rd_64;

RS_entry_t cur_inst;

logic [31:0] a_mul;
logic [31:0] b_mul;

rvfi_entry rvfi_input_reg;


// logic [1:0] num_active_inst;
logic counter;

logic [31:0] rd_v;
logic busy;

// assign func_read = num_active_inst[0] & num_active_inst[1];
assign mul_hold  = '0;

assign rs1_v = RS_out.rs1_data;
assign rs2_v = RS_out.rs2_data;

logic [31:0] rs1_inv,rs2_inv;
logic [63:0] result_inv;
assign rs1_inv    = (~rs1_v)+32'd1;
assign rs2_inv    = (~rs2_v)+32'd1;
assign result_inv = (~mul_result)+32'd1;

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
                .start(mul_en),
                .a(a_mul),
                .b(b_mul),
                .complete(mul_complete),
                .product(mul_result)
               );

always_ff @(posedge clk) begin
    if (rst||flush) begin
        cur_inst        <='0;
        busy            <='0;
    end else begin
        if (func_in_ready && !busy) rvfi_input_reg <= rvfi_entry_rs_reg;
        if (func_in_ready && !busy) cur_inst<= RS_out;
        // asserting and deasserting busy signal;
        if (func_in_ready && !busy)busy<='1;
        else if(mul_complete && cdb_ready)busy<='0;
    end
end

always_comb begin
    unique case (RS_out.op_type[1:0])
        2'b00: begin
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = (RS_out.rs2_data[31])? rs2_inv : rs2_v;
        end
        2'b01: begin
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = (RS_out.rs2_data[31])? rs2_inv : rs2_v;
        end
        2'b10: begin
            a_mul = (RS_out.rs1_data[31])? rs1_inv : rs1_v;
            b_mul = rs2_v;
        end
        2'b11: begin
            a_mul = rs1_v;
            b_mul = rs2_v;
        end
    endcase

    mul_en = func_in_ready && !busy;
    func_ready =  ~busy; // ~ (busy || mul_en);

    unique case (cur_inst.op_type[1:0])
        2'b00: 
            rd_64 = (cur_inst.rs1_data[31]^cur_inst.rs2_data[31])?  result_inv:mul_result;
        2'b01: 
            rd_64 = (cur_inst.rs1_data[31]^cur_inst.rs2_data[31])?  result_inv:mul_result;
        2'b10:
            rd_64 = (cur_inst.rs1_data[31])? result_inv:mul_result;
        2'b11:
            rd_64 = mul_result;
    endcase          

    if(cur_inst.op_type[1:0] == 2'b00)rd_v=rd_64[31:0];
    else rd_v=rd_64[63:32];

    if (mul_complete&&busy)begin
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
        rvfi_entry_mul          = rvfi_input_reg;
        rvfi_entry_mul.rd_wdata = rd_v;

    end else begin
        cdb='0;
        rvfi_entry_mul = '0;
    end
end

endmodule : func_mul