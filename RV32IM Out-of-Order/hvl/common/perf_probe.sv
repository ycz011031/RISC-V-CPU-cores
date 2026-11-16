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
`define LB top_tb.dut.if_stage_i.line_buf_superscalar_i

module perf_probe
import rv32i_types::*;
(
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
        // C0_HEAD_ALU split by where the head instruction is
        HA_RS_OPND_WAIT,                    // in its ALU station, an operand not ready
        HA_RS_NOT_PICKED,                   // in its ALU station, ready, another entry picked
        HA_RS_FU_STALL,                     // picked, ALU input register not free (CDB back-pressure)
        HA_IN_FU,                           // in the ALU input register, result goes to the CDB register
        HA_CDB_BLOCKED,                     // in the ALU input register, CDB granted to another unit
        HA_ON_CDB,                          // on the CDB: ROB marks it done at this edge
        HA_LUI_UNIT,                        // lui / auipc (LUI station or unit)
        HA_OTHER,
        C0_HEAD_ON_CDB,                     // any type: head result on the CDB, done at this edge
        // ... and by cycles since it was dispatched (dispatch cycle = 0)
        HA_AGE_1, HA_AGE_2, HA_AGE_3, HA_AGE_4, HA_AGE_5_8, HA_AGE_9_16, HA_AGE_17P,
        // mispredicts: cycles from the branch's result on the CDB to its commit (the flush),
        // i.e. what recovering at execute would start the refetch earlier by
        MP_RESOLVE_TO_COMMIT, MP_RESOLVED_AT_HEAD,
        // C0_HEAD_MULDIV split by where the head is
        HM_RS_OPND_WAIT,                    // in the MUL/DIV station, an operand not ready
        HM_RS_UNIT_BUSY,                    // in the station, ready, unit busy
        HM_RS_READY,                        // in the station, ready, unit free (moves this edge / behind another)
        HM_INREG_UNIT_BUSY,                 // in the unit's input register, unit busy with an older op
        HM_EXECUTING,                       // in the unit
        HM_CDB_BLOCKED,                     // unit done, CDB granted to another unit
        HM_ON_CDB, HM_OTHER,
        // C0_HEAD_BRANCH split
        HB_RS_OPND_WAIT, HB_RS_READY, HB_IN_FU, HB_ON_CDB, HB_OTHER,
        // C0_HEAD_LOAD split
        HL_MEM_RS,                          // in the memory station (operands / address)
        HL_AGEN,                            // in the address-generation register
        HL_LQ_STORE_DEP,                    // in the load queue behind an older store
        HL_LQ_WAIT,                         // in the load queue, no store dependence (memory port busy)
        HL_DCACHE,                          // access in the D-cache
        HL_ON_CDB, HL_OTHER,
        // MUL / DIV stations and units (per cycle; *_OPS are op-cycles, i.e. summed over entries)
        MUL_RS_OCC_SUM, MUL_RS_MAX, MUL_RS_FULL, MUL_OPND_WAIT_OPS,
        MUL_UNIT_WAIT_CYC,                  // >= 1 ready op (station or input register) while the unit is busy
        MUL_UNIT_WAIT_OPS,                  // number of such ops, summed over cycles
        MUL_STARTS, MUL_UNIT_BUSY_CYC, MUL_DONE_CDB_WAIT,
        DIV_RS_OCC_SUM, DIV_RS_MAX, DIV_RS_FULL, DIV_OPND_WAIT_OPS,
        DIV_UNIT_WAIT_CYC, DIV_UNIT_WAIT_OPS,
        DIV_STARTS, DIV_UNIT_BUSY_CYC, DIV_DONE_CDB_WAIT,
        // commit latency: commits in the cycle after a 0-commit cycle whose head was on the CDB,
        // and dispatch blocked by a full ROB / PRF while the head's result is on the CDB
        CU_AFTER_ONCDB_0, CU_AFTER_ONCDB_1, CU_AFTER_ONCDB_2,
        RETIRE_BLOCK_ONCDB,
        // old head classification (ROB RVFI copy, written only at completion) vs. the true type,
        // over the 0-commit cycles with a non-empty ROB outside recovery
        XO_WORD_ZERO, XO_WORD_STALE, XO_WORD_SAME,
        XO_ALU, XO_ALU_TRUE_LOAD, XO_ALU_TRUE_STORE, XO_ALU_TRUE_MULDIV, XO_ALU_TRUE_BRANCH, XO_ALU_TRUE_ALU,
        // ---- dispatch cycle accounting (both lanes stall together, so each cycle is one of these) ----
        DS_2, DS_1,                         // dispatched 2 / 1 (only one instruction available)
        DS_EMPTY_RECOVERY,                  // nothing to dispatch, refilling after a mispredict flush
        DS_EMPTY_FRONTEND,                  // nothing to dispatch otherwise
        DS_ROB_FULL, DS_PRF_FULL,
        DS_RS_ALU, DS_RS_MUL, DS_RS_DIV, DS_RS_LUI, DS_RS_MEM, DS_RS_BR,
        DS_DECODE_STALL, DS_OTHER,
        // ROB / PRF full: the head (the oldest unfinished instruction, never waiting on an operand)
        WF_HEAD_MUL_UNIT_WAIT,              // MUL/DIV ready, waiting for the busy unit
        WF_HEAD_MUL_EXEC,                   // MUL/DIV in the unit or on the CDB
        WF_HEAD_MUL_OTHER,
        WF_HEAD_LOAD, WF_HEAD_STORE, WF_HEAD_BRANCH, WF_HEAD_ALU, WF_HEAD_ON_CDB,
        // station full: entries in the full station, and how many wait on a value that is
        // (transitively) produced by a MUL/DIV that had not finished when the consumer dispatched
        RSF_ENTRIES, RSF_WAITING, RSF_WAIT_MULCHAIN, RSF_CYC_ANY_MULCHAIN,
        // all dispatched ops: operands not ready at dispatch, and of those on a MUL/DIV chain
        OPND_NOT_READY, OPND_MULCHAIN,
        // ---- front end: line buffer --------------------------------------------------
        FE_LINE_SEQ,                        // new line requested: sequential (fell off the end of the line)
        FE_LINE_TAKEN,                      // ... predicted-taken branch / jump to another line
        FE_LINE_REDIRECT,                   // ... flush (mispredict) redirect
        FE_LINE_IN_LAST2, FE_LINE_IN_LAST4, // the requested line was one of the last 1 / 3 other lines used
        FE_LINE_SEQ_OR_LAST4,               // covered by next-line prefetch or a 4-line buffer
        FE_REFILL_HIT_CYC,                  // fetch stalled waiting for the line, I-cache hit path
        FE_REFILL_MISS_CYC,                 // ... I-cache miss (fill from memory)
        FE1_TAKEN, FE1_LANE2_CTRL, FE1_END_OF_LINE, FE1_QUEUE, FE1_OTHER,   // why only 1 fetched
        FE0_REFILL, FE0_QUEUE_FULL, FE0_FLUSH, FE0_OTHER,                    // why 0 fetched
        MUL_UNITS_BUSY_SUM,
        // line buffer: where the next line was when fetch moved to it, prefetches, response bypass
        LB_NEXT_READY, LB_NEXT_INFLIGHT, LB_NEXT_DEMAND, LB_PREFETCH, LB_BYPASS,
        LB_PF_EVICT_NX,                     // a prefetch took the entry holding pc_next's line
        LB_PC_LOST,                         // fetch waits because pc's line is in no entry (taken by a prefetch)
        FE2_SLOT2_CTRL,                     // 2 fetched, slot 2 holds the group's branch / jal
        FE2_SLOT2_TAKEN,                    // ... predicted taken
        FE2_CROSS_LINE,                     // 2 fetched, slot 2 from the next line
        // memory station (in-order: only the oldest entry issues), per cycle with entries
        MRS_BUSY,                           // station not empty
        MRS_HEAD_ADDR_WAIT,                 // oldest entry: address operand not ready
        MRS_HEAD_DATA_WAIT,                 // oldest entry: a store, address ready, data not ready
        MRS_HEAD_READY_STALL,               // oldest entry ready, AGU register not free (queue full / CDB)
        MRS_HEAD_ISSUES,                    // oldest entry issues this cycle
        MRS_BEHIND_READY,                   // oldest entry not issuing and a younger entry is ready
        MRS_BEHIND_READY_LOAD,              // ... a younger ready entry is a load
        MRSF_ADDR_WAIT, MRSF_DATA_WAIT, MRSF_READY_STALL,   // the same, in cycles dispatch is blocked by the full station
        SQ_FULL_CYC, LQ_FULL_CYC,
        // commit lane 2 only retires plain ops: 1 commit while the 2nd-oldest is done but a store / branch / jump
        HL_LQ_YOUNGER_SENT,                 // head load ready in the load queue, a younger load sent to the D-cache instead
        HL_LQ_PORT_STORE,                   // head load ready in the load queue, the D-cache port busy with a store
        C1_LANE2_RULE, C1_LANE2_RULE_STORE, C1_LANE2_RULE_BRANCH, C1_LANE2_RULE_JUMP,
        C1_LANE2_RULE_WINFULL,              // ... while dispatch is blocked by a full ROB / rename buffer
        DS_WINFULL_C2, DS_WINFULL_C1, DS_WINFULL_C0,   // commits in the cycles dispatch is blocked by a full window                 // sum over cycles of busy multipliers
        // ---- control flow ----------------------------------------------------------
        FLUSHES, COMMIT_BRANCH, COMMIT_JAL, COMMIT_JALR, MISPRED_BRANCH, MISPRED_JAL, MISPRED_JALR,
        // ---- memory -----------------------------------------------------------------
        ICACHE_DFP_BUSY, DCACHE_DFP_BUSY, COMMIT_LOAD, COMMIT_STORE, COMMIT_MULDIV,
        // pcache: accesses accepted, main-array misses, of those served by the
        // victim cache, DRAM line fills, write-backs, cycles out of the pipeline state
        ICACHE_ACCESS, ICACHE_MISS, ICACHE_VC_HIT, ICACHE_DRAM_FILL, ICACHE_BUSY,
        DCACHE_ACCESS, DCACHE_MISS, DCACHE_VC_HIT, DCACHE_DRAM_FILL, DCACHE_WRITEBACK, DCACHE_BUSY,
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

    localparam int ROB_N = 2 ** ROBADDR_L;
    localparam int PRF_N = 2 ** PADDR_L;
    logic [ROBADDR_L-1:0] rob_head_i, rob_head_n;
    logic [ROBADDR_L:0]   rob_head, rob_tail, rob_diff;
    bit          in_recovery;
    longint      disp_cyc [ROB_N];             // dispatch cycle per ROB index
    logic [31:0] disp_inst [ROB_N];            // instruction per ROB index (the ROB's RVFI copy is only
                                            // written at completion)
    longint      cyc = 0;                   // free-running cycle count
    longint      done_cyc [ROB_N];             // cycle each ROB index was on a CDB

    bit          prev_c0_oncdb;
    bit          mchain [PRF_N];
    logic [26:0] fe_lines [4] = '{default: '1};               // per physical register: value on a MUL/DIV chain

    // tally the entries of a station: total, waiting on an operand, waiting on a MUL/DIV chain
    function automatic void tally(input RS_entry_t e, input bit v, inout int n, inout int w, inout int t);
        automatic bit w1, w2;
        if (!v) return;
        n++;
        w1 = e.rs1_use && !e.rs1_valid;
        w2 = e.rs2_use && !e.rs2_valid;
        if (w1 || w2) w++;
        if ((w1 && mchain[e.rs1_paddr]) || (w2 && mchain[e.rs2_paddr])) t++;
    endfunction

    function automatic bit on_cdb(input logic [ROBADDR_L-1:0] h);
        return (`D.cdb_main_1.valid && `D.cdb_main_1.rob_addr == h) ||
               (`D.cdb_main_2.valid && `D.cdb_main_2.rob_addr == h);
    endfunction

    // entry i of a 2-way station (MUL, DIV, LUI, BR: 8 entries, no same-cycle CDB forwarding)
    `define RS2_HAS(RS, i, h)  (`D.RS.entry_valid[i] && `D.RS.RS_entry[i].rob_addr == h)
    `define RS2_RDY(RS, i)     ((!`D.RS.RS_entry[i].rs1_use || `D.RS.RS_entry[i].rs1_valid) && \
                                (!`D.RS.RS_entry[i].rs2_use || `D.RS.RS_entry[i].rs2_valid))

    // where is the MUL/DIV with ROB index h?
    function automatic ctr_e locate_muldiv(input logic [ROBADDR_L-1:0] h);
        for (int i = 0; i < 8; i++) begin
            if (`RS2_HAS(res_station_MUL, i, h))
                return !`RS2_RDY(res_station_MUL, i) ? HM_RS_OPND_WAIT : (`D.func_mul_ready ? HM_RS_READY : HM_RS_UNIT_BUSY);
            if (`RS2_HAS(res_station_DIV, i, h))
                return !`RS2_RDY(res_station_DIV, i) ? HM_RS_OPND_WAIT : (`D.func_div_ready ? HM_RS_READY : HM_RS_UNIT_BUSY);
        end
        for (int k = 0; k < $size(`D.func_mul_i.slot_busy); k++)
            if (`D.func_mul_i.slot_busy[k] && `D.func_mul_i.slot_inst[k].rob_addr == h)
                return (`D.func_mul_i.slot_complete[k] && !(`D.mul_cdb_rdy && `D.func_mul_i.done_idx == k))
                       ? HM_CDB_BLOCKED : HM_EXECUTING;
        if (`D.func_div_i.busy && `D.func_div_i.cur_inst.rob_addr == h)
            return (`D.func_div_i.div_complete && !`D.div_cdb_rdy) ? HM_CDB_BLOCKED : HM_EXECUTING;
        if (`D.RS_mul_out_valid && `D.RS_mul_out.rob_addr == h) return `D.func_mul_i.busy ? HM_INREG_UNIT_BUSY : HM_EXECUTING;
        if (`D.RS_div_out_valid && `D.RS_div_out.rob_addr == h) return `D.func_div_i.busy ? HM_INREG_UNIT_BUSY : HM_EXECUTING;
        if (on_cdb(h)) return HM_ON_CDB;
        return HM_OTHER;
    endfunction

    function automatic ctr_e locate_branch(input logic [ROBADDR_L-1:0] h);
        for (int i = 0; i < 8; i++)
            if (`RS2_HAS(res_station_BR, i, h)) return `RS2_RDY(res_station_BR, i) ? HB_RS_READY : HB_RS_OPND_WAIT;
        if (`D.RS_br_out_valid && `D.RS_br_out.rob_addr == h) return HB_IN_FU;
        if (on_cdb(h)) return HB_ON_CDB;
        return HB_OTHER;
    endfunction

    function automatic ctr_e locate_load(input logic [ROBADDR_L-1:0] h);
        for (int i = 0; i < 8; i++)
            if (`D.res_station_MEM.entry_valid[i] && `D.res_station_MEM.RS_entry[i].rob_addr == h) return HL_MEM_RS;
        if (`D.RS_mem_out_valid && `D.RS_mem_out.rob_addr == h) return HL_AGEN;
        if (`D.mem_queue_out_controller_i.load_busy && `D.mem_queue_out_controller_i.load_reg.rob_addr == h) return HL_DCACHE;
        for (int i = 0; i < $size(`D.load_queue_i.entry_valid); i++)
            if (`D.load_queue_i.entry_valid[i] && `D.load_queue_i.load_entry[i].rob_addr == h)
                return (`D.load_queue_i.load_entry[i].depend_idx != '0) ? HL_LQ_STORE_DEP : HL_LQ_WAIT;
        if (on_cdb(h)) return HL_ON_CDB;
        return HL_OTHER;
    endfunction

    // where is the instruction with ROB index h (ALU path)?
    function automatic ctr_e locate_alu(input logic [ROBADDR_L-1:0] h);
        for (int i = 0; i < 16; i++) begin
            if (`D.res_station_ALU1.entry_valid[i] && `D.res_station_ALU1.RS_entry[i].rob_addr == h) begin
                if (!(`D.RS_alu1_out_valid_next && `D.res_station_ALU1.out_idx == 4'(i))) return
                    ((!`D.res_station_ALU1.RS_entry[i].rs1_use || `D.res_station_ALU1.RS_entry[i].rs1_valid ||
                      `D.res_station_ALU1.rs1_cdb1_forwarding[i] || `D.res_station_ALU1.rs1_cdb2_forwarding[i]) &&
                     (!`D.res_station_ALU1.RS_entry[i].rs2_use || `D.res_station_ALU1.RS_entry[i].rs2_valid ||
                      `D.res_station_ALU1.rs2_cdb1_forwarding[i] || `D.res_station_ALU1.rs2_cdb2_forwarding[i]))
                     ? HA_RS_NOT_PICKED : HA_RS_OPND_WAIT;
                return `D.func_alu1_ready ? HA_OTHER : HA_RS_FU_STALL;   // picked and issued: never the head at C0
            end
            if (`D.res_station_ALU2.entry_valid[i] && `D.res_station_ALU2.RS_entry[i].rob_addr == h) begin
                if (!(`D.RS_alu2_out_valid_next && `D.res_station_ALU2.out_idx == 4'(i))) return
                    ((!`D.res_station_ALU2.RS_entry[i].rs1_use || `D.res_station_ALU2.RS_entry[i].rs1_valid ||
                      `D.res_station_ALU2.rs1_cdb1_forwarding[i] || `D.res_station_ALU2.rs1_cdb2_forwarding[i]) &&
                     (!`D.res_station_ALU2.RS_entry[i].rs2_use || `D.res_station_ALU2.RS_entry[i].rs2_valid ||
                      `D.res_station_ALU2.rs2_cdb1_forwarding[i] || `D.res_station_ALU2.rs2_cdb2_forwarding[i]))
                     ? HA_RS_NOT_PICKED : HA_RS_OPND_WAIT;
                return `D.func_alu2_ready ? HA_OTHER : HA_RS_FU_STALL;
            end
        end
        if (`D.RS_alu1_out_valid && `D.RS_alu1_out.rob_addr == h) return `D.alu1_cdb_rdy ? HA_IN_FU : HA_CDB_BLOCKED;
        if (`D.RS_alu2_out_valid && `D.RS_alu2_out.rob_addr == h) return `D.alu2_cdb_rdy ? HA_IN_FU : HA_CDB_BLOCKED;
        if (`D.cdb_main_1.valid && `D.cdb_main_1.rob_addr == h) return HA_ON_CDB;
        if (`D.cdb_main_2.valid && `D.cdb_main_2.rob_addr == h) return HA_ON_CDB;
        return HA_OTHER;
    endfunction

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
            if (n_fetch == 1) begin
                if (`D.if_stage_i.channel_1_branching) ctr[FE1_TAKEN]++;
                else if (`D.if_stage_i.opcode2 inside {7'b1101111, 7'b1100011, 7'b1100111}) ctr[FE1_LANE2_CTRL]++;
                else if (`D.if_stage_i.end_linebuf) ctr[FE1_END_OF_LINE]++;
                else if (`D.instr_almost_full) ctr[FE1_QUEUE]++;
                else ctr[FE1_OTHER]++;
            end else if (n_fetch == 0) begin
                if (`D.flush || `D.if_stage_i.flushlatch) ctr[FE0_FLUSH]++;
                else if (`D.i_need_resp) ctr[FE0_REFILL]++;
                else if (`D.instr_full) ctr[FE0_QUEUE_FULL]++;
                else ctr[FE0_OTHER]++;
            end
            if (`D.i_need_resp) ctr[int'(`D.i_cache.state) == 0 ? FE_REFILL_HIT_CYC : FE_REFILL_MISS_CYC]++;
            if (`D.if_stage_i.i_request) begin
                if (!`LB.nx_hit) ctr[LB_NEXT_DEMAND]++;
                else if (`LB.st[`LB.nx_idx] == 2'd3) ctr[LB_NEXT_READY]++;
                else ctr[LB_NEXT_INFLIGHT]++;
            end
            if (`LB.prefetch) ctr[LB_PREFETCH]++;
            if (`LB.prefetch && `LB.nx_hit && `LB.p_vic == `LB.nx_idx) ctr[LB_PF_EVICT_NX]++;
            if (`LB.started && !`LB.pc_hit) ctr[LB_PC_LOST]++;
            begin
                automatic int hd = int'(`D.res_station_MEM.head) % 8;
                if (`D.store_queue_i.store_full) ctr[SQ_FULL_CYC]++;
                if (`D.load_queue_i.load_full)   ctr[LQ_FULL_CYC]++;
                if (|`D.res_station_MEM.entry_valid) begin
                    automatic RS_entry_t e = `D.res_station_MEM.RS_entry[hd];
                    automatic bit a_ok = !e.rs1_use || e.rs1_valid || `D.res_station_MEM.rs1_cdb1_forwarding[hd] || `D.res_station_MEM.rs1_cdb2_forwarding[hd];
                    automatic bit d_ok = !e.rs2_use || e.rs2_valid || `D.res_station_MEM.rs2_cdb1_forwarding[hd] || `D.res_station_MEM.rs2_cdb2_forwarding[hd];
                    automatic bit issue = a_ok && d_ok && `D.func_mem_ready;
                    automatic bit full_blk = `D.dispatch_stall && ((`D.dispatch_ready_MEM_1 && `D.RS_MEM_full_1) || (`D.dispatch_ready_MEM_2 && `D.RS_MEM_full_2));
                    ctr[MRS_BUSY]++;
                    if (!a_ok)             begin ctr[MRS_HEAD_ADDR_WAIT]++;   if (full_blk) ctr[MRSF_ADDR_WAIT]++;   end
                    else if (!d_ok)        begin ctr[MRS_HEAD_DATA_WAIT]++;   if (full_blk) ctr[MRSF_DATA_WAIT]++;   end
                    else if (!issue)       begin ctr[MRS_HEAD_READY_STALL]++; if (full_blk) ctr[MRSF_READY_STALL]++; end
                    else                   ctr[MRS_HEAD_ISSUES]++;
                    if (!issue) begin
                        automatic bit any = 0, anyl = 0;
                        for (int i = 0; i < 8; i++) begin
                            automatic RS_entry_t f = `D.res_station_MEM.RS_entry[i];
                            if (i != hd && `D.res_station_MEM.entry_valid[i] &&
                                (!f.rs1_use || f.rs1_valid) && (!f.rs2_use || f.rs2_valid)) begin
                                any = 1; if (!f.rs2_use) anyl = 1;      // loads use no rs2
                            end
                        end
                        if (any)  ctr[MRS_BEHIND_READY]++;
                        if (anyl) ctr[MRS_BEHIND_READY_LOAD]++;
                    end
                end
            end
            if (n_fetch == 2) begin
                if (`D.if_stage_i.s2_ctrl) ctr[FE2_SLOT2_CTRL]++;
                if (`D.if_stage_i.s2_taken) ctr[FE2_SLOT2_TAKEN]++;
                if (`D.pc[4:2] == 3'b111) ctr[FE2_CROSS_LINE]++;
            end
            if (`LB.bypass)   ctr[LB_BYPASS]++;
            if (`D.if_stage_i.i_request) begin
                automatic logic [26:0] ln = `D.if_stage_i.pc_next[31:5];
                automatic bit seq = 0, l2, l4;
                if (`D.flush || `D.if_stage_i.flushlatch) ctr[FE_LINE_REDIRECT]++;
                else if (`D.if_stage_i.br_signal) ctr[FE_LINE_TAKEN]++;
                else begin ctr[FE_LINE_SEQ]++; seq = 1; end
                l2 = ln == fe_lines[1];
                l4 = ln inside {fe_lines[1], fe_lines[2], fe_lines[3]};
                if (l2) ctr[FE_LINE_IN_LAST2]++;
                if (l4) ctr[FE_LINE_IN_LAST4]++;
                if (seq || l4) ctr[FE_LINE_SEQ_OR_LAST4]++;
            end

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
            // one reason per cycle
            begin
                automatic bit v1 = `D.id_dis_reg_1.i_valid, v2 = `D.id_dis_reg_2.i_valid;
                automatic bit rs_alu = (`D.dispatch_ready_ALU_1 && `D.RS_ALU_full_1) || (`D.dispatch_ready_ALU_2 && `D.RS_ALU_full_2);
                automatic bit rs_mul = (`D.dispatch_ready_MUL_1 && `D.RS_MUL_full_1) || (`D.dispatch_ready_MUL_2 && `D.RS_MUL_full_2);
                automatic bit rs_div = (`D.dispatch_ready_DIV_1 && `D.RS_DIV_full_1) || (`D.dispatch_ready_DIV_2 && `D.RS_DIV_full_2);
                automatic bit rs_lui = (`D.dispatch_ready_LUI_1 && `D.RS_LUI_full_1) || (`D.dispatch_ready_LUI_2 && `D.RS_LUI_full_2);
                automatic bit rs_mem = (`D.dispatch_ready_MEM_1 && `D.RS_MEM_full_1) || (`D.dispatch_ready_MEM_2 && `D.RS_MEM_full_2);
                automatic bit rs_br  = (`D.dispatch_ready_BR_1  && `D.RS_BR_full_1)  || (`D.dispatch_ready_BR_2  && `D.RS_BR_full_2);
                automatic bit robf = `D.rob_full_1 || (v2 && `D.rob_full_2);
                automatic bit prff = `D.PRF_full || (v2 && `D.PRF_almost_full);
                if (n_disp == 2) ctr[DS_2]++;
                else if (n_disp == 1) ctr[DS_1]++;
                else if (!v1 && !v2) ctr[in_recovery || `D.flush ? DS_EMPTY_RECOVERY : DS_EMPTY_FRONTEND]++;
                else if (`D.dispatch_stall && (robf || prff)) begin
                    automatic logic [31:0] hi = disp_inst[`D.ROB_i.head[ROBADDR_L-1:0]];
                    automatic logic [ROBADDR_L-1:0] hh = `D.ROB_i.head[ROBADDR_L-1:0];
                    ctr[robf ? DS_ROB_FULL : DS_PRF_FULL]++;
                    if (on_cdb(hh)) ctr[WF_HEAD_ON_CDB]++;
                    if (is_muldiv(hi)) begin
                        automatic ctr_e w = locate_muldiv(hh);
                        if (w inside {HM_RS_UNIT_BUSY, HM_INREG_UNIT_BUSY}) ctr[WF_HEAD_MUL_UNIT_WAIT]++;
                        else if (w inside {HM_EXECUTING, HM_CDB_BLOCKED, HM_ON_CDB}) ctr[WF_HEAD_MUL_EXEC]++;
                        else ctr[WF_HEAD_MUL_OTHER]++;
                    end
                    else if (op(hi) == 7'b0000011) ctr[WF_HEAD_LOAD]++;
                    else if (op(hi) == 7'b0100011) ctr[WF_HEAD_STORE]++;
                    else if (op(hi) inside {7'b1100011, 7'b1101111, 7'b1100111}) ctr[WF_HEAD_BRANCH]++;
                    else ctr[WF_HEAD_ALU]++;
                end
                else if (`D.dispatch_stall && (rs_alu || rs_mul || rs_div || rs_lui || rs_mem || rs_br)) begin
                    automatic int n = 0, w = 0, t = 0;
                    if (rs_alu) begin
                        ctr[DS_RS_ALU]++;
                        for (int i = 0; i < 16; i++) begin
                            if (`D.dispatch_ready_ALU_1 && `D.RS_ALU_full_1)
                                tally(`D.res_station_ALU1.RS_entry[i], `D.res_station_ALU1.entry_valid[i], n, w, t);
                            if (`D.dispatch_ready_ALU_2 && `D.RS_ALU_full_2)
                                tally(`D.res_station_ALU2.RS_entry[i], `D.res_station_ALU2.entry_valid[i], n, w, t);
                        end
                    end
                    else if (rs_mem) begin
                        ctr[DS_RS_MEM]++;
                        for (int i = 0; i < 8; i++)
                            tally(`D.res_station_MEM.RS_entry[i], `D.res_station_MEM.entry_valid[i], n, w, t);
                    end
                    else if (rs_br) begin
                        ctr[DS_RS_BR]++;
                        for (int i = 0; i < 8; i++) tally(`D.res_station_BR.RS_entry[i], `D.res_station_BR.entry_valid[i], n, w, t);
                    end
                    else if (rs_mul) begin
                        ctr[DS_RS_MUL]++;
                        for (int i = 0; i < 8; i++) tally(`D.res_station_MUL.RS_entry[i], `D.res_station_MUL.entry_valid[i], n, w, t);
                    end
                    else if (rs_div) begin
                        ctr[DS_RS_DIV]++;
                        for (int i = 0; i < 8; i++) tally(`D.res_station_DIV.RS_entry[i], `D.res_station_DIV.entry_valid[i], n, w, t);
                    end
                    else begin
                        ctr[DS_RS_LUI]++;
                        for (int i = 0; i < 8; i++) tally(`D.res_station_LUI.RS_entry[i], `D.res_station_LUI.entry_valid[i], n, w, t);
                    end
                    ctr[RSF_ENTRIES] += n; ctr[RSF_WAITING] += w; ctr[RSF_WAIT_MULCHAIN] += t;
                    if (t != 0) ctr[RSF_CYC_ANY_MULCHAIN]++;
                end
                else if (`D.decode_stall) ctr[DS_DECODE_STALL]++;
                else ctr[DS_OTHER]++;
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

            // ---- MUL / DIV stations and units -------------------------------------------------
            begin
                automatic int n_m = 0, r_m = 0, w_m = 0, n_d = 0, r_d = 0, w_d = 0;
                for (int i = 0; i < 8; i++) begin
                    if (`D.res_station_MUL.entry_valid[i]) begin
                        n_m++; if (`RS2_RDY(res_station_MUL, i)) r_m++; else w_m++;
                    end
                    if (`D.res_station_DIV.entry_valid[i]) begin
                        n_d++; if (`RS2_RDY(res_station_DIV, i)) r_d++; else w_d++;
                    end
                end
                ctr[MUL_RS_OCC_SUM] += n_m; ctr[DIV_RS_OCC_SUM] += n_d;
                if (n_m > ctr[MUL_RS_MAX]) ctr[MUL_RS_MAX] = n_m;
                if (n_d > ctr[DIV_RS_MAX]) ctr[DIV_RS_MAX] = n_d;
                if (n_m == 8) ctr[MUL_RS_FULL]++;
                if (n_d == 8) ctr[DIV_RS_FULL]++;
                ctr[MUL_OPND_WAIT_OPS] += w_m; ctr[DIV_OPND_WAIT_OPS] += w_d;
                for (int k = 0; k < $size(`D.func_mul_i.slot_busy); k++)
                    if (`D.func_mul_i.slot_busy[k]) ctr[MUL_UNITS_BUSY_SUM]++;
                if (`D.func_mul_i.busy) begin           // no multiplier free
                    automatic int q = r_m + int'(`D.RS_mul_out_valid);
                    ctr[MUL_UNIT_BUSY_CYC]++;
                    if (q != 0) begin ctr[MUL_UNIT_WAIT_CYC]++; ctr[MUL_UNIT_WAIT_OPS] += q; end
                    if (`D.func_mul_i.mul_complete && !`D.mul_cdb_rdy) ctr[MUL_DONE_CDB_WAIT]++;
                end
                if (`D.func_div_i.busy) begin
                    automatic int q = r_d + int'(`D.RS_div_out_valid);
                    ctr[DIV_UNIT_BUSY_CYC]++;
                    if (q != 0) begin ctr[DIV_UNIT_WAIT_CYC]++; ctr[DIV_UNIT_WAIT_OPS] += q; end
                    if (`D.func_div_i.div_complete && !`D.div_cdb_rdy) ctr[DIV_DONE_CDB_WAIT]++;
                end
                if (`D.func_mul_i.mul_en) ctr[MUL_STARTS]++;
                if (`D.func_div_i.div_en) ctr[DIV_STARTS]++;
            end

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
            // pcache states: 0 RUN, 1 SWAP, 2 EVICT, 3 FILL
            if (`D.i_cache.accept) ctr[ICACHE_ACCESS]++;
            if (`D.i_cache.b_miss) begin
                ctr[ICACHE_MISS]++;
                if (`D.i_cache.vc_hit) ctr[ICACHE_VC_HIT]++;
            end
            if (int'(`D.i_cache.state) == 3 && `D.i_cache.dfp_resp) ctr[ICACHE_DRAM_FILL]++;
            if (int'(`D.i_cache.state) != 0) ctr[ICACHE_BUSY]++;
            if (`D.d_cache.accept) ctr[DCACHE_ACCESS]++;
            if (`D.d_cache.b_miss) begin
                ctr[DCACHE_MISS]++;
                if (`D.d_cache.vc_hit) ctr[DCACHE_VC_HIT]++;
            end
            if (int'(`D.d_cache.state) == 3 && `D.d_cache.dfp_resp) ctr[DCACHE_DRAM_FILL]++;
            if (int'(`D.d_cache.state) == 2 && `D.d_cache.dfp_resp) ctr[DCACHE_WRITEBACK]++;
            if (int'(`D.d_cache.state) != 0) ctr[DCACHE_BUSY]++;

            // ---- commit accounting -----------------------------------------------------------
            n_commit = int'(`D.rvfi_entry_commit_1.valid) + int'(`D.rvfi_entry_commit_2.valid);
            ctr[COMMIT_0 + n_commit]++;
            if ((`D.id_dis_reg_1.i_valid || `D.id_dis_reg_2.i_valid) && `D.dispatch_stall &&
                (`D.rob_full_1 || (`D.id_dis_reg_2.i_valid && `D.rob_full_2) || `D.PRF_full ||
                 (`D.id_dis_reg_2.i_valid && `D.PRF_almost_full)))
                ctr[n_commit == 2 ? DS_WINFULL_C2 : (n_commit == 1 ? DS_WINFULL_C1 : DS_WINFULL_C0)]++;
            if (`D.rvfi_entry_commit_1.valid) ctr[COMMIT_LANE1]++;
            if (`D.rvfi_entry_commit_2.valid) ctr[COMMIT_LANE2]++;

            rob_head   = `D.ROB_i.head;
            rob_tail   = `D.ROB_i.tail;
            rob_head_i = rob_head[ROBADDR_L-1:0];
            rob_head_n = rob_head_i + 1'b1;
            rob_diff   = rob_tail - rob_head;                 // 6-bit pointers with wrap bit
            rob_count  = int'(rob_diff);
            head_inst  = disp_inst[rob_head_i];
            second_valid  = `D.ROB_i.rob_entry[rob_head_n].valid;
            second_status = `D.ROB_i.rob_entry[rob_head_n].status;
            second_type   = `D.ROB_i.rob_entry[rob_head_n].inst_type;

            begin
                automatic bit c0_oncdb = n_commit == 0 && !in_recovery && rob_count != 0 && on_cdb(rob_head_i);
                automatic bit disp_wants = `D.id_dis_reg_1.i_valid || `D.id_dis_reg_2.i_valid;
                automatic bit retire_full = `D.rob_full_1 || (`D.id_dis_reg_2.i_valid && `D.rob_full_2) ||
                                            `D.PRF_full || (`D.id_dis_reg_2.i_valid && `D.PRF_almost_full);
                if (c0_oncdb) ctr[C0_HEAD_ON_CDB]++;
                if (prev_c0_oncdb) ctr[CU_AFTER_ONCDB_0 + n_commit]++;
                prev_c0_oncdb = c0_oncdb;
                if (c0_oncdb && n_disp == 0 && disp_wants && retire_full) ctr[RETIRE_BLOCK_ONCDB]++;
            end
            if (n_commit == 0 && !in_recovery && rob_count != 0) begin
                automatic logic [31:0] old_inst = `D.ROB_i.rvfi_rob_entry[rob_head_i].inst;
                automatic bit old_alu = !(op(old_inst) inside {7'b0000011, 7'b0100011, 7'b1100011, 7'b1101111, 7'b1100111})
                                        && !is_muldiv(old_inst);
                if (old_inst == 32'd0)            ctr[XO_WORD_ZERO]++;
                else if (old_inst != head_inst)   ctr[XO_WORD_STALE]++;
                else                              ctr[XO_WORD_SAME]++;
                if (old_alu) begin
                    ctr[XO_ALU]++;
                    if (op(head_inst) == 7'b0000011)      ctr[XO_ALU_TRUE_LOAD]++;
                    else if (op(head_inst) == 7'b0100011) ctr[XO_ALU_TRUE_STORE]++;
                    else if (is_muldiv(head_inst))        ctr[XO_ALU_TRUE_MULDIV]++;
                    else if (op(head_inst) inside {7'b1100011, 7'b1101111, 7'b1100111}) ctr[XO_ALU_TRUE_BRANCH]++;
                    else                                  ctr[XO_ALU_TRUE_ALU]++;
                end
            end
            if (n_commit == 0 && !in_recovery && rob_count != 0 && op(head_inst) == 7'b0000011) begin
                for (int i = 0; i < $size(`D.load_queue_i.entry_valid); i++)
                    if (`D.load_queue_i.entry_valid[i] && `D.load_queue_i.load_entry[i].rob_addr == rob_head_i &&
                        `D.load_queue_i.load_entry[i].depend_idx == '0) begin
                        if (`D.mem_queue_out_controller_i.store_busy ||
                            (!`D.mem_queue_out_controller_i.mem_busy && `D.store_out_valid)) ctr[HL_LQ_PORT_STORE]++;
                        else if (`D.load_out_valid && `D.load_out_idx != i) ctr[HL_LQ_YOUNGER_SENT]++;
                    end
            end
            if (n_commit == 0) begin
                if (in_recovery)                ctr[C0_MISPREDICT_RECOVERY]++;
                else if (rob_count == 0)        ctr[C0_ROB_EMPTY]++;
                else if (op(head_inst) == 7'b0000011) begin ctr[C0_HEAD_LOAD]++; ctr[locate_load(rob_head_i)]++; end
                else if (op(head_inst) == 7'b0100011) ctr[C0_HEAD_STORE]++;
                else if (is_muldiv(head_inst))  begin ctr[C0_HEAD_MULDIV]++; ctr[locate_muldiv(rob_head_i)]++; end
                else if (op(head_inst) inside {7'b1100011, 7'b1101111, 7'b1100111}) begin
                    ctr[C0_HEAD_BRANCH]++; ctr[locate_branch(rob_head_i)]++;
                end
                else begin
                    automatic longint age = cyc - disp_cyc[rob_head_i];
                    ctr[C0_HEAD_ALU]++;
                    if (op(head_inst) inside {7'b0110111, 7'b0010111}) ctr[HA_LUI_UNIT]++;
                    else begin
                        automatic ctr_e w = locate_alu(rob_head_i);
                        ctr[w]++;
                    end
                    if      (age <= 1)  ctr[HA_AGE_1]++;
                    else if (age == 2)  ctr[HA_AGE_2]++;
                    else if (age == 3)  ctr[HA_AGE_3]++;
                    else if (age == 4)  ctr[HA_AGE_4]++;
                    else if (age <= 8)  ctr[HA_AGE_5_8]++;
                    else if (age <= 16) ctr[HA_AGE_9_16]++;
                    else                ctr[HA_AGE_17P]++;
                end
            end else if (n_commit == 1) begin
                if (!`D.flush && rob_count >= 2 && second_valid && second_status && second_type != 3'd0) begin
                    ctr[C1_LANE2_RULE]++;
                    if (second_type == 3'd3) ctr[C1_LANE2_RULE_STORE]++;
                    else if (second_type == 3'd1) ctr[C1_LANE2_RULE_BRANCH]++;
                    else ctr[C1_LANE2_RULE_JUMP]++;
                    if (`D.dispatch_stall && (`D.rob_full_1 || (`D.id_dis_reg_2.i_valid && `D.rob_full_2) ||
                                              `D.PRF_full || (`D.id_dis_reg_2.i_valid && `D.PRF_almost_full)))
                        ctr[C1_LANE2_RULE_WINFULL]++;
                end
                if (`D.flush)                   ctr[C1_MISPREDICT]++;
                else if (rob_count < 2)         ctr[C1_ONLY_ONE_IN_ROB]++;
                else if (second_type != 3'd0)   ctr[C1_SECOND_NOT_SIMPLE]++;   // branch/jump/store
                else if (!second_status)        ctr[C1_SECOND_NOT_DONE]++;
                else                            ctr[C1_OTHER]++;
            end

            // ---- control flow (commit side, both lanes) ---------------------------------------
            if (`D.flush) begin
                ctr[FLUSHES]++;
                ctr[MP_RESOLVE_TO_COMMIT] += cyc - done_cyc[rob_head_i];
                if (cyc - done_cyc[rob_head_i] <= 1) ctr[MP_RESOLVED_AT_HEAD]++;
            end
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

        // dispatch cycle of each ROB entry written at this edge (lane 2 alone goes to the tail)
        if (`D.rob_enq_1) begin
            disp_cyc [`D.rob_addr_1] = cyc;
            disp_inst[`D.rob_addr_1] = `D.rvfi_entry_dispatch_1.inst;
        end
        if (`D.rob_enq_2) begin
            disp_cyc [`D.rob_enq_1 ? `D.rob_addr_2 : `D.rob_addr_1] = cyc;
            disp_inst[`D.rob_enq_1 ? `D.rob_addr_2 : `D.rob_addr_1] = `D.rvfi_entry_dispatch_2.inst;
        end

        // most recent distinct lines in the line buffer (fe_lines[0] = current)
        if (`D.if_stage_i.i_request) begin
            automatic logic [26:0] ln = `D.if_stage_i.pc_next[31:5];
            automatic int k = 3;
            for (int i = 1; i < 4; i++) if (fe_lines[i] == ln && k == 3) k = i;
            for (int i = k; i > 0; i--) fe_lines[i] = fe_lines[i-1];
            fe_lines[0] = ln;
        end

        // MUL/DIV chain: a dispatched op's result is on the chain if it is a MUL/DIV, or if an
        // operand that is not ready at dispatch is on the chain (lane 1 first: lane 2 may read it)
        for (int l = 0; l < 2; l++) begin
            automatic bit en = (l == 0) ? `D.rob_enq_1 : `D.rob_enq_2;
            automatic RS_entry_t e = (l == 0) ? `D.dp_stage_1.dp_rs_reg_next : `D.dp_stage_2.dp_rs_reg_next;
            automatic logic [31:0] inst = (l == 0) ? `D.rvfi_entry_dispatch_1.inst : `D.rvfi_entry_dispatch_2.inst;
            if (en) begin
                automatic bit w1 = e.rs1_use && !e.rs1_valid, w2 = e.rs2_use && !e.rs2_valid;
                automatic bit c  = (w1 && mchain[e.rs1_paddr]) || (w2 && mchain[e.rs2_paddr]);
                if (!frozen) begin
                    if (w1 || w2) ctr[OPND_NOT_READY]++;
                    if (c)        ctr[OPND_MULCHAIN]++;
                end
                if (e.regf_we) mchain[e.rd_paddr] = is_muldiv(inst) || c;
            end
        end

        if (`D.cdb_main_1.valid) done_cyc[`D.cdb_main_1.rob_addr] = cyc;
        if (`D.cdb_main_2.valid) done_cyc[`D.cdb_main_2.rob_addr] = cyc;
        cyc++;

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
`undef LB
