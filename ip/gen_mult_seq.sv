// ============================================================================
// gen_mult_seq : vendor-neutral drop-in replacement for Synopsys DW_mult_seq
// ============================================================================
//
// Same parameter list and port list as DW_mult_seq, so a design can switch
// between the two with nothing more than an `ifdef around the module name.
//
// Implementation ("implicit operator + multicycle path"):
//   * On `start` the operands are captured into mcp_mul_op{a,b}_q.
//   * The product is written as a plain `*` operator between those operand
//     registers and the result register mcp_mul_res_q. That path is
//     NOT single cycle: an internal down-counter only lets mcp_mul_res_q
//     load LATENCY clock edges after the operands were captured, and the
//     operands cannot change in between (they only load on `start`).
//   * Timing closure is therefore done with a multicycle-path constraint
//     (see ip/xilinx_mcp.xdc):
//         set_multicycle_path -setup LATENCY    (op*_q -> res_q)
//         set_multicycle_path -hold  LATENCY-1
//   * On Xilinx devices the `*` maps onto DSP slices (combinational, since
//     the boundary registers are dont_touch and cannot be absorbed into the
//     DSP pipeline) or onto LUTs. On ASIC flows any multiplier works.
//
// Handshake (matches how the cores use DW_mult_seq):
//   * `complete` drops on the clock edge that samples `start`, and rises
//     LATENCY edges later together with a valid `product`. It then stays
//     high, and `product` holds, until the next `start`.
//   * `hold` freezes the unit (counter, operands, result).
//   * A new `start` while busy aborts the old operation and restarts.
//
// Latency: LATENCY = num_cyc - early_start (min 1). That approximates the
// DesignWare latency for the input_mode = output_mode = 1 configuration
// used in this repository. Nothing in the cores depends on the exact number
// because they all handshake on `complete`.
//
// rst_mode: 0 = asynchronous active-low reset, 1 = synchronous active-low.
// tc_mode : 0 = unsigned, 1 = two's complement.
// input_mode / output_mode are accepted for compatibility. Operands and
// result are always registered, because the multicycle constraint needs
// stable register boundaries.
// ============================================================================

module gen_mult_seq #(
    parameter int a_width     = 3,
    parameter int b_width     = 3,
    parameter int tc_mode     = 0,
    parameter int num_cyc     = 3,
    parameter int rst_mode    = 0,
    parameter int input_mode  = 1,
    parameter int output_mode = 1,
    parameter int early_start = 0
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         hold,
    input  logic                         start,
    input  logic [a_width-1:0]           a,
    input  logic [b_width-1:0]           b,
    output logic                         complete,
    output logic [a_width+b_width-1:0]   product
);

    localparam int LATENCY_RAW = num_cyc - ((early_start != 0) ? 1 : 0);
    localparam int LATENCY     = (LATENCY_RAW < 1) ? 1 : LATENCY_RAW;
    localparam int CNT_W       = (LATENCY > 1) ? $clog2(LATENCY) : 1;
    localparam int P_W         = a_width + b_width;

    // Multicycle-path boundary registers. dont_touch keeps synthesis from
    // retiming them or folding them into DSP pipeline registers, so the
    // names stay stable for the XDC constraint.
    (* dont_touch = "true" *) logic [a_width-1:0] mcp_mul_opa_q;
    (* dont_touch = "true" *) logic [b_width-1:0] mcp_mul_opb_q;
    (* dont_touch = "true" *) logic [P_W-1:0]     mcp_mul_res_q;

    logic             running_q,  running_d;
    logic             complete_q, complete_d;
    logic [CNT_W-1:0] cnt_q,      cnt_d;
    logic [a_width-1:0] opa_d;
    logic [b_width-1:0] opb_d;
    logic [P_W-1:0]     res_d;

    // ---- the implicit operator (this is the multicycle path) ----------------
    logic [P_W-1:0] prod_comb;
    generate
        if (tc_mode != 0) begin : g_signed
            logic signed [P_W-1:0] sa, sb;
            assign sa        = $signed(mcp_mul_opa_q);   // sign-extends
            assign sb        = $signed(mcp_mul_opb_q);
            assign prod_comb = P_W'(sa * sb);
        end else begin : g_unsigned
            assign prod_comb = P_W'(mcp_mul_opa_q) * P_W'(mcp_mul_opb_q);
        end
    endgenerate

    // ---- next state ------------------------------------------------------------
    always_comb begin
        running_d  = running_q;
        complete_d = complete_q;
        cnt_d      = cnt_q;
        opa_d      = mcp_mul_opa_q;
        opb_d      = mcp_mul_opb_q;
        res_d      = mcp_mul_res_q;
        if (!hold) begin
            if (start) begin
                opa_d      = a;
                opb_d      = b;
                running_d  = 1'b1;
                complete_d = 1'b0;
                cnt_d      = CNT_W'(LATENCY - 1);
            end else if (running_q) begin
                if (cnt_q == '0) begin
                    res_d      = prod_comb;          // multicycle capture
                    complete_d = 1'b1;
                    running_d  = 1'b0;
                end else begin
                    cnt_d      = cnt_q - 1'b1;
                end
            end
        end
    end

    // ---- state registers ---------------------------------------------------
    generate
        if (rst_mode == 0) begin : g_async_rst
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    running_q <= 1'b0; complete_q <= 1'b0; cnt_q <= '0;
                    mcp_mul_opa_q <= '0; mcp_mul_opb_q <= '0; mcp_mul_res_q <= '0;
                end else begin
                    running_q <= running_d; complete_q <= complete_d; cnt_q <= cnt_d;
                    mcp_mul_opa_q <= opa_d; mcp_mul_opb_q <= opb_d; mcp_mul_res_q <= res_d;
                end
            end
        end else begin : g_sync_rst
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    running_q <= 1'b0; complete_q <= 1'b0; cnt_q <= '0;
                    mcp_mul_opa_q <= '0; mcp_mul_opb_q <= '0; mcp_mul_res_q <= '0;
                end else begin
                    running_q <= running_d; complete_q <= complete_d; cnt_q <= cnt_d;
                    mcp_mul_opa_q <= opa_d; mcp_mul_opb_q <= opb_d; mcp_mul_res_q <= res_d;
                end
            end
        end
    endgenerate

    assign complete = complete_q;
    assign product  = mcp_mul_res_q;

endmodule : gen_mult_seq
