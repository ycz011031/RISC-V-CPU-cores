// ============================================================================
// cache_shared : 2 KB direct-mapped, write-back, write-allocate cache shared
//                by instruction fetch and data accesses (via the arbiter)
// ============================================================================
//
// Geometry: 64 lines x 32 B (same SRAM macros as the OoO core's cache_dm).
//   addr[31:11] tag | addr[10:5] index | addr[4:2] word | addr[1:0] byte
//
// Upward port (mem_req_t / mem_rsp_t, word granularity), hold-until-response:
//   * IDLE     : a presented request is accepted and the data/tag SRAMs are
//                read at its index.
//   * COMPARE  : hit  -> respond this cycle (read data or write performed).
//                       After a read hit a new request is accepted in the same
//                       cycle, so back-to-back read hits stream one per cycle.
//                miss -> write back the victim if dirty, then allocate.
//   * After a fill the cache returns to IDLE and looks up whatever is presented
//     *now*. If the requester still holds the request it hits and gets its
//     response. If it moved on (wrong-path fetch, another requester won
//     arbitration) the old request is never answered, so a late, unwanted
//     response cannot happen.
//   ufp_src is a sideband tag (which arbiter port) carried with the request
//   and returned with the response (ufp_rsp_src).
//
// Low power: the SRAMs are chip-selected only when they are actually read or
// written. While the downward port is busy they hold their outputs (the
// victim line is written back straight from the data SRAM output).
// ============================================================================

module cache_shared
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // upward facing port
    input   mem_req_t       ufp_req,
    input   logic           ufp_src,
    output  mem_rsp_t       ufp_rsp,
    output  logic           ufp_rsp_src,

    // downward facing port (cache lines)
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

    typedef enum logic [1:0] {
        IDLE,
        COMPARE,
        WRITEBACK,
        ALLOCATE
    } state_t;

    state_t         state, state_n;

    mem_req_t       req_q;          // request being looked up / serviced
    logic           src_q;
    logic   [63:0]  valid_q;
    logic   [63:0]  dirty_q;

    // SRAM ports
    logic           data_csb, data_web;
    logic   [31:0]  data_wmask;
    logic   [5:0]   data_addr;
    logic   [255:0] data_din, data_dout;
    logic           tag_csb, tag_web;
    logic   [5:0]   tag_addr;
    logic   [20:0]  tag_din, tag_dout;

    dm_cache_data_array data_array (
        .clk0   (clk),
        .csb0   (data_csb),
        .web0   (data_web),
        .wmask0 (data_wmask),
        .addr0  (data_addr),
        .din0   (data_din),
        .dout0  (data_dout)
    );

    dm_cache_tag_array tag_array (
        .clk0   (clk),
        .csb0   (tag_csb),
        .web0   (tag_web),
        .addr0  (tag_addr),
        .din0   (tag_din),
        .dout0  (tag_dout)
    );

    logic   [20:0]  req_tag;
    logic   [5:0]   req_idx;
    logic   [2:0]   req_word;
    logic           req_write;
    logic           ufp_valid;
    logic           hit;
    logic           accept;
    logic           set_dirty, fill_done;

    assign req_tag   = req_q.addr[31:11];
    assign req_idx   = req_q.addr[10:5];
    assign req_word  = req_q.addr[4:2];
    assign req_write = |req_q.wmask;
    assign ufp_valid = |ufp_req.rmask || |ufp_req.wmask;
    assign hit       = valid_q[req_idx] && (tag_dout == req_tag);

    always_comb begin
        state_n     = state;
        accept      = 1'b0;
        set_dirty   = 1'b0;
        fill_done   = 1'b0;

        data_csb    = 1'b1;
        data_web    = 1'b1;
        data_addr   = req_idx;
        data_wmask  = '0;
        data_din    = 'x;
        tag_csb     = 1'b1;
        tag_web     = 1'b1;
        tag_addr    = req_idx;
        tag_din     = req_tag;

        ufp_rsp.resp  = 1'b0;
        ufp_rsp.rdata = data_dout[32*req_word +: 32];
        ufp_rsp.raddr = req_q.addr;
        ufp_rsp_src   = src_q;

        dfp_read    = 1'b0;
        dfp_write   = 1'b0;
        dfp_addr    = {req_tag, req_idx, 5'b0};
        dfp_wdata   = data_dout;

        unique case (state)
            IDLE: begin
                if (ufp_valid) begin
                    accept  = 1'b1;
                    state_n = COMPARE;
                end
            end
            COMPARE: begin
                if (hit) begin
                    ufp_rsp.resp = 1'b1;
                    if (req_write) begin
                        // write hit: merge the bytes, line becomes dirty
                        data_csb   = 1'b0;
                        data_web   = 1'b0;
                        data_wmask = 32'(req_q.wmask) << (4 * req_word);
                        data_din   = {8{req_q.wdata}};
                        set_dirty  = 1'b1;
                        state_n    = IDLE;
                    end else if (ufp_valid) begin
                        accept     = 1'b1;          // stream the next request
                        state_n    = COMPARE;
                    end else begin
                        state_n    = IDLE;
                    end
                end else begin
                    state_n = (valid_q[req_idx] && dirty_q[req_idx]) ? WRITEBACK : ALLOCATE;
                end
            end
            WRITEBACK: begin
                dfp_write = 1'b1;
                dfp_addr  = {tag_dout, req_idx, 5'b0};
                if (dfp_resp) state_n = ALLOCATE;
            end
            ALLOCATE: begin
                dfp_read = 1'b1;
                if (dfp_resp) begin
                    data_csb   = 1'b0;
                    data_web   = 1'b0;
                    data_wmask = '1;
                    data_din   = dfp_rdata;
                    tag_csb    = 1'b0;
                    tag_web    = 1'b0;
                    fill_done  = 1'b1;
                    state_n    = IDLE;              // re-lookup what is presented now
                end
            end
            default: state_n = IDLE;
        endcase

        if (accept) begin
            data_csb  = 1'b0;
            data_addr = ufp_req.addr[10:5];
            tag_csb   = 1'b0;
            tag_addr  = ufp_req.addr[10:5];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            valid_q <= '0;
            dirty_q <= '0;
            req_q   <= '0;
            src_q   <= 1'b0;
        end else begin
            state <= state_n;
            if (accept) begin
                req_q <= ufp_req;
                src_q <= ufp_src;
            end
            if (set_dirty) dirty_q[req_idx] <= 1'b1;
            if (fill_done) begin
                valid_q[req_idx] <= 1'b1;
                dirty_q[req_idx] <= 1'b0;
            end
        end
    end

endmodule : cache_shared
