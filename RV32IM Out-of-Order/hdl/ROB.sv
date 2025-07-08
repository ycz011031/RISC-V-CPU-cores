module ROB
import rv32i_types::*;
#(
    parameter ROBADDR_L = 3
)(
    input   logic      clk,
    input   logic      rst,
    input   logic      flush,

    input disp_rob_t   disp_rob_1,
    input disp_rob_t   disp_rob_2,
    input CDB_t        cdb1,
    input CDB_t        cdb2,

    input  logic       enq1,
    input  logic       enq2,
    output logic       deq1,
    output logic       deq2,

    output logic [ROBADDR_L-1:0]  rob_addr_1,
    output logic [ROBADDR_L-1:0]  rob_addr_2,

    output logic                   full,
    output logic                   almost_full,
    output logic                   empty,
    output logic                   almost_empty,

    input  logic store_all_commited,
    output logic store_commit,

    output rob_entry_t rob_out_1,
    output rob_entry_t rob_out_2,

    output logic    error,

    input  rvfi_entry  rvfi_entry_cdb_reg_1,
    input  rvfi_entry  rvfi_entry_cdb_reg_2,
    output  rvfi_entry  rvfi_entry_commit_1,
    output  rvfi_entry  rvfi_entry_commit_2

);
// TODO add two way enq1ue, do not need to care about empty, no one is using it
// TODO need full and almost full, information coming from channel 1 is always older
localparam                  ROB_SIZE = 2**ROBADDR_L;

rvfi_entry rvfi_rob_entry [ROB_SIZE];
rob_entry_t rob_entry [ROB_SIZE];
logic   [ROBADDR_L:0]         head, tail; 
logic   [ROBADDR_L:0]         head_next, tail_next; 

assign head_next = head + 1'b1;
assign tail_next = tail + 1'b1;

assign rob_addr_1 = tail[ROBADDR_L-1:0];
assign rob_addr_2 = tail_next[ROBADDR_L-1:0];

always_ff @( posedge clk ) begin : rob_update

    if (rst || flush) begin
        head <= '0;
        tail <= '0;
        for (integer i = 0; i < ROB_SIZE; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
            rob_entry[i] <= '0;
            rvfi_rob_entry[i] <= '0;
        end
    end else begin
        error <= '0;
            case ({enq1, enq2, deq1, deq2})  
                4'b1000: begin  //channel 1 enq
                    if (!full) begin
                        rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                        rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                        rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                        rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                        rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                        rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;

                        tail <= tail + 1'b1; 
                    end
                end
                4'b0100: begin  //channel 2 enq
                    error <= '1;
                end
                4'b0010: begin  //one deq
                    rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                    if (!empty) begin 
                        head <= head + 2'd1;
                    end
                end
                4'b1100: begin  // both channel enq
                    if (!full) begin
                        if (!almost_full) begin
                            rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                            rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                            rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                            rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                            rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                            rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;

                            rob_entry[tail_next[ROBADDR_L-1:0]].valid <= '1;
                            rob_entry[tail_next[ROBADDR_L-1:0]].status <= '0;

                            rob_entry[tail_next[ROBADDR_L-1:0]].inst_type <= disp_rob_2.inst_type;
                            rob_entry[tail_next[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_2.rd_aaddr;
                            rob_entry[tail_next[ROBADDR_L-1:0]].rd_paddr <= disp_rob_2.rd_paddr;
                            rob_entry[tail_next[ROBADDR_L-1:0]].br_mispred <= '0;
                            tail <= tail + 2'd2; 
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1010: begin  //channel 1 enq and one deq
                    rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                    rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;
                    tail <= tail + 2'd1;

                    if (!empty) begin
                        rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                        head <= head + 2'd1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b0110: begin  //channel 2 enq and one deq
                    rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_2.inst_type;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_2.rd_aaddr;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_2.rd_paddr;
                    rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;
                    tail <= tail + 2'd1;

                    if (!empty) begin
                        rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                        head <= head + 2'd1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b0011: begin  // both channel deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                            rob_entry[head_next[ROBADDR_L-1:0]].valid <= '0;
                            head <= head + 2'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1011: begin  // channel 1 enq and both channel deq
                    rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                    rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;
                    tail <= tail + 2'd1;
                    if (!empty) begin
                        if (!almost_empty) begin
                            rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                            rob_entry[head_next[ROBADDR_L-1:0]].valid <= '0;
                            head <= head + 2'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b0111: begin  // channel 2 enq and both channel deq
                    rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_2.inst_type;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_2.rd_aaddr;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_2.rd_paddr;
                    rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;
                    tail <= tail + 2'd1;
                    if (!empty) begin
                        if (!almost_empty) begin
                            rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                            rob_entry[head_next[ROBADDR_L-1:0]].valid <= '0;
                            head <= head + 2'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1110: begin  // both channel enq and one deq
                    if (!empty) begin
                        rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                        head <= head + 2'd1;
                    end else begin
                        error <= '1;
                    end
                    if (!full) begin
                        rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                        rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                        rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                        rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                        rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                        rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;

                        rob_entry[tail_next[ROBADDR_L-1:0]].valid <= '1;
                        rob_entry[tail_next[ROBADDR_L-1:0]].status <= '0;

                        rob_entry[tail_next[ROBADDR_L-1:0]].inst_type <= disp_rob_2.inst_type;
                        rob_entry[tail_next[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_2.rd_aaddr;
                        rob_entry[tail_next[ROBADDR_L-1:0]].rd_paddr <= disp_rob_2.rd_paddr;
                        rob_entry[tail_next[ROBADDR_L-1:0]].br_mispred <= '0;
                        tail <= tail + 2'd2; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b1111: begin  // both channel enq and both channel deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            rob_entry[head[ROBADDR_L-1:0]].valid <= '0;
                            rob_entry[head_next[ROBADDR_L-1:0]].valid <= '0;
                            head <= head + 2'd2;
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                    rob_entry[tail[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail[ROBADDR_L-1:0]].inst_type <= disp_rob_1.inst_type;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_1.rd_aaddr;
                    rob_entry[tail[ROBADDR_L-1:0]].rd_paddr <= disp_rob_1.rd_paddr;
                    rob_entry[tail[ROBADDR_L-1:0]].br_mispred <= '0;

                    rob_entry[tail_next[ROBADDR_L-1:0]].valid <= '1;
                    rob_entry[tail_next[ROBADDR_L-1:0]].status <= '0;

                    rob_entry[tail_next[ROBADDR_L-1:0]].inst_type <= disp_rob_2.inst_type;
                    rob_entry[tail_next[ROBADDR_L-1:0]].rd_aaddr <= disp_rob_2.rd_aaddr;
                    rob_entry[tail_next[ROBADDR_L-1:0]].rd_paddr <= disp_rob_2.rd_paddr;
                    rob_entry[tail_next[ROBADDR_L-1:0]].br_mispred <= '0;
                    tail <= tail + 2'd2; 
                end
                default: ;
            endcase

        if (cdb1.valid && !empty) begin
            rob_entry[cdb1.rob_addr].status     <= '1;
            rob_entry[cdb1.rob_addr].br_mispred <= cdb1.br_mispred;
            rvfi_rob_entry[cdb1.rob_addr]       <= rvfi_entry_cdb_reg_1;
        end

        if (cdb2.valid && !empty) begin
            rob_entry[cdb2.rob_addr].status     <= '1;
            rob_entry[cdb2.rob_addr].br_mispred <= cdb2.br_mispred;
            rvfi_rob_entry[cdb2.rob_addr]       <= rvfi_entry_cdb_reg_2;
        end
    end
end


always_comb begin
    
    full = (head[ROBADDR_L] != tail[ROBADDR_L]) && (head[ROBADDR_L-1:0] == tail[ROBADDR_L-1:0]);
    almost_full = (head[ROBADDR_L] != tail_next[ROBADDR_L]) && (head[ROBADDR_L-1:0] == tail_next[ROBADDR_L-1:0]) || full;
    empty = head == tail;
    almost_empty = head_next == tail || empty;

    // TODO: handle store flush in memory queue

    deq1  = rob_entry[head[ROBADDR_L-1:0]].valid && rob_entry[head[ROBADDR_L-1:0]].status && head != tail && !(rob_entry[head[ROBADDR_L-1:0]].inst_type == 3'd3 && store_all_commited);
    deq2 = deq1 && rob_entry[(head_next[ROBADDR_L-1:0])].valid && rob_entry[(head_next[ROBADDR_L-1:0])].status && head != tail && (rob_entry[(head_next[ROBADDR_L-1:0])].inst_type == 3'd0);
    // Commit when (1) entry is valid (2) entry is done (3) ROB is not empty (4) Need to commit store but memory store have not finished
    rob_out_1 = deq1 ? rob_entry[head[ROBADDR_L-1:0]]:'0;
    rob_out_2 = deq2 ? rob_entry[(head_next[ROBADDR_L-1:0])]:'0;
    rob_out_2.valid = deq2 ? !rob_out_1.br_mispred : '0;

    store_commit = deq1 & rob_entry[head[ROBADDR_L-1:0]].inst_type == 3'd3;
    // store_en = rob_entry[head[ROBADDR_L-1:0]].valid && rob_entry[head[ROBADDR_L-1:0]].status && rob_entry[head[ROBADDR_L-1:0]].inst_type == 3'd3;    //Start store operation

    rvfi_entry_commit_1       = deq1? rvfi_rob_entry[head[ROBADDR_L-1:0]] : '0;
    rvfi_entry_commit_1.valid = deq1;
    rvfi_entry_commit_2       = deq2? rvfi_rob_entry[(head_next[ROBADDR_L-1:0])] : '0;
    rvfi_entry_commit_2.valid = deq2? !rob_out_1.br_mispred : '0;

end




endmodule: ROB