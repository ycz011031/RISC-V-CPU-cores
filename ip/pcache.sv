// ============================================================================
// pcache : parameterized, pipelined, blocking cache with an optional fully
//          associative victim cache (used by both cores for I, D and shared
//          caches)
// ============================================================================
//
// Geometry: WAYS x SETS lines of 32 B (256-bit downward port).
//   addr[31 -: TAG_W] tag | addr[5 +: IDX_W] index | addr[4:0] offset
//   UFP_BYTES = 4  : word port (addr[4:2] selects the word)
//   UFP_BYTES = 32 : line port (instruction fetch)
//
// Upward protocol: hold-until-response. A request is (addr, rmask/wmask,
// wdata, id). It is accepted in some cycle, the SRAMs are read at the clock
// edge, and the cycle after it is compared (stage B):
//   * hit  : ufp_resp = 1 this cycle, with ufp_raddr / ufp_rsp_id = the
//            accepted request. A store hit goes to a one-line write buffer
//            and is written into the data SRAM in the next cycle the port is
//            free; reads of that line are forwarded from the buffer.
//   * miss : the cache leaves the pipeline, refills, and then looks up
//            whatever is presented *now* (a request the requester no longer
//            holds is never answered).
// Pipelining: with ACCEPT_ON_RESP = 1 a new request is accepted in the same
// cycle stage B answers a hit, so hits stream one per cycle. That needs the
// requester to present its *next* request (or nothing) in the response cycle.
// A requester that keeps showing the answered request through the response
// cycle (both OoO requesters) must use ACCEPT_ON_RESP = 0: the cache then
// accepts nothing in a response cycle (one hit every two cycles, as before).
//
// Miss handling (one miss at a time, the cache is blocking):
//   victim way : an invalid way if any, else tree pseudo-LRU.
//   VC_ENTRIES > 0 : a fully associative victim cache of whole lines (FIFO
//     replacement, invalid slots first), exclusive with the main array.
//       main miss, VC hit  -> SWAP : the VC line moves into the victim way and
//                                    the victim moves into its VC slot.
//       main miss, VC miss -> the VC slot that will take the victim is written
//                             back first if dirty (EVICT), the line is read
//                             (FILL), and the victim moves into the VC.
//   VC_ENTRIES = 0 : a dirty victim is written back (EVICT), then FILL.
// The miss path is chosen in the compare cycle (no extra decision cycle).
// ufp_miss is high while the cache waits on the downward port (EVICT, FILL).
//
// SRAMs: cache_sram per way (data 32 x 8-bit write granules, tag), single
// port, chip-selected only when read or written. Valid / dirty / LRU bits and
// the victim cache are flip-flops.
// ============================================================================

module pcache #(
    parameter int WAYS           = 4,       // power of two (1 = direct mapped)
    parameter int SETS           = 16,      // power of two, >= 2
    parameter int UFP_BYTES      = 4,       // 4 (word port) or 32 (line port)
    parameter bit WRITABLE       = 1'b1,    // 0: read-only (instruction) cache
    parameter int VC_ENTRIES     = 32,      // 0: no victim cache
    parameter bit ACCEPT_ON_RESP = 1'b1,
    parameter int ID_W           = 1        // sideband id returned with the response
)(
    input   logic                   clk,
    input   logic                   rst,

    // upward facing port
    input   logic   [31:0]          ufp_addr,
    input   logic   [UFP_BYTES-1:0] ufp_rmask,
    input   logic   [UFP_BYTES-1:0] ufp_wmask,
    input   logic   [8*UFP_BYTES-1:0] ufp_wdata,
    input   logic   [ID_W-1:0]      ufp_id,
    output  logic   [8*UFP_BYTES-1:0] ufp_rdata,
    output  logic                   ufp_resp,
    output  logic   [31:0]          ufp_raddr,
    output  logic   [ID_W-1:0]      ufp_rsp_id,
    output  logic                   ufp_miss,

    // downward facing port (32 B lines)
    output  logic   [31:0]          dfp_addr,
    output  logic                   dfp_read,
    output  logic                   dfp_write,
    input   logic   [255:0]         dfp_rdata,
    output  logic   [255:0]         dfp_wdata,
    input   logic                   dfp_resp
);

    localparam int OFF_W  = 5;
    localparam int IDX_W  = $clog2(SETS);
    localparam int TAG_W  = 32 - OFF_W - IDX_W;
    localparam int LINE_W = 32 - OFF_W;
    localparam int WAY_W  = (WAYS > 1) ? $clog2(WAYS) : 1;
    localparam int LRU_W  = (WAYS > 1) ? WAYS - 1 : 1;
    localparam int UFP_W  = 8 * UFP_BYTES;
    localparam int WORDS  = 32 / UFP_BYTES;
    localparam int WSEL_W = (WORDS > 1) ? $clog2(WORDS) : 1;
    localparam int VC_N   = (VC_ENTRIES > 0) ? VC_ENTRIES : 1;
    localparam int VC_W   = (VC_N > 1) ? $clog2(VC_N) : 1;
    localparam bit HAS_VC = (VC_ENTRIES > 0);

    initial begin
        if (SETS < 2 || (SETS & (SETS - 1)) != 0) $fatal(1, "pcache: SETS must be a power of two >= 2");
        if ((WAYS & (WAYS - 1)) != 0)             $fatal(1, "pcache: WAYS must be a power of two");
        if (UFP_BYTES != 4 && UFP_BYTES != 32)    $fatal(1, "pcache: UFP_BYTES must be 4 or 32");
    end

    // ------------------------------------------------------------------ helpers
    function automatic logic [IDX_W-1:0] idx_of(input logic [31:0] a);
        return a[OFF_W +: IDX_W];
    endfunction

    function automatic logic [TAG_W-1:0] tag_of(input logic [31:0] a);
        return a[31 -: TAG_W];
    endfunction

    function automatic logic [WSEL_W-1:0] wsel_of(input logic [31:0] a);
        if (WORDS > 1) return a[$clog2(UFP_BYTES) +: WSEL_W];
        else           return '0;
    endfunction

    function automatic logic [255:0] merge_line(input logic [255:0] base,
                                                input logic [31:0]  m,
                                                input logic [255:0] d);
        for (int i = 0; i < 32; i++) if (m[i]) base[8*i +: 8] = d[8*i +: 8];
        return base;
    endfunction

    // tree pseudo-LRU, heap-ordered nodes 1..WAYS-1 stored at bit node-1;
    // a node bit points at the subtree holding the next victim (0 = lower half)
    function automatic logic [WAY_W-1:0] plru_victim(input logic [LRU_W-1:0] t);
        logic [WAY_W-1:0] w;
        int node;
        w = '0;
        node = 1;
        if (WAYS > 1) begin
            for (int l = 0; l < WAY_W; l++) begin
                w[WAY_W-1-l] = t[node-1];
                node = 2 * node + int'(t[node-1]);
            end
        end
        return w;
    endfunction

    function automatic logic [LRU_W-1:0] plru_touch(input logic [LRU_W-1:0] t,
                                                    input logic [WAY_W-1:0] way);
        int node;
        node = 1;
        if (WAYS > 1) begin
            for (int l = 0; l < WAY_W; l++) begin
                t[node-1] = ~way[WAY_W-1-l];
                node = 2 * node + int'(way[WAY_W-1-l]);
            end
        end
        return t;
    endfunction

    // ------------------------------------------------------------------ state
    typedef enum logic [2:0] {
        RUN,        // pipeline: accept / compare (a miss is detected here; the
                    // write buffer always drains in that cycle, nothing is accepted)
        SWAP,       // victim cache hit: exchange lines
        EVICT,      // write a dirty line back
        FILL        // read the missing line
    } state_t;

    typedef struct packed {
        logic                   valid;
        logic   [31:0]          addr;
        logic   [UFP_BYTES-1:0] rmask;
        logic   [UFP_BYTES-1:0] wmask;
        logic   [UFP_W-1:0]     wdata;
        logic   [ID_W-1:0]      id;
    } req_t;

    state_t                     state;
    req_t                       q;                  // stage B request

    logic   [SETS-1:0][WAYS-1:0]  valid_q, dirty_q;
    logic   [SETS-1:0][LRU_W-1:0] lru_q;

    // write buffer (store hits)
    logic                       wb_valid;
    logic   [IDX_W-1:0]         wb_idx;
    logic   [WAY_W-1:0]         wb_way;
    logic   [31:0]              wb_mask;
    logic   [255:0]             wb_data;

    // miss bookkeeping (latched in stage B)
    logic   [WAY_W-1:0]         m_way;
    logic                       m_vvalid, m_vdirty;
    logic   [TAG_W-1:0]         m_vtag;
    logic   [255:0]             m_vdata;
    logic   [VC_W-1:0]          m_slot;

    // victim cache
    logic   [VC_N-1:0]          vc_valid, vc_dirty;
    logic   [LINE_W-1:0]        vc_line [VC_N];
    logic   [255:0]             vc_data [VC_N];
    logic   [VC_W-1:0]          vc_ptr;

    // ------------------------------------------------------------------ SRAMs
    logic   [WAYS-1:0]          d_csb, d_web, t_csb, t_web;
    logic   [IDX_W-1:0]         s_addr;
    logic   [31:0]              d_wmask;
    logic   [255:0]             d_din;
    logic   [TAG_W-1:0]         t_din;
    logic   [255:0]             d_dout [WAYS];
    logic   [TAG_W-1:0]         t_dout [WAYS];

    generate for (genvar w = 0; w < WAYS; w++) begin : way
        cache_sram #(.DEPTH(SETS), .WIDTH(256), .NMASK(32)) data_array (
            .clk(clk), .csb(d_csb[w]), .web(d_web[w]), .wmask(d_wmask),
            .addr(s_addr), .din(d_din), .dout(d_dout[w])
        );
        cache_sram #(.DEPTH(SETS), .WIDTH(TAG_W), .NMASK(1)) tag_array (
            .clk(clk), .csb(t_csb[w]), .web(t_web[w]), .wmask(1'b1),
            .addr(s_addr), .din(t_din), .dout(t_dout[w])
        );
    end endgenerate

    // ------------------------------------------------------------------ stage B
    logic   [IDX_W-1:0]         q_idx;
    logic   [TAG_W-1:0]         q_tag;
    logic   [WSEL_W-1:0]        q_wsel;
    logic   [WAYS-1:0]          hit_vec;
    logic                       hit_any;
    logic   [WAY_W-1:0]         hit_way, vic_way;
    logic   [255:0]             hit_line, vic_line;
    logic                       vc_hit;
    logic   [VC_W-1:0]          vc_hit_slot, vc_ins_slot;

    assign q_idx  = idx_of(q.addr);
    assign q_tag  = tag_of(q.addr);
    assign q_wsel = wsel_of(q.addr);

    always_comb begin
        hit_way = '0;
        for (int w = 0; w < WAYS; w++) begin
            hit_vec[w] = valid_q[q_idx][w] && (t_dout[w] == q_tag);
            if (hit_vec[w]) hit_way = WAY_W'(w);
        end
        hit_any = |hit_vec;

        vic_way = plru_victim(lru_q[q_idx]);
        for (int w = WAYS - 1; w >= 0; w--) if (!valid_q[q_idx][w]) vic_way = WAY_W'(w);

        // write-buffer forwarding
        hit_line = merge_line(d_dout[hit_way],
                              (wb_valid && wb_idx == q_idx && wb_way == hit_way) ? wb_mask : 32'b0,
                              wb_data);
        vic_line = merge_line(d_dout[vic_way],
                              (wb_valid && wb_idx == q_idx && wb_way == vic_way) ? wb_mask : 32'b0,
                              wb_data);

        vc_hit      = 1'b0;
        vc_hit_slot = '0;
        vc_ins_slot = vc_ptr;
        if (HAS_VC) begin
            for (int i = 0; i < VC_N; i++) begin
                if (vc_valid[i] && vc_line[i] == q.addr[31:OFF_W]) begin
                    vc_hit      = 1'b1;
                    vc_hit_slot = VC_W'(i);
                end
            end
            for (int i = VC_N - 1; i >= 0; i--) if (!vc_valid[i]) vc_ins_slot = VC_W'(i);
        end
    end

    logic           ufp_valid;
    logic           b_hit, b_miss, store_hit, wb_same, force_drain;
    logic           accept, swap_wr, fill_wr, drain;
    logic   [31:0]  st_mask;
    logic   [255:0] st_data;

    assign ufp_valid   = (|ufp_rmask) || (WRITABLE && (|ufp_wmask));
    assign b_hit       = (state == RUN) && q.valid && hit_any;
    assign b_miss      = (state == RUN) && q.valid && !hit_any;
    assign store_hit   = WRITABLE && b_hit && (|q.wmask);
    assign wb_same     = wb_valid && wb_idx == q_idx && wb_way == hit_way;
    assign force_drain = store_hit && wb_valid && !wb_same;
    assign accept      = (state == RUN) && ufp_valid &&
                         !(b_miss || force_drain || (b_hit && !ACCEPT_ON_RESP));
    assign swap_wr     = (state == SWAP);
    assign fill_wr     = (state == FILL) && dfp_resp;
    assign drain       = wb_valid && !accept && !swap_wr && !fill_wr;

    always_comb begin
        st_mask = '0;
        st_mask[q_wsel*UFP_BYTES +: UFP_BYTES] = q.wmask;
        st_data = {WORDS{q.wdata}};
    end

    // ------------------------------------------------------------------ SRAM port
    always_comb begin
        d_csb   = '1;
        d_web   = '1;
        t_csb   = '1;
        t_web   = '1;
        s_addr  = q_idx;
        d_wmask = '0;
        d_din   = wb_data;
        t_din   = q_tag;
        if (accept) begin
            d_csb  = '0;
            t_csb  = '0;
            s_addr = idx_of(ufp_addr);
        end else if (swap_wr || fill_wr) begin
            d_csb[m_way] = 1'b0;
            d_web[m_way] = 1'b0;
            t_csb[m_way] = 1'b0;
            t_web[m_way] = 1'b0;
            d_wmask      = '1;
            d_din        = swap_wr ? vc_data[m_slot] : dfp_rdata;
            t_din        = swap_wr ? vc_line[m_slot][LINE_W-1 -: TAG_W] : q_tag;
        end else if (drain) begin
            s_addr        = wb_idx;
            d_csb[wb_way] = 1'b0;
            d_web[wb_way] = 1'b0;
            d_wmask       = wb_mask;
        end
    end

    // ------------------------------------------------------------------ ports
    assign ufp_resp   = b_hit;
    assign ufp_rdata  = hit_line[q_wsel*UFP_W +: UFP_W];
    assign ufp_raddr  = q.addr;
    assign ufp_rsp_id = q.id;
    assign ufp_miss   = (state == EVICT) || (state == FILL);

    assign dfp_read   = (state == FILL);
    assign dfp_write  = (state == EVICT);
    assign dfp_addr   = (state == EVICT) ? (HAS_VC ? {vc_line[m_slot], 5'b0} : {m_vtag, q_idx, 5'b0})
                                         : {q.addr[31:OFF_W], 5'b0};
    assign dfp_wdata  = HAS_VC ? vc_data[m_slot] : m_vdata;

    // ------------------------------------------------------------------ sequential
    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= RUN;
            q        <= '0;
            valid_q  <= '0;
            dirty_q  <= '0;
            lru_q    <= '0;
            wb_valid <= 1'b0;
            wb_idx   <= '0;
            wb_way   <= '0;
            wb_mask  <= '0;
            wb_data  <= '0;
            m_way    <= '0;
            m_vvalid <= 1'b0;
            m_vdirty <= 1'b0;
            m_vtag   <= '0;
            m_vdata  <= '0;
            m_slot   <= '0;
            vc_valid <= '0;
            vc_dirty <= '0;
            vc_ptr   <= '0;
        end else begin
            // ---- stage B register
            if (accept) begin
                q.valid <= 1'b1;
                q.addr  <= ufp_addr;
                q.rmask <= ufp_rmask;
                q.wmask <= WRITABLE ? ufp_wmask : '0;
                q.wdata <= ufp_wdata;
                q.id    <= ufp_id;
            end else if ((state == RUN && !b_miss) || swap_wr || fill_wr) begin
                q.valid <= 1'b0;
            end

            // ---- hits
            if (b_hit) lru_q[q_idx] <= plru_touch(lru_q[q_idx], hit_way);
            if (store_hit) dirty_q[q_idx][hit_way] <= 1'b1;

            // ---- write buffer
            if (drain) wb_valid <= 1'b0;
            if (store_hit) begin
                wb_valid <= 1'b1;
                if (wb_same) begin
                    wb_mask <= wb_mask | st_mask;
                    wb_data <= merge_line(wb_data, st_mask, st_data);
                end else begin
                    wb_idx  <= q_idx;
                    wb_way  <= hit_way;
                    wb_mask <= st_mask;
                    wb_data <= st_data;
                end
            end

            // ---- miss path
            if (b_miss) begin
                m_way    <= vic_way;
                m_vvalid <= valid_q[q_idx][vic_way];
                m_vdirty <= dirty_q[q_idx][vic_way];
                m_vtag   <= t_dout[vic_way];
                m_vdata  <= vic_line;
                m_slot   <= vc_hit ? vc_hit_slot : vc_ins_slot;
                if (vc_hit)
                    state <= SWAP;
                else if (HAS_VC)
                    state <= (valid_q[q_idx][vic_way] && vc_valid[vc_ins_slot] && vc_dirty[vc_ins_slot])
                             ? EVICT : FILL;
                else
                    state <= (valid_q[q_idx][vic_way] && dirty_q[q_idx][vic_way]) ? EVICT : FILL;
            end

            unique case (state)
                EVICT: begin
                    if (dfp_resp) begin
                        state <= FILL;
                        if (HAS_VC) vc_valid[m_slot] <= 1'b0;
                    end
                end
                FILL: begin
                    if (dfp_resp) begin
                        state                   <= RUN;
                        valid_q[q_idx][m_way]   <= 1'b1;
                        dirty_q[q_idx][m_way]   <= 1'b0;
                        lru_q[q_idx]            <= plru_touch(lru_q[q_idx], m_way);
                        if (HAS_VC && m_vvalid) begin
                            vc_valid[m_slot] <= 1'b1;
                            vc_dirty[m_slot] <= m_vdirty;
                            vc_line[m_slot]  <= {m_vtag, q_idx};
                            vc_data[m_slot]  <= m_vdata;
                            if (m_slot == vc_ptr)
                                vc_ptr <= (vc_ptr == VC_W'(VC_N - 1)) ? '0 : vc_ptr + 1'b1;
                        end
                    end
                end
                SWAP: begin
                    state                   <= RUN;
                    valid_q[q_idx][m_way]   <= 1'b1;
                    dirty_q[q_idx][m_way]   <= vc_dirty[m_slot];
                    lru_q[q_idx]            <= plru_touch(lru_q[q_idx], m_way);
                    if (m_vvalid) begin
                        vc_valid[m_slot] <= 1'b1;
                        vc_dirty[m_slot] <= m_vdirty;
                        vc_line[m_slot]  <= {m_vtag, q_idx};
                        vc_data[m_slot]  <= m_vdata;
                    end else begin
                        vc_valid[m_slot] <= 1'b0;
                    end
                end
                default: ;
            endcase
        end
    end

endmodule : pcache
