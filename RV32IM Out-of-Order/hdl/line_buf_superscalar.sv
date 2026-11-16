// ============================================================================
// line_buf_superscalar : fetch line buffer, ENTRIES lines, next-line prefetch
// ============================================================================
// Fetch reads two instructions per cycle out of whichever entry holds the
// line of pc. Entries are 32 B lines with a state:
//   INV  : empty
//   WANT : allocated for fetch, waiting for the I-cache port
//   PEND : its request is on the I-cache port
//   VAL  : data present
//
// I-cache port (one request at a time; held until ufp_resp, as the pcache
// hold-until-response contract with ACCEPT_ON_RESP = 0 requires):
//   * demand   : pc_next's line is in no entry -> allocate it (WANT, or PEND if
//                the port is free next cycle). Victim: an empty entry, else the
//                least recently used one that is not the line fetch is leaving,
//                else that line. The entry whose request is on the port is never
//                a victim.
//   * prefetch : when the port is free and nothing is waiting, the line after
//                pc's line is requested into the LRU entry that holds neither
//                pc's line nor the line filled last (registered state only; it
//                may take pc_next's line, which fetch then demands again;
//                +define+OOO_LB_NX_VICTIM: avoid pc_next's line instead).
// Response bypass: in the response cycle the cache line goes straight to the
// fetch slots when it is pc's line (no wait for the buffer write). ufp_rdata
// is only used in a ufp_resp cycle, which is when the contract makes it valid.
// Entries survive flushes (the I-cache is read-only).
// Slot 2 across the line end: when pc is the last word of its line and the next
// line is present (VAL), slot 2 is word 0 of that line; end_linebuf (slot 2 not
// available) is only raised when it is not.
// ============================================================================
module line_buf_superscalar
import rv32i_types::*;
#(
    parameter int ENTRIES = 2
)(
    input   logic   clk,
    input   logic   rst,
    input   logic   [31:0] pc,
    input   logic   [31:0] pc_next,
    input   nx_sel_t        nx_sel,         // which candidate pc_next is
    input   logic   [31:0] nx_flush, nx_flush_reg, nx_br, nx_t2,   // its candidates besides pc, pc+4, pc+8
    input   logic   [255:0] ufp_rdata,
    input   logic   ufp_resp,
    output  logic   [31:0] ufp_addr,
    output  logic   ufp_read,
    output  logic   [31:0] inst_1, inst_2,
    output  logic   i_request,      // fetch moves to another line this cycle (probe)
    output  logic   i_need_resp,    // pc's line is allocated but its data is not here yet: stall

    output  logic   end_linebuf,    // pc is the last word of its line and the next line is not here
    output  logic   inst_valid
);
    localparam int IW = (ENTRIES > 1) ? $clog2(ENTRIES) : 1;
`ifdef OOO_LB_NX_VICTIM
    localparam bit PF_NX_EXCL = 1'b1;       // old rule: the prefetch victim avoids pc_next's line
`else
    localparam bit PF_NX_EXCL = 1'b0;
`endif
    typedef enum logic [1:0] {INV, WANT, PEND, VAL} lb_st_t;

    initial if (ENTRIES < 2) $fatal(1, "line_buf_superscalar: ENTRIES must be >= 2");

    logic   [31:5]  tag  [ENTRIES];
    lb_st_t         st   [ENTRIES];
    logic   [255:0] data [ENTRIES];
    logic   [IW-1:0] rank [ENTRIES];        // 0 = most recently used
    logic           req_active;
    logic   [IW-1:0] req_idx;
    logic           started;                // fetch has had a valid instruction since reset
    logic           newest_v;               // newest_idx = the entry filled last
    logic   [IW-1:0] newest_idx;

    // ---- lookup -----------------------------------------------------------------
    logic           pc_hit, nx_hit, pf_hit, pf_val, want_any, resp_now, port_free, bypass;
    logic [IW-1:0]  pc_idx, nx_idx, want_idx, pf_idx;
    logic [31:5]    pf_line;
    logic [255:0]   line;

    assign pf_line = pc[31:5] + 1'b1;

    // pc_next's line: every candidate is looked up in parallel, then nx_sel picks one
    logic           fl_hit, flr_hit, br_hit, t2_hit, pfa_hit;
    logic [IW-1:0]  fl_idx, flr_idx, br_idx, t2_idx, pfa_idx;

    always_comb begin
        fl_hit = '0; flr_hit = '0; br_hit = '0; t2_hit = '0;
        fl_idx = '0; flr_idx = '0; br_idx = '0; t2_idx = '0;
        for (int i = 0; i < ENTRIES; i++) begin
            if (st[i] != INV && tag[i] == nx_flush[31:5])     begin fl_hit  = '1; fl_idx  = IW'(i); end
            if (st[i] != INV && tag[i] == nx_flush_reg[31:5]) begin flr_hit = '1; flr_idx = IW'(i); end
            if (st[i] != INV && tag[i] == nx_br[31:5])        begin br_hit  = '1; br_idx  = IW'(i); end
            if (st[i] != INV && tag[i] == nx_t2[31:5])        begin t2_hit  = '1; t2_idx  = IW'(i); end
        end
        unique case (nx_sel)
            NX_PC:        begin nx_hit = pc_hit;  nx_idx = pc_idx;  end
            NX_FLUSH:     begin nx_hit = fl_hit;  nx_idx = fl_idx;  end
            NX_FLUSH_REG: begin nx_hit = flr_hit; nx_idx = flr_idx; end
            NX_BR:        begin nx_hit = br_hit;  nx_idx = br_idx;  end
            NX_T2:        begin nx_hit = t2_hit;  nx_idx = t2_idx;  end
            NX_PC4:       begin nx_hit = (pc[4:2] == 3'b111) ? pfa_hit : pc_hit;
                                nx_idx = (pc[4:2] == 3'b111) ? pfa_idx : pc_idx; end
            default:      begin nx_hit = (pc[4:3] == 2'b11)  ? pfa_hit : pc_hit;     // pc + 8
                                nx_idx = (pc[4:3] == 2'b11)  ? pfa_idx : pc_idx; end
        endcase
    end

    always_comb begin
        pc_hit = '0; pc_idx = '0;
        pf_hit = '0; pf_val = '0; pf_idx = '0;
        pfa_hit = '0; pfa_idx = '0;
        want_any = '0; want_idx = '0;
        for (int i = 0; i < ENTRIES; i++) begin
            if (st[i] != INV && tag[i] == pc[31:5])      begin pc_hit = '1; pc_idx = IW'(i); end
            if (st[i] != INV && tag[i] == pf_line)        begin pfa_hit = '1; pfa_idx = IW'(i); end
            if (st[i] != INV && tag[i] == pf_line)        pf_hit = '1;
            if (st[i] == VAL && tag[i] == pf_line)        begin pf_val = '1; pf_idx = IW'(i); end
            if (st[i] == WANT)                            begin want_any = '1; want_idx = IW'(i); end
        end
        resp_now  = req_active && ufp_resp;
        port_free = !req_active || resp_now;
`ifdef OOO_LB_NO_BYPASS
        bypass    = '0;                         // experiment: no response bypass
`else
        bypass    = resp_now && pc_hit && req_idx == pc_idx;
`endif

        line        = (bypass) ? ufp_rdata : data[pc_idx];
        inst_valid  = pc_hit && (st[pc_idx] == VAL || bypass);
        // also stall when pc's line is gone (a prefetch took its entry), but not on the
        // dummy pc reset leaves one group before the program (fetch starts from it unstalled)
        i_need_resp = started ? !inst_valid : (pc_hit && !inst_valid);
        i_request   = pc_next[31:5] != pc[31:5];

        inst_1 = line[{pc[4:0], 3'd0} +: 32];
        inst_2 = (pc[4:2] == 3'b111) ? data[pf_idx][31:0] : line[{(pc[4:0]+5'd4), 3'd0} +: 32];
        end_linebuf = (pc[4:2] == 3'b111) && !pf_val;

        ufp_addr = {tag[req_idx], 5'd0};
        ufp_read = req_active;
    end

    // ---- allocation -------------------------------------------------------------------
    logic           demand, prefetch;
    logic           d_ok, p_ok;
    logic [IW-1:0]  d_vic, p_vic;

    always_comb begin
        automatic int best_d = -1, best_p = -1;
        d_ok = '0; d_vic = '0;
        p_ok = '0; p_vic = '0;
        for (int i = 0; i < ENTRIES; i++) begin
            automatic int s;
            automatic bit busy = req_active && req_idx == IW'(i);
            // demand: empty first, then LRU, the line being left last
            s = (st[i] == INV) ? 4 * ENTRIES : int'(rank[i]) + ((pc_hit && pc_idx == IW'(i)) ? 0 : 2 * ENTRIES);
            if (!busy && s > best_d) begin best_d = s; d_vic = IW'(i); d_ok = '1; end
            // prefetch: never pc's line or the line filled last. Registered state only, so
            // the choice does not wait for pc_next (and through it for the response bypass);
            // it can take pc_next's line, which fetch then demands again.
            s = (st[i] == INV) ? 4 * ENTRIES : int'(rank[i]);
            if (!busy && !(pc_hit && pc_idx == IW'(i)) && !(PF_NX_EXCL && nx_hit && nx_idx == IW'(i))
                && !(!PF_NX_EXCL && newest_v && newest_idx == IW'(i)) && s > best_p) begin
                best_p = s; p_vic = IW'(i); p_ok = '1;
            end
        end
        demand   = !nx_hit && d_ok;
        prefetch = !demand && port_free && !want_any && pc_hit && !pf_hit && p_ok;
    end

    // ---- LRU ranks: touch pc's entry, then the allocated one -----------------------------
    logic [IW-1:0] rank_n [ENTRIES];

    function automatic void touch(inout logic [IW-1:0] r [ENTRIES], input logic [IW-1:0] k);
        for (int j = 0; j < ENTRIES; j++) if (r[j] < r[k]) r[j] = r[j] + 1'b1;
        r[k] = '0;
    endfunction

    always_comb begin
        rank_n = rank;
        if (pc_hit)        touch(rank_n, pc_idx);
        if (demand)        touch(rank_n, d_vic);
        else if (prefetch) touch(rank_n, p_vic);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            req_active <= '0;
            req_idx    <= '0;
            newest_v   <= '0;
            newest_idx <= '0;
            started    <= '0;
            for (int i = 0; i < ENTRIES; i++) begin
                st[i]   <= INV;
                tag[i]  <= '0;
                data[i] <= '0;
                rank[i] <= IW'(i);
            end
        end else begin
            rank <= rank_n;
            if (inst_valid) started <= '1;
            if (resp_now) begin
                data[req_idx] <= ufp_rdata;
                st[req_idx]   <= VAL;
                req_active    <= '0;
                newest_v      <= '1;
                newest_idx    <= req_idx;
            end
            if (demand) begin
                tag[d_vic] <= pc_next[31:5];
                st[d_vic]  <= port_free ? PEND : WANT;
                if (port_free) begin
                    req_active <= '1;
                    req_idx    <= d_vic;
                end
            end else if (port_free && want_any) begin
                st[want_idx] <= PEND;
                req_active   <= '1;
                req_idx      <= want_idx;
            end else if (prefetch) begin
                tag[p_vic] <= pf_line;
                st[p_vic]  <= PEND;
                req_active <= '1;
                req_idx    <= p_vic;
            end
        end
    end

endmodule : line_buf_superscalar
