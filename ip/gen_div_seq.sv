// ============================================================================
// gen_div_seq : vendor-neutral drop-in replacement for Synopsys DW_div_seq
// ============================================================================
//
// Same parameter list and port list as DW_div_seq. See gen_mult_seq.sv for
// the general scheme. In short: operands are registered on `start`, the
// quotient and remainder are computed by a purely combinational divider
// between the operand registers and the result registers, and an internal
// counter only lets the result registers load LATENCY edges later.
// The op*_q -> quo/rem/dbz path is a multicycle path (see ip/xilinx_mcp.xdc).
//
// The combinational divider is an explicit restoring-division array (one
// compare/subtract row per quotient bit). It does not rely on the `/` and
// `%` operators, which some FPGA synthesis tools only accept for constant
// divisors.
//
// Divide by zero (matches the DesignWare convention):
//   divide_by_0 = 1, quotient = all ones, remainder = a.
// Signed overflow (tc_mode = 1, a = MIN, b = -1):
//   quotient = MIN, remainder = 0 (natural wrap-around result).
//
// LATENCY = num_cyc - early_start (min 1). rst_mode: 0 async, 1 sync.
// ============================================================================

module gen_div_seq #(
    parameter int a_width     = 3,
    parameter int b_width     = 3,
    parameter int tc_mode     = 0,
    parameter int num_cyc     = 3,
    parameter int rst_mode    = 0,
    parameter int input_mode  = 1,
    parameter int output_mode = 1,
    parameter int early_start = 0
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 hold,
    input  logic                 start,
    input  logic [a_width-1:0]   a,
    input  logic [b_width-1:0]   b,
    output logic                 complete,
    output logic                 divide_by_0,
    output logic [a_width-1:0]   quotient,
    output logic [b_width-1:0]   remainder
);

    localparam int LATENCY_RAW = num_cyc - ((early_start != 0) ? 1 : 0);
    localparam int LATENCY     = (LATENCY_RAW < 1) ? 1 : LATENCY_RAW;
    localparam int CNT_W       = (LATENCY > 1) ? $clog2(LATENCY) : 1;

    (* dont_touch = "true" *) logic [a_width-1:0] mcp_div_opa_q;
    (* dont_touch = "true" *) logic [b_width-1:0] mcp_div_opb_q;
    (* dont_touch = "true" *) logic [a_width-1:0] mcp_div_quo_q;
    (* dont_touch = "true" *) logic [b_width-1:0] mcp_div_rem_q;
    (* dont_touch = "true" *) logic               mcp_div_dbz_q;

    logic             running_q,  running_d;
    logic             complete_q, complete_d;
    logic [CNT_W-1:0] cnt_q,      cnt_d;
    logic [a_width-1:0] opa_d, quo_d;
    logic [b_width-1:0] opb_d, rem_d;
    logic               dbz_d;

    // ---- the implicit operator (this is the multicycle path) ----------------
    // Unsigned restoring division: n / d  ->  q, r
    function automatic void udivrem(
        input  logic [a_width-1:0] n,
        input  logic [b_width-1:0] d,
        output logic [a_width-1:0] q,
        output logic [b_width-1:0] r
    );
        logic [b_width:0] rem;        // one extra bit for the trial subtract
        logic [b_width:0] diff;
        rem = '0;
        q   = '0;
        for (int i = a_width - 1; i >= 0; i--) begin
            rem  = {rem[b_width-1:0], n[i]};
            diff = rem - {1'b0, d};
            if (!diff[b_width]) begin  // rem >= d
                rem  = diff;
                q[i] = 1'b1;
            end
        end
        r = rem[b_width-1:0];
    endfunction

    logic [a_width-1:0] quo_comb;
    logic [b_width-1:0] rem_comb;
    logic               dbz_comb;

    always_comb begin
        logic               a_neg, b_neg;
        logic [a_width-1:0] a_mag, uq;
        logic [b_width-1:0] b_mag, ur;

        dbz_comb = (mcp_div_opb_q == '0);
        a_neg    = (tc_mode != 0) && mcp_div_opa_q[a_width-1];
        b_neg    = (tc_mode != 0) && mcp_div_opb_q[b_width-1];
        a_mag    = a_neg ? (~mcp_div_opa_q + 1'b1) : mcp_div_opa_q;
        b_mag    = b_neg ? (~mcp_div_opb_q + 1'b1) : mcp_div_opb_q;

        udivrem(a_mag, b_mag, uq, ur);

        if (dbz_comb) begin
            quo_comb = '1;
            rem_comb = b_width'(mcp_div_opa_q);
        end else begin
            quo_comb = (a_neg ^ b_neg) ? (~uq + 1'b1) : uq;   // quotient sign
            rem_comb = a_neg           ? (~ur + 1'b1) : ur;   // remainder takes dividend sign
        end
    end

    // ---- next state ------------------------------------------------------------
    always_comb begin
        running_d  = running_q;
        complete_d = complete_q;
        cnt_d      = cnt_q;
        opa_d      = mcp_div_opa_q;
        opb_d      = mcp_div_opb_q;
        quo_d      = mcp_div_quo_q;
        rem_d      = mcp_div_rem_q;
        dbz_d      = mcp_div_dbz_q;
        if (!hold) begin
            if (start) begin
                opa_d      = a;
                opb_d      = b;
                running_d  = 1'b1;
                complete_d = 1'b0;
                cnt_d      = CNT_W'(LATENCY - 1);
            end else if (running_q) begin
                if (cnt_q == '0) begin
                    quo_d      = quo_comb;           // multicycle capture
                    rem_d      = rem_comb;
                    dbz_d      = dbz_comb;
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
                    mcp_div_opa_q <= '0; mcp_div_opb_q <= '0;
                    mcp_div_quo_q <= '0; mcp_div_rem_q <= '0; mcp_div_dbz_q <= 1'b0;
                end else begin
                    running_q <= running_d; complete_q <= complete_d; cnt_q <= cnt_d;
                    mcp_div_opa_q <= opa_d; mcp_div_opb_q <= opb_d;
                    mcp_div_quo_q <= quo_d; mcp_div_rem_q <= rem_d; mcp_div_dbz_q <= dbz_d;
                end
            end
        end else begin : g_sync_rst
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    running_q <= 1'b0; complete_q <= 1'b0; cnt_q <= '0;
                    mcp_div_opa_q <= '0; mcp_div_opb_q <= '0;
                    mcp_div_quo_q <= '0; mcp_div_rem_q <= '0; mcp_div_dbz_q <= 1'b0;
                end else begin
                    running_q <= running_d; complete_q <= complete_d; cnt_q <= cnt_d;
                    mcp_div_opa_q <= opa_d; mcp_div_opb_q <= opb_d;
                    mcp_div_quo_q <= quo_d; mcp_div_rem_q <= rem_d; mcp_div_dbz_q <= dbz_d;
                end
            end
        end
    endgenerate

    assign complete    = complete_q;
    assign divide_by_0 = mcp_div_dbz_q;
    assign quotient    = mcp_div_quo_q;
    assign remainder   = mcp_div_rem_q;

endmodule : gen_div_seq
