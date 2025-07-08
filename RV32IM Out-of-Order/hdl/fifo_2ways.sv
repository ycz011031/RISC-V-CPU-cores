module fifo_2ways #(
            parameter               DEPTH     = 8,
            parameter               WIDTH     = 8
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   enq1,
    input   logic                   enq2,

    input   logic                   deq1,
    input   logic                   deq2,

    input   logic   [WIDTH-1:0]     din1,
    input   logic   [WIDTH-1:0]     din2,

    output  logic   [WIDTH-1:0]     dout1,
    output  logic   [WIDTH-1:0]     dout2,

    output  logic                   full,
    output  logic                   almost_full,
    output  logic                   empty,
    output  logic                   almost_empty,

    output  logic                   error
);

    localparam                  Q_INDEX = $clog2(DEPTH);

    logic   [Q_INDEX:0]         head, tail;
    logic   [Q_INDEX:0]         head_next, tail_next;
    logic   [WIDTH-1:0]         internal_array  [DEPTH];

    assign head_next = head + 1'b1;
    assign tail_next = tail + 1'b1;

    always_ff @( posedge clk ) begin : fifo_update
        if (rst) begin
            head <= '0;
            tail <= '0;
            error <= '0;
            for (integer i = 0; i < DEPTH; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i] <= '0;
            end
        end else begin
            error <= '0;
            case ({enq1, enq2, deq1, deq2})  
                4'b1000: begin  //channel 1 enq
                    if (!full) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din1;
                        tail <= tail + 'd1; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b0100: begin  //channel 2 enq
                    if (!full) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din2;
                        tail <= tail + 'd1; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b0010, 4'b0001: begin  //channel 1 deq
                    if (!empty) begin
                        head <= head + 'd1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b1100: begin  // both channel enq
                    if (!full) begin
                        if (!almost_full) begin
                            internal_array[tail[Q_INDEX-1:0]] <= din1;
                            internal_array[tail_next[Q_INDEX-1:0]] <= din2;
                            tail <= tail + 'd2; 
                        end else begin
                            // internal_array[tail[Q_INDEX-1:0]] <= din1;
                            // tail <= tail + 1; 
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1010, 4'b1001: begin  //channel 1 enq and one deq
                    internal_array[tail[Q_INDEX-1:0]] <= din1;
                    tail <= tail + 'd1;
                    if (!empty) begin
                        head <= head + 'd1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b0110, 4'b0101: begin  //channel 2 enq and one deq
                    internal_array[tail[Q_INDEX-1:0]] <= din2;
                    tail <= tail + 'd1;
                    if (!empty) begin
                        head <= head + 'd1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b0011: begin  // both channel deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1011: begin  // channel 1 enq and both channel deq
                    internal_array[tail[Q_INDEX-1:0]] <= din1;
                    tail <= tail + 'd1;
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b0111: begin  // channel 2 enq and both channel deq
                    internal_array[tail[Q_INDEX-1:0]] <= din2;
                    tail <= tail + 'd1;
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 'd2;
                        end else begin
                            // head <= head + 1;
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1110, 4'b1101: begin  // both channel enq and one deq
                    if (!empty) begin
                        head <= head + 'd1;
                    end else begin
                        error <= '1;
                    end
                    if (!full) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din1;
                        internal_array[tail_next[Q_INDEX-1:0]] <= din2;
                        tail <= tail + 'd2; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b1111: begin  // both channel enq and both channel deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 'd2;
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                    internal_array[tail[Q_INDEX-1:0]] <= din1;
                    internal_array[tail_next[Q_INDEX-1:0]] <= din2;
                    tail <= tail + 'd2; 
                end
                default: ;
            endcase
        end

    end


    always_comb begin
        case ({deq1, deq2})
            2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                dout1 = (empty) ? '0 : internal_array[head[Q_INDEX-1:0]];
                dout2 = (empty || almost_empty) ? '0 : internal_array[head_next[Q_INDEX-1:0]];
            end
            2'b10: begin  //only enq
                dout2 = '0;
                dout1 = (empty) ? '0 : internal_array[head[Q_INDEX-1:0]];
            end
            2'b01: begin  // only deq
                dout1 = '0;
                dout2 = (empty) ? '0 : internal_array[head[Q_INDEX-1:0]];
            end
            default: begin
                dout1 = '0;
                dout2 = '0;
            end
        endcase
        // dout1 = (empty) ? '0 : internal_array[head[Q_INDEX-1:0]];
        // dout2 = (empty || almost_empty) ? '0 : internal_array[head_next[Q_INDEX-1:0]];

        full = (head[Q_INDEX] != tail[Q_INDEX]) && (head[Q_INDEX-1:0] == tail[Q_INDEX-1:0]);
        almost_full = (head[Q_INDEX] != tail_next[Q_INDEX]) && (head[Q_INDEX-1:0] == tail_next[Q_INDEX-1:0]);

        empty = head == tail;
        almost_empty = head_next == tail;
    end

endmodule : fifo_2ways