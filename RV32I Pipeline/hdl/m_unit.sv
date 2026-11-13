// ============================================================================
// m_unit : RV32M multiply / divide unit for the 5-stage pipeline
// ============================================================================
//
// Interface is deliberately the same shape as the data-memory port: the
// memory stage issues an operation with a one-cycle `start` pulse in the slot
// where it would issue a load, and the unit answers with a one-cycle `done`
// pulse carrying `result` (like dmem_resp / dmem_rdata). The memory stage
// stalls on it exactly like an outstanding load.
//
// Arithmetic is done on magnitudes by unsigned sequential operators. Signs and
// the RISC-V special cases are fixed up here:
//   * MULH / MULHSU / MULHU  : upper 32 bits of the signed/mixed/unsigned product
//   * DIV/DIVU by zero        : all ones;  REM/REMU by zero : rs1
//   * DIV overflow (-2^31/-1) : -2^31;     REM overflow     : 0
//     (falls out of the magnitude arithmetic: |-2^31| = 0x8000_0000)
//
// Operators: Synopsys DW_mult_seq / DW_div_seq when USE_SYNOPSYS_DW is defined,
// otherwise the vendor-neutral, port-compatible gen_mult_seq / gen_div_seq
// (ip/), which are implicit operators closed with a multicycle-path constraint.
// Same configuration as the out-of-order core's func_mul / func_div.
// ============================================================================

module m_unit
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    input   logic           start,      // issue: one-cycle pulse
    input   logic   [2:0]   funct3,     // m_f3_t
    input   logic   [31:0]  rs1_v,
    input   logic   [31:0]  rs2_v,

    output  logic           done,       // one-cycle pulse, result valid
    output  logic   [31:0]  result
);

    localparam int MUL_CYC = 5;
    localparam int DIV_CYC = 17;

    logic rst_n;
    assign rst_n = ~rst;

    // ---- operand conditioning (issue cycle) ---------------------------------
    logic        is_div;
    logic        a_neg, b_neg;
    logic [31:0] a_mag, b_mag;

    always_comb begin
        is_div = funct3[2];
        if (!is_div) begin
            // MUL/MULH: signed x signed, MULHSU: signed x unsigned, MULHU: unsigned
            a_neg = rs1_v[31] && (funct3 != m_f3_mulhu);
            b_neg = rs2_v[31] && (funct3 == m_f3_mul || funct3 == m_f3_mulh);
        end else begin
            // DIV/REM signed, DIVU/REMU unsigned
            a_neg = rs1_v[31] && !funct3[0];
            b_neg = rs2_v[31] && !funct3[0];
        end
        a_mag = a_neg ? (~rs1_v + 32'd1) : rs1_v;
        b_mag = b_neg ? (~rs2_v + 32'd1) : rs2_v;
    end

    // ---- sequential operators ----------------------------------------------
    logic        mul_start, div_start;
    logic        mul_complete, div_complete;
    logic [63:0] product;
    logic [31:0] quotient, remainder;
    logic        div_by_0;

    assign mul_start = start && !is_div;
    assign div_start = start &&  is_div;

`ifdef USE_SYNOPSYS_DW
    DW_mult_seq #(
`else
    gen_mult_seq #(
`endif
        .a_width(32), .b_width(32), .tc_mode(0), .num_cyc(MUL_CYC),
        .rst_mode(1), .input_mode(1), .output_mode(1), .early_start(1)
    ) u_mult (
        .clk, .rst_n, .hold(1'b0), .start(mul_start),
        .a(a_mag), .b(b_mag),
        .complete(mul_complete), .product(product)
    );

`ifdef USE_SYNOPSYS_DW
    DW_div_seq #(
`else
    gen_div_seq #(
`endif
        .a_width(32), .b_width(32), .tc_mode(0), .num_cyc(DIV_CYC),
        .rst_mode(1), .input_mode(1), .output_mode(1), .early_start(0)
    ) u_div (
        .clk, .rst_n, .hold(1'b0), .start(div_start),
        .a(a_mag), .b(b_mag),
        .complete(div_complete), .divide_by_0(div_by_0),
        .quotient(quotient), .remainder(remainder)
    );

    // ---- per-operation state ------------------------------------------------
    logic        busy_q;
    logic [2:0]  f3_q;
    logic        a_neg_q, b_neg_q, b_zero_q;
    logic [31:0] rs1_q;

    assign done = busy_q && (f3_q[2] ? div_complete : mul_complete);

    always_ff @(posedge clk) begin
        if (rst) begin
            busy_q   <= 1'b0;
            f3_q     <= '0;
            a_neg_q  <= 1'b0;
            b_neg_q  <= 1'b0;
            b_zero_q <= 1'b0;
            rs1_q    <= '0;
        end else begin
            if (start) begin            // start has priority over a same-cycle done
                busy_q   <= 1'b1;
                f3_q     <= funct3;
                a_neg_q  <= a_neg;
                b_neg_q  <= b_neg;
                b_zero_q <= (rs2_v == '0);
                rs1_q    <= rs1_v;
            end else if (done) begin
                busy_q   <= 1'b0;
            end
        end
    end

    // ---- result fix-up ------------------------------------------------------
    logic [63:0] product_s;
    always_comb begin
        product_s = (a_neg_q ^ b_neg_q) ? (~product + 64'd1) : product;
        unique case (f3_q)
            m_f3_mul                         : result = product_s[31:0];
            m_f3_mulh, m_f3_mulhsu, m_f3_mulhu: result = product_s[63:32];
            m_f3_div, m_f3_divu              : result = b_zero_q ? 32'hffff_ffff
                                                      : ((a_neg_q ^ b_neg_q) ? (~quotient + 32'd1) : quotient);
            m_f3_rem, m_f3_remu              : result = b_zero_q ? rs1_q
                                                      : (a_neg_q ? (~remainder + 32'd1) : remainder);
            default                          : result = '0;
        endcase
    end

endmodule : m_unit
