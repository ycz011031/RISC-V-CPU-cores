// ============================================================================
// arbiter : instruction / data requests -> one shared cache port
// ============================================================================
//
// Same job as the OoO core's arbiter (two requesters, one downstream port),
// but placed in front of the single shared cache, at word granularity.
//
// Policy: data has priority. In an in-order pipeline a waiting memory stage
// stalls everything, while fetch can simply retry.
//
// No transaction lock is needed (unlike the OoO DRAM-side arbiter). The cache
// ignores its input while it fills a line, and a request that is no longer
// presented when the fill completes is simply never answered. So switching
// the grant can never mix up responses. Every response carries the source tag
// it was accepted with and is routed back on that tag.
// ============================================================================

module arbiter
import rv32i_types::*;
(
    input   mem_req_t   i_req,      // fetch
    output  mem_rsp_t   i_rsp,
    input   mem_req_t   d_req,      // memory stage
    output  mem_rsp_t   d_rsp,

    output  mem_req_t   c_req,      // shared cache
    output  logic       c_src,      // 1 = data, 0 = instruction
    input   mem_rsp_t   c_rsp,
    input   logic       c_rsp_src
);

    localparam logic SRC_I = 1'b0;
    localparam logic SRC_D = 1'b1;

    logic d_active;
    assign d_active = |d_req.rmask || |d_req.wmask;

    always_comb begin
        c_req = d_active ? d_req : i_req;
        c_src = d_active ? SRC_D : SRC_I;

        i_rsp      = c_rsp;
        i_rsp.resp = c_rsp.resp && (c_rsp_src == SRC_I);
        d_rsp      = c_rsp;
        d_rsp.resp = c_rsp.resp && (c_rsp_src == SRC_D);
    end

endmodule : arbiter
