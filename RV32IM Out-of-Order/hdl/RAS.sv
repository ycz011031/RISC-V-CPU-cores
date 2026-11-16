// ============================================================================
// RAS : return address stack with commit-time repair
// ============================================================================
//
// Two copies of the same circular stack:
//   * speculative : updated at fetch (push = call, pop = return); its top is
//                   the predicted return target.
//   * committed   : updated when a call / return commits, so it always holds
//                   the architectural call stack.
// Mispredicts are recovered at commit, so on a flush every instruction after
// the mispredicting one is wrong path: the speculative copy is overwritten
// with the committed copy (including the commit of this cycle).
//
// push + pop in the same operation (jalr with two different link registers)
// replaces the top entry. Overflow wraps and overwrites the oldest entry;
// both copies wrap identically, so a repair stays consistent.
//
// Arrays are packed and written whole (xsim drops some indexed NBAs into
// unpacked arrays).
// ============================================================================

module RAS
#(
    parameter int RAS_HEIGHT = 8,
    parameter int RAS_ADDR_L = $clog2(RAS_HEIGHT)
)(
    input   logic           clk,
    input   logic           rst,

    // fetch side (speculative)
    input   logic           push,
    input   logic           pop,
    input   logic   [31:0]  push_addr,
    output  logic   [31:0]  top_addr,

    // commit side
    input   logic           c_push,
    input   logic           c_pop,
    input   logic   [31:0]  c_push_addr,

    // mispredict flush (recovered at commit)
    input   logic           flush
);

    typedef logic [RAS_HEIGHT-1:0][31:0] stack_t;

    stack_t                 s_stk, s_stk_n, c_stk, c_stk_n;
    logic [RAS_ADDR_L-1:0]  s_top, s_top_n, c_top, c_top_n;

    // one stack operation: push writes above the top (or over it when the
    // same operation also pops); pop moves the top down
    function automatic void step(input stack_t stk, input logic [RAS_ADDR_L-1:0] top,
                                 input logic ps, input logic pp, input logic [31:0] addr,
                                 output stack_t stk_n, output logic [RAS_ADDR_L-1:0] top_n);
        logic [RAS_ADDR_L-1:0] wr;
        wr    = pp ? top : top + 1'b1;
        stk_n = stk;
        top_n = top;
        if (ps) begin
            stk_n[wr] = addr;
            top_n     = wr;
        end else if (pp) begin
            top_n     = top - 1'b1;
        end
    endfunction

    always_comb begin
        step(c_stk, c_top, c_push, c_pop, c_push_addr, c_stk_n, c_top_n);
        if (flush) begin
            s_stk_n = c_stk_n;
            s_top_n = c_top_n;
        end else begin
            step(s_stk, s_top, push, pop, push_addr, s_stk_n, s_top_n);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            s_stk <= '0;
            c_stk <= '0;
            s_top <= '0;
            c_top <= '0;
        end else begin
            s_stk <= s_stk_n;
            c_stk <= c_stk_n;
            s_top <= s_top_n;
            c_top <= c_top_n;
        end
    end

    assign top_addr = s_stk[s_top];

endmodule : RAS
