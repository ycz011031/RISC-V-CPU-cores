module gshare
import rv32i_types::*;
#(
        parameter PHT_ADDR_L = 8
)
(   input   logic   clk,
    input   logic   rst,
    // input   logic   [31:0] pc,
    
    input  logic   [31:0] pc_next,
    input  logic   [PHT_ADDR_L-1:0] pc_next_idx2,   // (pc_next + 4)[PHT_ADDR_L+1:2], precomputed by fetch
    input logic fetch_stall,

    input logic flush,              // mispredict recovered at commit
    input logic flush_flip,         // ... by a conditional branch: its history bit was wrong
    // input logic br_mispred_actual,
    input logic update_pht,
    input logic update_ghr,
    output logic br_pred,
    output logic br_pred2,                      // prediction for the second fetch slot (pc + 4)
    input  logic use_slot2,                     // this group's branch is in slot 2: shift br_pred2 into the history
    output logic     [31:0]  jalr_target_pred,
    output logic [PHT_ADDR_L-1:0] curr_ghr,     // history including this fetch's branch prediction
    output logic [PHT_ADDR_L-1:0] ghr_out,      // history before it (checkpoint for a jalr)
    output logic [PHT_ADDR_L-1:0]  pht_read_addr_last,
    output logic [1:0]          count_last,
    output logic [PHT_ADDR_L-1:0]  pht_read_addr_last2,
    output logic [1:0]          count_last2,

    input logic [PHT_ADDR_L-1:0]  pht_write_addr,

    // input logic commit,
    input logic [PHT_ADDR_L-1:0] commit_ghr,
    input logic [1:0] commit_count

);
logic dum;
assign dum = update_ghr;

    localparam PHT_DEPTH = 2**PHT_ADDR_L;

    logic [PHT_DEPTH-1:0] init_checker;

    logic [PHT_ADDR_L-1:0]  ghr, pht_read_addr, pht_write_addr_reg, pht_read_addr_reg;
    logic [31:0] target_addr;
    logic [1:0] dummy_out;

    logic [1:0] count, count_next, pht_out;
    // slot 2 reads a second copy of the table (same writes, so the same contents)
    logic [PHT_ADDR_L-1:0] pht_read_addr2, pht_read_addr_reg2;
    logic [1:0] count2, pht_out2, dummy_out2;
    logic one_wait;

    assign pht_read_addr = ghr ^ pc_next[PHT_ADDR_L+1:2];
    assign pht_read_addr_last = pht_read_addr_reg;    //ghr ^ pc[PHT_ADDR_L+1:2];
    assign pht_read_addr2 = ghr ^ pc_next_idx2;                       // index of pc_next + 4
    assign pht_read_addr_last2 = pht_read_addr_reg2;
    assign count_last2 = count2;

    assign target_addr ='0;
    assign curr_ghr = {ghr[PHT_ADDR_L-2:0], use_slot2 ? br_pred2 : br_pred};     // shift in the prediction
    assign ghr_out  = ghr;

    assign count_last = count;

    always_ff @(posedge clk) begin
        if (rst) begin
            ghr <= '0;
            // pht_addr_reg <= '0;
        end else if (flush) begin
            // checkpoint of the mispredicting instruction: a branch's own bit
            // (LSB) was mispredicted; a jalr's checkpoint has no bit of its own
            ghr <= commit_ghr ^ PHT_ADDR_L'(flush_flip);
            // pht_addr_reg <= pht_addr;
        end else if (!(fetch_stall) && update_ghr) begin
            ghr <= curr_ghr;
            // pht_addr_reg <= pht_addr;
        end
        pht_read_addr_reg <= rst? '0 : pht_read_addr;
        pht_read_addr_reg2 <= rst? '0 : pht_read_addr2;

        if (rst) begin
            init_checker <= '0;
            one_wait<= '0;
            pht_write_addr_reg <= '0;
        end else if (update_pht) begin
            one_wait <= '1;
            pht_write_addr_reg <= pht_write_addr;
        end else if (one_wait) begin
            init_checker[pht_write_addr_reg] <= '1;
            one_wait <= '0;
        end
    end

    logic [1:0] write_count;

    always_comb begin

        if (init_checker[pht_read_addr_reg]) begin // && update_ghr to avoid x
            count = pht_out;
        end else begin
            count = wt;
        end
        count2 = init_checker[pht_read_addr_reg2] ? pht_out2 : wt;

        if (init_checker[pht_write_addr]) begin // && update_ghr to avoid x
            write_count = dummy_out;
        end else begin
            write_count = wt;
        end

        br_pred = count[1];
        br_pred2 = count2[1];
        jalr_target_pred = target_addr;

        unique case (commit_count)
            snt: begin
                if (flush) count_next = wnt;
                else count_next = commit_count;
            end
            wnt: begin
                if (flush) count_next = wt;
                else count_next = snt;
            end
            wt: begin
                if (flush) count_next = wnt;
                else count_next = st;
            end
            st: begin
                if (flush) count_next = wt;
                else count_next = commit_count;
            end
            default: count_next = commit_count;
        endcase
            
    end

    gshare_array
`ifdef OOO_PHT_BITS
        #(.ADDR_WIDTH(PHT_ADDR_L))          // simulation experiment: resized model
`endif
        pht_array (
        //read
        .clk0       (clk),
        .csb0       (1'b0),
        .web0       (1'b1), //read only
        // .wmask0     (1'b1),
        .addr0      (pht_read_addr),
        .din0       (count_next),
        .dout0      (pht_out),

        
        //write
        .clk1       (clk),
        .csb1       (1'b0),
        .web1       (~update_pht),
        // .wmask1     (1'b1),
        .addr1      (pht_write_addr),
        .din1       (count_next),
        .dout1      (dummy_out)
    );

    // copy read by the second fetch slot
        gshare_array
`ifdef OOO_PHT_BITS
        #(.ADDR_WIDTH(PHT_ADDR_L))          // simulation experiment: resized model
`endif
        pht_array2 (
        //read
        .clk0       (clk),
        .csb0       (1'b0),
        .web0       (1'b1), //read only
        // .wmask0     (1'b1),
        .addr0      (pht_read_addr2),
        .din0       (count_next),
        .dout0      (pht_out2),

        
        //write
        .clk1       (clk),
        .csb1       (1'b0),
        .web1       (~update_pht),
        // .wmask1     (1'b1),
        .addr1      (pht_write_addr),
        .din1       (count_next),
        .dout1      (dummy_out2)
    );

endmodule: gshare