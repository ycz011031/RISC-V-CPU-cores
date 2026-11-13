// ============================================================================
// perf_probe : cycle-accounting probes for the out-of-order core (testbench only)
// ============================================================================
// Reads DUT internals hierarchically (top_tb.dut.*); no RTL changes. Counts
// over the same window as the monitor's IPC: cleared at the segment-start
// marker (0x00102013) and frozen at the segment-stop marker (0x00202013).
// At the end of simulation every counter is written to ./perf.json and the
// headline numbers are printed.
//
// Instantiated from top_tb.svh when ECE411_PERF is defined (run_xsim.py
// always defines it).
// ============================================================================

`define D top_tb.dut

module perf_probe (
    mon_itf itf
);

    typedef enum int {
        CYCLES,
        // ---- lane liveness -------------------------------------------------
        FETCH_LANE1, FETCH_LANE2,           // instruction-queue enqueues
        DECODE_LANE1, DECODE_LANE2,         // valid instruction in id_dis_reg
        DISPATCH_LANE1, DISPATCH_LANE2,     // ROB enqueues
        ISSUE_ALU1, ISSUE_ALU2, ISSUE_MUL, ISSUE_DIV, ISSUE_LUI, ISSUE_MEM, ISSUE_BR,
        CDB1_VALID, CDB2_VALID,
        COMMIT_LANE1, COMMIT_LANE2,
        // ---- front end -------------------------------------------------------
        FETCH_0, FETCH_1, FETCH_2,
        FETCH_STALL_ICACHE, FETCH_STALL_QUEUE_FULL, FETCH_STALL_FLUSH, FETCH_STALL_FTQ,
        IQ_EMPTY,
        // ---- dispatch --------------------------------------------------------
        DISPATCH_0, DISPATCH_1, DISPATCH_2,
        DISP0_NO_INST, DISP0_ROB_FULL, DISP0_PRF_FULL, DISP0_RS_FULL, DISP0_DECODE_STALL, DISP0_OTHER,
        RSFULL_ALU1, RSFULL_ALU2, RSFULL_MUL, RSFULL_DIV, RSFULL_LUI, RSFULL_MEM, RSFULL_BR,
        // ---- reservation stations: cycles with entries waiting --------------------
        RSOCC_ALU1, RSOCC_ALU2, RSOCC_MUL, RSOCC_DIV, RSOCC_LUI, RSOCC_MEM, RSOCC_BR,
        FUBUSY_MUL, FUBUSY_DIV,
        // ---- CDB: result ready but not granted --------------------------------------
        CDBBLK_ALU1, CDBBLK_ALU2, CDBBLK_MUL, CDBBLK_DIV, CDBBLK_LUI, CDBBLK_LD, CDBBLK_ST, CDBBLK_BR,
        // ---- commit accounting -----------------------------------------------------
        COMMIT_0, COMMIT_1, COMMIT_2,
        C0_MISPREDICT_RECOVERY,             // 0 commits while refilling after a flush
        C0_ROB_EMPTY,                       // front end could not keep the ROB fed
        C0_HEAD_LOAD, C0_HEAD_STORE, C0_HEAD_MULDIV, C0_HEAD_BRANCH, C0_HEAD_ALU,
        C1_ONLY_ONE_IN_ROB, C1_SECOND_NOT_DONE, C1_SECOND_NOT_SIMPLE, C1_MISPREDICT, C1_OTHER,
        // ---- control flow ----------------------------------------------------------
        FLUSHES, COMMIT_BRANCH, COMMIT_JAL, COMMIT_JALR, MISPRED_BRANCH, MISPRED_JAL, MISPRED_JALR,
        // ---- memory -----------------------------------------------------------------
        ICACHE_DFP_BUSY, DCACHE_DFP_BUSY, COMMIT_LOAD, COMMIT_STORE, COMMIT_MULDIV,
        NUM_CTR
    } ctr_e;

    longint ctr [NUM_CTR];
    bit     frozen;

    function automatic void clear();
        foreach (ctr[i]) ctr[i] = 0;
    endfunction
    initial begin clear(); frozen = 0; end

    function automatic logic [6:0] op(input logic [31:0] inst); return inst[6:0]; endfunction
    function automatic bit is_muldiv(input logic [31:0] inst);
        return inst[6:0] == 7'b0110011 && inst[31:25] == 7'b0000001;
    endfunction

    // reservation-station occupancy (ALU stations use an unpacked valid array)
    function automatic bit any_unpacked16(input logic v [16]);
        foreach (v[i]) if (v[i]) return 1;
        return 0;
    endfunction
    function automatic bit any_unpacked8(input logic v [8]);
        foreach (v[i]) if (v[i]) return 1;
        return 0;
    endfunction

    logic [4:0]  rob_head_i, rob_head_n;
    logic [5:0]  rob_head, rob_tail, rob_diff;
    bit          in_recovery;

    always @(posedge itf.clk iff !itf.rst) begin
        automatic int n_commit, n_fetch, n_disp;
        automatic logic [31:0] head_inst;
        automatic bit head_status, second_status, second_valid;
        automatic logic [2:0] second_type;
        automatic int rob_count;

        // ---- ROI markers -----------------------------------------------------------
        for (int c = 0; c < 2; c++) begin
            if (itf.valid[c] && itf.inst[c] == 32'h00102013) begin clear(); frozen = 0; end
        end

        if (!frozen) begin
            ctr[CYCLES]++;

            // ---- front end ---------------------------------------------------------
            n_fetch = int'(`D.instr_enq) + int'(`D.instr_enq2);
            if (`D.instr_enq)  ctr[FETCH_LANE1]++;
            if (`D.instr_enq2) ctr[FETCH_LANE2]++;
            ctr[FETCH_0 + n_fetch]++;
            if (n_fetch == 0) begin
                if (`D.flush)                                ctr[FETCH_STALL_FLUSH]++;
                else if (`D.i_need_resp)                     ctr[FETCH_STALL_ICACHE]++;
                else if (`D.instr_full && !`D.instr_deq)     ctr[FETCH_STALL_QUEUE_FULL]++;
                else if (`D.ftq_stall)                       ctr[FETCH_STALL_FTQ]++;
            end
            if (`D.instr_empty) ctr[IQ_EMPTY]++;

            // ---- decode / dispatch ---------------------------------------------------
            if (`D.id_dis_reg_1.i_valid) ctr[DECODE_LANE1]++;
            if (`D.id_dis_reg_2.i_valid) ctr[DECODE_LANE2]++;
            n_disp = int'(`D.rob_enq_1) + int'(`D.rob_enq_2);
            if (`D.rob_enq_1) ctr[DISPATCH_LANE1]++;
            if (`D.rob_enq_2) ctr[DISPATCH_LANE2]++;
            ctr[DISPATCH_0 + n_disp]++;
            if (n_disp == 0) begin
                if (!`D.id_dis_reg_1.i_valid && !`D.id_dis_reg_2.i_valid) ctr[DISP0_NO_INST]++;
                else if (`D.rob_full_1 || (`D.id_dis_reg_2.i_valid && `D.rob_full_2)) ctr[DISP0_ROB_FULL]++;
                else if (`D.PRF_full || (`D.id_dis_reg_2.i_valid && `D.PRF_almost_full)) ctr[DISP0_PRF_FULL]++;
                else if (`D.dp_stage_1.matchfull || `D.dp_stage_2.matchfull) ctr[DISP0_RS_FULL]++;
                else if (`D.decode_stall) ctr[DISP0_DECODE_STALL]++;
                else ctr[DISP0_OTHER]++;
            end
            if (`D.dispatch_stall) begin
                if (`D.dispatch_ready_ALU_1 && `D.RS_ALU_full_1) ctr[RSFULL_ALU1]++;
                if (`D.dispatch_ready_ALU_2 && `D.RS_ALU_full_2) ctr[RSFULL_ALU2]++;
                if ((`D.dispatch_ready_MUL_1 && `D.RS_MUL_full_1) || (`D.dispatch_ready_MUL_2 && `D.RS_MUL_full_2)) ctr[RSFULL_MUL]++;
                if ((`D.dispatch_ready_DIV_1 && `D.RS_DIV_full_1) || (`D.dispatch_ready_DIV_2 && `D.RS_DIV_full_2)) ctr[RSFULL_DIV]++;
                if ((`D.dispatch_ready_LUI_1 && `D.RS_LUI_full_1) || (`D.dispatch_ready_LUI_2 && `D.RS_LUI_full_2)) ctr[RSFULL_LUI]++;
                if ((`D.dispatch_ready_MEM_1 && `D.RS_MEM_full_1) || (`D.dispatch_ready_MEM_2 && `D.RS_MEM_full_2)) ctr[RSFULL_MEM]++;
                if ((`D.dispatch_ready_BR_1  && `D.RS_BR_full_1)  || (`D.dispatch_ready_BR_2  && `D.RS_BR_full_2))  ctr[RSFULL_BR]++;
            end

            // ---- issue (an op enters the functional unit's input register) -------------
            if (`D.func_alu1_ready && `D.RS_alu1_out_valid_next) ctr[ISSUE_ALU1]++;
            if (`D.func_alu2_ready && `D.RS_alu2_out_valid_next) ctr[ISSUE_ALU2]++;
            if (`D.func_mul_ready  && `D.RS_mul_out_valid_next)  ctr[ISSUE_MUL]++;
            if (`D.func_div_ready  && `D.RS_div_out_valid_next)  ctr[ISSUE_DIV]++;
            if (`D.func_lui_ready  && `D.RS_lui_out_valid_next)  ctr[ISSUE_LUI]++;
            if (`D.func_mem_ready  && `D.RS_mem_out_valid_next)  ctr[ISSUE_MEM]++;
            if (`D.func_br_ready   && `D.RS_br_out_valid_next)   ctr[ISSUE_BR]++;
            if (any_unpacked16(`D.res_station_ALU1.entry_valid)) ctr[RSOCC_ALU1]++;
            if (any_unpacked16(`D.res_station_ALU2.entry_valid)) ctr[RSOCC_ALU2]++;
            if (any_unpacked8(`D.res_station_MUL.entry_valid)) ctr[RSOCC_MUL]++;
            if (any_unpacked8(`D.res_station_DIV.entry_valid)) ctr[RSOCC_DIV]++;
            if (any_unpacked8(`D.res_station_LUI.entry_valid)) ctr[RSOCC_LUI]++;
            if (|`D.res_station_MEM.entry_valid) ctr[RSOCC_MEM]++;
            if (any_unpacked8(`D.res_station_BR.entry_valid)) ctr[RSOCC_BR]++;
            if (!`D.func_mul_ready) ctr[FUBUSY_MUL]++;
            if (!`D.func_div_ready) ctr[FUBUSY_DIV]++;

            // ---- CDB ---------------------------------------------------------------------
            if (`D.cdb_main_1.valid) ctr[CDB1_VALID]++;
            if (`D.cdb_main_2.valid) ctr[CDB2_VALID]++;
            if (`D.alu1_cdb.valid && !`D.alu1_cdb_rdy) ctr[CDBBLK_ALU1]++;
            if (`D.alu2_cdb.valid && !`D.alu2_cdb_rdy) ctr[CDBBLK_ALU2]++;
            if (`D.mul_cdb.valid  && !`D.mul_cdb_rdy)  ctr[CDBBLK_MUL]++;
            if (`D.div_cdb.valid  && !`D.div_cdb_rdy)  ctr[CDBBLK_DIV]++;
            if (`D.lui_cdb.valid  && !`D.lui_cdb_rdy)  ctr[CDBBLK_LUI]++;
            if (`D.ld_cdb.valid   && !`D.ld_cdb_rdy)   ctr[CDBBLK_LD]++;
            if (`D.st_cdb.valid   && !`D.st_cdb_rdy)   ctr[CDBBLK_ST]++;
            if (`D.br_cdb.valid   && !`D.br_cdb_rdy)   ctr[CDBBLK_BR]++;

            // ---- memory --------------------------------------------------------------------
            if (`D.dfp_read_i || `D.dfp_write_i) ctr[ICACHE_DFP_BUSY]++;
            if (`D.dfp_read_d || `D.dfp_write_d) ctr[DCACHE_DFP_BUSY]++;

            // ---- commit accounting -----------------------------------------------------------
            n_commit = int'(`D.rvfi_entry_commit_1.valid) + int'(`D.rvfi_entry_commit_2.valid);
            ctr[COMMIT_0 + n_commit]++;
            if (`D.rvfi_entry_commit_1.valid) ctr[COMMIT_LANE1]++;
            if (`D.rvfi_entry_commit_2.valid) ctr[COMMIT_LANE2]++;

            rob_head   = `D.ROB_i.head;
            rob_tail   = `D.ROB_i.tail;
            rob_head_i = rob_head[4:0];
            rob_head_n = rob_head_i + 5'd1;
            rob_diff   = rob_tail - rob_head;                 // 6-bit pointers with wrap bit
            rob_count  = int'(rob_diff);
            head_inst  = `D.ROB_i.rvfi_rob_entry[rob_head_i].inst;
            second_valid  = `D.ROB_i.rob_entry[rob_head_n].valid;
            second_status = `D.ROB_i.rob_entry[rob_head_n].status;
            second_type   = `D.ROB_i.rob_entry[rob_head_n].inst_type;

            if (n_commit == 0) begin
                if (in_recovery)                ctr[C0_MISPREDICT_RECOVERY]++;
                else if (rob_count == 0)        ctr[C0_ROB_EMPTY]++;
                else if (op(head_inst) == 7'b0000011) ctr[C0_HEAD_LOAD]++;
                else if (op(head_inst) == 7'b0100011) ctr[C0_HEAD_STORE]++;
                else if (is_muldiv(head_inst))  ctr[C0_HEAD_MULDIV]++;
                else if (op(head_inst) inside {7'b1100011, 7'b1101111, 7'b1100111}) ctr[C0_HEAD_BRANCH]++;
                else                            ctr[C0_HEAD_ALU]++;
            end else if (n_commit == 1) begin
                if (`D.flush)                   ctr[C1_MISPREDICT]++;
                else if (rob_count < 2)         ctr[C1_ONLY_ONE_IN_ROB]++;
                else if (second_type != 3'd0)   ctr[C1_SECOND_NOT_SIMPLE]++;   // branch/jump/store
                else if (!second_status)        ctr[C1_SECOND_NOT_DONE]++;
                else                            ctr[C1_OTHER]++;
            end

            // ---- control flow (commit side, both lanes) ---------------------------------------
            if (`D.flush) ctr[FLUSHES]++;
            for (int c = 0; c < 2; c++) begin
                automatic logic [31:0] inst = (c == 0) ? `D.rvfi_entry_commit_1.inst : `D.rvfi_entry_commit_2.inst;
                automatic bit v = (c == 0) ? `D.rvfi_entry_commit_1.valid : `D.rvfi_entry_commit_2.valid;
                automatic bit mp = (c == 0) ? (`D.rob_out_1.valid && `D.rob_out_1.br_mispred)
                                            : (`D.rob_out_2.valid && `D.rob_out_2.br_mispred);
                if (v) begin
                    unique case (op(inst))
                        7'b1100011: begin ctr[COMMIT_BRANCH]++; if (mp) ctr[MISPRED_BRANCH]++; end
                        7'b1101111: begin ctr[COMMIT_JAL]++;    if (mp) ctr[MISPRED_JAL]++;    end
                        7'b1100111: begin ctr[COMMIT_JALR]++;   if (mp) ctr[MISPRED_JALR]++;   end
                        7'b0000011: ctr[COMMIT_LOAD]++;
                        7'b0100011: ctr[COMMIT_STORE]++;
                        default:    if (is_muldiv(inst)) ctr[COMMIT_MULDIV]++;
                    endcase
                end
            end
        end

        // recovery window: from a mispredict flush until the next commit
        if (`D.flush) in_recovery = 1;
        else if (n_commit != 0) in_recovery = 0;

        for (int c = 0; c < 2; c++) begin
            if (itf.valid[c] && itf.inst[c] == 32'h00202013) frozen = 1;
        end
    end

    final begin
        automatic int fd = $fopen("./perf.json", "w");
        automatic ctr_e e = e.first();
        $fwrite(fd, "{\n  \"core\": \"ooo\"");
        do begin
            $fwrite(fd, ",\n  \"%s\": %0d", e.name(), ctr[e]);
            e = e.next();
        end while (e != NUM_CTR && e != e.first());
        $fwrite(fd, "\n}\n");
        $fclose(fd);
        $display("Perf: cycles %0d | commit 0/1/2: %0d/%0d/%0d | dispatch 0/1/2: %0d/%0d/%0d | fetch 0/1/2: %0d/%0d/%0d | flushes %0d",
                 ctr[CYCLES], ctr[COMMIT_0], ctr[COMMIT_1], ctr[COMMIT_2],
                 ctr[DISPATCH_0], ctr[DISPATCH_1], ctr[DISPATCH_2],
                 ctr[FETCH_0], ctr[FETCH_1], ctr[FETCH_2], ctr[FLUSHES]);
    end

endmodule

`undef D
