module gshare
import rv32i_types::*;
#(
        parameter PHT_ADDR_L = 8
)
(   input   logic   clk,
    input   logic   rst,
    // input   logic   [31:0] pc,
    
    input  logic   [31:0] pc_next,
    input logic fetch_stall,

    input logic flush,
    // input logic br_mispred_actual,
    input logic update_pht,
    input logic update_ghr,
    output logic br_pred,
    output logic     [31:0]  jalr_target_pred,
    output logic [PHT_ADDR_L-1:0] curr_ghr,
    output logic [PHT_ADDR_L-1:0]  pht_read_addr_last,
    output logic [1:0]          count_last,

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
    logic one_wait;

    assign pht_read_addr = ghr ^ pc_next[PHT_ADDR_L+1:2];
    assign pht_read_addr_last = pht_read_addr_reg;    //ghr ^ pc[PHT_ADDR_L+1:2];

    assign target_addr ='0;
    assign curr_ghr = {ghr[PHT_ADDR_L-2:1], br_pred};

    assign count_last = count;

    always_ff @(posedge clk) begin
        if (rst) begin
            ghr <= '0;
            // pht_addr_reg <= '0;
        end else if (flush) begin
            ghr <= commit_ghr ^ PHT_ADDR_L'(1'b1); //flip LSB cuz it was mispred
            // pht_addr_reg <= pht_addr;
        end else if (!(fetch_stall) && update_ghr) begin
            ghr <= curr_ghr;
            // pht_addr_reg <= pht_addr;
        end
        pht_read_addr_reg <= rst? '0 : pht_read_addr;

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

        if (init_checker[pht_write_addr]) begin // && update_ghr to avoid x
            write_count = dummy_out;
        end else begin
            write_count = wt;
        end

        br_pred = count[1];
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

    gshare_array pht_array (
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

endmodule: gshare