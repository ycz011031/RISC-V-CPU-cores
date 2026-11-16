// ============================================================================
// perf_probe : cycle-accounting probes for the 5-stage pipeline (testbench only)
// ============================================================================
// Reads DUT internals hierarchically (top_tb.dut.*); no RTL changes. Same
// window as the monitor's IPC (segment start / stop markers).
//
// Top-down accounting: a shadow pipeline tags every bubble with the reason it
// was created (using the same update conditions as the RTL stage registers);
// the tag travels with the bubble. At the commit point (MEM/WB) every cycle is
// either a commit or a bubble with a root cause, so the categories add up to
// the cycle count exactly. TAG_MISMATCH checks the shadow against the real
// valid bits (must be 0).
// ============================================================================

`define C top_tb.dut.core

module perf_probe (
    mon_itf itf
);

    // bubble root causes (shadow tags)
    typedef enum int {
        T_VALID,
        T_FLUSH_BRANCH,     // mispredicted (not-taken) branch: flushed slots
        T_FLUSH_JALR,       // JALR: fetch waits for the target + flushed slot
        T_ICACHE_MISS,      // fetch waiting on a shared-cache miss
        T_PORT_CONFLICT,    // fetch lost the shared cache port to a data access
        T_FETCH_RESTART,    // fetch was paused during a memory stall (power gating)
        T_LOAD_USE,         // load-use / M-use bubble
        T_MEM_DCACHE,       // memory stage waiting on the cache (data miss)
        T_MEM_MULDIV,       // memory stage waiting on m_unit
        T_OTHER,
        T_NUM
    } tag_e;

    typedef enum int {
        CYCLES,
        COMMITS,
        // commit-point accounting (one per cycle): COMMITS + sum(LOST_*) == CYCLES
        LOST_FLUSH_BRANCH, LOST_FLUSH_JALR, LOST_ICACHE_MISS, LOST_PORT_CONFLICT,
        LOST_FETCH_RESTART, LOST_LOAD_USE, LOST_MEM_DCACHE, LOST_MEM_MULDIV, LOST_OTHER,
        TAG_MISMATCH,
        // stage occupancy
        VALID_IF_ID, VALID_ID_EX, VALID_EX_MEM, VALID_MEM_WB,
        MEM_STALL_CYCLES, MEM_STALL_DCACHE, MEM_STALL_MULDIV, LOAD_USE_CYCLES,
        // control flow
        REDIRECT_BRANCH, REDIRECT_JALR, COMMIT_BRANCH, COMMIT_JAL, COMMIT_JALR,
        COMMIT_LOAD, COMMIT_STORE, COMMIT_MULDIV,
        // shared cache
        // (pcache: MISS_* = main-array misses, VC_HIT_* = of those, served by the
        //  victim cache; BUSY_FILL = cycles out of the pipeline state)
        CACHE_ACCESS_I, CACHE_ACCESS_D, CACHE_MISS_I, CACHE_MISS_D, CACHE_WRITEBACK,
        CACHE_VC_HIT_I, CACHE_VC_HIT_D, CACHE_DRAM_FILL, CACHE_STORE_DRAIN_STALL,
        CACHE_BUSY_FILL, PORT_BOTH_REQUEST,
        NUM_CTR
    } ctr_e;

    longint ctr [NUM_CTR];
    bit     frozen;
    tag_e   t_ifid, t_idex, t_exmem, t_memwb;
    bit     mem_stall_q, d_active_q;

    function automatic void clear();
        foreach (ctr[i]) ctr[i] = 0;
    endfunction
    initial begin
        clear(); frozen = 0;
        t_ifid = T_OTHER; t_idex = T_OTHER; t_exmem = T_OTHER; t_memwb = T_OTHER;
        mem_stall_q = 0; d_active_q = 0;
    end

    always @(posedge itf.clk) begin
        automatic tag_e redir_cause, fetch_cause, mem_cause;
        automatic tag_e n_ifid = t_ifid, n_idex = t_idex, n_exmem = t_exmem, n_memwb = t_memwb;
        // pcache states: 0 RUN, 1 SWAP, 2 EVICT, 3 FILL
        automatic int cstate = int'(top_tb.dut.cache.state);
        automatic bit c_busy = (cstate != 0);
        automatic bit c_miss = top_tb.dut.cache.b_miss;
        automatic bit i_miss_now = c_miss && (top_tb.dut.cache.q.id == 1'b0);
        automatic bit d_rsp_now  = top_tb.dut.cache_rsp.resp && (top_tb.dut.cache_rsp_src == 1'b1);
        automatic logic [31:0] cinst = `C.mem_wb.rvfi.inst;

        if (itf.rst) begin
            t_ifid = T_OTHER; t_idex = T_OTHER; t_exmem = T_OTHER; t_memwb = T_OTHER;
            mem_stall_q = 0; d_active_q = 0;
        end else begin
            if (itf.valid[0] && itf.inst[0] == 32'h00102013) begin clear(); frozen = 0; end

            // ---- cause of a bubble created this cycle --------------------------------
            redir_cause = (`C.id_ex.opcode == 7'b1100111) ? T_FLUSH_JALR : T_FLUSH_BRANCH;
            if (`C.fetch.jalr_wait)                                        fetch_cause = T_FLUSH_JALR;
            else if (mem_stall_q)                                          fetch_cause = T_FETCH_RESTART;
            else if (c_busy || i_miss_now)                                 fetch_cause = T_ICACHE_MISS;
            else if (d_rsp_now || d_active_q)                              fetch_cause = T_PORT_CONFLICT;
            else                                                           fetch_cause = T_OTHER;
            mem_cause = `C.ex_mem.is_m ? T_MEM_MULDIV : T_MEM_DCACHE;

            // ---- commit-point accounting (current cycle) ---------------------------------
            if (!frozen) begin
                ctr[CYCLES]++;
                if (`C.mem_wb.valid) begin
                    ctr[COMMITS]++;
                    unique case (cinst[6:0])
                        7'b1100011: ctr[COMMIT_BRANCH]++;
                        7'b1101111: ctr[COMMIT_JAL]++;
                        7'b1100111: ctr[COMMIT_JALR]++;
                        7'b0000011: ctr[COMMIT_LOAD]++;
                        7'b0100011: ctr[COMMIT_STORE]++;
                        default:    if (cinst[6:0] == 7'b0110011 && cinst[31:25] == 7'b0000001) ctr[COMMIT_MULDIV]++;
                    endcase
                end else if (t_memwb == T_VALID) begin
                    ctr[LOST_OTHER]++;                      // shadow disagrees (see TAG_MISMATCH)
                end else begin
                    ctr[LOST_FLUSH_BRANCH + int'(t_memwb) - int'(T_FLUSH_BRANCH)]++;
                end
                if (`C.mem_wb.valid != (t_memwb == T_VALID)) ctr[TAG_MISMATCH]++;

                if (`C.if_id.valid)  ctr[VALID_IF_ID]++;
                if (`C.id_ex.valid)  ctr[VALID_ID_EX]++;
                if (`C.ex_mem.valid) ctr[VALID_EX_MEM]++;
                if (`C.mem_wb.valid) ctr[VALID_MEM_WB]++;
                if (`C.mem_stall) begin
                    ctr[MEM_STALL_CYCLES]++;
                    if (`C.ex_mem.is_m) ctr[MEM_STALL_MULDIV]++; else ctr[MEM_STALL_DCACHE]++;
                end
                if (`C.load_use && !`C.mem_stall) ctr[LOAD_USE_CYCLES]++;
                if (`C.redirect.valid) begin
                    if (redir_cause == T_FLUSH_JALR) ctr[REDIRECT_JALR]++; else ctr[REDIRECT_BRANCH]++;
                end
                if (top_tb.dut.cache.accept) begin
                    if (top_tb.dut.cache.ufp_id) ctr[CACHE_ACCESS_D]++; else ctr[CACHE_ACCESS_I]++;
                end
                if (c_miss) begin
                    if (top_tb.dut.cache.q.id) ctr[CACHE_MISS_D]++; else ctr[CACHE_MISS_I]++;
                    if (top_tb.dut.cache.vc_hit) begin
                        if (top_tb.dut.cache.q.id) ctr[CACHE_VC_HIT_D]++; else ctr[CACHE_VC_HIT_I]++;
                    end
                end
                if (cstate == 2 && top_tb.dut.cache.dfp_resp) ctr[CACHE_WRITEBACK]++;
                if (cstate == 3 && top_tb.dut.cache.dfp_resp) ctr[CACHE_DRAM_FILL]++;
                if (top_tb.dut.cache.force_drain) ctr[CACHE_STORE_DRAIN_STALL]++;
                if (c_busy) ctr[CACHE_BUSY_FILL]++;
                if (top_tb.dut.arbiter.d_active && |top_tb.dut.imem_req.rmask) ctr[PORT_BOTH_REQUEST]++;
            end

            // ---- shadow tag pipeline (mirrors the RTL update conditions) ---------------------
            // MEM/WB
            if (!`C.ex_mem.valid)       n_memwb = t_exmem;
            else if (`C.mem_stall)      n_memwb = mem_cause;
            else                        n_memwb = T_VALID;
            // EX/MEM
            if (!`C.mem_stall)          n_exmem = `C.id_ex.valid ? T_VALID : t_idex;
            // ID/EX
            if (!`C.mem_stall) begin
                if (`C.redirect.valid)  n_idex = redir_cause;
                else if (`C.load_use)   n_idex = T_LOAD_USE;
                else if (!`C.if_id.valid) n_idex = t_ifid;
                else                    n_idex = T_VALID;
            end
            // IF/ID
            if (`C.redirect.valid)      n_ifid = redir_cause;
            else if (`C.fetch.take)     n_ifid = T_VALID;
            else if (`C.decode_ready)   n_ifid = fetch_cause;

            t_ifid = n_ifid; t_idex = n_idex; t_exmem = n_exmem; t_memwb = n_memwb;
            mem_stall_q = `C.mem_stall;
            d_active_q  = top_tb.dut.arbiter.d_active;

            if (itf.valid[0] && itf.inst[0] == 32'h00202013) frozen = 1;
        end
    end

    final begin
        automatic int fd = $fopen("./perf.json", "w");
        automatic ctr_e e = e.first();
        $fwrite(fd, "{\n  \"core\": \"pipeline\"");
        do begin
            $fwrite(fd, ",\n  \"%s\": %0d", e.name(), ctr[e]);
            e = e.next();
        end while (e != NUM_CTR && e != e.first());
        $fwrite(fd, "\n}\n");
        $fclose(fd);
        $display("Perf: cycles %0d | commits %0d | lost: br %0d jalr %0d icache %0d port %0d restart %0d loaduse %0d dcache %0d muldiv %0d other %0d | tag mismatch %0d",
                 ctr[CYCLES], ctr[COMMITS], ctr[LOST_FLUSH_BRANCH], ctr[LOST_FLUSH_JALR],
                 ctr[LOST_ICACHE_MISS], ctr[LOST_PORT_CONFLICT], ctr[LOST_FETCH_RESTART],
                 ctr[LOST_LOAD_USE], ctr[LOST_MEM_DCACHE], ctr[LOST_MEM_MULDIV], ctr[LOST_OTHER],
                 ctr[TAG_MISMATCH]);
    end

endmodule

`undef C
